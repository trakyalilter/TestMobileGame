extends PanelContainer

var mid: String
var data: Dictionary
var manager: RefCounted
var parent_ui: Node
var target_slot_idx: int = -1

@onready var name_lbl = $MarginContainer/VBoxContainer/NameLabel
@onready var stats_lbl = $MarginContainer/VBoxContainer/StatsLabel
@onready var cost_lbl = $MarginContainer/VBoxContainer/CostLabel
@onready var owned_lbl = $MarginContainer/VBoxContainer/OwnedLabel
@onready var research_lbl = $MarginContainer/VBoxContainer/ResearchLabel
@onready var btn = $MarginContainer/VBoxContainer/Button

func setup(p_mid: String, p_data: Dictionary, p_manager, p_parent):
	mid = p_mid
	data = p_data
	manager = p_manager
	parent_ui = p_parent
	
	name_lbl.text = data["name"]
	name_lbl.add_theme_color_override("font_color", UITheme.CATEGORY_COLORS["shipyard"])
	
	# v83.9: Set Name Display
	var sid = data.get("set_id", "")
	var sm = GameState.shipyard_manager
	if sid == "" and data.get("is_custom") and data.has("base_module") and sm:
		var base_id = data["base_module"]
		sid = sm.modules.get(base_id, {}).get("set_id", "")
	var v_box = $MarginContainer/VBoxContainer
	var set_lbl = v_box.get_node_or_null("SetLabel")
	if not set_lbl:
		set_lbl = Label.new()
		set_lbl.name = "SetLabel"
		set_lbl.add_theme_font_size_override("font_size", 8)
		set_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		set_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v_box.add_child(set_lbl)
		v_box.move_child(set_lbl, name_lbl.get_index() + 1)
	
	if sid != "" and GameState.combat_manager and "TRINITY_SET_BONUSES" in GameState.combat_manager:
		var s_db = GameState.combat_manager.TRINITY_SET_BONUSES
		if s_db.has(sid):
			var set_name = s_db[sid]["name"]
			set_lbl.text = "[ %s ]" % set_name.to_upper()
			set_lbl.add_theme_color_override("font_color", Color(0.0, 0.8, 0.8)) # Cyan
			set_lbl.visible = true
		else:
			set_lbl.visible = false
	else:
		set_lbl.visible = false
	
	# (Removed old text-based socket render)
	
	UITheme.apply_card_style(self, "shipyard")
	UITheme.apply_premium_button_style(btn, "shipyard")
	
	_update_stats_text()
	UITheme.inject_diegetic_header(self, "shipyard")
	
	# v74.0: Render Physical Sockets on the card
	if data.has("sockets") and data["sockets"].size() > 0:
		var sock_container = HBoxContainer.new()
		sock_container.name = "SocketContainer"
		sock_container.alignment = BoxContainer.ALIGNMENT_CENTER
		sock_container.add_theme_constant_override("separation", 8)
		
		for gem in data["sockets"]:
			var sock_bg = Panel.new()
			sock_bg.custom_minimum_size = Vector2(10, 10)
			var sb = StyleBoxFlat.new()
			sb.bg_color = Color(0.02, 0.02, 0.02, 0.8) # Empty dark hole
			sb.border_width_left = 1; sb.border_width_top = 1; sb.border_width_right = 1; sb.border_width_bottom = 1;
			sb.border_color = Color(0.3, 0.3, 0.3, 0.8)
			
			if gem != null:
				var gem_name = ElementDB.get_display_name(gem)
				var g_color = _get_gem_color(gem_name)
				sb.bg_color = g_color
				sb.border_color = g_color.lightened(0.6)
				sb.shadow_color = g_color * Color(1, 1, 1, 0.4)
				sb.shadow_size = 4
			
			sock_bg.add_theme_stylebox_override("panel", sb)
			sock_bg.pivot_offset = Vector2(5, 5)
			sock_bg.rotation_degrees = 45 # Diamond layout
			
			var sock_wrap = Control.new()
			sock_wrap.custom_minimum_size = Vector2(16, 16)
			sock_bg.position = Vector2(3, 3)
			sock_wrap.add_child(sock_bg)
			sock_container.add_child(sock_wrap)
			
		$MarginContainer/VBoxContainer.add_child(sock_container)
		$MarginContainer/VBoxContainer.move_child(sock_container, 2)
	
	cost_lbl.text = ""
	research_lbl.hide()
	
	# Comparison tooltip on hover
	mouse_entered.connect(_on_hover_enter)
	mouse_exited.connect(_on_hover_exit)

