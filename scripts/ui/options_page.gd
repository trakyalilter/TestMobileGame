extends Control

# Sys Config — rebuilt as a scrollable, sectioned settings screen.
# The whole page is constructed in code so the layout isn't path-fragile and
# every section panel flows through UITheme.apply_card_style(), so it inherits
# the player's chosen card-frame "soul" just like every gameplay card.

const SPEED_OPTIONS := [1.0, 2.0, 4.0, 8.0, 16.0]

const FRAME_CAT := "engineering"   # neutral cyan for section frames
const DANGER_CAT := "combat"       # red for destructive actions
const HEADER_CAT := "ops"          # warm anchor for the page header

# Selected-state tint (matches the existing convention used for speed/cursor).
const SEL := Color(0.45, 1.0, 0.55)
const UNSEL := Color(1, 1, 1)

var _column: VBoxContainer
var _refreshers: Array = []        # Array[Callable] — repaint selected states
var _pt_label: Label               # total play-time readout
var _tele_label: Label             # balance telemetry readout
var _pt_refresh := 0.0
# Test Fitter (debug — Testing section). Persists in-session selection
# so the Fit button is one click after picking Tier + Rarity once.
var _test_hull_tier: int = 1
var _test_tier: int = 1
var _test_rarity: int = 2  # Rare default — best signal-to-noise for combat tests
var _test_weapon_type: int = 0  # 0=Mixed (rotate KIN/NRG/EXP), 1=KIN, 2=NRG, 3=EXP
var _test_consumable_id: String = "Mesh"  # default to the most common hull consumable
var _test_zone_tier: int = 2  # Z2 is the first gated zone (Z1 is always available)
var _grant_symbol_edit: LineEdit  # arbitrary-material granter — filter/typed input
var _grant_amount_edit: LineEdit  # arbitrary-material granter — amount input
var _grant_symbol_list: ItemList  # filterable suggestion dropdown
var _grant_symbol_syms: Array = []  # symbols parallel to _grant_symbol_list rows
var _grant_selected_symbol: String = ""  # symbol chosen from the dropdown
# v128 debug — skill/research setters + mission control
var _dbg_skill_idx: int = 0        # 0 = Gathering, 1 = Processing
var _dbg_skill_level: int = 100
var _dbg_mission_edit: LineEdit    # type a mission id to reveal/complete
# v130 debug — overclock / efficiency testing
var _dbg_eff_tier: int = 5         # 0 = none, 1..5 = Efficiency I..V


func _ready() -> void:
	_build_ui()
	$ConfirmationDialog.confirmed.connect(_on_confirmation_dialog_confirmed)


# --------------------------------------------------------------------------
# Layout scaffold
# --------------------------------------------------------------------------
func _build_ui() -> void:
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + s, 24)
	add_child(pad)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_FILL
	scroll.size_flags_vertical = Control.SIZE_FILL
	pad.add_child(scroll)

	# Centre a fixed-width column so controls stop stretching to full screen.
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.custom_minimum_size = Vector2(620, 0)
	col.add_theme_constant_override("separation", 16)
	center.add_child(col)
	_column = col

	_build_header()
	_build_save_section()
	_build_gameplay_section()
	_build_interface_section()
	_build_testing_section()

	var foot := Label.new()
	foot.text = tr("Horizon Idle · demo build · changes save automatically")
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_theme_font_size_override("font_size", 11)
	foot.add_theme_color_override("font_color", Color(0.45, 0.47, 0.55))
	col.add_child(foot)

	_refresh_all()


# --------------------------------------------------------------------------
# Sections
# --------------------------------------------------------------------------
func _build_header() -> void:
	var body := _section("System Config", HEADER_CAT)
	var sub := Label.new()
	sub.text = tr("Save, gameplay and interface options.")
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.62, 0.66, 0.76))
	body.add_child(sub)

	_pt_label = Label.new()
	_pt_label.add_theme_font_size_override("font_size", 12)
	_pt_label.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS[HEADER_CAT].lightened(0.25))
	body.add_child(_pt_label)
	_refresh_playtime()


func _build_save_section() -> void:
	var body := _section("Save Data", FRAME_CAT)

	# No manual SAVE GAME button — the game autosaves every 60s and on exit, so a
	# manual save is redundant (and misreads as "progress is lost unless you press
	# this"). Only the Hard Reset control lives here.
	var warn := Label.new()
	warn.text = tr("Hard reset wipes your save permanently — this cannot be undone.")
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.add_theme_font_size_override("font_size", 11)
	warn.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS[DANGER_CAT].lightened(0.15))
	body.add_child(warn)

	var reset_btn := _primary_button("HARD RESET GAME", DANGER_CAT)
	reset_btn.custom_minimum_size = Vector2(0, 38)
	reset_btn.pressed.connect(_on_reset_btn_pressed)
	body.add_child(reset_btn)


func _build_gameplay_section() -> void:
	var body := _section("Gameplay", FRAME_CAT)
	_add_choice_row(body, "Offline Combat",
		[["Off", false], ["On", true]],
		func(): return GameState.game_settings.get("offline_combat", false),
		func(v): _on_offline_combat_toggled(v))

	var replay := _primary_button("Replay Tutorials", FRAME_CAT)
	replay.custom_minimum_size = Vector2(0, 38)
	replay.pressed.connect(_on_replay_tutorials_pressed)
	body.add_child(replay)


func _build_interface_section() -> void:
	var body := _section("Interface", FRAME_CAT)

	_add_choice_row(body, "Cursor Size",
		[["Small", CursorManager.SIZE_SMALL],
		 ["Medium", CursorManager.SIZE_MEDIUM],
		 ["Large", CursorManager.SIZE_LARGE]],
		func(): return CursorManager.get_size(),
		func(v): _on_cursor_size_pressed(v))

	_add_choice_row(body, "Card Frame",
		[["Industrial", UITheme.CHROME_INDUSTRIAL],
		 ["Holographic", UITheme.CHROME_HOLOGRAPHIC],
		 ["Precursor", UITheme.CHROME_PRECURSOR]],
		func(): return UITheme.get_card_chrome(),
		func(v): _on_card_frame_pressed(v))

	_build_palette_picker(body)


# v123: UI colour-palette picker — wrapping buttons, each tinted with its
# palette's signature accent (active one stays white). Selecting one applies +
# saves it and reloads the scene so every stylebox re-themes against the new
# tokens; the player lands back on this page (GameState.ui_return_page).
func _build_palette_picker(body: VBoxContainer) -> void:
	var lbl := Label.new()
	lbl.text = tr("Color Palette")
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.66, 0.7, 0.8))
	body.add_child(lbl)

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	body.add_child(flow)

	var cur := UITheme.get_ui_palette()
	for id in UITheme.PALETTE_ORDER:
		var pal: Dictionary = UITheme.UI_PALETTES[id]
		var b := Button.new()
		b.text = str(pal["name"])
		b.custom_minimum_size = Vector2(134, 36)
		b.add_theme_font_size_override("font_size", 12)
		UITheme.apply_premium_button_style(b, FRAME_CAT)
		var acc: String = pal["colors"]["accent"]
		b.add_theme_color_override("font_color", Color.WHITE if id == cur else Color.html(acc))
		if id == cur:
			b.tooltip_text = tr("Active palette")
		b.pressed.connect(_on_palette_pressed.bind(id))
		flow.add_child(b)


