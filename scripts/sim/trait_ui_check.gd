extends Node
# ============================================================================
# BOSS SYSTEMS STRIP / TRAIT UI STATE CHECK (v139f) — verifies the read-only
# presentation feed combat_manager.get_trait_ui_state(), the phase/enrage bar
# metadata inputs, the defeat flight-recorder attribution, and the en/tr
# localization rows for the new strip strings.
#   Godot --headless --path <root> res://scenes/trait_ui_check.tscn
# ============================================================================

var fails := 0
var _notes: Array = []

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond: fails += 1
	print("[TRAITUI] %-42s %s %s" % [name, "OK" if cond else "*** FAIL", detail])

func _find_enemy_with(key: String) -> String:
	var cm = GameState.combat_manager
	for eid in cm.enemy_db:
		var e: Dictionary = cm.enemy_db[eid]
		if key == "phases":
			if (e.get("phases", []) as Array).size() > 1:
				return eid
		elif key == "sustain_pulse":
			if String((e.get("sustain", {}) as Dictionary).get("kind", "")) == "pulse":
				return eid
		elif not (e.get(key, {}) if typeof(e.get(key)) == TYPE_DICTIONARY else {}).is_empty():
			return eid
	return ""

func _spawn(eid: String) -> void:
	var cm = GameState.combat_manager
	var e: Dictionary = cm.enemy_db[eid]
	cm.current_zone = {"name": "probe", "difficulty": int(e.get("zone", 1)), "enemies": [eid]}
	cm.current_zone_id = "sector_alpha"
	cm.target_enemy_id = eid
	cm.spawn_enemy()
	cm.in_combat = true

func _on_notify(text, _color) -> void:
	_notes.append(String(text))

