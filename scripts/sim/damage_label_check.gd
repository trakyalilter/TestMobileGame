extends Node
# TYPED DAMAGE LABEL GUARD.
#
# The floating combat text is the only place the game tells you what type of
# damage just landed, and the exotic channel was invisible to it:
#   - player: Cryo-Lance / Corrosion Blaster are pure atk_cryo (k=e=x=0), so both
#     dominance tests failed and every hit floated "-N KIN" -- including in Z11+,
#     where conventional damage is cut 98% and Cryo is the entire lesson.
#   - the RESISTED / WEAK SPOT line read only resist_k/e/x, so Z11's resist_cryo
#     -0.25 never produced WEAK SPOT at the one fight built around a weakness.
#   - enemy: dmg_type "corrosion" (z13, z15) had no case and floated "KIN" too.
#
#   Godot --headless --path <root> res://scenes/damage_label_check.tscn

var fails: int = 0

func _ready() -> void:
	await get_tree().process_frame
	var cm = GameState.combat_manager
	var sm = GameState.shipyard_manager

	# ---- player labels: drive the real attack path -------------------------
	for case in [
			{"exotic": "cryo",      "tag": "CRY"},
			{"exotic": "corrosion", "tag": "COR"}]:
		var tags: Array = _fire_exotic_weapon(cm, sm, String(case["exotic"]))
		print("[DL] %s weapon -> damage tags %s" % [case["exotic"], str(tags)])
		_expect(tags.size() > 0, "%s weapon produced no damage event at all" % case["exotic"])
		for t in tags:
			_expect(String(t) == String(case["tag"]),
				"%s weapon floated '%s', expected '%s'" % [case["exotic"], String(t), String(case["tag"])])

	# ---- WEAK SPOT must be reachable on a cryo-weak target -----------------
	# resist_cryo -0.25 clears the <= -0.20 weakness threshold, but the roll is
	# 15% per hit, so fire until it shows rather than asserting on one swing.
	var saw_weak: bool = false
	for _i in range(400):
		for ev in _fire_exotic_weapon_events(cm, sm, "cryo"):
			if String(ev.get("type", "")) == "weakness" and String(ev.get("text", "")) == "WEAK SPOT":
				saw_weak = true
		if saw_weak:
			break
	print("[DL] cryo vs resist_cryo -0.25 -> WEAK SPOT seen: %s" % str(saw_weak))
	_expect(saw_weak, "WEAK SPOT never fired against a resist_cryo -0.25 target in 400 swings")

	# ---- enemy corrosion attacks must not masquerade as kinetic ------------
	var cor_ids: Array = []
	for eid in cm.enemy_db:
		if String(cm.enemy_db[eid].get("dmg_type", "")) == "corrosion":
			cor_ids.append(String(eid))
	print("[DL] enemies with dmg_type corrosion: %s" % str(cor_ids))
	_expect(cor_ids.size() > 0, "no corrosion enemies found -- guard is not exercising anything")
	for eid in cor_ids:
		# The manager's OWN mapping, not a copy of it — a mirror here would keep
		# passing after a regression in the real one.
		var tag: String = cm.damage_type_tag(String(cm.enemy_db[eid].get("dmg_type", "kinetic")))
		_expect(tag == "COR", "%s attacks labelled '%s', expected 'COR'" % [eid, tag])
	print("[DL] all corrosion enemies label COR")
	# No enemy anywhere may fall back to KIN unless it really is kinetic — that
	# fallback is exactly how corrosion hid for two zones.
	for eid in cm.enemy_db:
		var dt: String = String(cm.enemy_db[eid].get("dmg_type", "kinetic"))
		if dt != "kinetic" and cm.damage_type_tag(dt) == "KIN":
			_expect(false, "dmg_type '%s' (%s) has no tag and silently reads as kinetic" % [dt, eid])

	print("[DL] RESULT: %s (%d failure(s))" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _fire_exotic_weapon(cm, sm, exotic: String) -> Array:
	var tags: Array = []
	for ev in _fire_exotic_weapon_events(cm, sm, exotic):
		var t: String = String(ev.get("type", ""))
		if t == "dmg_shield" or t == "dmg_hull":
			var parts: PackedStringArray = String(ev.get("text", "")).split(" ")
			if parts.size() >= 2:
				tags.append(parts[parts.size() - 1])
	return tags


# Put a single pure-exotic weapon on the ship, point it at a Z11 target
# (warp_hardened, resist_cryo -0.25) and take one swing through the real
# _execute_player_attack path -- the label lives inside it.
func _fire_exotic_weapon_events(cm, sm, exotic: String) -> Array:
	# Spawn through the real path so current_enemy carries the computed fields
	# (def, resist_cryo, warp_hardened) rather than a hand-rolled dict.
	GameState.game_settings["z11_unlocked"] = true
	cm.current_zone_id = "the_threshold"
	cm.current_zone = cm.zones["the_threshold"]
	cm.target_enemy_id = "z11_warp_revenant"
	cm.spawn_enemy()
	cm.enemy_hp = 1.0e18            # never dies mid-measurement
	cm.enemy_max_hp = 1.0e18
	cm.enemy_shield = 1.0e18
	cm.enemy_max_shield = 1.0e18
	cm.in_combat = true
	cm.player_weapon_states.clear()
	cm.player_weapon_states.append({
		"name": "Probe " + exotic,
		"type": "cryo",
		"mid": "probe_" + exotic,
		"tier": 11,
		"rarity": 3,
		"exotic_type": exotic,
		"timer": 0.0,
		"interval": 1.0,
		"dmg_k": 0.0, "dmg_e": 0.0, "dmg_x": 0.0, "dmg_cryo": 50000.0,
		"slot_idx": 0,
		"energy_load": 0,
	})
	sm.current_hp = max(sm.current_hp, 1.0)
	cm.combat_events.clear()
	cm._execute_player_attack(0)
	return cm.combat_events.duplicate()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[DL] FAIL: %s" % msg)
		fails += 1
