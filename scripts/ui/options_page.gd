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
var _grant_symbol_edit: LineEdit  # arbitrary-material granter — symbol input
var _grant_amount_edit: LineEdit  # arbitrary-material granter — amount input


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
	foot.text = "Horizon Idle · prototype build · changes save automatically"
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
	sub.text = "Save, gameplay and interface options."
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

	var save_btn := _primary_button("SAVE GAME", FRAME_CAT)
	save_btn.pressed.connect(_on_save_btn_pressed)
	body.add_child(save_btn)

	var warn := Label.new()
	warn.text = "Hard reset wipes your save permanently — this cannot be undone."
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

	var tele_title := Label.new()
	tele_title.text = "Balance Telemetry (debug)"
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
	title.text = "Ship Fitter (debug)"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.66, 0.7, 0.8))
	body.add_child(title)

	var hint := Label.new()
	hint.text = "Auto-fit the active hull at the chosen Tier + Rarity. Bypasses research gates. Overwrites current loadout."
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

	# Emergency unstick: heat-lock can strand a player mid-fight if their
	# build outpaces vent (T10 sustained > 1M heat ceiling). One-click reset.
	var cool_btn := _primary_button("COOL SHIP (clear heat)", FRAME_CAT)
	cool_btn.custom_minimum_size = Vector2(0, 38)
	cool_btn.pressed.connect(_on_test_cool_ship_pressed)
	body.add_child(cool_btn)


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
	# A stale heat lock from a prior fight would survive this swap and
	# strand the new hull — clear heat as part of the construct path too.
	_neutralize_heat()
	var hull_name: String = hull_data.get("name", target_id)
	UITheme.show_notification("Constructed T%d: %s" % [_test_hull_tier, hull_name], Color(0.45, 1.0, 0.55))


# Pull heat ceiling + vent rate up to 1e9 (effectively infinite for any
# single combat session) and clear current state. Used by FIT SHIP /
# CONSTRUCT HULL / the standalone COOL SHIP button. Heat math:
# combat_manager.gd:1396 adds ~2 + dmg/100 heat per shot; T10 sustained
# fire can produce ~7,000 heat/sec, so a 1M ceiling fills in ~140s of
# uninterrupted fire — not enough. 1e9 ceiling + 1e9 vent rate makes
# heat effectively a no-op for test sessions; the bar will hover at 0%.
func _neutralize_heat() -> void:
	var cm = GameState.combat_manager
	if not cm:
		return
	cm.player_heat = 0.0
	cm.overheat_lock = 0.0
	cm.player_max_heat = 1_000_000_000.0
	cm.player_vent_rate = 1_000_000_000.0
	if cm.has_signal("heat_changed"):
		cm.heat_changed.emit(cm.player_heat, cm.player_max_heat)


func _on_test_cool_ship_pressed() -> void:
	_neutralize_heat()
	UITheme.show_notification("Heat neutralized — weapons online.", Color(0.45, 1.0, 0.55))


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

	# Heat is a real game mechanic (each shot adds 2 + dmg/100 heat into a
	# 100-cap with an 8/s base vent — normally tuned by cooling research,
	# milestones, and heat-sync affixes). A debug-fit has none of those.
	# Neutralize: clear current + raise the ceiling AND vent rate far past
	# anything any session can produce (T10 sustained ≈ 7k heat/s for
	# 30+ min would exceed a 1M cap).
	_neutralize_heat()

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
	title.text = "Zone Unlock (debug)"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.66, 0.7, 0.8))
	body.add_child(title)

	var hint := Label.new()
	hint.text = "Free-unlock zone_N_access research. Cascades Z2 → chosen tier so prerequisite chains stay intact."
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
# Material Granter (debug)
# --------------------------------------------------------------------------
# Free-text symbol + amount → directly into resources. Lets the player
# stock arbitrary materials (ores, refined metals, boss cores, reclaimed
# components, ammo tiers, anything) without grinding the chain. A dropdown
# would need 150+ entries — typing the symbol is faster when you already
# know what you want, which is the entire premise of a debug tool.
func _build_material_granter(body: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "Material Grant (debug)"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.66, 0.7, 0.8))
	body.add_child(title)

	var hint := Label.new()
	hint.text = "Enter element symbol (Fe, Si, Z3_Core, ExoticMatter, SalvagedAlloy, …) and amount. Adds straight to inventory."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.55, 0.58, 0.65))
	body.add_child(hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)

	var s_lbl := Label.new()
	s_lbl.text = "Symbol"
	s_lbl.add_theme_font_size_override("font_size", 11)
	s_lbl.add_theme_color_override("font_color", Color(0.62, 0.66, 0.76))
	row.add_child(s_lbl)

	_grant_symbol_edit = LineEdit.new()
	_grant_symbol_edit.placeholder_text = "Fe"
	_grant_symbol_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grant_symbol_edit.custom_minimum_size = Vector2(120, 0)
	row.add_child(_grant_symbol_edit)

	var a_lbl := Label.new()
	a_lbl.text = "Amount"
	a_lbl.add_theme_font_size_override("font_size", 11)
	a_lbl.add_theme_color_override("font_color", Color(0.62, 0.66, 0.76))
	row.add_child(a_lbl)

	_grant_amount_edit = LineEdit.new()
	_grant_amount_edit.placeholder_text = "1000"
	_grant_amount_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grant_amount_edit.custom_minimum_size = Vector2(100, 0)
	row.add_child(_grant_amount_edit)

	var btn := _primary_button("GRANT MATERIAL", FRAME_CAT)
	btn.custom_minimum_size = Vector2(0, 38)
	btn.pressed.connect(_on_test_grant_material_pressed)
	body.add_child(btn)


