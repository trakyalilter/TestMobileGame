extends Control

@onready var grid = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/ScrollContainer/GridContainer
@onready var credits_lbl = $HBoxContainer/RightPanel/VBoxContainer/CreditsLabel

# Details Panel
@onready var sel_name = $HBoxContainer/RightPanel/VBoxContainer/Details/NameLabel
@onready var sel_desc = $HBoxContainer/RightPanel/VBoxContainer/Details/ScrollContainer/DescLabel
@onready var price_lbl = $HBoxContainer/RightPanel/VBoxContainer/Details/PriceLabel
@onready var qty_spin = $HBoxContainer/RightPanel/VBoxContainer/Details/HBoxContainer/QtySpinBox
@onready var total_lbl = $HBoxContainer/RightPanel/VBoxContainer/Details/TotalLabel
@onready var sell_btn = $HBoxContainer/RightPanel/VBoxContainer/Details/SellBtn
@onready var sell_all_btn = $HBoxContainer/RightPanel/VBoxContainer/Details/SellAllBtn

# Filter Buttons
@onready var filter_all = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/CategoryFilter/AllBtn
@onready var filter_ores = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/CategoryFilter/OresBtn
@onready var filter_metals = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/CategoryFilter/MetalsBtn
@onready var filter_alloys = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/CategoryFilter/AlloysBtn
@onready var filter_comp = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/CategoryFilter/CompBtn
@onready var filter_other = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/CategoryFilter/OtherBtn

var card_scene = preload("res://scenes/ui/element_card.tscn")
var empty_slot_scene = preload("res://scenes/ui/empty_slot.tscn")
var cards = {} # {symbol: widget}
var selected_card = null
var min_slots = 48 # Increased from 40 for better grid
var selected_element = null
var price_val = 0
var current_filter = "all"

var storage_btn: Button = null

func _ready():
	_init_filter_buttons()
	
	# Premium Styling
	UITheme.apply_card_style($HBoxContainer/LeftPanel, "inventory")
	UITheme.apply_card_style($HBoxContainer/RightPanel, "inventory")
	UITheme.apply_premium_button_style(sell_btn, "inventory")
	UITheme.apply_premium_button_style(sell_all_btn, "inventory")
	
	# Inject Storage Upgrade Button (P65 Feature)
	storage_btn = Button.new()
	$HBoxContainer/LeftPanel/MarginContainer/VBoxContainer.add_child(storage_btn)
	# Move to top or bottom? Default is bottom.
	UITheme.apply_premium_button_style(storage_btn, "inventory")
	storage_btn.pressed.connect(_on_expand_storage_pressed)
	
	call_deferred("refresh_inventory")
	update_credits()
	GameState.resources.element_added.connect(_on_inventory_changed)
	GameState.resources.element_removed.connect(_on_inventory_changed)
	GameState.resources.currency_added.connect(func(t, a): update_credits())

func _on_expand_storage_pressed():
	if GameState.resources.upgrade_storage():
		# Play sound if available in UITheme, or just update
		update_credits()
		refresh_inventory()

# ... (Previous code)

func update_credits():
	# Update Capacity Display (Slots)
	var slots_used = GameState.resources.get_used_slots()
	var slots_max = GameState.resources.get_max_slots()
	
	if credits_lbl:
		credits_lbl.text = "Slots: %d / %d" % [slots_used, slots_max]
		if slots_used >= slots_max:
			credits_lbl.modulate = Color(1, 0.3, 0.3) # Red if full
		else:
			credits_lbl.modulate = Color.WHITE
			
	# Update Storage Button
	if storage_btn:
		var cost = GameState.resources.get_storage_upgrade_cost()
		storage_btn.text = "Expand Storage (+1 Slot) - %s Cr" % UITheme.format_num(cost)
		var current_cr = GameState.resources.get_currency("credits")
		if current_cr >= cost:
			storage_btn.disabled = false
			storage_btn.modulate = Color.WHITE
		else:
			storage_btn.disabled = true
			storage_btn.modulate = Color(0.7, 0.7, 0.7)