func _on_palette_pressed(id: String) -> void:
	if id == UITheme.get_ui_palette():
		return   # already active — skip the reload
	UITheme.apply_palette(id)
	GameState.save_game()
	GameState.ui_return_page = "options"   # land back here after the rebuild
	get_tree().reload_current_scene()


func _build_testing_section() -> void:
	var body := _section("Testing", "research")

	var speed_opts := []
	for s in SPEED_OPTIONS:
		speed_opts.append(["%d×" % int(s), s])
	_add_choice_row(body, "Game Speed",
		speed_opts,
		func(): return Engine.time_scale,
		func(v): _set_game_speed(v))

	body.add_child(HSeparator.new())

	_build_test_fitter(body)

	body.add_child(HSeparator.new())

	_build_zone_unlocker(body)

	body.add_child(HSeparator.new())

	_build_material_granter(body)

	body.add_child(HSeparator.new())

	_build_warp_debug(body)

	body.add_child(HSeparator.new())

	_build_offline_debug(body)

	body.add_child(HSeparator.new())

	_build_skill_research_debug(body)

	body.add_child(HSeparator.new())

	_build_mission_debug(body)

	body.add_child(HSeparator.new())

	_build_overclock_debug(body)

	body.add_child(HSeparator.new())

	var tele_title := Label.new()
	tele_title.text = tr("Balance Telemetry (debug)")
	tele_title.add_theme_font_size_override("font_size", 12)
	tele_title.add_theme_color_override("font_color", Color(0.66, 0.7, 0.8))
	body.add_child(tele_title)

	_tele_label = Label.new()
	_tele_label.add_theme_font_size_override("font_size", 11)
	_tele_label.add_theme_color_override("font_color", Color(0.6, 0.85, 0.7))
	body.add_child(_tele_label)
	_refresh_telemetry()


