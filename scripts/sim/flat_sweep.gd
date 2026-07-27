extends Node
# ============================================================================
# FLATTEN SWEEP — choose the SINGLE (shield_weight, armour_divisor, hull_coef)
# that replaces the per-channel triple, minimising TTK disturbance.
#
#   today   hull = atk_c * COEF[c] * af(ARMD[c])          af(f)=max(0.2, k/(a*f+k))
#   new     hull = atk_c * C      * af(F)
#   d(c)  = C*af(F) / (COEF[c]*af(ARMD[c]))     <- hull DPS ratio, per enemy
#   shield is UNCHANGED by this edit (no armour, no coefficient there).
#
# Trash can be made exact with an hp*d row in CHANNEL_SWAP_CALIB (shield side
# needs nothing). Bosses carry no calib rows, so their TTK moves by
#   ttk_ratio = (1-share_h) + share_h/d
# That is the binding constraint. share_h is gear-independent:
#   share_h = (hp/(COEF*af)) / (max_shield + hp/(COEF*af))
#
#   Godot --headless --path <root> res://scenes/flat_sweep.tscn
# ============================================================================

const SUFFIX := {"kinetic": "kinetic", "energy": "energy", "explosive": "missile"}
const CH := ["kinetic", "energy", "explosive"]
const COEF := {"kinetic": 1.2, "energy": 0.9, "explosive": 1.0}
const ARMD := {"kinetic": 1.0, "energy": 0.7, "explosive": 0.2}
const VALIDATE_SAMPLES := 6000

var rows: Array = []          # one dict per enemy
var patk: Dictionary = {}     # tier -> chan -> dps

