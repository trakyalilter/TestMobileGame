extends Node
## Core game engine. Autoloaded as `GameState`.
## Single-active-task model (like Melvor/HorizonIdle) with offline progress.

signal resources_changed
signal skills_changed
signal tech_changed
signal action_changed

var resources: Dictionary = {}          # symbol -> int
var skills: Dictionary = {              # skill_id -> total xp
	"harvesting": 0,
	"fabrication": 0,
	"combat": 0,
}
var unlocked_tech: Dictionary = {}      # tech_id -> true

# The single foreground task currently running.
var active_type: String = ""            # "gather" | "craft" | "combat" | ""
var active_id: String = ""
var progress: float = 0.0

# Combat state
var combat_hp: float = 0.0              # current hull HP (regenerates over time)
const HP_REGEN := 0.04                  # fraction of max HP restored per second

# Set during load(); main.gd reads & clears it to show the welcome-back modal.
var pending_offline: String = ""

const SAVE_PATH := "user://stellarforge_save.json"
const AUTOSAVE_INTERVAL := 15.0
var _save_accum := 0.0

func _ready() -> void:
	load_game()
	if combat_hp <= 0.0:
		combat_hp = combat_max_hp()

func _process(delta: float) -> void:
	_tick_active(delta)
	# Hull regenerates toward max whether fighting or not.
	var mx := combat_max_hp()
	if combat_hp < mx:
		combat_hp = minf(mx, combat_hp + mx * HP_REGEN * delta)
	_save_accum += delta
	if _save_accum >= AUTOSAVE_INTERVAL:
		_save_accum = 0.0
		save_game()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		save_game()

# ---------------- Resources ----------------
func amount(sym: String) -> int:
	return int(resources.get(sym, 0))

func add_resource(sym: String, amt: int) -> void:
	resources[sym] = amount(sym) + amt
	resources_changed.emit()

func can_afford(cost: Dictionary) -> bool:
	for sym in cost:
		if amount(sym) < int(cost[sym]):
			return false
	return true

func spend(cost: Dictionary, times: int = 1) -> void:
	for sym in cost:
		resources[sym] = amount(sym) - int(cost[sym]) * times
	resources_changed.emit()

# ---------------- Skills / leveling ----------------
func xp_for_level(lvl: int) -> int:
	if lvl <= 1:
		return 0
	return int(40.0 * pow(lvl - 1, 1.6))

func level_of(skill_id: String) -> int:
	var xp := int(skills.get(skill_id, 0))
	var lvl := 1
	while xp >= xp_for_level(lvl + 1):
		lvl += 1
	return lvl

func add_xp(skill_id: String, amt: int) -> void:
	skills[skill_id] = int(skills.get(skill_id, 0)) + amt
	skills_changed.emit()

## Sum of a named effect across all unlocked tech (e.g. "gather_yield", "gather_speed").
func tech_bonus(key: String) -> float:
	var s := 0.0
	for tid in unlocked_tech:
		s += float(GameData.TECH.get(tid, {}).get("effects", {}).get(key, 0.0))
	return s

func yield_mult(skill_id: String) -> float:
	var m := 1.0 + level_of(skill_id) * 0.02   # +2% per level
	if skill_id == "harvesting":
		m += tech_bonus("gather_yield")
	return m

# ---------------- Combat stats ----------------
func combat_max_hp() -> float:
	return 50.0 + level_of("combat") * 10.0

func combat_attack() -> float:
	return 5.0 + level_of("combat") * 2.0

# ---------------- Tech ----------------
func is_unlocked(tech_id: String) -> bool:
	return unlocked_tech.has(tech_id)

func can_unlock(tech_id: String) -> bool:
	if is_unlocked(tech_id):
		return false
	var t: Dictionary = GameData.TECH.get(tech_id, {})
	for r in t.get("req", []):
		if not is_unlocked(r):
			return false
	return can_afford(t.get("cost", {}))

