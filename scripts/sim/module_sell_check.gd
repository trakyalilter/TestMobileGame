extends Node
# ============================================================================
# MODULE SELL ZONE-SCALING CHECK (v137 #32) — verifies dropped-module sell price
# scales by the module's zone (N/10 of top-tier value) so farming a one-shot low
# boss stops paying frontier-equivalent Liras, while crafted (25% cost) and
# stone-crafted (0) paths stay untouched. Rarity ints: 1=Uncommon .. 4=Unique.
#   Godot --headless --path <root> res://scenes/module_sell_check.tscn
# ============================================================================

func _ready() -> void:
	var sm = GameState.shipyard_manager
	GameState.set_process(false)
	# Dropped (no "cost" key → rarity×zone path):
	sm.modules["__t_unc_z1"]  = {"rarity": 1, "zone": 1}
	sm.modules["__t_unc_z5"]  = {"rarity": 1, "zone": 5}
	sm.modules["__t_unc_z10"] = {"rarity": 1, "zone": 10}
	sm.modules["__t_uniq_z1"] = {"rarity": 4, "zone": 1}
	sm.modules["__t_uniq_z10"]= {"rarity": 4, "zone": 10}
	# Crafted (has cost → 25% path, zone-independent) + stone-crafted (→0):
	sm.modules["__t_crafted"] = {"rarity": 2, "zone": 1, "cost": {"credits": 8000}}
	sm.modules["__t_stone"]   = {"rarity": 3, "zone": 1, "stone_crafted": true}
	print("[MSELL] ============ module sell zone-scaling (#32) ============")
	print("[MSELL] Uncommon (base 750):  Z1=%-5d (exp 75)  Z5=%-5d (exp 375)  Z10=%-5d (exp 750)" % [
		sm.get_sell_price("__t_unc_z1"), sm.get_sell_price("__t_unc_z5"), sm.get_sell_price("__t_unc_z10")])
	print("[MSELL] Unique (base 100000): Z1=%-6d (exp 10000)  Z10=%-6d (exp 100000)" % [
		sm.get_sell_price("__t_uniq_z1"), sm.get_sell_price("__t_uniq_z10")])
	print("[MSELL] crafted 25%% of 8000 (zone-indep): %d (exp 2000)" % sm.get_sell_price("__t_crafted"))
	print("[MSELL] stone_crafted: %d (exp 0)" % sm.get_sell_price("__t_stone"))
	var z1: int = sm.get_sell_price("__t_uniq_z1")
	var z10: int = sm.get_sell_price("__t_uniq_z10")
	print("[MSELL] %s — farming a Z1 boss now pays %.0f%% of the Z10 equivalent" % [
		("PASS" if z1 * 10 == z10 else "*** FAIL"), 100.0 * float(z1) / float(z10)])
	get_tree().quit(0)
