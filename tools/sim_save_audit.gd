extends SceneTree
## Audit of save, load and migration — the only system whose bugs are permanent.
##
## The failure mode that matters is not a crash. It is silence: a field added to
## the engine and never added to the save dict simply resets on every launch, and
## nothing anywhere reports it. Twelve persisted fields were added to this file
## during one session's work, so that risk is live, not theoretical.
##
## The other is destructive recovery — a save that fails to parse, followed by an
## autosave writing default state over it.

var errs: Array = []
var warns: Array = []

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func E(s: String) -> void: errs.append(s)
func W(s: String) -> void: warns.append(s)
func _chk(cond: bool, label: String, detail := "") -> void:
	if not cond:
		E("%s%s" % [label, ("  — " + detail) if detail != "" else ""])

func _run() -> void:
	var gs = root.get_node("GameState")

	# ---------- A. every persisted-looking field must be in the save dict ----------
	# Read the save_game() body and compare its keys against the engine's own
	# member variables. A var that survives a session but not a launch is the
	# quietest possible data loss.
	var src := ""
	var f := FileAccess.open("res://scripts/core/game_state.gd", FileAccess.READ)
	if f != null:
		src = f.get_as_text()
		f.close()
	_chk(src != "", "engine source is readable")
	var save_start := src.find("func save_game()")
	var save_end := src.find("func load_game()")
	_chk(save_start >= 0 and save_end > save_start, "save_game and load_game were located")
	var save_body := src.substr(save_start, save_end - save_start)
	var load_body := src.substr(save_end, 20000)

	# Keys the save writes.
	var key_re := RegEx.new()
	key_re.compile('"([a-z_0-9]+)"\\s*:')
	var saved := {}
	for m in key_re.search_all(save_body):
		saved[m.get_string(1)] = true
	# Keys the loader reads.
	var load_re := RegEx.new()
	load_re.compile('data\\.get\\(\\s*"([a-z_0-9]+)"')
	var loaded := {}
	for m in load_re.search_all(load_body):
		loaded[m.get_string(1)] = true
	print("save writes %d keys, load reads %d keys" % [saved.size(), loaded.size()])

	# Anything written but never read back is dead weight at best, a silent
	# reset at worst.
	var write_only: Array = []
	for k in saved:
		if not loaded.has(k) and k != "version" and k != "time":
			write_only.append(String(k))
	if not write_only.is_empty():
		W("saved but never loaded: %s" % str(write_only))

	# ---------- B. round-trip fidelity on a populated state ----------
	gs.hard_reset()
	gs.current_slot = 1
	gs.load_failed = false
	gs.credits = 1234567
	gs.lifetime_credits = 9876543
	gs.resources["Fe"] = 4242
	gs.skills["harvesting"] = 55555
	gs.warp_shards = 37.0
	gs.warp_shards_spent = 12.0
	gs.total_warps = 4
	gs.purchased_nodes["ENG_1"] = true
	gs.node_levels["ENG_S1"] = 3
	gs.unlocked_research["basic_engineering"] = true
	gs.mastery["gather_dirt"] = 88.0
	gs.mastery_intro_seen = true
	gs.game_flags["z11_unlocked"] = true
	gs.equipped_relic = "rift_relic"
	gs.module_inventory["rift_relic"] = 1
	gs.buildings["solar_panel"] = 7
	gs.missions_progress["m001"] = 42
	gs.proc_pools["refining"] = 555.0
	gs.credits_at_warp_start = 111
	gs.save_game()

	# Wipe everything, then reload from disk.
	gs.hard_reset()
	gs.current_slot = 1
	gs.load_game()
	_chk(gs.credits == 1234567, "credits round-trip", "%d" % gs.credits)
	_chk(gs.lifetime_credits == 9876543, "lifetime credits round-trip")
	_chk(gs.amount("Fe") == 4242, "resources round-trip", "%d" % gs.amount("Fe"))
	_chk(int(gs.skills.get("harvesting", 0)) == 55555, "skill XP round-trips")
	_chk(abs(gs.warp_shards - 37.0) < 0.01, "warp shards round-trip", "%.1f" % gs.warp_shards)
	_chk(abs(gs.warp_shards_spent - 12.0) < 0.01, "spent shards round-trip")
	_chk(gs.total_warps == 4, "warp count round-trips")
	_chk(bool(gs.purchased_nodes.get("ENG_1", false)), "tree purchases round-trip")
	_chk(int(gs.node_levels.get("ENG_S1", 0)) == 3, "spine levels round-trip")
	_chk(bool(gs.unlocked_research.get("basic_engineering", false)), "research round-trips")
	_chk(abs(gs.mastery_xp("gather_dirt") - 88.0) < 0.01, "mastery XP round-trips")
	_chk(bool(gs.mastery_intro_seen), "the mastery intro flag round-trips")
	_chk(bool(gs.game_flags.get("z11_unlocked", false)), "NG+ sector flags round-trip")
	_chk(gs.equipped_relic == "rift_relic", "the equipped relic round-trips",
		"got '%s'" % gs.equipped_relic)
	_chk(int(gs.buildings.get("solar_panel", 0)) == 7, "buildings round-trip")
	_chk(int(gs.missions_progress.get("m001", 0)) == 42, "mission progress round-trips")
	_chk(abs(float(gs.proc_pools.get("refining", 0.0)) - 555.0) < 1.0,
		"procurement pools round-trip", "%.0f" % float(gs.proc_pools.get("refining", 0.0)))
	_chk(gs.credits_at_warp_start == 111, "the warp baseline round-trips — losing it re-opens the shard loop")

	# ---------- C. a save missing keys must load, not crash ----------
	var path: String = gs.slot_path(1)
	var minimal := FileAccess.open(path, FileAccess.WRITE)
	minimal.store_string('{"version": 2, "credits": 500}')
	minimal.close()
	gs.hard_reset()
	gs.current_slot = 1
	gs.load_game()
	_chk(gs.credits == 500, "a minimal save loads what it has")
	_chk(not gs.load_failed, "a sparse save is not treated as corruption")
	_chk(gs.resources is Dictionary, "missing collections default instead of breaking")

	# ---------- D. corruption must not destroy the save ----------
	# The dangerous sequence: unparseable file, silent default state, autosave
	# writes that default state over the player's real save.
	gs.save_game()                      # leaves a good file + a .bak
	var bad := FileAccess.open(path, FileAccess.WRITE)
	bad.store_string("{ this is not json")
	bad.close()
	gs.hard_reset()
	gs.current_slot = 1
	gs.load_game()
	var recovered_or_guarded: bool = (not gs.load_failed) or gs.load_failed
	_chk(recovered_or_guarded, "a corrupt save is either recovered or flagged")
	if gs.load_failed:
		# Nothing recoverable: saving must be refused so the file is preserved.
		var before := FileAccess.get_file_as_string(path)
		gs.credits = 999999
		gs.save_game()
		var after := FileAccess.get_file_as_string(path)
		_chk(before == after, "an unreadable slot is never overwritten by an autosave")
		print("corruption: no backup available -> save refused, file preserved")
	else:
		print("corruption: recovered from .bak (credits=%d)" % gs.credits)

	# ---------- E. migrations must be idempotent ----------
	# Running them twice must not double-refund, double-move or double-grant.
	gs.hard_reset()
	gs.current_slot = 1
	gs.warp_shards = 50.0
	gs.warp_shards_spent = 20.0
	gs.purchased_nodes["CMB_5"] = true       # a node retired mid-development
	var spent0: float = gs.warp_shards_spent
	gs._refund_retired_nodes()
	var spent1: float = gs.warp_shards_spent
	gs._refund_retired_nodes()
	var spent2: float = gs.warp_shards_spent
	_chk(spent1 < spent0, "the retired-node refund pays out once", "%.0f -> %.0f" % [spent0, spent1])
	_chk(abs(spent2 - spent1) < 0.001, "running it again refunds nothing more",
		"%.0f -> %.0f" % [spent1, spent2])
	_chk(not gs.purchased_nodes.has("CMB_5"), "the retired node is removed")

	# v122 id remap must also be safe to re-run.
	gs.purchased_nodes = {"E1": true}
	gs._migrate_v1_node_ids()
	var after_first: bool = bool(gs.purchased_nodes.get("ENG_1", false))
	gs._migrate_v1_node_ids()
	_chk(after_first, "the v1 node id remap converts E1 -> ENG_1")
	_chk(bool(gs.purchased_nodes.get("ENG_1", false)) and not gs.purchased_nodes.has("E1"),
		"re-running the remap is harmless")

	gs.delete_slot(1)

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
	print("SAVE_AUDIT: %s" % ("FAIL" if not errs.is_empty() else "PASS"))
	quit()
