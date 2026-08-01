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
var min_slots = 28
var selected_element = null
var price_val = 0
var current_filter = "all"

var storage_btn: Button = null

# v124: "Cargo Manifest" datasheet redesign of the right-hand Item-Details/Sell
# panel. Three bands inside Details: HERO (icon+name+meta, never scrolls),
# LEDGER (the only size_flags_v=3 child → the dossier scrolls, sell deck never
# gets pushed off-screen), SELL DECK (pinned bottom). All built in code so the
# four .tscn signal connections bind by reference and never need editing.
var hero_row: HBoxContainer = null
var hero_icon: TextureRect = null
var hero_text: VBoxContainer = null
var meta_lbl: RichTextLabel = null
var flavor_lbl: RichTextLabel = null
var minus_btn: Button = null
var plus_btn: Button = null
var max_btn: Button = null

func _ready():
	_init_filter_buttons()
	
	# Premium Styling. The big Storage / Item-Details containers keep the
	# styled background but NOT the CardChrome corner ornament — only the
	# individual item slot cards should carry the theme.
	UITheme.apply_card_style($HBoxContainer/LeftPanel, "inventory")
	UITheme.apply_card_style($HBoxContainer/RightPanel, "inventory")
	for _p in [$HBoxContainer/LeftPanel, $HBoxContainer/RightPanel]:
		var _c = _p.get_node_or_null("_CardChrome")
		if _c: _c.queue_free()
	UITheme.apply_premium_button_style(sell_btn, "inventory")
	# sell_all_btn is restyled to the quieter "sharp" secondary inside
	# _build_detail_panel — SELL is the dominant primary, SELL ALL the secondary.
	_style_details()
	_build_detail_panel()

	# Inject Storage Upgrade Button (P65 Feature)
	storage_btn = Button.new()
	$HBoxContainer/LeftPanel/MarginContainer/VBoxContainer.add_child(storage_btn)
	# Move to top or bottom? Default is bottom.
	UITheme.apply_premium_button_style(storage_btn, "inventory")
	storage_btn.pressed.connect(_on_expand_storage_pressed)
	
	# Inject Search Bar (User Request)
	_setup_search_bar()
	
	call_deferred("refresh_inventory")
	update_credits()
	GameState.resources.element_added.connect(_on_inventory_changed)
	GameState.resources.element_removed.connect(_on_inventory_changed)
	GameState.resources.currency_added.connect(func(t, a): update_credits())

var search_bar: LineEdit

func _setup_search_bar():
	search_bar = LineEdit.new()
	search_bar.placeholder_text = tr("Search...")
	
	# Use new UITheme method
	UITheme.apply_input_style(search_bar, "inventory")
	
	# Add to top of Left Panel
	var container = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer
	container.add_child(search_bar)
	container.move_child(search_bar, 0)
	
	search_bar.text_changed.connect(_on_search_text_changed)

func _on_search_text_changed(new_text):
	refresh_inventory()

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
		credits_lbl.text = tr("Slots: %d / %d") % [slots_used, slots_max]
		if slots_used >= slots_max:
			credits_lbl.modulate = UITheme.COLORS["negative"] # Red if full
		else:
			credits_lbl.modulate = UITheme.COLORS["text_main"]
			
	# Update Storage Button
	if storage_btn:
		var cost = GameState.resources.get_storage_upgrade_cost()
		storage_btn.text = tr("Expand Storage (+1 Slot) - %s Liras") % UITheme.format_num(cost)
		var current_cr = GameState.resources.get_currency("credits")
		if current_cr >= cost:
			storage_btn.disabled = false
			storage_btn.modulate = UITheme.COLORS["text_main"]
		else:
			storage_btn.disabled = true
			storage_btn.modulate = UITheme.COLORS["text_dim"]

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

func get_coach_anchor(key: String) -> Control:
	match key:
		"grid":
			return grid
		"storage":
			return storage_btn
	return null

