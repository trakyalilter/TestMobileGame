extends Node
# ============================================================================
# PRESET-AFTER-DEFEAT CHECK (v139c) — owner-reported "build 1 & 2 emptied after
# a defeat". Two build slots share the same physical (base) modules; a combat
# loss converts the equipped base ids to custom instances (durability). Before
# the fix, the NON-active preset still stored base ids and loaded EMPTY on
# switch. Asserts both builds survive the id churn.
#   Godot --headless --path <root> res://scenes/preset_defeat_check.tscn
# ============================================================================

var fails := 0
func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond: fails += 1
	print("[PRESET] %-38s %s %s" % [name, "OK" if cond else "*** FAIL", detail])

func _equip_build(sm) -> void:
	# Corvette slots: [wpn,wpn,shield,armor,engine,bat,bat,sensor]
	sm.equip_module(5, "z1_battery", true)
	sm.equip_module(6, "z1_battery", true)
	sm.equip_module(0, "z1_kinetic", true)
	sm.equip_module(1, "z1_kinetic", true)

func _weapons_equipped(sm) -> int:
	var n := 0
	for s in [0, 1]:
		var m = sm.loadout.get(s)
		if m != null and String(m) != "" and String(sm.modules.get(m, {}).get("slot_type", "")) == "weapon":
			n += 1
	return n

func _ready() -> void:
	var sm = GameState.shipyard_manager
	GameState.set_process(false)
	GameState.hard_reset()
	sm.active_hull = "corvette_hull"
	sm.loadout.clear()
	sm.module_inventory.clear()
	print("[PRESET] ============ preset-after-defeat check ============")

	# Own 2 base batteries + 2 base weapons (shared across both builds).
	sm.module_inventory["z1_battery"] = 2
	sm.module_inventory["z1_kinetic"] = 2

	# Build 1: equip + save.
	sm.active_preset_idx = 1
	_equip_build(sm)
	sm.save_loadout_preset(1)
	_ok("Build 1 armed (2 weapons)", _weapons_equipped(sm) == 2)

	# Build 2: switch (returns Build 1's modules to inventory), equip same, save.
	sm.load_loadout_preset(2)
	_equip_build(sm)
	sm.save_loadout_preset(2)
	_ok("Build 2 armed (2 weapons)", _weapons_equipped(sm) == 2)

	# Back on Build 1, then LOSE a fight — base ids convert to custom instances.
	sm.load_loadout_preset(1)
	sm.handle_module_defeat()
	var b1_custom := true
	for s in [0, 1]:
		if not String(sm.loadout.get(s, "")).begins_with("custom_"):
			b1_custom = false
	_ok("defeat converted Build 1 base→custom", b1_custom)

	# THE BUG: switch to Build 2 — it stored BASE ids that no longer exist.
	var r2: Dictionary = sm.load_loadout_preset(2)
	_ok("Build 2 survives defeat (not emptied)", _weapons_equipped(sm) == 2 and int(r2.get("skipped", 99)) == 0,
		"weapons=%d skipped=%d" % [_weapons_equipped(sm), int(r2.get("skipped", -1))])

	# And back to Build 1 stays armed too.
	var r1: Dictionary = sm.load_loadout_preset(1)
	_ok("Build 1 still armed after round-trip", _weapons_equipped(sm) == 2 and int(r1.get("skipped", 99)) == 0,
		"weapons=%d skipped=%d" % [_weapons_equipped(sm), int(r1.get("skipped", -1))])

	# Resolver unit: a base id resolves to an owned custom of the same base type.
	sm.module_inventory.clear()
	sm.module_inventory["custom_z1_kinetic_1"] = 1
	sm.modules["custom_z1_kinetic_1"] = {"base_module": "z1_kinetic", "slot_type": "weapon", "rarity": 0}
	_ok("resolver base→owned custom", sm._resolve_owned_equivalent("z1_kinetic") == "custom_z1_kinetic_1")
	_ok("resolver base-id parse", sm._module_base_id("custom_z1_kinetic_1") == "z1_kinetic")

	# ── v139e: COMBAT-LOCK. A designer-side build switch must NOT strip the fighting
	# ship out from under an active battle (owner-reported "swap from designer in combat
	# -> false NO AMMO"; "separate these"). Rebuild two shared-module builds, land on
	# Build 1 as the live ship, then assert the guard.
	sm.module_inventory.clear()
	sm.loadout.clear()
	sm.module_inventory["z1_battery"] = 2
	sm.module_inventory["z1_kinetic"] = 2
	sm.active_preset_idx = 1
	_equip_build(sm)
	sm.save_loadout_preset(1)
	sm.load_loadout_preset(2)
	_equip_build(sm)
	sm.save_loadout_preset(2)
	sm.load_loadout_preset(1)   # fighting ship = Build 1
	_ok("armed on Build 1 pre-combat", _weapons_equipped(sm) == 2 and int(sm.active_preset_idx) == 1)

	# Enter combat: a plain (designer-side) switch to Build 2 must be REFUSED and leave
	# the live ship on Build 1 — not stripped, not half-applied.
	GameState.combat_manager.in_combat = true
	var blocked: Dictionary = sm.load_loadout_preset(2)
	_ok("designer switch BLOCKED in combat", bool(blocked.get("blocked", false)) and int(blocked.get("loaded", -1)) == 0)
	_ok("live ship untouched by block", _weapons_equipped(sm) == 2 and int(sm.active_preset_idx) == 1,
		"weapons=%d active=%d" % [_weapons_equipped(sm), int(sm.active_preset_idx)])

	# The sanctioned combat-chip path (from_combat_swap=true) STILL applies mid-fight.
	var ok_swap: Dictionary = sm.load_loadout_preset(2, true)
	_ok("combat-chip swap ALLOWED in combat", _weapons_equipped(sm) == 2 and int(ok_swap.get("skipped", 99)) == 0 and int(sm.active_preset_idx) == 2,
		"weapons=%d skipped=%d active=%d" % [_weapons_equipped(sm), int(ok_swap.get("skipped", -1)), int(sm.active_preset_idx)])

	# Out of combat, the designer switch works normally again.
	GameState.combat_manager.in_combat = false
	var ok_free: Dictionary = sm.load_loadout_preset(1)
	_ok("designer switch OK out of combat", _weapons_equipped(sm) == 2 and int(ok_free.get("skipped", 99)) == 0 and int(sm.active_preset_idx) == 1,
		"weapons=%d skipped=%d active=%d" % [_weapons_equipped(sm), int(ok_free.get("skipped", -1)), int(sm.active_preset_idx)])

	print("[PRESET] %s" % ("ALL PASS" if fails == 0 else "*** %d FAILURE(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
