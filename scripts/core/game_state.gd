extends Node

# Core Systems
var resources : Node

signal game_resetted
signal game_loaded

# Managers
var gathering_manager : RefCounted
var processing_manager : RefCounted
var infrastructure_manager : RefCounted
var fleet_manager : RefCounted
var shipyard_manager : RefCounted
var research_manager : RefCounted
var combat_manager : RefCounted
var mission_manager : RefCounted
var warp_manager : RefCounted
var bounty_manager : RefCounted
var quest_manager : RefCounted
# var processing_manager
# var mission_manager
# var combat_manager
# var infrastructure_manager
# var shipyard_manager

var active_manager : RefCounted = null
var was_resetted: bool = false

var offline_report: String = ""   # legacy string (dead offline_modal.gd guards on it)
# v112: structured offline report consumed by the telemetry welcome modal.
# Array of activity blocks (see any manager's calculate_offline) + headline meta.
var offline_report_data: Array = []
var offline_away_sec: float = 0.0
var offline_capped: bool = false
# v123: transient page to land on after a scene reload (Sys Config palette swap).
# Not persisted — survives reload because GameState is an autoload.
var ui_return_page: String = ""
var elements_db: Array = []

# v52.1: Game Settings (opt-in features)
var game_settings: Dictionary = {
	"offline_combat": true,  # v135a: ON by default for NEW games — it's winnability-gated AND now drops the module pool (weapons/armor/shield), so the gear-check grind amortizes while away. Existing saves keep their own value (load-merge) to avoid a surprise durability-loss consent.
	# v125: one-time consent shown the first time Offline Combat is enabled
	# (it can destroy modules already worn to <=50% durability). Cleared on
	# hard_reset so a new playthrough re-confirms.
	"offline_combat_warned": false,
	# v114 (Zone Tier-Gate): gates the front/back sector-hardening system.
	# Default true → a brand-new game (no save) is gated. New Game (hard_reset)
	# re-sets it true. Loading a PRE-feature save (no key) flips it false in
	# load_game so already-cleared zones aren't retroactively re-walled.
	"tier_gate_enabled": true
}

# Auto-save
var time_since_save: float = 0.0
const PROD_SAVE_INTERVAL: float = 60.0

# P2.7: Global offline cap. Generous (24h) but finite — gathering/processing/
# infrastructure offline accrual was previously unbounded, both an economy
# exploit and a startup-stall risk (AUDIT_LOG AUD-P0-004). Tune here.
const OFFLINE_DELTA_CAP_SECONDS: float = 86400.0

# P3.10: lightweight balance telemetry (instrumentation, NOT gameplay).
#  occupancy  — seconds the single active slot spent per mode (is the
#               skilling loop alive, or is everyone just doing combat?).
#  production — total resource units credited per stream (did P0/P1.4
#               actually stop infra from out-producing gathering?).
# Persisted across prestige (lifetime/meta); cleared only on hard reset.
var telemetry: Dictionary = {
	"occupancy": {"mining": 0.0, "engineering": 0.0, "research": 0.0, "combat": 0.0, "idle": 0.0},
	"production": {"gather": 0.0, "process": 0.0, "infra": 0.0, "combat": 0.0},
	# Phase 0 (combat materials): per-material units by source. Validates the
	# mandatory-gate + punitive-fallback balance — if a gated material is
	# mostly "craft" the fallback is too cheap (or farming too painful); if
	# "combat" dominates the loop works. {mat_id: {combat: x, craft: y}}
	"mat_source": {},
	# Phase A (damage triangle): track per-type usage AND post-resist
	# delivered damage so we can see if players are actually adapting their
	# loadout to enemy resists. *_raw = pre-resist damage attempted by type;
	# *_done = damage that actually landed. Ratio done/raw ≈ avg (1 - resist)
	# experienced when that type was used. Balanced *_raw shares + done/raw
	# > 1.0 = players are adapting (using right type for the right enemy).
	"damage_type": {
		"kinetic_raw": 0.0, "energy_raw": 0.0, "explosive_raw": 0.0,
		"kinetic_done": 0.0, "energy_done": 0.0, "explosive_done": 0.0,
	},
	# v135a (funnel): per-zone boss-loss reason rollup {zone_id: {tag: count}} —
	# tag in wrong_type_resisted / under_tier_walled / out_tanked / low_dps.
	# Dev-only instrumentation; NEVER surfaced to the player. Lifetime/meta.
	"boss_losses": {},
}

