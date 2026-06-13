extends Node
## Core game engine. Autoloaded as `GameState`.
## Single-active-task model with offline progress. Content from GameData (ported
## from horizonidle-godot): gather/craft/combat + a credit-funded research tree.

signal resources_changed
signal skills_changed
signal research_changed
signal action_changed
signal missions_changed
signal offline_ready          # emitted after a background-resume catch-up, for the UI modal
signal level_up(skill_id: String, level: int)        # skill leveled up — celebratory popup
signal feature_revealed(title: String, msg: String)  # late-game system reveal fanfare (desktop parity)
var _suppress_fx := false                            # mute transient juice during offline catch-up

# Missions (tutorial chain)
var missions_active: Dictionary = {}     # mid -> true
var missions_progress: Dictionary = {}   # mid -> count
var missions_claimed: Dictionary = {}    # mid -> true
var _mission_completed_seen: Dictionary = {}  # mid -> true (live-eval completion edge, UI-refresh only)

var resources: Dictionary = {}          # symbol -> int
var credits: int = 0                    # research currency (earned by selling)
var lifetime_credits: int = 0           # total credits ever earned (for prestige)
# Warp / prestige
var warp_shards: float = 0.0
var total_warps: int = 0
var credits_at_warp_start: int = 0
# v107 Warp Mastery Tree (ported from ref_warp_manager.gd ~L13-47). Earned
# warp_shards still drive the global multipliers; warp_shards_spent tracks tree
# purchases. Available = shards - spent. Purchased nodes persist ACROSS warps
# (true meta-progression — only hard_reset clears them).
const TREE_NODES := {
	# Engineering branch (revealed at warp #1) ---------------------------
	"E1": {"branch": "engineering", "cost": 1, "name": "Yield Calibration",
		"desc": "+10% Gathering yield.", "implemented": true},
	"E2": {"branch": "engineering", "cost": 2, "name": "Recipe Efficiency",
		"desc": "-10% Processing duration.", "implemented": true},
	"E3": {"branch": "engineering", "cost": 3, "name": "Alt-Recipe Slot",
		"desc": "Unlocks alt-recipe variants on chosen recipes.", "implemented": false},
	"E4": {"branch": "engineering", "cost": 5, "name": "Building Overclock",
		"desc": "Buildings can be throttled up to 200% at +50% input cost per unit produced.", "implemented": false},
	"E5": {"branch": "engineering", "cost": 8, "name": "Reclamation Foundry",
		"desc": "Unlocks a building that auto-converts surplus raw materials into Liras at a slow rate.", "implemented": false},
	# Combat branch (revealed at warp #2) --------------------------------
	"C1": {"branch": "combat", "cost": 1, "name": "Hull Reinforcement",
		"desc": "+10% Hull HP on all hulls.", "implemented": true},
	"C2": {"branch": "combat", "cost": 2, "name": "Weapon Tuning",
		"desc": "+10% module damage.", "implemented": true},
	"C3": {"branch": "combat", "cost": 3, "name": "Auxiliary Slot",
		"desc": "Unlocks a 9th module slot (Auxiliary type — accepts any module).", "implemented": false},
	"C4": {"branch": "combat", "cost": 5, "name": "Matrix Core Resonance",
		"desc": "Unlocks the 4th Matrix Core tier (Resonant) with stronger affixes.", "implemented": false},
	"C5": {"branch": "combat", "cost": 8, "name": "Cryo Overcharge",
		"desc": "+50% Cryo damage. (Cryo weapons unlock on your first Warp — this overcharges them.)", "implemented": true},
}
# Branch reveal derived from total_warps (no separate state).
const BRANCH_REVEAL_WARP := {"engineering": 1, "combat": 2}
# Ordered node chains per branch (prereq = the prior node in the branch).
const TREE_BRANCH_ORDER := {
	"engineering": ["E1", "E2", "E3", "E4", "E5"],
	"combat": ["C1", "C2", "C3", "C4", "C5"],
}
var purchased_nodes: Dictionary = {}  # {node_id: true} — persists across warps
var warp_shards_spent: float = 0.0    # cumulative spend; available = shards - spent
# v111: Warping permanently unlocks Cryogenic armaments — the key to the Z11
# "Warp-Hardened" gate. Persists across prestiges (set once on the first Warp).
var cryo_unlocked: bool = false
var skills: Dictionary = {
	"harvesting": 0,
	"fabrication": 0,
	"combat": 0,
	"infrastructure": 0,
}
var unlocked_research: Dictionary = {}  # research_id -> true

# ---------------- Per-action Mastery (ported from desktop gathering_manager /
# processing_manager — identical logic for both skills) ----------------
# Each gather action id and craft recipe id accumulates its OWN mastery XP total
# (a float), separate from skill XP. Milestones at 10/25/50/75/100 grant
# cumulative duration reductions (capped 30%) that SPEED UP the action. Gather
# and craft ids share one dict — they never collide.
const MASTERY_XP_PER_COMPLETION := 1.0          # +1 mastery XP per completed loop
const MASTERY_MILESTONES := [10, 25, 50, 75, 100]
# Cumulative duration-reduction table indexed by # milestones passed (0..5).
const MASTERY_DURATION_BONUS_TABLE := [0.0, 0.05, 0.10, 0.20, 0.25, 0.30]
const MASTERY_LEVEL_CAP := 100
var mastery: Dictionary = {}  # {action_id / recipe_id: xp_total_float}

# Single foreground task
var active_type: String = ""            # "gather" | "craft" | "combat" | ""
var active_id: String = ""
var progress: float = 0.0

# Combat (real-time ship duel)
var combat_hp: float = 0.0            # persistent hull HP
var player_shield: float = 0.0        # regenerates fast in combat
var player_heat: float = 0.0          # weapons add heat; overheat locks fire
var _overheat_lock: float = 0.0
var _broadside_timer: float = 0.0     # unique module: Broadside Array
var _weapons: Array = []              # live weapon states built from loadout
var enemy_inst: Dictionary = {}       # live enemy instance
var _enemy_timer: float = 0.0
var combat_events: Array = []         # transient [{text,color,side,seq}] for UI popups
var _event_seq: int = 0
# Running tally of every item collected this combat engagement (item_id -> qty).
# Transient (not persisted); reset on each new engagement. Desktop session-loot parity.
var session_loot: Dictionary = {}
# Ammo + consumables (fittings)
var ammo_loadout: Dictionary = {}      # weapon slot index (String) -> ammo item id
var consumable_hull_slot: String = ""
var consumable_shield_slot: String = ""
var _consume_cd: float = 0.0
# Loadout Presets — 3 saved builds for quick swap (desktop ref ~L347-352).
# Each: {name, loadout (slot->mid), ammo_loadout (slot->ammo), consumable_hull, consumable_shield}.
var loadout_presets: Dictionary = {
	1: {"name": "", "loadout": {}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""},
	2: {"name": "", "loadout": {}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""},
	3: {"name": "", "loadout": {}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""},
}
const MAX_LEVEL := 99                  # skill level cap (matches desktop)
var _xp_table: Array = []              # lazily built cumulative XP-to-level table
const CONSUME_CD := 1.5
const CONSUME_THRESHOLD := 0.5         # auto-trigger at 50% hull/shield
const MAX_HEAT := 100.0
const VENT_RATE := 8.0

# v87.0 Enemy typed-damage balance compensation (desktop combat_manager):
# energy enemies hit shields x1.5 and explosive bypass 80% armor, so their raw
# atk is scaled down before being routed into the e/x channel.
const ENEMY_ENERGY_ATK_COMP := 0.75
const ENEMY_EXPLOSIVE_ATK_COMP := 0.85

# v80.1 Combat safety caps — anti-exploit hard ceilings (desktop apply_safety_caps).
const MAX_ATK_SPEED_MULT := 3.0          # Max 3x base fire rate (+200%)
const MAX_EVASION := 75.0                # Enemies always >=25% hit chance
const MAX_CRIT_CHANCE := 0.50            # No guaranteed-crit loops
const MAX_CRIT_DAMAGE := 3.0             # Caps burst spikes (crit variance mult)
const MAX_SHIELD_REGEN_PERCENT := 5.0    # % of max shield per second
const MAX_HP_REGEN_PERCENT := 2.0        # % of max HP per second
const MAX_ENEMY_SLOW := 0.50             # Jamming can't freeze enemies
const MAX_REFLECT_PERCENT := 0.10        # Reflect capped

# v86.0 Hazard-zone (gauntlet) runtime state. zone_id "" means no hazard active.
var hazard_state: Dictionary = {"active": false, "zone_id": "", "wave": 0, "max_waves": 7}
var boss_kills: Dictionary = {}          # enemy_id -> kill count (hazard unlocks, z11 flag)
var hazard_clears: Dictionary = {}       # hazard_zone_id -> true (first-clear reward gate)
var game_flags: Dictionary = {}          # persistent unlock flags (e.g. z11_unlocked)
var _enemy_enraged: bool = false         # v109 per-fight enrage state (reset on spawn)
var enemy_vulnerable_timer: float = 0.0  # v85.2 when >0 enemy takes +20% damage
var _player_berserk_timer: float = 0.0   # v85.2 Overdrive: +25% fire rate while >0

# Shipyard
var active_hull: String = ""
var owned_hulls: Dictionary = {}        # hull_id -> true
var module_inventory: Dictionary = {}   # module_id -> count (unequipped)
var loadout: Dictionary = {}            # slot_index (as String) -> module_id
var custom_modules: Dictionary = {}     # custom_id -> rolled module instance (rarity + affixes)

# --- Module rarity / affix system ---
const RARITY_LABEL := {0: "", 1: "Uncommon", 2: "Rare", 3: "Legendary", 4: "Unique"}
const RARITY_COLOR := {0: "9aa7c2", 1: "35d935", 2: "3a9fff", 3: "ffcc33", 4: "ff44cc"}
# v71.0 RARITY_STAT_RANGE (desktop ref_shipyard_manager.gd ~L20-26). These multiply
# the base module stat: Uncommon 1.30-1.50x, Rare 2.30-2.65x, Legendary 3.00-3.80x,
# Unique 4.50-6.00x. (Mobile previously ran ~10x weaker at 1.05-1.27x.)
const RARITY_RANGE := {1: [0.30, 0.50], 2: [1.30, 1.65], 3: [2.00, 2.80], 4: [3.50, 5.00]}
# v100 RARITY_SELL_PRICES / RARITY_SPARE_PARTS (desktop ref ~L2563/2571).
const RARITY_SELL := {0: 100, 1: 750, 2: 5000, 3: 30000, 4: 100000}
const RARITY_SPARE_PARTS := {0: 1, 1: 3, 2: 8, 3: 25, 4: 75}
# Desktop module zone-scaling curve (ref ~L29-31): early steps x1.34, late x1.28
# (late start at zone 7), replacing mobile's flat pow(1.30, …).
const MODULE_ZONE_SCALE_EARLY := 1.34
const MODULE_ZONE_SCALE_LATE := 1.28
const MODULE_ZONE_LATE_START := 7
const BOOSTABLE := ["atk_kinetic", "atk_energy", "atk_explosive", "hp", "def", "eva", "accuracy",
	"crit_chance", "max_shield", "shield_regen", "energy_capacity", "atk_speed_bonus",
	"shield_regen_mult", "atk_speed_mult", "jamming_strength", "atk_interval"]
const ZONE_SCALABLE := ["atk_kinetic", "atk_energy", "atk_explosive", "hp", "def", "eva",
	"accuracy", "max_shield", "shield_regen", "energy_capacity", "atk_interval"]
# v74.0 Module Affix System — full desktop AFFIX_DB (ref_shipyard_manager.gd ~L122-252).
# `scaling`: "flat" → floor(raw * 1.8^(zone-1)); "linear_tier" → raw * zone; else
# percent → raw/100 (a [0..1] fraction). `range` holds INTEGER endpoints (desktop).
# Slot mapping note: desktop "cooling" slot has no mobile equivalent (mobile slots:
# weapon/shield/armor/engine/battery/sensor) — heat_sync_focus drops "cooling" and
# stays weapon-only.
const AFFIX_DB := {
	# --- TACTICAL (Weapon, Sensor) ---
	"static_burst":     {"name": "Static Burst", "type": "tactical", "scaling": "percent", "range": [3, 8], "limit_to": ["weapon"], "desc": "%d%% shock on hit (resets enemy timer)"},
	"void_strike":      {"name": "Void Strike", "type": "tactical", "scaling": "percent", "range": [3, 8], "limit_to": ["weapon"], "desc": "%d%% chance to bypass shields"},
	"flat_atk":         {"name": "Sharpened Edge", "type": "tactical", "scaling": "flat", "range": [2, 5], "limit_to": ["weapon"], "desc": "+%d flat attack damage"},
	"flat_accuracy":    {"name": "Targeting Computer", "type": "tactical", "scaling": "flat", "range": [5, 15], "limit_to": ["weapon", "sensor"], "desc": "+%d flat accuracy"},
	"heat_sync_focus":  {"name": "Heat-Sync Focus", "type": "tactical", "scaling": "percent", "range": [5, 12], "limit_to": ["weapon"], "desc": "+%d%% fire rate while Heat > 40%%"},
	# --- DEFENSIVE (Armor, Shield) ---
	"flat_hp":          {"name": "Reinforced Layers", "type": "defensive", "scaling": "flat", "range": [5, 15], "limit_to": ["armor"], "desc": "+%d flat hull integrity"},
	"flat_def":         {"name": "Damped Plating", "type": "defensive", "scaling": "flat", "range": [1, 3], "limit_to": ["armor"], "desc": "+%d flat defense"},
	"flat_shield":      {"name": "Flux Capacitor", "type": "defensive", "scaling": "flat", "range": [10, 30], "limit_to": ["shield"], "desc": "+%d flat shield capacity"},
	"capacitor_pulse":  {"name": "Capacitor Pulse", "type": "defensive", "scaling": "percent", "range": [2, 5], "limit_to": ["shield", "battery"], "desc": "Restore %d%% shield on kill"},
	"nanite_resurgence":{"name": "Nanite Resurgence", "type": "defensive", "scaling": "percent", "range": [2, 5], "limit_to": ["armor"], "desc": "Restore %d%% hull on kill"},
	# --- INDUSTRIAL / ECONOMY (Sensor) ---
	"refinery_link":    {"name": "Refinery Link", "type": "industrial", "scaling": "percent", "range": [3, 10], "limit_to": ["sensor"], "desc": "+%d%% craft speed"},
	"extractor_efficiency": {"name": "Extractor Efficiency", "type": "industrial", "scaling": "percent", "range": [3, 10], "limit_to": ["sensor"], "desc": "+%d%% gather yield"},
	"nano_scavenger":   {"name": "Nano-Scavenger", "type": "industrial", "scaling": "percent", "range": [3, 10], "limit_to": ["sensor"], "desc": "%d%% chance to scavenge parts on kill"},
	"contract_negotiation": {"name": "Contract Negotiation", "type": "economy", "scaling": "percent", "range": [3, 10], "limit_to": ["sensor"], "desc": "+%d%% bounty credits"},
	"logistician_edge": {"name": "Logistician's Edge", "type": "economy", "scaling": "percent", "range": [3, 10], "limit_to": ["sensor"], "desc": "-%d%% delivery material cost"},
	# --- v85.1 Combat affixes ---
	"combat_sight":     {"name": "Combat Sight", "type": "tactical", "scaling": "percent", "range": [2, 5], "limit_to": ["weapon", "sensor"], "desc": "+%d%% critical strike chance"},
	"reflexive_plating":{"name": "Reflexive Plating", "type": "defensive", "scaling": "flat", "range": [2, 5], "limit_to": ["armor", "engine"], "desc": "+%d flat evasion"},
	"hull_heal_on_hit": {"name": "Nanite Syringe", "type": "defensive", "scaling": "linear_tier", "range": [1, 3], "limit_to": ["weapon", "armor"], "desc": "Restore %d hull on every hit"},
	"shield_heal_on_hit":{"name": "Shield Siphon", "type": "defensive", "scaling": "linear_tier", "range": [1, 3], "limit_to": ["weapon", "shield"], "desc": "Restore %d shield on every hit"},
	# --- v85.3 Refined combat affixes ---
	"lucky_hit_chance": {"name": "Tactical Breach Chance", "type": "tactical", "scaling": "percent", "range": [5, 10], "limit_to": ["weapon", "sensor"], "desc": "+%d%% tactical breach chance"},
	"dmg_healthy":      {"name": "Precision Calibration", "type": "tactical", "scaling": "percent", "range": [10, 20], "limit_to": ["weapon"], "desc": "+%d%% damage vs high-integrity (>80%% hull)"},
	"dmg_injured":      {"name": "Structural Exploitation", "type": "tactical", "scaling": "percent", "range": [15, 30], "limit_to": ["weapon"], "desc": "+%d%% damage vs damaged (<35%% hull)"},
	"vuln_on_hit":      {"name": "Exposing Pulse", "type": "tactical", "scaling": "percent", "range": [5, 12], "limit_to": ["weapon"], "desc": "%d%% chance to Expose enemies (20%% more dmg) for 3s"},
	"berserk_on_kill":  {"name": "Overdrive Catalyst", "type": "tactical", "scaling": "percent", "range": [8, 15], "limit_to": ["weapon", "engine"], "desc": "%d%% chance on kill to enter Overdrive (+25%% atk speed) for 5s"},
}

# Infrastructure (passive production buildings — runs in the background always)
var buildings: Dictionary = {}          # id -> count
var building_throttle: Dictionary = {}  # id -> 0..1
var infra_energy: float = 0.0           # grid battery (capacity = ship energy_cap)
var _fuel_frac: Dictionary = {}         # fractional fuel-generator consumption accumulator
var _build_timers: Dictionary = {}      # id -> accumulated time
var _build_frac: Dictionary = {}        # sym -> fractional carry
var _infra_dirty := false
var _infra_emit_accum := 0.0

var pending_offline: String = ""
var _bg_time := 0.0             # wall-clock when the app was backgrounded (0 = foreground)
var offline_combat := false             # option: process combat while away (off by default, like desktop)

# Legacy single-save path (pre-slots). Kept only for the one-time migration below.
const SAVE_PATH := "user://stellarforge_save.json"
# Melvor-style multi-slot saves. Each slot is an independent self-contained save.
const SLOT_COUNT := 4
var current_slot := 0                    # 0 = no slot active (character-select screen)
var character_name := "Commander"        # active character's display name
var _created_at := 0.0                   # unix time this character was created (slot metadata)
const AUTOSAVE_INTERVAL := 15.0
var _save_accum := 0.0

func slot_path(n: int) -> String:
	return "user://save_slot_%d.json" % n

func _ready() -> void:
	# Boot deferred: NO slot is loaded here anymore. The UI shows a character-select
	# screen first, then calls select_slot()/new_character() which runs enter_slot().
	# We only run the one-time legacy migration and leave state at fresh defaults.
	_migrate_legacy_save()

## One-time migration: a pre-slots single save becomes Slot 1 so existing players
## keep their progress. Only runs if the legacy file exists and Slot 1 does not.
func _migrate_legacy_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	if FileAccess.file_exists(slot_path(1)):
		return
	# Read the legacy JSON, stamp a default name, and write it as Slot 1.
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(txt) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return
	var data: Dictionary = json.data
	if not data.has("character_name"):
		data["character_name"] = "Commander"
	if not data.has("created_at"):
		data["created_at"] = Time.get_unix_time_from_system()
	var out := FileAccess.open(slot_path(1), FileAccess.WRITE)
	if out == null:
		return
	out.store_string(JSON.stringify(data, "\t"))
	out.close()

## Runs AFTER a slot becomes active (load_game / new_character) — the post-load init
## that used to live in _ready. Brings transient state up to a playable baseline.
func enter_slot() -> void:
	if active_hull == "":
		active_hull = "corvette_hull"
		owned_hulls["corvette_hull"] = true
	if combat_hp <= 0.0:
		combat_hp = combat_max_hp()
	if bounty_available.is_empty() and bounty_active.is_empty():
		generate_bounty_pool()
	ensure_standing_board()
	_mission_init()
	_mission_repair()

func _process(delta: float) -> void:
	_tick_active(delta)
	_tick_infra(delta)
	# Hull does NOT passively regenerate — repair via credits or in-combat consumables/sets.
	combat_hp = minf(combat_hp, combat_max_hp())
	# Throttle resource-change signals from passive production to ~2/sec.
	_infra_emit_accum += delta
	if _infra_dirty and _infra_emit_accum >= 0.5:
		_infra_emit_accum = 0.0
		_infra_dirty = false
		resources_changed.emit()
	if bounty_refresh_timer > 0.0:
		bounty_refresh_timer -= delta
		if bounty_refresh_timer <= 0.0:
			generate_bounty_pool()
	_save_accum += delta
	if _save_accum >= AUTOSAVE_INTERVAL:
		_save_accum = 0.0
		if current_slot != 0:        # never autosave to disk while at character-select
			save_game()

func _notification(what: int) -> void:
	# Saves are gated on an active slot — quitting/backgrounding at the
	# character-select screen must not write a half-initialized state to disk.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if current_slot != 0:
			save_game()
	# Android freezes the process while backgrounded (no _process ticks), so we
	# record when we leave and credit the elapsed time on return — same as a cold
	# launch, but without needing a full reload.
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if _bg_time == 0.0 and current_slot != 0:
			_bg_time = Time.get_unix_time_from_system()
			save_game()
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		if _bg_time > 0.0:
			var delta := Time.get_unix_time_from_system() - _bg_time
			_bg_time = 0.0
			_catch_up_offline(delta)

## Apply offline progress for `delta` seconds while the app was backgrounded
## (mirrors the cold-launch path) and notify the UI to show the report.
func _catch_up_offline(delta: float) -> void:
	if delta < 5.0:
		return
	pending_offline = ""
	_suppress_fx = true
	_apply_offline(delta)
	var infra := _offline_infra(delta)
	_suppress_fx = false
	if infra != "":
		if pending_offline == "":
			pending_offline = "Away for %s\n\n%s" % [_fmt_time(delta), infra]
		else:
			pending_offline += "\n" + infra
	resources_changed.emit()
	skills_changed.emit()
	if pending_offline != "":
		offline_ready.emit()

# ---------------- Resources / credits ----------------
func amount(sym: String) -> int:
	return int(resources.get(sym, 0))

func add_resource(sym: String, amt: int) -> void:
	# Storage cap: a new material is dropped when all slots are full (desktop
	# resources.gd). Existing stacks are unbounded.
	if amt > 0 and amount(sym) <= 0 and used_slots() >= max_slots():
		return
	resources[sym] = amount(sym) + amt
	# One-shot Recursion pointer on first Void Artifact (desktop v109).
	if sym == "VoidArtifact" and amt > 0 and not game_flags.get("recursion_revealed", false):
		game_flags["recursion_revealed"] = true
		if not _suppress_fx:
			feature_revealed.emit("⟨ RECURSION PROTOCOLS ONLINE ⟩",
				"Spend Void Artifacts on the Research page's RECURSION tab for permanent global bonuses.")
	if amt > 0 and not missions_active.is_empty():
		_mission_event("gather", sym, amt)
	if amt > 0:
		_standing_track_gather(sym, amt)
	resources_changed.emit()

# ---- Storage slots ----
const BASE_SLOTS := 28
var storage_upgrades := 0

func used_slots() -> int:
	var n := 0
	for sym in resources:
		if int(resources[sym]) > 0:
			n += 1
	return n

func max_slots() -> int:
	return BASE_SLOTS + storage_upgrades

func storage_upgrade_cost() -> int:
	return int(floor(1000.0 * pow(1.5, storage_upgrades)))