func _update_stats_text():
	var s_txt = ""
	var stats = data.get("stats", {})
	for k in stats:
		# v110: energy is tier-derived; suppress the stale per-module stat and
		# show the real POWER DRAW/SUPPLY line below.
		if k == "energy_load" or k == "energy_capacity":
			continue
		var label = FormatUtils.format_stat_label(k)
		var val = stats[k]
		s_txt += "%s: %s\n" % [label, FormatUtils.format_stat_value(k, val)]

	# v110: derived power line
	var stype = data.get("slot_type", "")
	if manager and manager.has_method("get_module_energy_load"):
		if stype in ["weapon", "shield", "armor", "engine", "sensor"]:
			var draw = manager.get_module_energy_load(mid)
			if draw > 0: s_txt += "POWER DRAW: %d\n" % draw
		elif stype == "battery":
			var supply = manager.get_module_energy_capacity(mid)
			if supply > 0: s_txt += "POWER: +%d\n" % supply

	# (Removed old text-prepend)
		
	var durability = int(data.get("durability", 100))
	s_txt += "Durability: %d/100\n" % durability
		
	stats_lbl.text = s_txt.strip_edges()
	
	# v74.0: Display Affixes
	if data.get("affixes", {}).size() > 0:
		var a_txt = "\n"
		var sm = GameState.shipyard_manager
		var affixes = data["affixes"]
		for aid in affixes:
			if aid in sm.AFFIX_DB:
				var cfg = sm.AFFIX_DB[aid]
				var val = int(affixes[aid] * 100)
				var a_desc = cfg["desc"] % val
				a_txt += "\n[ %s ]\n" % a_desc
		stats_lbl.text += a_txt



func update_state():
	var owned = manager.module_inventory.get(mid, 0)
	if data.get("slot_type") == "gem_synth":
		owned_lbl.text = "" # Synthesis doesn't go to storage directly
	else:
		owned_lbl.text = "In Storage: %d" % owned
	
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
	
	if data.get("is_custom", false) or data.get("is_unique", false):
		cost_lbl.text = "[center][color=orange]Drop-only module[/color][/center]"
		btn.text = "DROP ONLY"
		btn.disabled = true
		return

	var affordable = true
	var cost_str = "[center]"
	var cost_data = data.get("cost", {})
	
	for res in cost_data:
		var qty = cost_data[res]
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

func _on_button_pressed():
	if target_slot_idx >= 0:
		# Equip to specific slot
		if manager.module_inventory.get(mid, 0) > 0:
			if manager.equip_module(target_slot_idx, mid):
				UITheme.trigger_ui_thud(btn, 6.0)
				update_state()
				if parent_ui.has_method("_build_slot_grid"):
					parent_ui._build_slot_grid()
		target_slot_idx = -1
		_reset_highlight()
	else:
		# Craft module
		if manager.craft_module(mid):
			UITheme.trigger_ui_thud(btn, 5.0)
			update_state()

# ─────────────────────────────────────────────────
# SLOT HIGHLIGHTING
# ─────────────────────────────────────────────────

func highlight_for_slot(slot_idx: int, req_type: String):
	var my_type = data.get("slot_type", "")
	if my_type == req_type and manager.module_inventory.get(mid, 0) > 0:
		target_slot_idx = slot_idx
		modulate = Color(0.5, 1.0, 0.5, 1.0)  # Green highlight
		btn.text = "EQUIP"
		btn.disabled = false
	else:
		_reset_highlight()

func _reset_highlight():
	target_slot_idx = -1
	modulate = Color.WHITE
	if data.get("is_custom", false):
		btn.text = "DROP ONLY"
		btn.disabled = true
	elif data.get("slot_type") == "gem":
		btn.text = "Synthesize"
	elif data.get("slot_type") == "gem_synth":
		btn.text = "Fuse Cores"
	else:
		btn.text = "Craft"

func _get_gem_color(gem_name: String) -> Color:
	if "Crimson" in gem_name: return Color("#ff4444")
	if "Cobalt" in gem_name: return Color("#44ccff")
	if "Topaz" in gem_name: return Color("#ffcc00")
	if "Amethyst" in gem_name: return Color("#aa44ff")
	return Color("#b548b5") # Default purple

# ─────────────────────────────────────────────────
# COMPARISON TOOLTIP
# ─────────────────────────────────────────────────

func _on_hover_enter():
	tooltip_text = _build_comparison_tooltip()

func _on_hover_exit():
	pass

func _make_custom_tooltip(_for_text: String) -> Control:
	# v111.15 FRAME-IN-FRAME FIX: return a frameless RichTextLabel so the theme's
	# `TooltipPanel` wrapper is the single frame (returning our own bordered
	# PanelContainer nested two frames). Rarity stays visible via the bold
	# rarity-coloured title in the body.
	var rtl = RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.custom_minimum_size = Vector2(320, 0)
	rtl.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))
	rtl.text = _build_comparison_tooltip()
	return rtl

