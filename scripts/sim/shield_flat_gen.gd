extends Node
# ============================================================================
# SHIELD FLATTEN GENERATOR — emits FLATTEN_SHIELD_CALIB.
#
# The v154 flatten sets the PLAYER's shield weight to 1.0 on all channels and
# multiplies shield damage by the same (1 - amped resist) the hull half uses.
# Pre-v153 the player's shield weights were KIN 0.5 / NRG 1.5 / EXP 1.1 with NO
# resist term. So for a given enemy, on that enemy's OWN WEAK channel w:
#
#     d_shield(enemy) = (1.0 * (1 - amp(resist_w))) / SW_OLD[w]
#
# Scaling max_shield by d_shield leaves the weak channel's shield-phase TTK
# EXACTLY where it was, and — because the e3/e4 repair pulse heals
# enemy_max_shield * pct — leaves the repair-pulse race exactly where it was too.
#
# Reads resists LIVE from combat_manager.enemy_db, so it is correct for whatever
# resist assignment is currently authored. Emits NO rows for bosses, for
# warp_hardened (Z11) enemies, for phased NG+ bosses, or for enemies with no
# shield pool.
#
#   Godot --headless --path <root> res://scenes/shield_flat_gen.tscn
# ============================================================================

const SW_OLD := {"kinetic": 0.5, "energy": 1.5, "explosive": 1.1}

func _ready() -> void:
	var cm = GameState.combat_manager
	GameState.set_process(false)
	print("[SFG] ===== FLATTEN_SHIELD_CALIB GENERATOR =====")
	print("[SFG] d_shield = (1 - amp(resist_weak)) / SW_OLD[weak];  SW_OLD = K 0.5 / E 1.5 / X 1.1")
	print("[SFG] enemy | zone | weak | resist_weak | amp | d_shield | live max_shield")

	var out: Array = []
	var skipped: Array = []
	var ids: Array = cm.enemy_db.keys()
	ids.sort()
	for eid in ids:
		var sid := String(eid)
		var e: Dictionary = cm.enemy_db[sid]
		var rk: float = float(e.get("resist_k", 0.0))
		var re: float = float(e.get("resist_e", 0.0))
		var rx: float = float(e.get("resist_x", 0.0))
		var st: Dictionary = e.get("stats", {})
		var shd: float = float(st.get("max_shield", 0))
		var gated: bool = bool(e.get("warp_hardened", false)) or not (e.get("phases", []) as Array).is_empty()
		var isb: bool = bool(e.get("is_boss", false))
		if shd <= 0.0:
			continue
		if rk == 0.0 and re == 0.0 and rx == 0.0:
			skipped.append("%s (no triangle)" % sid)
			continue
		if gated:
			skipped.append("%s (cryo/phase gated)" % sid)
			continue
		if isb:
			skipped.append("%s (boss - deliberate)" % sid)
			continue
		var w := _weak_of(rk, re, rx)
		var rw: float = rk
		if w == "energy":
			rw = re
		elif w == "explosive":
			rw = rx
		var a := _amp(rw)
		var d: float = (1.0 - a) / float(SW_OLD[w])
		print("[SFG] %-26s z%-2d W=%-3s  r %+.2f  amp %+.4f  d %.4f  shd %10.0f" % [
			sid, int(e.get("zone", 0)), w.substr(0, 3).to_upper(), rw, a, d, shd])
		if absf(d - 1.0) > 0.0005:
			out.append("\t\"%s\": {\"max_shield\": %.4f}," % [sid, d])

	print("")
	print("[SFG] --- SKIPPED (%d) ---" % skipped.size())
	for s in skipped:
		print("[SFG]   " + String(s))
	print("")
	print("[SFG] --- TABLE: %d rows ---" % out.size())
	for l in out:
		print("[SFG] " + String(l))
	get_tree().quit(0)


func _amp(r: float) -> float:
	if r > 0.0:
		return clamp(r * 1.78, 0.0, 0.80)
	return clamp(r, -0.40, 0.0)

func _weak_of(rk: float, re: float, rx: float) -> String:
	if rk <= re and rk <= rx:
		return "kinetic"
	if re <= rk and re <= rx:
		return "energy"
	return "explosive"