# --------------------------------------------------------------------------
# Test Fitter (debug)
# --------------------------------------------------------------------------
# Auto-fits the active hull with the chosen Tier (Z1-10) + Rarity using the
# same drop pipeline combat uses, so the resulting modules carry the correct
# rarity bonuses + affixes. Bypasses can_equip_module's research gate by
# writing loadout[] directly — the whole point of this tool is to test gear
# you haven't unlocked yet. Weapon slots rotate KIN/NRG/EXP for damage-type
# variety, which is what Phase A's triangle expects you to leverage.
func _build_test_fitter(body: VBoxContainer) -> void:
	var title := Label.new()
	title.text = tr("Ship Fitter (debug)")
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.66, 0.7, 0.8))
	body.add_child(title)

	var hint := Label.new()
	hint.text = tr("Auto-fit the active hull at the chosen Tier + Rarity. Bypasses research gates. Overwrites current loadout.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.55, 0.58, 0.65))
	body.add_child(hint)

	# Hull construction — foundation step. Swap to any tier's hull, free,
	# bypassing research/credits/materials. Clears existing loadout (slot
	# layouts differ per tier; modules return to inventory via unequip_all).
	var hull_opts: Array = []
	for t in range(1, 11):
		hull_opts.append(["T%d" % t, t])
	_add_choice_row(body, "Hull Tier",
		hull_opts,
		func(): return _test_hull_tier,
		func(v): _set_test_hull_tier(v))

	var hull_btn := _primary_button("CONSTRUCT HULL", DANGER_CAT)
	hull_btn.custom_minimum_size = Vector2(0, 38)
	hull_btn.pressed.connect(_on_test_construct_hull_pressed)
	body.add_child(hull_btn)

	body.add_child(HSeparator.new())

	var tier_opts: Array = []
	for t in range(1, 11):
		tier_opts.append(["T%d" % t, t])
	_add_choice_row(body, "Module Tier",
		tier_opts,
		func(): return _test_tier,
		func(v): _set_test_tier(v))

	var rarity_opts: Array = [
		["Common", 0], ["Uncommon", 1], ["Rare", 2], ["Legendary", 3], ["Unique", 4]
	]
	_add_choice_row(body, "Rarity",
		rarity_opts,
		func(): return _test_rarity,
		func(v): _set_test_rarity(v))

	# Weapon Type: Mixed = rotate KIN/NRG/EXP across weapon slots (variety,
	# good for general testing). KIN/NRG/EXP = force ALL weapon slots to one
	# type (useful for isolating Phase A triangle scenarios — e.g. "all KIN
	# vs the kinetic-resist enemy in Z1, how punishing is wrong-type?").
	var wtype_opts: Array = [
		["Mixed", 0], ["KIN", 1], ["NRG", 2], ["EXP", 3]
	]
	_add_choice_row(body, "Weapon Type",
		wtype_opts,
		func(): return _test_weapon_type,
		func(v): _set_test_weapon_type(v))

	var fit_btn := _primary_button("FIT SHIP", DANGER_CAT)
	fit_btn.custom_minimum_size = Vector2(0, 38)
	fit_btn.pressed.connect(_on_test_fit_pressed)
	body.add_child(fit_btn)

	body.add_child(HSeparator.new())

	# Consumable stocking — pre-fight prep for sustained combat tests.
	# 5 hull consumables (heal % asc) then 5 shield consumables. Short
	# labels keep the segmented row sane on the 620px column.
	var cons_opts: Array = [
		["Patch", "EmergencyPatch"], ["Chitin", "ChitinPatch"], ["Mesh", "Mesh"],
		["Seal", "Seal"], ["AdvKit", "AdvMaintenanceKit"],
		["Shard", "CapacitorShard"], ["Boost", "BasicBooster"], ["Ion", "IonField"],
		["Cryo", "NitroCoolant"], ["ZeroP", "ZeroPoint"]
	]
	_add_choice_row(body, "Consumable",
		cons_opts,
		func(): return _test_consumable_id,
		func(v): _set_test_consumable(v))

	var stock_btn := _primary_button("+100 CONSUMABLE", FRAME_CAT)
	stock_btn.custom_minimum_size = Vector2(0, 38)
	stock_btn.pressed.connect(_on_test_stock_consumable_pressed)
	body.add_child(stock_btn)

	# v127: debug grant of Hack Stones so the Ship Designer's Hacking bar can be
	# tested without grinding research-gated combat drops.
	var stones_btn := _primary_button("+5 HACK CARDS (each)", FRAME_CAT)
	stones_btn.custom_minimum_size = Vector2(0, 38)
	stones_btn.pressed.connect(_on_test_grant_hack_stones_pressed)
	body.add_child(stones_btn)


func _set_test_tier(v) -> void:
	_test_tier = int(v)
	_refresh_all()


func _set_test_rarity(v) -> void:
	_test_rarity = int(v)
	_refresh_all()


func _set_test_weapon_type(v) -> void:
	_test_weapon_type = int(v)
	_refresh_all()


func _set_test_consumable(v) -> void:
	_test_consumable_id = str(v)
	_refresh_all()


# v127: debug — grant 5 of each Hack Stone, so the Ship Designer's Hacking bar +
# arm/apply flow can be tested without waiting on research-gated combat drops.
func _on_test_grant_hack_stones_pressed() -> void:
	if not GameState.resources:
		UITheme.show_notification("Resources unavailable.", Color.RED)
		return
	for sid in ["SpliceChip", "FirmwareInjector", "RootKey", "AnchorBolt", "CorruptionWorm", "RefitBay", "SignalCalibrator"]:
		GameState.resources.add_element(sid, 5)
	if GameState.shipyard_manager:
		GameState.shipyard_manager.inventory_updated.emit()
	UITheme.show_notification("+5 of each Hack Card. Open Ship Designer -> Armory to use them.", Color(0.6, 0.85, 1.0))


func _set_test_hull_tier(v) -> void:
	_test_hull_tier = int(v)
	_refresh_all()


func _on_test_construct_hull_pressed() -> void:
	var sm = GameState.shipyard_manager
	if not sm:
		UITheme.show_notification("Shipyard manager unavailable.", Color.RED)
		return
	# Resolve hull-id by tier (data-driven; doesn't hard-code corvette/frigate/…).
	var target_id: String = ""
	for hull_id in sm.hulls:
		if int(sm.hulls[hull_id].get("tier", 0)) == _test_hull_tier:
			target_id = hull_id
			break
	if target_id == "":
		UITheme.show_notification("No hull at T%d." % _test_hull_tier, Color.RED)
		return
	if target_id == sm.active_hull:
		UITheme.show_notification("Already in this hull.", Color(0.7, 0.7, 0.7))
		return
	# Mirror the safe parts of purchase_hull() — unequip back to inventory,
	# swap active_hull, init slot dict, recalc, full HP. Skip the cost/
	# research gates (test tool) and skip hull_constructed.emit (don't
	# credit missions for a debug swap).
	var hull_data = sm.hulls[target_id]
	sm.unequip_all()
	sm.active_hull = target_id
	sm.loadout = {}
	for i in range(hull_data["slots"].size()):
		sm.loadout[i] = null
	sm.ammo_loadout = {}
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	sm.inventory_updated.emit()
	var hull_name: String = hull_data.get("name", target_id)
	UITheme.show_notification("Constructed T%d: %s" % [_test_hull_tier, hull_name], Color(0.45, 1.0, 0.55))


func _on_test_stock_consumable_pressed() -> void:
	if not GameState.resources or _test_consumable_id == "":
		return
	GameState.resources.add_element(_test_consumable_id, 100)
	var display_name: String = ElementDB.get_display_name(_test_consumable_id)
	UITheme.show_notification("+100 %s" % display_name, Color(0.45, 1.0, 0.55))


# Map the fitter's weapon base-suffix + module tier to the matching ammo id.
# Tier bands: T1-2 → ammo T1, T3-5 → T2, T6-8 → T3, T9-10 → T4. Matches the
# game's ammo progression so a fitted ship uses tier-appropriate rounds, not
# T1 rounds on T10 guns. is_ammo_compatible() matches by name prefix so
# "SlugT4" / "CellT4" / "MissileT4" all pass for their respective weapons.
func _ammo_for_weapon(base_suffix: String, module_tier: int) -> String:
	var at: int = 1
	if module_tier <= 2:
		at = 1
	elif module_tier <= 5:
		at = 2
	elif module_tier <= 8:
		at = 3
	else:
		at = 4
	match base_suffix:
		"kinetic":
			return "SlugT%d" % at
		"energy":
			return "CellT%d" % at
		"missile":
			return "MissileT%d" % at
	return ""


func _on_test_fit_pressed() -> void:
	var sm = GameState.shipyard_manager
	if not sm or not (sm.active_hull in sm.hulls):
		UITheme.show_notification("No active hull to fit.", Color.RED)
		return
	var hull = sm.hulls[sm.active_hull]
	var slots: Array = hull["slots"]
	var weapon_types: Array = ["kinetic", "energy", "missile"]
	var weapon_pick: int = 0
	var equipped: int = 0
	var missing: Array = []

	for i in range(slots.size()):
		var slot_type: String = slots[i]
		var base_id: String = ""
		var w_suffix: String = ""  # set only for weapon slots — used to grant matching ammo below
		match slot_type:
			"weapon":
				# 0=Mixed: rotate across types. 1/2/3 force one type for ALL
				# weapon slots so the player can isolate Phase A triangle cases.
				match _test_weapon_type:
					1: w_suffix = "kinetic"
					2: w_suffix = "energy"
					3: w_suffix = "missile"
					_:
						w_suffix = weapon_types[weapon_pick % 3]
						weapon_pick += 1
				base_id = "z%d_%s" % [_test_tier, w_suffix]
			"shield":
				base_id = "z%d_shield" % _test_tier
			"armor":
				base_id = "z%d_armor" % _test_tier
			"engine":
				base_id = "z%d_engine" % _test_tier
			"battery":
				base_id = "z%d_battery" % _test_tier
			"sensor":
				base_id = "z%d_sensor" % _test_tier
			_:
				continue

		if not (base_id in sm.modules):
			if not (base_id in missing):
				missing.append(base_id)
			continue

		# Same drop pipeline combat uses: Common returns the base id and
		# bumps inventory; Uncommon+ creates a customized roll with affixes.
		var module_id: String = sm.generate_module_drop(base_id, _test_rarity, _test_tier)
		if module_id == "":
			continue

		# Direct loadout write — bypasses can_equip_module's research gate.
		sm.loadout[i] = module_id
		equipped += 1

		# Weapons need ammo or they fire blanks. equip_module() normally
		# auto-assigns SlugT1/CellT1/missile defaults, but our direct
		# loadout write bypasses that path — without this, T10 weapons on
		# a fitted ship deal 0 damage. Tier-band the ammo to the module
		# tier so the test loadout feels real rather than handicapped.
		if w_suffix != "":
			var ammo_id: String = _ammo_for_weapon(w_suffix, _test_tier)
			if ammo_id != "":
				GameState.resources.add_element(ammo_id, 1000)
				sm.ammo_loadout[i] = ammo_id

	sm.recalc_stats()
	sm.inventory_updated.emit()

	var rarity_names: Array = ["Common", "Uncommon", "Rare", "Legendary", "Unique"]
	var wtype_names: Array = ["Mixed", "KIN", "NRG", "EXP"]
	var msg: String = "Fitted T%d %s (%s weapons) — %d slot(s)" % [
		_test_tier, rarity_names[_test_rarity], wtype_names[_test_weapon_type], equipped]
	if not missing.is_empty():
		msg += "  (missing bases: %s)" % ", ".join(missing)
	UITheme.show_notification(msg, Color(0.45, 1.0, 0.55))


# --------------------------------------------------------------------------
# Zone Unlocker (debug)
# --------------------------------------------------------------------------
# Unlocks zone_N_access research entries for free, cascading Z2..N so the
# dependency chain stays intact (modules / recipes / infrastructure tiers
# all check zone_N_access throughout the codebase — skipping intermediate
# tiers would leave dead gates).
func _build_zone_unlocker(body: VBoxContainer) -> void:
	var title := Label.new()
	title.text = tr("Zone Unlock (debug)")
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.66, 0.7, 0.8))
	body.add_child(title)

	var hint := Label.new()
	hint.text = tr("Free-unlock zone_N_access research. Cascades Z2 → chosen tier so prerequisite chains stay intact.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.55, 0.58, 0.65))
	body.add_child(hint)

	var zone_opts: Array = []
	for z in range(2, 11):
		zone_opts.append(["Z%d" % z, z])
	_add_choice_row(body, "Up To Zone",
		zone_opts,
		func(): return _test_zone_tier,
		func(v): _set_test_zone_tier(v))

	var btn := _primary_button("UNLOCK ZONE", FRAME_CAT)
	btn.custom_minimum_size = Vector2(0, 38)
	btn.pressed.connect(_on_test_unlock_zone_pressed)
	body.add_child(btn)


func _set_test_zone_tier(v) -> void:
	_test_zone_tier = int(v)
	_refresh_all()


func _on_test_unlock_zone_pressed() -> void:
	var rm = GameState.research_manager
	if not rm:
		UITheme.show_notification("Research manager unavailable.", Color.RED)
		return
	# Mirror the safe parts of unlock_tech(): append + emit. Skip cost +
	# can_unlock prereq checks (test-tool intent). Cascade Z2..N so any
	# dependent gates between current state and the target tier light up.
	var newly: Array = []
	for t in range(2, _test_zone_tier + 1):
		var tech_id: String = "zone_%d_access" % t
		if not rm.is_tech_unlocked(tech_id):
			rm.unlocked_techs.append(tech_id)
			rm.tech_unlocked.emit(tech_id)
			newly.append("Z%d" % t)
	if newly.is_empty():
		UITheme.show_notification("Z2 — Z%d already unlocked." % _test_zone_tier, Color(0.7, 0.7, 0.7))
	else:
		UITheme.show_notification("Unlocked: %s" % ", ".join(newly), Color(0.45, 1.0, 0.55))


# --------------------------------------------------------------------------
# Skill + Research (debug)
# --------------------------------------------------------------------------
# Set Gathering/Processing to any level (or max both), and free-unlock every
# research node — so level-gated actions/recipes and research-gated content can
# be reached without the grind. Skill level is set by writing the XP threshold
# and re-deriving level via Skill.check_level_up (climbs up OR down from 1).
func _build_skill_research_debug(body: VBoxContainer) -> void:
	var title := Label.new()
	title.text = tr("Skill + Research (debug)")
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.66, 0.7, 0.8))
	body.add_child(title)

	var hint := Label.new()
	hint.text = tr("Set a skill to any level, max both skills, or unlock every research node. For testing level/research-gated actions, recipes, and content.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.55, 0.58, 0.65))
	body.add_child(hint)

	_add_choice_row(body, "Skill",
		[["Gathering", 0], ["Processing", 1]],
		func(): return _dbg_skill_idx,
		func(v): _dbg_skill_idx = int(v))

	_add_choice_row(body, "Level",
		[["1", 1], ["10", 10], ["25", 25], ["50", 50], ["75", 75], ["99", 99], ["100", 100]],
		func(): return _dbg_skill_level,
		func(v): _dbg_skill_level = int(v))

	var set_btn := _primary_button("SET SKILL LEVEL", FRAME_CAT)
	set_btn.custom_minimum_size = Vector2(0, 38)
	set_btn.pressed.connect(_on_dbg_set_skill_pressed)
	body.add_child(set_btn)

	var max_btn := _primary_button("MAX ALL SKILLS", FRAME_CAT)
	max_btn.custom_minimum_size = Vector2(0, 38)
	max_btn.pressed.connect(_on_dbg_max_skills_pressed)
	body.add_child(max_btn)

	var res_btn := _primary_button("UNLOCK ALL RESEARCH", DANGER_CAT)
	res_btn.custom_minimum_size = Vector2(0, 38)
	res_btn.pressed.connect(_on_dbg_unlock_all_research_pressed)
	body.add_child(res_btn)


func _dbg_set_skill_level(sk, target: int) -> void:
	if sk == null:
		return
	sk.xp = float(sk.get_xp_for_level(int(clamp(target, 1, sk.max_level))))
	sk.level = 1
	# v145: silent — otherwise "set level 100" fires ~100 level-up toasts.
	sk.rebuild_level_silently()


func _on_dbg_set_skill_pressed() -> void:
	var sk = GameState.gathering_manager if _dbg_skill_idx == 0 else GameState.processing_manager
	if sk == null:
		UITheme.show_notification("Skill manager unavailable.", Color.RED)
		return
	_dbg_set_skill_level(sk, _dbg_skill_level)
	var nm := "Gathering" if _dbg_skill_idx == 0 else "Processing"
	UITheme.show_notification("%s set to level %d." % [nm, sk.get_level()], Color(0.45, 1.0, 0.55))


func _on_dbg_max_skills_pressed() -> void:
	for sk in [GameState.gathering_manager, GameState.processing_manager]:
		_dbg_set_skill_level(sk, 100)
	UITheme.show_notification("Gathering + Processing maxed (100).", Color(0.45, 1.0, 0.55))


func _on_dbg_unlock_all_research_pressed() -> void:
	var rm = GameState.research_manager
	if rm == null:
		UITheme.show_notification("Research manager unavailable.", Color.RED)
		return
	var n := 0
	for tid in rm.tech_tree.keys():
		if not rm.is_tech_unlocked(tid):
			rm.unlocked_techs.append(tid)
			rm.tech_unlocked.emit(tid)
			n += 1
	UITheme.show_notification("Unlocked %d research node(s)." % n, Color(0.45, 1.0, 0.55))


# --------------------------------------------------------------------------
# Mission Control (debug)
# --------------------------------------------------------------------------
# Reveal / force-complete any mission by id, sweep all active missions (fast-
# forward the chain), or reset the whole board. Force-complete sets qty→target,
# marks completed, then claim_reward() grants the reward + auto-activates the
# next mission in the chain — so arcs (hack cards, cryo, warp) can be tested
# without playing through their prerequisites.
func _build_mission_debug(body: VBoxContainer) -> void:
	var title := Label.new()
	title.text = tr("Mission Control (debug)")
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.66, 0.7, 0.8))
	body.add_child(title)

	var hint := Label.new()
	hint.text = tr("Reveal / force-complete a mission by id, sweep all active, or reset the chain. Arc starters: goal_hack_1, goal_cryo_1, goal_001.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.55, 0.58, 0.65))
	body.add_child(hint)

	_dbg_mission_edit = LineEdit.new()
	_dbg_mission_edit.placeholder_text = tr("mission id (e.g. goal_hack_1)")
	_dbg_mission_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_dbg_mission_edit)

	var reveal_btn := _primary_button("REVEAL", FRAME_CAT)
	reveal_btn.custom_minimum_size = Vector2(0, 38)
	reveal_btn.pressed.connect(_on_dbg_mission_reveal_pressed)
	body.add_child(reveal_btn)

	var done_btn := _primary_button("COMPLETE + CLAIM", FRAME_CAT)
	done_btn.custom_minimum_size = Vector2(0, 38)
	done_btn.pressed.connect(_on_dbg_mission_complete_pressed)
	body.add_child(done_btn)

	var sweep_btn := _primary_button("COMPLETE ALL ACTIVE", FRAME_CAT)
	sweep_btn.custom_minimum_size = Vector2(0, 38)
	sweep_btn.pressed.connect(_on_dbg_mission_sweep_pressed)
	body.add_child(sweep_btn)

	var reset_btn := _primary_button("RESET ALL MISSIONS", DANGER_CAT)
	reset_btn.custom_minimum_size = Vector2(0, 38)
	reset_btn.pressed.connect(_on_dbg_mission_reset_pressed)
	body.add_child(reset_btn)


