extends Node
# ============================================================================
# AFFIX + MATRIX-CORE SANITY (v141) — are the bonuses REAL?
#
# bonus_audit.gd proves card == online == offline for the yield pipeline. This
# asks a different question about ship bonuses:
#   1. WIRED   — every AFFIX_DB id must have a slot in affix_bonuses, or
#                recalc_stats silently drops it (`if affix_id in affix_bonuses`).
#   2. LIVE    — every key gameplay READS must be one something can produce,
#                or the feature is dead code multiplying zero.
#   3. SANE    — ranges/caps ordered, tiers monotonic, no cap below one core.
#   4. CAPPED  — every gem facet has a cap, and caps actually bind.
#
# This class of bug is invisible to grep and to parity tests: the numbers all
# agree, they just agree on nothing happening.
#   Godot --headless --path <root> res://scenes/affix_gem_sanity.tscn
# ============================================================================

# Keys gameplay reads out of affix_bonuses. Kept here (not grepped) so the check
# fails loudly when someone adds a read for a bonus nothing grants.
# v161: extractor_efficiency / nano_scavenger / refinery_link were removed from the
# game — three v74.0 features that read a bonus no AFFIX_DB entry ever granted, so
# each multiplied a permanent 0.0. Their read sites are deleted; this list must not
# name them or the audit reports a finding that no longer exists.
const READ_KEYS := {
	"enemy_drop_mult": "combat_manager win_fight loot",
	"module_drop_mult": "get_effective_module_drop_chance",
	"stone_drop_mult": "combat_manager._roll_hack_stone_drops",
}

var fails := 0
var warns := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond: fails += 1
	print("[SANITY] %-52s %s %s" % [name, "OK" if cond else "*** FAIL", detail])

func _warn(msg: String) -> void:
	warns += 1
	print("[SANITY]   !! %s" % msg)


