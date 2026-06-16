extends "res://scripts/core/skill.gd"

# Prestige Manager: Warp-Core Reset
# Grants "Exotic Matter" (Warp Shards) based on total progress.

signal warped(shards_gained)
signal tree_node_purchased(node_id)  # v107: UI repaint hook on tree purchase

# v107: Warp Mastery Tree v1 — 2 branches × 5 nodes, spendable via shards.
# Earned warp_shards STILL drive existing global multipliers (untouched);
# warp_shards_spent tracks tree purchases. Available = shards - spent.
# Purchased nodes persist across warps (true meta-progression).
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
		"desc": "+50% Cryo damage. (Cryo weapons themselves unlock on your first Warp — this overcharges them.)", "implemented": true},
}

# Branch reveal is derived from total_warps — no separate state needed.
const BRANCH_REVEAL_WARP := {"engineering": 1, "combat": 2}

var total_warps: int = 0
var warp_shards: float = 0.0 # Permanent prestige currency (cumulative EARNED)
var credits_at_warp_start: float = 0.0 # To prevent infinite shard loop

# v107: Tree state ---------------------------------------------------------
var purchased_nodes: Dictionary = {}  # {node_id: true} — persists across warps
var warp_shards_spent: float = 0.0    # cumulative spend; available = shards - spent

func get_warp_tier() -> int:
	# Tier increases every 5 warps
	return int(total_warps / 5)

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
	if progress_score < 500000: return 0  # Lower threshold for first prestige
	
	# Shards = log2(progress / 500K) + 1
	# 500K = 1 shard, 2M = 3 shards, 16M = 6 shards, 128M = 9 shards
	var base = progress_score / 500000.0
	var shards = floor(log(max(1, base)) / log(2)) + 1
	return int(shards)

func execute_warp():
	var gains = calculate_warp_gains()
	if gains <= 0: return
	
	warp_shards += gains
	total_warps += 1
	credits_at_warp_start = GameState.resources.lifetime_credits
	
	# Cache shard count for post-reset bonuses
	var current_bonus_shards = warp_shards
	
	# RESET WORLD
	GameState.resources.reset(true)  # keep paid storage upgrades across warp (prestige)
	# Audit v42.0: Removed duplicate infrastructure_manager.reset() - handled below with decay
	
	# Reset Skill Levels with Partial Decay (Prestige Tier 1: Keep 30% XP)
	var decay = 0.7
	GameState.gathering_manager.reset(decay)
	GameState.processing_manager.reset(decay)
	GameState.infrastructure_manager.reset(decay)
	# Audit v2.0 P1-6: Research PERSISTS - only soft reset (clear in-progress, keep unlocks)
	GameState.research_manager.soft_reset()
	GameState.combat_manager.reset(decay)
	GameState.shipyard_manager.reset(decay)
	
	# Audit v2.0 P1-5: Improved Starting Bonus (5x credits + resource package)
	GameState.resources.add_currency("credits", current_bonus_shards * 5000.0)
	
	# Resource package per shard
	var base_resources = {"Fe": 50, "Si": 30, "Wood": 20, "Water": 50}
	for res in base_resources:
		GameState.resources.add_element(res, base_resources[res] * current_bonus_shards)

	# v111: Cryo unlock — Warping permanently grants Cryogenic armaments,
	# the key to the Z11 "Warp-Hardened" gate. First Warp grants a starter
	# Cryo Shard Pistol (~Z1 power) that proves the concept without
	# trivializing the Z1-Z10 re-climb. Better Cryo weapons are CRAFTED
	# with ExoticMatter (research: cryo_armaments). Runs AFTER
	# shipyard_manager.reset() so the granted weapon survives.
	GameState.game_settings["cryo_unlocked"] = true
	var sm = GameState.shipyard_manager
	if sm and sm.module_inventory.get("cryo_shard_pistol", 0) <= 0:
		sm.grant_module("cryo_shard_pistol")

	# v113 (NG+ P3): clear-gated frontier — if the Threshold Warden (Z11 boss) has
	# been cleared, THIS Warp reveals Zone 12 "The Rift" (Corrosion tier). Mirrors
	# the Z11-on-Z10-kill signpost; persists across future Warps (hard reset only).
	if GameState.game_settings.get("z11_cleared", false) and not GameState.game_settings.get("z12_unlocked", false):
		GameState.game_settings["z12_unlocked"] = true
		if UITheme:
			UITheme.show_notification("⟨ SECTOR 12 UNLOCKED — THE RIFT ⟩  The Warp tears a corrosive frontier open. The Rift Warden gates it with Cryo then Corrosion phases — craft Corrosion Armaments and swap presets mid-fight.", Color(0.6, 0.9, 0.7))

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
	return purchased_nodes.get(node_id, false)

func is_node_implemented(node_id: String) -> bool:
	if not node_id in TREE_NODES:
		return false
	return bool(TREE_NODES[node_id].get("implemented", true))

func can_purchase_node(node_id: String) -> bool:
	if not node_id in TREE_NODES:
		return false
	if is_node_purchased(node_id):
		return false
	if not is_node_implemented(node_id):
		return false  # v107: unfinished mechanic nodes refuse purchase
	var node: Dictionary = TREE_NODES[node_id]
	if not is_branch_revealed(node["branch"]):
		return false
	return get_available_shards() >= float(node["cost"])

func purchase_node(node_id: String) -> bool:
	if not can_purchase_node(node_id):
		return false
	var node: Dictionary = TREE_NODES[node_id]
	warp_shards_spent += float(node["cost"])
	purchased_nodes[node_id] = true
	tree_node_purchased.emit(node_id)
	return true

# Effect queries — other managers call these to fold tree bonuses into their
# own stat math. Returning 1.0 means "node not bought". Stat nodes only;
# unlock-mechanic nodes (E3/E4/E5/C3/C4/C5) are checked via is_node_purchased.
func get_tree_gathering_bonus() -> float:
	return 1.10 if is_node_purchased("E1") else 1.0

func get_tree_processing_speed_bonus() -> float:
	# E2: -10% duration → speed multiplier = 1 / 0.9
	return (1.0 / 0.9) if is_node_purchased("E2") else 1.0

func get_tree_hull_bonus() -> float:
	return 1.10 if is_node_purchased("C1") else 1.0

func get_tree_damage_bonus() -> float:
	return 1.10 if is_node_purchased("C2") else 1.0

# v109: C5 Cryo Overcharge — +50% Cryo damage (Cryo-only amplifier; stacks on
# top of C2's general +10%). 1.0 when unpurchased.
func get_tree_cryo_bonus() -> float:
	return 1.50 if is_node_purchased("C5") else 1.0

# === Save / Load =========================================================

func get_save_data_manager() -> Dictionary:
	var data = get_save_data()
	data["total_warps"] = total_warps
	data["warp_shards"] = warp_shards
	data["credits_at_warp_start"] = credits_at_warp_start
	data["purchased_nodes"] = purchased_nodes
	data["warp_shards_spent"] = warp_shards_spent
	return data

func load_save_data_manager(data: Dictionary):
	load_save_data(data)
	total_warps = data.get("total_warps", 0)
	warp_shards = data.get("warp_shards", 0.0)
	credits_at_warp_start = data.get("credits_at_warp_start", 0.0)
	purchased_nodes = data.get("purchased_nodes", {})
	warp_shards_spent = float(data.get("warp_shards_spent", 0.0))

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
	credits_at_warp_start = 0.0