func _build_comparison_tooltip() -> String:
	if not data: return ""
	
	var sm = GameState.shipyard_manager
	var rarity = int(data.get("rarity", sm.Rarity.COMMON))
	var rarity_label = sm.RARITY_LABELS.get(rarity, "Common")
	if rarity == sm.Rarity.COMMON: rarity_label = "Common"
	
	var rarity_color_hex = sm.RARITY_COLORS.get(rarity, Color.GRAY).to_html(false)
	var slot_type = data.get("slot_type", "weapon")
	
	var tt = ""
	
	# 1. HEADER
	var display_name = data.get("name", "Item").to_upper()
	for suffix in [" (COMMON)", " (UNCOMMON)", " (RARE)", " (LEGENDARY)", " (UNIQUE)"]:
		display_name = display_name.replace(suffix, "")
		
	var rarity_color = sm.RARITY_COLORS.get(rarity, Color.WHITE)
	var div = "[color=#41526e]──────────────────────────────[/color]\n"

	tt = "" # Reset tt as it was already initialized
	tt += "[b][color=#%s]%s[/color][/b]\n" % [rarity_color.to_html(), data.get("name", "Unknown Item")]
	tt += "[font_size=10][color=gray]%s[/color][/font_size]\n" % [slot_type.capitalize()]
	tt += div
	
	if slot_type == "gem" or slot_type == "gem_synth":
		var gem_desc = data.get("desc", ElementDB.get_element_description(mid))
		tt += "[center][font_size=12][color=silver]%s[/color][/font_size][/center]\n" % gem_desc
		return tt
		
	var my_stats = data.get("stats", {})
	
	# 2. PRIMARY STAT
	if slot_type == "weapon":
		var dmg = my_stats.get("atk_kinetic", 0) + my_stats.get("atk_energy", 0) + my_stats.get("atk_explosive", 0) + my_stats.get("atk_cryo", 0)
		var interval = max(0.01, float(my_stats.get("atk_interval", 2.5)))
		var dps = float(dmg) / interval
		tt += "[font_size=20][b]%.1f DPS[/b][/font_size]\n" % dps
		tt += "[font_size=9][color=gray]%s total damage, %.2f hits/s[/color][/font_size]\n" % [UITheme.format_num(dmg), 1.0 / interval]
		if my_stats.get("atk_kinetic", 0) > 0:
			tt += "[color=#99ccff][b]KINETIC[/b][/color]  [color=gray]Strong vs Hull, weak vs Shield[/color]\n"
		if my_stats.get("atk_energy", 0) > 0:
			tt += "[color=#ffe64d][b]ENERGY[/b][/color]  [color=gray]Strong vs Shield, bypasses Armor[/color]\n"
		if my_stats.get("atk_explosive", 0) > 0:
			tt += "[color=#ff804d][b]EXPLOSIVE[/b][/color]  [color=gray]Ignores most Armor[/color]\n"
		if my_stats.get("atk_cryo", 0) > 0:
			tt += "[color=#b3f0ff][b]CRYOGENIC[/b][/color]  [color=gray]Breaches Warp-Hardened, self-charging[/color]\n"
		tt += div
	elif slot_type == "shield":
		var val = my_stats.get("max_shield", 0)
		tt += "[font_size=20][b]%s[/b][/font_size] [font_size=10][color=gray]Shield Capacity[/color][/font_size]\n" % UITheme.format_num(val)
		tt += div
	elif slot_type == "armor":
		var hp_val = my_stats.get("hp", 0)
		tt += "[center][font_size=20][b]%s[/b][/font_size] [font_size=10][color=gray]Integrity Reinforcement[/color][/font_size][/center]\n" % UITheme.format_num(hp_val)
		tt += "[color=#41526e]──────────────────────────────[/color]\n"

	# 3. STAT COMPARISON
	var equipped_mid = null
	var equipped_stats = {}
	for idx in manager.loadout:
		var m = manager.loadout[idx]
		if m and m in manager.modules:
			var m_data = manager.modules[m]
			if m_data.get("slot_type") == slot_type:
				equipped_mid = m
				equipped_stats = m_data.get("stats", {})
				break
	
	for k in my_stats:
		# Filter out structural and redundant stats
		if k == "atk_interval": continue
		if k == "energy_load" or k == "energy_capacity": continue  # v110: derived now
		if slot_type == "weapon" and (k == "atk_kinetic" or k == "atk_energy" or k == "atk_explosive" or k == "atk_cryo"): continue
		if slot_type == "shield" and k == "max_shield": continue
		if slot_type == "armor" and k == "hp": continue
		
		var label = FormatUtils.format_stat_label(k)
		var val = my_stats[k]
		var delta_str = ""
		
		if equipped_mid and equipped_mid != mid and k != "energy_load":
			var eq_val = equipped_stats.get(k, 0)
			var diff = val - eq_val
			if diff > 0:
				delta_str = " [color=lime][font_size=9](+%s ^)[/font_size][/color]" % FormatUtils.format_stat_value(k, diff)
			elif diff < 0:
				delta_str = " [color=red][font_size=9](%s v)[/font_size][/color]" % FormatUtils.format_stat_value(k, diff)
		
		# v76.0: Display Roll Range for base stats
		var range_info = ""
		var b_id = data.get("base_module", "")
		if b_id != "" and b_id in sm.modules and k in sm.BOOSTABLE_STATS:
			var b_val = sm.modules[b_id].get("stats", {}).get(k, 0)
			if b_val > 0:
				var s_range = sm.RARITY_STAT_RANGE.get(rarity, [0, 0])
				if s_range[1] > 0:
					var zone_mult = 1.0
					if k in sm.ZONE_SCALABLE_STATS and data.has("zone_difficulty"):
						zone_mult = sm.get_module_zone_multiplier(int(data.get("zone_difficulty", 1)))
					var scaled_base = b_val * zone_mult
					var r_min = scaled_base * (1.0 + s_range[0])
					var r_max = scaled_base * (1.0 + s_range[1])
					range_info = " [color=gray][font_size=8][%s-%s][/font_size][/color]" % [
						FormatUtils.format_stat_value(k, r_min),
						FormatUtils.format_stat_value(k, r_max)
					]

		tt += "[color=silver]* %s: [color=white]%s[/color][/color]%s%s\n" % [label, FormatUtils.format_stat_value(k, val), range_info, delta_str]
	
	# 4. RANDOM AFFIXES
	var affixes = data.get("affixes", {})
	if affixes.size() > 0:
		tt += div
		var zone_difficulty = int(data.get("zone_difficulty", 1))
		for aid in affixes:
			if aid in sm.AFFIX_DB:
				var cfg = sm.AFFIX_DB[aid]
				var val_raw = affixes[aid]
				var scaling = cfg.get("scaling", "percent")
				
				# v80.1 Fix: Use scaled ranges for display
				var s_range = sm.get_affix_scaled_range(aid, zone_difficulty)
				var val_str = ""
				var range_str = ""
				
				if scaling == "flat" or scaling == "linear_tier":
					val_str = str(int(val_raw))
					range_str = " [color=gray][font_size=9][%d-%d][/font_size][/color]" % [int(s_range[0]), int(s_range[1])]
				else:
					val_str = "%d%%" % int(val_raw * 100)
					range_str = " [color=gray][font_size=9][%d-%d]%%[/font_size][/color]" % [int(s_range[0] * 100), int(s_range[1] * 100)]
				
				var desc = cfg["desc"] % [int(val_raw) if (scaling == "flat" or scaling == "linear_tier") else int(val_raw * 100)]
				
				if rarity == sm.Rarity.LEGENDARY:
					tt += "[color=orange][b]%s[/b][/color]%s\n" % [desc, range_str]
				elif rarity == sm.Rarity.UNIQUE:
					tt += "[color=#ff33cc][b]%s[/b][/color]%s\n" % [desc, range_str]
				else:
					tt += "[color=cyan]%s[/color]%s\n" % [desc, range_str]

	# 5. FOOTER
	tt += div
	if equipped_mid and equipped_mid != mid:
		tt += "[font_size=9][color=yellow]Comparing with: %s[/color][/font_size]" % manager.modules[equipped_mid]["name"]
	else:
		tt += "[font_size=9][color=gray](Currently equipped module)[/color][/font_size]" if equipped_mid == mid else ""

	# v83.9: Set Bonus Tooltip Section
	var sid = data.get("set_id", "")
	if sid == "" and data.get("is_custom") and data.has("base_module"):
		var base_id = data["base_module"]
		sid = sm.modules.get(base_id, {}).get("set_id", "")
	if sid != "" and GameState.combat_manager and "TRINITY_SET_BONUSES" in GameState.combat_manager:
		var s_db = GameState.combat_manager.TRINITY_SET_BONUSES
		if s_db.has(sid):
			tt += div
			var set_info = s_db[sid]
			var count = GameState.combat_manager.get_set_piece_count(sid)
			var total = set_info["pieces"]
			var active = count >= total
			
			tt += "[b][color=#00ffff]SET: %s[/color][/b]\n" % set_info["name"].to_upper()
			tt += "[font_size=10][color=gray]%d / %d pieces equipped[/color][/font_size]\n" % [count, total]
			
			for bonus_key in set_info["bonus"]:
				var val = set_info["bonus"][bonus_key]
				var b_name = bonus_key.replace("_pct", "").replace("_flat", "").replace("_", " ").to_upper()
				var val_str = "+%d%%" % val if ("_pct" in bonus_key or "crit" in bonus_key) else "+%d" % val
				
				var col = "#ffffff" if active else "#666666"
				tt += "[color=%s]%s: %s[/color]\n" % [col, b_name, val_str]

	return tt