func _ready() -> void:
	var cm = GameState.combat_manager
	GameState.set_process(false)
	GameState.hard_reset()
	UITheme.notification_requested.connect(_on_notify)
	print("[TRAITUI] ============ boss-systems trait UI check ============")

	# ── 1. No fight -> empty state ──
	cm.in_combat = false
	cm.current_enemy = null
	_ok("idle state empty", cm.get_trait_ui_state().is_empty())

	# ── 2. Reactive Armor: plating mult grows via landed hits ──
	var eid_ra := _find_enemy_with("reactive_armor")
	_ok("found reactive_armor enemy", eid_ra != "", eid_ra)
	if eid_ra != "":
		_spawn(eid_ra)
		var st: Dictionary = cm.get_trait_ui_state()
		_ok("plating key present", st.has("plating"))
		_ok("plating starts x1.0", absf(float(st.get("plating", {}).get("mult", 0.0)) - 1.0) < 0.001)
		var per: int = int(cm.current_enemy.get("reactive_armor", {}).get("per_hits", 25))
		for i in range(per):
			cm._trait_note_player_hit("kinetic")
		st = cm.get_trait_ui_state()
		_ok("plating grew after hits", float(st.get("plating", {}).get("mult", 0.0)) > 1.3, "mult=%.2f" % float(st.get("plating", {}).get("mult", 0.0)))

	# ── 3. Charge Nuke: cannon count feed ──
	var eid_cn := _find_enemy_with("charge_nuke")
	_ok("found charge_nuke enemy", eid_cn != "", eid_cn)
	if eid_cn != "":
		_spawn(eid_cn)
		var st2: Dictionary = cm.get_trait_ui_state()
		_ok("cannon key present", st2.has("cannon"))
		_ok("cannon count resets on spawn", int(st2.get("cannon", {}).get("count", -1)) == 0)
		_ok("cannon n sane", int(st2.get("cannon", {}).get("n", 0)) >= 2)

	# ── 4. Multi-phase boss: phase idx follows HP; enrage arms + fires ──
	var eid_ph := _find_enemy_with("phases")
	_ok("found phased boss", eid_ph != "", eid_ph)
	if eid_ph != "":
		_spawn(eid_ph)
		var st3: Dictionary = cm.get_trait_ui_state()
		_ok("phase key present", st3.has("phase"))
		_ok("opens in phase 1", int(st3.get("phase", {}).get("idx", -1)) == 0)
		var plist: Array = st3.get("phase", {}).get("list", [])
		cm.enemy_hp = int(cm.enemy_max_hp * (1.0 / float(plist.size()) * 0.5))  # deep into last band
		st3 = cm.get_trait_ui_state()
		_ok("phase advances with HP", int(st3.get("phase", {}).get("idx", -1)) == plist.size() - 1, "elem=%s" % String(st3.get("phase", {}).get("element", "")))
		if st3.has("enrage"):
			_ok("enrage armed pre-threshold", true)
			cm.enemy_hp = int(cm.enemy_max_hp * (float(cm.current_enemy.get("enrage_at", 0.4)) - 0.05))
			cm._check_enrage()
			st3 = cm.get_trait_ui_state()
			_ok("enrage active post-threshold", bool(st3.get("enrage", {}).get("active", false)))

	# ── 5. Volatile: critical flag below 25% ──
	var eid_v := _find_enemy_with("volatile")
	_ok("found volatile enemy", eid_v != "", eid_v)
	if eid_v != "":
		_spawn(eid_v)
		var st4: Dictionary = cm.get_trait_ui_state()
		_ok("volatile calm above 25%", not bool(st4.get("volatile", {}).get("critical", true)))
		cm.enemy_hp = int(cm.enemy_max_hp * 0.20)
		st4 = cm.get_trait_ui_state()
		_ok("volatile critical below 25%", bool(st4.get("volatile", {}).get("critical", false)))

	# ── 6. Corrosive field + sustain pulse keys ──
	var eid_cf := _find_enemy_with("corrosive_field")
	if eid_cf != "":
		_spawn(eid_cf)
		_ok("corrosion key present", cm.get_trait_ui_state().has("corrosion"))
	var eid_sp := _find_enemy_with("sustain_pulse")
	if eid_sp != "":
		_spawn(eid_sp)
		var st5: Dictionary = cm.get_trait_ui_state()
		_ok("sustain pulse key present", String(st5.get("sustain", {}).get("kind", "")) == "pulse")
		_ok("pulse countdown sane", float(st5.get("sustain", {}).get("next_s", -1.0)) > 0.0)

	# ── 7. Defeat flight-recorder attribution ──
	var eid_any := _find_enemy_with("charge_nuke")
	if eid_any != "":
		_spawn(eid_any)
		_notes.clear()
		cm._pending_death_cause = "nuke"
		cm.lose_fight()
		var got_nuke := false
		for n in _notes:
			if "MAIN CANNON" in n: got_nuke = true
		_ok("nuke death attributed", got_nuke)
		_ok("cause resets after loss", cm._pending_death_cause == "attack")
		_spawn(eid_any)
		_notes.clear()
		cm._pending_death_cause = "corrosion"
		cm.lose_fight()
		var got_cor := false
		for n in _notes:
			if "CORROSION" in n: got_cor = true
		_ok("corrosion death attributed", got_cor)
		_spawn(eid_any)
		_notes.clear()
		cm._pending_death_cause = "attack"
		cm.lose_fight()
		var got_none := true
		for n in _notes:
			if "KILLED" in n: got_none = false
		_ok("plain death stays silent", got_none)

	# ── 7b. v139f drama layer: events carry machine-readable trait tags ──
	if eid_ph != "":
		_spawn(eid_ph)
		cm.combat_events.clear()
		cm.enemy_hp = int(cm.enemy_max_hp * 0.10)
		cm._check_phase_transition()
		var ev_ph: Dictionary = cm.combat_events.back() if cm.combat_events.size() > 0 else {}
		_ok("phase event tagged", String(ev_ph.get("trait", "")) == "phase", str(ev_ph.get("text", "none")))
		cm.combat_events.clear()
		cm._check_enrage()
		var ev_en: Dictionary = cm.combat_events.back() if cm.combat_events.size() > 0 else {}
		_ok("enrage event tagged", String(ev_en.get("trait", "")) == "enrage")

	# ── 7c. v139f explainer vocabulary: UITheme.trait_info_for ──
	if eid_ph != "":
		var inf_ph: Dictionary = UITheme.trait_info_for(cm.enemy_db[eid_ph])
		_ok("info: phased boss has phase+enrage", inf_ph.has("phase") and inf_ph.has("enrage"), str(inf_ph.keys()))
		_ok("info: phase body formatted", "→" in String(inf_ph.get("phase", {}).get("body", "")))
	if eid_cn != "":
		var inf_cn: Dictionary = UITheme.trait_info_for(cm.enemy_db[eid_cn])
		_ok("info: nuke boss has cannon", inf_cn.has("cannon"))
		_ok("info: cannon numbers baked in", "×" in String(inf_cn.get("cannon", {}).get("body", "")))
	if eid_v != "":
		var inf_v: Dictionary = UITheme.trait_info_for(cm.enemy_db[eid_v])
		_ok("info: leviathan grid+volatile", inf_v.has("grid") and inf_v.has("volatile"))
	_ok("info: traitless def empty", UITheme.trait_info_for({}).is_empty())

	# ── 7d. v139g design guard: every Z3-Z8 boss has a DISTINCT headline trait
	# (owner: "each boss is new flavor"). Z1/Z2 softs are the teach half of the
	# Z8/Z7 tests; Z9/Z10 combos compose taught systems and are exempt.
	var headline := {}
	for eid in cm.enemy_db:
		var e: Dictionary = cm.enemy_db[eid]
		if not e.get("is_boss", false):
			continue
		var z: int = int(e.get("zone", 0))
		if z < 3 or z > 8:
			continue
		var tag := ""
		if float(e.get("enrage_at", 0.0)) > 0.0: tag = "enrage"
		var sk := String((e.get("sustain", {}) as Dictionary).get("kind", ""))
		if sk != "": tag = sk
		if not (e.get("reactive_armor", {}) as Dictionary).is_empty(): tag = "reactive"
		if not (e.get("adaptive_grid", {}) as Dictionary).is_empty(): tag = "adaptive"
		if not (e.get("charge_nuke", {}) as Dictionary).is_empty(): tag = "nuke"
		if not (e.get("volatile", {}) as Dictionary).is_empty(): tag = "volatile"
		if not (e.get("corrosive_field", {}) as Dictionary).is_empty(): tag = "corrosive"
		if tag == "":
			continue
		if headline.has(tag):
			_ok("Z3-Z8 headline traits distinct", false, "%s repeats %s (also on %s)" % [eid, tag, headline[tag]])
		headline[tag] = eid
	_ok("Z3-Z8 headline count sane", headline.size() >= 6, str(headline))

	# ── 8. Localization rows live in both locales ──
	TranslationServer.set_locale("tr")
	_ok("tr row VOLATILE CORE", tr("VOLATILE CORE") == "KARARSIZ ÇEKİRDEK", tr("VOLATILE CORE"))
	_ok("tr row Boss Systems", tr("Boss Systems") == "Patron Sistemleri")
	_ok("tr row CORROSION", tr("CORROSION") == "KOROZYON")
	_ok("tr row CANNON CYCLE", tr("CANNON CYCLE") == "TOP DÖNGÜSÜ")
	_ok("tr row KILLED short", tr("KILLED DURING ENRAGE") == "ÖFKE SIRASINDA YOK EDİLDİN")
	TranslationServer.set_locale("en")
	_ok("en fallback identity", tr("VOLATILE CORE") == "VOLATILE CORE")

	print("[TRAITUI] ============ %s ============" % ("ALL PASS" if fails == 0 else "%d FAIL(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