# v135a (funnel): append-only DEV event TIMELINE — zone clears, boss attempts (+
# a why-failed tag), warp screen open vs performed, and logout snapshots. Purpose:
# see WHERE real players stall so WE can tune the world. Invisible to the player
# (no UI reads it), persisted in the save as a capped FIFO, lifetime/meta (cleared
# only on hard reset). This watches; it never warns — the player self-discovers.
var event_log: Array = []
const EVENT_LOG_CAP := 500

# Total active play time: real wall-clock seconds the game has been open.
# Measured off the system clock so Engine.time_scale (game-speed) can't
# inflate it. Persisted across sessions; reset only on a full New Game.
var total_playtime: float = 0.0
var _pt_last_msec: int = 0

func _ready():
	# Initialize Resources
	var res_script = load("res://scripts/core/resources.gd")
	resources = res_script.new()
	add_child(resources)
	
	load_elements_db()
	
	# Initialize Managers
	gathering_manager = load("res://scripts/managers/gathering_manager.gd").new()
	processing_manager = load("res://scripts/managers/processing_manager.gd").new()
	infrastructure_manager = load("res://scripts/managers/infrastructure_manager.gd").new()
	shipyard_manager = load("res://scripts/managers/shipyard_manager.gd").new()
	research_manager = load("res://scripts/managers/research_manager.gd").new()
	combat_manager = load("res://scripts/managers/combat_manager.gd").new()
	mission_manager = load("res://scripts/managers/mission_manager.gd").new()
	warp_manager = load("res://scripts/managers/warp_manager.gd").new()
	fleet_manager = load("res://scripts/managers/fleet_manager.gd").new()
	bounty_manager = load("res://scripts/managers/bounty_manager.gd").new()
	quest_manager = load("res://scripts/managers/quest_manager.gd").new()

	mission_manager.connect_signals()
	bounty_manager.connect_signals()
	quest_manager.connect_signals()
	warp_manager.warped.connect(_on_warped)  # v135a: funnel warp_performed event

	load_game()

# v135a (funnel): a warp actually happened — log it (the counterpart to the
# warp_opened event lets us measure open->commit conversion). charge_bonus can't
# be split from the signal (warp_charge is already zeroed), so log total gains.
func _on_warped(gains) -> void:
	log_event({
		"type": "warp_performed",
		"shards_gained": int(gains),
		"total_shards_after": warp_manager.warp_shards,
		"total_warps": warp_manager.total_warps,
		"t": int(Time.get_unix_time_from_system()),
	})

func _process(delta):
	# 0. Total play time (real clock — immune to game-speed scaling)
	var now_ms := Time.get_ticks_msec()
	if _pt_last_msec == 0:
		_pt_last_msec = now_ms
	total_playtime += float(now_ms - _pt_last_msec) / 1000.0
	_pt_last_msec = now_ms

	# 1. Background Automation (Infrastructure)
	if infrastructure_manager: infrastructure_manager.process_tick(delta)
	if bounty_manager: bounty_manager.process_tick(delta)
	# v134h: Warp-Core Charge is now a MANUAL feed (warp_manager.feed_core, called from
	# the Warp page) — no always-on drain here. This removes the silent day-0 cap on
	# bulk basics (Dirt/Water/Wood were pinned at ~5000 by the old auto-sink).

	# 2. Active Foreground Task
	# In Python it was one active manager. 
	# In Godot we can stick to that or allow parallel.
	# Sticking to single active manager for now as per Python logic
	if active_manager:
		active_manager.process_tick(delta)

	# 3. Occupancy telemetry (P3.10) — attribute this frame to one mode
	var _ok := _occupancy_key()
	var _occ: Dictionary = telemetry["occupancy"]
	_occ[_ok] = float(_occ.get(_ok, 0.0)) + delta

	# Auto-save
	time_since_save += delta
	if time_since_save >= PROD_SAVE_INTERVAL:
		save_game()
		time_since_save = 0.0

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		save_game(true)  # v135a: shutdown -> write a funnel logout snapshot

# P3.10: which mode the single active slot is occupying this frame.
func _occupancy_key() -> String:
	if combat_manager and combat_manager.in_combat: return "combat"
	if active_manager == gathering_manager: return "mining"
	if active_manager == processing_manager: return "engineering"
	if active_manager == research_manager: return "research"
	return "idle"

