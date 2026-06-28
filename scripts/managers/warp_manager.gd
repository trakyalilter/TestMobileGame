extends "res://scripts/core/skill.gd"

# Prestige Manager: Warp-Core Reset
# Grants "Exotic Matter" (Warp Shards) based on total progress.

signal warped(shards_gained)
signal tree_node_purchased(node_id)  # v107: UI repaint hook on tree purchase

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
		"desc": "+15% gathering yield.", "implemented": true},
	"ENG_2": {"branch": "engineering", "cost": 2, "name": "Recipe Efficiency",
		"desc": "-15% processing action duration.", "implemented": true, "prereq": ["ENG_1"]},
	"ENG_3": {"branch": "engineering", "cost": 3, "name": "Alt-Recipe Codex",
		"desc": "Unlocks alt-recipe variants per processing tier.", "implemented": false, "prereq": ["ENG_2"]},
	"ENG_4": {"branch": "engineering", "cost": 4, "name": "Industrial Memory",
		"desc": "-20% infrastructure build cost.", "implemented": true, "prereq": ["ENG_1"]},
	"ENG_5": {"branch": "engineering", "cost": 5, "name": "Building Overclock",
		"desc": "Throttle buildings to 200% output at +50% input/unit.", "implemented": false, "prereq": ["ENG_4"]},
	"ENG_6": {"branch": "engineering", "cost": 6, "name": "Resonant Foundry",
		"desc": "A building that converts surplus primitives into Warp-Core Charge.", "implemented": false, "prereq": ["ENG_3", "ENG_5"]},
	"ENG_S1": {"branch": "engineering", "cost": 2, "step": 1, "repeatable": true, "name": "Resource Surge",
		"desc": "+6% gathering AND infrastructure yield per level.", "implemented": true, "prereq": ["ENG_1"]},
	"ENG_S2": {"branch": "engineering", "cost": 3, "step": 2, "repeatable": true, "name": "Skilling Tempo",
		"desc": "-2% active tick duration per level (floored at 40% of base).", "implemented": true, "prereq": ["ENG_2"]},

	# ===== COMBAT (reveal warp #2) — "my ship spawns already armed" =====
	"CMB_1": {"branch": "combat", "cost": 1, "name": "Hardened Hull",
		"desc": "+15% hull HP on all hulls.", "implemented": true},
	"CMB_2": {"branch": "combat", "cost": 2, "name": "Weapon Tuning",
		"desc": "+10% module damage.", "implemented": true, "prereq": ["CMB_1"]},
	"CMB_5": {"branch": "combat", "cost": 3, "name": "Cryo Overcharge",
		"desc": "+50% Cryo damage.", "implemented": true, "prereq": ["CMB_2"]},
	"CMB_3": {"branch": "combat", "cost": 5, "name": "Auxiliary Slot",
		"desc": "Unlocks a 9th module slot that accepts any module type.", "implemented": false, "prereq": ["CMB_2"]},
	"CMB_4": {"branch": "combat", "cost": 6, "name": "Matrix Core IV",
		"desc": "Unlocks the Resonant matrix-core tier (above Pristine).", "implemented": false, "prereq": ["CMB_3"]},
	"CMB_6": {"branch": "combat", "cost": 8, "name": "Vanguard Doctrine",
		"desc": "Choose a combat archetype (Glass Cannon / Bulwark / Skirmisher).", "implemented": false, "prereq": ["CMB_4"]},
	"CMB_S1": {"branch": "combat", "cost": 2, "step": 1, "repeatable": true, "name": "Arsenal Doctrine",
		"desc": "+6% module damage per level.", "implemented": true, "prereq": ["CMB_1"]},

	# ===== RECURSION (reveal warp #2) — "each warp is faster, cheaper, pays more" =====
	"REC_1": {"branch": "recursion", "cost": 1, "name": "Blueprint Cache",
		"desc": "On warp, auto-rebuild 50% of your buildings for free.", "implemented": true},
	"REC_2": {"branch": "recursion", "cost": 2, "name": "Deeper Roots",
		"desc": "Keep 40% XP through a warp (up from 30%).", "implemented": true, "prereq": ["REC_1"]},
	"REC_3": {"branch": "recursion", "cost": 4, "name": "Lowered Threshold",
		"desc": "First-shard score gate 500k -> 350k.", "implemented": true, "prereq": ["REC_2"]},
	"REC_5": {"branch": "recursion", "cost": 4, "name": "Catch-Up Cache",
		"desc": "Warp starter package ~1.8x larger.", "implemented": true, "prereq": ["REC_3"]},
	"REC_6": {"branch": "recursion", "cost": 6, "name": "Persistent Schematics",
		"desc": "Keep 55% XP through a warp (stacks with Deeper Roots).", "implemented": true, "prereq": ["REC_2"]},
	"REC_7": {"branch": "recursion", "cost": 8, "name": "Accelerated Tiering",
		"desc": "Warp Tier increments every 4 warps instead of 5.", "implemented": true, "prereq": ["REC_6"]},
	"REC_4": {"branch": "recursion", "cost": 5, "name": "Resonance Tuning",
		"desc": "Warp-Core Charge +25% efficiency and a higher bonus-shard cap.", "implemented": true, "prereq": ["REC_1"]},
	"REC_Q1": {"branch": "recursion", "cost": 2, "name": "Bulk Fabrication",
		"desc": "Unlock craft x10 / craft-to-target in processing.", "implemented": false},
	"REC_Q2": {"branch": "recursion", "cost": 3, "name": "Automated Logistics",
		"desc": "Auto-claim completed missions, quests, and bounties.", "implemented": false, "prereq": ["REC_Q1"]},
	"REC_Q3": {"branch": "recursion", "cost": 3, "name": "Loadout Presets",
		"desc": "Save module/ammo presets with one-tap equip.", "implemented": false, "prereq": ["REC_Q1"]},
	"REC_Q4": {"branch": "recursion", "cost": 3, "name": "Offline Coffer",
		"desc": "Raise the global offline cap 24h -> 36h.", "implemented": true},
	"REC_Q5": {"branch": "recursion", "cost": 5, "name": "Extended Coffer",
		"desc": "Raise the global offline cap 36h -> 48h.", "implemented": true, "prereq": ["REC_Q4"]},
	"REC_S1": {"branch": "recursion", "cost": 3, "step": 2, "repeatable": true, "name": "Shard Resonance",
		"desc": "+3% warp shards earned per level.", "implemented": true, "prereq": ["REC_1"]},
	"REC_S2": {"branch": "recursion", "cost": 2, "step": 1, "repeatable": true, "cap": 10, "name": "Blueprint Bandwidth",
		"desc": "+5% free building rebuild per level (caps at +50%).", "implemented": true, "prereq": ["REC_1"]},
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