func unlock_tech(tech_id: String) -> bool:
	if not can_unlock(tech_id):
		return false
	var t: Dictionary = GameData.TECH[tech_id]
	spend(t.get("cost", {}))
	unlocked_tech[tech_id] = true
	tech_changed.emit()
	return true

# ---------------- Requirement checks ----------------
func meets_requirements(def: Dictionary, skill_id: String) -> bool:
	if level_of(skill_id) < int(def.get("level_req", 1)):
		return false
	var tr: String = def.get("tech_req", "")
	if tr != "" and not is_unlocked(tr):
		return false
	return true

# ---------------- Active task ----------------
func start_task(type: String, id: String) -> void:
	if active_type == type and active_id == id:
		stop_task()   # tapping an active task toggles it off
		return
	active_type = type
	active_id = id
	progress = 0.0
	action_changed.emit()

func stop_task() -> void:
	active_type = ""
	active_id = ""
	progress = 0.0
	action_changed.emit()

func current_duration() -> float:
	return effective_duration(active_type, active_id)

## Duration after research speed bonuses; works for any action, not just the active one.
func effective_duration(type: String, id: String) -> float:
	if type == "gather" and GameData.GATHER.has(id):
		return float(GameData.GATHER[id].get("duration", 3.0)) / (1.0 + tech_bonus("gather_speed"))
	elif type == "craft" and GameData.CRAFT.has(id):
		return float(GameData.CRAFT[id].get("duration", 3.0)) / (1.0 + tech_bonus("craft_speed"))
	elif type == "combat" and GameData.ENEMIES.has(id):
		# Time to destroy one enemy = its hull / our attack-per-second.
		return maxf(0.5, float(GameData.ENEMIES[id]["hp"]) / combat_attack())
	return 0.0

func _tick_active(delta: float) -> void:
	if active_type == "":
		return
	if active_type == "craft" and not can_afford(GameData.CRAFT[active_id].get("inputs", {})):
		stop_task()   # ran out of inputs
		return
	progress += delta
	var dur := current_duration()
	if dur <= 0.0:
		return
	while progress >= dur:
		progress -= dur
		_complete_active()
		if active_type == "":
			break

func _complete_active() -> void:
	if active_type == "gather":
		var a: Dictionary = GameData.GATHER[active_id]
		var amt := randi_range(int(a["min"]), int(a["max"]))
		amt = maxi(1, int(round(amt * yield_mult("harvesting"))))
		add_resource(a["resource"], amt)
		add_xp("harvesting", int(a.get("xp", 0)))
	elif active_type == "craft":
		var r: Dictionary = GameData.CRAFT[active_id]
		if not can_afford(r.get("inputs", {})):
			stop_task()
			return
		spend(r.get("inputs", {}))
		add_resource(r["output"], int(r.get("amount", 1)))
		add_xp("fabrication", int(r.get("xp", 0)))
	elif active_type == "combat":
		var e: Dictionary = GameData.ENEMIES[active_id]
		# Roll loot for the kill.
		for entry in e.get("loot", []):
			if randf() < float(entry[1]):
				add_resource(entry[0], randi_range(int(entry[2]), int(entry[3])))
		add_xp("combat", int(e.get("xp", 0)))
		# Take damage sustained over the fight; retreat if the hull is breached.
		combat_hp -= float(e.get("dmg", 0.0)) * current_duration()
		if combat_hp <= 0.0:
			combat_hp = combat_max_hp() * 0.25
			stop_task()

