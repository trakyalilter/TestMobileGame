extends Control

# Loot Filter — rarity, slot type, and (new) weapon damage-type sub-filter.
# Restyled to the project's recessed/accent card language.

const ACCENT := Color(0.373, 0.878, 0.784)
const DMG_COLORS := {
	"kinetic": Color(1.0, 0.60, 0.24),
	"energy": Color(0.30, 0.82, 1.0),
	"explosive": Color(1.0, 0.55, 0.32),
	"cryo": Color(0.70, 0.95, 1.0),  # v109: pale ice
}

var panel: PanelContainer
var rarity_column: VBoxContainer
var type_column: VBoxContainer
var weapon_type_column: VBoxContainer
var btn_close: Button

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Dim backdrop so the modal reads as focused (and eats stray clicks).
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.11, 0.99)
	style.set_border_width_all(1)
	style.border_width_top = 3
	style.border_color = ACCENT
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 26
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = tr("LOOT FILTER")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", ACCENT)
	vbox.add_child(title)

	var sub = Label.new()
	sub.text = tr("Only loot you keep is rolled — filtered drops are skipped entirely.")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_color_override("font_color", Color(0.55, 0.58, 0.66))
	vbox.add_child(sub)

	vbox.add_child(_rule())

	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 22)
	vbox.add_child(hbox)

	rarity_column = _make_column(hbox)
	hbox.add_child(_vrule())
	type_column = _make_column(hbox)
	hbox.add_child(_vrule())
	weapon_type_column = _make_column(hbox)

	vbox.add_child(_rule())

	btn_close = Button.new()
	btn_close.text = tr("CLOSE")
	btn_close.custom_minimum_size = Vector2(0, 42)
	vbox.add_child(btn_close)
	UITheme.apply_premium_button_style(btn_close, "combat")
	btn_close.pressed.connect(close)
	dim.gui_input.connect(_on_dim_input)

	_build_filter_sections()

func _make_column(parent: Control) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.add_theme_constant_override("separation", 7)
	parent.add_child(c)
	return c

func _rule() -> HSeparator:
	var s := HSeparator.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.30)
	ss.content_margin_top = 1
	s.add_theme_stylebox_override("separator", ss)
	return s

func _vrule() -> VSeparator:
	var s := VSeparator.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(0.30, 0.34, 0.42, 0.45)
	s.add_theme_stylebox_override("separator", ss)
	return s

func _build_filter_sections():
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	if not sm or not cm: return

	# v137: filters are now teal toggle chips (was default CheckBox), each tinted by
	# its own meaning — rarity chips in their rarity colour, weapon chips in their
	# damage colour, slot chips in the panel accent. ON = accent fill + colour; OFF =
	# recessed + dim. See UITheme.make_toggle_chip.
	_add_section_header(tr("RARITY"), rarity_column)
	for rarity_val in sm.Rarity.values():
		var rarity_name = sm.RARITY_LABELS.get(rarity_val, "Common")
		if rarity_name == "": rarity_name = "Common"
		var chip = UITheme.make_toggle_chip(rarity_name, sm.RARITY_COLORS.get(rarity_val, Color.WHITE), cm.loot_filter.get(rarity_val, true))
		chip.toggled.connect(_on_rarity_toggled.bind(rarity_val))
		rarity_column.add_child(chip)

	_add_section_header(tr("SLOT TYPE"), type_column)
	for t in ["weapon", "armor", "shield", "engine", "battery", "sensor"]:
		var chip = UITheme.make_toggle_chip(t.capitalize(), ACCENT, cm.loot_type_filter.get(t, true))
		chip.toggled.connect(_on_type_toggled.bind(t))
		type_column.add_child(chip)

	_add_section_header(tr("WEAPON TYPE"), weapon_type_column)
	# v109: Cryo is the surprise first-Warp unlock — don't list it (spoiler)
	# until the player has actually unlocked it.
	var wtypes := ["kinetic", "energy", "explosive"]
	if GameState.game_settings.get("cryo_unlocked", false):
		wtypes.append("cryo")
	for wt in wtypes:
		var chip = UITheme.make_toggle_chip(wt.capitalize(), DMG_COLORS.get(wt, Color.WHITE), cm.loot_weapon_type_filter.get(wt, true))
		chip.toggled.connect(_on_weapon_type_toggled.bind(wt))
		weapon_type_column.add_child(chip)

	var note = Label.new()
	note.text = tr("Applies only to\nweapon drops.")
	note.add_theme_font_size_override("font_size", 9)
	note.add_theme_color_override("font_color", Color(0.5, 0.53, 0.6))
	weapon_type_column.add_child(note)

func _add_section_header(text: String, container: Control):
	var l = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", ACCENT)
	l.add_theme_font_size_override("font_size", 12)
	container.add_child(l)
	var u := HSeparator.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.22)
	u.add_theme_stylebox_override("separator", ss)
	container.add_child(u)

func _on_rarity_toggled(is_pressed: bool, rarity_val: int):
	GameState.combat_manager.loot_filter[rarity_val] = is_pressed
	UITheme.show_notification(tr("Rarity: %s %s") % [tr(GameState.shipyard_manager.RARITY_LABELS.get(rarity_val, "Common")), tr("ON") if is_pressed else tr("OFF")], Color.AQUA)

func _on_type_toggled(is_pressed: bool, type_name: String):
	GameState.combat_manager.loot_type_filter[type_name] = is_pressed
	UITheme.show_notification(tr("Type: %s %s") % [tr(type_name.capitalize()), tr("ON") if is_pressed else tr("OFF")], Color.AQUA)

func _on_weapon_type_toggled(is_pressed: bool, wt: String):
	GameState.combat_manager.loot_weapon_type_filter[wt] = is_pressed
	UITheme.show_notification(tr("Weapon: %s %s") % [tr(wt.capitalize()), tr("ON") if is_pressed else tr("OFF")], DMG_COLORS.get(wt, Color.AQUA))

func _on_dim_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		close()

func close():
	queue_free()