func refresh_inventory():
	# Clear
	if not grid: return
	for child in grid.get_children():
		child.queue_free()
	cards.clear()
	
	var elements_db = GameState.elements_db
	var slot_count = 0
	var search_txt = search_bar.text.to_lower() if search_bar else ""
	
	# 1. Show Filtered Owned Items
	var owned_elements = GameState.resources.elements.keys()
	owned_elements.sort()
	for symbol in owned_elements:
		var amt = GameState.resources.elements.get(symbol, 0)

		if amt <= 0: continue
		# v147: consumables / matrix cores / hack cards are ARMORY stock — they are
		# equipped and applied from the Armory tabs, and listing them here as well
		# just duplicated them into the cargo hold they no longer occupy.
		if ElementDB.is_armory_item(symbol): continue

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
				"description": tr("Material discovered in the field. Properties unknown."),
				"category": "other"
			}
			
		# SEARCH FILTER
		if search_txt != "":
			if not (search_txt in el_meta["name"].to_lower() or search_txt in symbol.to_lower()):
				continue
		
		# Filter Check
		if current_filter != "all":
			var item_cat = ElementDB.get_category(symbol)
			if current_filter == "metals":
				if item_cat != "basic_metals" and item_cat != "advanced_metals" and item_cat != "rare_metals":
					continue
			elif current_filter == "other":
				# 'other' is a catch-all for anything not explicitly listed in the main filter buttons
				var specific_cats = ["ores", "basic_metals", "advanced_metals", "rare_metals", "alloys", "components"]
				if item_cat in specific_cats:
					continue
				# If we are here, it's a special item (like Boss Cores) and should be shown in 'Other'
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

# Styles the nodes that STAY plain Labels / separators. The dossier, price and
# total Labels are converted to RichTextLabels in _build_detail_panel and styled
# there (RTL has no horizontal_alignment / font_color in the Label sense), so they
# are intentionally NOT touched here. Colors route through UITheme tokens; the
# recess bg + separator are the allowed palette-exempt fixed values.
func _style_details() -> void:
	var gold: Color = UITheme.CATEGORY_COLORS.get("inventory", Color(1.0, 0.8, 0.2))
	var dim: Color = UITheme.COLORS["text_dim"]
	var base := "HBoxContainer/RightPanel/VBoxContainer"

	# Header: accent caption + slim slots sub-line.
	var hdr := get_node_or_null(base + "/Label")
	if hdr:
		hdr.add_theme_color_override("font_color", gold)
		hdr.add_theme_font_size_override("font_size", 13)
		hdr.uppercase = true
	var slots := get_node_or_null(base + "/CreditsLabel")
	if slots:
		slots.add_theme_color_override("font_color", dim)
		slots.add_theme_font_size_override("font_size", 10)

	# Item name — the hero line (stays a Label, reparented into the hero row).
	if sel_name:
		sel_name.add_theme_font_size_override("font_size", 20)
		sel_name.add_theme_color_override("font_color", gold)
		sel_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Sell block caption.
	var sell_hdr := get_node_or_null(base + "/Details/Label2")
	if sell_hdr:
		sell_hdr.add_theme_color_override("font_color", gold.lerp(dim, 0.4))
		sell_hdr.add_theme_font_size_override("font_size", 11)
		sell_hdr.uppercase = true
	var sep := get_node_or_null(base + "/Details/HSeparator")
	if sep:
		sep.modulate = Color(1, 1, 1, 0.12)


