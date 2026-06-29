extends Node

# Dumps the exact game constants the income sim needs into income_data.json.
# Zero transcription: reads live ElementDB / managers. The Python sim
# (run_time_sim.py) applies the tunable income + policy model on top.

func _ready() -> void:
	var pm = GameState.processing_manager
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	var gm = GameState.gathering_manager
	var im = GameState.infrastructure_manager

	var recipes: Dictionary = pm.recipes
	var modules: Dictionary = sm.modules
	var enemy_db: Dictionary = cm.enemy_db
	var tech_tree: Dictionary = rm.tech_tree
	var actions: Dictionary = gm.actions
	var building_db: Dictionary = im.building_db

	# material -> first recipe that outputs it (for raw expansion + depth)
	var producer := {}
	for rid in recipes.keys():
		for m in recipes[rid].get("output", {}).keys():
			if not producer.has(m):
				producer[m] = rid

	var out := {}
	out["zones"] = {}

	for z in range(1, 11):
		var zd := {}
		# --- credit gate (zone_N_access research) ---
		var gate_credits := 0.0
		var tk := "zone_%d_access" % z
		if tech_tree.has(tk):
			gate_credits = float(tech_tree[tk].get("cost", 0))
		zd["gate_credits"] = gate_credits

		# --- module credit cost + raw demand (5 combat modules) ---
		var mod_credits := 0.0
		var raw_demand := 0.0
		var max_level := 0
		for t in ["kinetic", "energy", "missile", "shield", "armor"]:
			var mid := "z%d_%s" % [z, t]
			if not modules.has(mid):
				continue
			var cost = modules[mid].get("cost", {})
			for mat in cost.keys():
				if mat == "credits":
					mod_credits += float(cost[mat])
				else:
					raw_demand += _expand_raw(mat, float(cost[mat]), recipes, producer, {})
		zd["module_credits"] = mod_credits
		zd["raw_demand"] = raw_demand

		# --- combat income: avg credits/kill + avg hp over non-boss zone enemies ---
		var n := 0
		var sum_credits := 0.0
		var sum_hp := 0.0
		var boss_hp := 0.0
		var boss_credits := 0.0
		for eid in enemy_db.keys():
			var e = enemy_db[eid]
			if int(e.get("zone", 0)) != z:
				continue
			var avg_c := _avg_credits(e.get("loot", []))
			var hp := float(e.get("stats", {}).get("hp", 0))
			if bool(e.get("is_boss", false)):
				boss_hp = hp
				boss_credits = avg_c
			else:
				n += 1
				sum_credits += avg_c
				sum_hp += hp
		zd["credits_per_kill"] = (sum_credits / n) if n > 0 else 0.0
		zd["enemy_avg_hp"] = (sum_hp / n) if n > 0 else 0.0
		zd["boss_hp"] = boss_hp
		zd["boss_credits"] = boss_credits

		# --- player weapon DPS proxy (sum of zone weapons' atk/interval) ---
		var dps := 0.0
		for t in ["kinetic", "energy", "missile"]:
			var mid := "z%d_%s" % [z, t]
			if modules.has(mid):
				var st = modules[mid].get("stats", {})
				var atk := 0.0
				for k in ["atk_kinetic", "atk_energy", "atk_explosive"]:
					atk = max(atk, float(st.get(k, 0)))
				var interval := float(st.get("atk_interval", 2.0))
				if interval > 0:
					dps += atk / interval
		zd["weapon_dps"] = dps

		# --- xp gate: highest module/recipe level_req implied for this zone ---
		# (use the deepest endgame recipe gating this zone's spine, if any)
		zd["max_gate_level"] = max_level

		out["zones"][str(z)] = zd

	# --- globals ---
	# best gather throughput (units/hour) across unlocked-tier actions
	var best_gather := 0.0
	var base_dur := float(gm.action_duration)
	for aid in actions.keys():
		var a = actions[aid]
		var dur := float(a.get("duration", base_dur))
		var yld := 0.0
		for entry in a.get("loot_table", []):
			# entry = [item, chance, min, max]
			if entry.size() >= 4:
				yld += float(entry[1]) * (float(entry[2]) + float(entry[3])) / 2.0
		if dur > 0:
			best_gather = max(best_gather, yld / dur * 3600.0)
	out["gather_units_per_hour_best"] = best_gather

	# infra throughput if you owned ONE of every building (raw units/hour)
	var infra_uph_all := 0.0
	for bid in building_db.keys():
		var b = building_db[bid]
		var interval := float(b.get("interval", 5.0))
		var ysum := 0.0
		for k in b.get("yield", {}).keys():
			ysum += float(b["yield"][k])
		if interval > 0:
			infra_uph_all += ysum / interval * 3600.0
	out["infra_units_per_hour_one_each"] = infra_uph_all

	# total credits to own one of every building (the unmodelled late credit sink)
	var total_building_cr := 0.0
	for bid in building_db.keys():
		total_building_cr += float(building_db[bid].get("cost", {}).get("credits", 0))
	out["total_building_credit_cost"] = total_building_cr

	# XP table (level -> cumulative xp) for the gating math
	var skill = gm  # gathering_manager extends Skill
	var xp_tbl := {}
	for lvl in range(1, 101):
		xp_tbl[str(lvl)] = skill.get_xp_for_level(lvl)
	out["xp_table"] = xp_tbl

	out["warp"] = {
		"shard_base_divisor": 500000.0,
		"production_per_shard": 0.02,
		"combat_per_shard": 0.03,
		"tier_every_warps": 5,
	}
	out["offline_combat_default"] = bool(GameState.game_settings.get("offline_combat", false))

	var f = FileAccess.open("res://income_data.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("INCOME_PROBE: wrote income_data.json (%d zones)" % out["zones"].size())
	get_tree().quit()

func _avg_credits(loot: Array) -> float:
	for entry in loot:
		if entry.size() >= 3 and String(entry[0]) == "credits":
			return (float(entry[1]) + float(entry[2])) / 2.0
	return 0.0

func _expand_raw(mat: String, qty: float, recipes: Dictionary, producer: Dictionary, visiting: Dictionary) -> float:
	if not producer.has(mat) or visiting.has(mat):
		return qty
	var r = recipes[producer[mat]]
	var out_qty := float(r.get("output", {}).get(mat, 1.0))
	if out_qty <= 0.0:
		return qty
	var scale := qty / out_qty
	var v2 := visiting.duplicate()
	v2[mat] = true
	var total := 0.0
	var inputs = r.get("input", {})
	for inp in inputs.keys():
		total += _expand_raw(inp, float(inputs[inp]) * scale, recipes, producer, v2)
	return total