func _dbg_reveal_mission(mm, mid: String) -> void:
	var m = mm.missions[mid]
	m["active"] = true
	if not mid in mm.active_missions:
		mm.active_missions.append(mid)


func _dbg_force_complete(mm, mid: String) -> void:
	var m = mm.missions[mid]
	m["current_qty"] = m["target_qty"]
	m["completed"] = true


func _on_dbg_mission_reveal_pressed() -> void:
	var mm = GameState.mission_manager
	var mid := _dbg_mission_edit.text.strip_edges()
	if mm == null or not mid in mm.missions:
		UITheme.show_notification("No mission '%s'." % mid, Color.RED)
		return
	_dbg_reveal_mission(mm, mid)
	mm.mission_updated.emit()
	UITheme.show_notification("Revealed %s." % mid, Color(0.45, 1.0, 0.55))


func _on_dbg_mission_complete_pressed() -> void:
	var mm = GameState.mission_manager
	var mid := _dbg_mission_edit.text.strip_edges()
	if mm == null or not mid in mm.missions:
		UITheme.show_notification("No mission '%s'." % mid, Color.RED)
		return
	_dbg_reveal_mission(mm, mid)      # claim requires it be active
	_dbg_force_complete(mm, mid)
	mm.claim_reward(mid)              # grants reward + activates next in chain
	mm.mission_updated.emit()
	UITheme.show_notification("Completed + claimed %s." % mid, Color(0.45, 1.0, 0.55))