# v121: Warp-Core Charge ("Resonance") — per-RUN accumulator. The Warp Core
# continuously consumes a basket of BASE materials (fed by always-on infra)
# ABOVE a reserve floor and accrues charge; charge converts to BONUS shards at
# execute_warp, then resets to 0. This is the continuous, tier-scaling
# base-material sink that makes building MANY primitive extractors finally pay.
# It NEVER gates active skilling — only surplus above CHARGE_RESERVE is eaten.
var warp_charge: float = 0.0

func get_warp_tier() -> int:
	# Tier increases every N warps (REC_7 Accelerated Tiering: 4 instead of 5)
	return int(total_warps / get_warps_per_tier())

func _init():
	super._init("Warp")

func calculate_warp_gains() -> int:
	# Formula based on LIFETIME credits earned + total buildings
	# Log2 scaling: More generous early, natural soft cap late
	var total_credits = GameState.resources.lifetime_credits - credits_at_warp_start
	var building_count = 0
	for bid in GameState.infrastructure_manager.buildings:
		building_count += GameState.infrastructure_manager.buildings[bid]
	
	var progress_score = total_credits + (building_count * 1000.0)
	progress_score *= get_tree_shard_score_mult()  # v122 REC_S1: +3%/level, applied PRE-floor
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
	credits_at_warp_start = GameState.resources.lifetime_credits
	warp_charge = 0.0   # v121: Resonance is per-run — spent at warp

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
			UITheme.show_notification("SECTOR 11 BREACHED - The Threshold. Conventional fire barely scratches these warp-hardened hulls; Cryo armaments are the key - craft stronger Cryo via Cryogenic Armaments research.", Color(0.55, 0.85, 1.0))

	# v113 (NG+ P3): clear-gated frontier — if the Threshold Warden (Z11 boss) has
	# been cleared, THIS Warp reveals Zone 12 "The Rift" (Corrosion tier). Mirrors
	# the Z11-on-Z10-kill signpost; persists across future Warps (hard reset only).
	if GameState.game_settings.get("z11_cleared", false) and not GameState.game_settings.get("z12_unlocked", false):
		GameState.game_settings["z12_unlocked"] = true
		if GameState.combat_manager:  # v113: refresh the sector list so Z12 shows
			GameState.combat_manager.zones_changed.emit()
		if UITheme:
			UITheme.show_notification("⟨ SECTOR 12 UNLOCKED — THE RIFT ⟩  The Warp tears a corrosive frontier open. The Rift Warden gates it with Cryo then Corrosion phases — craft Corrosion Armaments and swap presets mid-fight.", Color(0.6, 0.9, 0.7))

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
	var m: float = 1.15 if is_node_purchased("ENG_1") else 1.0   # ENG_1 +15%
	m *= 1.0 + 0.06 * float(get_node_level("ENG_S1"))            # ENG_S1 spine
	return m

# ENG_S1 also buffs infrastructure yield (wired in infrastructure_manager).
func get_tree_infra_bonus() -> float:
	return 1.0 + 0.06 * float(get_node_level("ENG_S1"))

func get_tree_processing_speed_bonus() -> float:
	var m: float = (1.0 / 0.85) if is_node_purchased("ENG_2") else 1.0   # ENG_2 -15% dur
	var red: float = min(0.02 * float(get_node_level("ENG_S2")), 0.60)   # ENG_S2 -2%/L, floor 40%
	if red > 0.0:
		m *= 1.0 / (1.0 - red)
	return m