func _init_filter_buttons():
	var filter_btns = [filter_all, filter_ores, filter_metals, filter_alloys, filter_comp, filter_other]
	for b in filter_btns:
		UITheme.apply_sharp_button_style(b, "inventory")
		
	filter_all.pressed.connect(func(): set_filter("all"))
	filter_ores.pressed.connect(func(): set_filter("ores"))
	filter_metals.pressed.connect(func(): set_filter("metals")) # Combined basic/adv for simplicity
	filter_alloys.pressed.connect(func(): set_filter("alloys"))
	filter_comp.pressed.connect(func(): set_filter("components"))
	filter_other.pressed.connect(func(): set_filter("other"))

func set_filter(category):
	current_filter = category
	
	# Untoggle others
	filter_all.button_pressed = (category == "all")
	filter_ores.button_pressed = (category == "ores")
	filter_metals.button_pressed = (category == "metals")
	filter_alloys.button_pressed = (category == "alloys")
	filter_comp.button_pressed = (category == "components")
	filter_other.button_pressed = (category == "other")
	
	refresh_inventory()

func _on_inventory_changed(symbol, amount):
	if visible:
		# Update Capacity Display (just in case)
		update_credits()
		refresh_inventory()

func refresh_inventory():
	# Clear
	if not grid: return
	for child in grid.get_children():
		child.queue_free()
	cards.clear()
	
	var elements_db = GameState.elements_db
	var slot_count = 0
	
	# 1. Show Filtered Owned Items
	var owned_elements = GameState.resources.elements.keys()
	owned_elements.sort()
	for symbol in owned_elements:
		var amt = GameState.resources.elements.get(symbol, 0)
		
		if amt <= 0: continue
		
		# Find metadata in elements_db or create fallback
		var el_meta = null
		for e in elements_db:
			if e["symbol"] == symbol:
				el_meta = e
				break
		
		if el_meta == null:
			el_meta = {
				"symbol": symbol,
				"name": ElementDB.get_display_name(symbol),
				"description": "Material discovered in the field. Properties unknown.",
				"category": "other"
			}
		
		# Filter Check
		if current_filter != "all":
			var item_cat = ElementDB.get_category(symbol)
			if current_filter == "metals":
				if item_cat != "basic_metals" and item_cat != "advanced_metals" and item_cat != "rare_metals":
					continue
			elif current_filter == "other":
				# 'other' is a catch-all for anything not in the specific filters
				var specific_cats = ["ores", "basic_metals", "advanced_metals", "rare_metals", "alloys", "components"]
				if item_cat in specific_cats:
					continue
			elif item_cat != current_filter:
				continue
		
		var card = card_scene.instantiate()
		grid.add_child(card)
		card.setup(el_meta, amt)
		card.clicked.connect(_on_item_clicked)
		cards[symbol] = card
		slot_count += 1
			
	# 2. Fill remaining with Empty Slots
	var target_slots = max(min_slots, GameState.resources.get_max_slots())
	var needed = max(0, target_slots - slot_count)
	for i in range(needed):
		var empty = empty_slot_scene.instantiate()
		grid.add_child(empty)
			
	update_credits()
	
	# Re-apply selection highlight if it exists in the new list
	if selected_element:
		var symbol = selected_element["symbol"]
		if symbol in cards:
			selected_card = cards[symbol]
			selected_card.set_selected(true)
			
			# v65.2 Fix: Do NOT reset SpinBox if we are just refreshing existing selection
			# unless the amount changed and current value is higher than new max
			var amt = GameState.resources.get_element_amount(symbol)
			if amt > 0:
				qty_spin.max_value = amt
				if qty_spin.value > amt:
					qty_spin.value = amt
			else:
				selected_element = null
				clear_selection()
		else:
			# Item gone (sold or used up)
			selected_element = null
			selected_card = null
			clear_selection()
	else:
		selected_card = null

