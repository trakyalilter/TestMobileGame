extends Control
# ──────────────────────────────────────────────────────────────────────────
# Sector Chart — full-screen star-map overlay for combat sector + target select.
# Replaces the old NavPanel ItemList AND the in-HUD enemy-card list. Clicking a
# system selects it (page.select_zone) and fills the readout's TARGETS roster;
# picking a target + ENGAGE calls page.engage_from_map → request_fight(eid),
# then closes back to the combat HUD.
#
# State is read live from the combat manager (boss_kills, current_zone_id,
# get_available_zones, zones/enemy_db) — no save migration. Built in code (no
# .tscn), like the other combat modals.
# ──────────────────────────────────────────────────────────────────────────

const StarMapCanvas := preload("res://scripts/ui/star_map_canvas.gd")

const C_JADE  := Color(0.274, 0.878, 0.627)
const C_AQUA  := Color(0.427, 0.941, 0.847)
const C_TEAL  := Color(0.216, 0.788, 0.690)
const C_AMBER := Color(1.000, 0.761, 0.302)
const C_CORAL := Color(1.000, 0.392, 0.451)
const C_DIM   := Color(0.498, 0.639, 0.612)
const C_TEXT  := Color(0.894, 0.961, 0.933)

var manager
var page

var _canvas: Control
var _backdrop: ColorRect
var _frame: Panel
var _title: Label
var _subtitle: Label
var _legend: HBoxContainer
var _close_btn: Button
var _readout: PanelContainer

# readout fields
var _ro_name: Label
var _ro_band: Label
var _ro_status: Label
var _tgt_box: VBoxContainer       # selected-target detail (filled from sector view)
var _tgt_name: Label
var _tgt_type: Label
var _tgt_hp: Label
var _tgt_shield: Label
var _tgt_atk: Label
var _tgt_def: Label
var _tgt_xp: Label
var _tgt_resist: Label
var _tgt_weak: Label
var _tgt_drops: RichTextLabel     # v131: what the selected hostile drops
var _back_btn: Button
var _engage_btn: Button
var _engage_hint: Label

var selected_id: String = ""       # focused sector
var selected_enemy_id: String = "" # picked hostile (in sector view)
var _in_sector: bool = false
var _models: Array = []

# damage-type tag colours (match the combat HUD)
const DMG_COLS := {
	"kinetic": Color(0.60, 0.80, 1.00),
	"energy": Color(1.00, 0.90, 0.30),
	"explosive": Color(1.00, 0.50, 0.30),
}
const DMG_TAGS := {"kinetic": "KIN", "energy": "NRG", "explosive": "EXP"}

func setup(_manager, _page) -> void:
	manager = _manager
	page = _page
	name = "StarMapOverlay"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	if not resized.is_connected(_layout):
		resized.connect(_layout)
	selected_id = page.selected_zone_id if page.selected_zone_id != "" else ""
	visible = false

func open() -> void:
	visible = true
	move_to_front()
	if page.selected_zone_id != "":
		selected_id = page.selected_zone_id
	# always (re)open on the galaxy view, no target picked
	_in_sector = false
	selected_enemy_id = ""
	if _canvas:
		_canvas.reset_galaxy()
	_layout()
	rebuild()

func close() -> void:
	visible = false

# v128: coach anchors INTO the open Sector Chart — the sector map for the "pick a
# sector" step, the readout panel (target detail + weakness + engage) for the
# "pick a target / check weakness" steps. combat_page forwards here while the
# chart is up, since the old HUD anchors are covered by this overlay.
func get_coach_anchor(key: String) -> Control:
	match key:
		"zones":
			return _canvas
		"enemies":
			return _readout
	return null