func upgrade_storage() -> bool:
	var cost := storage_upgrade_cost()
	if credits < cost:
		return false
	credits -= cost
	storage_upgrades += 1
	resources_changed.emit()
	return true

func gain_credits(n: int) -> void:
	credits += n
	lifetime_credits += n   # lifetime total drives prestige gains

# ---------------- Warp / prestige multipliers ----------------
func warp_tier() -> int:
	return total_warps / 5

func warp_gathering_mult() -> float:
	return (1.0 + warp_shards * 0.015) * pow(2.0, warp_tier())

func warp_xp_mult() -> float:
	return (1.0 + warp_shards * 0.025) * pow(2.0, warp_tier())

func warp_production_mult() -> float:
	return (1.0 + warp_shards * 0.02) * pow(2.0, warp_tier())

func warp_combat_mult() -> float:
	return (1.0 + warp_shards * 0.03) * pow(2.0, warp_tier())

# ---------------- Warp Mastery Tree (ref_warp_manager ~L138-196) ----------------
func available_warp_shards() -> float:
	return maxf(0.0, warp_shards - warp_shards_spent)

func is_branch_revealed(branch: String) -> bool:
	if not branch in BRANCH_REVEAL_WARP:
		return false
	return total_warps >= int(BRANCH_REVEAL_WARP[branch])

func is_node_purchased(node_id: String) -> bool:
	return bool(purchased_nodes.get(node_id, false))

func is_node_implemented(node_id: String) -> bool:
	if not node_id in TREE_NODES:
		return false
	return bool(TREE_NODES[node_id].get("implemented", true))

func can_purchase_node(node_id: String) -> bool:
	# Faithful to ref_warp_manager.can_purchase_node (~L156-166): nodes are
	# INDEPENDENT — no in-branch prereq chain. A node is buyable once its branch
	# is revealed, it is implemented, and you can afford it. (A prereq chain would
	# strand the implemented C5 Cryo Overcharge behind the unimplemented C3/C4.)
	if not node_id in TREE_NODES:
		return false
	if is_node_purchased(node_id):
		return false
	if not is_node_implemented(node_id):
		return false  # unfinished mechanic nodes refuse purchase (desktop parity)
	var node: Dictionary = TREE_NODES[node_id]
	if not is_branch_revealed(node["branch"]):
		return false
	return available_warp_shards() >= float(node["cost"])

func purchase_tree_node(node_id: String) -> bool:
	if not can_purchase_node(node_id):
		return false
	warp_shards_spent += float(TREE_NODES[node_id]["cost"])
	purchased_nodes[node_id] = true
	if active_type == "combat":
		combat_hp = minf(maxf(combat_hp, 1.0), combat_max_hp())   # keep current HP within the (now larger) C1 ceiling
	resources_changed.emit()
	return true

# Effect queries — folded into the matching stat getters. 1.0 means "not bought".
func tree_gathering_bonus() -> float:
	return 1.10 if is_node_purchased("E1") else 1.0          # E1: +10% gather yield

func tree_processing_speed_bonus() -> float:
	return (1.0 / 0.9) if is_node_purchased("E2") else 1.0   # E2: -10% duration

func tree_hull_bonus() -> float:
	return 1.10 if is_node_purchased("C1") else 1.0          # C1: +10% hull HP

func tree_damage_bonus() -> float:
	return 1.10 if is_node_purchased("C2") else 1.0          # C2: +10% module damage

func tree_cryo_bonus() -> float:
	return 1.50 if is_node_purchased("C5") else 1.0          # C5: +50% Cryo damage

## Shards that would be gained by warping now (0 = below threshold).
func warp_gain_preview() -> int:
	var earned := lifetime_credits - credits_at_warp_start
	var bcount := 0
	for bid in buildings:
		bcount += int(buildings[bid])
	var score := float(earned) + bcount * 1000.0
	if score < 500000.0:
		return 0
	return int(floor(log(maxf(1.0, score / 500000.0)) / log(2.0)) + 1.0)

func execute_warp() -> int:
	var gains := warp_gain_preview()
	if gains <= 0:
		return 0
	warp_shards += gains
	total_warps += 1
	credits_at_warp_start = lifetime_credits
	var bonus := int(warp_shards)
	# Reset the world. Research unlocks PERSIST (soft reset); skills keep 30% XP.
	resources = {}
	credits = 0
	for sk in skills:
		skills[sk] = int(skills[sk] * 0.3)
	buildings = {}
	building_throttle = {}
	infra_energy = 0.0
	_build_timers = {}
	_build_frac = {}
	_upkeep_timer = 0.0
	upkeep_efficiency = 1.0
	active_hull = "corvette_hull"
	owned_hulls = {"corvette_hull": true}
	module_inventory = {}
	loadout = {}
	ammo_loadout = {}
	consumable_hull_slot = ""
	consumable_shield_slot = ""
	for i in [1, 2, 3]:
		loadout_presets[i] = {"name": "", "loadout": {}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""}
	bounty_active = []
	stop_task()
	# Starting package (does not feed the next prestige).
	credits = bonus * 5000
	for r in {"Fe": 50, "Si": 30, "Wood": 20, "Water": 50}:
		resources[r] = {"Fe": 50, "Si": 30, "Wood": 20, "Water": 50}[r] * bonus
	# v111: Cryo unlock — Warping permanently grants Cryogenic armaments, the only
	# weapons that bite Z11 Warp-Hardened hulls. The FIRST Warp grants a starter
	# Cryo Shard Pistol (~Z1 power); guard on the flag so re-warps don't duplicate
	# it (desktop warp_manager ~L106-116). Runs AFTER the world reset above so the
	# granted weapon survives into the fresh run.
	if not cryo_unlocked:
		module_inventory["cryo_shard_pistol"] = int(module_inventory.get("cryo_shard_pistol", 0)) + 1
	cryo_unlocked = true
	combat_hp = combat_max_hp()
	generate_bounty_pool()
	# Standing Orders are zone-tiered + track inventory — regenerate against the
	# fresh post-warp world (mirrors the bounty pool refresh above).
	standing_board = []
	_standing_fill()
	# Warp goal missions (goal_002/goal_003) track total_warps.
	_mission_event("warp_perform", "warp", 1)
	_mission_sync()
	resources_changed.emit()
	skills_changed.emit()
	research_changed.emit()
	action_changed.emit()
	save_game()
	return gains

func can_afford(cost: Dictionary) -> bool:
	for sym in cost:
		if amount(sym) < int(cost[sym]):
			return false
	return true

func spend(cost: Dictionary, times: int = 1) -> void:
	for sym in cost:
		resources[sym] = amount(sym) - int(cost[sym]) * times
	resources_changed.emit()

func sell_all(sym: String) -> void:
	var qty := amount(sym)
	if qty <= 0:
		return
	gain_credits(qty * maxi(1, GameData.value_of(sym)))
	resources[sym] = 0
	resources_changed.emit()

# ---------------- Skills ----------------
func xp_for_level(lvl: int) -> int:
	# RuneScape-style table (matches the desktop Skill class): steeper early game,
	# capped at level 99.
	if _xp_table.is_empty():
		var total := 0.0
		_xp_table.resize(MAX_LEVEL + 1)
		for l in range(1, MAX_LEVEL + 1):
			_xp_table[l] = int(total)
			var boost := 200.0 if l < 20 else 0.0
			total += floor(l + boost + 300.0 * pow(2.0, float(l) / 7.0)) / 4.0
	if lvl <= 1:
		return 0
	if lvl > MAX_LEVEL:
		return 0x7FFFFFFFFFFF       # unreachable — enforces the level cap
	return int(_xp_table[lvl])

func level_of(skill_id: String) -> int:
	var xp := int(skills.get(skill_id, 0))
	var lvl := 1
	while lvl < MAX_LEVEL and xp >= xp_for_level(lvl + 1):
		lvl += 1
	return lvl

func add_xp(skill_id: String, amt: int) -> void:
	# Crew Quarters: +10% XP gain per building (desktop infrastructure xp_buff).
	var xp_mult := warp_xp_mult() * (1.0 + building_count("crew_quarters") * 0.10)
	var before := level_of(skill_id)
	skills[skill_id] = int(skills.get(skill_id, 0)) + int(round(amt * xp_mult))
	skills_changed.emit()
	var after := level_of(skill_id)
	if after > before and not _suppress_fx:
		level_up.emit(skill_id, after)   # not while applying offline — the report covers it

func yield_mult(skill_id: String) -> float:
	if skill_id != "harvesting":
		return 1.0 + level_of(skill_id) * 0.01
	var m := 1.0 + level_of("harvesting") * 0.01          # +1% per level (Planetary Operations)
	if level_of("harvesting") >= 10:
		m *= 1.10                                          # milestone 10: +10% yield
	m *= research_efficiency_mult()                        # Efficiency I-V: 2x..32x
	m *= 1.0 + affix_total("extractor_efficiency")
	m *= 1.0 + research_bonus("gathering_yield_mult")      # Recursion: gathering_focus
	m *= tree_gathering_bonus()                            # E1 Yield Calibration: +10%
	# NB: warp prestige boosts gathering via SPEED (see gather_speed_mult), not yield.
	return m

# ---------------- Per-action Mastery ----------------
## XP required to REACH `target` from `target-1` (desktop _mastery_xp_needed_for_level).
func mastery_xp_needed(target: int) -> float:
	if target <= 0 or target > MASTERY_LEVEL_CAP:
		return 0.0
	return 25.0 + float(target) * 5.0

func mastery_xp(id: String) -> float:
	return float(mastery.get(id, 0.0))

## Current mastery level for an action/recipe id (0..100).
func mastery_level(id: String) -> int:
	var xp := mastery_xp(id)
	var level := 0
	var threshold := 0.0
	while level < MASTERY_LEVEL_CAP:
		var needed := mastery_xp_needed(level + 1)
		if xp < threshold + needed:
			break
		threshold += needed
		level += 1
	return level

## Progress within the current level → {in_level, needed, at_cap} for a bar.
func mastery_progress(id: String) -> Dictionary:
	var xp := mastery_xp(id)
	var level := mastery_level(id)
	if level >= MASTERY_LEVEL_CAP:
		return {"in_level": 0.0, "needed": 0.0, "at_cap": true}
	var threshold := 0.0
	for n in range(1, level + 1):
		threshold += mastery_xp_needed(n)
	var needed := mastery_xp_needed(level + 1)
	return {"in_level": xp - threshold, "needed": needed, "at_cap": false}

## Number of mastery milestones passed at this id's current level (0..5).
func mastery_milestones_passed(id: String) -> int:
	var level := mastery_level(id)
	var passed := 0
	for m in MASTERY_MILESTONES:
		if level >= int(m):
			passed += 1
	return passed

## Duration multiplier from mastery: 1.0 → 0.70 (max). <1.0 means faster.
func mastery_dur_mult(id: String) -> float:
	var idx: int = clampi(mastery_milestones_passed(id), 0, MASTERY_DURATION_BONUS_TABLE.size() - 1)
	return 1.0 - float(MASTERY_DURATION_BONUS_TABLE[idx])

## Next mastery milestone LEVEL above the current one (0 if at/over cap) — UI teaser.
func next_mastery_milestone(id: String) -> int:
	var level := mastery_level(id)
	for m in MASTERY_MILESTONES:
		if level < int(m):
			return int(m)
	return 0

## Credit mastery XP for `n` completed loops (online: n=1; offline: n=batch).
func gain_mastery_xp(id: String, n: float = MASTERY_XP_PER_COMPLETION) -> void:
	mastery[id] = mastery_xp(id) + n

# ---------------- Combat stats ----------------
## Derived ship stats from the active hull + equipped modules.
## Returns {} when no ship is equipped.
func ship_stats() -> Dictionary:
	if active_hull == "" or not GameData.HULLS.has(active_hull):
		return {}
	var h: Dictionary = GameData.HULLS[active_hull]
	# v110: hulls provide ZERO energy — all capacity comes from batteries (the
	# hull energy_capacity stat is now vestigial / display-only). Batteries had
	# their capacity baked into module stats in Phase 5.
	var s := {"atk": 0.0, "hp": float(h.get("hp", 100)), "def": 0.0, "shield": 0.0,
		"energy_cap": 0.0, "energy_load": 0.0,
		"acc": 100.0, "eva": 0.0, "crit": 0.05, "shield_regen": 0.0}
	var dps := 0.0
	var spd_bonus := 0.0
	var spd_mult := 1.0
	# Engineering skill scales module stats (desktop recalc_stats); eva/acc/crit
	# stay flat there too.
	var eng := 1.0 + level_of("fabrication") * 0.01
	s["regen_bonus"] = 0.0
	for k in loadout:
		var m: Dictionary = module_def(loadout[k])
		var st: Dictionary = m.get("stats", {})
		s.hp += float(st.get("hp", 0)) * eng
		s.def += float(st.get("def", 0)) * eng
		s.shield += float(st.get("max_shield", 0)) * eng
		s.energy_cap += float(st.get("energy_capacity", 0)) * eng
		s.energy_load += float(st.get("energy_load", 0))
		s.acc += float(st.get("accuracy", 0))
		s.eva += float(st.get("eva", 0))
		s.crit += float(st.get("crit_chance", 0))
		s.shield_regen += float(st.get("shield_regen", 0)) * eng
		s["regen_bonus"] += float(st.get("shield_regen_mult", 0)) + float(st.get("shield_regen_bonus", 0))
		spd_bonus += float(st.get("atk_speed_bonus", 0))
		if st.has("atk_speed_mult"):
			spd_mult *= float(st["atk_speed_mult"])
		var dmg := float(st.get("atk_energy", 0)) + float(st.get("atk_kinetic", 0)) + float(st.get("atk_explosive", 0))
		if dmg > 0.0:
			dps += dmg / maxf(0.1, float(st.get("atk_interval", 1.0)))
	# v80.1/v85.1 Flat affix bonuses BEFORE gem/set multipliers (desktop recalc_stats
	# ~L1966-1974). flat_atk folds into the aggregated attack as a flat damage add.
	s.hp += affix_total("flat_hp")
	s.shield += affix_total("flat_shield")
	s.def += affix_total("flat_def")
	s.acc += affix_total("flat_accuracy")
	s.crit += affix_total("combat_sight")
	s.eva += affix_total("reflexive_plating")
	dps += affix_total("flat_atk")
	s.atk = dps * (1.0 + spd_bonus) * spd_mult + float(h.get("atk", 0))
	s["atk_speed_bonus"] = spd_bonus
	s["hp_regen"] = 0.0
	s["jamming_strength"] = 0.0
	for k in loadout:
		var jst: Dictionary = module_def(loadout[k]).get("stats", {})
		s["jamming_strength"] += float(jst.get("jamming_strength", 0))
		s["hp_regen"] += float(jst.get("hp_regen", 0)) * eng
	# Gem core global multipliers
	s.crit += gem_bonus("crit_chance")
	s.hp *= 1.0 + gem_bonus("hp_mult")
	s.def *= 1.0 + gem_bonus("def_mult")
	s.shield *= 1.0 + gem_bonus("max_shield_mult")
	s.shield_regen *= 1.0 + gem_bonus("shield_regen_mult")
	s.eva *= 1.0 + gem_bonus("eva_mult")
	s.energy_cap *= 1.0 + gem_bonus("energy_capacity_mult") + research_bonus("applied_physics")
	# Combat skill milestones (desktop Phase 21): +5% crit @ L10, +15 eva @ L25.
	if level_of("combat") >= 10:
		s.crit += 0.05
	if level_of("combat") >= 25:
		s.eva += 15.0
	# v80.1 Trinity set stat bonuses (desktop _apply_trinity_stat_bonuses).
	# Damage % bonuses (atk_pct / all_dmg_pct / *_dmg_pct) are applied in the
	# weapon damage path (ship_weapons / _player_fire); here we fold in the
	# defensive/utility ones that live as ship stats.
	s["atk_speed_bonus"] += trinity_bonus("atk_speed_pct") / 100.0
	s.def += trinity_bonus("def_flat")
	if trinity_bonus("def_pct") > 0.0:
		s.def *= 1.0 + trinity_bonus("def_pct") / 100.0
	s.crit += trinity_bonus("crit_chance") / 100.0
	s.eva += trinity_bonus("evasion_flat")
	s.acc += trinity_bonus("accuracy_flat")
	s["hp_regen"] += trinity_bonus("hp_regen_flat")
	if trinity_bonus("shield_hp_pct") > 0.0:
		s.shield *= 1.0 + trinity_bonus("shield_hp_pct") / 100.0
	if trinity_bonus("shield_regen_pct") > 0.0:
		s.shield_regen *= 1.0 + trinity_bonus("shield_regen_pct") / 100.0
	# v80.1 Safety caps — anti-exploit ceilings on the values combat consumes.
	s["atk_speed_bonus"] = minf(s["atk_speed_bonus"], MAX_ATK_SPEED_MULT - 1.0)
	s.eva = minf(s.eva, MAX_EVASION)
	s.crit = minf(s.crit, MAX_CRIT_CHANCE)
	s["jamming_strength"] = minf(s["jamming_strength"], MAX_ENEMY_SLOW)
	if s.shield > 0.0:
		s.shield_regen = minf(s.shield_regen, s.shield * MAX_SHIELD_REGEN_PERCENT / 100.0)
	if s.hp > 0.0:
		s["hp_regen"] = minf(s["hp_regen"], s.hp * MAX_HP_REGEN_PERCENT / 100.0)
	return s

## Live weapon list built from equipped weapon modules (or the hull cannon).
func ship_weapons() -> Array:
	var spd_bonus := 0.0
	var spd_mult := 1.0
	for k in loadout:
		var st: Dictionary = module_def(loadout[k]).get("stats", {})
		spd_bonus += float(st.get("atk_speed_bonus", 0))
		if st.has("atk_speed_mult"):
			spd_mult *= float(st["atk_speed_mult"])
	# v80.1 Trinity: atk-speed boost (capped), and damage multipliers.
	spd_bonus = minf(spd_bonus + trinity_bonus("atk_speed_pct") / 100.0, MAX_ATK_SPEED_MULT - 1.0)
	var speed := (1.0 + spd_bonus) * spd_mult
	var dmg_mult := (1.0 + level_of("combat") * 0.005) * warp_combat_mult() * (1.0 + research_bonus("combat_damage")) * tree_damage_bonus()  # C2 Weapon Tuning: +10%
	# Trinity all/atk damage % applies to every type; energy/missile % stack on top.
	var trin_all := 1.0 + (trinity_bonus("atk_pct") + trinity_bonus("all_dmg_pct")) / 100.0
	var trin_e := 1.0 + trinity_bonus("energy_dmg_pct") / 100.0
	var trin_x := 1.0 + trinity_bonus("missile_dmg_pct") / 100.0
	var eng_mult := 1.0 + level_of("fabrication") * 0.01
	var out := []
	for k in loadout:
		var m: Dictionary = module_def(loadout[k])
		if m.get("slot", "") != "weapon":
			continue
		var st: Dictionary = m.get("stats", {})
		var ke := float(st.get("atk_energy", 0))
		var kk := float(st.get("atk_kinetic", 0))
		var kx := float(st.get("atk_explosive", 0))
		var kc := float(st.get("atk_cryo", 0))
		var type := "kinetic"
		if kc > 0: type = "cryo"
		elif ke > 0: type = "energy"
		elif kx > 0: type = "explosive"
		var gk := 1.0 + gem_bonus("atk_kinetic_mult")
		var ge := 1.0 + gem_bonus("atk_energy_mult")
		out.append({"name": m.get("name", "Weapon"), "type": type, "slot": str(k),
			"dmg_k": kk * eng_mult * dmg_mult * gk * trin_all,
			"dmg_e": ke * eng_mult * dmg_mult * ge * trin_all * trin_e,
			"dmg_x": kx * eng_mult * dmg_mult * trin_all * trin_x,
			"dmg_cryo": kc * eng_mult * dmg_mult * trin_all * tree_cryo_bonus(),
			"interval": maxf(0.3, float(st.get("atk_interval", 2.5)) / maxf(0.2, speed)), "timer": randf_range(0.0, 0.4)})
	if out.is_empty():
		var h: Dictionary = GameData.HULLS.get(active_hull, {})
		out.append({"name": "Standard Cannon", "type": "kinetic", "slot": "",
			"dmg_k": float(h.get("atk", 5)) * dmg_mult, "dmg_e": 0.0, "dmg_x": 0.0, "dmg_cryo": 0.0,
			"interval": maxf(0.3, 3.0 / maxf(0.2, speed)), "timer": 0.0})
	return out

## Flat ammo damage bonus by item id (faithful tiers), and which damage type it feeds.
func ammo_bonus(ammo_id: String) -> Array:
	if ammo_id.begins_with("Slug"):
		var b := 5.0
		if "T1S" in ammo_id: b = 10.0
		elif "T2" in ammo_id: b = 15.0
		elif "T3" in ammo_id: b = 30.0
		elif "T4" in ammo_id: b = 60.0
		return ["k", b]
	elif ammo_id.begins_with("Cell"):
		var b := 5.0
		if "T2" in ammo_id: b = 15.0
		elif "T3" in ammo_id: b = 30.0
		elif "T4" in ammo_id: b = 60.0
		return ["e", b]
	elif "issile" in ammo_id or "orpedo" in ammo_id or "eeker" in ammo_id:
		var b := 10.0
		if "Seeker" in ammo_id: b = 25.0
		elif "orpedo" in ammo_id: b = 60.0
		return ["x", b]
	return ["", 0.0]

func combat_max_hp() -> float:
	var s := ship_stats()
	if s.is_empty():
		return 100.0
	# Desktop max_hp = (hull + modules x eng) x (1 + max_hp_mult + materials_science)
	# — no combat-level HP term in the original.
	# v109: Recursive Hardening (defense_focus) applies hull_hp_mult multiplicatively.
	return float(s["hp"]) * (1.0 + research_bonus("max_hp_mult") + research_bonus("materials_science")) \
		* (1.0 + research_bonus("hull_hp_mult")) * tree_hull_bonus()   # C1 Hull Reinforcement: +10%

func player_max_shield() -> float:
	var s := ship_stats()
	return s.get("shield", 0.0) if not s.is_empty() else 0.0

## Average sustained DPS vs a target (used for offline + UI readout).
func avg_player_dps() -> float:
	var total := 0.0
	for w in ship_weapons():
		total += (float(w["dmg_k"]) + float(w["dmg_e"]) + float(w["dmg_x"]) + float(w.get("dmg_cryo", 0.0))) / maxf(0.3, float(w["interval"]))
	return total

func combat_attack() -> float:
	return avg_player_dps()

## Idle combat preview for an enemy: time-to-kill + whether you can win/farm it.
func combat_preview(eid: String) -> Dictionary:
	var e: Dictionary = GameData.ENEMIES.get(eid, {})
	if e.is_empty():
		return {}
	var diff := 1
	for z in GameData.ZONES:
		if eid in z.get("enemies", []):
			diff = int(z.get("difficulty", 1))
			break
	var k := maxf(20.0, float(diff) * 50.0)
	var raw_dps := avg_player_dps()
	var pdps := maxf(0.001, raw_dps * (1.0 - float(e.get("def", 0)) / (float(e.get("def", 0)) + k)))
	var ehp := float(e.get("hp", 10)) + float(e.get("max_shield", 0))
	var ttk := ehp / pdps
	var pdef := float(ship_stats().get("def", 0.0))
	var edps := float(e.get("atk", 0)) / maxf(0.5, float(e.get("interval", 2.5))) * (1.0 - pdef / (pdef + k))
	var sustain := float(ship_stats().get("shield_regen", 0.0)) + (50.0 if has_set_bonus("patient_zero") else 0.0)
	var self_ehp := combat_max_hp() + player_max_shield()
	return {
		"has_weapon": raw_dps > 0.0,
		"ttk": ttk,
		"win": edps * ttk < self_ehp,        # survive a single kill
		"farmable": edps <= sustain,         # can farm indefinitely (regen outpaces incoming)
	}

