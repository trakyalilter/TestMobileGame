extends SceneTree
## Audit of the combat tables and everything that drops from them.
##
## sim_data_integrity proves loot symbols RESOLVE and sim_combat_math proves the
## damage formulas hold. Neither asks whether the content is COHERENT: whether a
## zone gate's boss core actually drops, whether a hardened enemy has a weapon
## that can hurt it, or whether a drop pool can physically yield an item.
##
## That last one is a live hazard: the v136 weighted picker gives batteries
## weight 0, so a pool of nothing but zero-weight slots silently drops NOTHING
## rather than erroring.

var errs: Array = []
var warns: Array = []

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func E(s: String) -> void: errs.append(s)
func W(s: String) -> void: warns.append(s)

## Effective HP of an enemy as the player meets it — hull plus shield.
func _ehp(e: Dictionary) -> float:
	return float(e.get("hp", 0)) + float(e.get("max_shield", 0))

func _run() -> void:
	var gs = root.get_node("GameState")
	var gd = root.get_node("GameData")
	print("enemies=%d  zones=%d  modules=%d" % [gd.ENEMIES.size(), gd.ZONES.size(), gd.MODULES.size()])

	# ---------- A. zone <-> enemy agreement ----------
	var listed := {}
	var zone_of := {}
	for z in gd.ZONES:
		var zd: Dictionary = z
		var zdiff := int(zd.get("difficulty", 0))
		for eid in zd.get("enemies", []):
			var id := String(eid)
			if not gd.ENEMIES.has(id):
				E("zone '%s' lists enemy '%s' which does not exist" % [zd.get("id", "?"), id])
				continue
			listed[id] = true
			zone_of[id] = zdiff
			var ez := int((gd.ENEMIES[id] as Dictionary).get("zone", 0))
			if ez != zdiff:
				W("enemy '%s' is tagged zone %d but listed in a difficulty-%d sector" % [id, ez, zdiff])
	# Hazard zones are a SEPARATE content track: their enemies are reached through
	# the gauntlet, never listed in a sector, and their stats are tuned against
	# wave pacing rather than the sector ladder. Collect them so neither the
	# reachability warning nor the difficulty curve mistakes them for trash.
	var hazard_enemies := {}
	for hid in gd.HAZARD_ZONES:
		var hz: Dictionary = gd.HAZARD_ZONES[hid]
		var ids: Array = (hz.get("enemy_pool", []) as Array).duplicate()
		ids.append(hz.get("elite_enemy", ""))
		ids.append(hz.get("boss_enemy", ""))
		for eid in ids:
			var id2 := String(eid)
			if id2 == "":
				continue
			if not gd.ENEMIES.has(id2):
				E("hazard zone '%s' references enemy '%s' which does not exist" % [hid, id2])
			hazard_enemies[id2] = true
	for eid in gd.ENEMIES:
		if not listed.has(String(eid)) and not hazard_enemies.has(String(eid)):
			W("enemy '%s' is in no sector list and no hazard pool — unreachable content" % eid)

	# ---------- B. stat sanity ----------
	for eid in gd.ENEMIES:
		var e: Dictionary = gd.ENEMIES[eid]
		if float(e.get("hp", 0)) <= 0.0:
			E("enemy '%s' has no HP" % eid)
		if float(e.get("interval", 0)) <= 0.0:
			E("enemy '%s' has a non-positive attack interval (divide-by-zero risk)" % eid)
		for rk in ["resist_k", "resist_e", "resist_x", "resist_cryo"]:
			var rv := float(e.get(rk, 0.0))
			if rv < -1.0 or rv > 1.0:
				E("enemy '%s' %s=%.2f is outside [-1, 1]" % [eid, rk, rv])

	# ---------- C. drop pools must be able to yield something ----------
	# _pick_weighted_base sums MODULE_DROP_WEIGHTS over the pool. A pool whose
	# every entry weighs 0 returns "" and drops nothing, forever, silently.
	var pools_checked := 0
	for eid in gd.ENEMIES:
		var e: Dictionary = gd.ENEMIES[eid]
		var pool: Array = e.get("drop_pool", [])
		if pool.is_empty():
			continue
		pools_checked += 1
		var total := 0
		for bid in pool:
			var b := String(bid)
			if not gd.MODULES.has(b):
				E("enemy '%s' drop pool names '%s', not a real module" % [eid, b])
				continue
			total += int(gs.MODULE_DROP_WEIGHTS.get(String((gd.MODULES[b] as Dictionary).get("slot", "")), 4))
		if total <= 0:
			E("enemy '%s' has a drop pool that can never yield an item (every slot is weight 0)" % eid)

	print("drop pools checked: %d" % pools_checked)

	# ---------- D. boss cores must actually drop ----------
	# A zone gate asks for the previous sector's core. If no boss drops it, the
	# gate is uncrossable and the whole run stops there.
	var core_source := {}
	for eid in gd.ENEMIES:
		var e: Dictionary = gd.ENEMIES[eid]
		var core := String(e.get("boss_core", ""))
		if core != "":
			core_source[core] = String(eid)
		for row in e.get("loot", []):
			if String(row[0]).ends_with("_Core"):
				core_source[String(row[0])] = String(eid)
	var gates := 0
	for tid in gd.RESEARCH:
		for sym in (gd.RESEARCH[tid] as Dictionary).get("items", {}):
			var s := String(sym)
			if not s.ends_with("_Core"):
				continue
			gates += 1
			if not core_source.has(s):
				E("research '%s' needs '%s', which no enemy drops — the gate cannot be crossed" % [tid, s])
	print("core-gated techs verified: %d (cores dropped by %d enemies)" % [gates, core_source.size()])

	# ---------- E. hardened / phased enemies need a usable counter ----------
	# Warp-hardened cuts conventional damage x0.02; phases gate on an exotic
	# channel. Both are unbeatable unless a weapon of that channel exists.
	var exotic_weapons := {}
	for mid in gd.MODULES:
		var m: Dictionary = gd.MODULES[mid]
		var st: Dictionary = m.get("stats", {})
		if float(st.get("atk_cryo", 0)) > 0.0:
			exotic_weapons[String(st.get("exotic_element", m.get("exotic_type", "cryo")))] = true
	var hardened := 0
	for eid in gd.ENEMIES:
		var e: Dictionary = gd.ENEMIES[eid]
		if bool(e.get("warp_hardened", false)) or not (e.get("phases", []) as Array).is_empty():
			hardened += 1
		if bool(e.get("warp_hardened", false)) and not exotic_weapons.has("cryo"):
			E("enemy '%s' is warp-hardened but no Cryo weapon exists to breach it" % eid)
		for ph in e.get("phases", []):
			if not exotic_weapons.has(String(ph)):
				E("enemy '%s' has a '%s' phase but no weapon of that channel exists" % [eid, ph])

	print("hardened/phased enemies checked: %d (exotic channels available: %s)" % [hardened, str(exotic_weapons.keys())])

	# ---------- F. loot row shape and plausibility ----------
	var rows := 0
	for eid in gd.ENEMIES:
		var e: Dictionary = gd.ENEMIES[eid]
		for key in ["loot", "rare_loot"]:
			for row in e.get(key, []):
				rows += 1
				if (row as Array).size() < 4:
					E("enemy '%s' %s row %s is malformed" % [eid, key, str(row)])
					continue
				var sym := String(row[0])
				var chance := float(row[1])
				var lo := float(row[2])
				var hi := float(row[3])
				if sym != "credits" and not gd.RESOURCES.has(sym) and not gd.MODULES.has(sym) and not gd.SET_MODULES.has(sym):
					E("enemy '%s' drops '%s', which is not a resource or module" % [eid, sym])
				if chance <= 0.0 or chance > 1.0:
					E("enemy '%s' drop '%s' has chance %.3f (must be >0 and <=1)" % [eid, sym, chance])
				if lo > hi:
					E("enemy '%s' drop '%s' has min %.0f > max %.0f" % [eid, sym, lo, hi])
				if lo < 0.0:
					E("enemy '%s' drop '%s' has a negative minimum" % [eid, sym])
	print("loot rows checked: %d" % rows)

	# ---------- G. difficulty must climb with the sector ----------
	# Compare each sector's toughest trash against the previous sector's. A dip
	# means a later zone is easier than the one gating it.
	var by_zone := {}
	for eid in gd.ENEMIES:
		var e: Dictionary = gd.ENEMIES[eid]
		if bool(e.get("is_boss", false)) or hazard_enemies.has(String(eid)):
			continue      # bosses spike by design; hazard waves are their own track
		var z := int(e.get("zone", 0))
		by_zone[z] = maxf(float(by_zone.get(z, 0.0)), _ehp(e))
	var zones_sorted: Array = by_zone.keys()
	zones_sorted.sort()
	var prev := 0.0
	var prev_z := 0
	for z in zones_sorted:
		var cur := float(by_zone[z])
		if prev > 0.0 and cur < prev:
			W("[curve] sector %d's toughest trash (%s EHP) is weaker than sector %d's (%s EHP)"
				% [z, gd.fmt(int(cur)), prev_z, gd.fmt(int(prev))])
		prev = cur
		prev_z = int(z)

	# ---------- report ----------
	print("")
	if errs.is_empty():
		print("ERRORS: none")
	else:
		print("--- ERRORS (%d) ---" % errs.size())
		for e in errs:
			print("  x %s" % e)
	if not warns.is_empty():
		print("--- WARNINGS (%d) ---" % warns.size())
		for w in warns:
			print("  ! %s" % w)
	print("COMBAT_LOOT_AUDIT: %s" % ("FAIL" if not errs.is_empty() else "PASS"))
	quit()