# ── construction ────────────────────────────────────────────────────────-─
func _build_ui() -> void:
	# Near-solid scrim (full-rect anchored so it always covers, regardless of
	# _layout timing). At 0.94 the whole combat HUD + radar rings ghosted
	# through; a modal star map wants an opaque deck, not a tint.
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.019, 0.043, 0.039, 0.996)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)

	_frame = Panel.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(0, 0, 0, 0)
	fs.set_border_width_all(1)
	fs.border_color = Color(C_TEAL.r, C_TEAL.g, C_TEAL.b, 0.30)
	_frame.add_theme_stylebox_override("panel", fs)
	add_child(_frame)

	_canvas = StarMapCanvas.new()
	add_child(_canvas)
	_canvas.zone_clicked.connect(_on_zone_clicked)
	_canvas.zone_hovered.connect(_on_zone_hovered)
	_canvas.enemy_clicked.connect(_on_enemy_clicked)

	_title = _mk_label("SECTOR CHART", 18, Color(0.427, 0.941, 0.847), true)
	add_child(_title)
	_subtitle = _mk_label("NAVIGATION · SELECT A SECTOR", 9, C_DIM, false)
	add_child(_subtitle)

	_legend = HBoxContainer.new()
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.add_theme_constant_override("separation", 16)
	add_child(_legend)
	_legend_chip(C_JADE, "CLEARED")
	_legend_chip(C_AQUA, "CURRENT")
	_legend_chip(C_AMBER, "AVAILABLE")
	_legend_chip(C_DIM, "LOCKED")
	_legend_chip(C_CORAL, "BOSS")

	_close_btn = Button.new()
	_close_btn.text = "CLOSE"
	_close_btn.add_theme_font_size_override("font_size", 12)
	if UITheme.has_method("apply_premium_button_style"):
		UITheme.apply_premium_button_style(_close_btn, "combat")
	_close_btn.pressed.connect(close)
	add_child(_close_btn)

	_build_readout()

