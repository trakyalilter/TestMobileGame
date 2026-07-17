extends PanelContainer

var hid: String
var data: Dictionary
var manager: RefCounted
var parent_ui: Node
var _cost_link_wired := false   # v137: connect the material→Atlas link once

@onready var name_lbl = $MarginContainer/VBoxContainer/NameLabel
@onready var slot_lbl = $MarginContainer/VBoxContainer/SlotsLabel
@onready var cost_lbl = $MarginContainer/VBoxContainer/CostLabel
@onready var research_lbl = $MarginContainer/VBoxContainer/ResearchLabel
@onready var btn = $MarginContainer/VBoxContainer/Button

func setup(p_hid: String, p_data: Dictionary, p_manager, p_parent):
	hid = p_hid
	data = p_data
	manager = p_manager
	parent_ui = p_parent

	# v137: click a cost material name → deep-link to its Atlas page (skip Liras).
	if not _cost_link_wired:
		_cost_link_wired = true
		cost_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		cost_lbl.meta_clicked.connect(func(meta): UITheme.request_atlas_from_meta(meta))

	name_lbl.text = tr(data["name"])
	if data.get("tier"):
		name_lbl.text += " (TIER %d)" % data["tier"]
	
	name_lbl.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS["shipyard"])
	
	UITheme.apply_card_style(self, "shipyard")
	UITheme.apply_premium_button_style(btn, "shipyard")
	
	slot_lbl.text = tr("HP: %d\nSlots: %d") % [_hull_hp_display(), data["slots"].size()]

	# Cost text handled dynamically in update_state
	cost_lbl.text = ""
	research_lbl.hide()
	
	UITheme.inject_diegetic_header(self, "shipyard")
	
# v124: catalog HP reflects the global "+% all hulls" buffs — CMB_1 Hardened Hull
# (warp tree) and Recursive Hardening (research) — so a purchased hull bonus shows
# on every card, not only the equipped-ship stats panel. Module/gem HP is
# loadout-specific and intentionally not shown on the catalog card.
func _hull_hp_display() -> int:
	var base: float = float(data["stats"].get("hp", 0))
	var mult: float = 1.0
	if GameState.warp_manager:
		mult *= GameState.warp_manager.get_tree_hull_bonus()
	if GameState.research_manager:
		mult *= 1.0 + GameState.research_manager.get_efficiency_bonus("hull_hp_mult")
	return int(round(base * mult))

func _process(delta):
	update_state()

func update_state():
	# Keep catalog HP live with global hull buffs (buying CMB_1 updates every card).
	slot_lbl.text = tr("HP: %d\nSlots: %d") % [_hull_hp_display(), data["slots"].size()]
	if manager.active_hull == hid:
		btn.text = tr("Active")
		btn.disabled = true
		modulate = Color(1.2, 1.2, 1)
		research_lbl.hide()
	else:
		btn.text = tr("Construct")
		
		# Check Research Requirements
		var req_id = data.get("research_req")
		var tech_unlocked = GameState.research_manager.is_tech_unlocked(req_id)
		
		if not tech_unlocked:
			var tech_name = GameState.research_manager.tech_tree.get(req_id, {}).get("name", req_id)
			UITheme.apply_locked_overlay(self, data["name"], tr("RESEARCH: %s") % tr(tech_name), true, req_id, "shipyard")
			research_lbl.text = tr("Req: %s") % tech_name
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
				
			var res_disp: String = UITheme.LIRA_ICON_BB if res == "credits" else "[url=atlasmat:%s]%s[/url]" % [res, ElementDB.get_display_name(res)]
			cost_str += "[color=%s]%s %s[/color]\n" % [color, FormatUtils.format_number(qty), res_disp]
		
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
