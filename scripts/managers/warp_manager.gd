extends "res://scripts/core/skill.gd"

# Prestige Manager: Warp-Core Reset
# Grants "Exotic Matter" (Warp Shards) based on total progress.

signal warped(shards_gained)
signal tree_node_purchased(node_id)  # v107: UI repaint hook on tree purchase
signal rift_opened(first_reveal)     # v138: the Singularity tore open (first_reveal = first time EVER)

# v107: Warp Mastery Tree v1 — 2 branches × 5 nodes, spendable via shards.
# Earned warp_shards STILL drive existing global multipliers (untouched);
# warp_shards_spent tracks tree purchases. Available = shards - spent.
# Purchased nodes persist across warps (true meta-progression).
# v122: Warp Mastery Tree v2 — 3 branches. Each = cheap FINITE "toys" + REPEATABLE
# triangular spines (cost = base + step*current_level) that absorb the long tail so
# the tree never dead-ends. `repeatable` nodes use node_levels; finite use
# purchased_nodes. `implemented:false` = stub (refuses purchase) until wired.
const TREE_NODES := {
	# ===== ENGINEERING (reveal warp #1) — "my empire rebuilds faster & bigger" =====
	"ENG_1": {"branch": "engineering", "cost": 1, "name": "Yield Calibration",
		"desc": "+1 gathering yield (flat, per gather).", "implemented": true},
	"ENG_2": {"branch": "engineering", "cost": 2, "name": "Recipe Efficiency",
		"desc": "-15% processing action duration.", "implemented": true, "prereq": ["ENG_1"]},
	"ENG_3": {"branch": "engineering", "cost": 3, "name": "Efficient Recipe",
		"desc": "-1 of each input material per craft (min 1).", "implemented": true, "prereq": ["ENG_2"]},
	"ENG_4": {"branch": "engineering", "cost": 4, "name": "Industrial Memory",
		"desc": "-20% infrastructure build cost.", "implemented": true, "prereq": ["ENG_1"]},
	"ENG_5": {"branch": "engineering", "cost": 5, "name": "Building Overclock",
		"desc": "Throttle buildings to 200% output at +50% input/unit.", "implemented": true, "prereq": ["ENG_4"]},
	"ENG_6": {"branch": "engineering", "cost": 6, "name": "Resonant Foundry",
		"desc": "Auto-feeds a fraction of your surplus primitives into the Core each cycle.", "implemented": false, "prereq": ["ENG_3", "ENG_5"]},
	"ENG_S1": {"branch": "engineering", "cost": 2, "step": 1, "repeatable": true, "name": "Resource Surge",
		"desc": "+6% gathering AND infrastructure yield per level.", "implemented": true, "prereq": ["ENG_1"]},
	"ENG_S2": {"branch": "engineering", "cost": 3, "step": 2, "repeatable": true, "name": "Skilling Tempo",
		"desc": "-2% processing duration per level (max -40%).", "implemented": true, "prereq": ["ENG_2"]},

	# ===== COMBAT (reveal warp #2) — "my ship spawns already armed" =====
	"CMB_1": {"branch": "combat", "cost": 1, "name": "Hardened Hull",
		"desc": "+15% hull HP on all hulls.", "implemented": true},
	"CMB_2": {"branch": "combat", "cost": 2, "name": "Weapon Tuning",
		"desc": "+10% module damage.", "implemented": true, "prereq": ["CMB_1"]},
	"CMB_3": {"branch": "combat", "cost": 5, "name": "Auxiliary Slot",
		"desc": "Adds one extra module slot on every hull that accepts any module type.", "implemented": true, "prereq": ["CMB_2"]},
	"CMB_4": {"branch": "combat", "cost": 6, "name": "Matrix Core IV",
		"desc": "Unlocks the Resonant matrix-core tier (fuse 3 Pristine cores into 1 Resonant).", "implemented": true, "prereq": ["CMB_3"]},
	"CMB_S1": {"branch": "combat", "cost": 2, "step": 1, "repeatable": true, "name": "Arsenal Doctrine",
		"desc": "+6% module damage per level.", "implemented": true, "prereq": ["CMB_1"]},

	# ===== RECURSION (reveal warp #2) — "each warp is faster, cheaper, pays more" =====
	"REC_1": {"branch": "recursion", "cost": 1, "name": "Blueprint Cache",
		"desc": "On warp, auto-rebuild 50% of your buildings for free.", "implemented": true},
	"REC_2": {"branch": "recursion", "cost": 2, "name": "Deeper Roots",
		"desc": "Keep 40% XP through a warp (up from 30%).", "implemented": true, "prereq": ["REC_1"]},
	"REC_6": {"branch": "recursion", "cost": 6, "name": "Persistent Schematics",
		"desc": "Keep 55% XP through a warp (stacks with Deeper Roots).", "implemented": true, "prereq": ["REC_2"]},
	"REC_4": {"branch": "recursion", "cost": 5, "name": "Resonance Tuning",
		"desc": "Warp-Core Charge +25% efficiency and a higher bonus-shard cap.", "implemented": true, "prereq": ["REC_1"]},
	"REC_S1": {"branch": "recursion", "cost": 3, "step": 2, "repeatable": true, "name": "Shard Resonance",
		"desc": "+3% warp shards earned per level.", "implemented": true, "prereq": ["REC_1"]},
	"REC_S2": {"branch": "recursion", "cost": 2, "step": 1, "repeatable": true, "cap": 10, "name": "Blueprint Bandwidth",
		"desc": "+5% free building rebuild per level (caps at +50%).", "implemented": true, "prereq": ["REC_1"]},
	"REC_S3": {"branch": "recursion", "cost": 3, "step": 2, "repeatable": true, "cap": 10, "name": "Cryptographic Cache",
		"desc": "+8% Hack Card drop rate per level (caps at +80%).", "implemented": true, "prereq": ["REC_1"]},
}