func _build_readout() -> void:
	_readout = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.122, 0.114, 0.96)
	sb.set_border_width_all(1)
	sb.border_color = Color(C_TEAL.r, C_TEAL.g, C_TEAL.b, 0.45)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(16)
	_readout.add_theme_stylebox_override("panel", sb)
	add_child(_readout)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	_readout.add_child(v)

	# v131: the info area SCROLLS (long boss drop lists overflowed the fixed-height
	# panel and pushed ENGAGE off-screen); the action buttons stay pinned below.
	var info_scroll := ScrollContainer.new()
	info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(info_scroll)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 7)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_scroll.add_child(info)

	info.add_child(_mk_label("DESTINATION", 9, C_TEAL, false))
	_ro_name = _mk_label("—", 20, C_TEXT, true)
	info.add_child(_ro_name)
	_ro_band = _mk_label("", 9, C_TEAL, false)
	info.add_child(_ro_band)

	# (Threat-level bar + recommended-DPS readout removed — the sector band label
	# above already conveys danger qualitatively without spoiler-y target numbers.)
	info.add_child(_sep())

	# TARGET — the hostile picked on the sector view (selection happens on the
	# map, not in a list). A prompt shows until one is chosen.
	info.add_child(_mk_label("TARGET", 9, C_TEAL, false))
	_ro_status = _mk_label("", 9, C_DIM, false)
	_ro_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ro_status.custom_minimum_size = Vector2(224, 0)
	info.add_child(_ro_status)
	_tgt_box = VBoxContainer.new()
	_tgt_box.add_theme_constant_override("separation", 3)
	info.add_child(_tgt_box)
	_tgt_name = _mk_label("", 15, C_TEXT, true)
	_tgt_box.add_child(_tgt_name)
	_tgt_type = _mk_label("", 9, C_DIM, false)
	_tgt_box.add_child(_tgt_type)
	_tgt_box.add_child(_spacer(2))
	_tgt_hp = _kv_row(_tgt_box, "HULL", "—", C_TEXT)
	_tgt_shield = _kv_row(_tgt_box, "SHIELD", "—", C_AQUA)
	_tgt_atk = _kv_row(_tgt_box, "ATTACK", "—", C_TEXT)
	_tgt_def = _kv_row(_tgt_box, "DEFENSE", "—", C_TEXT)
	_tgt_xp = _kv_row(_tgt_box, "XP REWARD", "—", C_JADE)
	_tgt_box.add_child(_spacer(3))
	_tgt_resist = _kv_row(_tgt_box, "RESISTS", "—", C_CORAL)
	_tgt_weak = _kv_row(_tgt_box, "WEAK TO", "—", C_JADE)
	# v131: DROPS — the loot case for picking this target (was invisible intel).
	_tgt_box.add_child(_spacer(3))
	_tgt_box.add_child(_mk_label("DROPS", 9, C_TEAL, false))
	_tgt_drops = RichTextLabel.new()
	_tgt_drops.bbcode_enabled = true
	_tgt_drops.fit_content = true
	_tgt_drops.scroll_active = false
	_tgt_drops.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tgt_drops.add_theme_font_size_override("normal_font_size", 10)
	_tgt_drops.custom_minimum_size = Vector2(224, 0)
	_tgt_box.add_child(_tgt_drops)
	_tgt_box.visible = false

	# (v131: expanding spacer removed — the scroll area above takes the expansion,
	# which pins the buttons to the bottom the same way.)

	_back_btn = Button.new()
	_back_btn.text = "BACK TO STAR MAP"
	_back_btn.custom_minimum_size = Vector2(0, 30)
	_back_btn.add_theme_font_size_override("font_size", 11)
	if UITheme.has_method("apply_premium_button_style"):
		UITheme.apply_premium_button_style(_back_btn, "ops")
	_back_btn.pressed.connect(_on_back)
	_back_btn.visible = false
	v.add_child(_back_btn)

	_engage_btn = Button.new()
	_engage_btn.text = "SELECT A SECTOR"
	_engage_btn.custom_minimum_size = Vector2(0, 44)
	_engage_btn.add_theme_font_size_override("font_size", 14)
	if UITheme.has_method("apply_premium_button_style"):
		UITheme.apply_premium_button_style(_engage_btn, "combat")
	_engage_btn.pressed.connect(_on_engage)
	_engage_btn.disabled = true
	v.add_child(_engage_btn)
	_engage_hint = _mk_label("Click a sector on the chart to scan it.", 8, C_DIM, false)
	_engage_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_engage_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_engage_hint.custom_minimum_size = Vector2(224, 0)
	v.add_child(_engage_hint)

# ── layout (absolute, recomputed on resize) ───────────────────────────────-
func _layout() -> void:
	var w := size.x
	var h := size.y
	# backdrop + frame are full-rect anchored; no manual sizing needed.
	if _title: _title.position = Vector2(46, 24)
	if _subtitle: _subtitle.position = Vector2(46, 50)
	if _legend: _legend.position = Vector2(46, h - 32)
	if _close_btn:
		_close_btn.position = Vector2(w - 116, 22)
		_close_btn.custom_minimum_size = Vector2(94, 30)
	var ro_w := 272.0
	if _readout:
		_readout.position = Vector2(w - ro_w - 36, 80)
		_readout.size = Vector2(ro_w, h - 80 - 36)
	if _canvas:
		_canvas.position = Vector2(36, 76)
		_canvas.size = Vector2(w - ro_w - 36 - 36 - 16, h - 76 - 36)

# ── state model ───────────────────────────────────────────────────────────
func rebuild() -> void:
	_models = _compute_models()
	_canvas.set_models(_models)
	if _model_by_id(selected_id).is_empty():
		selected_id = _default_selection()
	_canvas.set_selected(selected_id)
	if not _in_sector:
		_set_idle_readout(_model_by_id(selected_id))

# Called by the page when the selection changes elsewhere (e.g. coach focus).
func set_external_selection(zone_id: String) -> void:
	selected_id = zone_id
	if _canvas:
		_canvas.set_selected(zone_id)
	if visible and not _in_sector:
		_set_idle_readout(_model_by_id(zone_id))

