extends PanelContainer

var hid: String
var data: Dictionary
var manager: RefCounted
var parent_ui: Node

@onready var name_lbl = $MarginContainer/VBoxContainer/NameLabel
@onready var slot_lbl = $MarginContainer/VBoxContainer/SlotsLabel
@onready var cost_lbl = $MarginContainer/VBoxContainer/CostLabel
@onready var research_lbl = $MarginContainer/VBoxContainer/ResearchLabel
@onready var btn = $MarginContainer/VBoxContainer/Button
@onready var ship_icon = $MarginContainer/VBoxContainer/ShipIcon

func setup(p_hid: String, p_data: Dictionary, p_manager, p_parent):
	hid = p_hid
	data = p_data
	manager = p_manager
	parent_ui = p_parent
	
	name_lbl.text = data["name"]
	if data.get("tier"):
		name_lbl.text += " (TIER %d)" % data["tier"]
	
	name_lbl.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS["shipyard"])
	
	UITheme.apply_card_style(self, "shipyard")
	UITheme.apply_premium_button_style(btn, "shipyard")
	
	slot_lbl.text = "HP: %d | ATK: %d\nSlots: %d" % [data["stats"].get("hp",0), data["stats"].get("atk",0), data["slots"].size()]
	
	if data.has("visual"):
		ship_icon.texture = load(data["visual"])
	
	# Cost text handled dynamically in update_state
	cost_lbl.text = ""
	research_lbl.hide()
	
	UITheme.inject_diegetic_header(self, "shipyard")
	
func _process(delta):
	update_state()

func update_state():
	if manager.active_hull == hid:
		btn.text = "Active"
		btn.disabled = true
		modulate = Color(1.2, 1.2, 1)
		research_lbl.hide()
	else:
		btn.text = "Construct"
		
		# Check Research Requirements
		var req_id = data.get("research_req")
		var tech_unlocked = GameState.research_manager.is_tech_unlocked(req_id)
		
		if not tech_unlocked:
			var tech_name = GameState.research_manager.tech_tree.get(req_id, {}).get("name", req_id)
			UITheme.apply_locked_overlay(self, data["name"], "RESEARCH: %s" % tech_name, true, req_id, "shipyard")
			research_lbl.text = "Req: %s" % tech_name
			research_lbl.show()
			btn.disabled = true
			cost_lbl.hide()
			return
		else:
			UITheme.apply_locked_overlay(self, data["name"], "", false)
			research_lbl.hide()
			cost_lbl.show()

		var affordable = true
		var cost_str = "[center]"
		
		for res in data["cost"]:
			var qty = data["cost"][res]
			var can_afford = false
			var color = "gray" 
			
			if res == "credits":
				if GameState.resources.get_currency("credits") >= qty: 
					can_afford = true
					color = "lime"
			else:
				if GameState.resources.get_element_amount(res) >= qty: 
					can_afford = true
					color = "lime"
			
			if not can_afford:
				affordable = false
				
			cost_str += "[color=%s]%s %s[/color]\n" % [color, FormatUtils.format_number(qty), (UITheme.LIRA_ICON_BB if res == "credits" else ElementDB.get_display_name(res))]
		
		cost_str += "[/center]"
		cost_lbl.text = cost_str
		
		btn.disabled = not affordable
		modulate = Color(1, 1, 1)

func _on_button_pressed():
	if manager.construct_hull(hid):
		# TACTILE: Heavy industrial thud
		UITheme.trigger_mechanical_bash(self, 12.0)
		
		# Optional: Screen flash or pulse
		var tween = create_tween()
		tween.tween_property(self, "modulate", Color(2, 2, 2), 0.1)
		tween.tween_property(self, "modulate", Color(1, 1, 1), 0.3)