# v122: v1 node ids remapped on load (only the 5 that were ever purchasable).
const V1_NODE_REMAP := {"E1": "ENG_1", "E2": "ENG_2", "C1": "CMB_1", "C2": "CMB_2", "C5": "CMB_5"}

# Branch reveal is derived from total_warps — no separate state needed.
const BRANCH_REVEAL_WARP := {"engineering": 1, "combat": 2, "recursion": 2}

var total_warps: int = 0
var warp_shards: float = 0.0 # Permanent prestige currency (cumulative EARNED)
var credits_at_warp_start: float = 0.0 # To prevent infinite shard loop

# v107: Tree state ---------------------------------------------------------
var purchased_nodes: Dictionary = {}  # {finite_node_id: true} — persists across warps
var node_levels: Dictionary = {}      # v122: {repeatable_node_id: level} — persists across warps
var warp_shards_spent: float = 0.0    # cumulative spend; available = shards - spent

# v121 / v134h: Warp-Core Charge ("Resonance") — per-RUN accumulator. The player
# MANUALLY FEEDS surplus base materials into the Core on the Warp page (feed_core);
# each deposit accrues charge weighted by material. Charge converts to BONUS shards
# at execute_warp, then resets to 0. This is a DELIBERATE, visible base-material
# prestige sink — it never touches inventory passively, so stockpiles grow freely.
# (v134h: replaced the always-on auto-drain, which silently capped bulk basics.)
var warp_charge: float = 0.0

# v138: the SINGULARITY — warping is now diegetic. Killing any Zone-3+ boss tears
# a rift open on the Sector Chart; the player warps by ENTERING IT (the Warp page
# only spends shards / monitors). Per-RUN state: re-earned every run, closed by
# execute_warp, cleared on hard reset. The player chooses when (or whether) to
# enter — no nag, no directive ("her yiğidin yoğurt yiyişi farklıdır").
var rift_open: bool = false
var _rift_key_missing: bool = false   # save predates v138 → game_state derives once

# Open the rift (idempotent). Also flips warp_first_revealed — the prestige system
# reveals WITH the first singularity, not at a research milestone (was zone_6).
func open_rift() -> void:
	if rift_open:
		return
	rift_open = true
	var first: bool = not GameState.game_settings.get("warp_first_revealed", false)
	GameState.game_settings["warp_first_revealed"] = true
	rift_opened.emit(first)