func _compute_models() -> Array:
	var avail := {}
	for z in manager.get_available_zones():
		avail[z["id"]] = true
	var out: Array = []
	for zid in manager.zones:
		var data = manager.zones[zid]
		var boss_id := _find_boss(data.get("enemies", []))
		var cleared: bool = boss_id != "" and int(manager.boss_kills.get(boss_id, 0)) > 0
		var is_avail: bool = avail.has(zid)
		# v131: the "cleared always shows" bypass ALSO requires the zone's ACCESS
		# research to be unlocked. A desynced save (a boss_kills entry without its
		# access research — e.g. from debug tools) otherwise leaks a far sector onto
		# the map, spoiling what's ahead. Normal play can't clear a sector before
		# researching access, so this is transparent there.
		var req := str(data.get("research_req", ""))
		var research_ok: bool = req == "" or (GameState.research_manager and GameState.research_manager.is_tech_unlocked(req))
		# Reveal gate: an undiscovered system stays OFF the chart until its unlock
		# research makes it available — sectors appear one by one instead of the
		# whole map (which spoils what's ahead). Cleared+accessible systems show.
		if not is_avail and not (cleared and research_ok):
			continue
		var state := "locked"
		if zid == manager.current_zone_id and is_avail:
			state = "current"
		elif cleared:
			state = "cleared"
		elif is_avail:
			state = "available"
		out.append({
			"id": zid,
			"name": str(data.get("name", zid)),
			"difficulty": int(data.get("difficulty", 1)),
			"state": state,
			"is_boss": boss_id != "",
			"is_hazard": false,
		})
	for hid in manager.hazard_zones:
		var hz = manager.hazard_zones[hid]
		var unlocked: bool = manager.is_hazard_unlocked(hid)
		# Reveal gate (same as systems): hidden until its access is unlocked.
		if not unlocked and not manager.hazard_clears.has(hid):
			continue
		# Hazard ids live in hazard_zones, not zones, so the main loop's
		# current-zone check above never matches them. Derive state here, with
		# current_zone_id taking precedence (start_hazard sets it to the hazard
		# id) so the player's position shows on the chart mid-gauntlet — matching
		# combat_page._zone_state.
		var h_state := "locked"
		if unlocked:
			h_state = "available"
		if manager.hazard_clears.has(hid):
			h_state = "cleared"
		if unlocked and hid == manager.current_zone_id:
			h_state = "current"
		out.append({
			"id": hid,
			"name": str(hz.get("name", "Hazard")),
			"difficulty": int(hz.get("zone_difficulty", 3)),
			"state": h_state,
			"is_boss": true,
			"is_hazard": true,
		})
	return out

func _find_boss(enemies: Array) -> String:
	for eid in enemies:
		if manager.enemy_db.get(eid, {}).get("is_boss", false):
			return str(eid)
	for eid in enemies:
		if str(eid).findn("boss") >= 0:
			return str(eid)
	return ""

func _default_selection() -> String:
	# Prefer where the player is, then the deepest reachable system, else home.
	var cur: String = manager.current_zone_id
	if cur != "" and _state_of(cur) != "locked":
		return cur
	var best := ""
	var bd := -1
	for m in _models:
		if str(m["state"]) != "locked" and int(m["difficulty"]) > bd:
			bd = int(m["difficulty"])
			best = str(m["id"])
	return best if best != "" else "lunar_orbit"

func _state_of(zid: String) -> String:
	var m := _model_by_id(zid)
	return "locked" if m.is_empty() else str(m["state"])

func _model_by_id(id: String) -> Dictionary:
	for m in _models:
		if m["id"] == id:
			return m
	return {}

