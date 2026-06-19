extends Node
# ============================================================================
# GATING SPIKE — per-zone numeric win/lose for CARRIED vs CRAFTED loadouts, with
# the FULL effective-power model the design hinges on:
#   • affixes      — rare+ loadouts come from generate_module_drop (rolls affixes)
#   • matrix cores — every socket filled with a Pristine core (Crimson=offense on
#                    weapons, Amethyst=defense on armor/shield, Topaz elsewhere)
#   • crafted commons are CLEAN — base module id, no affixes, no sockets/cores
#   • hull changes per zone — always the tier-N hull; batteries kept tier-N so a
#     loadout never fails on POWER (we're measuring combat, not the energy gate)
#
# Hardening is turned OFF (tier_gate_enabled=false) so this is the PURE numeric
# picture — stats + affixes + cores vs the (steepened) enemy. Player HP is NOT
# refilled, so the enemy can out-trade weak gear → a real WIN / LOSE / DNF.
#
# Target cycle:  N-1 Legendary LOSES · N Common WINS · N-1 Unique WINS · N Rare WINS
# If N-1 Legendary already WINS, the numeric gate isn't there yet (enemy too soft
# and/or rarity curve too strong) — that's the signal for the rebalance.
#
# Run: Godot_console.exe --headless --path <proj> res://scenes/gating_spike.tscn
# ============================================================================

const DT := 0.25
const MAX_FIGHT_S := 900.0   # 15 min — endgame bosses legitimately run long; a
                             # high cap separates "too slow" (DNF) from "dies" (LOSE)
const WTYPES := ["kinetic", "energy", "missile"]
const R_COMMON := 0
const R_RARE := 2
const R_LEGENDARY := 3
const R_UNIQUE := 4
const CORE_FACET := {"weapon": "Crimson", "armor": "Amethyst", "shield": "Amethyst"}
const CORE_TIER_NAME := {1: "Stable", 2: "Pristine"}   # 0 = no cores

var _killed := false
var _target := ""

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	GameState.set_process(false)
	GameState.hard_reset()
	seed(20260619)
	_unlock_everything()
	# Measure the PURE numeric outcome — no hardening floor.
	GameState.game_settings["tier_gate_enabled"] = false
	# Combat leveling is being removed; measure with no combat-level damage bonus.
	GameState.combat_manager.level = 1
	var cm = GameState.combat_manager
	if cm.has_signal("enemy_defeated"):
		cm.enemy_defeated.connect(_on_kill)

	print("[GATE] Pure-numeric win/lose · hardening OFF · hull=tier-N · rare+ = affixed + matrix-cored · commons CLEAN")
	print("[GATE] target: N-1 Leg LOSE | N-1 Uniq WIN | N Common WIN | N Rare WIN")
	print("[GATE] Leg-/Leg~/Leg+ = carried N-1 Legendary with NO / Stable / Pristine cores (affixes always on)")

	print("[GATE] === PASS 1: pre-warp (warps=0) ===")
	for n in range(2, 11):
		_run_zone(n)
	# PASS 2: model the player having taken Warp #1 (~16 shards, the Z10-depth
	# bank) by the late zones. The design gates z9+ behind warping, so a no-warp
	# sim false-DNFs there — this pass shows the real late-game picture.
	var wm = GameState.warp_manager
	wm.total_warps = 1
	wm.warp_shards = 16.0
	wm.warp_shards_spent = 0.0
	print("[GATE] === PASS 2: post Warp #1 (16 shards, combat x%.2f) ===" % wm.get_combat_multiplier())
	for n in range(7, 11):
		_run_zone(n)
	print("[GATE] done")
	get_tree().quit(0)

func _run_zone(n: int) -> void:
	var cm = GameState.combat_manager
	var zid := ""
	var enemy := ""
	for z in cm.zones:
		if int(cm.zones[z].get("difficulty", 0)) == n:
			zid = str(z)
			var roster: Array = cm.zones[z].get("enemies", [])
			if roster.size() >= 3:
				enemy = str(roster[2])  # e3 = first back-half regular
			break
	if zid == "" or enemy == "":
		print("[GATE] z%d: no zone / e3 found" % n)
		return
	# Carried N-1 Legendary under escalating matrix-core investment (affixes always
	# on — intrinsic to the rarity). Isolates how much the CORES swing the gate vs.
	# the rarity stats + affixes alone.
	var leg0 := _trial(n, n - 1, R_LEGENDARY, true, 0, zid, enemy)
	var legS := _trial(n, n - 1, R_LEGENDARY, true, 1, zid, enemy)
	var legP := _trial(n, n - 1, R_LEGENDARY, true, 2, zid, enemy)
	var uniq := _trial(n, n - 1, R_UNIQUE, true, 2, zid, enemy)
	var com := _trial(n, n, R_COMMON, false, 0, zid, enemy)
	var rare := _trial(n, n, R_RARE, true, 2, zid, enemy)
	print("[GATE] z%-2d %-16s | Leg- %-9s Leg~ %-9s Leg+ %-9s | Uniq %-9s | Com %-9s | Rare %s" % [
		n, enemy, leg0, legS, legP, uniq, com, rare])