func _ready() -> void:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	var rm = GameState.research_manager
	GameState.set_process(false)

	# ---- 1. player per-channel throughput -----------------------------------
	print("[FS] === PLAYER PER-CHANNEL ATK (clean Common tier-N, band ammo) ===")
	print("[FS] tier |     KIN |     NRG |     EXP | normalised")
	for tz in range(1, 11):
		patk[tz] = {}
		for ch in CH:
			patk[tz][ch] = _player_atk(sm, cm, rm, tz, String(ch))
		var bk: float = float(patk[tz]["kinetic"])
		print("[FS] %4d | %7.1f | %7.1f | %7.1f | 1.000 : %.3f : %.3f" % [
			tz, bk, patk[tz]["energy"], patk[tz]["explosive"],
			float(patk[tz]["energy"]) / bk, float(patk[tz]["explosive"]) / bk])

	# ---- 2. enemy table ------------------------------------------------------
	print("")
	print("[FS] === ENEMY TABLE (post-rebase, post-calib, post-steepening) ===")
	print("[FS] enemy | role | z | def_eff | k | rho | hp | shield | weak | share_hull")
	for tz in range(1, 16):
		var zid := ""
		for z in cm.zones:
			if int(cm.zones[z].get("difficulty", 0)) == tz:
				zid = String(z)
				break
		if zid == "":
			continue
		var roster: Array = cm.zones[zid].get("enemies", [])
		for i in range(roster.size()):
			var eid := String(roster[i])
			var e: Dictionary = cm.enemy_db.get(eid, {})
			if e.is_empty():
				continue
			var rk: float = float(e.get("resist_k", 0.0))
			var re: float = float(e.get("resist_e", 0.0))
			var rx: float = float(e.get("resist_x", 0.0))
			var gated: bool = bool(e.get("warp_hardened", false)) or not (e.get("phases", []) as Array).is_empty()
			if not gated and rk == 0.0 and re == 0.0 and rx == 0.0:
				continue
			var isb: bool = bool(e.get("is_boss", false))
			var st: Dictionary = e.get("stats", {})
			# zone steepening: skipped for warp_hardened and phased enemies
			var steep: bool = (tz >= 3) and not gated
			var armor: float = float(st.get("def", 0)) * (1.5 if steep else 1.0)
			var hp: float = float(st.get("hp", 0)) * (min(1.60, 1.20 + 0.08 * float(tz - 3)) if steep else 1.0)
			var shd: float = float(st.get("max_shield", 0))
			var kpoly: float = 40.0 + 30.0 * pow(float(tz), 1.3)
			var k: float = maxf(kpoly, 0.7 * armor)
			var w := _weak_of(rk, re, rx)
			if gated:
				w = "cryo"
			var af := {}
			var ca := {}
			for ch in ["kinetic", "energy", "explosive", "cryo"]:
				var frac: float = 0.5 if ch == "cryo" else float(ARMD[ch])
				var cf: float = 1.0 if ch == "cryo" else float(COEF[ch])
				var f: float = maxf(0.20, 1.0 - (armor * frac) / (armor * frac + k))
				af[ch] = f
				ca[ch] = cf * f
			var t_h: float = hp / float(ca[w])
			var share_h: float = t_h / (shd + t_h)
			var row := {
				"id": eid, "role": ("BOSS" if isb else ("e%d" % (i + 1))), "z": tz,
				"boss": isb, "armor": armor, "k": k, "rho": armor / k, "gated": gated,
				"hp": hp, "shd": shd, "weak": w, "af": af, "ca": ca, "share_h": share_h,
				"zid": zid,
			}
			rows.append(row)
			print("[FS] %-26s %-4s z%-2d def %8.0f  k %8.0f  rho %.3f  hp %10.0f  shd %8.0f  W=%-3s  share_h %.3f" % [
				eid, row["role"], tz, armor, k, armor / k, hp, shd, w.substr(0, 3).to_upper(), share_h])

	# ---- 3. validate the closed form against the REAL resolve_damage ---------
	# READ THIS BEFORE BELIEVING THE NUMBER. The closed form models the PRE-FLATTEN
	# pipeline (per-channel COEF/ARMD above) — that is the whole point, it is the
	# baseline the hp rows are computed against. So this section only reads ~0%
	# error while resolve_damage still HAS the per-channel pipeline. Once
	# CHANNEL_ARMOR_DIV / CHANNEL_HULL_COEF are live, resolve_damage returns
	# A*C*af(F)*(1-r) and the closed form returns A*COEF*af(ARMD)*(1-r), so this
	# section necessarily reports max|d - 1| — i.e. it turns into a SECOND,
	# independent check that the shipped flatten equals the emitted table. Post-
	# flatten the expected worst error is max|d-1| = 0.2963 (the 1.2963 rows).
	print("")
	print("[FS] === VALIDATION: closed form vs real resolve_damage (hull, shield=0) ===")
	var worst: float = 0.0
	var worst_id := ""
	var nval: int = 0
	for row in rows:
		if bool(row["gated"]):
			continue
		var e: Dictionary = cm.enemy_db.get(String(row["id"]), {})
		cm.current_zone_id = String(row["zid"])
		cm.current_zone = cm.zones[String(row["zid"])]
		cm.current_enemy = {
			"resist_k": e.get("resist_k", 0.0), "resist_e": e.get("resist_e", 0.0),
			"resist_x": e.get("resist_x", 0.0), "resist_cryo": 0.0,
			"warp_hardened": false, "phases": [], "phase_cut": 0.15,
		}
		cm.enemy_hp = 1000
		cm.enemy_max_hp = 2000   # 0.5 -> neither dmg_healthy nor dmg_injured band
		for ch in CH:
			var A: float = 1.0e7
			var ak: float = A if ch == "kinetic" else 0.0
			var ae: float = A if ch == "energy" else 0.0
			var ax: float = A if ch == "explosive" else 0.0
			var tot: float = 0.0
			for s in range(VALIDATE_SAMPLES):
				var r: Array = cm.resolve_damage(ak, ae, ax, 0, float(row["armor"]), int(row["z"]), 0.0, true)
				tot += float(r[1])
			var meas: float = tot / float(VALIDATE_SAMPLES)
			var rr: float = _amp(float(e.get("resist_%s" % _rkey(ch), 0.0)))
			var pred: float = A * float(COEF[ch]) * float((row["af"] as Dictionary)[ch]) * (1.0 - rr)
			var err: float = absf(meas - pred) / pred
			nval += 1
			if err > worst:
				worst = err
				worst_id = "%s/%s" % [row["id"], ch]
	print("[FS] validated %d (enemy,channel) pairs. WORST relative error %.4f%%  (%s)" % [nval, worst * 100.0, worst_id])

	# ---- 4. the sweep --------------------------------------------------------
	print("")
	print("[FS] === SWEEP: F = armour divisor fraction, C = hull coefficient ===")
	print("[FS] boss_rms   = RMS ln(ttk_new/ttk_old) over the 9 UNCOMPENSATED zone bosses, weak channel")
	print("[FS] boss_max   = worst single boss |ttk change|")
	print("[FS] trash_rms  = RMS ln(hp calib factor) over the 36 trash cells (churn, TTK stays exact)")
	print("[FS] score      = 0.75*boss_rms + 0.25*trash_rms")
	print("[FS]     F |     C | boss_rms | boss_max | trash_rms |  score")
	var best: Dictionary = {}
	var f: float = 0.20
	while f <= 1.001:
		var c: float = 0.80
		while c <= 1.401:
			var m: Dictionary = _score(f, c)
			if best.is_empty() or float(m["score"]) < float(best["score"]):
				best = m
				best["F"] = f
				best["C"] = c
			c += 0.005
		f += 0.01
	# print a readable grid around the optimum
	for ff in [0.20, 0.30, 0.40, 0.50, 0.55, 0.58, 0.60, 0.62, 0.65, 0.70, 0.80, 1.00]:
		var bc: Dictionary = {}
		var bcv: float = 0.0
		var cc: float = 0.80
		while cc <= 1.401:
			var m2: Dictionary = _score(float(ff), cc)
			if bc.is_empty() or float(m2["score"]) < float(bc["score"]):
				bc = m2
				bcv = cc
			cc += 0.005
		print("[FS] %5.2f | %5.3f | %8.4f | %+7.1f%% | %9.4f | %6.4f    (C optimised for this F)" % [
			ff, bcv, bc["boss_rms"], float(bc["boss_max"]) * 100.0, bc["trash_rms"], bc["score"]])
	print("[FS] ---- unconstrained optimum: F = %.3f  C = %.3f  score %.4f" % [best["F"], best["C"], best["score"]])

	# fixed-C slices at the chosen F
	print("")
	print("[FS] === C slice at F = 0.60 ===")
	for cc2 in [0.95, 1.00, 1.02, 1.026, 1.03, 1.05, 1.10]:
		var m3: Dictionary = _score(0.60, float(cc2))
		print("[FS] C %5.3f | boss_rms %.4f | boss_max %+.1f%% | trash_rms %.4f | score %.4f" % [
			cc2, m3["boss_rms"], float(m3["boss_max"]) * 100.0, m3["trash_rms"], m3["score"]])

	# ---- 5. per-cell detail for the recommended triple ----------------------
	print("")
	print("[FS] === C slice at F = 0.50 (= today's cryo divisor) ===")
	for cc3 in [0.95, 0.955, 1.00, 1.026, 1.05]:
		var m4: Dictionary = _score(0.50, float(cc3))
		print("[FS] C %5.3f | boss_rms %.4f | boss_max %+.1f%% | trash_rms %.4f | score %.4f" % [
			cc3, m4["boss_rms"], float(m4["boss_max"]) * 100.0, m4["trash_rms"], m4["score"]])

	_detail(0.50, 1.00, true)

	# ---- 6. the triangle proof ----------------------------------------------
	print("")
	print("[FS] === TRIANGLE PROOF: post-flatten channel throughput = A_c * (1 - amp(resist_c)) ===")
	var A: Dictionary = {"kinetic": 1.0, "energy": float(patk[10]["energy"]) / float(patk[10]["kinetic"]),
		"explosive": float(patk[10]["explosive"]) / float(patk[10]["kinetic"])}
	print("[FS] A (tier-normalised) KIN %.3f  NRG %.3f  EXP %.3f" % [A["kinetic"], A["energy"], A["explosive"]])
	for wm in [0.30, 0.40]:
		for w in CH:
			# the shipped triangle: weak = w, resisted = stronger of the other two
			# in the order EXP > NRG > KIN, natural = the third.
			var nat := ""
			var res := ""
			if w == "kinetic":
				nat = "energy"
				res = "explosive"
			elif w == "energy":
				nat = "kinetic"
				res = "explosive"
			else:
				nat = "kinetic"
				res = "energy"
			var tw: float = float(A[w]) * (1.0 + wm)
			var tn: float = float(A[nat]) * 1.0
			var tr: float = float(A[res]) * (1.0 - _amp(0.37))
			print("[FS] weak=%-3s (x%.2f)  W %-3s %.4f  |  N %-3s %.4f  |  R %-3s %.4f   ->  W/N %.4f  N/R %.4f  %s" % [
				w.substr(0, 3).to_upper(), 1.0 + wm, w.substr(0, 3).to_upper(), tw,
				nat.substr(0, 3).to_upper(), tn, res.substr(0, 3).to_upper(), tr,
				tw / tn, tn / tr, ("OK" if (tw > tn and tn > tr) else "*** FAILS ***")])
	print("[FS] --- alternative assignment: put RESISTED on the strongest remaining channel ---")
	for wm2 in [0.30, 0.40]:
		for w3 in CH:
			var others: Array = []
			for ch in CH:
				if String(ch) != w3:
					others.append(String(ch))
			var s0: String = String(others[0])
			var s1: String = String(others[1])
			var res2: String = s0 if float(A[s0]) >= float(A[s1]) else s1
			var nat2: String = s1 if res2 == s0 else s0
			var tw2: float = float(A[w3]) * (1.0 + wm2)
			var tn2: float = float(A[nat2])
			var tr2: float = float(A[res2]) * (1.0 - _amp(0.37))
			print("[FS] weak=%-3s (x%.2f)  W %.4f | N %-3s %.4f | R %-3s %.4f  ->  W/N %.4f  N/R %.4f  %s" % [
				w3.substr(0, 3).to_upper(), 1.0 + wm2, tw2, nat2.substr(0, 3).to_upper(), tn2,
				res2.substr(0, 3).to_upper(), tr2, tw2 / tn2, tn2 / tr2,
				("OK" if (tw2 > tn2 and tn2 > tr2) else "*** FAILS ***")])
	# ---- 7. enemy-side residual if we flatten BOTH directions ----------------
	print("")
	print("[FS] === ENEMY SIDE: what a BOTH-DIRECTION flatten would cost ===")
	print("[FS] fold the old hull coefficients into ENEMY_*_ATK_COMP; the only residual is")
	print("[FS] the armour divisor acting on the PLAYER's own (small) defense.")
	print("[FS] tier | player def | k | rho_p | af1.0/af0.7/af0.2 -> af%.2f | incoming dmg change KIN/NRG/EXP" % 0.50)
	for tz2 in range(1, 11):
		_player_atk(sm, cm, rm, tz2, "kinetic")
		var pdef: float = float(sm.defense)
		var kp: float = maxf(40.0 + 30.0 * pow(float(tz2), 1.3), 0.7 * pdef)
		var a1: float = maxf(0.20, 1.0 - (pdef * 1.0) / (pdef * 1.0 + kp))
		var a7: float = maxf(0.20, 1.0 - (pdef * 0.7) / (pdef * 0.7 + kp))
		var a2: float = maxf(0.20, 1.0 - (pdef * 0.2) / (pdef * 0.2 + kp))
		var an: float = maxf(0.20, 1.0 - (pdef * 0.5) / (pdef * 0.5 + kp))
		print("[FS] %4d | %10.0f | %8.0f | %.3f | %.4f/%.4f/%.4f -> %.4f | %+6.2f%% %+6.2f%% %+6.2f%%" % [
			tz2, pdef, kp, pdef / kp, a1, a7, a2, an,
			(an / a1 - 1.0) * 100.0, (an / a7 - 1.0) * 100.0, (an / a2 - 1.0) * 100.0])

	# ---- 8. enemies not on any zone roster (hazard pools etc.) --------------
	print("")
	print("[FS] === ENEMIES NOT ON A ZONE ROSTER (hazard pools) ===")
	var seen: Dictionary = {}
	for row in rows:
		seen[String(row["id"])] = true
	for eid2 in cm.enemy_db:
		var sid := String(eid2)
		if seen.has(sid):
			continue
		var e2: Dictionary = cm.enemy_db[sid]
		var rk2: float = float(e2.get("resist_k", 0.0))
		var re2: float = float(e2.get("resist_e", 0.0))
		var rx2: float = float(e2.get("resist_x", 0.0))
		if rk2 == 0.0 and re2 == 0.0 and rx2 == 0.0:
			continue
		var z2: int = int(e2.get("zone", 1))
		var st2: Dictionary = e2.get("stats", {})
		var steep2: bool = z2 >= 3
		var arm2: float = float(st2.get("def", 0)) * (1.5 if steep2 else 1.0)
		var k2: float = maxf(40.0 + 30.0 * pow(float(z2), 1.3), 0.7 * arm2)
		var w5 := _weak_of(rk2, re2, rx2)
		var frac5: float = float(ARMD[w5])
		var afo: float = maxf(0.20, 1.0 - (arm2 * frac5) / (arm2 * frac5 + k2))
		var afn5: float = maxf(0.20, 1.0 - (arm2 * 0.50) / (arm2 * 0.50 + k2))
		var d5: float = (1.0 * afn5) / (float(COEF[w5]) * afo)
		print("[FS] %-26s z%-2d W=%-3s  hp row x%.4f" % [sid, z2, w5.substr(0, 3).to_upper(), d5])

	print("[FS] --- adaptive_grid (z10 boss, +0.15 RAW to the channel you use, cap) ---")
	for w4 in CH:
		var natx := "energy" if w4 == "kinetic" else "kinetic"
		# weak channel ramps -0.40 -> -0.25 ; natural ramps 0.00 -> +0.15 (amped 0.267)
		var w_end: float = float(A[w4]) * (1.0 - _amp(-0.40 + 0.15))
		var w_avg: float = float(A[w4]) * 0.5 * ((1.0 - _amp(-0.40)) + (1.0 - _amp(-0.25)))
		var n_end: float = float(A[natx]) * (1.0 - _amp(0.15))
		var n_avg: float = float(A[natx]) * 0.5 * ((1.0 - _amp(0.0)) + (1.0 - _amp(0.15)))
		print("[FS] weak=%-3s  W end %.4f avg %.4f | N(%s) end %.4f avg %.4f  -> avg W/N %.3f  %s" % [
			w4.substr(0, 3).to_upper(), w_end, w_avg, natx.substr(0, 3).to_upper(), n_end, n_avg,
			w_avg / n_avg, ("OK" if w_avg > n_avg else "*** FAILS ***")])

	get_tree().quit(0)