# P3.10: credit produced resource units to a stream (gather/process/infra/combat).
func note_production(stream: String, amount) -> void:
	if amount == null: return
	var a := float(amount)
	if a <= 0.0: return
	var p: Dictionary = telemetry["production"]
	p[stream] = float(p.get(stream, 0.0)) + a

# Phase 0: credit a tracked combat-material to its source ("combat" drop or
# "craft" = the punitive fallback recipe). Lets us see, per gated material,
# whether players farm it or fall back to the lossy craft.
func note_material(mat_id: String, source: String, amount = 1) -> void:
	var a := float(amount)
	if a <= 0.0: return
	var ms: Dictionary = telemetry["mat_source"]
	var rec: Dictionary = ms.get(mat_id, {"combat": 0.0, "craft": 0.0})
	rec[source] = float(rec.get(source, 0.0)) + a
	ms[mat_id] = rec

# Convenience: credit a fallback-CRAFTED output, but only if it's a tracked
# combat material. Keeps processing call sites a single plain statement.
func note_craft_material(mat_id: String, amount) -> void:
	if mat_id in ElementDB.get_elements_in_category("reclaimed_components"):
		note_material(mat_id, "craft", amount)

# Phase A: credit a player attack's per-type raw and post-resist damage so
# we can see which type the player picked and what landed. One call site
# inside the resist-application block keeps overhead negligible.
func note_damage(k_raw: float, e_raw: float, x_raw: float, k_done: float, e_done: float, x_done: float) -> void:
	var d: Dictionary = telemetry["damage_type"]
	d["kinetic_raw"] = float(d.get("kinetic_raw", 0.0)) + k_raw
	d["energy_raw"] = float(d.get("energy_raw", 0.0)) + e_raw
	d["explosive_raw"] = float(d.get("explosive_raw", 0.0)) + x_raw
	d["kinetic_done"] = float(d.get("kinetic_done", 0.0)) + k_done
	d["energy_done"] = float(d.get("energy_done", 0.0)) + e_done
	d["explosive_done"] = float(d.get("explosive_done", 0.0)) + x_done

func _task_label(m) -> String:
	if m == gathering_manager: return "Mining"
	if m == processing_manager: return "Engineering"
	if m == research_manager: return "Research"
	if m == combat_manager: return "Combat"
	return "Task"

func set_active_manager(manager):
	if active_manager and active_manager != manager:
		active_manager.stop_action()
		# Only one foreground task runs at a time — make the swap visible so
		# the player isn't left wondering why their last task "stopped".
		UITheme.show_notification("%s paused — now %s" % [_task_label(active_manager), _task_label(manager)], Color(1.0, 0.82, 0.35))
	active_manager = manager

# v135a (funnel): append a dev event to the capped FIFO timeline. Invisible to the
# player (no UI reads event_log); read only by dev tooling. Cheap.
func log_event(e: Dictionary) -> void:
	event_log.append(e)
	if event_log.size() > EVENT_LOG_CAP:
		event_log = event_log.slice(event_log.size() - EVENT_LOG_CAP)

# Highest unlocked zone difficulty (there is no max_zone field — scan the roster).
func _max_unlocked_difficulty() -> int:
	var best := 0
	if combat_manager:
		for z in combat_manager.get_available_zones():
			best = max(best, int(combat_manager.zones.get(String(z.get("id", "")), {}).get("difficulty", 0)))
	return best