func _trial(hull_tier: int, mod_tier: int, rarity: int, as_drop: bool, core_tier: int, zid: String, enemy: String) -> String:
	# Deterministic per-config seed → reproducible run-to-run, and one row's RNG
	# can't perturb another's (affix shuffles / drop ids no longer shift the next
	# trial's combat rolls). Without this, iteration-to-iteration deltas are noise.
	seed(hull_tier * 100003 + mod_tier * 1009 + rarity * 31 + core_tier * 7 + 1)
	if not _fit(hull_tier, mod_tier, rarity, as_drop, core_tier):
		return "n/a"
	return _fight(zid, enemy)

# Equip the tier-`hull_tier` hull; fill combat slots (weapon/armor/shield/engine/
# sensor) at (mod_tier, rarity); batteries always tier-`hull_tier` common so power
# is never the limiter. Rare+ go through generate_module_drop (affixes + sockets)
# and get every socket filled with a Pristine core; commons equip the clean base id.
func _fit(hull_tier: int, mod_tier: int, rarity: int, as_drop: bool, core_tier: int) -> bool:
	var sm = GameState.shipyard_manager
	var hid := ""
	for h in sm.hulls:
		if int(sm.hulls[h].get("tier", 0)) == hull_tier:
			hid = h
			break
	if hid == "":
		return false
	sm.unequip_all()
	sm.active_hull = hid
	sm.loadout = {}
	sm.ammo_loadout = {}
	var slots: Array = sm.hulls[hid]["slots"]
	for i in range(slots.size()):
		sm.loadout[i] = null
	var wp := 0
	for i in range(slots.size()):
		var st := str(slots[i])
		# Batteries always tier-N common — power enabler, combat-neutral.
		if st == "battery":
			var bbase := "z%d_battery" % hull_tier
			if bbase in sm.modules:
				sm.loadout[i] = bbase
			continue
		var base := ""
		var wsfx := ""
		match st:
			"weapon":
				wsfx = WTYPES[wp % 3]
				wp += 1
				base = "z%d_%s" % [mod_tier, wsfx]
			"shield": base = "z%d_shield" % mod_tier
			"armor": base = "z%d_armor" % mod_tier
			"engine": base = "z%d_engine" % mod_tier
			"sensor": base = "z%d_sensor" % mod_tier
			_: continue
		if not (base in sm.modules):
			continue
		var mid := base
		if as_drop:
			mid = sm.generate_module_drop(base, rarity, mod_tier)
			if mid == "":
				continue
			_socket_cores(mid, st, core_tier)
		sm.loadout[i] = mid
		if wsfx != "":
			var at := 4
			if mod_tier <= 8: at = 3
			if mod_tier <= 5: at = 2
			if mod_tier <= 2: at = 1
			var ammo: String = {"kinetic": "SlugT%d", "energy": "CellT%d", "missile": "MissileT%d"}[wsfx] % at
			GameState.resources.add_element(ammo, 500000)
			sm.ammo_loadout[i] = ammo
	sm.recalc_stats()
	sm.current_hp = sm.max_hp
	return true

func _socket_cores(mid: String, slot_type: String, core_tier: int) -> void:
	if core_tier <= 0:
		return
	var sm = GameState.shipyard_manager
	var m = sm.modules.get(mid, {})
	if not (m is Dictionary) or not m.has("sockets"):
		return
	var facet: String = str(CORE_FACET.get(slot_type, "Topaz"))
	var core: String = "%s%sCore" % [CORE_TIER_NAME[core_tier], facet]
	var socks: Array = m["sockets"]
	for idx in range(socks.size()):
		GameState.resources.add_element(core, 1)
		sm.insert_gem(mid, idx, core)

func _fight(zid: String, enemy: String) -> String:
	var sm = GameState.shipyard_manager
	var cm = GameState.combat_manager
	_killed = false
	_target = enemy
	sm.current_hp = sm.max_hp
	cm.start_expedition(zid)
	cm.set_target_enemy(enemy)
	# Suppress the random 5% ELITE spawn (2.5x HP / 1.8x ATK) — pure noise that
	# randomly flips a gating WIN/LOSE. Re-spawn until a normal enemy appears.
	var eguard := 0
	while cm.in_combat and bool(cm.current_enemy.get("is_elite", false)) and eguard < 60:
		eguard += 1
		cm.set_target_enemy(enemy)
	if not cm.in_combat:
		return "NOPWR"   # couldn't even engage (unpowered / blocked)
	var steps := int(MAX_FIGHT_S / DT)
	for i in range(steps):
		if _killed:
			return "WIN %.0fs" % (float(i) * DT)
		if not cm.in_combat:
			return "LOSE"   # fight ended with no kill → player died / retreated
		cm.process_tick(DT)
	return "DNF"   # alive but couldn't kill in time → DPS far too low

func _unlock_everything() -> void:
	var rm = GameState.research_manager
	for n in range(2, 13):
		var tech := "zone_%d_access" % n
		if tech in rm.tech_tree and not (tech in rm.unlocked_techs):
			rm.unlocked_techs.append(tech)
	GameState.resources.add_currency("credits", 1000000000.0)

func _on_kill(eid = null, _b = null, _c = null) -> void:
	if str(eid) == _target:
		_killed = true