func _score(F: float, C: float) -> Dictionary:
	var bs: float = 0.0
	var bn: int = 0
	var bmax: float = 0.0
	var ts: float = 0.0
	var tn: int = 0
	for row in rows:
		if bool(row["gated"]) or int(row["z"]) < 2 or int(row["z"]) > 10:
			continue
		var w := String(row["weak"])
		var afn: float = maxf(0.20, 1.0 - (float(row["armor"]) * F) / (float(row["armor"]) * F + float(row["k"])))
		var d: float = (C * afn) / float((row["ca"] as Dictionary)[w])
		if bool(row["boss"]):
			var sh: float = float(row["share_h"])
			var ttk: float = (1.0 - sh) + sh / d
			bs += log(ttk) * log(ttk)
			bn += 1
			bmax = maxf(bmax, absf(ttk - 1.0))
		else:
			ts += log(d) * log(d)
			tn += 1
	var brms: float = sqrt(bs / maxf(1.0, float(bn)))
	var trms: float = sqrt(ts / maxf(1.0, float(tn)))
	return {"boss_rms": brms, "boss_max": bmax, "trash_rms": trms, "score": 0.75 * brms + 0.25 * trms}


func _detail(F: float, C: float, cryo_joins: bool = true) -> void:
	print("")
	print("[FS] ===== DETAIL  F = %.3f   C = %.3f   shield weight 1.0   cryo_joins=%s =====" % [F, C, str(cryo_joins)])
	print("[FS] --- A. K/E/X cells: UNCOMPENSATED ttk on the weak channel, and the hp row that zeroes it ---")
	var calib: Array = []
	var nrow: int = 0
	for row in rows:
		if bool(row["gated"]):
			continue
		var afn: float = maxf(0.20, 1.0 - (float(row["armor"]) * F) / (float(row["armor"]) * F + float(row["k"])))
		var dk: float = (C * afn) / float((row["ca"] as Dictionary)["kinetic"])
		var de: float = (C * afn) / float((row["ca"] as Dictionary)["energy"])
		var dx: float = (C * afn) / float((row["ca"] as Dictionary)["explosive"])
		var w := String(row["weak"])
		var dw: float = (C * afn) / float((row["ca"] as Dictionary)[w])
		var sh: float = float(row["share_h"])
		var ttk: float = (1.0 - sh) + sh / dw
		print("[FS] %-26s %-4s W=%-3s  d %.3f/%.3f/%.3f   ttk_raw %+7.1f%%   hp x%.4f" % [
			row["id"], row["role"], w.substr(0, 3).to_upper(), dk, de, dx, (ttk - 1.0) * 100.0, dw])
		if absf(dw - 1.0) > 0.005:
			calib.append("\t\"%s\": {\"hp\": %.4f}," % [row["id"], dw])
			nrow += 1

	print("[FS] --- B. AFTER the hp row: per-channel ttk vs today (weak is EXACT by construction) ---")
	print("[FS] enemy | role | weak | ttk KIN | ttk NRG | ttk EXP")
	for row in rows:
		if bool(row["gated"]):
			continue
		var w2 := String(row["weak"])
		var denom: float = float((row["ca"] as Dictionary)[w2])
		var out: Array = []
		for ch in CH:
			var cac: float = float((row["ca"] as Dictionary)[ch])
			var R: float = cac / denom                      # hull-phase stretch
			var th: float = float(row["hp"]) / cac          # this channel's own hull time
			var shc: float = th / (float(row["shd"]) + th)
			out.append(((1.0 - shc) + shc * R - 1.0) * 100.0)
		print("[FS] %-26s %-4s W=%-3s  %+7.1f%% %+7.1f%% %+7.1f%%" % [
			row["id"], row["role"], w2.substr(0, 3).to_upper(), out[0], out[1], out[2]])

	print("[FS] --- C. CRYO-GATED cells (Z11 warp_hardened + NG+ phased bosses) ---")
	for row in rows:
		if not bool(row["gated"]):
			continue
		var afc_old: float = float((row["ca"] as Dictionary)["cryo"])
		var afn2: float = maxf(0.20, 1.0 - (float(row["armor"]) * F) / (float(row["armor"]) * F + float(row["k"])))
		var dc: float = ((C * afn2) / afc_old) if cryo_joins else 1.0
		var sh2: float = float(row["share_h"])
		var ttk2: float = (1.0 - sh2) + sh2 / dc
		print("[FS] %-26s %-4s z%-2d rho %.3f  d_cryo %.4f  ttk %+6.1f%%  hp row x%.4f" % [
			row["id"], row["role"], row["z"], row["rho"], dc, (ttk2 - 1.0) * 100.0, dc])
		if cryo_joins and absf(dc - 1.0) > 0.005:
			calib.append("\t\"%s\": {\"hp\": %.4f}," % [row["id"], dc])
			nrow += 1

	print("[FS] --- D. hp rows required: %d ---" % nrow)
	for l in calib:
		print("[FS] " + String(l))


