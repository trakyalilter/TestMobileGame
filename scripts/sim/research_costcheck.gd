extends Node
# ============================================================================
# RESEARCH COST CHECK — prints the EFFECTIVE (unlock-time) item cost of research
# nodes, i.e. what the player actually pays and what the node card shows. Research
# item costs are DOUBLE-scaled and it's easy to under-count: the authored raw qty
# is first stage-scaled at _init (x2.5 MID / x? LATE — _scale_mid_late_research_
# item_costs, but only for items in the MID/LATE/ENDGAME lists), THEN multiplied by
# MATERIAL_MULTIPLIER (x2) at can_unlock/pay (_effective_item_requirement). NON_
# SCALING items (SalvageData, cores, …) skip both. So a raw "AdvCircuit: 20" on a
# combat node silently becomes 100. This probe makes the real number visible.
#   Godot --headless --path <root> res://scenes/research_costcheck.tscn
# ============================================================================

func _ready() -> void:
	var rm = GameState.research_manager
	GameState.set_process(false)
	print("[COSTCHK] === effective research item costs (unlock-time charge = node-card display) ===")
	for nid in ["firmware_hacking", "shipwright_1", "shipwright_2"]:
		var node: Dictionary = rm.tech_tree.get(nid, {})
		if node.is_empty():
			print("[COSTCHK] %-18s (missing)" % nid)
			continue
		var ci: Dictionary = node.get("cost_items", {})
		var parts := []
		for item in ci:
			var eff: int = rm._effective_item_requirement(item, int(ci[item]))
			parts.append("%s x%d" % [ElementDB.get_display_name(item), eff])
		print("[COSTCHK] %-18s (%s) | %s" % [nid, String(node.get("name", "")), ", ".join(parts)])
	get_tree().quit(0)