# ── readout ────────────────────────────────────────────────────────────────
# Shared header: sector name / band / threat / recommended DPS.
func _update_sector_header(m: Dictionary) -> void:
	if m.is_empty():
		return
	var diff := int(m["difficulty"])
	var heat := _heat(diff)
	_ro_name.text = str(m["name"]).replace("⚠ ", "").to_upper()
	_ro_name.add_theme_color_override("font_color", C_AQUA if str(m["state"]) == "current" else C_TEXT)
	var band := "CALM SPACE" if diff <= 4 else ("CONTESTED SPACE" if diff <= 8 else "HOSTILE SPACE")
	if m.get("is_hazard", false):
		band = "ELECTROMAGNETIC HAZARD"
	_ro_band.text = "SECTOR %02d · %s" % [diff, band]
	_ro_band.add_theme_color_override("font_color", heat)

# Galaxy view — a sector is highlighted but not drilled into yet.
func _set_idle_readout(m: Dictionary) -> void:
	if m.is_empty():
		return
	_update_sector_header(m)
	_tgt_box.visible = false
	_back_btn.visible = false
	var st := str(m["state"])
	if st == "locked":
		_ro_status.text = _gate_text(str(m["id"]))
		_ro_status.add_theme_color_override("font_color", C_CORAL)
		_engage_btn.disabled = true
		_engage_btn.text = "SECTOR LOCKED"
		_engage_hint.text = "Unlock this sector to deploy here."
	elif m.get("is_hazard", false):
		_ro_status.text = _hazard_summary(str(m["id"]))
		_ro_status.add_theme_color_override("font_color", C_AMBER)
		_engage_btn.disabled = false
		_engage_btn.text = "ENTER GAUNTLET"
		_engage_hint.text = "A multi-wave gauntlet — no single target to pick."
	else:
		_ro_status.text = "Click this sector to drop in and scan its hostiles."
		_ro_status.add_theme_color_override("font_color", C_DIM)
		_engage_btn.disabled = true
		_engage_btn.text = "SELECT A SECTOR"
		_engage_hint.text = "Click a sector on the chart to drill in."

# Sector view — drilled in, awaiting a target pick on the map.
func _set_sector_prompt(m: Dictionary) -> void:
	_update_sector_header(m)
	_tgt_box.visible = false
	_back_btn.visible = true
	_ro_status.text = "Select a hostile cluster or the boss on the map."
	_ro_status.add_theme_color_override("font_color", C_DIM)
	_engage_btn.disabled = true
	_engage_btn.text = "SELECT A TARGET"
	_engage_hint.text = "Click a cluster on the chart, then engage."

