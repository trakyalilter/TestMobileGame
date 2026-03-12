@tool
extends SceneTree

# Local duplicate of combat/shipyard math for rapid testing
var enemy_db = {}
var modules = {}
var hulls = {}

# v80.1 Safety Caps
const MAX_ATK_SPEED_MULT = 3.0
const MAX_EVASION = 75
const MAX_CRIT_CHANCE = 0.50
const DEF_K_CONSTANT = 100.0

func _init():
	# Build pseudo-DB for testing scaling formulas
	for i in range(1, 11):
		_build_zone(i)
		
	print("=========================================")
	print("--- ZONE 4 UNIQUE GEAR VS ZONE 5 ---")
	print("=========================================")
	
	# Scenario A: Player with Z4 Unique Gear fighting Z5 Regular
	_run_sim(4, true, 5, false)
	
	# Scenario B: Player with Z4 Unique Gear fighting Z5 Boss
	_run_sim(4, true, 5, true)
	
	# Scenario C: Player with Z5 Legendary Gear fighting Z5 Boss
	_run_sim(5, false, 5, true, 1.20) # 1.20 is Legendary multiplier
	
	print("\nDone.")
	quit()

func _build_zone(zone: int):
	# Base Enemy Formula: HP=floor(200*2.2^(N-1)), ATK=floor(12*2.2^(N-1)), DEF=floor(3*2.2^(N-1))
	var mult = pow(2.2, zone - 1)
	enemy_db["z%d_reg" % zone] = {
		"hp": floor(200 * mult),
		"atk": floor(12 * mult),
		"def": floor(3 * mult),
		"max_shield": floor(50 * mult),
		"atk_interval": 2.5,
		"accuracy": 30 + (zone * 5),
		"eva": 10 + (zone * 2)
	}
	# Boss: HPx8, ATKx3, DEFx4
	enemy_db["z%d_boss" % zone] = {
		"hp": floor(200 * mult) * 8,
		"atk": floor(12 * mult) * 3,
		"def": floor(3 * mult) * 4,
		"max_shield": floor(50 * mult) * 4,
		"atk_interval": 2.5,
		"accuracy": 40 + (zone * 8),
		"eva": 15 + (zone * 3)
	}
	
	# Hull Formula (Cruiser at Z4, Battlecruiser at Z5)
	# HP = floor(80*2.2^(N-1))
	hulls[zone] = {
		"hp": floor(80 * mult),
		"slots": min(6 + (zone * 2), 26)
	}
	
	# Common Module Formulas
	# ATK Kinetic = 8, Energy = 10 -> Avg ~ 9
	modules["z%d_common" % zone] = {
		"atk": floor(9 * mult),
		"atk_interval": 2.0,
		"def": floor(5 * mult),
		"hp": floor(20 * mult),
		"max_shield": floor(40 * mult)
	}
	
	# Unique Module Formula (Proposed: 1.8x Common Base)
	modules["z%d_unique" % zone] = {
		"atk": floor(9 * mult * 1.8),
		"atk_interval": 2.0,
		"def": floor(5 * mult * 1.8),
		"hp": floor(20 * mult * 1.8),
		"max_shield": floor(40 * mult * 1.8)
	}

func _run_sim(player_gear_zone: int, is_unique: bool, enemy_zone: int, is_boss: bool, custom_rarity_mult: float = 1.25):
	var p_hull = hulls[player_gear_zone]
	var p_mod = modules["z%d_unique" % player_gear_zone] if is_unique else modules["z%d_common" % player_gear_zone]
	var e_target = enemy_db["z%d_boss" % enemy_zone] if is_boss else enemy_db["z%d_reg" % enemy_zone]
	
	# Build Player Loadout (Assuming 1/3 weapons, 1/3 shields, 1/3 armor for simplicity)
	var num_wep = floor(p_hull.slots / 3.0)
	var num_shd = floor(p_hull.slots / 3.0)
	var num_arm = floor(p_hull.slots / 3.0)
	
	# Apply rarity jump
	var rarity_mult = custom_rarity_mult
	
	# Assume Trinity set bonus (+15% dmg, +500 DEF) if Unique
	var set_dmg = 1.15 if is_unique else 1.00
	var set_def = 500 if is_unique else 0

	var p_atk = (p_mod.atk * num_wep * rarity_mult) * set_dmg
	var p_def = (p_mod.def * num_arm * rarity_mult) + set_def
	var p_hp = p_hull.hp + (p_mod.hp * num_arm * rarity_mult)
	var p_shield = (p_mod.max_shield * num_shd * rarity_mult)
	
	# --- Simulate Enemy DPS vs Player EHP ---
	# EHP = HP / (1 - Damage Reduction)
	var edmg_red = float(p_def) / (float(p_def) + DEF_K_CONSTANT)
	var p_ehp = float(p_hp) / (1.0 - edmg_red) + p_shield
	
	var e_dps = float(e_target.atk) / e_target.atk_interval
	
	var ttk_player = p_ehp / e_dps if e_dps > 0 else 99999
	
	# --- Simulate Player DPS vs Enemy EHP ---
	var pdmg_red = float(e_target.def) / (float(e_target.def) + DEF_K_CONSTANT)
	var e_ehp = float(e_target.hp) / (1.0 - pdmg_red) + e_target.max_shield
	
	var p_dps = float(p_atk) / p_mod.atk_interval
	
	var ttk_enemy = e_ehp / p_dps if p_dps > 0 else 99999
	
	print("---")
	var gear_lbl = "Z%d %s" % [player_gear_zone, "Unique" if is_unique else ("Legendary" if custom_rarity_mult == 1.20 else "Common")]
	var e_lbl = "Z%d %s" % [enemy_zone, "Boss" if is_boss else "Regular Enemy"]
	print("%s vs %s:" % [gear_lbl, e_lbl])
	print("Player: %.0f DPS | %.0f EHP (%.0f HP, %.0f Shield, %.0f DEF) [Time To Die: %.1fs]" % [p_dps, p_ehp, p_hp, p_shield, p_def, ttk_player])
	print("Enemy : %.0f DPS | %.0f EHP (%.0f HP, %.0f Shield, %.0f DEF) [Time To Die: %.1fs]" % [e_dps, e_ehp, e_target.hp, e_target.max_shield, e_target.def, ttk_enemy])
	
	if ttk_player > ttk_enemy:
		print("RESULT: Player WINS comfortably (Survives by %.1f seconds)" % (ttk_player - ttk_enemy))
	else:
		print("RESULT: Player LOSES (Dies %.1f seconds before enemy)" % (ttk_enemy - ttk_player))


