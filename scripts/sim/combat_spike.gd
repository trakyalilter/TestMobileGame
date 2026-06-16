extends Node

# ============================================================================
# WARP x FLEET TTK SPIKE — does each warp leave the player net stronger, and
# does the fleet add combat power?
#
# Holds a FIXED tier-matched Legendary loadout (T7) and measures boss TTK across
# warps 0..3, with and without a built fleet:
#   - Warp power: total_warps + warp_shards are set to model a player who has
#     re-climbed to T7 at warp W. Shard model = ~16 shards / warp (a Z10-depth
#     climb banks floor(log2(score/500k))+1 ~= 16; cumulative). warp_tier =
#     floor(W/5) = 0 for W<=4, so warps 1-3 grow ONLY via shards (+3%/shard).
#   - Fleet: built to capacity (1 + total_warps) from granted glut. Combat does
#     NOT read fleet power (P1 = sink only), so fleeted TTK == unfleeted TTK by
#     construction — this run PROVES that empirically. Also reports
#     get_fleet_power() and the PROJECTED TTK if the fleet were wired at the doc
#     spec (0.25x main-ship power / ship, +100% cap).
#
# Run: tools/run_sim.ps1 -Scene "res://scenes/combat_spike.tscn"
# ============================================================================

const DT := 0.25
const FIXED_TIER := 7                  # mid-late: warp mult meaningful, fight long enough to time
const WARPS := [0, 1, 2, 3]
const SHARDS_PER_WARP := 16            # ~floor(log2(Z10 score/500k))+1, cumulative
const RARITY := 3                      # Rarity.LEGENDARY
const MAX_FIGHT_S := 1800.0
const WTYPES := ["kinetic", "energy", "missile"]
const FLEET_SHIP_FRACTION := 0.25      # doc spec: each fleet ship ~= 0.25x main power
const FLEET_BONUS_CAP := 1.0           # doc spec: full fleet ~= +100% effective power

var _killed := false
var _boss_id := ""
var _zid := ""

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	GameState.set_process(false)
	GameState.hard_reset()
	seed(777)
	_unlock_everything()
	var cm = GameState.combat_manager
	if cm.has_signal("enemy_defeated"):
		cm.enemy_defeated.connect(_on_kill)

	print("[WF] Fixed loadout: T%d Legendary (mixed weapons). Boss = T%d zone boss." % [FIXED_TIER, FIXED_TIER])
	print("[WF] combat reads fleet power? NO (P1 sink-only) -> fleeted==unfleeted is expected.")
	print("[WF] ----------------------------------------------------------------------------------")
	print("[WF] warp | shards | combatMult | TTK(no fleet) | fleet cnt/cap | fleetPwr | TTK(fleet) | TTK(projected 0.25x/ship)")

	# Fit the loadout ONCE so loadout-roll RNG (Legendary affixes) doesn't drift
	# between warps — the only systematic variable across rows is the warp mult.
	_fit_tier(FIXED_TIER)
	var zb: Array = _find_zone_boss(FIXED_TIER)
	if zb.is_empty():
		print("[WF] no zone/boss at T%d" % FIXED_TIER)
		get_tree().quit(1)
		return
	_zid = str(zb[0])
	_boss_id = str(zb[1])

	for w in WARPS:
		_run_warp(int(w))
	print("[WF] done")
	get_tree().quit(0)

func _unlock_everything() -> void:
	var rm = GameState.research_manager
	for n in range(2, 11):
		var tech: String = "zone_%d_access" % n
		if tech in rm.tech_tree and not (tech in rm.unlocked_techs):
			rm.unlocked_techs.append(tech)
	GameState.game_settings["z11_unlocked"] = true
	GameState.game_settings["cryo_unlocked"] = true
	GameState.resources.add_currency("credits", 1000000000.0)

func _run_warp(w: int) -> void:
	var wm = GameState.warp_manager

	# --- Model the warp state: warps + cumulative shards (tier stays 0 for W<=4)
	wm.total_warps = w
	wm.warp_shards = float(w) * float(SHARDS_PER_WARP)
	wm.warp_shards_spent = 0.0
	var cmult: float = wm.get_combat_multiplier()

	# --- TTK with NO fleet (loadout already fit once in _boot) ---
	GameState.fleet_manager.ships.clear()
	var ttk_nofleet: float = _fight(_zid, _boss_id)

	# --- Build a fleet to capacity from granted glut, then re-measure ---
	_grant_glut()
	var built: int = _build_fleet_to_cap()
	var fcap: int = GameState.fleet_manager.get_fleet_capacity()
	var fpwr: float = GameState.fleet_manager.get_fleet_power()
	var ttk_fleet: float = _fight(_zid, _boss_id)

	# --- Projected TTK if fleet were wired at the doc spec (0.25x/ship, +100% cap) ---
	var fleet_bonus: float = min(FLEET_BONUS_CAP, FLEET_SHIP_FRACTION * float(built))
	var ttk_proj: float = (ttk_nofleet / (1.0 + fleet_bonus)) if ttk_nofleet > 0.0 else -1.0

	print("[WF] W%d | %d | %.2fx | %s | %d/%d | %d | %s | %s" % [
		w, int(wm.warp_shards), cmult,
		_fmt(ttk_nofleet), built, fcap, int(fpwr),
		_fmt(ttk_fleet), _fmt(ttk_proj)])