func save_game(is_shutdown: bool = false):
	# v135a (funnel): logout snapshot ONLY at shutdown — gating it here keeps the 60s
	# autosave (and warp-triggered saves) from flooding the 500-cap event_log.
	if is_shutdown:
		log_event({
			"type": "logout",
			"score": warp_manager.get_progress_score(),
			"shards_banked": warp_manager.warp_shards,
			"total_warps": warp_manager.total_warps,
			"max_diff": _max_unlocked_difficulty(),
			"playtime": int(total_playtime),
			"t": int(Time.get_unix_time_from_system()),
		})
	var save_data = {
		"version": 4, # v4: funnel event_log + telemetry.boss_losses (additive)
		"resources": resources.get_save_data(),
		"gathering": gathering_manager.get_save_data_manager(),
		"processing": processing_manager.get_save_data_manager(),
		"infrastructure": infrastructure_manager.get_save_data_manager(),
		"shipyard": shipyard_manager.get_save_data_manager(),
		"research": research_manager.get_save_data_manager(),
		"combat": combat_manager.get_save_data_manager(),
		"mission": mission_manager.get_save_data_manager(),
		"prestige": warp_manager.get_save_data_manager(),
		"fleet": fleet_manager.get_save_data_manager(),
		"bounty": bounty_manager.get_save_data_manager(),
		"quest": quest_manager.get_save_data_manager(),
		"game_settings": game_settings,  # v52.1
		"total_playtime": total_playtime,
		"telemetry": telemetry,  # P3.10 (additive; old saves default safely)
		"event_log": event_log,  # v135a funnel timeline (additive, capped FIFO)
		"last_save_time": Time.get_unix_time_from_system()
	}
	
	# P0 Fix: Atomic Save Pattern
	var path_final = "user://savegame.json"
	var path_temp = "user://savegame.tmp"
	var path_bak = "user://savegame.bak"
	
	var file = FileAccess.open(path_temp, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
		file.close() # Ensure flush
		
		# Verify temp file exists
		if FileAccess.file_exists(path_temp):
			# Backup existing save
			if FileAccess.file_exists(path_final):
				var err = DirAccess.copy_absolute(path_final, path_bak)
				if err != OK: print("Warning: Backup failed.")
			
			# Atomic Rename
			var err = DirAccess.rename_absolute(path_temp, path_final)
			if err == OK:
				print("Game Saved Atomically.")
			else:
				print("CRITICAL: Failed to rename temp save file. Error: ", err)
		else:
			print("CRITICAL: Temp save file creation failed.")
	else:
		print("Failed to open temp save file.")

func migrate_save(data: Dictionary, from_version: int) -> Dictionary:
	print("Migrating save from v%d..." % from_version)
	# v0 -> v1 (Initial Versioning)
	if from_version < 1:
		pass  # nothing to add for legacy unversioned saves
	# v1 -> v2 (P1 Mastery — per-action / per-recipe XP dicts)
	if from_version < 2:
		if data.has("gathering") and data["gathering"] is Dictionary:
			if not data["gathering"].has("mastery"):
				data["gathering"]["mastery"] = {}
		if data.has("processing") and data["processing"] is Dictionary:
			if not data["processing"].has("mastery"):
				data["processing"]["mastery"] = {}
	# v2 -> v3 (Warp-Core Charge / Resonance). Additive; load defaults warp_charge
	# to 0.0 anyway, so this just backfills the prestige dict for cleanliness.
	if from_version < 3:
		if data.has("prestige") and data["prestige"] is Dictionary:
			if not data["prestige"].has("warp_charge"):
				data["prestige"]["warp_charge"] = 0.0
	# v3 -> v4 (funnel instrumentation). Additive: dev event_log timeline + per-zone
	# boss-loss rollup. load_game guarded-merges both, so this just backfills keys.
	if from_version < 4:
		if not data.has("event_log"):
			data["event_log"] = []
		if data.has("telemetry") and data["telemetry"] is Dictionary:
			if not data["telemetry"].has("boss_losses"):
				data["telemetry"]["boss_losses"] = {}
	data["version"] = 4
	return data

func load_game():
	# v134c DATA-LOSS FIX: a MISSING primary save must still try the .bak backup.
	# The atomic save (write .tmp → copy .json→.bak → rename .tmp→.json) can leave
	# the player with .bak-ONLY if the process dies between the backup copy and the
	# rename, or the rename fails (see save_game's "CRITICAL: Failed to rename").
	# The old guard early-returned on a missing .json and booted a FRESH game,
	# silently orphaning a save that was sitting intact in .bak. Only boot fresh
	# when BOTH files are genuinely absent (true first launch / post hard-reset).
	if not FileAccess.file_exists("user://savegame.json") and not FileAccess.file_exists("user://savegame.bak"):
		return

	var json = JSON.new()
	var error = FAILED   # stays FAILED if primary is missing → falls through to .bak
	if FileAccess.file_exists("user://savegame.json"):
		var file = FileAccess.open("user://savegame.json", FileAccess.READ)
		if file:
			error = json.parse(file.get_as_text())

	# Corrupt OR missing primary save → recover from the .bak backup before booting
	# fresh. A half-written (or unrenamed) savegame.json must never cost a save.
	if error != OK and FileAccess.file_exists("user://savegame.bak"):
		push_warning("savegame.json missing/corrupt — recovering from savegame.bak")
		var bak_file = FileAccess.open("user://savegame.bak", FileAccess.READ)
		if bak_file:
			error = json.parse(bak_file.get_as_text())
			if error == OK:
				print("Recovered save from savegame.bak")

	if error == OK:
		var data = json.data

		# Version Check & Migration
		var ver = data.get("version", 0)
		if ver < 3:
			data = migrate_save(data, ver)
			
		resources.load_save_data(data.get("resources", {}))
		gathering_manager.load_save_data_manager(data.get("gathering", {}))
		infrastructure_manager.load_save_data_manager(data.get("infrastructure", {}))
		research_manager.load_save_data_manager(data.get("research", {}))
		processing_manager.load_save_data_manager(data.get("processing", {}))
		
		# Shipyard depends on research and processing for capacity scaling!
		shipyard_manager.load_save_data_manager(data.get("shipyard", {}))
		
		combat_manager.load_save_data_manager(data.get("combat", {}))
		mission_manager.load_save_data_manager(data.get("mission", {}))
		warp_manager.load_save_data_manager(data.get("prestige", {}))
		fleet_manager.load_save_data_manager(data.get("fleet", {}))
		bounty_manager.load_save_data_manager(data.get("bounty", {}))
		quest_manager.load_save_data_manager(data.get("quest", {}))
		
		# v138 migration: pre-Singularity saves have no rift flag. A NEVER-warped save
		# that already killed a Zone-3+ boss earned its rift — derive it once (combat
		# is loaded by now; warp loads before combat's boss_kills would be visible to
		# it). Post-warp saves start closed and re-earn it, per the per-run rule.
		if warp_manager._rift_key_missing and warp_manager.total_warps == 0 and not warp_manager.rift_open:
			for _beid in combat_manager.boss_kills:
				if int(combat_manager.boss_kills[_beid]) > 0 \
						and int(combat_manager.enemy_db.get(_beid, {}).get("zone", 0)) >= 3:
					warp_manager.rift_open = true
					break

		# v52.1: Load game settings
		var saved_settings = data.get("game_settings", {})
		for key in saved_settings:
			game_settings[key] = saved_settings[key]
		# v114 (Zone Tier-Gate): new-game-only rollout. A save written before this
		# feature has no flag → ungate it so the hardened back-halves don't suddenly
		# wall zones the player already cleared. New/post-feature saves carry it.
		if not saved_settings.has("tier_gate_enabled"):
			game_settings["tier_gate_enabled"] = false

		# Restore lifetime play time (defaults to 0 for pre-existing saves).
		# Re-anchor the clock so the load gap isn't counted as play time.
		total_playtime = float(data.get("total_playtime", 0.0))
		_pt_last_msec = Time.get_ticks_msec()

		# P3.10: restore telemetry. Guarded merge into the existing shape so
		# old saves (no telemetry) and any future key drift load safely.
		var saved_tele = data.get("telemetry", {})
		if saved_tele is Dictionary:
			for grp in ["occupancy", "production", "damage_type"]:
				if saved_tele.has(grp) and saved_tele[grp] is Dictionary:
					for k in telemetry[grp]:
						telemetry[grp][k] = float(saved_tele[grp].get(k, 0.0))
			if saved_tele.has("mat_source") and saved_tele["mat_source"] is Dictionary:
				telemetry["mat_source"] = saved_tele["mat_source"].duplicate(true)
			# v135a: restore the per-zone boss-loss rollup (dict).
			if saved_tele.has("boss_losses") and saved_tele["boss_losses"] is Dictionary:
				telemetry["boss_losses"] = saved_tele["boss_losses"].duplicate(true)
			# v135a: restore the funnel event timeline (top-level key; cap on load).
			var saved_log = data.get("event_log", [])
			if saved_log is Array:
				event_log = saved_log.duplicate()
				if event_log.size() > EVENT_LOG_CAP:
					event_log = event_log.slice(event_log.size() - EVENT_LOG_CAP)
		
		# Restore Active Manager
		var offline_combat_enabled = game_settings.get("offline_combat", false)
		
		if gathering_manager.is_active:
			set_active_manager(gathering_manager)
		elif processing_manager.is_active:
			set_active_manager(processing_manager)
		elif research_manager.is_active:
			set_active_manager(research_manager)
		elif combat_manager.in_combat:
			if offline_combat_enabled:
				set_active_manager(combat_manager)
			else:
				# If offline combat is disabled, stop combat upon offline load.
				combat_manager.stop_action()
			
		# Offline Progress
		var last_time = data.get("last_save_time", Time.get_unix_time_from_system())
		var current_time = Time.get_unix_time_from_system()
		var delta = current_time - last_time
		
		if delta > 10:
			# v122 REC_Q4/Q5 Coffers: Warp Tree raises the 24h base cap (×1.5 / ×2).
			var cap_mult: float = warp_manager.get_tree_offline_cap_mult() if warp_manager else 1.0
			var eff_cap: float = OFFLINE_DELTA_CAP_SECONDS * cap_mult
			var capped_delta = min(delta, eff_cap)
			process_offline_progress(capped_delta)
			# v137 FIX (#34): consume the offline window NOW by writing a fresh last_save_time.
			# Load applied offline but only re-saved at the 60s autosave / window-close handler
			# — a force-kill inside that window re-applied the SAME delta on the next load
			# (offline double-dip, stacks with any offline over-grant). Saving here makes the
			# next boot's delta ~0. All managers are loaded + offline-applied by this point, so
			# this persists complete, consistent state (atomic .tmp->rename->.bak).
			save_game()
			# v112: the telemetry welcome modal builds its own headline from these.
			offline_away_sec = capped_delta
			offline_capped = delta > eff_cap
	else:
		# Both savegame.json and .bak are unreadable. Preserve the corrupt file for
		# manual recovery so the next autosave doesn't bury the evidence; boot fresh.
		push_error("Save load failed (json + bak unreadable): %s" % json.get_error_message())
		if FileAccess.file_exists("user://savegame.json"):
			DirAccess.copy_absolute("user://savegame.json", "user://savegame.corrupt.json")
	
	game_loaded.emit()

func process_offline_progress(delta: float):
	print("Processing offline progress for ", delta, " seconds.")
	# v112: each manager now returns a structured block dict (or null/"" when
	# nothing happened). A non-empty dict is truthy; null and "" are falsy.
	var reports: Array = []

	var g_report = gathering_manager.calculate_offline(delta)
	if g_report: reports.append(g_report)

	var p_report = processing_manager.calculate_offline(delta)
	if p_report: reports.append(p_report)

	var i_report = infrastructure_manager.calculate_offline(delta)
	if i_report: reports.append(i_report)

	# v134h: Warp-Core Charge is now a MANUAL feed on the Warp page — it cannot accrue
	# offline, so there is no offline charge pass or prestige report block here anymore.

	var r_report = research_manager.calculate_offline(delta)
	if r_report: reports.append(r_report)

	# v132: advance the bounty refresh timer offline — it only ticked in the live
	# _process loop, so the 8h board refresh was frozen while away (and its lazy
	# first-seed never fired for players who went straight offline).
	if bounty_manager: bounty_manager.process_tick(delta)

	# v52.1: Optional offline combat
	if game_settings.get("offline_combat", false):
		var c_report = combat_manager.calculate_offline(delta)
		if c_report: reports.append(c_report)
	elif combat_manager.in_combat:
		# Player left mid-fight with offline combat off — explain the silence
		# instead of letting them think combat is broken.
		reports.append({
			"category": "combat", "title": "Combat", "action": "",
			"time_sec": int(delta), "actions": 0, "xp": 0,
			"gains": {}, "drains": {}, "status": "standby",
			"notes": ["Paused — enable Offline Combat in Options to keep fighting while away."],
		})

	offline_report_data = reports

func hard_reset():
	resources.reset()
	resources.seed_starter_kit()  # New Game gets the same Distress Cache as a first launch
	# v107: resources.reset() intentionally KEEPS lifetime_credits because
	# warp_manager.execute_warp() relies on it staying monotonic (the warp
	# formula uses `lifetime_credits - credits_at_warp_start` as the delta).
	# But hard reset is a brand-new playthrough — that lifetime number MUST
	# be zeroed, otherwise calculate_warp_gains() returns > 0 immediately,
	# the P0 fanfare trips on the first credit reward (e.g. first mission
	# claim), and the Warp tab pops up on a fresh game.
	resources.lifetime_credits = 0.0
	gathering_manager.reset()
	processing_manager.reset()
	infrastructure_manager.reset()
	shipyard_manager.reset()
	research_manager.reset()
	combat_manager.reset()
	# v107: warp_manager MUST reset BEFORE mission_manager — the INTO THE VOID
	# mission re-evaluates current_qty from warp_manager.total_warps every
	# tick, so leaving warp state stale would auto-complete the mission on a
	# fresh playthrough. Same path clears all Mastery Tree purchases.
	if warp_manager: warp_manager.reset()
	if fleet_manager: fleet_manager.reset()
	# Clear the P0 prestige-reveal flag so the fanfare can fire again for
	# the new playthrough.
	game_settings.erase("warp_first_revealed")
	# v109: same for the Recursion discovery pointer.
	game_settings.erase("recursion_revealed")
	# v109: re-lock Cryo on a fresh game (it's a first-Warp unlock).
	game_settings.erase("cryo_unlocked")
	# v109: re-lock the Z11 Warp Gate on a fresh game.
	game_settings.erase("z11_unlocked")
	# v113 (NG+): re-lock the Z12 Rift frontier + its clear-gate flag.
	game_settings.erase("z10_cleared")
	game_settings.erase("z11_cleared")
	game_settings.erase("z12_unlocked")
	# v113 (NG+ P2): re-lock earned Threshold Relics (master keys) + empty the slot.
	# (shipyard_manager.reset() above wiped inventory but leaves equipped_relic.)
	game_settings.erase("rift_relic_earned")
	if shipyard_manager: shipyard_manager.equipped_relic = ""
	# Re-arm the one-time "enable Offline Combat" tip for the new playthrough.
	game_settings.erase("offline_combat_nudge_seen")
	# v125: re-arm the offline-combat durability-risk consent prompt.
	game_settings.erase("offline_combat_warned")
	mission_manager.reset()
	if quest_manager: quest_manager.reset()
	# v132: bounty was the ONLY manager missing here (it had no reset() at all) —
	# a New Game inherited the old playthrough's contracts, including completed
	# endgame deliveries worth tens of millions, claimable on the fresh save.
	if bounty_manager: bounty_manager.reset()

	# P3.10: telemetry is a fresh-playthrough metric — clear on hard reset.
	for grp in ["occupancy", "production", "damage_type"]:
		for k in telemetry[grp]:
			telemetry[grp][k] = 0.0
	telemetry["mat_source"] = {}  # free-form per-material map — just empty it
	telemetry["boss_losses"] = {}  # v135a: per-zone boss-loss rollup
	event_log = []                 # v135a: funnel timeline (lifetime; clears on hard reset only, NOT warp)

	# Re-show first-visit page tours on a fresh playthrough
	game_settings["coach_seen"] = {}

	# v114: New Game is a gated playthrough (front/back sector-hardening on).
	game_settings["tier_gate_enabled"] = true

	# New Game = brand new lifetime clock (Warp prestige does NOT reset this)
	total_playtime = 0.0
	_pt_last_msec = Time.get_ticks_msec()

	was_resetted = true
	game_resetted.emit()
	
	# v134c: clear EVERY save artifact, not just the primary. Now that load_game
	# recovers from .bak when .json is missing, a lingering .bak would RESURRECT the
	# pre-reset save on the next boot if the player started a New Game and quit
	# before the first autosave wrote a fresh .json. Wipe .bak/.tmp/.corrupt too so
	# New Game is durable.
	for p in ["user://savegame.json", "user://savegame.bak", "user://savegame.tmp", "user://savegame.corrupt.json"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func load_elements_db():
	var file = FileAccess.open("res://assets/elements.json", FileAccess.READ)
	if file:
		var content = file.get_as_text()
		var json = JSON.new()
		var error = json.parse(content)
		if error == OK:
			elements_db = json.data
			print("Loaded elements_db: ", elements_db.size(), " entries.")
		else:
			print("Failed to parse elements.json: ", json.get_error_message())
	else:
		print("Failed to open res://assets/elements.json")

func get_element_data(symbol: String) -> Dictionary:
	for element in elements_db:
		if element.get("symbol") == symbol:
			return element
	return {}
