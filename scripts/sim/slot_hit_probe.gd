extends Node
# Diagnostic: what does an equipped Ship Designer slot look like to the mouse?
#
# Symptom (owner): a Matrix Core only attaches when dropped near the slot's
# BOTTOM-RIGHT corner. Godot resolves a drop by finding the topmost control
# under the cursor and walking UP the parent chain, stopping at the first
# MOUSE_FILTER_STOP node. Any STOP child that does not implement _can_drop_data
# therefore carves a dead zone out of the tile.
#
# This dumps the real filters + rects instead of assuming engine defaults.
#   Godot --path . res://scenes/slot_hit_probe.tscn
const FILTER_NAME := {0: "STOP", 1: "PASS", 2: "IGNORE"}

func _ready() -> void:
	var m: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(m)
	for _i in range(40):
		await get_tree().process_frame
	get_tree().current_scene = m
	var cs: Dictionary = GameState.game_settings.get("coach_seen", {})
	cs["designer"] = true
	GameState.game_settings["coach_seen"] = cs
	if "offline_modal" in m and m.offline_modal != null and is_instance_valid(m.offline_modal):
		m.offline_modal.visible = false
	m.switch_to("designer")
	for _i in range(60):
		await get_tree().process_frame

	var slot: Control = _find_equipped_slot(m)
	if slot == null:
		print("[HIT] no equipped designer slot found")
		get_tree().quit(1)
		return
	# Scroll it into view — an off-screen slot makes every hit test return NONE
	# (its ancestors' rects exclude the point) and the map reads as a false clean.
	var anc: Node = slot.get_parent()
	while anc != null:
		if anc is ScrollContainer:
			(anc as ScrollContainer).ensure_control_visible(slot)
			break
		anc = anc.get_parent()
	for _i in range(20):
		await get_tree().process_frame

	print("[HIT] slot '%s' rect=%s filter=%s clip=%s" % [
		slot.name, slot.get_global_rect(), FILTER_NAME.get(slot.mouse_filter, "?"),
		slot.clip_contents])
	_dump(slot, 1)

	# Which node actually receives the cursor, across the tile? Searched from the
	# SCENE ROOT, not from the slot — the viewport hit-tests the whole tree, so a
	# probe rooted at the slot can only ever answer "the slot" and would miss the
	# overlay/sibling that is actually eating the drop. (First cut did exactly
	# that and reported a clean 5x5 while the bug was live.)
	print("[HIT] drop owner map (7x7 across the slot; '.' = the slot itself):")
	var r := slot.get_global_rect()
	for gy in range(7):
		var row := ""
		for gx in range(7):
			var p := r.position + Vector2(
				r.size.x * (0.07 + 0.145 * gx), r.size.y * (0.07 + 0.145 * gy))
			var owner_node := _drop_owner_from_root(slot, p)
			row += "%-20s" % (("." if owner_node == slot else str(owner_node.name)) if owner_node else "NONE")
		print("[HIT]   %s" % row)

	# ---- where does the DRAG PREVIEW actually sit relative to the cursor? -----
	# The whole tile accepts, so target resolution is not the bug. That leaves the
	# preview: if the crystal does not straddle the cursor, the player aims by the
	# crystal and the cursor lands somewhere else entirely.
	var card: Control = _find_gem_card(m)
	if card == null:
		print("[HIT] no gem card in the armory to drag-test")
		get_tree().quit(0)
		return
	var prev: Control = card._make_drag_preview()
	card.force_drag({"type": "module", "mid": str(card.mid),
		"slot_type": str(card.data.get("slot_type", "gem"))}, prev)
	for _i in range(4):
		await get_tree().process_frame
	var mouse := card.get_viewport().get_mouse_position()
	print("[HIT] --- drag preview geometry ---")
	print("[HIT] mouse=%s  preview_root_pos=%s (top_level=%s)" % [
		mouse, prev.global_position, prev.is_set_as_top_level()])
	for ch in prev.get_children():
		if ch is Control:
			var cr := (ch as Control).get_global_rect()
			print("[HIT] preview child '%s' rect=%s centre=%s  offset_from_mouse=%s" % [
				ch.name, cr, cr.get_center(), cr.get_center() - mouse])
	get_tree().quit(0)