func get_warp_tier() -> int:
	# Tier increases every N warps (REC_7 Accelerated Tiering: 4 instead of 5)
	return int(total_warps / get_warps_per_tier())

func _init():
	super._init("Warp")

# v135a: the prestige progress score — lifetime credits since last warp +
# buildings*1000, times the Recursion-tree mult. Factored so calculate_warp_gains,
# the save logout snapshot, and the header Warp-Charge gauge never disagree.
func get_progress_score() -> float:
	var total_credits = GameState.resources.lifetime_credits - credits_at_warp_start
	var building_count = 0
	for bid in GameState.infrastructure_manager.buildings:
		building_count += GameState.infrastructure_manager.buildings[bid]
	return (total_credits + building_count * 1000.0) * get_tree_shard_score_mult()

func calculate_warp_gains() -> int:
	# Formula based on LIFETIME credits earned + total buildings
	# Log2 scaling: More generous early, natural soft cap late
	var progress_score = get_progress_score()   # v135a: factored (REC mult applied inside)
	var threshold = get_tree_shard_threshold()       # v122 REC_3: 500k, or 350k if Lowered Threshold
	if progress_score < threshold: return 0

	# Shards = log2(progress / threshold) + 1  (threshold = the 1-shard anchor)
	var base = progress_score / threshold
	var shards = floor(log(max(1, base)) / log(2)) + 1
	return int(shards)