# ---------------- Shipyard ----------------
func _afford_cost(cost: Dictionary) -> bool:
	for sym in cost:
		if sym == "credits":
			if credits < int(cost[sym]):
				return false
		elif amount(sym) < int(cost[sym]):
			return false
	return true

func _pay_cost(cost: Dictionary) -> void:
	for sym in cost:
		if sym == "credits":
			credits -= int(cost[sym])
		else:
			resources[sym] = amount(sym) - int(cost[sym])

func hull_owned(hid: String) -> bool:
	return owned_hulls.has(hid)

func hull_unlocked(hid: String) -> bool:
	var rr: String = GameData.HULLS.get(hid, {}).get("research_req", "")
	return rr == "" or is_research_unlocked(rr)

func hull_can_get(hid: String) -> bool:
	if not hull_unlocked(hid):
		return false
	if hull_owned(hid):
		return true
	return _afford_cost(GameData.HULLS.get(hid, {}).get("cost", {}))

func select_hull(hid: String) -> bool:
	if not GameData.HULLS.has(hid) or not hull_unlocked(hid):
		return false
	if not hull_owned(hid):
		if not _afford_cost(GameData.HULLS[hid].get("cost", {})):
			return false
		_pay_cost(GameData.HULLS[hid].get("cost", {}))
		owned_hulls[hid] = true
		_mission_event("construct", hid, 1)
	# Switching ships returns all equipped modules to inventory (slots differ).
	for k in loadout:
		module_inventory[loadout[k]] = int(module_inventory.get(loadout[k], 0)) + 1
	loadout = {}
	active_hull = hid
	resources_changed.emit()
	return true

func module_unlocked(mid: String) -> bool:
	var rr: String = GameData.MODULES.get(mid, {}).get("research_req", "")
	return rr == "" or is_research_unlocked(rr)

func module_can_buy(mid: String) -> bool:
	return module_unlocked(mid) and _afford_cost(GameData.MODULES.get(mid, {}).get("cost", {}))

func buy_module(mid: String) -> bool:
	if not module_can_buy(mid):
		return false
	_pay_cost(GameData.MODULES[mid].get("cost", {}))
	module_inventory[mid] = int(module_inventory.get(mid, 0)) + 1
	_mission_event("craft", mid, 1)
	resources_changed.emit()
	return true

var equip_notice := ""                  # last equip rejection reason (shown in UI)

func equip_module(mid: String) -> bool:
	if int(module_inventory.get(mid, 0)) <= 0:
		return false
	var st: String = module_def(mid).get("slot", "")
	var slots: Array = GameData.HULLS.get(active_hull, {}).get("slots", [])
	for i in slots.size():
		if slots[i] == st and not loadout.has(str(i)):
			# Grid-overload guard (desktop Phase 18): reject if equipping pushes
			# energy load past capacity, unless the module itself adds capacity
			# (a battery — anti-softlock exception).
			var before := ship_stats()
			loadout[str(i)] = mid
			var after := ship_stats()
			if float(after.get("energy_load", 0.0)) > float(after.get("energy_cap", 0.0)) \
					and float(after.get("energy_cap", 0.0)) <= float(before.get("energy_cap", 0.0)) + 0.1:
				loadout.erase(str(i))
				equip_notice = "Grid overload — equip a Battery for more power."
				resources_changed.emit()
				return false
			module_inventory[mid] = int(module_inventory[mid]) - 1
			equip_notice = ""
			_mission_sync()   # loadout_check / loadout_rare_weapon missions re-check on equip
			resources_changed.emit()
			return true
	return false

func unequip_slot(idx: String) -> void:
	if loadout.has(idx):
		module_inventory[loadout[idx]] = int(module_inventory.get(loadout[idx], 0)) + 1
		loadout.erase(idx)
		ammo_loadout.erase(idx)
		_mission_sync()
		resources_changed.emit()

## Equip a module into a SPECIFIC slot index (the slot-first Designer flow).
## Swaps out whatever currently occupies the slot, validates the slot type and
## the energy grid (same anti-softlock battery exception as equip_module), and
## rolls back cleanly on rejection so nothing is lost.
func equip_module_to_slot(idx: int, mid: String) -> bool:
	if int(module_inventory.get(mid, 0)) <= 0:
		return false
	var slots: Array = GameData.HULLS.get(active_hull, {}).get("slots", [])
	if idx < 0 or idx >= slots.size():
		return false
	if module_def(mid).get("slot", "") != slots[idx]:
		return false
	var key := str(idx)
	var prev: String = loadout.get(key, "")   # current occupant (swapped out on success)
	var before := ship_stats()
	if prev != "":
		module_inventory[prev] = int(module_inventory.get(prev, 0)) + 1
		loadout.erase(key)
	loadout[key] = mid
	var after := ship_stats()
	if float(after.get("energy_load", 0.0)) > float(after.get("energy_cap", 0.0)) \
			and float(after.get("energy_cap", 0.0)) <= float(before.get("energy_cap", 0.0)) + 0.1:
		# Roll back to the pre-swap state.
		loadout.erase(key)
		if prev != "":
			loadout[key] = prev
			module_inventory[prev] = int(module_inventory.get(prev, 0)) - 1
		equip_notice = "Grid overload — equip a Battery for more power."
		resources_changed.emit()
		return false
	module_inventory[mid] = int(module_inventory[mid]) - 1
	ammo_loadout.erase(key)   # a swapped weapon clears the old slot's ammo binding
	equip_notice = ""
	_mission_sync()
	resources_changed.emit()
	return true

# ---------------- Loadout presets ----------------
# Faithful port of ref_shipyard_manager save/load/clear_loadout_preset
# (~L2667-2748), adapted to the mobile equip API (equip_module(mid) auto-assigns
# the first free matching slot, so the same module set reproduces the same slot
# keys — ammo is keyed by those slot strings). Engine-side only (UI is Phase 8).
func _preset_has_no_modules(preset: Dictionary) -> bool:
	for k in preset.get("loadout", {}):
		var v = preset["loadout"][k]
		if v != null and v != "":
			return false
	return true

func save_loadout_preset(idx: int) -> bool:
	if not loadout_presets.has(idx):
		return false
	var preset: Dictionary = loadout_presets[idx]
	preset["loadout"] = loadout.duplicate(true)
	preset["ammo_loadout"] = ammo_loadout.duplicate(true)
	preset["consumable_hull"] = consumable_hull_slot
	preset["consumable_shield"] = consumable_shield_slot
	if preset["name"] == "":
		preset["name"] = "Build %d" % idx
	resources_changed.emit()
	return true

# Returns {"loaded": int, "skipped": int}.
func load_loadout_preset(idx: int) -> Dictionary:
	if not loadout_presets.has(idx):
		return {"loaded": 0, "skipped": 0}
	var preset: Dictionary = loadout_presets[idx]
	if _preset_has_no_modules(preset):
		return {"loaded": 0, "skipped": 0}
	# Step 1: return every currently-equipped module to inventory.
	for slot in loadout.keys().duplicate():
		unequip_slot(slot)
	# Step 2: equip preset modules (equip_module handles inventory/slot/energy/research).
	var loaded := 0
	var skipped := 0
	for raw_slot in preset["loadout"]:
		var mid = preset["loadout"][raw_slot]
		if mid == null or mid == "":
			continue
		if equip_module(mid):
			loaded += 1
		else:
			skipped += 1
	# Step 3: restore ammo for slots that still hold a weapon.
	for raw_slot in preset.get("ammo_loadout", {}):
		var s := str(raw_slot)
		if loadout.has(s) and loadout[s] != null and loadout[s] != "":
			ammo_loadout[s] = preset["ammo_loadout"][raw_slot]
	# Step 4: restore consumables only if the player still owns at least one.
	var hull_c: String = preset.get("consumable_hull", "")
	consumable_hull_slot = hull_c if hull_c != "" and amount(hull_c) > 0 else ""
	var shield_c: String = preset.get("consumable_shield", "")
	consumable_shield_slot = shield_c if shield_c != "" and amount(shield_c) > 0 else ""
	_mission_sync()
	resources_changed.emit()
	return {"loaded": loaded, "skipped": skipped}

func clear_loadout_preset(idx: int) -> bool:
	if not loadout_presets.has(idx):
		return false
	loadout_presets[idx] = {"name": "", "loadout": {}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""}
	resources_changed.emit()
	return true

func is_loadout_preset_empty(idx: int) -> bool:
	if not loadout_presets.has(idx):
		return true
	return _preset_has_no_modules(loadout_presets[idx])

# ---------------- Module rarity / affixes ----------------
## Unified lookup: rolled custom instance, else the base catalogue module.
func module_def(mid: String) -> Dictionary:
	if custom_modules.has(mid):
		return custom_modules[mid]
	if GameData.SET_MODULES.has(mid):
		return GameData.SET_MODULES[mid]
	return GameData.MODULES.get(mid, {})

## True if a module (base id) is equipped — including rolled instances of it.
func loadout_has_module(base_id: String) -> bool:
	for mid in loadout.values():
		if mid == base_id or module_def(mid).get("base", "") == base_id:
			return true
	return false

func _current_zone_id() -> String:
	for z in GameData.ZONES:
		if active_id in z.get("enemies", []):
			return z.get("id", "")
	return ""

# ---------------- Set bonuses + gem sockets ----------------
func equipped_set_counts() -> Dictionary:
	var counts := {}
	for mid in loadout.values():
		var sn: String = module_def(mid).get("set", "")
		if sn != "":
			counts[sn] = int(counts.get(sn, 0)) + 1
	return counts

func has_set_bonus(bonus_key: String) -> bool:
	var counts := equipped_set_counts()
	for sn in counts:
		if counts[sn] >= 3 and GameData.SETS.get(sn, {}).get("bonus", "") == bonus_key:
			return true
	return false

# v80.1 Trinity sets (desktop _get_active_trinity_sets): a set_id is "active"
# when at least its `pieces` count is equipped. Generalizes the legacy
# has_set_bonus hooks to the full 10-set data-driven system.
func active_trinity_sets() -> Array:
	var counts := equipped_set_counts()
	var out := []
	for sn in counts:
		var req := int(GameData.TRINITY_SET_BONUSES.get(sn, {}).get("pieces", 3))
		if int(counts[sn]) >= req:
			out.append(sn)
	return out

# Sum of a trinity bonus key across all active sets (desktop _get_set_bonus_value).
func trinity_bonus(key: String) -> float:
	var total := 0.0
	for sn in active_trinity_sets():
		var b: Dictionary = GameData.TRINITY_SET_BONUSES.get(sn, {})
		if b.has(key):
			total += float(b[key])
	return total

## Sum of a gem effect across gems socketed into equipped modules.
func gem_bonus(key: String) -> float:
	var s := 0.0
	for mid in loadout.values():
		for gid in module_def(mid).get("sockets", []):
			if gid != null and gid != "" and GameData.GEMS.has(gid):
				s += float(GameData.GEMS[gid]["effects"].get(key, 0.0))
	return s

## Insert a gem (from inventory) into the first empty socket of a custom module.
func socket_gem(cid: String, gem_id: String) -> bool:
	if not custom_modules.has(cid) or amount(gem_id) <= 0:
		return false
	var sockets: Array = custom_modules[cid].get("sockets", [])
	for i in sockets.size():
		if sockets[i] == null or sockets[i] == "":
			sockets[i] = gem_id
			resources[gem_id] = amount(gem_id) - 1
			resources_changed.emit()
			return true
	return false

func unsocket_gem(cid: String, idx: int) -> void:
	if not custom_modules.has(cid):
		return
	var sockets: Array = custom_modules[cid].get("sockets", [])
	if idx >= 0 and idx < sockets.size() and sockets[idx] != null and sockets[idx] != "":
		add_resource(sockets[idx], 1)
		sockets[idx] = null
		resources_changed.emit()

## Drop a set piece as a mutable custom instance (with sockets).
func _grant_set_piece(base_id: String) -> String:
	var t: Dictionary = GameData.SET_MODULES.get(base_id, {})
	if t.is_empty():
		return ""
	var cid := "set_%s_%d" % [base_id, randi() % 1000000]
	custom_modules[cid] = {
		"name": t.get("name", base_id), "slot": t.get("slot", ""), "stats": t.get("stats", {}).duplicate(),
		"desc": t.get("desc", ""), "rarity": 4, "affixes": {}, "set": t.get("set", ""),
		"base": base_id, "sockets": [null, null, null],
	}
	module_inventory[cid] = int(module_inventory.get(cid, 0)) + 1
	return cid

func roll_rarity(is_boss: bool) -> int:
	var r := randf()
	var leg := 0.05 if is_boss else 0.02
	if r < leg:
		return 3
	elif r < leg + 0.10:
		return 2
	elif r < leg + 0.40:
		return 1
	return 0

## Desktop module zone-scaling curve (ref get_module_zone_multiplier ~L2286): early
## steps x1.34, then x1.28 from zone 7 on. Replaces mobile's flat pow(1.30, …).
func module_zone_mult(zone_diff: int) -> float:
	var diff := maxi(1, zone_diff)
	var early_steps := mini(diff - 1, MODULE_ZONE_LATE_START - 1)
	var late_steps := maxi(0, diff - MODULE_ZONE_LATE_START)
	return pow(MODULE_ZONE_SCALE_EARLY, early_steps) * pow(MODULE_ZONE_SCALE_LATE, late_steps)

## Creates a rolled module instance (or the base for Common); returns its id.
func generate_module(base_id: String, rarity: int, zone_diff: int) -> String:
	if not GameData.MODULES.has(base_id):
		return ""
	if rarity == 0:
		module_inventory[base_id] = int(module_inventory.get(base_id, 0)) + 1
		return base_id
	var base: Dictionary = GameData.MODULES[base_id]
	var zmult := module_zone_mult(zone_diff)
	var rng: Array = RARITY_RANGE[rarity]
	var stats := {}
	for sk in base.get("stats", {}):
		var bv := float(base["stats"][sk])
		if BOOSTABLE.has(sk):
			var scaled := bv
			if ZONE_SCALABLE.has(sk):
				scaled = maxf(0.25, bv / zmult) if sk == "atk_interval" else bv * zmult
			var bonus := randf_range(rng[0], rng[1])
			if sk == "atk_interval":
				# Desktop ref ~L2354-2359: coefficient 0.15, capped at -40% (0.6x
				# base) and an absolute 0.25s (4Hz) floor, so high-rarity rolls don't
				# compound DPS into outliers now that the bonus range is larger.
				var boosted := scaled / (1.0 + bonus * 0.15)
				boosted = maxf(boosted, scaled * 0.6)
				stats[sk] = snappedf(maxf(0.25, boosted), 0.01)
			else:
				stats[sk] = snappedf(scaled * (1.0 + bonus), 0.1) if scaled < 50.0 else float(int(round(scaled * (1.0 + bonus))))
		else:
			stats[sk] = bv
	# Affixes: pick N from the slot-eligible pool.
	var slot: String = base.get("slot", "")
	var pool := []
	for aid in AFFIX_DB:
		if (AFFIX_DB[aid]["limit_to"] as Array).has(slot):
			pool.append(aid)
	if pool.is_empty():
		for aid in AFFIX_DB:
			if AFFIX_DB[aid]["type"] in ["industrial", "economy"]:
				pool.append(aid)
	# v101 affix count per rarity: Uncommon 1, Rare 2, Legendary 3, Unique 4.
	var n: int = mini({1: 1, 2: 2, 3: 3, 4: 4}.get(rarity, 0), pool.size())
	pool.shuffle()
	var affixes := {}
	var greater_affixes := []
	for i in n:
		var aid: String = pool[i]
		var cfg: Dictionary = AFFIX_DB[aid]
		# v101 Greater Affix: 15% chance to pin value to range[1] * 2.0.
		var is_greater := randf() < 0.15
		var raw_val: float = float(cfg["range"][1]) * 2.0 if is_greater else float(randi_range(int(cfg["range"][0]), int(cfg["range"][1])))
		if is_greater:
			greater_affixes.append(aid)
		# Scaling modes (desktop generate_module_drop ~L2422-2430).
		var final_val := 0.0
		match cfg.get("scaling", "percent"):
			"flat": final_val = floor(raw_val * pow(1.8, maxi(0, zone_diff - 1)))
			"linear_tier": final_val = raw_val * zone_diff
			_: final_val = raw_val / 100.0
		affixes[aid] = final_val
	# Sockets: Unique = 3, Legendary = 1-3, Rare = 30% chance of 1.
	var sockets := []
	if rarity == 4:
		sockets = [null, null, null]
	elif rarity == 3:
		for _i in randi() % 3 + 1:
			sockets.append(null)
	elif rarity == 2 and randf() < 0.3:
		sockets = [null]
	var cid := "cm_%s_%d_%d" % [base_id, Time.get_ticks_msec(), randi() % 100000]
	custom_modules[cid] = {
		"name": "%s (%s)" % [base.get("name", base_id), RARITY_LABEL[rarity]],
		"slot": slot, "stats": stats, "desc": base.get("desc", ""),
		"rarity": rarity, "affixes": affixes, "base": base_id, "sockets": sockets,
		"greater_affixes": greater_affixes,
	}
	module_inventory[cid] = int(module_inventory.get(cid, 0)) + 1
	return cid

## Sum of an affix value across equipped (loadout) custom modules.
func affix_total(key: String) -> float:
	var s := 0.0
	for mid in loadout.values():
		if custom_modules.has(mid):
			s += float(custom_modules[mid].get("affixes", {}).get(key, 0.0))
	return s

func sell_module(mid: String) -> bool:
	if int(module_inventory.get(mid, 0)) <= 0:
		return false
	var price := 100
	var rarity := 0
	if custom_modules.has(mid):
		rarity = int(custom_modules[mid].get("rarity", 0))
		price = int(RARITY_SELL.get(rarity, 100))
	else:
		# Crafted modules: 25% of credit cost (desktop get_sell_price ~L2581).
		price = maxi(50, int(float(GameData.MODULES.get(mid, {}).get("cost", {}).get("credits", 200)) * 0.25))
		rarity = int(GameData.MODULES.get(mid, {}).get("rarity", 0))
	# v100 Demolish parity: grant RARITY_SPARE_PARTS alongside credits (ref ~L2571).
	# Mobile has no separate demolish action, so the spare-parts yield is folded into
	# the sell path (the SparePart element already exists in GameData).
	add_resource("SparePart", int(RARITY_SPARE_PARTS.get(rarity, 1)))
	module_inventory[mid] = int(module_inventory[mid]) - 1
	if module_inventory[mid] <= 0:
		module_inventory.erase(mid)
		if custom_modules.has(mid):
			custom_modules.erase(mid)
	gain_credits(price)
	resources_changed.emit()
	return true

# ---------------- Bounty board ----------------
signal bounty_changed

const BOUNTY_MAX_ACTIVE := 3
const BOUNTY_MAX_AVAIL := 6
const BOUNTY_REFRESH := 28800.0   # 8 hours
const DELIVERY_MATERIALS := {
	1: [["Cu", 500, 1000, 25000], ["Fe", 300, 600, 40000], ["Si", 200, 400, 30000]],
	2: [["Fe", 800, 1500, 100000], ["Cu", 300, 600, 75000], ["Steel", 100, 250, 150000]],
	3: [["Steel", 250, 500, 250000], ["Ti", 100, 250, 400000], ["Circuit", 100, 200, 300000]],
	4: [["Ti", 300, 600, 600000], ["W", 150, 300, 500000], ["Graphite", 200, 400, 400000]],
	5: [["AdvCircuit", 100, 200, 1250000], ["Superalloy", 50, 150, 1500000], ["NavData", 100, 250, 1000000]],
	6: [["ColonySalvage", 250, 500, 2000000], ["AdvCircuit", 150, 300, 1750000], ["Steel", 2000, 5000, 2500000]],
	7: [["RadIsotope", 200, 500, 3000000], ["Pt", 100, 250, 3750000], ["Superalloy", 150, 300, 2750000]],
	8: [["VoidCrystal", 50, 150, 5000000], ["Diamond", 30, 80, 4000000], ["ExoticMatter", 20, 50, 6000000]],
	9: [["BiohazardSample", 100, 250, 7500000], ["MutatedTissue", 50, 150, 9000000], ["PathogenCore", 20, 50, 10000000]],
	10: [["VoidEssence", 50, 100, 25000000], ["ChronoCore", 20, 50, 37500000], ["PrimordialShard", 10, 30, 50000000]],
}

var bounty_available: Array = []
var bounty_active: Array = []
var bounty_refresh_timer: float = 0.0
var bounty_total: int = 0
var _bounty_id := 0

func _gen_bid() -> String:
	_bounty_id += 1
	return "b%d" % _bounty_id

func bounty_max_diff() -> int:
	return clampi(1 + int(level_of("combat") / 4.0), 1, 10)

func _zones_in_range(mind: int, maxd: int) -> Array:
	var out := []
	for z in GameData.ZONES:
		var diff := int(z.get("difficulty", 1))
		if diff >= mind and diff <= maxd:
			out.append(z)
	return out

func generate_bounty_pool() -> void:
	bounty_available.clear()
	var maxd := bounty_max_diff()
	var mind := maxi(1, maxd - 1)
	var attempts := 0
	while bounty_available.size() < BOUNTY_MAX_AVAIL and attempts < 100:
		attempts += 1
		var c := {}
		var roll := randf()
		if roll < 0.4:
			c = _gen_hunt(mind, maxd, false)
		elif roll < 0.7:
			c = _gen_delivery(mind, maxd)
		else:
			c = _gen_hunt(maxd, maxd, true)
		if not c.is_empty():
			var dup := false
			for e in bounty_available:
				if e["target"] == c["target"] and e["type"] == c["type"] and e.get("is_elite", false) == c.get("is_elite", false):
					dup = true
					break
			if not dup:
				bounty_available.append(c)
	bounty_refresh_timer = BOUNTY_REFRESH
	bounty_changed.emit()

## Unlocked module ids dropped by a zone's enemies (for bounty rewards).
func _zone_module_pool(z: Dictionary) -> Array:
	var pool := []
	for eid in z.get("enemies", []):
		for mid in GameData.ENEMIES.get(eid, {}).get("drop_pool", []):
			if GameData.MODULES.has(mid) and module_unlocked(mid) and not pool.has(mid):
				pool.append(mid)
	return pool

func _gen_hunt(mind: int, maxd: int, elite: bool) -> Dictionary:
	var zs := _zones_in_range(mind, maxd)
	if zs.is_empty():
		return {}
	var z: Dictionary = zs[randi() % zs.size()]
	var ens: Array = z.get("enemies", [])
	if ens.is_empty():
		return {}
	var eid: String = ens[randi() % ens.size()]
	var e: Dictionary = GameData.ENEMIES.get(eid, {})
	if e.is_empty():
		return {}
	var diff := int(z.get("difficulty", 1))
	var base_xp := float(e.get("xp", 10))
	var qty := 1 if elite else randi_range(5, 20)
	var reward := int(base_xp * 300.0 * pow(diff, 1.5)) if elite else int(base_xp * qty * 5.0 * pow(diff, 1.8))
	var title := ("★ ELITE: %s" % e["name"]) if elite else ("Hunt: %s" % e["name"])
	var desc := "Destroy %s%d %s in %s." % ["the ELITE " if elite else "", qty, e["name"], z.get("name", "")]
	return {"id": _gen_bid(), "type": "hunt", "title": title, "desc": desc,
		"target": eid, "target_qty": qty, "current_qty": 0, "reward_credits": reward,
		"reward_pool": _zone_module_pool(z),
		"zone_id": z.get("id", ""), "difficulty": diff, "completed": false, "is_elite": elite}

