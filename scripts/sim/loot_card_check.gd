extends Node
# ============================================================================
# LOOT CARD CHECK (v141c) — the expedition-yield hover card must actually render.
#
# Combat loot tiles now show the full Ship-Designer module card on hover instead
# of a one-line tooltip. The fragile part is the ID: a dropped module is a ROLLED
# instance ("custom_z2_armor_7"), not a base id, and combat_page derives which one
# to hand to module_card.build_module_bbcode. If that resolution is wrong the
# builder returns "" and the tile shows NOTHING on hover — strictly worse than the
# tooltip it replaced, and invisible to a headless boot.
#
#   Godot --headless --path <root> res://scenes/loot_card_check.tscn
# ============================================================================

const _ModuleCard = preload("res://scripts/ui/module_card.gd")

var fails := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		fails += 1
	print("[LOOTCARD] %-46s %s %s" % [name, "OK" if cond else "*** FAIL", detail])


# Mirrors combat_page._build_loot_tile's id resolution exactly. If that logic
# changes without this following, the asserts below stop testing the real path.
func _card_mid_for(str_id: String, sm) -> String:
	if not (str_id.begins_with("custom_") or sm.modules.has(str_id)):
		return ""
	var mid := str_id
	if str_id.begins_with("custom_") and not sm.modules.has(str_id):
		var parts := str_id.split("_")
		var base_id := str_id.trim_prefix("custom_")
		if parts.size() > 2 and parts[parts.size() - 1].is_valid_int():
			base_id = base_id.trim_suffix("_" + parts[parts.size() - 1])
		mid = base_id
	return str_id if sm.modules.has(str_id) else mid


func _ready() -> void:
	GameState.hard_reset()
	var sm = GameState.shipyard_manager
	print("[LOOTCARD] ============ loot hover card ============")

	# 1. A plain base module (crafted, always in sm.modules).
	var base_id := "z1_kinetic"
	_ok("base module present", sm.modules.has(base_id), base_id)
	var bb_base: String = _ModuleCard.build_module_bbcode(_card_mid_for(base_id, sm))
	_ok("base module renders a card", bb_base.length() > 40, "%d chars" % bb_base.length())

	# 2. A ROLLED drop — the case the tooltip change actually targets.
	var rolled := ""
	for r in [sm.Rarity.UNCOMMON, sm.Rarity.RARE, sm.Rarity.LEGENDARY]:
		rolled = sm.generate_module_drop(base_id, r, 2)
		if rolled != "":
			break
	_ok("generated a rolled drop", rolled != "", rolled)
	if rolled != "":
		var resolved := _card_mid_for(rolled, sm)
		_ok("rolled id resolves", resolved != "", "%s -> %s" % [rolled, resolved])
		var bb: String = _ModuleCard.build_module_bbcode(resolved)
		_ok("rolled drop renders a card", bb.length() > 40, "%d chars" % bb.length())
		# The card must carry the ROLL's own data, not the base module's — that is
		# the whole reason to prefer the custom id over the base. Compare
		# case-insensitively: the card renders its title uppercased.
		# A rolled module's stored name carries a rarity suffix ("Mass Driver Mk.I
		# (Uncommon)"); the card prints the bare name and renders the rarity on its
		# own line, so compare against the part before " (".
		var nm := String(sm.modules[resolved].get("name", "?"))
		var bare := nm.split(" (")[0]
		_ok("card names the module", bb.to_lower().contains(bare.to_lower()), bare)
		# And it must show the ROLLED rarity, which is what distinguishes this
		# instance from the plain base module.
		var rar := int(sm.modules[resolved].get("rarity", 0))
		_ok("rolled module is above Common", rar > 0, "rarity %d" % rar)

	# 3. A custom id whose registry entry is GONE (save churn / stale loot dict).
	# Must fall back to the base module rather than resolving to nothing.
	var orphan := "custom_%s_999" % base_id
	var fallback := _card_mid_for(orphan, sm)
	_ok("orphan custom id falls back to base", fallback == base_id, "%s -> %s" % [orphan, fallback])
	_ok("orphan still renders a card",
		_ModuleCard.build_module_bbcode(fallback).length() > 40)

	# 4. Materials must NOT resolve — they keep the cheap native tooltip.
	for mat in ["Fe", "credits", "Steel"]:
		_ok("material %s takes no card" % mat, _card_mid_for(mat, sm) == "")

	# 5. no_hints: the loot tile doesn't wire shift-click/right-click, so the card
	# must not advertise them there — while the Designer card still does.
	sm.module_inventory[base_id] = maxi(1, int(sm.module_inventory.get(base_id, 0)))
	var with_hints: String = _ModuleCard.build_module_bbcode(base_id)
	var no_hints: String = _ModuleCard.build_module_bbcode(base_id, "", false, true)
	var pin_txt := tr("Shift-click to pin & compare two modules")
	var rec_txt := tr("Right-click to recycle for parts")
	_ok("designer card KEEPS the compare hint", with_hints.contains(pin_txt))
	_ok("designer card KEEPS the recycle hint", with_hints.contains(rec_txt))
	_ok("loot card DROPS the compare hint", not no_hints.contains(pin_txt))
	_ok("loot card DROPS the recycle hint", not no_hints.contains(rec_txt))
	# The stats body must survive — hiding hints must not blank the card.
	_ok("loot card still renders stats", no_hints.length() > 40, "%d chars" % no_hints.length())

	print("[LOOTCARD] ============ %s ============" % ("ALL PASS" if fails == 0 else "%d FAIL(S)" % fails))
	get_tree().quit(1 if fails > 0 else 0)
