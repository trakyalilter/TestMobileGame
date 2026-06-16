extends Node

# ============================================================================
# TTK SPIKE — deterministic on-tier boss time-to-kill measurement.
#
# For each representative tier, builds a tier-matched LEGENDARY loadout (the
# v106 balance target's assumed gear) via the same fit pipeline the debug Test
# Fit Tool uses (construct hull by tier -> generate_module_drop per slot ->
# tier-banded ammo), sets a tier-appropriate combat level, then fights that
# tier's zone boss as a damage race (HP topped on death, deaths counted) up to
# a 30-min cap. Reports energy used/capacity (validates the v112 battery
# headroom), boss HP, deaths, and TTK.
#
# No warp bonus (0 warps) -> measures BASE on-tier combat power, which is the
# context the v106 TTK targets (Z7 ~8min, Z10 ~13min) were set in.
#
# Run: tools/run_sim.ps1 -Scene "res://scenes/combat_spike.tscn"
# ============================================================================

const DT := 0.25
const TIERS := [3, 5, 7, 10]          # early-mid, mid, v106 ~8min, v106 ~13min
const RARITY := 3                      # Rarity.LEGENDARY (matches v106 assumption)
const MAX_FIGHT_S := 1800.0            # 30-min cap -> DNF
const WTYPES := ["kinetic", "energy", "missile"]

var _killed := false
var _boss_id := ""
var _deaths := 0

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

	print("[TTK] tier | hull | energy(used/cap) | headroom | boss | bossHP | maxHP%lost | TTK")
	print("[TTK] --------------------------------------------------------------------------")
	for t in TIERS:
		_measure_tier(int(t))
	print("[TTK] done")
	get_tree().quit(0)

func _unlock_everything() -> void:
	# Free-unlock every zone gate so start_expedition() accepts the zone.
	var rm = GameState.research_manager
	for n in range(2, 11):
		var tech: String = "zone_%d_access" % n
		if tech in rm.tech_tree and not (tech in rm.unlocked_techs):
			rm.unlocked_techs.append(tech)
	GameState.game_settings["z11_unlocked"] = true
	GameState.game_settings["cryo_unlocked"] = true
	GameState.resources.add_currency("credits", 1000000000.0)

func _ammo_for(suffix: String, tier: int) -> String:
	var at: int = 1
	if tier <= 2: at = 1
	elif tier <= 5: at = 2
	elif tier <= 8: at = 3
	else: at = 4
	match suffix:
		"kinetic": return "SlugT%d" % at
		"energy": return "CellT%d" % at
		"missile": return "MissileT%d" % at
	return ""

func _measure_tier(t: int) -> void:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager

	# --- Construct the tier-t hull (data-driven; mirror Test Fit Tool) ---
	var hid: String = ""
	for h in sm.hulls:
		if int(sm.hulls[h].get("tier", 0)) == t:
			hid = h
			break
	if hid == "":
		print("[TTK] T%d: no hull at this tier" % t)
		return
	sm.unequip_all()
	sm.active_hull = hid
	sm.loadout = {}
	var slots: Array = sm.hulls[hid]["slots"]
	for i in range(slots.size()):
		sm.loadout[i] = null
	sm.ammo_loadout = {}

	# --- Fit a tier-matched LEGENDARY loadout, mixed weapons ---
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
			var ammo: String = _ammo_for(wsfx, t)
			if ammo != "":
				GameState.resources.add_element(ammo, 200000)
				sm.ammo_loadout[i] = ammo

	# Tier-appropriate combat level so skill_dmg_mult (1 + lvl*0.005) reflects a
	# real player at this depth, not a level-1 floor. ~tier*9 (T10 -> ~90).
	var clvl: int = clampi(t * 9, 1, 100)
	GameState.combat_manager.level = clvl

	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	_neutralize_heat()

	# --- Find the zone at this difficulty + its boss ---
	var zid: String = ""
	_boss_id = ""
	for z in cm.zones:
		if int(cm.zones[z].get("difficulty", 0)) == t:
			zid = str(z)
			for e in cm.zones[z]["enemies"]:
				if cm.enemy_db.get(e, {}).get("is_boss", false):
					_boss_id = str(e)
					break
			break
	if zid == "" or _boss_id == "":
		print("[TTK] T%d: no zone/boss found" % t)
		return
	var boss_hp: float = float(cm.enemy_db[_boss_id]["stats"]["hp"])
	var e_used: int = int(sm.energy_used)
	var e_cap: int = int(sm.energy_capacity)
	var headroom_pct: float = (float(e_cap - e_used) / float(max(1, e_cap))) * 100.0

	# --- Fight the boss as a damage race (top HP on death, count deaths) ---
	_killed = false
	_deaths = 0
	cm.start_expedition(zid)
	cm.set_target_enemy(_boss_id)
	var unpowered: bool = (sm.energy_used > sm.energy_capacity) or (not cm.in_combat)
	var steps: int = int(MAX_FIGHT_S / DT)
	var ttk: float = -1.0
	var min_hp_frac: float = 1.0   # track how close to death (survivability proxy)
	for i in range(steps):
		if _killed:
			ttk = float(i) * DT
			break
		# Pure OFFENSIVE damage race: top HP each tick so the player never dies.
		# (Avoids the handle_module_defeat crash on custom modules AND isolates
		# "how long to kill" from survivability, which consumables/repairs cover
		# in real play.) Record the lowest HP fraction reached as a survivability
		# proxy: <~0.3 means the loadout would need heals to hold the fight.
		if sm.max_hp > 0:
			var frac: float = float(sm.current_hp) / float(sm.max_hp)
			if frac < min_hp_frac:
				min_hp_frac = frac
		sm.current_hp = sm.max_hp
		if not cm.in_combat:
			cm.start_expedition(zid)
			cm.set_target_enemy(_boss_id)
			if not cm.in_combat:
				break   # can't even enter (e.g. still unpowered) — bail
		cm.process_tick(DT)
	if _killed and ttk < 0.0:
		ttk = MAX_FIGHT_S
	_deaths = int(round((1.0 - min_hp_frac) * 100.0))   # reuse as "max HP% lost"

	var ttk_str: String = ("DNF >%.0fmin" % (MAX_FIGHT_S / 60.0))
	if ttk >= 0.0:
		ttk_str = "%.0fs (%.1fmin)" % [ttk, ttk / 60.0]
	var flag: String = ""
	if unpowered:
		flag = "  [UNPOWERED]"
	print("[TTK] T%d | %s | %d/%d | %.0f%% | %s | %d | %d | %s%s" % [
		t, hid, e_used, e_cap, headroom_pct, _boss_id,
		int(boss_hp), _deaths, ttk_str, flag])

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
