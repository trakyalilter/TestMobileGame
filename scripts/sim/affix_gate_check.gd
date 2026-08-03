extends Node
# ============================================================================
# AFFIX RESEARCH GATE (v141) — an affix must not ROLL while the system it scales
# does not exist for the player.
#
# Case: "Cryptographic Decoder" (+X% Hack Card drop chance) rolled on sensors from
# the very first drop, but combat_manager._roll_hack_stone_drops returns EMPTY
# unless `firmware_hacking` is researched — so the affix multiplied zero. A dead
# stat that still consumed one of the module's affix slots, i.e. a silently worse
# item. Now AFFIX_DB entries may declare "research_req" and are pooled out until
# the tech lands.
#
# Also pins the de-duplication: generate_module_drop used to carry a byte-identical
# inline copy of the pool filter, so a rule added to _legal_affix_pool missed real
# drops. Both paths must agree.
#   Godot --headless --path <root> res://scenes/affix_gate_check.tscn
# ============================================================================

const GATED := "stone_drop_mult"
const GATE_TECH := "firmware_hacking"

var fails := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond: fails += 1
	print("[AFFIXGATE] %-48s %s %s" % [name, "OK" if cond else "*** FAIL", detail])


# Roll a lot of sensors and report whether the gated affix ever appears.
func _gated_appears_in_drops(sm, n: int) -> bool:
	for i in range(n):
		var cid := String(sm.generate_module_drop("z1_sensor", 2, 3))
		if cid == "":
			continue
		var d: Dictionary = sm.modules.get(cid, {})
		if (d.get("affixes", {}) as Dictionary).has(GATED):
			return true
	return false


func _ready() -> void:
	GameState.set_process(false)
	GameState.hard_reset()
	var sm = GameState.shipyard_manager
	var rm = GameState.research_manager
	seed(20260723)

	print("[AFFIXGATE] ============ affix research gate ============")

	_ok("affix declares a research gate",
		String(sm.AFFIX_DB[GATED].get("research_req", "")) == GATE_TECH,
		String(sm.AFFIX_DB[GATED].get("research_req", "")))

	# ── 1. Locked: the affix must be out of the pool AND out of real drops ──
	rm.unlocked_techs.erase(GATE_TECH)
	_ok("gate tech locked", not rm.is_tech_unlocked(GATE_TECH))
	var pool_locked: Array = sm._legal_affix_pool("sensor")
	_ok("pool EXCLUDES gated affix while locked", not (GATED in pool_locked),
		"pool=%d" % pool_locked.size())
	_ok("sensor pool still has other affixes", pool_locked.size() > 0, str(pool_locked))
	_ok("no gated affix across 300 sensor drops", not _gated_appears_in_drops(sm, 300))

	# ── 2. Researched: it must come back (the gate delays, never deletes) ──
	if not rm.is_tech_unlocked(GATE_TECH):
		rm.unlocked_techs.append(GATE_TECH)
	_ok("gate tech unlocked", rm.is_tech_unlocked(GATE_TECH))
	var pool_open: Array = sm._legal_affix_pool("sensor")
	_ok("pool INCLUDES gated affix once researched", GATED in pool_open,
		"pool=%d" % pool_open.size())
	_ok("gated affix DOES roll after research", _gated_appears_in_drops(sm, 300))

	# ── 3. Ungated affixes are untouched by the gate ──
	rm.unlocked_techs.erase(GATE_TECH)
	var p2: Array = sm._legal_affix_pool("sensor")
	_ok("ungated sensor affix still pools", "enemy_drop_mult" in p2, str(p2))
	_ok("locked pool is exactly one smaller", pool_open.size() - p2.size() == 1,
		"%d vs %d" % [pool_open.size(), p2.size()])

	# ── 4. Non-destructive: gear that ALREADY has the affix keeps it ──
	rm.unlocked_techs.append(GATE_TECH)
	var owned := ""
	for i in range(300):
		var cid := String(sm.generate_module_drop("z1_sensor", 2, 3))
		if cid != "" and (sm.modules.get(cid, {}).get("affixes", {}) as Dictionary).has(GATED):
			owned = cid
			break
	if owned != "":
		rm.unlocked_techs.erase(GATE_TECH)   # simulate a warp wiping the research
		_ok("existing gear keeps the affix after research reset",
			(sm.modules[owned].get("affixes", {}) as Dictionary).has(GATED))

	print("[AFFIXGATE] ============ %s ============" % ("ALL PASS" if fails == 0 else "%d FAIL(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