func execute_warp():
	var base_gains = calculate_warp_gains()
	if base_gains <= 0: return
	var charge_bonus = get_charge_bonus_shards(base_gains)   # v121: Warp-Core Charge
	var gains = base_gains + charge_bonus
	
	warp_shards += gains
	total_warps += 1
	warp_charge = 0.0   # v121: Resonance is per-run — spent at warp
	rift_open = false   # v138: the Singularity collapses behind you — re-earned next run (Z3+ boss)
	# v137 FIX: credits_at_warp_start is snapshotted AFTER the starter package now
	# (see the note at the grant below). Snapshotting it HERE — before the starter —
	# let the starter's lifetime_credits bump read as post-warp "progress" and
	# self-funded an infinite warp loop once cumulative shards crossed ~56.

	# Cache shard count for post-reset bonuses
	var current_bonus_shards = warp_shards

	# v122 REC_1 Blueprint Cache: snapshot a fraction of buildings BEFORE the wipe
	# so we can free-rebuild them after reset (kills the "lose all infra" dread).
	var blueprint_frac := get_blueprint_rebuild_frac()
	var blueprint_snapshot := {}
	if blueprint_frac > 0.0 and GameState.infrastructure_manager:
		for bid in GameState.infrastructure_manager.buildings:
			var keep_n := int(floor(float(GameState.infrastructure_manager.buildings[bid]) * blueprint_frac))
			if keep_n > 0:
				blueprint_snapshot[bid] = keep_n

	# RESET WORLD
	GameState.resources.reset(true)  # keep paid storage upgrades across warp (prestige)
	# Audit v42.0: Removed duplicate infrastructure_manager.reset() - handled below with decay
	
	# Reset Skill Levels with Partial Decay (v122 REC_2/REC_6: keep 30/40/55% XP)
	var decay = 1.0 - get_tree_xp_keep()
	GameState.gathering_manager.reset(decay)
	GameState.processing_manager.reset(decay)
	GameState.infrastructure_manager.reset(decay)
	# v122 REC_1 Blueprint Cache: free-rebuild the snapshotted buildings post-wipe.
	if not blueprint_snapshot.is_empty() and GameState.infrastructure_manager:
		for bid in blueprint_snapshot:
			GameState.infrastructure_manager.buildings[bid] = blueprint_snapshot[bid]
	# Audit v2.0 P1-6: Research PERSISTS - only soft reset (clear in-progress, keep unlocks)
	GameState.research_manager.soft_reset()
	GameState.combat_manager.reset(decay)
	GameState.shipyard_manager.reset(decay)
	
	# Audit v2.0 P1-5: Improved Starting Bonus (5x credits + resource package)
	var starter_mult := get_tree_starter_mult()  # v122 REC_5 Catch-Up Cache (~1.8x)
	GameState.resources.add_currency("credits", current_bonus_shards * 5000.0 * starter_mult)

	# Resource package per shard
	var base_resources = {"Fe": 50, "Si": 30, "Wood": 20, "Water": 50}
	for res in base_resources:
		GameState.resources.add_element(res, base_resources[res] * current_bonus_shards * starter_mult)

	# v137 FIX: snapshot the prestige baseline AFTER the starter inflates lifetime_credits,
	# so post-warp progress_score = 0. The starter (shards*5000*mult) must NOT count as
	# earned progress — otherwise once cumulative shards >= ~56 it alone cleared the 500k
	# threshold, re-enabled Warp instantly, and ran total_warps -> 2^warp_tier away into
	# float overflow. This var exists precisely to prevent that infinite shard loop.
	credits_at_warp_start = GameState.resources.lifetime_credits

	# v111: Cryo unlock — Warping permanently grants Cryogenic armaments,
	# the key to the Z11 "Warp-Hardened" gate. v113: NO free weapon is granted --
	# every Cryo weapon is CRAFTED from Cryo Catalyst (Sector 10) + research
	# (cryo_armaments), the Cryo Repeater first. The Forge Cryogenic Arms mission
	# guides research -> craft -> breach; this flag just opens the research.
	GameState.game_settings["cryo_unlocked"] = true
	var sm = GameState.shipyard_manager

	# v113 (NG+): Z11 "The Threshold" is warp-gated. Clearing the Z10 boss arms
	# z10_cleared; THIS Warp (which also grants Cryo above) breaches Sector 11 --
	# so the player always has Cryo the instant Z11 appears. Mirrors the
	# clear-boss -> Warp -> next-zone pattern used for Z11 -> Z12.
	if GameState.game_settings.get("z10_cleared", false) and not GameState.game_settings.get("z11_unlocked", false):
		GameState.game_settings["z11_unlocked"] = true
		if GameState.combat_manager:
			GameState.combat_manager.zones_changed.emit()
		if UITheme:
			UITheme.show_notification(tr("SECTOR 11 BREACHED - The Threshold. Conventional fire barely scratches these warp-hardened hulls; Cryo armaments are the key - craft stronger Cryo via Cryogenic Armaments research."), Color(0.55, 0.85, 1.0))

	# v113 (NG+ P3): clear-gated frontier — if the Threshold Warden (Z11 boss) has
	# been cleared, THIS Warp reveals Zone 12 "The Rift" (Corrosion tier). Mirrors
	# the Z11-on-Z10-kill signpost; persists across future Warps (hard reset only).
	if GameState.game_settings.get("z11_cleared", false) and not GameState.game_settings.get("z12_unlocked", false):
		GameState.game_settings["z12_unlocked"] = true
		if GameState.combat_manager:  # v113: refresh the sector list so Z12 shows
			GameState.combat_manager.zones_changed.emit()
		if UITheme:
			UITheme.show_notification(tr("⟨ SECTOR 12 UNLOCKED — THE RIFT ⟩  The Warp tears a corrosive frontier open. The Rift Warden gates it with Cryo then Corrosion phases — craft Corrosion Armaments and swap presets mid-fight."), Color(0.6, 0.9, 0.7))

	# v137 (NG+ step 2): Corrosion-loop sectors Z13-Z15 reveal the same way — clear the prior
	# boss (sets its z*_cleared flag in combat_manager), then any Warp opens the next. One
	# table drives all three; persists across Warp, cleared only on hard reset.
	var _ng_reveal := [
		["z12_cleared", "z13_unlocked", "⟨ SECTOR 13 UNLOCKED — THE VERDIGRIS REACH ⟩  The Warp opens the oxidized ruin. The Verdigris Warden hardens Corrosion then Cryo — swap the other way this time."],
		["z13_cleared", "z14_unlocked", "⟨ SECTOR 14 UNLOCKED — THE DISSOLUTION ⟩  A three-phase gate: Cryo → Corrosion → Cryo. Two swaps to breach the Dissolution Tyrant."],
		["z14_cleared", "z15_unlocked", "⟨ SECTOR 15 UNLOCKED — THE CAUSTIC CORE ⟩  The corrosion-loop capstone. The Caustic Sovereign opens and closes on Corrosion, Cryo between."],
	]
	for _r in _ng_reveal:
		if GameState.game_settings.get(_r[0], false) and not GameState.game_settings.get(_r[1], false):
			GameState.game_settings[_r[1]] = true
			if GameState.combat_manager:
				GameState.combat_manager.zones_changed.emit()
			if UITheme:
				UITheme.show_notification(tr(String(_r[2])), Color(0.6, 0.9, 0.7))

	# v113 (NG+ P2): Threshold Relics (master keys) persist across Warp. The reset
	# above wiped the module inventory, so re-grant + re-equip any relic the player
	# has earned (the "<id>_earned" game_settings flag, set on the boss's first
	# clear). Cleared only on hard reset.
	if sm:
		for _mid in sm.modules:
			if sm.modules[_mid].get("slot_type", "") == "relic" and GameState.game_settings.get(_mid + "_earned", false):
				if sm.module_inventory.get(_mid, 0) <= 0:
					sm.module_inventory[_mid] = 1
				if sm.equipped_relic == "":
					sm.equipped_relic = _mid

	warped.emit(gains)
	GameState.save_game()

