extends SceneTree
## PHASE 4 — Progression & missions. The mission *chain* is audited separately
## (sim_mission_audit.gd); this checks the wider progression GRAPH a player climbs:
## research tree is an acyclic, fully-reachable DAG; every zone's gate (research or
## unlock-flag) is reachable and engine-driven; the XP curve is monotone and its
## inverse is exact; all content level-gates sit within the level cap; and every
## enemy is actually fightable in some zone or hazard (no orphan fights).

var gd
var gs
var errors: Array = []
var warns: Array = []

# Flags the engine sets in code to gate the post-research zones (z11 on the Z10
# boss kill, z12 on the Z11 boss kill). Zone unlock_flags must be one of these.
const ENGINE_SET_FLAGS := {"z11_unlocked": true, "z12_unlocked": true}

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func E(s): errors.append(s)
func W(s): warns.append(s)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	gd = root.get_node("GameData")
	gs = root.get_node("GameState")

	_check_research_acyclic()
	_check_research_reachable()
	_check_zone_gating()
	_check_xp_curve()
	_check_level_caps()
	_check_enemy_reachability()

	print("\n===== PHASE 4: PROGRESSION & MISSIONS =====")
	print("research=%d zones=%d enemies=%d hazards=%d gather=%d craft=%d MAX_LEVEL=%d" % [
		gd.RESEARCH.size(), gd.ZONES.size(), gd.ENEMIES.size(), gd.HAZARD_ZONES.size(),
		gd.GATHER.size(), gd.CRAFT.size(), gs.MAX_LEVEL])
	print("errors=%d  warnings=%d" % [errors.size(), warns.size()])
	if not warns.is_empty():
		print("\n--- WARNINGS (%d) ---" % warns.size())
		for w in warns: print("  ⚠ " + w)
	if not errors.is_empty():
		print("\n--- ERRORS (%d) ---" % errors.size())
		for e in errors: print("  ✗ " + e)
		print("\nPROGRESSION: FAIL")
		quit(1)
		return
	print("\nPROGRESSION: PASS")
	quit()

# Edges out of a tech: its parent plus every req_tech.
func _prereqs(tid: String) -> Array:
	var t: Dictionary = gd.RESEARCH[tid]
	var out := []
	var par = t.get("parent", "")
	if par != null and String(par) != "": out.append(String(par))
	for rt in t.get("req_tech", []):
		if String(rt) != "": out.append(String(rt))
	return out

# --- Research graph must be acyclic: a cycle in parent/req_tech edges would make
# every tech in it permanently un-unlockable. ---
func _check_research_acyclic() -> void:
	var state := {}   # tid -> 1 visiting, 2 done
	for tid in gd.RESEARCH:
		if not state.has(tid):
			_dfs_cycle(tid, state, [])

func _dfs_cycle(tid: String, state: Dictionary, stack: Array) -> void:
	if not gd.RESEARCH.has(tid):
		return
	state[tid] = 1
	stack.append(tid)
	for p in _prereqs(tid):
		if state.get(p, 0) == 1:
			E("RESEARCH cycle: %s -> %s (prereq loop)" % [tid, p])
		elif not state.has(p):
			_dfs_cycle(p, state, stack)
	stack.pop_back()
	state[tid] = 2

# --- Every tech must be reachable: a tech is researchable once its parent and all
# req_tech are researchable. requires_warp techs are reachable (warp itself is a
# reachable game state via zone_6_access). Fixpoint closure over the tech set. ---
func _check_research_reachable() -> void:
	var reachable := {}
	var changed := true
	while changed:
		changed = false
		for tid in gd.RESEARCH:
			if reachable.has(tid):
				continue
			var ok := true
			for p in _prereqs(tid):
				if not reachable.has(p):
					ok = false
					break
			if ok:
				reachable[tid] = true
				changed = true
	for tid in gd.RESEARCH:
		if not reachable.has(tid):
			E("RESEARCH %s is UNREACHABLE (prereq never satisfiable)" % tid)

