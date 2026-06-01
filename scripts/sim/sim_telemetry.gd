extends RefCounted

# JSONL telemetry sink. One record per line: {"t": "<type>", ...}.
# Record types emitted by the runner:
#   meta    — run header (archetype, seed, schedule, game/harness version)
#   snap    — periodic state snapshot (session boundary + offline return)
#   event   — discrete: MILESTONE / WARP / RESEARCH / STALL
#   summary — run footer (time-to-milestone, time-to-first-warp, totals)

var _f: FileAccess = null

func open_path(path: String) -> bool:
	_f = FileAccess.open(path, FileAccess.WRITE)
	if _f == null:
		push_error("[SIM] telemetry: cannot open %s (err %d)" % [path, FileAccess.get_open_error()])
		return false
	return true

func write(rec: Dictionary) -> void:
	if _f:
		_f.store_line(JSON.stringify(rec))
		_f.flush()   # force to disk so live monitors (Get-Content -Wait) see it

func close() -> void:
	if _f:
		_f.flush()
		_f.close()
		_f = null