# ---------------- Offline progress ----------------
func _apply_offline(delta: float) -> void:
	if active_type == "" or delta < 5.0:
		return
	var dur := current_duration()
	if dur <= 0.0:
		return
	var by_time := int(delta / dur)
	if by_time <= 0:
		return

	if active_type == "gather":
		var a: Dictionary = GameData.GATHER[active_id]
		var avg: float = (int(a["min"]) + int(a["max"])) / 2.0
		var per := maxi(1, int(round(avg * yield_mult("harvesting"))))
		var total := per * by_time
		add_resource(a["resource"], total)
		add_xp("harvesting", int(a.get("xp", 0)) * by_time)
		pending_offline = "Away for %s\n\n+%s %s\n+%d Harvesting XP" % [
			_fmt_time(delta), GameData.fmt(total), GameData.res_name(a["resource"]),
			int(a.get("xp", 0)) * by_time]
	elif active_type == "craft":
		var r: Dictionary = GameData.CRAFT[active_id]
		var by_inputs := 0x7FFFFFFF
		for sym in r.get("inputs", {}):
			by_inputs = mini(by_inputs, int(amount(sym) / int(r["inputs"][sym])))
		var count := mini(by_time, by_inputs)
		if count <= 0:
			return
		spend(r.get("inputs", {}), count)
		var made := int(r.get("amount", 1)) * count
		add_resource(r["output"], made)
		add_xp("fabrication", int(r.get("xp", 0)) * count)
		pending_offline = "Away for %s\n\nCrafted %s %s\n+%d Fabrication XP" % [
			_fmt_time(delta), GameData.fmt(made), GameData.res_name(r["output"]),
			int(r.get("xp", 0)) * count]
	elif active_type == "combat":
		var e: Dictionary = GameData.ENEMIES[active_id]
		# Only auto-farm offline if the fight is sustainable (regen >= incoming damage).
		var net: float = combat_max_hp() * HP_REGEN - float(e.get("dmg", 0.0))
		if net < 0.0:
			return
		add_xp("combat", int(e.get("xp", 0)) * by_time)
		var summary := ""
		for entry in e.get("loot", []):
			var avg: float = (int(entry[2]) + int(entry[3])) / 2.0 * float(entry[1])
			var got := int(round(avg * by_time))
			if got > 0:
				add_resource(entry[0], got)
				summary += "\n+%s %s" % [GameData.fmt(got), GameData.res_name(entry[0])]
		combat_hp = combat_max_hp()
		pending_offline = "Away for %s\n\nDestroyed %d %s%s\n+%d Combat XP" % [
			_fmt_time(delta), by_time, e["name"], summary, int(e.get("xp", 0)) * by_time]

func _fmt_time(secs: float) -> String:
	var s := int(secs)
	var h := s / 3600
	var m := (s % 3600) / 60
	if h > 0:
		return "%dh %dm" % [h, m]
	if m > 0:
		return "%dm %ds" % [m, s % 60]
	return "%ds" % s

# ---------------- Save / load ----------------
func save_game() -> void:
	var data := {
		"version": 1,
		"resources": resources,
		"skills": skills,
		"tech": unlocked_tech.keys(),
		"active_type": active_type,
		"active_id": active_id,
		"progress": progress,
		"combat_hp": combat_hp,
		"time": Time.get_unix_time_from_system(),
	}
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(SAVE_PATH, SAVE_PATH + ".bak")
	DirAccess.rename_absolute(tmp, SAVE_PATH)

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(txt) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return
	var data: Dictionary = json.data

	resources = data.get("resources", {})
	skills = data.get("skills", skills)
	unlocked_tech = {}
	for t in data.get("tech", []):
		unlocked_tech[t] = true
	active_type = data.get("active_type", "")
	active_id = data.get("active_id", "")
	progress = float(data.get("progress", 0.0))
	combat_hp = float(data.get("combat_hp", 0.0))

	var last := float(data.get("time", Time.get_unix_time_from_system()))
	_apply_offline(Time.get_unix_time_from_system() - last)

	resources_changed.emit()
	skills_changed.emit()
	tech_changed.emit()
	action_changed.emit()

func hard_reset() -> void:
	resources = {}
	skills = {"harvesting": 0, "fabrication": 0, "combat": 0}
	unlocked_tech = {}
	pending_offline = ""
	combat_hp = combat_max_hp()
	stop_task()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	resources_changed.emit()
	skills_changed.emit()
	tech_changed.emit()