func _on_dbg_mission_sweep_pressed() -> void:
	var mm = GameState.mission_manager
	if mm == null:
		return
	var ids: Array = mm.active_missions.duplicate()   # snapshot; claim mutates the list
	var n := 0
	for mid in ids:
		_dbg_force_complete(mm, mid)
		if mm.claim_reward(mid):
			n += 1
	mm.mission_updated.emit()
	UITheme.show_notification("Completed %d active mission(s)." % n, Color(0.45, 1.0, 0.55))


func _on_dbg_mission_reset_pressed() -> void:
	var mm = GameState.mission_manager
	if mm == null:
		return
	mm.init_missions()
	mm.connect_signals()
	mm.mission_updated.emit()
	UITheme.show_notification("All missions reset to start.", Color(1.0, 0.7, 0.3))


# --------------------------------------------------------------------------
# Overclock / Efficiency (debug) — v130
# --------------------------------------------------------------------------
# Test the Boost-Card overclock + the nerfed Efficiency ladder without the
# lvl-45 craft grind: grant cards, set the EXACT efficiency tier (x2/3/4/5/10),
# and bulk-grant building counts to exercise the OC clamp + DR interplay.
func _build_overclock_debug(body: VBoxContainer) -> void:
	var title := Label.new()
	title.text = tr("Overclock / Efficiency (debug)")
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.66, 0.7, 0.8))
	body.add_child(title)

	var hint := Label.new()
	hint.text = tr("Grant Boost Cards, set the exact Efficiency research tier (x2/x3/x4/x5/x10), or +10 every owned building for overclock-cap testing.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.55, 0.58, 0.65))
	body.add_child(hint)

	var cards_btn := _primary_button("+5 BOOST CARDS", FRAME_CAT)
	cards_btn.custom_minimum_size = Vector2(0, 38)
	cards_btn.pressed.connect(_on_dbg_grant_boost_cards_pressed)
	body.add_child(cards_btn)

	_add_choice_row(body, "Efficiency Tier",
		[["None", 0], ["I", 1], ["II", 2], ["III", 3], ["IV", 4], ["V", 5]],
		func(): return _dbg_eff_tier,
		func(v): _dbg_eff_tier = int(v))

	var tier_btn := _primary_button("SET EFFICIENCY TIER", FRAME_CAT)
	tier_btn.custom_minimum_size = Vector2(0, 38)
	tier_btn.pressed.connect(_on_dbg_set_eff_tier_pressed)
	body.add_child(tier_btn)

	var bld_btn := _primary_button("+10 TO ALL OWNED BUILDINGS", FRAME_CAT)
	bld_btn.custom_minimum_size = Vector2(0, 38)
	bld_btn.pressed.connect(_on_dbg_bulk_buildings_pressed)
	body.add_child(bld_btn)


func _on_dbg_grant_boost_cards_pressed() -> void:
	if not GameState.resources:
		return
	GameState.resources.add_element("BoostCard", 5)
	UITheme.show_notification("+5 Boost Cards. Open Infrastructure to install them.", Color(1.0, 0.76, 0.28))


func _on_dbg_set_eff_tier_pressed() -> void:
	var rm = GameState.research_manager
	if rm == null:
		return
	# Set unlocked_techs to EXACTLY this tier: strip all efficiency nodes, then
	# re-add 1..N (the ladder is highest-tier-wins, so intermediates matter for UI).
	for t in ["efficiency_1", "efficiency_2", "efficiency_3", "efficiency_4", "efficiency_5"]:
		rm.unlocked_techs.erase(t)
	for i in range(1, _dbg_eff_tier + 1):
		rm.unlocked_techs.append("efficiency_%d" % i)
	UITheme.show_notification("Efficiency tier %d -> x%.0f output." % [_dbg_eff_tier, rm.get_efficiency_multiplier()], Color(0.45, 1.0, 0.55))


func _on_dbg_bulk_buildings_pressed() -> void:
	var im = GameState.infrastructure_manager
	if im == null:
		return
	var bumped := 0
	for bid in im.buildings.keys():
		if int(im.buildings[bid]) > 0:
			im.buildings[bid] = int(im.buildings[bid]) + 10
			bumped += 1
	if bumped == 0:
		UITheme.show_notification("No owned buildings — build at least one first.", Color(1.0, 0.7, 0.3))
		return
	im.activity_occurred.emit()
	UITheme.show_notification("+10 to %d building type(s). (Direct grant — no mission credit.)" % bumped, Color(0.45, 1.0, 0.55))


# --------------------------------------------------------------------------
# Material Granter (debug)
# --------------------------------------------------------------------------
# Free-text symbol + amount → directly into resources. Lets the player
# stock arbitrary materials (ores, refined metals, boss cores, reclaimed
# components, ammo tiers, anything) without grinding the chain. A dropdown
# would need 150+ entries — typing the symbol is faster when you already
# know what you want, which is the entire premise of a debug tool.
func _build_material_granter(body: VBoxContainer) -> void:
	var title := Label.new()
	title.text = tr("Material Grant (debug)")
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.66, 0.7, 0.8))
	body.add_child(title)

	var hint := Label.new()
	hint.text = tr("Type to filter by name or symbol, pick from the list (shows friendly names), set an amount. Adds straight to inventory.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.55, 0.58, 0.65))
	body.add_child(hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)

	var s_lbl := Label.new()
	s_lbl.text = tr("Material")
	s_lbl.add_theme_font_size_override("font_size", 11)
	s_lbl.add_theme_color_override("font_color", Color(0.62, 0.66, 0.76))
	row.add_child(s_lbl)

	_grant_symbol_edit = LineEdit.new()
	_grant_symbol_edit.placeholder_text = tr("type to filter (e.g. Navigation Data)")
	_grant_symbol_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grant_symbol_edit.custom_minimum_size = Vector2(120, 0)
	_grant_symbol_edit.text_changed.connect(_on_grant_filter_changed)
	_grant_symbol_edit.focus_entered.connect(func(): _on_grant_filter_changed(_grant_symbol_edit.text))
	row.add_child(_grant_symbol_edit)

	var a_lbl := Label.new()
	a_lbl.text = tr("Amount")
	a_lbl.add_theme_font_size_override("font_size", 11)
	a_lbl.add_theme_color_override("font_color", Color(0.62, 0.66, 0.76))
	row.add_child(a_lbl)

	_grant_amount_edit = LineEdit.new()
	_grant_amount_edit.placeholder_text = "1000"
	_grant_amount_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grant_amount_edit.custom_minimum_size = Vector2(100, 0)
	row.add_child(_grant_amount_edit)

	# Filterable suggestion list — shows "Friendly Name (SYMBOL)"; click to pick.
	_grant_symbol_list = ItemList.new()
	_grant_symbol_list.custom_minimum_size = Vector2(0, 160)
	_grant_symbol_list.visible = false
	_grant_symbol_list.item_selected.connect(_on_grant_symbol_picked)
	body.add_child(_grant_symbol_list)

	var btn := _primary_button("GRANT MATERIAL", FRAME_CAT)
	btn.custom_minimum_size = Vector2(0, 38)
	btn.pressed.connect(_on_test_grant_material_pressed)
	body.add_child(btn)

# Rebuild the suggestion list from ELEMENT_NAMES, filtered by `txt` (matches
# friendly name OR symbol, case-insensitive). Sorted by friendly name.
func _on_grant_filter_changed(txt: String) -> void:
	if not _grant_symbol_list:
		return
	# Typing invalidates any prior dropdown selection until re-picked/resolved.
	_grant_selected_symbol = ""
	_grant_symbol_list.clear()
	_grant_symbol_syms.clear()
	var needle := txt.strip_edges().to_lower()
	var rows: Array = []  # [display, symbol]
	for sym in ElementDB.ELEMENT_NAMES:
		var dn: String = ElementDB.ELEMENT_NAMES[sym]
		if needle == "" or needle in dn.to_lower() or needle in String(sym).to_lower():
			rows.append([dn, String(sym)])
	rows.sort_custom(func(a, b): return a[0].naturalnocasecmp_to(b[0]) < 0)
	var cap := mini(rows.size(), 200)
	for i in range(cap):
		_grant_symbol_list.add_item("%s  (%s)" % [rows[i][0], rows[i][1]])
		_grant_symbol_syms.append(rows[i][1])
	_grant_symbol_list.visible = _grant_symbol_syms.size() > 0

func _on_grant_symbol_picked(idx: int) -> void:
	if idx < 0 or idx >= _grant_symbol_syms.size():
		return
	_grant_selected_symbol = _grant_symbol_syms[idx]
	# Show the friendly name in the field (the user asked to SEE the name).
	_grant_symbol_edit.text = ElementDB.get_display_name(_grant_selected_symbol)
	_grant_symbol_list.visible = false

# Resolve the grant target: a dropdown pick wins; otherwise treat the typed
# text as a raw symbol, or match it against a friendly name.
func _resolve_grant_symbol() -> String:
	var text := _grant_symbol_edit.text.strip_edges() if _grant_symbol_edit else ""
	if _grant_selected_symbol != "" and (text == ElementDB.get_display_name(_grant_selected_symbol) or text == _grant_selected_symbol):
		return _grant_selected_symbol
	if text == "":
		return ""
	if text in ElementDB.ELEMENT_NAMES:  # typed a raw symbol
		return text
	var low := text.to_lower()
	for sym in ElementDB.ELEMENT_NAMES:  # typed a friendly name
		if ElementDB.ELEMENT_NAMES[sym].to_lower() == low:
			return String(sym)
	return ""


func _on_test_grant_material_pressed() -> void:
	if not GameState.resources:
		UITheme.show_notification("Resources unavailable.", Color.RED)
		return
	var symbol: String = _resolve_grant_symbol()
	var amt_text: String = ""
	if _grant_amount_edit:
		amt_text = _grant_amount_edit.text.strip_edges()
	if symbol == "":
		UITheme.show_notification("Pick a material from the list (or type a valid symbol/name).", Color.RED)
		return
	if not amt_text.is_valid_int():
		UITheme.show_notification("Amount must be a whole number.", Color.RED)
		return
	var amt: int = amt_text.to_int()
	if amt <= 0:
		UITheme.show_notification("Amount must be greater than 0.", Color.RED)
		return
	GameState.resources.add_element(symbol, amt)
	if _grant_symbol_list:
		_grant_symbol_list.visible = false
	var dn: String = ElementDB.get_display_name(symbol)
	UITheme.show_notification("+%d %s" % [amt, dn], Color(0.45, 1.0, 0.55))


# v107: Warp Mastery Tree playtest helpers --------------------------------
# Pure debug. "+1M Liras" lets you do a NATURAL warp (lifetime_credits auto-
# increments inside add_currency, so the gain calc returns a real shard).
# "Force Warp" bypasses the gain check entirely — bumps total_warps + shards
# and emits the warped signal, with NO world reset, so you keep gear/XP/
# materials for rapid reveal testing.
func _build_warp_debug(body: VBoxContainer) -> void:
	var title := Label.new()
	title.text = tr("Warp Mastery Tree (debug)")
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.66, 0.7, 0.8))
	body.add_child(title)

	var hint := Label.new()
	hint.text = tr("'+1M Liras' lets you execute a natural warp (gain calc returns ~1 shard). 'Force Warp' bumps total_warps and grants 1 shard directly — NO world reset, so you keep gear/progress for rapid branch-reveal testing.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.55, 0.58, 0.65))
	body.add_child(hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)

	var liras_btn := _primary_button("+1M LIRAS", FRAME_CAT)
	liras_btn.custom_minimum_size = Vector2(0, 38)
	liras_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	liras_btn.pressed.connect(_on_test_grant_liras_pressed)
	row.add_child(liras_btn)

	var warp_btn := _primary_button("FORCE WARP +1 (no reset)", FRAME_CAT)
	warp_btn.custom_minimum_size = Vector2(0, 38)
	warp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warp_btn.pressed.connect(_on_test_force_warp_pressed)
	row.add_child(warp_btn)

	# Second row — reveal-flag reset for replaying the P0 fanfare test.
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	body.add_child(row2)

	var reset_btn := _primary_button("RESET REVEAL FLAG (replay fanfare)", FRAME_CAT)
	reset_btn.custom_minimum_size = Vector2(0, 38)
	reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_btn.pressed.connect(_on_test_reset_warp_reveal_pressed)
	row2.add_child(reset_btn)


func _build_offline_debug(body: VBoxContainer) -> void:
	var title := Label.new()
	title.text = tr("Offline Welcome (debug)")
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.66, 0.7, 0.8))
	body.add_child(title)

	var hint := Label.new()
	hint.text = tr("Replays the offline welcome-back telemetry with a sample 15h report (multiple activities + a long material list, so the scrollable cargo ledger is exercised).")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.55, 0.58, 0.65))
	body.add_child(hint)

	var btn := _primary_button("PREVIEW OFFLINE WELCOME", FRAME_CAT)
	btn.custom_minimum_size = Vector2(0, 38)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_on_test_offline_preview_pressed)
	body.add_child(btn)