# A target was picked on the sector view — show its detail, enable ENGAGE.
func _show_target_detail(eid: String) -> void:
	var e = manager.enemy_db.get(eid, {})
	if e.is_empty():
		return
	var s = e.get("stats", {})
	var is_boss: bool = e.get("is_boss", false)
	var dt := str(e.get("dmg_type", "kinetic"))
	_back_btn.visible = true
	_tgt_box.visible = true
	_ro_status.text = ""
	_tgt_name.text = str(e.get("name", "Hostile"))
	_tgt_name.add_theme_color_override("font_color", C_CORAL if is_boss else C_TEXT)
	_tgt_type.text = ("SECTOR BOSS · %s DAMAGE" % DMG_TAGS.get(dt, "KIN")) if is_boss else ("%s DAMAGE" % DMG_TAGS.get(dt, "KIN"))
	_tgt_type.add_theme_color_override("font_color", DMG_COLS.get(dt, C_DIM))
	_tgt_hp.text = UITheme.format_num(s.get("hp", 0))
	var sh := int(s.get("max_shield", 0))
	_tgt_shield.get_parent().visible = sh > 0
	_tgt_shield.text = UITheme.format_num(sh)
	_tgt_atk.text = UITheme.format_num(s.get("atk", 0))
	_tgt_def.text = UITheme.format_num(int(s.get("def", 0)))
	_tgt_xp.text = "+%s" % UITheme.format_num(int(e.get("xp", 0)))

	# Resist / weakness — the actionable intel for picking a loadout before ENGAGE.
	if e.get("warp_hardened", false):
		_tgt_resist.text = "all except Cryo"
		_tgt_weak.text = "CRYO only (warp-hardened)"
	else:
		var res_parts: Array = []
		var weak_parts: Array = []
		for entry in [[float(e.get("resist_k", 0.0)), "KIN"], [float(e.get("resist_e", 0.0)), "NRG"], [float(e.get("resist_x", 0.0)), "EXP"], [float(e.get("resist_cryo", 0.0)), "CRY"]]:
			var rv: float = entry[0]
			var tag: String = entry[1]
			if rv > 0.05:
				res_parts.append("%s +%d%%" % [tag, int(round(rv * 100.0))])
			elif rv < -0.05:
				weak_parts.append("%s %d%%" % [tag, int(round(rv * 100.0))])
		_tgt_resist.text = " · ".join(res_parts) if not res_parts.is_empty() else "none"
		_tgt_weak.text = " · ".join(weak_parts) if not weak_parts.is_empty() else "none"

	_fill_target_drops(e, is_boss)

	_engage_btn.disabled = false
	_engage_btn.text = "ENGAGE"
	_engage_hint.text = "Deploy and attack %s." % str(e.get("name", "the target"))

# v131: render the hostile's drop table into the readout. Materials (with qty
# ranges), rare drops (with odds), boss core / first-clear relic, and the module
# roll — the other half of "is this the right target to farm?".
func _fill_target_drops(e: Dictionary, is_boss: bool) -> void:
	if not is_instance_valid(_tgt_drops):
		return
	var dim := "#8fa6a0"
	var lines: Array = []
	for entry in e.get("loot", []):
		var sym := str(entry[0])
		var qty := "%s–%s" % [UITheme.format_num(int(entry[1])), UITheme.format_num(int(entry[2]))]
		if sym == "credits":
			lines.append("%sLiras ×%s" % [UITheme.LIRA_ICON_BB, qty])
		else:
			lines.append("%s%s ×%s" % [ElementDB.material_icon_bbcode(sym, 12), ElementDB.get_display_name(sym), qty])
	for entry in e.get("rare_loot", []):
		var rsym := str(entry[0])
		lines.append("%s%s [color=%s](rare)[/color]" % [ElementDB.material_icon_bbcode(rsym, 12), _drop_display_name(rsym), dim])
	var core := str(e.get("boss_core", ""))
	if core != "":
		lines.append("%s%s [color=%s](guaranteed)[/color]" % [ElementDB.material_icon_bbcode(core, 12), ElementDB.get_display_name(core), dim])
	if str(e.get("relic_drop", "")) != "":
		lines.append("Threshold Relic [color=%s](first clear)[/color]" % dim)
	# v131b: no probabilities shown — just WHAT can drop (types), not the odds.
	var pool_types := _pool_slot_types(e)
	if is_boss and not pool_types.is_empty():
		lines.append("Modules [color=%s](Uncommon+ · %s)[/color]" % [dim, " · ".join(PackedStringArray(pool_types))])
	elif e.get("drops_modules", true) and float(e.get("module_drop_chance", 0.0)) > 0.0 and not pool_types.is_empty():
		lines.append("Module chance [color=%s](%s)[/color]" % [dim, " · ".join(PackedStringArray(pool_types))])
	_tgt_drops.text = "[color=#c8d4d0]" + "\n".join(PackedStringArray(lines)) + "[/color]" if not lines.is_empty() else "[color=%s]—[/color]" % dim

# v131: rare_loot mixes ELEMENT ids and MODULE ids (unique set pieces like
# z1_unique_weapon). Resolve module ids to their real display names; everything
# else goes through ElementDB as usual.
func _drop_display_name(id: String) -> String:
	var sm = GameState.shipyard_manager
	if sm and sm.modules.has(id):
		return str(sm.modules[id].get("name", id))
	return ElementDB.get_display_name(id)