# One-time structural build of the datasheet panel. Runs in _ready AFTER
# _style_details. Converts the three text-dump Labels to RichTextLabels in place
# (preserving node names so nothing downstream breaks), builds the hero band +
# the quantity stepper, and pins the sell deck. No .tscn edits → the four signal
# [connection]s survive untouched.
func _build_detail_panel() -> void:
	var details := get_node_or_null("HBoxContainer/RightPanel/VBoxContainer/Details") as VBoxContainer
	if details == null:
		return

	# (a) Label → RichTextLabel for price / total (inline lira icon needs bbcode).
	price_lbl = _label_to_rtl(price_lbl, false)
	total_lbl = _label_to_rtl(total_lbl, false)
	price_lbl.add_theme_font_size_override("normal_font_size", 12)
	total_lbl.add_theme_font_size_override("normal_font_size", 15)

	# (b) HERO band — big tinted material icon + name + meta line.
	hero_row = HBoxContainer.new()
	hero_row.name = "HeroRow"
	hero_row.add_theme_constant_override("separation", 12)

	hero_icon = TextureRect.new()
	hero_icon.name = "HeroIcon"
	hero_icon.custom_minimum_size = Vector2(48, 48)
	hero_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hero_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_row.add_child(hero_icon)

	hero_text = VBoxContainer.new()
	hero_text.name = "HeroText"
	hero_text.add_theme_constant_override("separation", 2)
	hero_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hero_row.add_child(hero_text)

	# Reparent the existing NameLabel into the hero text column (keeps sel_name valid).
	if sel_name.get_parent():
		sel_name.get_parent().remove_child(sel_name)
	sel_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hero_text.add_child(sel_name)

	meta_lbl = RichTextLabel.new()
	meta_lbl.name = "MetaLabel"
	meta_lbl.bbcode_enabled = true
	meta_lbl.fit_content = true
	meta_lbl.scroll_active = false
	meta_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta_lbl.add_theme_font_size_override("normal_font_size", 11)
	# v137: the "View in Atlas" link (appended in update_selection_view) deep-links the
	# selected item to its full Atlas entry — sources/uses live there, not in this panel.
	meta_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	meta_lbl.meta_clicked.connect(func(meta): UITheme.request_atlas_from_meta(meta))
	hero_text.add_child(meta_lbl)

	flavor_lbl = RichTextLabel.new()
	flavor_lbl.name = "FlavorLabel"
	flavor_lbl.bbcode_enabled = true
	flavor_lbl.fit_content = true
	flavor_lbl.scroll_active = false
	flavor_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor_lbl.add_theme_font_size_override("normal_font_size", 11)

	details.add_child(hero_row)
	details.move_child(hero_row, 0)
	details.add_child(flavor_lbl)
	details.move_child(flavor_lbl, 1)

	# (c) Sources/uses reference data was removed — it belongs in the Atlas, not the
	# sell panel. Free the old dossier ScrollContainer and drop a flexible spacer in
	# its place so the identity stays at the top and the sell deck pins to the bottom.
	sel_desc = null
	var scroll := get_node_or_null("HBoxContainer/RightPanel/VBoxContainer/Details/ScrollContainer")
	var spacer_idx: int = 2
	if scroll:
		spacer_idx = scroll.get_index()
		scroll.get_parent().remove_child(scroll)
		scroll.queue_free()
	var spacer := Control.new()
	spacer.name = "DetailSpacer"
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(spacer)
	details.move_child(spacer, spacer_idx)

	# (d) Quantity stepper — wrap the (kept, value-model) SpinBox with −/+/MAX so the
	# existing value_changed wiring and clamp logic stay byte-for-byte intact.
	var qty_row := get_node_or_null("HBoxContainer/RightPanel/VBoxContainer/Details/HBoxContainer") as HBoxContainer
	if qty_row:
		qty_row.add_theme_constant_override("separation", 6)
		var qlabel := qty_row.get_node_or_null("Label")
		if qlabel:
			qty_row.remove_child(qlabel)
			qlabel.queue_free()

		qty_spin.alignment = HORIZONTAL_ALIGNMENT_CENTER
		qty_spin.custom_minimum_size = Vector2(64, 32)
		qty_spin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		UITheme.apply_input_style(qty_spin.get_line_edit(), "inventory")
		_hide_spinbox_arrows(qty_spin)

		minus_btn = Button.new()
		minus_btn.text = "−"   # U+2212 MINUS SIGN (pairs with +)
		minus_btn.custom_minimum_size = Vector2(34, 32)
		plus_btn = Button.new()
		plus_btn.text = "+"
		plus_btn.custom_minimum_size = Vector2(34, 32)
		max_btn = Button.new()
		max_btn.text = tr("MAX")
		max_btn.custom_minimum_size = Vector2(48, 32)
		for b in [minus_btn, plus_btn, max_btn]:
			b.focus_mode = Control.FOCUS_NONE
			qty_row.add_child(b)
			UITheme.apply_sharp_button_style(b, "inventory")
			# sharp style sets no resting font color → set it explicitly.
			b.add_theme_color_override("font_color", UITheme.COLORS["text_main"])
		minus_btn.add_theme_font_size_override("font_size", 18)
		plus_btn.add_theme_font_size_override("font_size", 18)

		# Final order: [ − ] [ readout ] [ + ] [ MAX ]
		qty_row.move_child(minus_btn, 0)
		qty_row.move_child(qty_spin, 1)
		qty_row.move_child(plus_btn, 2)
		qty_row.move_child(max_btn, 3)

		minus_btn.pressed.connect(_on_qty_minus)
		plus_btn.pressed.connect(_on_qty_plus)
		max_btn.pressed.connect(_on_qty_max)

	# (e) SELL ALL → quieter sharp secondary (SELL stays the premium primary).
	UITheme.apply_sharp_button_style(sell_all_btn, "inventory")
	sell_all_btn.add_theme_color_override("font_color", UITheme.COLORS["text_dim"])

	clear_selection()