# GLOBAL BUFFS
func get_production_multiplier() -> float:
	var base = 1.0 + (warp_shards * 0.02) # 2% per shard
	return base * pow(2.0, get_warp_tier())

func get_combat_multiplier() -> float:
	var base = 1.0 + (warp_shards * 0.03) # 3% per shard (Audit v9.0: buffed from 1%)
	return base * pow(2.0, get_warp_tier())

# Audit v2.0 P1-9: New multipliers for broader prestige impact
func get_gathering_multiplier() -> float:
	var base = 1.0 + (warp_shards * 0.015) # 1.5% per shard
	return base * pow(2.0, get_warp_tier())

func get_xp_multiplier() -> float:
	var base = 1.0 + (warp_shards * 0.025) # 2.5% per shard
	return base * pow(2.0, get_warp_tier())

# === v107: Warp Mastery Tree =============================================

func get_available_shards() -> float:
	return max(0.0, warp_shards - warp_shards_spent)

func is_branch_revealed(branch: String) -> bool:
	if not branch in BRANCH_REVEAL_WARP:
		return false
	return total_warps >= int(BRANCH_REVEAL_WARP[branch])

func is_node_purchased(node_id: String) -> bool:
	if _is_repeatable(node_id):
		return int(node_levels.get(node_id, 0)) >= 1
	return purchased_nodes.get(node_id, false)

func is_node_implemented(node_id: String) -> bool:
	if not node_id in TREE_NODES:
		return false
	return bool(TREE_NODES[node_id].get("implemented", true))

# v122: repeatable-spine helpers ------------------------------------------
func _is_repeatable(node_id: String) -> bool:
	return node_id in TREE_NODES and bool(TREE_NODES[node_id].get("repeatable", false))

func get_node_level(node_id: String) -> int:
	if _is_repeatable(node_id):
		return int(node_levels.get(node_id, 0))
	return 1 if purchased_nodes.get(node_id, false) else 0

# Next-level cost (triangular for repeatables: base + step*current_level).
func get_node_cost(node_id: String) -> int:
	if not node_id in TREE_NODES:
		return 0
	var node: Dictionary = TREE_NODES[node_id]
	if _is_repeatable(node_id):
		return int(node["cost"]) + int(node.get("step", 1)) * int(node_levels.get(node_id, 0))
	return int(node["cost"])

func _prereqs_met(node_id: String) -> bool:
	for p in TREE_NODES[node_id].get("prereq", []):
		if not is_node_purchased(p):
			return false
	return true