func _on_item_clicked(data):
	# Clear old highlight
	if selected_card:
		selected_card.set_selected(false)
	
	selected_element = data
	selected_card = cards[data["symbol"]]
	selected_card.set_selected(true)
	
	var amt = GameState.resources.get_element_amount(data["symbol"])
	update_selection_view(data, amt)

func update_selection_view(data, amount):
	sel_name.text = ElementDB.get_full_display(data["symbol"])
	
	var desc = data["description"]
	var info = GameState.resources.get_resource_info(data["symbol"])
	
	if not info["sources"].is_empty():
		desc += "\n\nSOURCES:"
		for src in info["sources"]:
			desc += "\n- %s: %s" % [src["name"], src.get("amount", "??")]
			
	if not info["uses"].is_empty():
		desc += "\n\nUSES:"
		for use in info["uses"]:
			desc += "\n- %s: %s" % [use["name"], str(use.get("amount", "??"))]
			
	sel_desc.text = desc
	
	price_val = data.get("base_value", 1) 
	price_lbl.text = "Unit Price: %s Cr" % UITheme.format_num(price_val)
	
	qty_spin.max_value = amount
	qty_spin.value = 1
	qty_spin.editable = true
	sell_btn.disabled = false
	sell_all_btn.disabled = false
	
	update_total_price(1)

func clear_selection():
	sel_name.text = "Select an Item"
	sel_desc.text = ""
	price_lbl.text = "Unit Price: -"
	qty_spin.editable = false
	sell_btn.disabled = true
	sell_all_btn.disabled = true
	total_lbl.text = "Total: 0 Cr"

func update_total_price(val):
	total_lbl.text = "Total: %s Cr" % UITheme.format_num(val * price_val)

func _on_qty_spin_box_value_changed(value):
	update_total_price(value)

func _on_sell_btn_pressed():
	if not selected_element: return
	
	# v65.1 Fix: Force SpinBox to commit current text to value before reading
	# This handles cases where user types a number but doesn't press Enter/Shift Focus before clicking
	if qty_spin.has_method("apply"):
		qty_spin.apply() # Some versions
	else:
		qty_spin.value = float(qty_spin.get_line_edit().text)
		
	var qty = int(qty_spin.value)
	perform_sale(selected_element["symbol"], qty)

func _on_sell_all_btn_pressed():
	if not selected_element: return
	var symbol = selected_element["symbol"]
	var qty = int(GameState.resources.get_element_amount(symbol))
	perform_sale(symbol, qty)

func perform_sale(symbol, qty):
	if qty <= 0:
		spawn_floating_text("Invalid Qty", Color.RED, sell_btn)
		return
		
	var total = qty * price_val
	if GameState.resources.remove_element(symbol, qty):
		GameState.resources.add_currency("credits", total)
		spawn_floating_text("+%s Cr" % UITheme.format_num(total), Color.GOLD, sell_btn)
		# refresh_inventory() # v65.1 Cleanup: Redundant, handled by signals
	else:
		spawn_floating_text("Sale Failed", Color.RED, sell_btn)

func spawn_floating_text(text, color, target_widget):
	# Using local float text logic similar to processing_page.gd
	var ft_scene = preload("res://scenes/ui/floating_text.tscn")
	var ft = ft_scene.instantiate()
	# Add to main UI so it's not clipped by panels
	get_tree().root.add_child(ft)
	
	var center = target_widget.global_position + target_widget.size / 2.0
	ft.setup(text, color, center)



func _process(delta):
	# Poll for inventory changes?
	# Or rely on refresh signals? 
	# For simplicity/MVP, refresh on show?
	pass
	
func _on_visibility_changed():
	if visible:
		refresh_inventory()