# Replaces a Label with a RichTextLabel of the same name/index/parent and returns
# the new node. expand → fill the panel width (for the dossier wrap).
func _label_to_rtl(old: Label, expand: bool) -> RichTextLabel:
	var parent := old.get_parent()
	var idx := old.get_index()
	var rtl := RichTextLabel.new()
	rtl.name = old.name
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.custom_minimum_size = old.custom_minimum_size
	rtl.size_flags_vertical = old.size_flags_vertical
	if expand:
		rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		rtl.size_flags_horizontal = old.size_flags_horizontal
	parent.remove_child(old)
	old.queue_free()
	parent.add_child(rtl)
	parent.move_child(rtl, idx)
	return rtl


# SpinBox has no "hide arrows" property in this engine version — override the
# combined up/down icon with a 1×1 transparent texture so only our −/+/MAX show.
func _hide_spinbox_arrows(sb: SpinBox) -> void:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	sb.add_theme_icon_override("updown", tex)


# −/+/MAX drive qty_spin.value, which auto-emits value_changed →
# _on_qty_spin_box_value_changed → update_total_price (total + SELL label refresh).
func _on_qty_minus() -> void:
	qty_spin.value = max(qty_spin.min_value, qty_spin.value - 1)

func _on_qty_plus() -> void:
	qty_spin.value = min(qty_spin.max_value, qty_spin.value + 1)

func _on_qty_max() -> void:
	qty_spin.value = qty_spin.max_value