func can_purchase_node(node_id: String) -> bool:
	if not node_id in TREE_NODES:
		return false
	if not is_node_implemented(node_id):
		return false  # v107: unfinished mechanic nodes refuse purchase
	var node: Dictionary = TREE_NODES[node_id]
	if not is_branch_revealed(node["branch"]):
		return false
	if not _prereqs_met(node_id):
		return false
	if _is_repeatable(node_id):
		var cap: int = int(node.get("cap", 0))  # 0 = no hard cap
		if cap > 0 and int(node_levels.get(node_id, 0)) >= cap:
			return false
	elif is_node_purchased(node_id):
		return false
	return get_available_shards() >= float(get_node_cost(node_id))

func purchase_node(node_id: String) -> bool:
	if not can_purchase_node(node_id):
		return false
	warp_shards_spent += float(get_node_cost(node_id))
	if _is_repeatable(node_id):
		node_levels[node_id] = int(node_levels.get(node_id, 0)) + 1
	else:
		purchased_nodes[node_id] = true
	tree_node_purchased.emit(node_id)
	# v124: recompute ship stats so shipyard-side tree buffs apply IMMEDIATELY —
	# notably CMB_1 Hardened Hull (+15% max_hp via get_tree_hull_bonus()), which
	# otherwise wouldn't show until the next equip/combat recalc. (Gathering/
	# processing bonuses are read live; combat damage rebuilds per-fight.)
	if GameState.shipyard_manager:
		# recalc_stats() already preserves the HP ratio (full ship stays full at
		# the new max — see its _hp_ratio logic), so just recompute.
		GameState.shipyard_manager.recalc_stats()
	return true

# v122: remap v1 node ids (E1->ENG_1 …) on load so old saves keep their purchases.
func _migrate_v1_node_ids() -> void:
	for old_id in V1_NODE_REMAP:
		if purchased_nodes.has(old_id):
			purchased_nodes[V1_NODE_REMAP[old_id]] = true
			purchased_nodes.erase(old_id)

# Effect queries — other managers call these to fold tree bonuses into their
# own stat math. Returning 1.0 means "node not bought". Stat nodes only;
# unlock-mechanic nodes (E3/E4/E5/C3/C4/C5) are checked via is_node_purchased.
func get_tree_gathering_bonus() -> float:
	# ENG_1 is now a FLAT +1 (get_tree_gathering_flat); this multiplier is the ENG_S1 spine only.
	return 1.0 + 0.06 * float(get_node_level("ENG_S1"))            # ENG_S1 spine

# ENG_1 Yield Calibration: flat +1 units per gather (added AFTER yield multipliers).
func get_tree_gathering_flat() -> int:
	return 1 if is_node_purchased("ENG_1") else 0

# ENG_3 Efficient Recipe: -1 of each processing input material per craft (consumer floors at min 1).
func get_tree_recipe_material_reduction() -> int:
	return 1 if is_node_purchased("ENG_3") else 0

# ENG_S1 also buffs infrastructure yield (wired in infrastructure_manager).
func get_tree_infra_bonus() -> float:
	return 1.0 + 0.06 * float(get_node_level("ENG_S1"))

func get_tree_processing_speed_bonus() -> float:
	var m: float = (1.0 / 0.85) if is_node_purchased("ENG_2") else 1.0   # ENG_2 -15% dur
	var red: float = min(0.02 * float(get_node_level("ENG_S2")), 0.40)   # ENG_S2 -2%/L, max -40%
	if red > 0.0:
		m *= 1.0 / (1.0 - red)
	return m

func get_tree_hull_bonus() -> float:
	return 1.15 if is_node_purchased("CMB_1") else 1.0   # CMB_1 +15%

# REC_S3 Cryptographic Cache: +8%/level Hack Card drop rate (random rolls only), capped +80%.
func get_tree_card_drop_bonus() -> float:
	return min(0.08 * float(get_node_level("REC_S3")), 0.80)

func get_tree_damage_bonus() -> float:
	var m: float = 1.10 if is_node_purchased("CMB_2") else 1.0   # CMB_2 +10%
	m *= 1.0 + 0.06 * float(get_node_level("CMB_S1"))            # CMB_S1 spine
	return m


# === v122: new effect queries (Recursion meta + Engineering spines) =======
# REC_S1: scales progress_score BEFORE the log/floor (see calculate_warp_gains).
func get_tree_shard_score_mult() -> float:
	return 1.0 + 0.03 * float(get_node_level("REC_S1"))