func _on_test_offline_preview_pressed() -> void:
	var main_scene = get_tree().current_scene
	var modal = main_scene.get("offline_modal") if main_scene else null
	if modal and is_instance_valid(modal) and modal.has_method("debug_preview"):
		modal.debug_preview()
	else:
		UITheme.show_notification("Offline modal unavailable.", Color.RED)


func _on_test_grant_liras_pressed() -> void:
	if not GameState.resources:
		UITheme.show_notification("Resources unavailable.", Color.RED)
		return
	# add_currency("credits", X) auto-bumps lifetime_credits, which feeds the
	# warp gain calc. 1M is comfortably over the 500K first-warp threshold.
	GameState.resources.add_currency("credits", 1_000_000)
	UITheme.show_notification("+1,000,000 Liras (lifetime credits bumped — natural warp now available)", Color(0.45, 1.0, 0.55))


func _on_test_reset_warp_reveal_pressed() -> void:
	GameState.game_settings["warp_first_revealed"] = false
	# Also hide the Warp tab again so the reveal is visible/dramatic on next
	# threshold-cross. Backward-compat path would re-flip it if total_warps>0,
	# so this only really "hides" the tab for never-warped saves.
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("_update_sidebar_styling"):
		main_scene._update_sidebar_styling()
	UITheme.show_notification(
		"[DEBUG] Reveal flag cleared — click '+1M LIRAS' to re-trigger the fanfare via the natural path.",
		Color(0.7, 0.6, 1.0)
	)


