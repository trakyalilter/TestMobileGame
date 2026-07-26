extends Node

# DPS FIDELITY PROBE (v149 interval normalisation).
# Walks every zone x every enemy through the REAL spawn_enemy pipeline (tier
# rebase -> zone steepening -> front-cell calib -> warp catch-up) and prints the
# EFFECTIVE atk + atk_interval, i.e. the numbers the fight actually uses. Also
# dumps every weapon module's base dps. Run before and after the change and diff.

func _ready() -> void:
	GameState.hard_reset()
	var cm = GameState.combat_manager
	var sm = GameState.shipyard_manager
	print("[IVF] --- ENEMIES (effective, post-pipeline) ---")
	var zkeys: Array = cm.zones.keys()
	for zid in zkeys:
		var z: Dictionary = cm.zones[zid]
		cm.current_zone = z
		cm.current_zone_id = String(zid)
		for eid in z.get("enemies", []):
			if not cm.enemy_db.has(eid):
				continue
			cm.target_enemy_id = eid
			# spawn_enemy rolls a 5% ELITE (x1.8 atk). That randomness swamps a
			# 1%-scale fidelity read, so respawn until a baseline (non-elite) roll.
			var guard := 0
			cm.spawn_enemy()
			while bool(cm.current_enemy.get("is_elite", false)) and guard < 200:
				cm.spawn_enemy()
				guard += 1
			var ce = cm.current_enemy
			var atk: float = float(ce.get("atk", 0))
			var iv: float = float(ce.get("atk_interval", 0.0))
			var dps: float = atk / max(0.0001, iv)
			print("[IVF] E %s|%s atk=%s iv=%s dps=%s" % [
				String(zid), String(eid), str(atk), str(iv), str(dps)])
	print("[IVF] --- SWING FIELDS ---")
	for eid in cm.enemy_db:
		var e: Dictionary = cm.enemy_db[eid]
		var iv2: float = float(e.get("stats", {}).get("atk_interval", 0.0))
		var cn: Dictionary = e.get("charge_nuke", {})
		if not cn.is_empty():
			print("[IVF] NUKE %s every_n=%d iv=%s period=%s mult=%s" % [
				String(eid), int(cn.get("every_n", 0)), str(iv2),
				str(float(cn.get("every_n", 0)) * iv2), str(cn.get("mult", 0))])
		var su: Dictionary = e.get("sustain", {})
		if String(su.get("kind", "")) == "siphon":
			print("[IVF] SIPHON %s pct=%s iv=%s rate_per_s=%s" % [
				String(eid), str(su.get("pct", 0)), str(iv2),
				str(float(su.get("pct", 0)) / max(0.0001, iv2))])
	print("[IVF] --- WEAPON MODULES (base, post tier-rebase) ---")
	for mid in sm.modules:
		var m: Dictionary = sm.modules[mid]
		var st: Dictionary = m.get("stats", {})
		if not st.has("atk_interval"):
			continue
		var tot: float = float(st.get("atk_kinetic", 0)) + float(st.get("atk_energy", 0)) \
			+ float(st.get("atk_explosive", 0)) + float(st.get("atk_cryo", 0))
		var iv3: float = float(st.get("atk_interval", 2.0))
		print("[IVF] W %s atk=%s iv=%s dps=%s" % [
			String(mid), str(tot), str(iv3), str(tot / max(0.0001, iv3))])
	get_tree().quit()