# REC_2 / REC_6: fraction of XP kept through a warp.
func get_tree_xp_keep() -> float:
	if is_node_purchased("REC_6"): return 0.55
	if is_node_purchased("REC_2"): return 0.40
	return 0.30

# REC_3: first-shard progress_score threshold (also the shard-curve anchor).
func get_tree_shard_threshold() -> float:
	return 500000.0   # REC_3 Lowered Threshold removed

# REC_5: warp starter-package multiplier.
func get_tree_starter_mult() -> float:
	return 1.0   # REC_5 Catch-Up Cache removed

# REC_7: warps required per Warp-Tier increment.
func get_warps_per_tier() -> int:
	return 5   # REC_7 Accelerated Tiering removed

# REC_1 + REC_S2: fraction of buildings auto-rebuilt free on warp.
func get_blueprint_rebuild_frac() -> float:
	if not is_node_purchased("REC_1"):
		return 0.0
	return min(0.50 + 0.05 * float(get_node_level("REC_S2")), 1.0)

# ENG_4 Industrial Memory: infrastructure build-cost multiplier.
func get_tree_build_cost_mult() -> float:
	return 0.80 if is_node_purchased("ENG_4") else 1.0

# REC_Q4 / REC_Q5 Coffers: global offline-cap multiplier (24h base -> 36h -> 48h).
func get_tree_offline_cap_mult() -> float:
	return 1.0   # REC_Q4/REC_Q5 Coffers removed (offline cap stays at base)

# === v121 / v134h: Warp-Core Charge — MANUAL feed weights =================
# Charge-per-unit-fed by material. This one authored table is the SINGLE source of
# truth for BOTH which materials are feedable AND how much each is worth. Spread
# across the PRIMITIVE pyramid: bulk raws (Dirt/Water/Wood) carry the dominant
# weight so feeding the glut is the primary path; raw ORES mid; Fe/Si/C (refined
# bases) low. Cu/Steel/Ti are OMITTED (pure converter outputs, can't be stacked).
const CHARGE_WEIGHT := {
	"Dirt": 70.0, "Water": 70.0, "Wood": 55.0,
	"Malachite": 4.0, "Cassiterite": 4.0, "Bauxite": 6.0,
	"Quartz": 3.0, "Dolomite": 4.0, "ZincOre": 4.0,
	"Fe": 6.0, "Si": 6.0, "C": 4.0,
}
const CHARGE_PER_UNIT := 1.0
# Warp-tier multiplier on charge gained PER UNIT FED — LINEAR (1 + 0.6*tier), so a
# late-tier player's deposits are worth more. tier0=1x, tier2=2.2x, tier5=4x.
const CHARGE_TIER_COEF := 0.6

func get_charge_feed_mult() -> float:
	return 1.0 + CHARGE_TIER_COEF * float(get_warp_tier())

# Charge a deposit of `amount` units of `sym` is worth — pure, no side effects.
# Used both to preview the feed and to compute the accrual. 0 if not feedable.
func charge_value(sym: String, amount: float) -> float:
	if amount <= 0.0 or not CHARGE_WEIGHT.has(sym): return 0.0
	return amount * float(CHARGE_WEIGHT[sym]) * CHARGE_PER_UNIT * get_charge_feed_mult()

# v134h: MANUAL feed. The player deposits `amount` of `sym` from inventory into the
# Core; the material is consumed and warp_charge accrues by charge_value(). Clamps
# to what the player owns. Returns the charge gained (0 if nothing was fed).
func feed_core(sym: String, amount: float) -> float:
	if amount <= 0.0 or not CHARGE_WEIGHT.has(sym): return 0.0
	var have: float = GameState.resources.get_element_amount(sym)
	if have < amount: amount = have          # clamp to owned
	if amount <= 0.0: return 0.0
	# remove_element is all-or-nothing; amount <= have, so it always succeeds.
	if not GameState.resources.remove_element(sym, amount): return 0.0
	var gained: float = charge_value(sym, amount)
	warp_charge += gained
	return gained