func _on_test_force_warp_pressed() -> void:
	if not GameState.warp_manager:
		UITheme.show_notification("Warp manager unavailable.", Color.RED)
		return
	var wm = GameState.warp_manager
	# v110: Warp tab now reveals on Zone 6 research; force the reveal flag
	# directly so this debug button puts the player into the testable state
	# regardless of research progress.
	GameState.game_settings["warp_first_revealed"] = true
	wm.total_warps += 1
	wm.warp_shards += 1.0
	# v111: mirror execute_warp's Cryo unlock — grant the starter pistol + flag.
	GameState.game_settings["cryo_unlocked"] = true
	var sm = GameState.shipyard_manager
	if sm and sm.module_inventory.get("cryo_lance", 0) <= 0:
		sm.grant_module("cryo_lance")  # v113: debug grants a USABLE Cryo weapon (real warp grants none)
	wm.warped.emit(1)   # repaints Warp page + reveals branch if threshold crossed
	# Sidebar visibility only re-evaluates on page-switch, so force a refresh
	# now — otherwise the newly-unlocked Warp tab won't appear in the nav
	# until the user clicks another tab first.
	var main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("_update_sidebar_styling"):
		main_scene._update_sidebar_styling()
	UITheme.show_notification("[DEBUG] Force Warp — total_warps=%d, +1 shard, warp_drive unlocked (no reset)" % wm.total_warps, Color(0.7, 0.6, 1.0))


# --------------------------------------------------------------------------
# Builders
# --------------------------------------------------------------------------
func _section(title: String, category: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_FILL
	_column.add_child(panel)

	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 20)
	mc.add_theme_constant_override("margin_right", 20)
	mc.add_theme_constant_override("margin_top", 16)
	mc.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(mc)

	# Style + chrome last, so the ornament overlay stays the top sibling
	# (paints above the section content, matching the gameplay-card pattern).
	UITheme.apply_card_style(panel, category)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 11)
	mc.add_child(vb)

	var t := Label.new()
	t.text = title.to_upper()
	t.add_theme_font_size_override("font_size", 15)
	t.add_theme_color_override("font_color", Color.WHITE)
	vb.add_child(t)

	var rule := ColorRect.new()
	rule.color = UITheme.CATEGORY_COLORS.get(category, Color(0.216, 0.788, 0.690))
	rule.color.a = 0.30
	rule.custom_minimum_size = Vector2(0, 2)
	vb.add_child(rule)

	return vb