func update_selection_view(data, amount):
	var symbol: String = str(data["symbol"])
	sel_name.text = ElementDB.get_full_display(symbol)

	# Live palette tokens (read each time — COLORS is mutated by apply_palette).
	var dim_hex: String = UITheme.COLORS["text_dim"].to_html(false)
	var main_hex: String = UITheme.COLORS["text_main"].to_html(false)
	var warn_hex: String = UITheme.COLORS["warning"].to_html(false)

	# Hero icon — static cached Texture2D, tinted (white SVG). Hidden if absent.
	var tex: Texture2D = ElementDB.get_material_icon(symbol)
	if tex != null:
		hero_icon.texture = tex
		hero_icon.modulate = ElementDB.get_material_tint(symbol)
		hero_icon.visible = true
	else:
		hero_icon.visible = false

	# Meta line: prettified category • N held.
	var cat: String = ElementDB.get_category(symbol).replace("_", " ").to_upper()
	meta_lbl.text = tr("[color=#%s]%s[/color]   [color=#%s]•[/color]   [color=#%s][b]%s[/b] held[/color]   [color=#%s]•[/color]   [url=atlasmat:%s][color=#5FE0C8][u]View in Atlas[/u][/color][/url]") % [dim_hex, cat, dim_hex, main_hex, UITheme.format_num(amount), dim_hex, symbol]

	# Flavor — one-line dim italic blurb ([ escaped so a stray bracket isn't a tag).
	# Sources/uses reference data intentionally lives in the Atlas, not here.
	var flavor: String = str(data.get("description", "")).replace("[", "[lb]")
	flavor_lbl.text = tr("[i][color=#%s]%s[/color][/i]") % [dim_hex, flavor]

	# Unit price — gold value + inline lira icon.
	# v132: default 0, not 1 — items with no base_value (hack cards, zone alloys,
	# Boost Cards) were priced at 1 Lira, letting players destroy progression
	# items for pocket change. 0 matches get_element_value's semantics everywhere.
	price_val = data.get("base_value", 0)
	price_lbl.text = tr("[color=#%s]Unit Price[/color]   [color=#%s][b]%s[/b][/color] %s") % [dim_hex, warn_hex, UITheme.format_num(price_val), UITheme.LIRA_ICON_BB]

	qty_spin.max_value = amount
	qty_spin.value = 1
	qty_spin.editable = true
	sell_btn.disabled = false
	sell_all_btn.disabled = false
	sell_all_btn.text = tr("Sell entire stack")
	if minus_btn: minus_btn.disabled = false
	if plus_btn: plus_btn.disabled = false
	if max_btn: max_btn.disabled = false

	update_total_price(1)

func clear_selection():
	var dim_hex: String = UITheme.COLORS["text_dim"].to_html(false)
	sel_name.text = tr("Select an Item")
	if hero_icon: hero_icon.visible = false
	if meta_lbl: meta_lbl.text = ""
	if flavor_lbl: flavor_lbl.text = ""
	if price_lbl: price_lbl.text = tr("[color=#%s]Unit Price   —[/color]") % dim_hex
	qty_spin.editable = false
	sell_btn.disabled = true
	sell_all_btn.disabled = true
	if minus_btn: minus_btn.disabled = true
	if plus_btn: plus_btn.disabled = true
	if max_btn: max_btn.disabled = true
	if total_lbl: total_lbl.text = tr("[color=#%s]Total   0[/color] %s") % [dim_hex, UITheme.LIRA_ICON_BB]

func update_total_price(val):
	var dim_hex: String = UITheme.COLORS["text_dim"].to_html(false)
	var pos_hex: String = UITheme.COLORS["positive"].to_html(false)
	if total_lbl:
		total_lbl.text = tr("[color=#%s]Total[/color]   [color=#%s][b]%s[/b][/color] %s") % [dim_hex, pos_hex, UITheme.format_num(val * price_val), UITheme.LIRA_ICON_BB]
	# Live SELL-button caption mirrors the chosen quantity.
	if sell_btn:
		sell_btn.text = tr("SELL  ·  %s") % UITheme.format_num(int(val))

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
		UITheme.show_notification(tr("Invalid Qty"), Color.RED)
		return
	# v132: never destroy items for nothing — zero-value goods (progression mats,
	# crafting cards) are craft-only, not sellable.
	if price_val <= 0:
		UITheme.show_notification(tr("This item has no market value — it's used in crafting."), Color(1.0, 0.7, 0.3))
		return

	var total = qty * price_val
	if GameState.resources.remove_element(symbol, qty):
		GameState.resources.add_currency("credits", total)
		UITheme.show_notification(tr("+%s Liras") % UITheme.format_num(total), Color.GOLD)
		# refresh_inventory() # v65.1 Cleanup: Redundant, handled by signals
	else:
		UITheme.show_notification(tr("Sale Failed"), Color.RED)


func _process(delta):
	# Poll for inventory changes?
	# Or rely on refresh signals? 
	# For simplicity/MVP, refresh on show?
	pass
	
func _on_visibility_changed():
	if visible:
		refresh_inventory()