func _fmt(s: float) -> String:
	if s < 0.0:
		return "DNF"
	return "%.0fs(%.1fm)" % [s, s / 60.0]

# ---------------------------------------------------------------------------
func _fit_tier(t: int) -> void:
	var sm = GameState.shipyard_manager
	var hid: String = ""
	for h in sm.hulls:
		if int(sm.hulls[h].get("tier", 0)) == t:
			hid = h
			break
	if hid == "":
		return
	sm.unequip_all()
	sm.active_hull = hid
	sm.loadout = {}
	var slots: Array = sm.hulls[hid]["slots"]
	for i in range(slots.size()):
		sm.loadout[i] = null
	sm.ammo_loadout = {}
	var wp: int = 0
	for i in range(slots.size()):
		var st: String = str(slots[i])
		var base: String = ""
		var wsfx: String = ""
		match st:
			"weapon":
				wsfx = WTYPES[wp % 3]
				wp += 1
				base = "z%d_%s" % [t, wsfx]
			"shield": base = "z%d_shield" % t
			"armor": base = "z%d_armor" % t
			"engine": base = "z%d_engine" % t
			"battery": base = "z%d_battery" % t
			"sensor": base = "z%d_sensor" % t
			_: continue
		if not (base in sm.modules):
			continue
		var mid: String = sm.generate_module_drop(base, RARITY, t)
		if mid == "":
			continue
		sm.loadout[i] = mid
		if wsfx != "":
			var at: int = 4
			if t <= 8: at = 3
			if t <= 5: at = 2
			if t <= 2: at = 1
			var ammo: String = {"kinetic": "SlugT%d", "energy": "CellT%d", "missile": "MissileT%d"}[wsfx] % at
			GameState.resources.add_element(ammo, 200000)
			sm.ammo_loadout[i] = ammo
	GameState.combat_manager.level = clampi(t * 9, 1, 100)
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	_neutralize_heat()

func _find_zone_boss(t: int) -> Array:
	var cm = GameState.combat_manager
	for z in cm.zones:
		if int(cm.zones[z].get("difficulty", 0)) == t:
			for e in cm.zones[z]["enemies"]:
				if cm.enemy_db.get(e, {}).get("is_boss", false):
					return [str(z), str(e)]
	return []

func _fight(zid: String, boss_id: String) -> float:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	_killed = false
	sm.current_hp = sm.max_hp
	cm.start_expedition(zid)
	cm.set_target_enemy(boss_id)
	if not cm.in_combat:
		return -1.0
	var steps: int = int(MAX_FIGHT_S / DT)
	for i in range(steps):
		if _killed:
			return float(i) * DT
		sm.current_hp = sm.max_hp   # pure offensive damage race
		if not cm.in_combat:
			cm.start_expedition(zid)
			cm.set_target_enemy(boss_id)
			if not cm.in_combat:
				return -1.0
		cm.process_tick(DT)
	return -1.0

func _grant_glut() -> void:
	var r = GameState.resources
	for sym in ["Water", "Dirt", "Steel", "Circuit", "AdvCircuit", "Superalloy"]:
		r.add_element(sym, 5000000)

func _build_fleet_to_cap() -> int:
	var fm = GameState.fleet_manager
	var built: int = 0
	var guard: int = 0
	while fm.get_fleet_count() < fm.get_fleet_capacity() and guard < 100:
		guard += 1
		var buildable: Array = fm.get_buildable_hulls()
		var picked: String = ""
		var best_pwr: float = -1.0
		for hid in buildable:
			if fm.can_build(hid) and fm.get_hull_power(hid) > best_pwr:
				best_pwr = fm.get_hull_power(hid)
				picked = hid
		if picked == "":
			break
		if not fm.build_ship(picked):
			break
		built += 1
	return built

func _neutralize_heat() -> void:
	var cm = GameState.combat_manager
	if not cm:
		return
	cm.player_heat = 0.0
	cm.overheat_lock = 0.0
	cm.player_max_heat = 1000000000.0
	cm.player_vent_rate = 1000000000.0

func _on_kill(eid = null, _b = null, _c = null) -> void:
	if str(eid) == _boss_id:
		_killed = true
