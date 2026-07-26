extends Node
# Exercises _migrate_uniform_atk_interval on synthetic pre-v149 saved drops.
func _ready() -> void:
	var sm = GameState.shipyard_manager
	# A pre-v149 missile roll: base was 4.0, roll landed 3.60s, atk 113 (87 x1.30).
	sm.custom_modules["custom_old_missile"] = {
		"base_module": "z3_missile", "rarity": 2,
		"stats": {"atk_explosive": 113.0, "energy_load": 30, "atk_interval": 3.60},
	}
	sm.modules["custom_old_missile"] = sm.custom_modules["custom_old_missile"]
	# A max-roll pre-v149 missile at the old floor 2.40s.
	sm.custom_modules["custom_old_missile2"] = {
		"base_module": "z3_missile", "rarity": 4,
		"stats": {"atk_explosive": 150.0, "energy_load": 30, "atk_interval": 2.40},
	}
	sm.modules["custom_old_missile2"] = sm.custom_modules["custom_old_missile2"]
	# A kinetic roll off the unchanged 2.0 base — MUST be left alone.
	sm.custom_modules["custom_kin"] = {
		"base_module": "z3_kinetic", "rarity": 3,
		"stats": {"atk_kinetic": 60.0, "energy_load": 18, "atk_interval": 1.55},
	}
	sm.modules["custom_kin"] = sm.custom_modules["custom_kin"]
	for k in ["custom_old_missile", "custom_old_missile2", "custom_kin"]:
		var st: Dictionary = sm.custom_modules[k]["stats"]
		var a: float = float(st.get("atk_explosive", st.get("atk_kinetic", 0)))
		print("[MIG] BEFORE %s atk=%s iv=%s dps=%s" % [k, str(a), str(st["atk_interval"]), str(a / float(st["atk_interval"]))])
	sm._migrate_uniform_atk_interval()
	sm._migrate_atk_interval_caps()
	for k in ["custom_old_missile", "custom_old_missile2", "custom_kin"]:
		var st2: Dictionary = sm.custom_modules[k]["stats"]
		var a2: float = float(st2.get("atk_explosive", st2.get("atk_kinetic", 0)))
		print("[MIG] AFTER  %s atk=%s iv=%s dps=%s" % [k, str(a2), str(st2["atk_interval"]), str(a2 / float(st2["atk_interval"]))])
	get_tree().quit()