func _on_test_grant_material_pressed() -> void:
	if not GameState.resources:
		UITheme.show_notification("Resources unavailable.", Color.RED)
		return
	var symbol: String = ""
	if _grant_symbol_edit:
		symbol = _grant_symbol_edit.text.strip_edges()
	var amt_text: String = ""
	if _grant_amount_edit:
		amt_text = _grant_amount_edit.text.strip_edges()
	if symbol == "":
		UITheme.show_notification("Enter a material symbol.", Color.RED)
		return
	if not amt_text.is_valid_int():
		UITheme.show_notification("Amount must be a whole number.", Color.RED)
		return
	var amt: int = amt_text.to_int()
	if amt <= 0:
		UITheme.show_notification("Amount must be greater than 0.", Color.RED)
		return
	GameState.resources.add_element(symbol, amt)
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
	title.text = "Warp Mastery Tree (debug)"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.66, 0.7, 0.8))
	body.add_child(title)

	var hint := Label.new()
	hint.text = "'+1M Liras' lets you execute a natural warp (gain calc returns ~1 shard). 'Force Warp' bumps total_warps and grants 1 shard directly — NO world reset, so you keep gear/progress for rapid branch-reveal testing."
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
	# The Warp sidebar tab is gated behind the "warp_drive" research tech, so a
	# Force Warp alone wouldn't reveal the page in the nav. Force-unlock that
	# tech here too so a single click puts the player into the testable state.
	var rm = GameState.research_manager
	if rm and not rm.is_tech_unlocked("warp_drive"):
		if not "warp_drive" in rm.unlocked_techs:
			rm.unlocked_techs.append("warp_drive")
			rm.tech_unlocked.emit("warp_drive")
	wm.total_warps += 1
	wm.warp_shards += 1.0
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
	rule.color = UITheme.CATEGORY_COLORS.get(category, Color(0.3, 0.6, 1.0))
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
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.66, 0.7, 0.8))
	parent.add_child(lbl)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var btns: Array = []
	for o in opts:
		var b := Button.new()
		b.text = str(o[0])
		b.custom_minimum_size = Vector2(0, 38)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.apply_premium_button_style(b, FRAME_CAT)
		b.add_theme_font_size_override("font_size", 14)
		var val = o[1]
		b.pressed.connect(func():
			on_pick.call(val)
			_refresh_all())
		row.add_child(b)
		btns.append([b, val])

	_refreshers.append(func():
		var cur = get_cur.call()
		for pair in btns:
			pair[0].modulate = SEL if pair[1] == cur else UNSEL)


func _refresh_all() -> void:
	for r in _refreshers:
		r.call()


# --------------------------------------------------------------------------
# Behaviour
# --------------------------------------------------------------------------
func _on_offline_combat_toggled(pressed: bool) -> void:
	GameState.game_settings["offline_combat"] = pressed
	print("[Options] Offline Combat: ", pressed)


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


func _on_save_btn_pressed() -> void:
	GameState.save_game()
	UITheme.show_notification("Game saved", Color(0.45, 0.9, 0.55))


func _on_reset_btn_pressed() -> void:
	$ConfirmationDialog.popup_centered()


func _on_confirmation_dialog_confirmed() -> void:
	GameState.hard_reset()
	get_tree().reload_current_scene()


func _on_replay_tutorials_pressed() -> void:
	GameState.game_settings["coach_seen"] = {}
	GameState.save_game()
	UITheme.show_notification("Tutorials reset — page tips will reappear as you visit each screen", Color(0.42, 0.84, 1.0))


# --------------------------------------------------------------------------
# Live readouts
# --------------------------------------------------------------------------
func _refresh_playtime() -> void:
	if _pt_label:
		_pt_label.text = "Total Play Time:  %s" % FormatUtils.format_playtime(GameState.total_playtime)


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
	_tele_label.text = "Active slot — %s\nProduction — %s\nMaterials — %s\nDamage — %s" % [
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