# Prefer a gem card, else ANY module card — the preview ROOT is positioned by the
# engine the same way for both branches, and that root placement is the question.
func _find_gem_card(m: Node) -> Control:
	var q: Array = [m]
	var fallback: Control = null
	while q.size() > 0:
		var n = q.pop_front()
		if n is Control and n.get_script() != null \
				and str(n.get_script().resource_path).ends_with("module_card.gd"):
			var d = n.get("data")
			if d != null and not (d as Dictionary).is_empty():
				var st := str((d as Dictionary).get("slot_type", ""))
				if st in ["gem", "gem_synth"]:
					return n
				if fallback == null:
					fallback = n
		q.append_array(n.get_children())
	if fallback:
		print("[HIT] (no gem card on this page — using a '%s' card; root placement is shared)"
			% str((fallback.get("data") as Dictionary).get("slot_type", "?")))
	return fallback

# PREFER a slot whose module has SOCKETS — that is the case the Matrix-Core drop
# bug lives in. The first run of this probe grabbed any equipped slot, landed on a
# socketless one, and reported a perfectly clean hit map while the bug was live.
func _find_equipped_slot(m: Node) -> Control:
	var q: Array = [m]
	var fallback: Control = null
	while q.size() > 0:
		var n = q.pop_front()
		if n is Control and str(n.get_script().resource_path if n.get_script() else "").ends_with("designer_slot_widget.gd"):
			if n.get("slot_idx") != null:
				var eq = GameState.shipyard_manager.loadout.get(int(n.slot_idx))
				if eq:
					var md: Dictionary = GameState.shipyard_manager.modules.get(str(eq), {})
					if (md.get("sockets", []) as Array).size() > 0:
						print("[HIT] using SOCKETED slot %d (%d socket(s))" % [
							int(n.slot_idx), (md.get("sockets", []) as Array).size()])
						return n
					if fallback == null:
						fallback = n
		q.append_array(n.get_children())
	if fallback:
		print("[HIT] WARNING: no socketed module equipped — falling back to a socketless slot,")
		print("[HIT]          which CANNOT reproduce the Matrix-Core drop bug.")
	return fallback

func _dump(c: Node, depth: int) -> void:
	for ch in c.get_children():
		if ch is Control:
			var cc := ch as Control
			print("[HIT] %s%s (%s) filter=%s vis=%s rect=%s" % [
				"  ".repeat(depth), cc.name, cc.get_class(),
				FILTER_NAME.get(cc.mouse_filter, "?"), cc.visible, cc.get_global_rect()])
		_dump(ch, depth + 1)

# Topmost non-IGNORE control containing p, searched in reverse child order
# (later children draw on top), then the walk up to the first STOP.
func _topmost(c: Control, p: Vector2) -> Control:
	if not c.visible or c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		if not c.visible:
			return null
	if not c.get_global_rect().has_point(p):
		return null
	var kids := c.get_children()
	for i in range(kids.size() - 1, -1, -1):
		if kids[i] is Control:
			var hit := _topmost(kids[i] as Control, p)
			if hit != null:
				return hit
	return c if c.mouse_filter != Control.MOUSE_FILTER_IGNORE else null

func _drop_owner_from_root(slot: Control, p: Vector2) -> Control:
	# Search the entire scene, exactly as the viewport does.
	var root_ctl: Control = null
	var n: Node = slot
	while n != null:
		if n is Control:
			root_ctl = n as Control
		n = n.get_parent()
	if root_ctl == null:
		return null
	var c := _topmost(root_ctl, p)
	while c != null:
		if _overrides_can_drop(c):
			return c
		if c.mouse_filter == Control.MOUSE_FILTER_STOP:
			return c   # swallows the query without handling it — a DEAD ZONE
		c = c.get_parent_control()
	return null

# has_method("_can_drop_data") is TRUE for every Control — it is a ClassDB
# virtual — so using it made the walk return the topmost node and rendered the
# probe blind to the STOP-vs-PASS distinction it exists to measure. Ask the
# SCRIPT whether it actually implements the override.
func _overrides_can_drop(c: Control) -> bool:
	var scr = c.get_script()
	if scr == null:
		return false
	for mi in scr.get_script_method_list():
		if str(mi.get("name", "")) == "_can_drop_data":
			return true
	return false
