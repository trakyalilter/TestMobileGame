extends Node

# Prints each infra category's buildings in the new UI sort order (by build
# credits cost) so we can eyeball that it reads early→late with no inversions.
# Run: tools/run_sim.ps1 -Scene "res://scenes/infra_order_spike.tscn"

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	GameState.set_process(false)
	var im = GameState.infrastructure_manager
	var rm = GameState.research_manager
	var by_cat := {}
	for bid in im.building_db:
		var d = im.building_db[bid]
		var cat: String = str(d.get("category", "industry"))
		if not by_cat.has(cat):
			by_cat[cat] = []
		by_cat[cat].append(bid)

	for cat in ["power", "extraction", "industry", "logistics"]:
		if not by_cat.has(cat):
			continue
		var bids: Array = by_cat[cat]
		# NEW sort: research-unlock tier first (progression gate), credits as
		# tiebreaker within a tier. No-research buildings = tier 0 (available now).
		bids.sort_custom(func(a, b):
			var ta: int = _tier(im, rm, a)
			var tb: int = _tier(im, rm, b)
			if ta != tb:
				return ta < tb
			return _cr(im, a) < _cr(im, b))
		print("[IO] === %s ===" % cat.to_upper())
		for bid in bids:
			var d = im.building_db[bid]
			print("[IO]   T%d  %9d cr  %-26s  (req: %s)" % [
				_tier(im, rm, bid), int(_cr(im, bid)), str(d.get("name", bid)),
				str(d.get("research_req", "-"))])
	print("[IO] done")
	get_tree().quit(0)

func _cr(im, bid: String) -> float:
	return float(im.building_db[bid].get("cost", {}).get("credits", 0.0))

func _tier(im, rm, bid: String) -> int:
	var req = im.building_db[bid].get("research_req", "")
	var key: String = str(req)
	if key == "" or key == "-" or not rm.tech_tree.has(key):
		return 0
	return int(rm.tech_tree[key].get("tier", 0))