func _gen_delivery(mind: int, maxd: int) -> Dictionary:
	var tier := randi_range(mind, maxd)
	var tmpl: Array = DELIVERY_MATERIALS.get(tier, [])
	if tmpl.is_empty():
		return {}
	var t: Array = tmpl[randi() % tmpl.size()]
	var qty := randi_range(int(t[1]), int(t[2]))
	var rpool := []
	for z in GameData.ZONES:
		if int(z.get("difficulty", 1)) == tier:
			rpool = _zone_module_pool(z)
			break
	return {"id": _gen_bid(), "type": "delivery", "title": "Supply: %s" % GameData.res_name(t[0]),
		"desc": "Deliver %d %s to the station." % [qty, GameData.res_name(t[0])],
		"target": t[0], "target_qty": qty, "current_qty": 0, "reward_credits": int(t[3]),
		"reward_pool": rpool, "zone_id": "", "difficulty": tier, "completed": false, "is_elite": false}

func _find_contract(arr: Array, cid: String) -> Variant:
	for c in arr:
		if c["id"] == cid:
			return c
	return null

func accept_contract(cid: String) -> bool:
	if bounty_active.size() >= BOUNTY_MAX_ACTIVE:
		return false
	var c = _find_contract(bounty_available, cid)
	if c == null:
		return false
	if c["type"] == "delivery":
		var need := int(c["target_qty"] * (1.0 - affix_total("logistician_edge")))  # Logistician's Edge
		if amount(c["target"]) < need:
			return false
		resources[c["target"]] = amount(c["target"]) - need
		c["current_qty"] = need
		c["completed"] = true
	bounty_available.erase(c)
	bounty_active.append(c)
	resources_changed.emit()
	bounty_changed.emit()
	return true

func claim_contract(cid: String) -> bool:
	var c = _find_contract(bounty_active, cid)
	if c == null or not c["completed"]:
		return false
	gain_credits(int(c["reward_credits"] * (1.0 + affix_total("contract_negotiation")) * credit_reward_mult()))  # Contract Negotiation + Recursive Acquisition
	# Module reward: bounties have a high rarity floor (Rare+).
	var rpool: Array = c.get("reward_pool", [])
	if not rpool.is_empty():
		var rarity := 3 if (int(c.get("difficulty", 1)) >= 8 or randf() < 0.25) else 2  # Legendary or Rare
		generate_module(rpool[randi() % rpool.size()], rarity, int(c.get("difficulty", 1)))
	bounty_active.erase(c)
	bounty_total += 1
	resources_changed.emit()
	bounty_changed.emit()
	return true

func abandon_contract(cid: String) -> bool:
	var c = _find_contract(bounty_active, cid)
	if c == null:
		return false
	if c["type"] == "delivery" and int(c["current_qty"]) > 0:
		resources[c["target"]] = amount(c["target"]) + int(c["current_qty"])
	bounty_active.erase(c)
	resources_changed.emit()
	bounty_changed.emit()
	return true

func bounty_refresh_cost() -> int:
	return bounty_max_diff() * 5000

func force_refresh_bounty() -> bool:
	var cost := bounty_refresh_cost()
	if credits < cost:
		return false
	credits -= cost
	generate_bounty_pool()
	resources_changed.emit()
	return true

func bounty_on_kill(eid: String) -> void:
	var changed := false
	for c in bounty_active:
		if c["type"] == "hunt" and c["target"] == eid and not c["completed"]:
			c["current_qty"] = mini(int(c["current_qty"]) + 1, int(c["target_qty"]))
			if int(c["current_qty"]) >= int(c["target_qty"]):
				c["completed"] = true
			changed = true
	if changed:
		bounty_changed.emit()

# ---------------- Standing Orders board ----------------
# Faithful port of ref_quest_manager.gd. A SECOND quest board, distinct from
# Bounties: 6 passive-tracked slots (gather / hunt non-boss), 55/45 split,
# instant claim with auto-replacement (no accept/abandon), material rewards from
# a DEDICATED per-tier table (distinct from bounty delivery materials), manual
# reroll at 2500×max_diff credits, no timed refresh.
signal standing_orders_changed

const STANDING_BOARD_SIZE := 6
const STANDING_REROLL_BASE := 2500
# Per-tier material reward pool: [material_id, min_qty, max_qty] (ref ~L13-24).
const STANDING_MATERIAL_REWARDS := {
	1: [["Cu", 100, 250], ["Fe", 80, 180], ["Si", 50, 150]],
	2: [["Steel", 40, 100], ["Cu", 200, 500], ["Circuit", 25, 60]],
	3: [["Ti", 60, 150], ["Steel", 150, 350], ["AdvCircuit", 30, 80]],
	4: [["W", 80, 200], ["Ti", 200, 450], ["Graphite", 100, 250]],
	5: [["Superalloy", 30, 80], ["AdvCircuit", 80, 200], ["NavData", 50, 120]],
	6: [["AdvCircuit", 150, 350], ["ColonySalvage", 100, 250], ["Superalloy", 60, 150]],
	7: [["RadIsotope", 80, 200], ["Pt", 50, 120], ["Superalloy", 100, 250]],
	8: [["VoidCrystal", 20, 60], ["Diamond", 15, 40], ["ExoticMatter", 10, 30]],
	9: [["BiohazardSample", 40, 100], ["MutatedTissue", 25, 70], ["PathogenCore", 10, 25]],
	10: [["VoidEssence", 20, 50], ["ChronoCore", 10, 25], ["PrimordialShard", 5, 15]],
}

var standing_board: Array = []
var standing_total: int = 0
var _standing_id := 0

func standing_orders() -> Array:
	return standing_board

func _gen_sid() -> String:
	_standing_id += 1
	return "so%d" % _standing_id

## Max difficulty from zones whose research gate is unlocked (ref _get_max_difficulty).
func standing_max_diff() -> int:
	var md := 1
	for z in GameData.ZONES:
		var req: String = z.get("research_req", "")
		if req == "" or is_research_unlocked(req):
			md = maxi(md, int(z.get("difficulty", 1)))
	return md

func _standing_fill() -> void:
	var attempts := 0
	while standing_board.size() < STANDING_BOARD_SIZE and attempts < 100:
		attempts += 1
		var q := _gen_standing_order()
		if not q.is_empty():
			standing_board.append(q)
	standing_orders_changed.emit()

func _gen_standing_order() -> Dictionary:
	var maxd := standing_max_diff()
	var mind := maxi(1, maxd - 1)
	# 55% gather, 45% hunt (non-boss).
	if randf() < 0.55:
		return _gen_standing_gather(mind, maxd)
	return _gen_standing_hunt(mind, maxd)

## Retry wrapper for single-slot replacement: a lone empty roll (e.g. a tier with
## no delivery-material template, or no valid hunt zone) must never shrink the
## board below STANDING_BOARD_SIZE. Falls back through the type split a few times.
func _gen_standing_order_retry() -> Dictionary:
	for _i in 20:
		var q := _gen_standing_order()
		if not q.is_empty():
			return q
	return {}

func _gen_standing_gather(mind: int, maxd: int) -> Dictionary:
	# DELIVERY_MATERIALS tops out at tier 10; clamp so high-zone (Z11) players
	# still draw gather orders instead of always rolling empty at tier 11.
	var tier := mini(randi_range(mind, maxd), 10)
	var tmpl: Array = DELIVERY_MATERIALS.get(tier, [])
	if tmpl.is_empty():
		return {}
	var t: Array = tmpl[randi() % tmpl.size()]
	var mat_id: String = t[0]
	# Orders demand smaller quantities than bounties (they aren't consumed).
	# Floor at 1 so a small material range can never produce a 0/0 auto-complete.
	var qty := maxi(1, int(randf_range(float(t[1]), float(t[2])) * 0.6))
	var credits_r := int(float(t[3]) * 0.4)
	var dn := GameData.res_name(mat_id)
	return {
		"id": _gen_sid(), "type": "gather",
		"title": "Stockpile: %s" % dn,
		"desc": "Acquire %d units of %s." % [qty, dn],
		"target": mat_id, "target_qty": qty, "current_qty": 0,
		"reward_credits": credits_r, "reward_material": _roll_standing_material(tier),
		"difficulty": tier, "completed": false, "claimed": false,
	}

func _gen_standing_hunt(mind: int, maxd: int) -> Dictionary:
	var valid := _zones_in_range(mind, maxd)
	if valid.is_empty():
		return {}
	var z: Dictionary = valid[randi() % valid.size()]
	var diff := int(z.get("difficulty", 1))
	# Prefer non-boss for orders; bosses are bounty territory.
	var non_boss := []
	for eid in z.get("enemies", []):
		if not GameData.ENEMIES.get(eid, {}).get("is_boss", false):
			non_boss.append(eid)
	if non_boss.is_empty():
		non_boss = z.get("enemies", [])
	if non_boss.is_empty():
		return {}
	var enemy_id: String = non_boss[randi() % non_boss.size()]
	var e: Dictionary = GameData.ENEMIES.get(enemy_id, {})
	if e.is_empty():
		return {}
	var qty := randi_range(8, 20)
	var base_xp := float(e.get("xp", 10))
	var diff_mult := pow(float(diff), 1.4)
	var credit_reward := int(base_xp * qty * 10.0 * diff_mult)
	return {
		"id": _gen_sid(), "type": "hunt",
		"title": "Sweep: %s" % e.get("name", enemy_id),
		"desc": "Destroy %d %s in %s." % [qty, e.get("name", enemy_id), z.get("name", "")],
		"target": enemy_id, "target_qty": qty, "current_qty": 0,
		"reward_credits": credit_reward, "reward_material": _roll_standing_material(diff),
		"difficulty": diff, "completed": false, "claimed": false,
	}

func _roll_standing_material(tier: int) -> Dictionary:
	# 60% chance to roll a material reward in addition to credits.
	if randf() > 0.6:
		return {}
	var pool: Array = STANDING_MATERIAL_REWARDS.get(tier, [])
	if pool.is_empty():
		return {}
	var pick: Array = pool[randi() % pool.size()]
	return {"id": pick[0], "qty": randi_range(int(pick[1]), int(pick[2]))}

## Increment gather progress on resource gain (ref _on_element_added). Progress is
## additive (not re-read from inventory) so spending materials never regresses it.
func _standing_track_gather(sym: String, amt: int) -> void:
	if standing_board.is_empty():
		return
	var changed := false
	for q in standing_board:
		if q.get("claimed", false) or q.get("completed", false) or q["type"] != "gather":
			continue
		if q["target"] == sym:
			q["current_qty"] = mini(int(q["current_qty"]) + amt, int(q["target_qty"]))
			if int(q["current_qty"]) >= int(q["target_qty"]):
				q["completed"] = true
			changed = true
	if changed:
		standing_orders_changed.emit()

## Pull current inventory levels into gather orders so existing stockpiles count.
func sync_standing_gather() -> void:
	var changed := false
	for q in standing_board:
		if q.get("claimed", false) or q["type"] != "gather":
			continue
		var have := amount(q["target"])
		if have > int(q["current_qty"]):
			q["current_qty"] = mini(have, int(q["target_qty"]))
			if int(q["current_qty"]) >= int(q["target_qty"]):
				q["completed"] = true
			changed = true
	if changed:
		standing_orders_changed.emit()

## Hunt progress on enemy kill (called from _win_combat).
func standing_on_kill(eid: String) -> void:
	var changed := false
	for q in standing_board:
		if q.get("claimed", false) or q.get("completed", false) or q["type"] != "hunt":
			continue
		if q["target"] == eid:
			q["current_qty"] = mini(int(q["current_qty"]) + 1, int(q["target_qty"]))
			if int(q["current_qty"]) >= int(q["target_qty"]):
				q["completed"] = true
			changed = true
	if changed:
		standing_orders_changed.emit()

func _find_standing(i: int) -> Variant:
	if i < 0 or i >= standing_board.size():
		return null
	return standing_board[i]

## Instant claim: grants credits + material reward (ref claim_quest ~L199-235),
## then auto-replaces the slot. The slot is removed BEFORE rewards are granted so
## the add_resource hook (which re-emits standing_orders_changed) never rebuilds
## the board with the just-claimed order still showing a Claim button.
func claim_standing_order(i: int) -> bool:
	var q = _find_standing(i)
	if q == null or not q.get("completed", false) or q.get("claimed", false):
		return false
	var cred := int(float(q["reward_credits"]) * warp_production_mult() * credit_reward_mult())
	var mat: Dictionary = q.get("reward_material", {})
	q["claimed"] = true
	standing_total += 1
	standing_board.remove_at(i)
	# Replace first so the board is whole before reward side effects fire.
	var fresh := _gen_standing_order_retry()
	if not fresh.is_empty():
		standing_board.append(fresh)
	gain_credits(cred)
	if not mat.is_empty():
		add_resource(mat["id"], int(mat["qty"]))
	resources_changed.emit()
	standing_orders_changed.emit()
	return true

func standing_reroll_cost() -> int:
	return STANDING_REROLL_BASE * standing_max_diff()

## Manual reroll: keep completed-but-unclaimed orders, reroll the rest.
func reroll_standing_orders() -> bool:
	var cost := standing_reroll_cost()
	if credits < cost:
		return false
	credits -= cost
	var kept := []
	for q in standing_board:
		if q.get("completed", false) and not q.get("claimed", false):
			kept.append(q)
	standing_board = kept
	_standing_fill()
	resources_changed.emit()
	standing_orders_changed.emit()
	return true

func ensure_standing_board() -> void:
	if standing_board.is_empty():
		_standing_fill()
	else:
		sync_standing_gather()

# ---------------- Infrastructure ----------------
# ── v109 Infrastructure rebalance (ported from ref_infrastructure_manager.gd
# P0/P1 constants ~L14-42). Mobile previously ran the old over-scaled formulas;
# these bring it to desktop parity. ──
# P0.3: cap the engineering yield bonus (was 1+log10(1+fab)*5 → ~11x at fab 99).
const INFRA_ENG_SCALE_COEF := 1.0   # log coefficient (was 5.0)
const INFRA_ENG_SCALE_CAP := 3.0    # hard ceiling on the engineering multiplier
# P0.2: diminishing returns on stacked buildings — linear to KNEE, then a
# saturating tail (asymptote = KNEE + TAIL).
const INFRA_DR_KNEE := 10
const INFRA_DR_TAIL := 10
# Single source of truth for engineering-scaled buildings. munitions_factory is
# carried verbatim from desktop (a dead id — no such building — kept for parity).
const INFRA_ENG_SCALED_BUILDINGS := ["auto_smelter", "hydro_plant", "industrial_centrifuge",
	"munitions_factory", "titanium_refinery", "superalloy_forge", "adv_circuit_foundry"]
# P1.4: gathering owns the ore tier — raw ore/metal extractors are throttled so
# active gathering is the primary source and infra ore-mining is a trickle.
const INFRA_ORE_EXTRACTION_MULT := 0.5
const INFRA_ORE_EXTRACTORS := ["lithium_extractor", "brine_extractor", "copper_mine",
	"deep_crust_drill", "tin_mine", "quartz_mine", "quartz_excavator", "zinc_mine",
	"bauxite_mine", "bauxite_miner", "dolomite_quarry", "manganese_dredge", "nickel_mine",
	"chromite_excavator", "tungsten_drill", "germanite_excavator", "platinum_drill",
	"precious_dredge", "iridium_drill", "osmium_condenser"]
# v104: continuous building-upkeep sink. Every building drains a little of the
# cheapest glut mats per interval; per-building cost grows with total count.
# Drain-if-available only — never goes negative, never punishes AFK.
const UPKEEP_INTERVAL := 60.0
const UPKEEP_BASE := {"Water": 2.0, "Dirt": 1.0}   # per building, per interval, pre-growth
const UPKEEP_COUNT_GROWTH := 0.05                   # +5% per-building cost per building owned
const UPKEEP_GROWTH_CAP := 8.0                      # growth multiplier ceiling
var _upkeep_timer: float = 0.0
# P2.6: proportional upkeep throttle — when upkeep mats run short buildings
# produce at the affordable fraction. Transient (recomputed; not saved).
var upkeep_efficiency: float = 1.0

# P0.3: capped engineering yield multiplier (single source of truth — used by
# _produce_batch AND building_rate_text so the UI can't disagree with reality).
func _eng_scale(bid: String) -> float:
	if not bid in INFRA_ENG_SCALED_BUILDINGS:
		return 1.0
	return clampf(1.0 + (log(1.0 + level_of("fabrication")) / log(10.0)) * INFRA_ENG_SCALE_COEF,
		1.0, INFRA_ENG_SCALE_CAP)

# P0.2: diminishing returns on stacked buildings. Linear up to KNEE, then a
# saturating tail (ceiling = KNEE + TAIL). Applied to BOTH yield and input so
# surplus buildings idle rather than burn inputs for no extra output.
func _dr_units(count: int) -> float:
	if count <= INFRA_DR_KNEE:
		return float(count)
	var extra := float(count - INFRA_DR_KNEE)
	return float(INFRA_DR_KNEE) + extra / (1.0 + extra / float(INFRA_DR_TAIL))

# P1.4: yield multiplier for raw ore extractors (gathering owns the ore tier).
func _ore_throttle(bid: String) -> float:
	return INFRA_ORE_EXTRACTION_MULT if bid in INFRA_ORE_EXTRACTORS else 1.0

# v104: charge `intervals` full upkeep periods (1 online, many for offline
# catch-up). Drain-if-available only. Returns {res: consumed} for reporting.
func _apply_upkeep(intervals: int) -> Dictionary:
	var consumed := {}
	if intervals <= 0:
		return consumed
	var total := 0
	for bid in buildings:
		total += maxi(0, int(buildings[bid]))
	if total <= 0:
		return consumed
	var growth: float = minf(UPKEEP_GROWTH_CAP, 1.0 + float(total) * UPKEEP_COUNT_GROWTH)
	for res in UPKEEP_BASE:
		var demand: float = float(UPKEEP_BASE[res]) * float(total) * growth * float(intervals)
		if demand <= 0.0:
			continue
		var take: float = minf(demand, amount(res))   # never negative, never a hard gate
		if take > 0.0:
			resources[res] = amount(res) - take
			consumed[res] = take
			_infra_dirty = true
	return consumed

# P2.6: affordable fraction of upkeep for `intervals` periods WITHOUT consuming
# — the bottleneck (min) ratio across upkeep resources.
func _upkeep_efficiency_for(intervals: int) -> float:
	if intervals <= 0:
		return 1.0
	var total := 0
	for bid in buildings:
		total += maxi(0, int(buildings[bid]))
	if total <= 0:
		return 1.0
	var growth: float = minf(UPKEEP_GROWTH_CAP, 1.0 + float(total) * UPKEEP_COUNT_GROWTH)
	var eff := 1.0
	for res in UPKEEP_BASE:
		var demand: float = float(UPKEEP_BASE[res]) * float(total) * growth * float(intervals)
		if demand <= 0.0:
			continue
		eff = minf(eff, clampf(amount(res) / demand, 0.0, 1.0))
	return eff

func building_count(bid: String) -> int:
	return int(buildings.get(bid, 0))

func get_throttle(bid: String) -> float:
	return float(building_throttle.get(bid, 1.0))

func set_throttle(bid: String, v: float) -> void:
	building_throttle[bid] = clampf(v, 0.0, 1.0)
	resources_changed.emit()

func _is_fuel_gen(d: Dictionary) -> bool:
	return float(d.get("energy_gen", 0.0)) > 0.0 and not d.get("input", {}).is_empty()

## Returns {"gen": kW, "cons": kW, "eff": 0..1}. Nominal readout for the UI
## (assumes fuel available); the live tick also banks/drains the grid battery.
func infra_power() -> Dictionary:
	var gen := 0.0
	var cons := 0.0
	for bid in buildings:
		var d: Dictionary = GameData.BUILDINGS.get(bid, {})
		var t := get_throttle(bid)
		gen += float(d.get("energy_gen", 0.0)) * buildings[bid] * t
		cons += float(d.get("energy_cons", 0.0)) * buildings[bid] * t
	if level_of("infrastructure") >= 10:
		gen *= 1.10                                       # milestone 10: +10% generation
	var eff := 1.0 if cons <= gen or cons <= 0.0 else gen / cons
	return {"gen": gen, "cons": cons, "eff": eff}

func _global_yield_bonus() -> Dictionary:
	var gyb := {}
	for bid in buildings:
		var yb: Dictionary = GameData.BUILDINGS.get(bid, {}).get("yield_bonus", {})
		for res in yb:
			gyb[res] = gyb.get(res, 0.0) + float(yb[res]) * buildings[bid]
	return gyb

func _infra_skill_speed() -> float:
	# Desktop get_effective_interval uses only the Industrial Logistics hub bonus.
	# (industrial_catalysis is a processing-speed bonus, applied in recipe_speed_mult.)
	return 1.0 + level_of("infrastructure") * 0.01 + research_bonus("industrial_logistics")

## Energy phase: pure generators always run; fuel generators run at 100% (ignoring
## grid efficiency) to jumpstart, consuming fuel; surplus banks into the grid
## battery (capacity = ship energy_cap) and is drained to cover deficits.
## Returns grid efficiency 0..1 for the production phase.
func _infra_energy_step(delta: float) -> float:
	var skill_speed := _infra_skill_speed()
	var gen := 0.0
	var cons := 0.0
	for bid in buildings:
		var count: int = buildings[bid]
		if count <= 0:
			continue
		var d: Dictionary = GameData.BUILDINGS.get(bid, {})
		var t := get_throttle(bid)
		cons += float(d.get("energy_cons", 0.0)) * count * t
		var eg := float(d.get("energy_gen", 0.0))
		if eg <= 0.0:
			continue
		if d.get("input", {}).is_empty():
			gen += eg * count * t                          # pure generator (solar)
		else:
			var ei: float = maxf(0.05, float(d.get("interval", 1.0)) / skill_speed)
			var inp: Dictionary = d["input"]
			var can_fuel := true
			for res in inp:
				if amount(res) < float(inp[res]) * count * t * (delta / ei):
					can_fuel = false
					break
			if can_fuel:
				# Fractional fuel draw accumulated so small per-frame amounts don't
				# round up to a whole unit every frame.
				for res in inp:
					var need := float(inp[res]) * count * t * (delta / ei)
					_fuel_frac[res] = float(_fuel_frac.get(res, 0.0)) + need
					var whole := int(_fuel_frac[res])
					if whole > 0:
						resources[res] = amount(res) - whole
						_fuel_frac[res] = float(_fuel_frac[res]) - whole
						_infra_dirty = true
				gen += eg * count * t
	if level_of("infrastructure") >= 10:
		gen *= 1.10
	var cap: float = ship_stats().get("energy_cap", 0.0)
	var net := gen - cons
	if net >= 0.0:
		infra_energy = minf(cap, infra_energy + net * delta)
		return 1.0
	var deficit := -net * delta
	if infra_energy >= deficit:
		infra_energy -= deficit
		return 1.0
	if infra_energy > 0.0:
		var eff := infra_energy / deficit
		infra_energy = 0.0
		return eff
	return 0.0