# Bonus shards the current warp_charge is worth. Log-scaled so early charge
# gives a real boost but saturates hard. Capped to +50% of the run's BASE shards
# (with a +1 floor once past the knee) AND an absolute +5, so it can never
# out-earn the progress_score climb that anchors the shard economy.
# v134h: re-anchored 250k -> 1M. Manual feeds are burstier than the old passive
# drip (a single Dirt dump can be millions of charge), so the knee moved up to keep
# a normal surplus dump in the +1..+3 band and only a big hoard reaching +5.
# TUNING ESTIMATE — instrument real per-session feed volumes in playtest and adjust.
const CHARGE_PER_BONUS_SHARD := 1000000.0
const CHARGE_BONUS_FRAC_CAP := 0.5
const CHARGE_BONUS_ABS_CAP := 5

func get_charge_bonus_shards(base_shards: int = -1) -> int:
	var per: float = CHARGE_PER_BONUS_SHARD
	var abs_cap: int = CHARGE_BONUS_ABS_CAP
	if is_node_purchased("REC_4"):   # v122 REC_4 Resonance Tuning: +25% efficiency, +1 cap
		per /= 1.25
		abs_cap += 1
	if warp_charge < per: return 0
	var raw: float = floor(log(warp_charge / per) / log(2.0)) + 1.0
	var bonus := int(max(0.0, raw))
	if base_shards < 0:
		base_shards = calculate_warp_gains()
	var cap_by_base: int = (max(int(floor(float(base_shards) * CHARGE_BONUS_FRAC_CAP)), 1) if base_shards > 0 else 0)
	bonus = int(min(bonus, cap_by_base))
	bonus = int(min(bonus, abs_cap))
	return bonus

# === Save / Load =========================================================

func get_save_data_manager() -> Dictionary:
	var data = get_save_data()
	data["total_warps"] = total_warps
	data["warp_shards"] = warp_shards
	data["credits_at_warp_start"] = credits_at_warp_start
	data["purchased_nodes"] = purchased_nodes
	data["node_levels"] = node_levels          # v122: repeatable-spine levels
	data["warp_shards_spent"] = warp_shards_spent
	data["warp_charge"] = warp_charge          # v121: Warp-Core Charge
	data["rift_open"] = rift_open              # v138: per-run Singularity state
	return data

func load_save_data_manager(data: Dictionary):
	load_save_data(data)
	total_warps = data.get("total_warps", 0)
	warp_shards = data.get("warp_shards", 0.0)
	credits_at_warp_start = data.get("credits_at_warp_start", 0.0)
	purchased_nodes = data.get("purchased_nodes", {})
	node_levels = data.get("node_levels", {})           # v122: defaults {} on old saves
	_migrate_v1_node_ids()                              # v122: E1->ENG_1 … remap
	warp_shards_spent = float(data.get("warp_shards_spent", 0.0))
	warp_charge = float(data.get("warp_charge", 0.0))   # v121: defaults 0 on old saves
	rift_open = bool(data.get("rift_open", false))      # v138
	# v138 migration marker: pre-Singularity saves lack the key — game_state derives
	# the rift once from boss_kills after ALL managers load (combat isn't loaded yet here).
	_rift_key_missing = not data.has("rift_open")

# v107: Full reset for HARD RESET path only. WARP resets (execute_warp) must
# never call this — they intentionally preserve shards, total_warps, and the
# Mastery Tree purchases. Bug history: hard_reset() in game_state used to
# skip warp_manager entirely, so total_warps stayed > 0 and the "Perform your
# first Warp" mission auto-completed on a fresh game; tree purchases also
# carried through. CLAUDE.md flagged this class explicitly.
func reset(decay_factor: float = 1.0) -> void:
	super.reset(decay_factor)
	total_warps = 0
	warp_shards = 0.0
	warp_shards_spent = 0.0
	purchased_nodes = {}
	node_levels = {}    # v122: repeatable-spine levels cleared on hard reset
	credits_at_warp_start = 0.0
	warp_charge = 0.0   # v121: Warp-Core Charge cleared on hard reset
	rift_open = false   # v138: Singularity cleared on hard reset