# v131: which SLOT TYPES this hostile's module pool can actually yield — mirrors
# the real drop rules: research-locked bases are filtered out (same check as
# win_fight's unlocked_pool) and weight-0 types (battery) never drop.
func _pool_slot_types(e: Dictionary) -> Array:
	var sm = GameState.shipyard_manager
	var rm = GameState.research_manager
	if sm == null:
		return []
	var order := ["weapon", "shield", "armor", "engine", "sensor"]
	var found := {}
	for mod_id in e.get("module_drop_pool", []):
		var mdef: Dictionary = sm.modules.get(str(mod_id), {})
		if mdef.is_empty():
			continue
		var req := str(mdef.get("research_req", ""))
		if req != "" and rm and not rm.is_tech_unlocked(req):
			continue
		var st := str(mdef.get("slot_type", "weapon"))
		if float(manager.MODULE_DROP_WEIGHTS.get(st, 10)) <= 0.0:
			continue
		found[st] = true
	var out: Array = []
	for st in order:
		if found.has(st):
			out.append(st.capitalize())
	return out

func _zone_combat_stats(zid: String) -> Dictionary:
	var data = manager.zones.get(zid, {})
	var boss_hp := 0
	var boss_atk := 0
	var boss_name := "—"
	var tough_hp := 0
	for eid in data.get("enemies", []):
		var e = manager.enemy_db.get(eid, {})
		var s = e.get("stats", {})
		if e.get("is_boss", false):
			boss_hp = int(s.get("hp", 0))
			boss_atk = int(s.get("atk", 0))
			boss_name = str(e.get("name", "Boss"))
		elif int(s.get("hp", 0)) > tough_hp:
			tough_hp = int(s.get("hp", 0))
	var rec := int(boss_hp / 30.0) if boss_hp > 0 else int(tough_hp / 15.0)
	var enemy_txt := "%s HP" % UITheme.format_num(tough_hp) if tough_hp > 0 else "—"
	return {"enemy": enemy_txt, "boss": boss_name, "dps": rec}

func _gate_text(zid: String) -> String:
	if manager.hazard_zones.has(zid):
		return "Locked — defeat the Asteroid Belt boss to expose this anomaly."
	var data = manager.zones.get(zid, {})
	var req = data.get("research_req", "")
	if req != "":
		return "Locked — complete research: %s." % str(req).capitalize()
	var flag = data.get("unlock_flag", "")
	if flag == "z11_unlocked":
		return "Locked — defeat the Sector 10 boss, then execute a Warp."
	if flag == "z12_unlocked":
		return "Locked — clear The Threshold, then Warp."
	return "Locked."

func _heat(diff: int) -> Color:
	if diff <= 4:
		return C_TEAL
	elif diff <= 8:
		return C_AMBER
	return C_CORAL

# ── sector enemy models (fed to the canvas, pre-formatted so it stays dumb) ──
func _build_enemy_models(zid: String) -> Array:
	var data = manager.zones.get(zid, {})
	var enemies: Array = data.get("enemies", []).duplicate()
	# weakest -> strongest, boss last (consistent cluster ordering)
	enemies.sort_custom(func(a, b):
		var ea = manager.enemy_db.get(a, {})
		var eb = manager.enemy_db.get(b, {})
		var ba: bool = ea.get("is_boss", false)
		var bb: bool = eb.get("is_boss", false)
		if ba != bb:
			return not ba
		return _enemy_score(ea) < _enemy_score(eb)
	)
	var out: Array = []
	for eid in enemies:
		if not manager.enemy_db.has(eid):
			continue
		var e = manager.enemy_db[eid]
		var s = e.get("stats", {})
		var dt := str(e.get("dmg_type", "kinetic"))
		out.append({
			"eid": str(eid),
			"name": str(e.get("name", "Hostile")),
			"is_boss": e.get("is_boss", false),
			"color": DMG_COLS.get(dt, C_DIM),
			"hp_txt": UITheme.format_num(s.get("hp", 0)),
			"tag": DMG_TAGS.get(dt, "KIN"),
		})
	return out