func _tick_infra(delta: float) -> void:
	if buildings.is_empty():
		return
	var eff := _infra_energy_step(delta)
	var skill_speed := _infra_skill_speed()
	var gyb := _global_yield_bonus()
	# v109 P2.6: production advances at energy_eff * upkeep_eff (last cycle's throttle).
	var prod_eff := eff * upkeep_efficiency
	for bid in buildings:
		var count: int = buildings[bid]
		if count <= 0:
			continue
		var d: Dictionary = GameData.BUILDINGS.get(bid, {})
		if d.get("special", "") == "passive_gather":
			_passive_gather_step(bid, count, delta * prod_eff)
			continue
		# Process producers AND upkeep consumers (e.g. Crew Quarters' Food); skip
		# pure/fuel generators (handled in the energy step).
		if not _is_production_building(d):
			continue
		var eff_interval: float = maxf(0.05, float(d.get("interval", 1.0)) / skill_speed)
		var t := get_throttle(bid)
		_build_timers[bid] = float(_build_timers.get(bid, 0.0)) + delta * prod_eff * t
		var guard := 0
		while float(_build_timers[bid]) >= eff_interval and guard < 200:
			guard += 1
			_build_timers[bid] = float(_build_timers[bid]) - eff_interval
			_produce_batch(bid, count, d, gyb)
	# v104: continuous upkeep sink — only charged while the grid is live, so an
	# idle/unpowered base never bleeds mats. Accumulate then charge whole intervals.
	if eff > 0.0:
		_upkeep_timer += delta
		if _upkeep_timer >= UPKEEP_INTERVAL:
			var n: int = int(_upkeep_timer / UPKEEP_INTERVAL)
			_upkeep_timer -= float(n) * UPKEEP_INTERVAL
			upkeep_efficiency = _upkeep_efficiency_for(n)   # P2.6 throttle for next cycle
			_apply_upkeep(n)

func _is_production_building(d: Dictionary) -> bool:
	if not d.get("yield", {}).is_empty():
		return true
	# Upkeep consumer (has input, isn't a generator) — e.g. Crew Quarters.
	return not d.get("input", {}).is_empty() and float(d.get("energy_gen", 0.0)) <= 0.0

## Drone Recovery Bay: every 10s, each bay has a 25% chance to roll one entry
## from a random unlocked gathering action's loot table (desktop passive_gather).
func _passive_gather_step(bid: String, count: int, eff_delta: float) -> void:
	var key := "_pg_" + bid
	_build_timers[key] = float(_build_timers.get(key, 0.0)) + eff_delta
	while float(_build_timers[key]) >= 10.0:
		_build_timers[key] = float(_build_timers[key]) - 10.0
		_passive_gather_roll(count)
		add_resource("Cu", count)   # v109: guaranteed +1 Cu/bay/10s (ref ~L1507)

func _passive_gather_roll(bays: int) -> void:
	var unlocked := []
	for aid in GameData.GATHER:
		var a: Dictionary = GameData.GATHER[aid]
		if level_of("harvesting") < int(a.get("level_req", 1)):
			continue
		var req: String = a.get("research_req", "")
		if req != "" and not is_research_unlocked(req):
			continue
		if not a.get("loot", []).is_empty():
			unlocked.append(a)
	if unlocked.is_empty():
		return
	for _i in range(bays):
		if randf() < 0.25:
			var a: Dictionary = unlocked.pick_random()
			var row = (a["loot"] as Array).pick_random()
			add_resource(row[0], maxi(1, randi_range(int(row[2]), int(row[3]))))

## Offline infrastructure catch-up: runs the grid + production over `delta`,
## returns a short loot summary (or "").
func _offline_infra(delta: float) -> String:
	if buildings.is_empty():
		return ""
	var eff := _infra_energy_step(delta)
	if eff <= 0.0:
		return ""
	var skill_speed := _infra_skill_speed()
	var gyb := _global_yield_bonus()
	# v109 P2.6: throttle offline production by the upkeep fraction the player can
	# afford over the away window (the actual drain happens once at the end).
	upkeep_efficiency = _upkeep_efficiency_for(int(delta / UPKEEP_INTERVAL))
	var prod_eff := eff * upkeep_efficiency
	var before := {}
	for sym in resources:
		before[sym] = amount(sym)
	var cr_before := credits
	for bid in buildings:
		var count: int = buildings[bid]
		if count <= 0:
			continue
		var d: Dictionary = GameData.BUILDINGS.get(bid, {})
		if d.get("special", "") == "passive_gather":
			var pg_cycles: int = int(delta * prod_eff * get_throttle(bid) / 10.0)
			for _p in range(mini(pg_cycles, 500000)):
				_passive_gather_roll(count)
			if pg_cycles > 0:
				add_resource("Cu", count * mini(pg_cycles, 500000))   # v109 guaranteed Cu
			continue
		if not _is_production_building(d):
			continue
		var eff_interval: float = maxf(0.05, float(d.get("interval", 1.0)) / skill_speed)
		var cycles: int = int(delta * prod_eff * get_throttle(bid) / eff_interval)
		for _i in range(mini(cycles, 500000)):
			_produce_batch(bid, count, d, gyb)            # self-limits when feedstock runs out
		if cycles > 0:
			add_xp("infrastructure", mini(cycles, 500000))
	# v104: offline upkeep — closed-form, whole intervals only.
	_apply_upkeep(int(delta / UPKEEP_INTERVAL))
	var parts := []
	for sym in resources:
		var made := amount(sym) - int(before.get(sym, 0))
		if made > 0:
			parts.append("+%s %s" % [GameData.fmt(made), GameData.res_name(sym)])
	if credits - cr_before > 0:
		parts.append("+₡%s" % GameData.fmt(credits - cr_before))
	if parts.is_empty():
		return ""
	return "Infrastructure: " + ", ".join(parts)

func _produce_batch(bid: String, count: int, d: Dictionary, gyb: Dictionary) -> void:
	# v109 P0.2: diminishing returns — effective units replace raw count on BOTH
	# input draw and yield, so over-stacked buildings idle instead of burning feed.
	var units := _dr_units(count)
	var inp: Dictionary = d.get("input", {})
	for res in inp:
		if amount(res) < float(inp[res]) * units:
			return  # not enough fuel/feedstock this cycle
	for res in inp:
		resources[res] = amount(res) - float(inp[res]) * units
		_infra_dirty = true
	# v109: Recursive Networking (infrastructure_focus) — infinite +5%/level building yield.
	var net_mult := 1.0 + research_bonus("building_yield_mult")
	var eng := _eng_scale(bid)              # P0.3 capped engineering scaling
	var ore := _ore_throttle(bid)           # P1.4 ore tier handed to gathering
	for res in d.get("yield", {}):
		var qty := float(d["yield"][res]) * units * eng * ore * (1.0 + float(gyb.get(res, 0.0))) * warp_production_mult() * net_mult
		_build_frac[res] = float(_build_frac.get(res, 0.0)) + qty
		var whole := int(_build_frac[res])
		if whole > 0:
			_build_frac[res] = float(_build_frac[res]) - whole
			if res == "credits":
				gain_credits(whole)
			else:
				resources[res] = amount(res) + whole
			_infra_dirty = true
	# Research-gated byproducts (desktop _produce_batch ~L1456-1468): statistical
	# expectation of 0.2 per effective unit, accumulated fractionally.
	if bid == "hydro_plant" and is_research_unlocked("fluid_dynamics"):
		_infra_byproduct("N", units * 0.2)
	elif bid == "industrial_centrifuge" and is_research_unlocked("advanced_mineralogy"):
		_infra_byproduct("Ti", units * 0.2)
	add_xp("infrastructure", 1)

## Accumulate a fractional byproduct expectation and bank whole units.
func _infra_byproduct(res: String, expected: float) -> void:
	var key := "_bp_" + res
	_build_frac[key] = float(_build_frac.get(key, 0.0)) + expected
	var whole := int(_build_frac[key])
	if whole > 0:
		_build_frac[key] = float(_build_frac[key]) - whole
		resources[res] = amount(res) + whole
		_infra_dirty = true

func _credit_mult(c: int) -> float:
	if c < 10: return pow(1.15, c)
	if c < 25: return pow(1.15, 10) * pow(1.24, c - 10)
	return pow(1.15, 10) * pow(1.24, 15) * pow(1.32, c - 25)

func _item_mult(c: int) -> float:
	if c < 10: return pow(1.15, c)
	if c < 25: return pow(1.15, 10) * pow(1.20, c - 10)
	return pow(1.15, 10) * pow(1.20, 15) * pow(1.26, c - 25)

func building_cost(bid: String) -> Dictionary:
	var d: Dictionary = GameData.BUILDINGS.get(bid, {})
	var c := building_count(bid)
	var out := {}
	for res in d.get("cost", {}):
		var base := float(d["cost"][res])
		var m: float = _credit_mult(c) if res == "credits" else _item_mult(c)
		out[res] = int(ceil(base * m))
	return out

func building_unlocked(bid: String) -> bool:
	var rr: String = GameData.BUILDINGS.get(bid, {}).get("research_req", "")
	return rr == "" or is_research_unlocked(rr)

func building_can_afford(bid: String) -> bool:
	var d: Dictionary = GameData.BUILDINGS.get(bid, {})
	if not building_unlocked(bid):
		return false
	if d.has("max") and building_count(bid) >= int(d["max"]):
		return false
	var cost := building_cost(bid)
	for res in cost:
		if res == "credits":
			if credits < int(cost[res]):
				return false
		elif amount(res) < int(cost[res]):
			return false
	return true

func build_building(bid: String) -> bool:
	if not building_can_afford(bid):
		return false
	var cost := building_cost(bid)
	for res in cost:
		if res == "credits":
			credits -= int(cost[res])
		else:
			resources[res] = amount(res) - int(cost[res])
	buildings[bid] = building_count(bid) + 1
	_mission_event("build", bid, 1)
	resources_changed.emit()
	return true

# ---------------- Research ----------------
func is_research_unlocked(rid: String) -> bool:
	return unlocked_research.has(rid)

# --- Research passive efficiency bonuses (ported from research_manager) ---
func research_efficiency_mult() -> float:
	if is_research_unlocked("efficiency_5"): return 32.0
	if is_research_unlocked("efficiency_4"): return 16.0
	if is_research_unlocked("efficiency_3"): return 8.0
	if is_research_unlocked("efficiency_2"): return 4.0
	if is_research_unlocked("efficiency_1"): return 2.0
	return 1.0

func auto_consume_threshold() -> float:
	if is_research_unlocked("auto_repair_80"): return 0.8
	if is_research_unlocked("auto_repair_60"): return 0.6
	if is_research_unlocked("auto_repair_40"): return 0.4
	if is_research_unlocked("auto_repair_20"): return 0.2
	return 0.0

# Faithful port of ref_research_manager.gd::get_efficiency_bonus (v105/v109):
# accumulate into a single bonus (no early returns), and the repeatable-research
# loop ALWAYS applies for every bonus_type (the v105 fix that un-broke the
# Recursive Optimization / Calibration / Logistics / Networking endgame sinks).
func research_bonus(key: String) -> float:
	var bonus := 0.0
	match key:
		"combat_xp":
			if is_research_unlocked("combat_heuristics"): bonus += 0.20
		"shield_regen":
			if is_research_unlocked("shield_harmonics"): bonus += 0.20
		"max_hp_mult":
			if is_research_unlocked("hull_hardening"): bonus += 0.15
		"attack_speed":
			if is_research_unlocked("core_overclocking"): bonus += 0.10
		"gathering_yield":
			if is_research_unlocked("deep_core_optics"): bonus += 1.0
			if is_research_unlocked("colony_automation"): bonus += 5.0
		"processing_speed":
			if is_research_unlocked("nano_fabrication"): bonus += 0.15
			if is_research_unlocked("perfect_automation"): bonus += 0.30
			# v105b: folded into processing speed, bumped 0.15 -> 0.25.
			if is_research_unlocked("industrial_catalysis"): bonus += 0.25
		"research_speed":
			if is_research_unlocked("perfect_automation"): bonus += 0.30
	# Hub node passive bonuses (desktop Audit v8.0 P1-25).
	if key == "applied_physics" and is_research_unlocked("applied_physics"): bonus += 0.10
	if key == "materials_science" and is_research_unlocked("materials_science"): bonus += 0.10
	if key == "industrial_logistics" and is_research_unlocked("industrial_logistics"): bonus += 0.10
	if key == "xeno_engineering" and is_research_unlocked("xeno_engineering"): bonus += 0.25
	# Recursive (infinite endgame) bonuses — always summed, for every bonus_type.
	bonus += _repeatable_bonus(key)
	return bonus

# ---- Repeatable / Recursion research (infinite +5%/level sinks) ----
# Definitions live in GameData.REPEATABLE (generated from repeatable_tech.json),
# matching the desktop repeatable_tech_db. Exposed via these getters so existing
# call sites (and main.gd's GameState.REPEATABLE / REPEATABLE_ORDER reads) keep
# working without an autoload-in-const dependency.
var REPEATABLE: Dictionary = GameData.REPEATABLE
var REPEATABLE_ORDER: Array = GameData.REPEATABLE_ORDER
var repeatable_research: Dictionary = {}   # id -> level

# v109 Recursive Acquisition (wealth_focus): +5%/level Lira from combat, quests
# & bounties. Returns a multiplier (1.0 + credit_reward_mult bonus).
func credit_reward_mult() -> float:
	return 1.0 + research_bonus("credit_reward_mult")

func _repeatable_bonus(bonus_type: String) -> float:
	var b := 0.0
	for rid in repeatable_research:
		var rd: Dictionary = REPEATABLE.get(rid, {})
		if rd.get("bonus_type", "") == bonus_type:
			b += int(repeatable_research[rid]) * float(rd.get("bonus_value", 0.0))
	return b

func repeatable_level(rid: String) -> int:
	return int(repeatable_research.get(rid, 0))

func repeatable_cost(rid: String) -> Dictionary:
	var rd: Dictionary = REPEATABLE[rid]
	var lvl := repeatable_level(rid)
	var c := {"credits": int(float(rd["base_cost"]) * pow(1.3, lvl))}
	for res in rd.get("items", {}):
		c[res] = int(float(rd["items"][res]) * pow(1.2, lvl))
	return c

func can_unlock_repeatable(rid: String) -> bool:
	var c := repeatable_cost(rid)
	if credits < int(c["credits"]):
		return false
	for res in c:
		if res == "credits":
			continue
		if amount(res) < int(c[res]):
			return false
	return true

func unlock_repeatable(rid: String) -> bool:
	if not can_unlock_repeatable(rid):
		return false
	var c := repeatable_cost(rid)
	credits -= int(c["credits"])
	for res in c:
		if res != "credits":
			resources[res] = amount(res) - int(c[res])
	repeatable_research[rid] = repeatable_level(rid) + 1
	research_changed.emit()
	return true

# Full-repair (100% missing HP) cost per hull. Desktop's get_full_repair_cost
# (ref ~L2166-2174) only defines 5 tiers; the other 5 are filled in here with
# monotonic tier-scaled values (desktop is itself incomplete — see Phase 7 notes):
# t1 1k, t2 5k, t3 25k, t4 50k, t5 100k, t6 200k, t7 300k, t8 500k, t9 1M, t10 2M.
const REPAIR_COST := {"corvette_hull": 1000, "frigate_hull": 5000, "destroyer_hull": 25000,
	"cruiser_hull": 50000, "battlecruiser_hull": 100000, "capital_hull": 200000,
	"carrier_hull": 300000, "dreadnought_hull": 500000, "titan_hull": 1000000,
	"leviathan_hull": 2000000}

## Repair cost scales with damage taken (desktop get_repair_cost ~L2176-2185):
## 0 at full HP, max(10, full_cost * missing/max) otherwise.
func repair_cost() -> int:
	var maxhp := combat_max_hp()
	if maxhp <= 0.0 or combat_hp >= maxhp:
		return 0
	var full := float(REPAIR_COST.get(active_hull, 1000))
	var ratio := (maxhp - combat_hp) / maxhp
	return maxi(10, int(full * ratio))

func repair_hull() -> bool:
	if combat_hp >= combat_max_hp():
		return false
	var cost := repair_cost()
	if credits < cost:
		return false
	credits -= cost
	combat_hp = combat_max_hp()
	resources_changed.emit()
	return true

# --- Missions ---
func _mission_init() -> void:
	if missions_active.is_empty() and missions_claimed.is_empty() and not GameData.MISSION_ORDER.is_empty():
		missions_active[GameData.MISSION_ORDER[0]] = true
	_surface_core_goals()
	_mission_sync()

## The [CORE GOAL] missions (goal_*) are long-term prestige objectives — keep
## them hidden during the guided tutorial so a new player only sees the tutorial
## chain, then reveal them once the tutorial is finished (desktop shows them, but
## on mobile the early screen is busy enough). Removing them while the tutorial
## runs also cleans up older saves that surfaced them too early.
func _tutorial_done() -> bool:
	# Walk the real next-chain from the first mission and find the LAST
	# [TUTORIAL]-tagged mission actually on it; the tutorial is over once that's
	# claimed. (Scanning all MISSIONS would deadlock on orphaned tutorial
	# missions like m016b that aren't reachable via `next`.)
	var cur: String = GameData.MISSION_ORDER[0] if not GameData.MISSION_ORDER.is_empty() else "m001"
	var last_tut := ""
	var seen := {}
	var guard := 0
	while cur != "" and not seen.has(cur) and guard < 500:
		guard += 1
		seen[cur] = true
		if String(GameData.MISSIONS.get(cur, {}).get("name", "")).begins_with("[TUTORIAL]"):
			last_tut = cur
		cur = GameData.MISSIONS.get(cur, {}).get("next", "")
	return last_tut == "" or missions_claimed.has(last_tut)

func _surface_core_goals() -> void:
	var ready := _tutorial_done()
	for gid in GameData.MISSION_GOALS:
		if missions_claimed.has(gid):
			continue
		if ready:
			missions_active[gid] = true
		else:
			missions_active.erase(gid)   # stay hidden until the tutorial ends

## Recover a stalled tutorial chain: if there's no active mission but unclaimed
## ones remain (e.g. an old save whose chain hit a since-fixed dead link),
## re-activate the next unclaimed mission by walking the chain from the start.
func _mission_repair() -> void:
	if not missions_active.is_empty() or missions_claimed.is_empty():
		return
	if GameData.MISSION_ORDER.is_empty():
		return
	var cur: String = GameData.MISSION_ORDER[0]
	var guard := 0
	while cur != "" and missions_claimed.has(cur) and guard < 200:
		guard += 1
		cur = GameData.MISSIONS.get(cur, {}).get("next", "")
	if cur != "" and GameData.MISSIONS.has(cur) and not missions_claimed.has(cur):
		missions_active[cur] = true
		_mission_sync()
		missions_changed.emit()

func mission_completed(mid: String) -> bool:
	var m: Dictionary = GameData.MISSIONS.get(mid, {})
	match m.get("type", ""):
		"gather_multi":               # need N of each material at once (inventory-based)
			return multi_have(m) >= int(m.get("qty", 1))
		"loadout_check":              # ship has a weapon + a shield equipped (or a named slot filled)
			return _loadout_check_met(m)
		"equip_consumables":          # both consumable slots stocked with >= qty
			return _equip_consumables_met(m)
		"drop_rarity":                # own / equip a module of rarity >= target
			return _has_module_rarity(int(m.get("target", "0")))
		"loadout_rare_weapon":        # equipped weapon of rarity >= target
			return _has_rare_weapon_equipped(int(m.get("target", "0")))
	return int(missions_progress.get(mid, 0)) >= int(m.get("qty", 1))

## Per-slot loadout check (desktop): "combat_ready" needs weapon+shield; a named
## slot_type target (engine/weapon/shield/battery) is met when ANY such module is equipped.
func _loadout_check_met(m: Dictionary) -> bool:
	var target := str(m.get("target", ""))
	if target == "combat_ready" or target == "":
		return is_combat_ready()
	for k in loadout:
		if module_def(loadout[k]).get("slot", "") == target:
			return true
	return false

## Rarity of a module instance id (rolled instances carry "rarity"; base/set
## modules use their data "rarity", defaulting to 0 = common).
func module_rarity(mid: String) -> int:
	return int(module_def(mid).get("rarity", 0))

func _has_module_rarity(target_rarity: int) -> bool:
	for inv_mid in module_inventory:
		if module_rarity(inv_mid) >= target_rarity:
			return true
	for eq_mid in loadout.values():
		if eq_mid != "" and module_rarity(eq_mid) >= target_rarity:
			return true
	return false

func _has_rare_weapon_equipped(target_rarity: int) -> bool:
	for mid in loadout.values():
		if mid != "" and module_def(mid).get("slot", "") == "weapon" \
			and module_rarity(mid) >= target_rarity:
			return true
	return false

func _equip_consumables_met(m: Dictionary) -> bool:
	# Desktop reads the required count from the mission target ("1").
	var req := int(str(m.get("target", "1")))
	var hull_ok := consumable_hull_slot != "" and amount(consumable_hull_slot) >= req
	var shield_ok := consumable_shield_slot != "" and amount(consumable_shield_slot) >= req
	return hull_ok and shield_ok

## Summed inventory progress toward a gather_multi mission's per-material goals.
func multi_have(m: Dictionary) -> int:
	var p := 0
	var tgt = m.get("target", {})
	if tgt is Dictionary:
		for s in tgt:
			p += mini(amount(s), int(tgt[s]))
	return p

func is_combat_ready() -> bool:
	var has_w := false
	var has_s := false
	for k in loadout:
		var st: String = module_def(loadout[k]).get("slot", "")
		if st == "weapon":
			has_w = true
		elif st == "shield":
			has_s = true
	if not has_s and ship_stats().get("shield", 0.0) > 0.0:
		has_s = true
	return has_w and has_s

## True once the player has started the tutorial chain (claimed or made progress).
func has_mission_progress() -> bool:
	if not missions_claimed.is_empty():
		return true
	for mid in missions_progress:
		if int(missions_progress[mid]) > 0:
			return true
	return false

## True when at least one active mission is finished and waiting to be claimed.
func has_claimable_mission() -> bool:
	for mid in missions_active:
		if mission_completed(mid) and not missions_claimed.has(mid):
			return true
	return false

# Retroactively reconcile active missions with current state (ported from the
# desktop sync_progress). Lets a mission that became active AFTER its requirement
# was already met — e.g. you researched Applied Physics before the mission asked —
# register as done instead of waiting for an event that already fired.
func _mission_sync() -> void:
	var changed := false
	for mid in missions_active.keys():
		if missions_claimed.has(mid):
			continue
		if mission_completed(mid):
			# Live-evaluated types (equip_consumables / drop_rarity /
			# loadout_rare_weapon / loadout_check) report completion without a
			# stored progress value — flag a UI refresh the first time we see it done.
			if not _mission_completed_seen.has(mid):
				_mission_completed_seen[mid] = true
				changed = true
			continue
		var m: Dictionary = GameData.MISSIONS.get(mid, {})
		var t: String = m.get("type", "")
		var target = m.get("target", "")   # may be a Dictionary for gather_multi
		var qty: int = int(m.get("qty", 1))
		var cur: int = int(missions_progress.get(mid, 0))
		var nv := cur
		match t:
			"research":
				if is_research_unlocked(target):
					nv = qty
			"gather":
				nv = maxi(cur, mini(amount(target), qty))
			"craft":
				var have := int(module_inventory.get(target, 0))
				for k in loadout:
					if loadout[k] == target:
						have += 1
				nv = maxi(cur, mini(have, qty))
			"build":
				nv = maxi(cur, mini(int(buildings.get(target, 0)), qty))
			"construct":
				var cur_tier := int(GameData.HULLS.get(active_hull, {}).get("tier", 0))
				var tgt_tier := int(GameData.HULLS.get(target, {}).get("tier", 0))
				if active_hull == target or hull_owned(target) or cur_tier >= tgt_tier:
					nv = qty
			"warp_perform":
				nv = maxi(cur, mini(total_warps, qty))
			# "defeat", "discover", "visit_page" are event-only (no persistent
			# state to reconcile). equip_consumables / drop_rarity /
			# loadout_rare_weapon / loadout_check are evaluated live in
			# mission_completed(), so they need no progress reconcile here.
		if nv != cur:
			missions_progress[mid] = nv
			changed = true
	if changed:
		missions_changed.emit()