func _ready() -> void:
	GameState.set_process(false)
	GameState.hard_reset()
	var sm = GameState.shipyard_manager
	print("[SANITY] ============ affix + matrix core sanity ============")

	# ── 1. Every AFFIX_DB id must be aggregatable ──
	# recalc_stats: `if affix_id in affix_bonuses` — an id missing from that dict
	# rolls onto gear, shows in the tooltip, and is then thrown away.
	var unaggregatable := []
	for a_id in sm.AFFIX_DB:
		if not sm.affix_bonuses.has(a_id):
			unaggregatable.append(String(a_id))
	_ok("every AFFIX_DB id has an affix_bonuses slot", unaggregatable.is_empty(),
		str(unaggregatable))

	# ── 2. Every key gameplay READS must be producible ──
	var dead := []
	for k in READ_KEYS:
		if not sm.affix_bonuses.has(String(k)):
			dead.append("%s (%s)" % [k, READ_KEYS[k]])
	_ok("no gameplay read of a non-existent bonus", dead.is_empty(), "")
	for d in dead:
		_warn("DEAD READ: %s — always 0.0, the feature never fires" % d)

	# PROVE it rather than infer it from a missing dict key. A "this is dead" finding
	# gets acted on (code deleted), so assert it the expensive way: roll a large batch
	# of legendary drops across every slot type and confirm the id never appears. If a
	# future affix starts granting one of these keys, this flips and the warning above
	# becomes wrong — which is exactly the case a static scan would miss.
	if not dead.is_empty():
		var seen := {}
		for st in ["weapon", "armor", "shield", "engine", "sensor", "battery"]:
			var base := ""
			for mid in sm.modules:
				if String((sm.modules[mid] as Dictionary).get("slot_type", "")) == st:
					base = String(mid)
					break
			if base == "":
				continue
			for i in range(300):
				var cid := String(sm.generate_module_drop(base, 3, 10))
				if cid == "":
					continue
				for a in ((sm.custom_modules.get(cid, {}) as Dictionary).get("affixes", {}) as Dictionary):
					seen[String(a)] = true
		print("[SANITY]   roll proof: %d distinct affixes seen across 1800 legendary drops" % seen.size())
		for d in dead:
			var key: String = String(d).split(" ")[0]
			_ok("  '%s' provably never rolls" % key, not seen.has(key))

	# ── 3. Affix definition sanity ──
	var bad_range := []
	var no_desc := []
	for a_id in sm.AFFIX_DB:
		var cfg: Dictionary = sm.AFFIX_DB[a_id]
		var r: Array = cfg.get("range", [])
		if r.size() != 2 or float(r[0]) <= 0.0 or float(r[1]) < float(r[0]):
			bad_range.append(String(a_id))
		if String(cfg.get("desc", "")) == "":
			no_desc.append(String(a_id))
	_ok("all affix ranges are [min>0, max>=min]", bad_range.is_empty(), str(bad_range))
	_ok("all affixes have a player-facing desc", no_desc.is_empty(), str(no_desc))

	# ── 4. Gem facets: every facet a core grants must have a cap ──
	var uncapped := {}
	var facet_max := {}       # facet -> biggest single-core grant
	for core in sm.GEM_FACETS:
		for role in (sm.GEM_FACETS[core] as Dictionary):
			var facets: Dictionary = sm.GEM_FACETS[core][role]
			for f in facets:
				var v := float(facets[f])
				facet_max[f] = maxf(float(facet_max.get(f, 0.0)), v)
				if not sm.GEM_FACET_CAPS.has(f):
					uncapped[f] = true
	_ok("every gem facet has a cap", uncapped.is_empty(), str(uncapped.keys()))

	# A cap below a single core's grant means one core already wastes part of itself.
	var cap_too_low := []
	for f in facet_max:
		if sm.GEM_FACET_CAPS.has(f) and float(sm.GEM_FACET_CAPS[f]) < float(facet_max[f]):
			cap_too_low.append("%s cap=%.2f < one core %.2f" % [f, float(sm.GEM_FACET_CAPS[f]), float(facet_max[f])])
	_ok("no cap sits below a single core's grant", cap_too_low.is_empty(), str(cap_too_low))

	# Caps that keep multiplicative facets sane (<1.0 or the maths inverts).
	for f in ["ammo_eff", "energy_eff"]:
		if sm.GEM_FACET_CAPS.has(f):
			_ok("%s cap stays < 1.0" % f, float(sm.GEM_FACET_CAPS[f]) < 1.0,
				"%.2f" % float(sm.GEM_FACET_CAPS[f]))

	# ── 5. Core tiers must be monotonic (Cracked < Stable < Pristine < Resonant) ──
	var colors := ["Crimson", "Cobalt", "Topaz", "Amethyst"]
	var tiers := ["Cracked", "Stable", "Pristine", "Resonant"]
	for c in colors:
		for role in ["weapon", "defense", "utility"]:
			var prev := -1.0
			var prev_name := ""
			var ok_mono := true
			var trail := []
			for t in tiers:
				var cid: String = "%s%sCore" % [t, c]
				if not sm.GEM_FACETS.has(cid):
					continue
				var fd: Dictionary = (sm.GEM_FACETS[cid] as Dictionary).get(role, {})
				var total := 0.0
				for f in fd:
					total += float(fd[f])
				trail.append("%s=%.2f" % [t, total])
				if total <= prev:
					ok_mono = false
					prev_name = t
				prev = total
			_ok("%s/%s tiers strictly increase" % [c, role], ok_mono,
				("%s broke it" % prev_name) if not ok_mono else " ".join(trail))

	# ── 6. Research-gated affixes must actually gate (v141) ──
	var gated := []
	for a_id in sm.AFFIX_DB:
		var req := String((sm.AFFIX_DB[a_id] as Dictionary).get("research_req", ""))
		if req != "":
			gated.append("%s->%s" % [a_id, req])
	print("[SANITY]   research-gated affixes: %s" % str(gated))
	for g in gated:
		var parts: PackedStringArray = String(g).split("->")
		var aid: String = parts[0]
		var tech: String = parts[1]
		GameState.research_manager.unlocked_techs.erase(tech)
		var lt: String = String((sm.AFFIX_DB[aid] as Dictionary).get("limit_to", ["sensor"])[0])
		_ok("%s pooled OUT while %s locked" % [aid, tech],
			not (aid in sm._legal_affix_pool(lt)))
		GameState.research_manager.unlocked_techs.append(tech)
		_ok("%s pooled IN once %s researched" % [aid, tech],
			aid in sm._legal_affix_pool(lt))

	print("[SANITY] ---- %d warning(s) ----" % warns)
	print("[SANITY] ============ %s ============" % ("ALL PASS" if fails == 0 else "%d FAIL(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
