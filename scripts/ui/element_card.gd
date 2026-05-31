extends PanelContainer

signal clicked(element_data)

var element_data
var amount

@onready var symbol_lbl = $MarginContainer/VBoxContainer/SymbolLabel
@onready var name_lbl = $MarginContainer/VBoxContainer/NameLabel
@onready var amt_lbl = $MarginContainer/VBoxContainer/AmountLabel

func _ready() -> void:
	# v111.16: match empty_slot.gd / module_card.gd grid-cell sizing so FILLED
	# and EMPTY inventory cells are identical. Previously element cards were a
	# fixed 108px SHRINK box while empty slots were 100px EXPAND_FILL + square,
	# so filled and empty cells never matched. Expand to share the column width,
	# fill the row height, and keep square.
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_FILL
	if not resized.is_connected(_keep_square):
		resized.connect(_keep_square)

# Mirror of empty_slot._keep_square / module_card._keep_square: when the grid
# stretches us wider than our min, bump min height to match so the cell renders
# as a square. The guard prevents a layout loop (bumping min.y doesn't change
# size.x in a GridContainer).
func _keep_square() -> void:
	if size.x > custom_minimum_size.y:
		custom_minimum_size.y = size.x

func setup(p_data, p_amount):
	element_data = p_data
	amount = p_amount
	
	var display_name = ElementDB.get_display_name(element_data["symbol"])
	var symbol = element_data["symbol"]
	
	# Primary Text is always the Display Name
	symbol_lbl.text = display_name
	symbol_lbl.add_theme_font_size_override("font_size", 14) # Standardized size
	
	# Alignment and visibility
	$MarginContainer/VBoxContainer.alignment = BoxContainer.ALIGNMENT_CENTER
	
	# Only show symbol as secondary if it's short and different (e.g. Iron vs Fe)
	if symbol.to_lower() != display_name.to_lower() and symbol.length() <= 3:
		name_lbl.text = "(" + symbol + ")"
		name_lbl.visible = true
		name_lbl.custom_minimum_size.y = 20 # Smaller fixed size
	else:
		name_lbl.visible = false
		name_lbl.custom_minimum_size.y = 0
		
	symbol_lbl.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS.get("inventory", Color.WHITE))
	amt_lbl.text = FormatUtils.format_number(amount)
	
	UITheme.apply_card_style(self, "inventory")

func set_selected(is_selected: bool):
	if is_selected:
		modulate = Color(1.5, 1.5, 1.2) # Brighten and slight yellow tint
	else:
		modulate = Color(1, 1, 1)

func update_amount(new_amt):
	amount = new_amt
	amt_lbl.text = FormatUtils.format_number(amount)

func _gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(element_data)
