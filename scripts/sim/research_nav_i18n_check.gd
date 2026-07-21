extends Node
# ============================================================================
# RESEARCH NAV + TAB-NAME i18n CHECK (v139h) — owner-reported: with TWO active
# research missions on different tabs, entering Research landed on the WRONG tab
# (the firmware GOAL's Combat tab instead of the Industry tab of the metallurgy
# CHAPTER beat the player was following); and "Industry"/"Sectors" tab NAMES
# weren't translated. Asserts:
#   - all 7 research tab names resolve to Turkish under the tr locale (Fix 2)
#   - on_page_enter focuses the mission the objective ARROW guides — the earliest
#     beat in DEFINITION order (chapter before side goals) — even when the goal
#     activated first (append order). So metallurgy (Industry) wins over firmware
#     (Combat); a lone goal still guides its own tab (Fix 1)
#   Godot --headless --path <root> res://scenes/research_nav_i18n_check.tscn
# ============================================================================

var fails := 0
func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond: fails += 1
	print("[NAVLOC] %-46s %s %s" % [name, "OK" if cond else "*** FAIL", detail])

func _activate(mm, mid: String) -> void:
	if mid in mm.missions:
		mm.missions[mid]["active"] = true
		if not mid in mm.active_missions:
			mm.active_missions.append(mid)

# Mirror on_page_enter's selection: first ACTIVE research beat in DEFINITION order.
func _first_active_research_tech(mm) -> String:
	for mid in mm.missions:
		if not mid in mm.active_missions:
			continue
		var m = mm.missions[mid]
		if m.get("completed", false) or m["type"] != "research":
			continue
		return str(m["target"])
	return ""

# Which tab a tech lives on, per the real graphs data.
func _tab_of(rp, tech_id: String) -> String:
	for tab_name in rp.graphs:
		if tech_id in rp.graphs[tab_name]["nodes"]:
			return tab_name
	return ""

func _ready() -> void:
	print("[NAVLOC] ===== research nav + tab-name i18n check =====")
	var mm = GameState.mission_manager
	GameState.set_process(false)
	GameState.hard_reset()

	# Fix 2: every research tab name must translate under the Turkish locale.
	Localization.set_locale("tr")
	var pairs := [["Gathering", "Toplama"], ["Industry", "Sanayi"], ["Automation", "Otomasyon"],
		["Ships", "Gemiler"], ["Combat", "Savaş"], ["Warp Tech", "Warp Teknolojisi"],
		["Sectors", "Sektörler"]]
	for pair in pairs:
		var got: String = tr(pair[0])
		_ok("tr(%s)" % pair[0], got == pair[1], "-> '%s'" % got)

	var rp = load("res://scripts/ui/research_page.gd").new()
	_ok("firmware_hacking on Combat", _tab_of(rp, "firmware_hacking") == "Combat")
	_ok("metallurgy_advanced on Industry", _tab_of(rp, "metallurgy_advanced") == "Industry")

	# Fix 1a: activate the firmware GOAL first (append order), then the metallurgy
	# CHAPTER beat. on_page_enter must still pick metallurgy (definition order = arrow),
	# landing on Industry/Sanayi — NOT the firmware goal's Combat tab.
	_activate(mm, "goal_hack_1")     # firmware_hacking  -> Combat  (appended FIRST)
	_activate(mm, "m029a2")          # metallurgy_advanced -> Industry
	var picked := _first_active_research_tech(mm)
	_ok("chapter beat wins vs goal (append-order proof)", picked == "metallurgy_advanced",
		"picked '%s'" % picked)
	_ok("=> lands on Industry (Sanayi)", _tab_of(rp, picked) == "Industry")

	# Fix 1b: a lone goal research mission still guides its own tab.
	mm.missions["m029a2"]["active"] = false
	mm.active_missions.erase("m029a2")
	var solo := _first_active_research_tech(mm)
	_ok("lone goal guides its tab (firmware->Combat)", _tab_of(rp, solo) == "Combat",
		"picked '%s'" % solo)
	rp.free()

	print("[NAVLOC] %s" % ("ALL PASS" if fails == 0 else "*** %d FAILURE(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