func _mission_event(type: String, target: String, amount: int) -> void:
	var changed := false
	for mid in missions_active.keys():
		var m: Dictionary = GameData.MISSIONS.get(mid, {})
		if m.get("type", "") == type and m.get("target", "") == target and not mission_completed(mid):
			missions_progress[mid] = mini(int(m.get("qty", 1)), int(missions_progress.get(mid, 0)) + amount)
			changed = true
	if changed:
		missions_changed.emit()

## Page-navigation hook for visit_page missions (e.g. m016c "Combat Briefing"
## auto-completes when the Combat page is opened). Called from main.gd::_show().
func mission_visit_page(page_id: String) -> void:
	_mission_event("visit_page", page_id, 1)

func claim_mission(mid: String) -> bool:
	if not missions_active.has(mid) or not mission_completed(mid) or missions_claimed.has(mid):
		return false
	var m: Dictionary = GameData.MISSIONS[mid]
	gain_credits(int(int(m.get("cr", 0)) * warp_production_mult() * credit_reward_mult()))   # prestige- + Recursive-Acquisition-scaled reward
	missions_claimed[mid] = true
	missions_active.erase(mid)
	var nxt: String = m.get("next", "")
	if nxt != "" and GameData.MISSIONS.has(nxt) and not missions_claimed.has(nxt):
		missions_active[nxt] = true
	_surface_core_goals()   # claiming the last tutorial mission reveals the core goals
	_mission_sync()   # the newly-activated mission may already be satisfied
	missions_changed.emit()
	return true

func research_available(rid: String) -> bool:
	if is_research_unlocked(rid):
		return false
	var t: Dictionary = GameData.RESEARCH.get(rid, {})
	var parent: String = t.get("parent", "")
	if parent != "" and not is_research_unlocked(parent):
		return false
	# req_tech: real prerequisites distinct from the parent edge. Desktop can_unlock
	# requires every one unlocked (faithful to ref_research_manager.gd ~L1783).
	for rt in t.get("req_tech", []):
		if String(rt) != "" and not is_research_unlocked(String(rt)):
			return false
	# requires_warp: prestige-gated tech (e.g. Cryogenic Armaments) stays locked
	# until the player has Warped at least once (desktop ~L1788). Gated on the
	# persistent cryo_unlocked flag — set on the first Warp, equivalent to the
	# old total_warps>0 check but the flag is the real semantic gate.
	if bool(t.get("requires_warp", false)) and not cryo_unlocked:
		return false
	return credits >= int(t.get("credits", 0)) and can_afford(t.get("items", {}))

func unlock_research(rid: String) -> bool:
	if not research_available(rid):
		return false
	var t: Dictionary = GameData.RESEARCH[rid]
	credits -= int(t.get("credits", 0))
	spend(t.get("items", {}))
	unlocked_research[rid] = true
	# Warp Core stays hidden until Zone 6 research (desktop v110 reveal moment).
	if rid == "zone_6_access" and not game_flags.get("warp_revealed", false):
		game_flags["warp_revealed"] = true
		feature_revealed.emit("⟨ WARP CORE RESONANCE ⟩",
			"A new prestige system is online — open WARP CORE in the menu to spend Exotic Matter Shards.")
	_mission_event("research", rid, 1)
	# discover missions (e.g. goal_001 -> sector_epsilon): a zone is "discovered"
	# the moment its gating research is unlocked.
	for z in GameData.ZONES:
		if z.get("research_req", "") == rid:
			_mission_event("discover", z.get("id", ""), 1)
	research_changed.emit()
	return true

# ---------------- Requirements ----------------
func meets_requirements(def: Dictionary, skill_id: String) -> bool:
	if level_of(skill_id) < int(def.get("level_req", 1)):
		return false
	var rr: String = def.get("research_req", "")
	if rr != "" and not is_research_unlocked(rr):
		return false
	return true

# ---------------- Active task ----------------
func start_task(type: String, id: String) -> void:
	if active_type == type and active_id == id:
		stop_task()
		return
	active_type = type
	active_id = id
	progress = 0.0
	if type == "combat":
		_init_combat(id)
	action_changed.emit()

func stop_task() -> void:
	active_type = ""
	active_id = ""
	progress = 0.0
	enemy_inst = {}
	action_changed.emit()

# ---------------- Real-time combat ----------------
func _init_combat(eid: String) -> void:
	_weapons = ship_weapons()
	player_shield = player_max_shield()
	player_heat = 0.0
	_overheat_lock = 0.0
	_enemy_timer = 0.0
	combat_events.clear()
	# Fresh engagement — clear the session-loot tally (desktop clears on zone entry).
	session_loot = {}
	if combat_hp <= 0.0:
		combat_hp = combat_max_hp()
	_spawn_enemy_inst(eid)

func _spawn_enemy_inst(eid: String) -> void:
	var e: Dictionary = GameData.ENEMIES.get(eid, {})
	# Progression compensation (desktop): enemy baseline scales against the
	# player's permanent external multipliers so TTK doesn't collapse late-game.
	var prog := clampf((1.0 + level_of("combat") * 0.005) \
		* (1.0 + level_of("fabrication") * 0.01) \
		* (1.0 + maxf(0.0, research_bonus("attack_speed"))) \
		* maxf(1.0, warp_combat_mult()), 1.0, 6.0)
	var over := maxf(0.0, prog - 1.0)
	var is_boss: bool = e.get("is_boss", false)
	var hp_comp := 0.42 if is_boss else 0.28
	var sh_comp := 0.36 if is_boss else 0.24
	var atk_comp := 0.28 if is_boss else 0.18
	var elite := randf() < 0.05
	for c in bounty_active:   # elite-hunt contracts force an elite spawn
		if c.get("is_elite", false) and not c["completed"] and c["target"] == eid:
			elite = true
			break
	var hp := float(e.get("hp", 10))
	var atk := float(e.get("atk", 1))
	var shd := float(e.get("max_shield", 0))
	var df := float(e.get("def", 0))
	if over > 0.0:
		hp = maxf(1.0, roundf(hp * (1.0 + over * hp_comp)))
		shd = maxf(0.0, roundf(shd * (1.0 + over * sh_comp)))
		atk = maxf(1.0, roundf(atk * (1.0 + over * atk_comp)))
		df = maxf(0.0, roundf(df * (1.0 + over * 0.12)))
	var xp := int(e.get("xp", 0))
	var nm: String = e.get("name", eid)
	var loot: Array = e.get("loot", [])
	if elite:
		hp *= 2.5
		atk *= 1.8
		xp = int(xp * 3)
		nm = "ELITE " + nm
		loot = loot.duplicate(true)
		for row in loot:
			row[2] = int(row[2] * 2.5)
			row[3] = int(row[3] * 2.5)
	enemy_inst = {
		"id": eid, "name": nm, "elite": elite,
		"hp": hp, "max_hp": hp,
		"shield": shd, "max_shield": shd,
		"atk": atk, "def": df,
		"acc": float(e.get("accuracy", 0)), "eva": float(e.get("eva", 0)),
		"interval": maxf(0.5, float(e.get("interval", 2.5))),
		"loot": loot, "xp": xp,
		"drop_chance": float(e.get("drop_chance", 0.0)), "drop_pool": e.get("drop_pool", []),
		# Combat-parity data (desktop v109): typed damage + per-type resistances.
		"zone": int(e.get("zone", 1)),
		"dmg_type": String(e.get("dmg_type", "kinetic")),
		"resist_k": float(e.get("resist_k", 0.0)),
		"resist_e": float(e.get("resist_e", 0.0)),
		"resist_x": float(e.get("resist_x", 0.0)),
		"resist_cryo": float(e.get("resist_cryo", 0.0)),
		"warp_hardened": bool(e.get("warp_hardened", false)),
		"enrage_at": float(e.get("enrage_at", 0.0)),
		"enrage_atk_mult": float(e.get("enrage_atk_mult", 1.5)),
		# v80.1 boss-core drop: granted on kill so zone_N_access research unlocks.
		"is_boss": bool(e.get("is_boss", false)),
		"boss_core": String(e.get("boss_core", "")),
	}
	# v109 reset per-fight enrage; v85.2 vulnerable wears off between fights.
	_enemy_enraged = false
	enemy_vulnerable_timer = 0.0
	# Trinity: Harbinger's Wrath — reduce this enemy's effective DEF on spawn.
	var def_red := trinity_bonus("enemy_def_reduce_pct")
	if def_red > 0.0:
		enemy_inst["def"] = maxf(0.0, float(enemy_inst["def"]) * (1.0 - def_red / 100.0))

func _combat_difficulty() -> int:
	# Active hazard run uses the hazard zone's difficulty.
	if hazard_state.get("active", false):
		var hz: Dictionary = GameData.HAZARD_ZONES.get(hazard_state["zone_id"], {})
		return int(hz.get("difficulty", 3))
	for z in GameData.ZONES:
		if active_id in z.get("enemies", []):
			return int(z.get("difficulty", 1))
	return 1

# v101 Combat Loot Scaling (desktop ref_combat_manager.gd ~L1838-1861): keeps combat
# resource drops in pace with gathering/processing progression. +1%/combat level,
# +15%/zone tier above 1, times the efficiency research tier (x1.5..x4) and the warp
# combat multiplier. Base/early stays ~1.0.
func get_combat_loot_multiplier() -> float:
	var mult := 1.0
	mult += level_of("combat") * 0.01
	mult += maxf(0.0, float(_combat_difficulty() - 1)) * 0.15
	# Efficiency research tiers (same x1.5..x4 factor as get_combat_loot_multiplier).
	if is_research_unlocked("efficiency_5"): mult *= 4.0
	elif is_research_unlocked("efficiency_4"): mult *= 3.0
	elif is_research_unlocked("efficiency_3"): mult *= 2.5
	elif is_research_unlocked("efficiency_2"): mult *= 2.0
	elif is_research_unlocked("efficiency_1"): mult *= 1.5
	mult *= maxf(1.0, warp_combat_mult())
	return mult

func _event(text: String, color: String, side: String) -> void:
	combat_events.append({"text": text, "color": color, "side": side, "seq": _event_seq})
	_event_seq += 1
	while combat_events.size() > 14:
		combat_events.pop_front()

func _tick_combat(delta: float) -> void:
	if enemy_inst.is_empty():
		return
	var ss := ship_stats()
	var maxsh := player_max_shield()
	# Heat venting (4x while overloaded / locked; +25% milestone @ combat L75)
	if player_heat > 0.0:
		var vent := VENT_RATE
		if level_of("combat") >= 75:
			vent *= 1.25
		if player_heat > MAX_HEAT or _overheat_lock > 0.0:
			vent *= 4.0
		player_heat = maxf(0.0, player_heat - vent * delta)
	if _overheat_lock > 0.0 and player_heat <= 0.0:
		_overheat_lock = 0.0
	# v85.2 Vulnerable status timer counts down each tick.
	if enemy_vulnerable_timer > 0.0:
		enemy_vulnerable_timer = maxf(0.0, enemy_vulnerable_timer - delta)
	# Shield regen (both sides)
	if player_shield < maxsh:
		player_shield = minf(maxsh, player_shield + float(ss.get("shield_regen", 0.0)) * (1.0 + research_bonus("shield_regen") + float(ss.get("regen_bonus", 0.0))) * delta)
	if enemy_inst["shield"] < enemy_inst["max_shield"]:
		enemy_inst["shield"] = minf(enemy_inst["max_shield"], enemy_inst["shield"] + minf(enemy_inst["max_shield"] * 0.01, 50.0) * delta)
	# Unified HP regen (Trinity hp_regen_flat + modules), capped in ship_stats.
	if float(ss.get("hp_regen", 0.0)) > 0.0 and combat_hp < combat_max_hp():
		combat_hp = minf(combat_max_hp(), combat_hp + float(ss["hp_regen"]) * delta)
	# Set bonus: Patient Zero's Strain — hull regen during combat
	if has_set_bonus("patient_zero") and combat_hp < combat_max_hp():
		combat_hp = minf(combat_max_hp(), combat_hp + 50.0 * delta)
	# Player weapons fire on their own intervals (Heat-Sync Focus boosts rate when hot)
	var fire_sf := 1.0 + research_bonus("attack_speed")
	if player_heat >= MAX_HEAT * 0.4:
		fire_sf += affix_total("heat_sync_focus")
	if loadout_has_module("warp_stabilizer"):
		fire_sf += 0.15
	# v85.2 Overdrive (berserk_on_kill): +25% fire rate for 5s after a proc'd kill.
	if _player_berserk_timer > 0.0:
		_player_berserk_timer = maxf(0.0, _player_berserk_timer - delta)
		fire_sf *= 1.25
	# Broadside Array: periodic heavy kinetic salvo
	if loadout_has_module("broadside_array"):
		_broadside_timer += delta
		if _broadside_timer >= 20.0:
			_broadside_timer = 0.0
			_broadside_fire()
			if active_type != "combat":
				return
	for w in _weapons:
		w["timer"] = float(w["timer"]) + delta * fire_sf
		var guard := 0
		while float(w["timer"]) >= float(w["interval"]) and guard < 20:
			guard += 1
			w["timer"] = float(w["timer"]) - float(w["interval"])
			_player_fire(w, ss)
			if active_type != "combat":
				return
	# Enemy fires on its interval
	# Enemy attack slow: Cryo-Lord set (-15%) and Chrono Stabilizer (-20%)
	var eslow := 1.0
	if has_set_bonus("cryo"):
		eslow *= 0.85
	if loadout_has_module("chrono_stabilizer"):
		eslow *= 0.8
	# Electronic warfare: jamming slows the enemy timer (capped at MAX_ENEMY_SLOW).
	eslow *= maxf(1.0 - MAX_ENEMY_SLOW, 1.0 - float(ss.get("jamming_strength", 0.0)))
	_enemy_timer += delta * eslow
	var eguard := 0
	while _enemy_timer >= float(enemy_inst["interval"]) and eguard < 20:
		eguard += 1
		_enemy_timer -= float(enemy_inst["interval"])
		_enemy_fire(ss)
		if active_type != "combat":
			return
	# Auto-consumables (repair / shield) when low
	if _consume_cd > 0.0:
		_consume_cd -= delta
	else:
		_check_consume(maxsh)

func _check_consume(maxsh: float) -> void:
	var th := auto_consume_threshold()   # gated by Auto-Repair research (desktop parity)
	if th <= 0.0:
		return
	if consumable_hull_slot != "" and amount(consumable_hull_slot) > 0:
		if combat_hp / maxf(1.0, combat_max_hp()) <= th:
			_trigger_consume(consumable_hull_slot)
			return
	if consumable_shield_slot != "" and amount(consumable_shield_slot) > 0 and maxsh > 0.0:
		if player_shield / maxsh <= th:
			_trigger_consume(consumable_shield_slot)

func use_manual_consumable(kind: String) -> void:
	if _consume_cd > 0.0 or active_type != "combat":
		return
	var item: String = consumable_hull_slot if kind == "hull" else consumable_shield_slot
	if item == "" or amount(item) <= 0:
		for cid in GameData.CONSUMABLES:
			if GameData.CONSUMABLES[cid].get("type", "") == kind and amount(cid) > 0:
				item = cid
				break
	if item != "" and amount(item) > 0:
		_trigger_consume(item)
		resources_changed.emit()

func _trigger_consume(item_id: String) -> void:
	var d: Dictionary = GameData.CONSUMABLES.get(item_id, {})
	if d.is_empty() or amount(item_id) < 1:
		return
	resources[item_id] = amount(item_id) - 1
	_consume_cd = CONSUME_CD
	var pct := float(d.get("heal_pct", 0.0))
	if d.get("type", "hull") == "hull":
		var amt := combat_max_hp() * pct
		combat_hp = minf(combat_max_hp(), combat_hp + amt)
		_event("+%d HP" % int(amt), "5fd585", "player")
	else:
		var amt := player_max_shield() * pct
		player_shield = minf(player_max_shield(), player_shield + amt)
		_event("+%d SHLD" % int(amt), "55d3e6", "player")

func set_ammo(slot: String, ammo_id: String) -> void:
	if ammo_id == "":
		ammo_loadout.erase(slot)
	else:
		ammo_loadout[slot] = ammo_id
	resources_changed.emit()

func set_consumable(kind: String, item_id: String) -> void:
	if kind == "hull":
		consumable_hull_slot = item_id
	else:
		consumable_shield_slot = item_id
	_mission_sync()   # equip_consumables missions evaluate live consumable slots
	resources_changed.emit()

func _player_fire(w: Dictionary, ss: Dictionary) -> void:
	if _overheat_lock > 0.0:
		return
	var dtot := float(w["dmg_k"]) + float(w["dmg_e"]) + float(w["dmg_x"]) + float(w.get("dmg_cryo", 0.0))
	player_heat += 2.0 + dtot / 100.0
	if player_heat >= MAX_HEAT:
		_overheat_lock = 1.0
		_event("OVERHEAT", "ef9a54", "player")
		return
	# v86.0 EMP Storm hazard: weapons jam (40% without the Faraday counter, 10% with).
	if hazard_state.get("active", false) and _active_hazard_type() == "emp_storm":
		var jam_chance := 0.10 if loadout_has_module("faraday_hull") else 0.40
		if randf() < jam_chance:
			_event("EMP JAM", "ecb44a", "enemy")
			return
	var acc := float(ss.get("acc", 100.0))
	var hit := clampf(acc / (acc + float(enemy_inst["eva"])), 0.2, 1.0)
	if randf() > hit:
		_event("MISS", "9aa7c2", "enemy")
		return
	# v85.1 Heal-on-hit affixes (ref ~L1518-1525): restore hull / shield per landed hit.
	var hull_heal := affix_total("hull_heal_on_hit")
	if hull_heal > 0.0:
		combat_hp = minf(combat_max_hp(), combat_hp + hull_heal)
	var shield_heal := affix_total("shield_heal_on_hit")
	if shield_heal > 0.0:
		player_shield = minf(player_max_shield(), player_shield + shield_heal)
	# v85.2 Lucky Hit: chance to apply Vulnerable (+20% damage taken for 3s).
	var lucky := 0.10 + affix_total("lucky_hit_chance")
	if randf() < lucky:
		var vchance := affix_total("vuln_on_hit")
		if vchance > 0.0 and randf() < vchance:
			enemy_vulnerable_timer = 3.0
			_event("EXPOSED!", "b78ae8", "enemy")
	# Ammo (desktop v109): every slotted non-cryo weapon REQUIRES compatible
	# ammo to fire (kinetic→Slug, energy→Cell, explosive→Missile). The hull
	# standard cannon (slot "") and cryo weapons are exempt and fire for free.
	var dk := float(w["dmg_k"])
	var de := float(w["dmg_e"])
	var dx := float(w["dmg_x"])
	var dc := float(w.get("dmg_cryo", 0.0))
	var wtype := String(w.get("type", "kinetic"))
	if wtype == "energy" and loadout_has_module("plasma_overcharger"):
		de *= 2.0   # Plasma Overcharger
	var requires_ammo := String(w.get("slot", "")) != "" and wtype != "cryo"
	var ammo: String = ammo_loadout.get(w.get("slot", ""), "")
	var ab: Array = ammo_bonus(ammo) if ammo != "" else ["", 0.0]
	var ammo_ok: bool = ammo != "" and amount(ammo) > 0 \
		and ((wtype == "kinetic" and ab[0] == "k") \
			or (wtype == "energy" and ab[0] == "e") \
			or (wtype == "explosive" and ab[0] == "x"))
	if ammo_ok:
		resources[ammo] = amount(ammo) - 1
		match ab[0]:
			"k": dk += ab[1]
			"e": de += ab[1]
			"x": dx += ab[1]
	elif requires_ammo:
		# No compatible ammo loaded — the weapon can't fire (desktop parity).
		if randf() < 0.12:
			_event("NO AMMO", "ef6a52", "enemy")
		return
	# Static Burst: chance to reset the enemy's attack timer on hit.
	var sb := affix_total("static_burst")
	if sb > 0.0 and randf() < sb:
		_enemy_timer = 0.0
		_event("SHOCK", "ecb44a", "enemy")
	# Void Strike: chance to bypass the shield entirely.
	var vs := affix_total("void_strike")
	var voided: bool = vs > 0.0 and randf() < vs
	var res := resolve_damage(dk, de, dx, 0.0 if voided else float(enemy_inst["shield"]), enemy_inst["def"], _combat_difficulty(), float(ss.get("crit", 0.05)), true, dc)
	if voided:
		_event("VOID", "ff44cc", "enemy")
	else:
		enemy_inst["shield"] = maxf(0.0, enemy_inst["shield"] - res[0])
	enemy_inst["hp"] -= res[1]
	if res[0] > 0:
		_event("-%d" % int(res[0]), "55d3e6", "enemy")
	if res[1] > 0:
		_event(("CRIT %d" % int(res[1])) if res[2] else ("-%d" % int(res[1])), "ecb44a" if res[2] else "ef6a52", "enemy")
	# v86.0 resist feedback (ref_combat_manager ~L1636-1644): the dominant-type
	# resistance vs this hit. Low % per hit (anti-spam) so the player learns that
	# damage-type choice matters without popup spam.
	# Only when the hit actually landed hull damage, so the resist/weak cue
	# reflects real mitigation rather than a fully shield-absorbed swing.
	if not enemy_inst.is_empty() and res[1] > 0:
		var dom := 0.0
		match wtype:
			"energy": dom = float(enemy_inst.get("resist_e", 0.0))
			"explosive": dom = float(enemy_inst.get("resist_x", 0.0))
			"cryo": dom = float(enemy_inst.get("resist_cryo", 0.0))
			_: dom = float(enemy_inst.get("resist_k", 0.0))
		if dom >= 0.20 and randf() < 0.15:
			_event("RESISTED", "9aa7c2", "enemy")
		elif dom <= -0.20 and randf() < 0.15:
			_event("WEAK SPOT", "5fd585", "enemy")
	if enemy_inst["hp"] <= 0.0:
		_win_combat()

