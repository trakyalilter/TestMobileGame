extends "res://scripts/core/skill.gd"

# Prestige Manager: Warp-Core Reset
# Grants "Exotic Matter" (Warp Shards) based on total progress.

signal warped(shards_gained)

var total_warps: int = 0
var warp_shards: float = 0.0 # Permanent prestige currency
var credits_at_warp_start: float = 0.0 # To prevent infinite shard loop

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
	GameState.resources.reset()
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

func get_save_data_manager() -> Dictionary:
	var data = get_save_data()
	data["total_warps"] = total_warps
	data["warp_shards"] = warp_shards
	data["credits_at_warp_start"] = credits_at_warp_start
	return data

func load_save_data_manager(data: Dictionary):
	load_save_data(data)
	total_warps = data.get("total_warps", 0)
	warp_shards = data.get("warp_shards", 0.0)
	credits_at_warp_start = data.get("credits_at_warp_start", 0.0)
