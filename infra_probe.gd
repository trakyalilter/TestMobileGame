extends Node

# Dumps exact infrastructure economics to infra_data.json for the pyramid
# investigation: per-building cost (credits + materials), production (material +
# base rate/hr at count=1), inputs, energy, gate, throttle/eng flags — plus the
# diminishing-returns curve that caps effective output per building type.

func _ready() -> void:
	var im = GameState.infrastructure_manager
	var bdb: Dictionary = im.building_db

	var out := {}

	# DR curve: effective units for owning N of a single building type
	var dr := {}
	for n in [1, 5, 10, 15, 20, 30, 50, 100, 200]:
		dr[str(n)] = im._dr_units(n)
	out["dr_curve"] = dr
	out["constants"] = {
		"DR_KNEE": im.INFRA_DR_KNEE,
		"DR_TAIL": im.INFRA_DR_TAIL,
		"DR_CEILING": im.INFRA_DR_KNEE + im.INFRA_DR_TAIL,
		"ENG_SCALE_CAP": im.INFRA_ENG_SCALE_CAP,
		"ORE_THROTTLE_MULT": im.INFRA_ORE_EXTRACTION_MULT,
	}

	var blist := []
	for bid in bdb.keys():
		var d = bdb[bid]
		var rec := {}
		rec["id"] = bid
		rec["name"] = d.get("name", bid)
		rec["category"] = d.get("category", "")
		rec["research_req"] = d.get("research_req", "")
		rec["interval"] = float(d.get("interval", 1.0))
		rec["energy_gen"] = float(d.get("energy_gen", 0.0))
		rec["energy_cons"] = float(d.get("energy_cons", 0.0))
		rec["ore_throttled"] = bid in im.INFRA_ORE_EXTRACTORS
		rec["eng_scaled"] = bid in im.INFRA_ENG_SCALED_BUILDINGS

		# cost split: credits + materials
		var cost = d.get("cost", {})
		rec["credits"] = float(cost.get("credits", 0))
		var mats := {}
		for k in cost.keys():
			if k != "credits":
				mats[k] = cost[k]
		rec["material_cost"] = mats

		# yields + inputs
		var yields := {}
		var primary := ""
		var best := -1.0
		for k in d.get("yield", {}).keys():
			yields[k] = d["yield"][k]
			if float(d["yield"][k]) > best:
				best = float(d["yield"][k])
				primary = k
		rec["yields"] = yields
		rec["primary_material"] = primary
		var inputs := {}
		for k in d.get("input", {}).keys():
			inputs[k] = d["input"][k]
		rec["inputs"] = inputs

		# base output/hr for ONE building (eff yield incl ore-throttle/eng at
		# current default state, divided by raw interval)
		var per_hr := 0.0
		if primary != "" and rec["interval"] > 0:
			per_hr = im.get_effective_yield(bid, primary) / rec["interval"] * 3600.0
		rec["primary_per_hour_at_1"] = per_hr
		# effective at the DR ceiling (count>=~200): per_hr * 20
		rec["primary_per_hour_ceiling"] = per_hr * (im.INFRA_DR_KNEE + im.INFRA_DR_TAIL)
		# credits per (primary unit / hour) at count=1 (cost efficiency)
		rec["credits_per_unit_hr"] = (rec["credits"] / per_hr) if per_hr > 0 else -1.0

		blist.append(rec)

	out["buildings"] = blist
	out["building_count"] = blist.size()

	var f = FileAccess.open("res://infra_data.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("INFRA_PROBE: wrote infra_data.json (%d buildings)" % blist.size())
	get_tree().quit()