func _enemy_score(e: Dictionary) -> float:
	var s = e.get("stats", {})
	return (float(s.get("hp", 0)) + float(s.get("max_shield", 0))) \
		* (1.0 + float(s.get("def", 0)) / 100.0) \
		* (1.0 + float(s.get("atk", 0)) / 50.0)

func _hazard_summary(hid: String) -> String:
	var hz = manager.hazard_zones.get(hid, {})
	var counter = GameState.shipyard_manager.modules.get(hz.get("counter_module", ""), {}).get("name", hz.get("counter_module", ""))
	var cleared: bool = manager.hazard_clears.has(hid)
	return "%d-wave gauntlet. Requires %s. %s" % [int(hz.get("max_waves", 0)), counter, "Cleared." if cleared else "Not yet cleared."]

# ── interaction ───────────────────────────────────────────────────────────
func _on_zone_clicked(zid: String) -> void:
	var m := _model_by_id(zid)
	if m.is_empty():
		return
	selected_id = zid
	selected_enemy_id = ""
	_canvas.set_selected(zid)
	page.select_zone(zid)
	var st := str(m["state"])
	if st == "locked":
		_canvas.shake(zid)
		_set_idle_readout(m)
		return
	if m.get("is_hazard", false):
		# hazards are a wave gauntlet, not a cluster field — engage from here.
		_set_idle_readout(m)
		return
	# drill into the sector close-up: hostiles spread as clickable clusters.
	_in_sector = true
	_canvas.enter_sector(m, _build_enemy_models(zid))
	_set_sector_prompt(m)

func _on_enemy_clicked(eid: String) -> void:
	selected_enemy_id = eid
	_show_target_detail(eid)

func _on_back() -> void:
	_in_sector = false
	selected_enemy_id = ""
	_canvas.exit_sector()
	_set_idle_readout(_model_by_id(selected_id))

func _on_zone_hovered(_zid: String) -> void:
	pass  # hover handled visually in the canvas

func _on_engage() -> void:
	var m := _model_by_id(selected_id)
	if m.is_empty() or str(m["state"]) == "locked":
		return
	if m.get("is_hazard", false):
		page.engage_from_map(selected_id, "")   # hazard ignores the target id
		close()
		return
	if selected_enemy_id == "":
		return
	page.engage_from_map(selected_id, selected_enemy_id)
	close()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	# Clicking empty backdrop (children consume their own areas) closes.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		close()

# ── widget helpers ─────────────────────────────────────────────────────────
func _mk_label(txt: String, fs: int, col: Color, bold: bool) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if bold:
		l.add_theme_constant_override("outline_size", 0)
	return l

func _kv_row(parent: VBoxContainer, key: String, val: String, val_col: Color) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var k := _mk_label(key, 8, C_DIM, false)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(k)
	var val_lbl := _mk_label(val, 10, val_col, false)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_lbl)
	return val_lbl

func _sep() -> HSeparator:
	var s := HSeparator.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_TEAL.r, C_TEAL.g, C_TEAL.b, 0.18)
	sb.content_margin_top = 1
	s.add_theme_stylebox_override("separator", sb)
	return s

func _spacer(h: float, expand: bool = false) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		c.custom_minimum_size = Vector2(0, h)
	return c

func _legend_chip(col: Color, txt: String) -> void:
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 5)
	var dot := ColorRect.new()
	dot.color = col
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(dot)
	box.add_child(_mk_label(txt, 8, C_DIM, false))
	_legend.add_child(box)

# (removed _style_threat_bar — the star-map threat bar was cut.)