func get_tree_hull_bonus() -> float:
	return 1.15 if is_node_purchased("CMB_1") else 1.0   # CMB_1 +15%

func get_tree_damage_bonus() -> float:
	var m: float = 1.10 if is_node_purchased("CMB_2") else 1.0   # CMB_2 +10%
	m *= 1.0 + 0.06 * float(get_node_level("CMB_S1"))            # CMB_S1 spine
	return m

# v109: Cryo Overcharge — +50% Cryo damage, 1.0 when unpurchased.
func get_tree_cryo_bonus() -> float:
	return 1.50 if is_node_purchased("CMB_5") else 1.0

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
	return 350000.0 if is_node_purchased("REC_3") else 500000.0

# REC_5: warp starter-package multiplier.
func get_tree_starter_mult() -> float:
	return 1.8 if is_node_purchased("REC_5") else 1.0

# REC_7: warps required per Warp-Tier increment.
func get_warps_per_tier() -> int:
	return 4 if is_node_purchased("REC_7") else 5

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
	if is_node_purchased("REC_Q5"): return 2.0
	if is_node_purchased("REC_Q4"): return 1.5
	return 1.0

# === v121: Warp-Core Charge sink =========================================
# Per-tick basket the Core consumes. Spread WIDE across the PRIMITIVE pyramid:
# bulk raws (Dirt/Water/Wood) carry the dominant weight; the raw ORES
# (Malachite/Cassiterite/Bauxite/Quartz/Dolomite/ZincOre — the DR-uncapped ore
# extractors) fan demand to those 21 buildings; Fe/Si/C (low weight) are the
# converter-fed channel that keeps active processing relevant. Cu/Steel/Ti are
# intentionally OMITTED (pure converter outputs, 10/10-capped, can't be stacked).
# Values = units demanded/sec at tier 0, mult 1.0.
const CHARGE_BASKET := {
	"Dirt": 70.0, "Water": 70.0, "Wood": 55.0,
	"Malachite": 4.0, "Cassiterite": 4.0, "Bauxite": 6.0,
	"Quartz": 3.0, "Dolomite": 4.0, "ZincOre": 4.0,
	"Fe": 6.0, "Si": 6.0, "C": 4.0,
}
# Per-symbol floor: the Core only eats inventory ABOVE this, so an active
# gatherer/processor of the same material is never starved — only true surplus.
const CHARGE_RESERVE := {
	"Dirt": 5000.0, "Water": 5000.0, "Wood": 5000.0,
	"Malachite": 1000.0, "Cassiterite": 1000.0, "Bauxite": 1000.0,
	"Quartz": 1000.0, "Dolomite": 1000.0, "ZincOre": 1000.0,
	"Fe": 2000.0, "Si": 2000.0, "C": 2000.0,
}
const CHARGE_RESERVE_DEFAULT := 1000.0
const CHARGE_PER_UNIT := 1.0
# Each warp_tier multiplies the demand RATE (and thus charge gained) — LINEAR
# (1 + 0.6*tier), tracking linear extractor stacking NOT the 2^tier production
# mult. tier0=1x, tier2=2.2x, tier5=4x.
const CHARGE_TIER_COEF := 0.6

func get_charge_rate_mult() -> float:
	return 1.0 + CHARGE_TIER_COEF * float(get_warp_tier())

# Called every background tick (online) and once with elapsed delta (offline).
# Consumes a tier-scaled basket of base materials ABOVE the per-symbol reserve
# floor, accruing warp_charge. Each symbol independent: consume
# min(want, max(0, have - reserve)) — a shortfall just zeroes THAT symbol's
# contribution (partial accrual), never blocks others, never drops the active
# gatherer below the floor. Returns charge gained.
func process_charge(delta: float) -> float:
	if delta <= 0.0: return 0.0
	var tmult := get_charge_rate_mult()
	var gained := 0.0
	for sym in CHARGE_BASKET:
		var want: float = float(CHARGE_BASKET[sym]) * tmult * delta
		if want <= 0.0: continue
		var reserve: float = float(CHARGE_RESERVE.get(sym, CHARGE_RESERVE_DEFAULT))
		var have: float = GameState.resources.get_element_amount(sym)
		var avail: float = have - reserve
		if avail <= 0.0: continue
		var take: float = min(want, avail)
		if take <= 0.0: continue
		# remove_element is all-or-nothing; take <= have, so it always succeeds.
		if GameState.resources.remove_element(sym, take):
			gained += take * CHARGE_PER_UNIT
	if gained > 0.0:
		warp_charge += gained
	return gained

# Bonus shards the current warp_charge is worth. Log-scaled so early charge
# gives a real boost but saturates hard. Capped to +50% of the run's BASE shards
# (with a +1 floor once past the knee) AND an absolute +5, so it can never
# out-earn the progress_score climb that anchors the shard economy.
const CHARGE_PER_BONUS_SHARD := 250000.0
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