# --- Zones: contiguous difficulty 1..N, each gate reachable. A research_req must
# be a real (and reachable) tech; an unlock_flag must be one the engine actually
# sets (otherwise the zone can never open). A zone needs at least one gate past #1. ---
func _check_zone_gating() -> void:
	var diffs := {}
	for z in gd.ZONES:
		var d: int = int(z.get("difficulty", 0))
		if diffs.has(d):
			E("ZONE difficulty %d duplicated (%s)" % [d, z.get("name", "")])
		diffs[d] = true
		var req: String = z.get("research_req", "")
		var flag: String = z.get("unlock_flag", "")
		if d > 1 and req == "" and flag == "":
			E("ZONE %s (diff %d) has no gate (free access past zone 1)" % [z.get("name", ""), d])
		if req != "" and not gd.RESEARCH.has(req):
			E("ZONE %s research_req '%s' is not a real tech" % [z.get("name", ""), req])
		if flag != "" and not ENGINE_SET_FLAGS.has(flag):
			E("ZONE %s unlock_flag '%s' is never set by the engine (unopenable)" % [z.get("name", ""), flag])
	# Difficulties must be contiguous 1..max so progression has no gap.
	var mx := 0
	for d in diffs: mx = maxi(mx, d)
	for i in range(1, mx + 1):
		if not diffs.has(i):
			E("ZONE difficulty gap: no zone at difficulty %d" % i)

# --- XP curve: strictly increasing through the cap, and level_of is its exact
# inverse at each boundary (off-by-one here mis-gates every level requirement). ---
func _check_xp_curve() -> void:
	var prev := -1
	for lvl in range(2, gs.MAX_LEVEL + 1):
		var x: int = gs.xp_for_level(lvl)
		if x <= prev:
			E("xp_for_level non-increasing at %d: %d <= %d" % [lvl, x, prev])
		prev = x
	# Inverse check at sampled boundaries: exactly xp_for_level(L) -> level L, and one
	# below -> L-1.
	var saved: Dictionary = gs.skills.duplicate(true)
	for L in [2, 10, 20, 50, 80, 99]:
		gs.skills["combat"] = gs.xp_for_level(L)
		if gs.level_of("combat") != L:
			E("level_of(xp_for_level(%d)) = %d, expected %d" % [L, gs.level_of("combat"), L])
		if L > 2:
			gs.skills["combat"] = gs.xp_for_level(L) - 1
			if gs.level_of("combat") != L - 1:
				E("level_of(xp_for_level(%d)-1) = %d, expected %d" % [L, gs.level_of("combat"), L - 1])
	gs.skills = saved

# --- Level gates must sit within the cap; content gated above MAX_LEVEL can never
# be reached. ---
func _check_level_caps() -> void:
	for gid in gd.GATHER:
		var lr: int = int(gd.GATHER[gid].get("level_req", 1))
		if lr < 1 or lr > gs.MAX_LEVEL:
			E("GATHER %s level_req %d outside [1, %d]" % [gid, lr, gs.MAX_LEVEL])
	for cid in gd.CRAFT:
		var lr: int = int(gd.CRAFT[cid].get("level_req", 1))
		if lr < 1 or lr > gs.MAX_LEVEL:
			E("CRAFT %s level_req %d outside [1, %d]" % [cid, lr, gs.MAX_LEVEL])

# --- Every enemy must be fightable somewhere: a zone roster, or a hazard pool /
# elite / boss. An orphan enemy is dead content. ---
func _check_enemy_reachability() -> void:
	var reachable := {}
	for z in gd.ZONES:
		for eid in z.get("enemies", []):
			reachable[eid] = true
	for hid in gd.HAZARD_ZONES:
		var h: Dictionary = gd.HAZARD_ZONES[hid]
		for eid in h.get("enemy_pool", []):
			reachable[eid] = true
		var el: String = h.get("elite_enemy", "")
		if el != "": reachable[el] = true
		var bo: String = h.get("boss_enemy", "")
		if bo != "": reachable[bo] = true
	for eid in gd.ENEMIES:
		if not reachable.has(eid):
			W("ENEMY %s is in no zone or hazard (unfightable / dead content)" % eid)
