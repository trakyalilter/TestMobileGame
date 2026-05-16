extends Control

# Loot Filter — rarity, slot type, and (new) weapon damage-type sub-filter.
# Restyled to the project's recessed/accent card language.

const ACCENT := Color(0.42, 0.84, 1.0)
const DMG_COLORS := {
	"kinetic": Color(1.0, 0.60, 0.24),
	"energy": Color(0.30, 0.82, 1.0),
	"explosive": Color(1.0, 0.55, 0.32),
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
	title.text = "LOOT FILTER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", ACCENT)
	vbox.add_child(title)

	var sub = Label.new()
	sub.text = "Only loot you keep is rolled — filtered drops are skipped entirely."
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
	btn_close.text = "CLOSE"
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

	_add_section_header("RARITY", rarity_column)
	for rarity_val in sm.Rarity.values():
		var rarity_name = sm.RARITY_LABELS.get(rarity_val, "Common")
		if rarity_name == "": rarity_name = "Common"
		var cb = CheckBox.new()
		cb.text = rarity_name
		cb.button_pressed = cm.loot_filter.get(rarity_val, true)
		cb.add_theme_color_override("font_color", sm.RARITY_COLORS.get(rarity_val, Color.WHITE))
		cb.toggled.connect(_on_rarity_toggled.bind(rarity_val))
		rarity_column.add_child(cb)

	_add_section_header("SLOT TYPE", type_column)
	for t in ["weapon", "armor", "shield", "engine", "battery", "sensor"]:
		var cb = CheckBox.new()
		cb.text = t.capitalize()
		cb.button_pressed = cm.loot_type_filter.get(t, true)
		cb.add_theme_color_override("font_color", Color(0.86, 0.88, 0.92))
		cb.toggled.connect(_on_type_toggled.bind(t))
		type_column.add_child(cb)

	_add_section_header("WEAPON TYPE", weapon_type_column)
	for wt in ["kinetic", "energy", "explosive"]:
		var cb = CheckBox.new()
		cb.text = wt.capitalize()
		cb.button_pressed = cm.loot_weapon_type_filter.get(wt, true)
		cb.add_theme_color_override("font_color", DMG_COLORS.get(wt, Color.WHITE))
		cb.toggled.connect(_on_weapon_type_toggled.bind(wt))
		weapon_type_column.add_child(cb)

	var note = Label.new()
	note.text = "Applies only to\nweapon drops."
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
	UITheme.show_notification("Rarity: " + GameState.shipyard_manager.RARITY_LABELS.get(rarity_val, "Common") + (" ON" if is_pressed else " OFF"), Color.AQUA)

func _on_type_toggled(is_pressed: bool, type_name: String):
	GameState.combat_manager.loot_type_filter[type_name] = is_pressed
	UITheme.show_notification("Type: " + type_name.capitalize() + (" ON" if is_pressed else " OFF"), Color.AQUA)

func _on_weapon_type_toggled(is_pressed: bool, wt: String):
	GameState.combat_manager.loot_weapon_type_filter[wt] = is_pressed
	UITheme.show_notification("Weapon: " + wt.capitalize() + (" ON" if is_pressed else " OFF"), DMG_COLORS.get(wt, Color.AQUA))

func _on_dim_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		close()

func close():
	queue_free()