func _primary_button(text: String, category: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_premium_button_style(b, category)
	b.add_theme_font_size_override("font_size", 15)
	return b


# label + a full-width segmented selector. `get_cur` returns the active value,
# `on_pick` is called with the chosen value. Highlight is driven by _refresh_all.
func _add_choice_row(parent: VBoxContainer, label_text: String,
		opts: Array, get_cur: Callable, on_pick: Callable) -> void:
	# v137: segmented pill — label left, options as segments inside a recessed track;
	# the active segment fills teal. One control for On/Off and multi-choice settings.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.72, 0.83, 0.80))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.039, 0.086, 0.078)
	track.set_border_width_all(1)
	track.border_color = Color(0.141, 0.251, 0.231)
	track.set_corner_radius_all(8)
	track.content_margin_left = 3
	track.content_margin_right = 3
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", track)
	row.add_child(pill)
	var seg := HBoxContainer.new()
	seg.add_theme_constant_override("separation", 3)
	pill.add_child(seg)

	var btns: Array = []
	for o in opts:
		var b := Button.new()
		b.text = str(o[0])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(50, 30)
		b.add_theme_font_size_override("font_size", 13)
		var val = o[1]
		b.pressed.connect(func():
			on_pick.call(val)
			_refresh_all())
		seg.add_child(b)
		btns.append([b, val])
		_style_segment(b, val == get_cur.call())

	_refreshers.append(func():
		var cur = get_cur.call()
		for pair in btns:
			_style_segment(pair[0], pair[1] == cur))

func _style_segment(b: Button, active: bool) -> void:
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(5)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	if active:
		box.bg_color = Color(0.216, 0.788, 0.690)   # teal fill
		b.add_theme_stylebox_override("normal", box)
		b.add_theme_stylebox_override("hover", box)
		b.add_theme_stylebox_override("pressed", box)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", Color(0.024, 0.137, 0.114))
		b.add_theme_color_override("font_hover_color", Color(0.024, 0.137, 0.114))
	else:
		box.bg_color = Color(0, 0, 0, 0)             # transparent
		var hov := box.duplicate()
		hov.bg_color = Color(0.216, 0.788, 0.690, 0.10)
		b.add_theme_stylebox_override("normal", box)
		b.add_theme_stylebox_override("hover", hov)
		b.add_theme_stylebox_override("pressed", hov)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", Color(0.43, 0.55, 0.53))
		b.add_theme_color_override("font_hover_color", Color(0.6, 0.72, 0.68))


func _refresh_all() -> void:
	for r in _refreshers:
		r.call()


# --------------------------------------------------------------------------
# Behaviour
# --------------------------------------------------------------------------
func _on_offline_combat_toggled(pressed: bool) -> void:
	# v125: first time it's switched ON, require explicit consent — offline combat
	# can destroy modules already worn to <=50% durability. Decline keeps it off;
	# the choice row repaints from the (unchanged) setting either way.
	if pressed and not GameState.game_settings.get("offline_combat_warned", false):
		UITheme.show_offline_combat_warning(
			Callable(self, "_on_offline_combat_consent"),
			Callable(self, "_on_offline_combat_decline"))
		return
	GameState.game_settings["offline_combat"] = pressed
	print("[Options] Offline Combat: ", pressed)


func _on_offline_combat_consent() -> void:
	GameState.game_settings["offline_combat"] = true
	GameState.game_settings["offline_combat_warned"] = true
	_refresh_all()


func _on_offline_combat_decline() -> void:
	GameState.game_settings["offline_combat"] = false
	_refresh_all()


func _on_cursor_size_pressed(px: int) -> void:
	GameState.game_settings["cursor_size"] = px
	CursorManager.apply_size(px)
	GameState.save_game()


func _on_card_frame_pressed(mode: int) -> void:
	GameState.game_settings["card_chrome"] = mode
	GameState.save_game()
	UITheme.chrome_changed.emit()  # live-repaint every visible card


func _set_game_speed(speed: float) -> void:
	Engine.time_scale = speed


func _on_reset_btn_pressed() -> void:
	# v112: themed modal (was the primitive Window ConfirmationDialog).
	var body := tr("Delete your save and restart from scratch?\n\n")
	body += tr("[color=#f06b6b]Everything is wiped — Liras, ships, research, Warp Mastery, prestige.[/color]\n\n")
	body += tr("[color=#ffb454][b]This cannot be undone.[/b][/color]")
	UITheme.show_confirm({
		"title": tr("Confirm Hard Reset"),
		"body": body,
		"confirm_text": tr("Yes, Delete Everything"),
		"cancel_text": tr("Cancel"),
		"accent": Color(0.95, 0.40, 0.40),   # alarm red frame
		"danger": true,
		"on_confirm": Callable(self, "_on_confirmation_dialog_confirmed"),
	})


func _on_confirmation_dialog_confirmed() -> void:
	GameState.hard_reset()
	get_tree().reload_current_scene()


func _on_replay_tutorials_pressed() -> void:
	GameState.game_settings["coach_seen"] = {}
	GameState.save_game()
	UITheme.show_notification("Tutorials reset — page tips will reappear as you visit each screen", Color(0.373, 0.878, 0.784))


# --------------------------------------------------------------------------
# Live readouts
# --------------------------------------------------------------------------
func _refresh_playtime() -> void:
	if _pt_label:
		_pt_label.text = tr("Total Play Time:  %s") % FormatUtils.format_playtime(GameState.total_playtime)


func _pct_line(d: Dictionary) -> String:
	var total := 0.0
	for k in d:
		total += float(d[k])
	if total <= 0.0:
		return "no data yet"
	var parts := []
	for k in d:
		var p := float(d[k]) / total * 100.0
		if p >= 0.5:
			parts.append("%s %d%%" % [k, int(round(p))])
	return ", ".join(parts) if not parts.is_empty() else "no data yet"


func _mat_line(ms: Dictionary) -> String:
	if ms.is_empty():
		return "no data yet"
	var parts := []
	for mat in ms:
		var c := float(ms[mat].get("combat", 0.0))
		var k := float(ms[mat].get("craft", 0.0))
		var tot := c + k
		if tot <= 0.0:
			continue
		parts.append("%s %d%% farmed" % [mat, int(round(c / tot * 100.0))])
	return ", ".join(parts) if not parts.is_empty() else "no data yet"


func _dmg_line(d: Dictionary) -> String:
	var k_raw := float(d.get("kinetic_raw", 0.0))
	var e_raw := float(d.get("energy_raw", 0.0))
	var x_raw := float(d.get("explosive_raw", 0.0))
	var tot := k_raw + e_raw + x_raw
	if tot <= 0.0:
		return "no data yet"
	var parts := []
	if k_raw > 0.0:
		parts.append("KIN %d%% (×%.2f)" % [int(round(k_raw / tot * 100.0)), float(d.get("kinetic_done", 0.0)) / k_raw])
	if e_raw > 0.0:
		parts.append("NRG %d%% (×%.2f)" % [int(round(e_raw / tot * 100.0)), float(d.get("energy_done", 0.0)) / e_raw])
	if x_raw > 0.0:
		parts.append("EXP %d%% (×%.2f)" % [int(round(x_raw / tot * 100.0)), float(d.get("explosive_done", 0.0)) / x_raw])
	return ", ".join(parts)

func _refresh_telemetry() -> void:
	if not _tele_label:
		return
	var t = GameState.telemetry
	_tele_label.text = tr("Active slot — %s\nProduction — %s\nMaterials — %s\nDamage — %s") % [
		_pct_line(t["occupancy"]), _pct_line(t["production"]), _mat_line(t.get("mat_source", {})), _dmg_line(t.get("damage_type", {}))]


func _process(delta: float) -> void:
	if not visible:
		return
	_pt_refresh += delta
	if _pt_refresh >= 1.0:
		_pt_refresh = 0.0
		_refresh_playtime()
		_refresh_telemetry()


# Kept for external callers (e.g. page navigation) — re-sync selected states.
func update_ui() -> void:
	_refresh_all()