func _enemy_fire(ss: Dictionary) -> void:
	var eva := float(ss.get("eva", 0.0))
	var e_acc := float(enemy_inst["acc"])
	var dodge := minf(eva / (eva + 150.0 * (1.0 + e_acc / 100.0)), 0.75)
	if randf() < dodge:
		_event("DODGE", "9aa7c2", "player")
		return
	var pdef := float(ss.get("def", 0.0))
	_check_enrage()   # v109: re-evaluate enrage before this swing (telegraph + buff)
	# Typed enemy fire (desktop v109): route the enemy's atk into the slot
	# matching its dmg_type so the player's armor-type mitigation behaves as
	# desktop. Reactive Armor is now handled inside resolve_damage (via k).
	# v87.0 typed-damage compensation: energy/explosive enemies hit harder per
	# point (x1.5 shields / 80% armor bypass) so their raw atk is scaled down.
	var atk := float(enemy_inst["atk"])
	if _enemy_enraged:
		atk *= float(enemy_inst.get("enrage_atk_mult", 1.5))
	var e_k := 0.0
	var e_e := 0.0
	var e_x := 0.0
	match String(enemy_inst.get("dmg_type", "kinetic")):
		"energy": e_e = atk * ENEMY_ENERGY_ATK_COMP
		"explosive": e_x = atk * ENEMY_EXPLOSIVE_ATK_COMP
		_: e_k = atk
	var res := resolve_damage(e_k, e_e, e_x, player_shield, pdef, _combat_difficulty(), 0.05, false)
	# Exotic Shield Matrix: 30% damage reduction in Sector Gamma
	if loadout_has_module("exotic_shield_matrix") and _current_zone_id() == "sector_gamma":
		res[1] = int(res[1] * 0.7)
	# v80.1 Unified reflect (desktop): Monolith's Bedrock set (reflect_pct) +
	# Reflective Sheath module (+20%), clamped to MAX_REFLECT_PERCENT.
	var reflect_pct := trinity_bonus("reflect_pct") / 100.0
	if loadout_has_module("reflective_sheath"):
		reflect_pct += 0.20
	reflect_pct = minf(reflect_pct, MAX_REFLECT_PERCENT)
	if reflect_pct > 0.0:
		var ref_dmg := int((res[0] + res[1]) * reflect_pct)
		if ref_dmg > 0:
			enemy_inst["hp"] -= ref_dmg
			_event("REFLECT %d" % ref_dmg, "9aa7c2", "enemy")
			if enemy_inst["hp"] <= 0.0:
				_win_combat()
				return
	player_shield = maxf(0.0, player_shield - res[0])
	combat_hp -= res[1]
	# v109 typed enemy-damage readout: tag hull damage with the enemy's dmg_type
	# (KIN/NRG/EXP) so the popup tells the player what's hurting them.
	var dtag: String = {"energy": "NRG", "explosive": "EXP"}.get(String(enemy_inst.get("dmg_type", "kinetic")), "KIN")
	if res[0] > 0:
		_event("-%d %s" % [int(res[0]), dtag], "55d3e6", "player")
	if res[1] > 0:
		_event("-%d %s" % [int(res[1]), dtag], "ef6a52", "player")
	if combat_hp <= 0.0:
		_lose_combat()

# v109 P3 boss mechanic — Enrage. When the enemy's HP first crosses below its
# enrage_at fraction it permanently surges ATK by enrage_atk_mult for the rest
# of the fight. Telegraphed once. Data-driven (enrage_at / enrage_atk_mult on
# any enemy; currently the Threshold Warden).
func _check_enrage() -> void:
	if _enemy_enraged or enemy_inst.is_empty():
		return
	var thr := float(enemy_inst.get("enrage_at", 0.0))
	if thr <= 0.0 or float(enemy_inst.get("max_hp", 0.0)) <= 0.0:
		return
	if float(enemy_inst["hp"]) / float(enemy_inst["max_hp"]) <= thr:
		_enemy_enraged = true
		var mult := float(enemy_inst.get("enrage_atk_mult", 1.5))
		_event("ENRAGED x%.1f" % mult, "ff5933", "enemy")

## Broadside Array: a heavy kinetic salvo (5x equipped kinetic damage).
func _broadside_fire() -> void:
	var total_k := 0.0
	for w in _weapons:
		if w["type"] == "kinetic":
			total_k += float(w["dmg_k"])
	if total_k <= 0.0:
		return
	var res := resolve_damage(total_k * 5.0, 0.0, 0.0, float(enemy_inst["shield"]), enemy_inst["def"], _combat_difficulty(), 0.10, true)
	enemy_inst["shield"] = maxf(0.0, enemy_inst["shield"] - res[0])
	enemy_inst["hp"] -= res[1]
	_event("BROADSIDE %d" % int(res[0] + res[1]), "ecb44a", "enemy")
	if enemy_inst["hp"] <= 0.0:
		_win_combat()

## Damage-type resolution: kinetic/energy/explosive(/cryo) vs shields then armor.
## Ported from desktop v109 combat_manager.resolve_damage:
##   * k = DEF_K_CONSTANT + DEF_K_ZONE_SCALE * pow(zone_diff, DEF_K_ZONE_EXP)
##   * armor mitigation clamped so >=(1-MAX_DAMAGE_REDUCTION) of each type lands
##   * when the player is the attacker, the current enemy's per-type resistances
##     (resist_k/e/x/cryo, clamped -0.4..0.5) reduce each hull-damage type
##   * warp_hardened enemies near-nullify conventional (K/E/X) damage (x0.02)
## Cryo is the 4th type; it stays inert (atk_cryo defaults 0) until Cryo weapons
## ship, so existing K/E/X math is unchanged where no cryo/resist data applies.
func resolve_damage(atk_k: float, atk_e: float, atk_x: float, c_shield: float, c_armor: float, difficulty: int, crit_chance: float, is_player_attacker: bool = false, atk_cryo: float = 0.0) -> Array:
	var hardened: bool = is_player_attacker and not enemy_inst.is_empty() and bool(enemy_inst.get("warp_hardened", false))
	var noncryo := 0.02 if hardened else 1.0
	var shield_pot := (atk_k * 0.5 + atk_e * 1.5 + atk_x * 1.1) * noncryo + atk_cryo * 1.0
	# v85.2 Vulnerable status: enemy takes +20% damage while the timer is live.
	if not is_player_attacker and enemy_vulnerable_timer > 0.0:
		shield_pot *= 1.2
	# v85.2 Healthy/Injured affix bonuses (player attacks only).
	if is_player_attacker and not enemy_inst.is_empty():
		var ehp_pct := float(enemy_inst["hp"]) / maxf(1.0, float(enemy_inst["max_hp"]))
		if ehp_pct >= 0.8:
			var bh := affix_total("dmg_healthy")
			if bh > 0.0: shield_pot *= 1.0 + bh
		elif ehp_pct <= 0.35:
			var bi := affix_total("dmg_injured")
			if bi > 0.0: shield_pot *= 1.0 + bi
	var dmg_shield := minf(c_shield, shield_pot)
	var bleed := (shield_pot - dmg_shield) / shield_pot if shield_pot > 0.0 else 1.0
	var k := GameData.DEF_K_CONSTANT + GameData.DEF_K_ZONE_SCALE * pow(float(difficulty), GameData.DEF_K_ZONE_EXP)
	# Reactive Armor: low HP effectively raises k (better mitigation) on the player.
	if not is_player_attacker and loadout_has_module("reactive_armor"):
		var hp_ratio := combat_hp / maxf(1.0, combat_max_hp())
		k *= 1.0 + (1.0 - hp_ratio)
	var arm_k := c_armor
	var arm_e := c_armor * 0.7
	var arm_x := c_armor * 0.2
	var arm_cryo := c_armor * 0.5
	var min_factor := 1.0 - GameData.MAX_DAMAGE_REDUCTION
	var hk := atk_k * 1.2 * maxf(min_factor, 1.0 - arm_k / (arm_k + k))
	var he := atk_e * 0.9 * maxf(min_factor, 1.0 - arm_e / (arm_e + k))
	var hx := atk_x * 1.0 * maxf(min_factor, 1.0 - arm_x / (arm_x + k))
	var hc := atk_cryo * 1.0 * maxf(min_factor, 1.0 - arm_cryo / (arm_cryo + k))
	# Enemy per-type resistances (player attacks only). Negative = weakness.
	if is_player_attacker and not enemy_inst.is_empty():
		var rk := clampf(float(enemy_inst.get("resist_k", 0.0)), -0.40, 0.50)
		var re := clampf(float(enemy_inst.get("resist_e", 0.0)), -0.40, 0.50)
		var rx := clampf(float(enemy_inst.get("resist_x", 0.0)), -0.40, 0.50)
		var rc := clampf(float(enemy_inst.get("resist_cryo", 0.0)), -0.40, 0.50)
		hk *= 1.0 - rk
		he *= 1.0 - re
		hx *= 1.0 - rx
		hc *= 1.0 - rc
		# Warp-Hardened nullifies conventional hull damage (Cryo exempt); applied
		# after the resist clamp so it is a hard gate, not armor.
		if hardened:
			hk *= 0.02
			he *= 0.02
			hx *= 0.02
	var hull := (hk + he + hx + hc) * bleed
	# v85.2 Vulnerable + Healthy/Injured also scale the hull total (desktop parity).
	if not is_player_attacker and enemy_vulnerable_timer > 0.0:
		hull *= 1.2
	if is_player_attacker and not enemy_inst.is_empty():
		var ehp_pct2 := float(enemy_inst["hp"]) / maxf(1.0, float(enemy_inst["max_hp"]))
		if ehp_pct2 >= 0.8:
			var bh2 := affix_total("dmg_healthy")
			if bh2 > 0.0: hull *= 1.0 + bh2
		elif ehp_pct2 <= 0.35:
			var bi2 := affix_total("dmg_injured")
			if bi2 > 0.0: hull *= 1.0 + bi2
	var variance := randf_range(0.9, 1.1)
	var is_crit := randf() < crit_chance
	# v80.1 Crit damage cap (variance multiplier ceiling).
	if is_crit:
		variance *= minf(1.5, MAX_CRIT_DAMAGE)
	var minhull := 1.0 if (atk_k + atk_e + atk_x + atk_cryo) > 0.0 else 0.0
	return [dmg_shield * variance, maxf(minhull, hull * variance), is_crit]

func _win_combat() -> void:
	_roll_loot(enemy_inst["loot"], get_combat_loot_multiplier(), 0, true)
	add_xp("combat", int(enemy_inst["xp"] * (1.0 + research_bonus("combat_xp"))))
	bounty_on_kill(active_id)
	standing_on_kill(active_id)
	_mission_event("defeat", active_id, 1)
	_event("DESTROYED", "5fd585", "enemy")
	# On-kill affixes
	var cap := minf(affix_total("capacitor_pulse"), 0.30)
	if cap > 0.0:
		player_shield = minf(player_max_shield(), player_shield + player_max_shield() * cap)
	var nan := minf(affix_total("nanite_resurgence"), 0.30)
	if nan > 0.0:
		combat_hp = minf(combat_max_hp(), combat_hp + combat_max_hp() * nan)
	# v85.2 Overdrive Catalyst: chance on kill to surge fire rate for 5s (ref ~L1982).
	var berserk := affix_total("berserk_on_kill")
	if berserk > 0.0 and randf() < berserk:
		_player_berserk_timer = 5.0
		_event("OVERDRIVEN!", "ff6a40", "player")
	var scav := affix_total("nano_scavenger")
	if scav > 0.0 and randf() < scav:
		var parts := ["Circuit", "Chip", "AdvCircuit"]
		var p: String = parts[randi() % parts.size()]
		var pq := 1 + int(_combat_difficulty() / 3.0)
		add_resource(p, pq)
		_log_session_loot(p, pq)
		_event("SCAVENGED " + GameData.res_name(p), "55d3e6", "enemy")
	# Rolled module drop (rarity + affixes). v109: bosses burst — roll 4-10 modules
	# bypassing the drop-chance gate (ref ~L2075-2081); regulars keep the single
	# drop_chance-gated roll.
	var pool := []
	for mid in enemy_inst.get("drop_pool", []):
		if GameData.MODULES.has(mid) and module_unlocked(mid):
			pool.append(mid)
	if not pool.is_empty():
		var is_boss: bool = bool(enemy_inst.get("is_boss", false))
		if is_boss:
			for _i in randi_range(4, 10):
				_roll_one_module_drop(pool)
		else:
			var dc: float = float(enemy_inst.get("drop_chance", 0.0)) * (1.0 + research_bonus("xeno_engineering"))
			if enemy_inst.get("elite", false):
				dc = minf(1.0, dc * 3.0)
			if dc > 0.0 and randf() < dc:
				_roll_one_module_drop(pool)
	# Set-piece drop: bosses drop their themed set pieces (8% chance).
	for sn in GameData.SETS:
		var sd: Dictionary = GameData.SETS[sn]
		if sd.get("boss", "") == active_id and randf() < 0.08:
			var pieces: Array = sd.get("pieces", [])
			if not pieces.is_empty():
				var scid := _grant_set_piece(pieces[randi() % pieces.size()])
				_log_session_loot(scid, 1)
				_event("SET PIECE!", "ff44cc", "enemy")
			break
	# Gem drop (rare; quality scales with zone difficulty).
	if randf() < 0.03:
		var diff := _combat_difficulty()
		var tier := "Cracked" if diff < 4 else ("Stable" if diff < 8 else "Pristine")
		var colors := ["Crimson", "Cobalt", "Topaz", "Amethyst"]
		var gid := "%s%sCore" % [tier, colors[randi() % colors.size()]]
		if GameData.GEMS.has(gid):
			add_resource(gid, 1)
			_log_session_loot(gid, 1)
			_event("GEM: " + GameData.GEMS[gid]["name"], "3a9fff", "enemy")
	# v86.0 Track boss kills (hazard unlocks + Z11 flag). Use the live enemy id
	# (hazard waves override active_id with their pool enemy).
	var killed_id: String = String(enemy_inst.get("id", active_id))
	if bool(enemy_inst.get("is_boss", false)) or GameData.ENEMIES.get(killed_id, {}).get("is_boss", false):
		boss_kills[killed_id] = int(boss_kills.get(killed_id, 0)) + 1
		# v80.1 Boss Core drop: zone bosses grant their ZN_Core, which gates the
		# zone_N_access research (desktop ref_combat_manager.gd ~L1964-1975).
		var core_id: String = String(enemy_inst.get("boss_core", GameData.ENEMIES.get(killed_id, {}).get("boss_core", "")))
		if core_id != "":
			add_resource(core_id, 1)
			_log_session_loot(core_id, 1)
			_event("BOSS CORE: " + GameData.res_name(core_id), "ffa040", "enemy")
	# v109 Z10 boss kill auto-unlocks Zone 11 "The Threshold" (flag, not research).
	if killed_id == "z10_boss_leviathan" and not game_flags.get("z11_unlocked", false):
		game_flags["z11_unlocked"] = true
		_event("SECTOR 11 DETECTED", "8cd9ff", "player")
	# v86.0 Hazard gauntlet progression: advance the wave instead of re-engaging.
	if hazard_state.get("active", false):
		hazard_state["wave"] = int(hazard_state["wave"]) + 1
		if int(hazard_state["wave"]) >= int(hazard_state["max_waves"]):
			_complete_hazard_zone()
		else:
			_spawn_hazard_wave_enemy()
			_event("WAVE %d/%d" % [int(hazard_state["wave"]) + 1, int(hazard_state["max_waves"])], "ecb44a", "player")
		return
	_spawn_enemy_inst(active_id)   # auto re-engage (idle farming)

# v109 single rarity-rolled module drop from the unlocked pool (ref _roll_one_module_drop
# ~L1892). Bosses call this 4-10x; regulars once behind the drop_chance gate.
func _roll_one_module_drop(pool: Array) -> void:
	if pool.is_empty():
		return
	var base_id: String = pool[randi() % pool.size()]
	var rarity := roll_rarity(bool(enemy_inst.get("is_boss", false)) or enemy_inst.get("elite", false))
	var cid := generate_module(base_id, rarity, _combat_difficulty())
	if cid != "":
		_log_session_loot(cid, 1)
		_event("%s DROP" % (RARITY_LABEL[rarity] if rarity > 0 else "MODULE").to_upper(), RARITY_COLOR.get(rarity, "b78ae8"), "enemy")
		_mission_sync()   # drop_rarity missions re-check on a new module drop

func _lose_combat() -> void:
	var cost := mini(repair_cost(), credits)   # repair fee on defeat (capped at available credits)
	credits -= cost
	combat_hp = combat_max_hp()
	player_shield = 0.0
	_event("HULL BREACH  −₡%s" % GameData.fmt(cost), "ef6a52", "player")
	# v86.0 Hazard: ejected on death — abandon the gauntlet run.
	if hazard_state.get("active", false):
		_event("HAZARD FAILED", "ef6a52", "player")
		_reset_hazard_state()
	stop_task()

# ---------------- v86.0 Hazard zones (gauntlet dungeons) ----------------
# Data-driven from GameData.HAZARD_ZONES. A hazard unlocks once its unlock_boss
# has >=1 kill; it runs max_waves waves (regular pool, elite at max_waves-2, boss
# at max_waves-1), scaling enemy hp/atk/shield x(1+wave*0.20). First clear grants
# a reward. EMP hazards jam weapons unless the counter module is equipped.
## Public read of the per-fight enrage state for the live battle readout.
func enemy_enraged() -> bool:
	return _enemy_enraged

func is_hazard_unlocked(zone_id: String) -> bool:
	var hz: Dictionary = GameData.HAZARD_ZONES.get(zone_id, {})
	if hz.is_empty():
		return false
	var unlock_boss: String = hz.get("unlock_boss", "")
	return unlock_boss == "" or int(boss_kills.get(unlock_boss, 0)) > 0

func has_counter_module(zone_id: String) -> bool:
	var hz: Dictionary = GameData.HAZARD_ZONES.get(zone_id, {})
	if hz.is_empty():
		return false
	var counter: String = hz.get("counter_module", "")
	return counter == "" or loadout_has_module(counter)

func _active_hazard_type() -> String:
	if not hazard_state.get("active", false):
		return ""
	return GameData.HAZARD_ZONES.get(hazard_state["zone_id"], {}).get("hazard_type", "")

func _reset_hazard_state() -> void:
	hazard_state = {"active": false, "zone_id": "", "wave": 0, "max_waves": 7}

## Enter a hazard gauntlet. Gated by the unlock boss + counter module. Returns
## true if entry succeeded. Adapts the desktop start_hazard to mobile's task flow.
func start_hazard(zone_id: String) -> bool:
	var hz: Dictionary = GameData.HAZARD_ZONES.get(zone_id, {})
	if hz.is_empty():
		return false
	if not is_hazard_unlocked(zone_id):
		_event("LOCKED", "ef6a52", "player")
		return false
	var counter: String = hz.get("counter_module", "")
	if counter != "" and not loadout_has_module(counter):
		_event("REQUIRES %s" % counter.to_upper(), "ef6a52", "player")
		return false
	if active_hull == "":
		return false
	hazard_state = {"active": true, "zone_id": zone_id, "wave": 0, "max_waves": int(hz.get("max_waves", 7))}
	active_type = "combat"
	active_id = zone_id
	progress = 0.0
	_weapons = ship_weapons()
	if combat_hp <= 0.0:
		combat_hp = combat_max_hp()
	player_shield = player_max_shield()
	player_heat = 0.0
	_overheat_lock = 0.0
	_enemy_timer = 0.0
	combat_events.clear()
	session_loot = {}   # fresh hazard run — clear the session-loot tally
	_spawn_hazard_wave_enemy()
	_event("HAZARD: %s" % String(hz.get("name", zone_id)).to_upper(), "ecb44a", "player")
	_event("WAVE 1/%d" % int(hazard_state["max_waves"]), "ecb44a", "player")
	action_changed.emit()
	return true

func _spawn_hazard_wave_enemy() -> void:
	var hz: Dictionary = GameData.HAZARD_ZONES.get(hazard_state["zone_id"], {})
	var wave := int(hazard_state["wave"])
	var max_waves := int(hazard_state["max_waves"])
	var pool: Array = hz.get("enemy_pool", [])
	var eid: String = pool[0] if not pool.is_empty() else ""
	if wave == max_waves - 1:
		eid = hz.get("boss_enemy", eid)
	elif wave == max_waves - 2:
		eid = hz.get("elite_enemy", eid)
	elif not pool.is_empty():
		eid = pool[wave % pool.size()]
	_spawn_enemy_inst(eid)
	# Scale stats by wave progression (+20% per wave), then refill HP/shield.
	var wave_mult := 1.0 + float(wave) * 0.20
	enemy_inst["max_hp"] = float(enemy_inst["max_hp"]) * wave_mult
	enemy_inst["hp"] = enemy_inst["max_hp"]
	enemy_inst["atk"] = float(enemy_inst["atk"]) * wave_mult
	enemy_inst["max_shield"] = float(enemy_inst.get("max_shield", 0.0)) * wave_mult
	enemy_inst["shield"] = enemy_inst["max_shield"]

func _complete_hazard_zone() -> void:
	var hz_id: String = hazard_state["zone_id"]
	var hz: Dictionary = GameData.HAZARD_ZONES.get(hz_id, {})
	_event("HAZARD CLEARED!", "ffcc33", "player")
	if not hazard_clears.get(hz_id, false):
		hazard_clears[hz_id] = true
		var reward: String = hz.get("first_clear_reward", "")
		if reward != "":
			add_resource(reward, 1)
			_event("FIRST CLEAR REWARD", "ffcc33", "player")
	_reset_hazard_state()
	stop_task()

func _offline_combat(delta: float) -> void:
	var e: Dictionary = GameData.ENEMIES.get(active_id, {})
	if e.is_empty():
		return
	var diff := _combat_difficulty()
	var k := maxf(20.0, float(diff) * 50.0)
	var pdps := avg_player_dps() * (1.0 - float(e.get("def", 0)) / (float(e.get("def", 0)) + k))
	pdps = maxf(1.0, pdps)
	var ehp := float(e.get("hp", 10)) + float(e.get("max_shield", 0))
	var kill_time := ehp / pdps
	if kill_time <= 0.0:
		return
	var reps := int(delta / kill_time)
	if reps <= 0:
		return
	var pdef := float(ship_stats().get("def", 0.0))
	var edps := float(e.get("atk", 0)) / maxf(0.5, float(e.get("interval", 2.5))) * (1.0 - pdef / (pdef + k))
	var sustain := float(ship_stats().get("shield_regen", 0.0)) + (50.0 if has_set_bonus("patient_zero") else 0.0)
	if edps > sustain:
		return   # not survivable unattended
	# v101 offline parity: loot scales by the same combat multiplier as online, and
	# each kill rolls module drops (ref calculate_offline ~L2449-2511).
	var summary := _offline_loot(e.get("loot", []), get_combat_loot_multiplier(), reps)
	var pool := []
	for mid in e.get("drop_pool", []):
		if GameData.MODULES.has(mid) and module_unlocked(mid):
			pool.append(mid)
	if not pool.is_empty():
		var dc: float = float(e.get("drop_chance", 0.0)) * (1.0 + research_bonus("xeno_engineering"))
		var mods := 0
		for _i in reps:
			if dc > 0.0 and randf() < dc:
				var base_id: String = pool[randi() % pool.size()]
				var rarity := roll_rarity(false)
				if generate_module(base_id, rarity, diff) != "":
					mods += 1
		if mods > 0:
			summary += "+%d Modules  " % mods
	add_xp("combat", int(e.get("xp", 0)) * reps)
	combat_hp = combat_max_hp()
	player_shield = player_max_shield()
	pending_offline = "Away for %s\n\nDestroyed %d %s\n%s\n+%d Combat XP" % [_fmt_time(delta), reps, e.get("name", ""), summary, int(e.get("xp", 0)) * reps]

func current_duration() -> float:
	return effective_duration(active_type, active_id)

func effective_duration(type: String, id: String) -> float:
	if type == "gather" and GameData.GATHER.has(id):
		return float(GameData.GATHER[id].get("duration", 4.0)) / gather_speed_mult(id)
	elif type == "craft" and GameData.CRAFT.has(id):
		return float(GameData.CRAFT[id].get("duration", 4.0)) / recipe_speed_mult(id)
	return 0.0