func _rkey(ch: String) -> String:
	if ch == "kinetic":
		return "k"
	if ch == "energy":
		return "e"
	return "x"

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

func _player_atk(sm, cm, rm, tz: int, chan: String) -> float:
	GameState.hard_reset()
	for tid in rm.tech_tree:
		if int(rm.tech_tree[tid].get("tier", 99)) <= tz and not tid in rm.unlocked_techs:
			rm.unlocked_techs.append(tid)
	for h in sm.hulls:
		if int(sm.hulls[h].get("tier", 0)) == clampi(tz, 1, 10):
			sm.active_hull = String(h)
			break
	sm.loadout.clear()
	sm.ammo_loadout.clear()
	var wz: int = clampi(tz, 1, 10)
	_fill(sm, "battery", "z%d_battery" % wz, wz)
	_fill(sm, "weapon", "z%d_%s" % [wz, SUFFIX[chan]], wz)
	_fill(sm, "armor", "z%d_armor" % wz, wz)
	_fill(sm, "shield", "z%d_shield" % wz, wz)
	var band := ElementDB.get_ammo_band_for_zone(tz)
	var ammo := String(ElementDB.get_band_ammo_id(chan, band))
	GameState.resources.add_element(ammo, 1000000)
	for i in _slots(sm, "weapon"):
		sm.ammo_loadout[i] = ammo
	sm.recalc_stats()
	cm._rebuild_player_weapon_states()
	var key := "dmg_k"
	if chan == "energy":
		key = "dmg_e"
	elif chan == "explosive":
		key = "dmg_x"
	var mult := ElementDB.get_ammo_damage_mult(ammo)
	var tot := 0.0
	for w in cm.player_weapon_states:
		tot += float(w.get(key, 0.0)) * mult / float(w.get("interval", 2.0))
	return tot

func _fill(sm, stype: String, base_id: String, zone: int) -> void:
	if not base_id in sm.modules:
		return
	for i in _slots(sm, stype):
		var cid := String(sm.generate_module_drop(base_id, 0, zone))
		if cid == "":
			continue
		sm.equip_module(i, cid, true)

func _slots(sm, stype: String) -> Array:
	var out: Array = []
	var slots: Array = sm.hulls.get(sm.active_hull, {}).get("slots", [])
	for i in range(slots.size()):
		if String(slots[i]) == stype:
			out.append(i)
	return out
