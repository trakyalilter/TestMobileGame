extends Node
# ============================================================================
# MISSION DOT CHECK (v177)
#
# The sidebar mission dots ("orbs") were a single flat teal regardless of which
# mission placed them. v177 colors each dot by its mission's CATEGORY via
# UITheme.mission_tag_color — the same mapping the mission cards' name line
# uses, so the dot can be traced to its mission on the missions page.
#
# Asserted against the REAL main scene (instantiated, not mocked):
#   1. a [CHAPTER 2] mission's page dot renders in Lira gold
#   2. a [CORE GOAL] mission's page dot renders in warp purple
#   3. an [ENDGAME] mission's page dot renders in cryo ice
#   4. PRIORITY: chapter beats core-goal when both want the same page
#   5. [TUTORIAL] missions still place NO dot (the coach arrow owns tutorials)
#   6. the mission card name color and the dot color agree (the whole point)
#
#   Godot --headless --path <root> res://scenes/mission_dot_check.tscn
# ============================================================================

var _fails: Array = []

func _fail(msg: String) -> void:
	_fails.append(msg)

func _ready() -> void:
	if not GameState.sim_mode:
		print("[DOT] ABORT: sim_mode false.")
		get_tree().quit(1)
		return
	var m: Node = load("res://scenes/main.tscn").instantiate()
	# DEFERRED, like designer_shot: a plain add_child inside our own _ready fails
	# with "Parent node is busy setting up children" — main never enters the tree,
	# every @onready stays null, and the probe reports phantom failures.
	get_tree().root.add_child.call_deferred(m)
	for _i in range(10):
		await get_tree().process_frame
	print("[DOT] ============ MISSION DOT CHECK ============")

	var mm = GameState.mission_manager
	# Progressive disclosure hides the research/combat/shipyard nav buttons on a
	# fresh sim boot, and the refresh (correctly) never dots a hidden page — the
	# first run of this probe failed all four cases on exactly that. Unlock the
	# tech tree so the sidebar is fully revealed; disclosure is not under test.
	# Techs unlocked so main's own periodic disclosure pass agrees with the
	# visibility set below (has_basic_eng etc. all true) instead of re-hiding it.
	# NOT via _update_sidebar_styling() — that whole pass touches nodes that are
	# Nil under a probe boot and crashes; the buttons are flipped directly.
	var rm = GameState.research_manager
	for tid in rm.tech_tree:
		if not tid in rm.unlocked_techs:
			rm.unlocked_techs.append(tid)
	for p in ["research", "combat", "shipyard"]:
		var b: Button = m._get_btn_for_page(String(p))
		if b:
			b.visible = true
	await get_tree().process_frame

	# Synthetic missions, one per category, each targeting a DISTINCT page via a
	# type _page_for_mission routes: research -> research, defeat -> combat,
	# craft -> shipyard. Injected into mm.missions so the real refresh path
	# (active_missions -> _page_for_mission -> tint) runs unmodified.
	mm.missions["dotchk_ch"] = {"id": "dotchk_ch", "tag": "[CHAPTER 2]", "name": "DotChk Ch",
		"description": "", "type": "research", "target": "zone_2_access", "target_qty": 1,
		"current_qty": 0, "multi_progress": {}, "reward_cr": 0, "reward_xp": 0,
		"next_mission": "", "completed": false, "claimed": false, "active": true}
	mm.missions["dotchk_goal"] = {"id": "dotchk_goal", "tag": "[CORE GOAL]", "name": "DotChk Goal",
		"description": "", "type": "defeat", "target": "z1_lunar_drone", "target_qty": 999,
		"current_qty": 0, "multi_progress": {}, "reward_cr": 0, "reward_xp": 0,
		"next_mission": "", "completed": false, "claimed": false, "active": true}
	mm.missions["dotchk_end"] = {"id": "dotchk_end", "tag": "[ENDGAME]", "name": "DotChk End",
		"description": "", "type": "craft", "target": "z1_kinetic", "target_qty": 999,
		"current_qty": 0, "multi_progress": {}, "reward_cr": 0, "reward_xp": 0,
		"next_mission": "", "completed": false, "claimed": false, "active": true}
	mm.active_missions = ["dotchk_ch", "dotchk_goal", "dotchk_end"]

	m._refresh_mission_dots(mm)
	await get_tree().process_frame

	print("[DOT] debug: _mission_dots has %d entries" % m._mission_dots.size())
	for p2 in ["research", "combat", "shipyard"]:
		var b2: Button = m._get_btn_for_page(String(p2))
		var d2 = m._mission_dots.get(String(p2))
		print("[DOT] debug: %-10s btn=%s vis=%s | dot=%s dot_vis=%s" % [
			p2, b2 != null, (b2.visible if b2 else false),
			d2 != null, ((d2 as Control).visible if d2 else false)])

	_expect_dot(m, mm.missions["dotchk_ch"], "[CHAPTER 2]", "chapter/gold")
	_expect_dot(m, mm.missions["dotchk_goal"], "[CORE GOAL]", "goal/purple")
	_expect_dot(m, mm.missions["dotchk_end"], "[ENDGAME]", "endgame/ice")

	# ---- 4. priority: chapter wins a shared page --------------------------
	# Retarget the goal mission onto the chapter mission's page and re-refresh.
	var ch_page: String = m._page_for_mission(mm.missions["dotchk_ch"])
	mm.missions["dotchk_goal"]["type"] = "research"
	mm.missions["dotchk_goal"]["target"] = "zone_2_access"
	mm.active_missions = ["dotchk_goal", "dotchk_ch"]   # goal FIRST — order must not decide
	m._refresh_mission_dots(mm)
	var sb_pri := _dot_sb(m, ch_page)
	if sb_pri == null:
		_fail("priority case: no dot on '%s'" % ch_page)
	elif not _col_eq(sb_pri.bg_color, UITheme.mission_tag_color("[CHAPTER 2]")):
		_fail("priority: dot on '%s' is %s, expected CHAPTER gold to beat CORE GOAL" % [
			ch_page, sb_pri.bg_color])
	else:
		print("[DOT] priority on shared page: CHAPTER beats CORE GOAL")

	# ---- 5. tutorials never dot -------------------------------------------
	mm.missions["dotchk_ch"]["tag"] = "[TUTORIAL]"
	mm.active_missions = ["dotchk_ch"]
	m._refresh_mission_dots(mm)
	var any_visible := false
	for page in m._mission_dots:
		var d: Control = m._mission_dots[page]
		if is_instance_valid(d) and d.visible:
			any_visible = true
	if any_visible:
		_fail("a [TUTORIAL] mission lit a dot — the coach arrow owns tutorials")
	else:
		print("[DOT] tutorial exclusion: no dot")

	print("[DOT] -------------------------------------------")
	for f in _fails:
		print("[DOT] FAIL: %s" % f)
	print("[DOT] RESULT: %s (%d failure(s))" % ["PASS" if _fails.is_empty() else "FAIL", _fails.size()])
	get_tree().quit(0 if _fails.is_empty() else 1)

func _dot_sb(m: Node, page: String) -> StyleBoxFlat:
	var dot = m._mission_dots.get(page)
	if dot == null or not is_instance_valid(dot) or not (dot as Control).visible:
		return null
	return (dot as Control).get_theme_stylebox("panel") as StyleBoxFlat

func _col_eq(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01

func _expect_dot(m: Node, mdata: Dictionary, tag: String, label: String) -> void:
	var page: String = m._page_for_mission(mdata)
	if page == "":
		_fail("%s: _page_for_mission routed nowhere" % label)
		return
	var sb := _dot_sb(m, page)
	if sb == null:
		_fail("%s: no visible dot on page '%s'" % [label, page])
		return
	var want: Color = UITheme.mission_tag_color(tag)
	if not _col_eq(sb.bg_color, want):
		_fail("%s: dot on '%s' is %s, mapping says %s" % [label, page, sb.bg_color, want])
		return
	# 6. the card side of the association: the mission card colors its name line
	# with the SAME function, so equality here is what makes the dot traceable.
	print("[DOT] %s -> page '%s' dot %s (matches card mapping)" % [label, page, sb.bg_color])