# Per-action gathering speed techs (ported from gathering_manager.get_action_speed_multiplier)
const GATHER_SPEED_TECH := {
	"gather_dirt": [["diamond_drills", 0.50], ["ultrasonic_drills", 0.50], ["plasma_bore", 0.75]],
	"collect_water": [["high_flow_pumps", 0.50], ["superfluid_intake", 0.50], ["hydro_vortex", 0.75]],
	"gather_wood": [["laser_cutters", 0.50], ["mono_filament", 0.50], ["molecular_disassembler", 0.75]],
	"harvest_nebula": [["magnetic_funnels", 0.25]],
}

func gather_speed_mult(id: String) -> float:
	var m := 1.0
	for row in GATHER_SPEED_TECH.get(id, []):
		if is_research_unlocked(row[0]):
			m += float(row[1])
	m += building_count("biosphere_dome") * 0.05           # Biosphere Dome: +5% gather speed/bldg
	m *= 1.0 / mastery_dur_mult(id)                        # per-action Mastery: faster as it levels
	return m * warp_gathering_mult()                       # prestige boosts gather via speed

# Per-recipe processing speed techs (ported from processing_manager.get_recipe_speed_multiplier)
const RECIPE_SPEED_TECH := {
	"centrifuge_dirt": [["fast_centrifuges", 0.25], ["maglev_bearings", 0.50], ["quantum_separators", 0.75]],
	"electrolysis": [["catalytic_electrodes", 0.25], ["ion_exchange", 0.50], ["resonance_splitters", 0.75]],
	"charcoal_burning": [["pyrolysis_control", 0.25]],
	"smelt_steel_basic": [["blast_furnace", 0.25]],
	"smelt_steel_oxygen": [["blast_furnace", 0.25]],
	"press_graphite": [["hydraulic_press", 0.25]],
}

func recipe_speed_mult(id: String) -> float:
	var m := 1.0 + level_of("fabrication") * 0.01           # +1% Engineering / level
	for row in RECIPE_SPEED_TECH.get(id, []):
		if is_research_unlocked(row[0]):
			m += float(row[1])
	m += research_bonus("processing_speed")                 # nano_fabrication / perfect_automation
	m += research_bonus("industrial_logistics")             # hub +10%
	m += affix_total("refinery_link")                       # module affix
	# Infrastructure speed buildings
	if int(buildings.get("fabricator", 0)) > 0: m += 0.20
	if int(buildings.get("catalyst_chamber", 0)) > 0: m += 0.25
	if int(buildings.get("silver_catalyst_bay", 0)) > 0: m += 0.15
	if level_of("fabrication") >= 10: m *= 1.10             # milestone 10
	if level_of("fabrication") >= 25: m *= 1.11             # milestone 25
	m *= tree_processing_speed_bonus()                      # E2 Recipe Efficiency: -10% duration
	m *= 1.0 / mastery_dur_mult(id)                         # per-recipe Mastery: faster as it levels
	return m

func _tick_active(delta: float) -> void:
	if active_type == "":
		return
	if active_type == "combat":
		_tick_combat(delta)
		return
	if active_type == "craft" and not can_afford(GameData.CRAFT[active_id].get("inputs", {})):
		stop_task()
		return
	progress += delta
	var dur := current_duration()
	if dur <= 0.0:
		return
	while progress >= dur:
		progress -= dur
		_complete_active()
		if active_type == "":
			break

## Rolls a loot table [[sym, chance, min, max], ...], applying a yield multiplier.
# Accumulate a combat drop into the per-engagement session tally (desktop session-loot).
# Called ONLY at combat grant sites, never from generic add_resource, so it never
# double-counts gather/craft yields.
func _log_session_loot(id: String, qty: int) -> void:
	if id == "" or qty <= 0:
		return
	session_loot[id] = int(session_loot.get(id, 0)) + qty

func _roll_loot(loot: Array, mult: float, flat: int = 0, log_session: bool = false) -> void:
	for row in loot:
		if randf() < float(row[1]):
			var amt := maxi(1, int(round((randi_range(int(row[2]), int(row[3])) + flat) * mult)))
			if row[0] == "credits":
				# v109 Recursive Acquisition (wealth_focus): +5%/level Lira from combat.
				var cr := int(amt * credit_reward_mult())
				gain_credits(cr)
				if log_session:
					_log_session_loot("credits", cr)
				resources_changed.emit()
			else:
				add_resource(row[0], amt)
				if log_session:
					_log_session_loot(row[0], amt)

func _loot_snapshot(items) -> Dictionary:
	var snap := {}
	for it in items:
		var sym = it[0] if it is Array else it
		snap[sym] = amount(sym)
	return snap

## Glanceable production rate of the active task — the idle-appropriate readout
## (e.g. "▲ 340 Dirt/min") shown ambiently on the active banner.
func action_rate_text() -> String:
	return rate_text(active_type, active_id)

## Production rate of any gather/craft action (dominant output per minute), so
## cards can show it before you start — lets idle players compare actions.
func rate_text(type: String, id: String) -> String:
	if type == "gather" and GameData.GATHER.has(id):
		var a: Dictionary = GameData.GATHER[id]
		var dur := effective_duration("gather", id)
		if dur <= 0.0:
			return ""
		var ym := yield_mult("harvesting")
		var best := ""
		var bestrate := 0.0
		for row in a.get("loot", []):
			if row[0] == "credits":
				continue
			var avg := (int(row[2]) + int(row[3])) / 2.0 * float(row[1])
			var rate := avg * ym / dur * 60.0
			if rate > bestrate:
				bestrate = rate
				best = row[0]
		if best == "":
			return ""
		return "▲ %s %s/min" % [GameData.fmt(int(bestrate)), GameData.res_name(best)]
	elif type == "craft" and GameData.CRAFT.has(id):
		var r: Dictionary = GameData.CRAFT[id]
		var dur := effective_duration("craft", id)
		if dur <= 0.0:
			return ""
		var eff := research_efficiency_mult()
		var best := ""
		var bestrate := 0.0
		for sym in r.get("outputs", {}):
			var rate := float(r["outputs"][sym]) * eff / dur * 60.0
			if rate > bestrate:
				bestrate = rate
				best = sym
		if best == "":
			return ""
		return "▲ %s %s/min" % [GameData.fmt(int(bestrate)), GameData.res_name(best)]
	return ""

## Per-building production rate (dominant yield/min at the given/current count).
func building_rate_text(bid: String) -> String:
	var d: Dictionary = GameData.BUILDINGS.get(bid, {})
	var yld: Dictionary = d.get("yield", {})
	if yld.is_empty():
		return ""
	var n := maxi(1, building_count(bid))     # owned count, or a per-1 preview
	var ei: float = maxf(0.05, float(d.get("interval", 1.0)) / _infra_skill_speed())
	var gyb := _global_yield_bonus()
	var units := _dr_units(n)                  # v109 P0.2 diminishing returns
	var eng := _eng_scale(bid)                 # v109 P0.3 capped engineering scaling
	var ore := _ore_throttle(bid)              # v109 P1.4 ore throttle
	var best := ""
	var bestrate := 0.0
	for sym in yld:
		var per := float(yld[sym]) * units * eng * ore * (1.0 + float(gyb.get(sym, 0.0))) * warp_production_mult()
		var rate := per * (60.0 / ei)
		if rate > bestrate:
			bestrate = rate
			best = sym
	if best == "":
		return ""
	return "▲ %s %s/min" % [GameData.fmt(int(bestrate)), GameData.res_name(best)]

func _complete_active() -> void:
	if active_type == "gather":
		var a: Dictionary = GameData.GATHER[active_id]
		_roll_loot(a.get("loot", []), yield_mult("harvesting"), int(research_bonus("gathering_yield")))
		add_xp("harvesting", int(a.get("xp", 0)))
		gain_mastery_xp(active_id)                          # per-action Mastery: +1 per loop
	elif active_type == "craft":
		var r: Dictionary = GameData.CRAFT[active_id]
		if not can_afford(r.get("inputs", {})):
			stop_task()
			return
		spend(r.get("inputs", {}))
		_grant_craft_outputs(active_id, r, 1)
		add_xp("fabrication", int(r.get("xp", 0)))
		gain_mastery_xp(active_id)                          # per-recipe Mastery: +1 per loop

## Grants a recipe's outputs for `count` completions, applying the same yield
## rules as the desktop processing_manager: efficiency multiplier (2–32×),
## oxygen-blast-furnace ×5 Steel, milestone-50 5% double, plus the bonus table
## (efficiency-scaled, with scrap-recycling extra rolls).
func _grant_craft_outputs(rid: String, r: Dictionary, count: int) -> void:
	var eff := research_efficiency_mult()
	var oxy_steel: bool = is_research_unlocked("oxygen_blast_furnace")
	var m50 := level_of("fabrication") >= 50
	for sym in r.get("outputs", {}):
		var per := float(r["outputs"][sym])
		if sym == "Steel" and oxy_steel:
			per *= 5.0
		per *= eff
		var total := per * count
		if m50:                                            # 5% chance per unit to double
			var doubles := 0
			for _i in range(mini(count, 4096)):
				if randf() < 0.05:
					doubles += 1
			total += per * doubles
		add_resource(sym, int(round(total)))
	# Bonus / output table — efficiency-scaled, scrap recycling adds rolls.
	var rolls := 1
	if rid == "recycle_scrap":
		rolls += int(research_bonus("scrap_rolls"))
	for _r in range(rolls):
		for _c in range(count):
			_roll_loot(r.get("bonus", []), eff)

# ---------------- Offline ----------------
func _apply_offline(delta: float) -> void:
	if active_type == "" or delta < 5.0:
		return
	if active_type == "combat":
		if offline_combat:
			_offline_combat(delta)
		return
	var dur := current_duration()
	if dur <= 0.0:
		return
	var reps := int(delta / dur)
	if reps <= 0:
		return

	if active_type == "gather":
		var a: Dictionary = GameData.GATHER[active_id]
		var summary := _offline_loot(a.get("loot", []), yield_mult("harvesting"), reps)
		add_xp("harvesting", int(a.get("xp", 0)) * reps)
		gain_mastery_xp(active_id, float(reps))             # batch Mastery for offline loops
		pending_offline = "Away for %s\n\n%s\n+%d Harvesting XP" % [_fmt_time(delta), summary, int(a.get("xp", 0)) * reps]
	elif active_type == "craft":
		var r: Dictionary = GameData.CRAFT[active_id]
		var by_inputs := 0x7FFFFFFF
		for sym in r.get("inputs", {}):
			by_inputs = mini(by_inputs, int(amount(sym) / int(r["inputs"][sym])))
		var count := mini(reps, by_inputs)
		if count <= 0:
			return
		spend(r.get("inputs", {}), count)
		var before := {}
		for sym in r.get("outputs", {}):
			before[sym] = amount(sym)
		_grant_craft_outputs(active_id, r, count)
		var summary := ""
		for sym in r.get("outputs", {}):
			var made := amount(sym) - int(before[sym])
			summary += "\n+%s %s" % [GameData.fmt(made), GameData.res_name(sym)]
		add_xp("fabrication", int(r.get("xp", 0)) * count)
		gain_mastery_xp(active_id, float(count))            # batch Mastery for offline loops
		pending_offline = "Away for %s\n%s\n+%d Fabrication XP" % [_fmt_time(delta), summary, int(r.get("xp", 0)) * count]

func _offline_loot(loot: Array, mult: float, reps: int) -> String:
	var s := ""
	for row in loot:
		var avg: float = (int(row[2]) + int(row[3])) / 2.0 * float(row[1])
		var got := int(round(avg * mult * reps))
		if got > 0:
			if row[0] == "credits":
				gain_credits(got)
				s += "+₡%s  " % GameData.fmt(got)
			else:
				add_resource(row[0], got)
				s += "+%s %s  " % [GameData.fmt(got), GameData.res_name(row[0])]
	return s

func _fmt_time(secs: float) -> String:
	var s := int(secs)
	var h := s / 3600
	var m := (s % 3600) / 60
	if h > 0: return "%dh %dm" % [h, m]
	if m > 0: return "%dm %ds" % [m, s % 60]
	return "%ds" % s

# ---------------- Save / load ----------------
func save_game() -> void:
	var data := {
		"version": 2,
		"resources": resources,
		"credits": credits,
		"lifetime_credits": lifetime_credits,
		"storage_upgrades": storage_upgrades,
		"repeatable_research": repeatable_research,
		"offline_combat": offline_combat,
		"warp_shards": warp_shards,
		"total_warps": total_warps,
		"purchased_nodes": purchased_nodes,
		"warp_shards_spent": warp_shards_spent,
		"cryo_unlocked": cryo_unlocked,
		"credits_at_warp_start": credits_at_warp_start,
		"skills": skills,
		"mastery": mastery,
		"research": unlocked_research.keys(),
		"active_type": active_type,
		"active_id": active_id,
		"progress": progress,
		"combat_hp": combat_hp,
		"active_hull": active_hull,
		"owned_hulls": owned_hulls.keys(),
		"module_inventory": module_inventory,
		"custom_modules": custom_modules,
		"loadout": loadout,
		"ammo_loadout": ammo_loadout,
		"consumable_hull_slot": consumable_hull_slot,
		"consumable_shield_slot": consumable_shield_slot,
		"loadout_presets": loadout_presets,
		"buildings": buildings,
		"building_throttle": building_throttle,
		"infra_energy": infra_energy,
		"bounty_available": bounty_available,
		"bounty_active": bounty_active,
		"bounty_refresh_timer": bounty_refresh_timer,
		"bounty_total": bounty_total,
		"bounty_id": _bounty_id,
		"standing_board": standing_board,
		"standing_total": standing_total,
		"standing_id": _standing_id,
		"missions_active": missions_active.keys(),
		"missions_progress": missions_progress,
		"missions_claimed": missions_claimed.keys(),
		"boss_kills": boss_kills,
		"hazard_clears": hazard_clears,
		"game_flags": game_flags,
		"character_name": character_name,
		"created_at": _created_at,
		"time": Time.get_unix_time_from_system(),
	}
	if current_slot == 0:        # no active slot — nothing to write to
		return
	var path := slot_path(current_slot)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
	DirAccess.rename_absolute(tmp, path)

func load_game() -> void:
	var path := slot_path(current_slot) if current_slot != 0 else SAVE_PATH
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(txt) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return
	var data: Dictionary = json.data
	resources = data.get("resources", {})
	credits = int(data.get("credits", 0))
	lifetime_credits = int(data.get("lifetime_credits", credits))
	storage_upgrades = int(data.get("storage_upgrades", 0))
	repeatable_research = data.get("repeatable_research", {})
	offline_combat = bool(data.get("offline_combat", false))
	for k in repeatable_research:
		repeatable_research[k] = int(repeatable_research[k])
	warp_shards = float(data.get("warp_shards", 0.0))
	total_warps = int(data.get("total_warps", 0))
	purchased_nodes = data.get("purchased_nodes", {})
	warp_shards_spent = float(data.get("warp_shards_spent", 0.0))
	# Back-compat: pre-v111 saves with warps predate the flag — infer it.
	cryo_unlocked = bool(data.get("cryo_unlocked", total_warps > 0))
	credits_at_warp_start = int(data.get("credits_at_warp_start", 0))
	skills = data.get("skills", skills)
	# Per-action Mastery — defaults to empty so pre-mastery saves load unchanged.
	mastery = {}
	var saved_mastery = data.get("mastery", {})
	if saved_mastery is Dictionary:
		for k in saved_mastery:
			mastery[k] = float(saved_mastery[k])
	unlocked_research = {}
	for r in data.get("research", []):
		unlocked_research[r] = true
	active_type = data.get("active_type", "")
	active_id = data.get("active_id", "")
	progress = float(data.get("progress", 0.0))
	combat_hp = float(data.get("combat_hp", 0.0))
	active_hull = data.get("active_hull", "")
	owned_hulls = {}
	for hid in data.get("owned_hulls", []):
		owned_hulls[hid] = true
	module_inventory = data.get("module_inventory", {})
	for k in module_inventory:
		module_inventory[k] = int(module_inventory[k])
	custom_modules = data.get("custom_modules", {})
	ammo_loadout = data.get("ammo_loadout", {})
	consumable_hull_slot = data.get("consumable_hull_slot", "")
	consumable_shield_slot = data.get("consumable_shield_slot", "")
	# Presets: JSON stringifies the int slot keys — re-key to int on load.
	var lp: Dictionary = data.get("loadout_presets", {})
	if not lp.is_empty():
		var restored := {}
		for raw_idx in lp:
			restored[int(raw_idx)] = lp[raw_idx]
		for i in [1, 2, 3]:
			if not restored.has(i):
				restored[i] = {"name": "", "loadout": {}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""}
		loadout_presets = restored
	loadout = data.get("loadout", {})
	buildings = data.get("buildings", {})
	for k in buildings:
		buildings[k] = int(buildings[k])
	building_throttle = data.get("building_throttle", {})
	infra_energy = float(data.get("infra_energy", 0.0))
	bounty_available = data.get("bounty_available", [])
	bounty_active = data.get("bounty_active", [])
	bounty_refresh_timer = float(data.get("bounty_refresh_timer", 0.0))
	bounty_total = int(data.get("bounty_total", 0))
	_bounty_id = int(data.get("bounty_id", 0))
	standing_board = data.get("standing_board", [])
	standing_total = int(data.get("standing_total", 0))
	_standing_id = int(data.get("standing_id", 0))
	ensure_standing_board()   # populate fresh saves / sync gather progress on load
	missions_active = {}
	for mid in data.get("missions_active", []):
		missions_active[mid] = true
	missions_progress = data.get("missions_progress", {})
	for k in missions_progress:
		missions_progress[k] = int(missions_progress[k])
	missions_claimed = {}
	for mid in data.get("missions_claimed", []):
		missions_claimed[mid] = true
	# Core goals stay hidden until the tutorial is done (also strips them from
	# older saves that surfaced them during the tutorial).
	_surface_core_goals()
	boss_kills = data.get("boss_kills", {})
	for k in boss_kills:
		boss_kills[k] = int(boss_kills[k])
	hazard_clears = data.get("hazard_clears", {})
	game_flags = data.get("game_flags", {})
	character_name = String(data.get("character_name", "Commander"))
	_created_at = float(data.get("created_at", 0.0))
	# Reveal back-compat: saves that already passed a milestone shouldn't re-hide it.
	if is_research_unlocked("zone_6_access") or total_warps > 0:
		game_flags["warp_revealed"] = true
	if amount("VoidArtifact") > 0:
		game_flags["recursion_revealed"] = true
	_mission_sync()   # reconcile active missions with already-satisfied state on load
	var last := float(data.get("time", Time.get_unix_time_from_system()))
	var away := Time.get_unix_time_from_system() - last
	_suppress_fx = true
	_apply_offline(away)
	var infra_report := _offline_infra(away)   # buildings keep producing while away
	_suppress_fx = false
	if infra_report != "":
		if pending_offline == "":
			pending_offline = "Away for %s\n\n%s" % [_fmt_time(away), infra_report]
		else:
			pending_offline += "\n" + infra_report
	# Re-arm the live duel if a combat task was active (transient state isn't saved).
	if active_type == "combat":
		if GameData.ENEMIES.has(active_id):
			_init_combat(active_id)
		else:
			active_type = ""
			active_id = ""
	resources_changed.emit()
	skills_changed.emit()
	research_changed.emit()
	action_changed.emit()

func hard_reset() -> void:
	resources = {}
	credits = 0
	lifetime_credits = 0
	warp_shards = 0.0
	total_warps = 0
	purchased_nodes = {}
	warp_shards_spent = 0.0
	cryo_unlocked = false
	credits_at_warp_start = 0
	skills = {"harvesting": 0, "fabrication": 0, "combat": 0, "infrastructure": 0}
	mastery = {}
	unlocked_research = {}
	buildings = {}
	building_throttle = {}
	infra_energy = 0.0
	storage_upgrades = 0
	repeatable_research = {}
	_build_timers = {}
	_build_frac = {}
	_upkeep_timer = 0.0
	upkeep_efficiency = 1.0
	active_hull = "corvette_hull"
	owned_hulls = {"corvette_hull": true}
	module_inventory = {}
	custom_modules = {}
	loadout = {}
	ammo_loadout = {}
	consumable_hull_slot = ""
	consumable_shield_slot = ""
	for i in [1, 2, 3]:
		loadout_presets[i] = {"name": "", "loadout": {}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""}
	bounty_available = []
	bounty_active = []
	bounty_refresh_timer = 0.0
	bounty_total = 0
	standing_board = []
	standing_total = 0
	_standing_id = 0
	missions_active = {}
	missions_progress = {}
	missions_claimed = {}
	_mission_init()
	pending_offline = ""
	player_shield = 0.0
	player_heat = 0.0
	enemy_inst = {}
	combat_hp = combat_max_hp()
	stop_task()
	generate_bounty_pool()
	_standing_fill()
	character_name = "Commander"
	_created_at = 0.0
	# NB: hard_reset only clears IN-MEMORY state now. It must NOT delete any slot
	# file, so creating a new character can't wipe a sibling slot. The active slot's
	# on-disk file is overwritten naturally on the next save_game() (e.g. new_character).
	resources_changed.emit()
	skills_changed.emit()
	research_changed.emit()

# ---------------- Save slots (Melvor-style character select) ----------------
## Read slot n's save WITHOUT touching live state and summarize it for the picker.
## Returns {exists=false} for empty/corrupt slots.
func slot_summary(n: int) -> Dictionary:
	var path := slot_path(n)
	if not FileAccess.file_exists(path):
		return {"exists": false}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"exists": false}
	var txt := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(txt) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"exists": false}
	var data: Dictionary = json.data
	# Combat level from the saved combat XP via the same xp→level table.
	var combat_xp := 0
	var sk = data.get("skills", {})
	if sk is Dictionary:
		combat_xp = int(sk.get("combat", 0))
	var lvl := 1
	while lvl < MAX_LEVEL and combat_xp >= xp_for_level(lvl + 1):
		lvl += 1
	# Sector label = furthest-unlocked combat zone, derived from saved research.
	var research := {}
	for r in data.get("research", []):
		research[r] = true
	var gf = data.get("game_flags", {})
	if not (gf is Dictionary):
		gf = {}
	var sector := "Lunar Orbit"
	for z in GameData.ZONES:
		var unlocked := false
		if z.has("unlock_flag"):
			# Flag-gated zones (e.g. The Threshold) need the flag set — NOT open by default.
			unlocked = bool(gf.get(z["unlock_flag"], false))
		else:
			var req: String = String(z.get("research_req", ""))
			unlocked = (req == "" or research.has(req))
		if unlocked:
			sector = String(z.get("name", sector))
	return {
		"exists": true,
		"name": String(data.get("character_name", "Commander")),
		"combat_level": lvl,
		"credits": int(data.get("credits", 0)),
		"sector": sector,
		"last_played": float(data.get("time", 0.0)),
	}

## Activate slot n: load its save (computes offline) and run post-load init.
func select_slot(n: int) -> void:
	current_slot = n
	load_game()
	enter_slot()

## Create a fresh character in slot n. Resets in-memory state (without deleting any
## sibling slot file), stamps the name, runs post-load init, and writes the slot file.
func new_character(n: int, name: String) -> void:
	hard_reset()
	current_slot = n
	character_name = name if name.strip_edges() != "" else "Commander"
	_created_at = Time.get_unix_time_from_system()
	enter_slot()
	save_game()

## Delete slot n's save (and its .bak). Clears current_slot if it was active.
func delete_slot(n: int) -> void:
	var path := slot_path(n)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if FileAccess.file_exists(path + ".bak"):
		DirAccess.remove_absolute(path + ".bak")
	if current_slot == n:
		current_slot = 0

func has_any_save() -> bool:
	for n in range(1, SLOT_COUNT + 1):
		if FileAccess.file_exists(slot_path(n)):
			return true
	return false
