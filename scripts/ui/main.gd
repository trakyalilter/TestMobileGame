extends Control
## Mobile shell for the ported horizonidle content: grid cards with category
## sub-tabs (gather/craft/combat) and a credit-funded research tree.

# Bottom bar = primary loops; secondary systems live under "More".
const BOTTOM := [
	{"id": "gather",   "label": "Gather"},
	{"id": "craft",    "label": "Craft"},
	{"id": "combat",   "label": "Combat"},
	{"id": "research", "label": "Research"},
	{"id": "more",     "label": "More"},
]
const PAGE_IDS := ["gather", "craft", "combat", "research", "more", "build", "shipyard", "ship", "bounty", "standing", "warp", "fleet", "missions", "atlas", "stats", "hazard", "settings"]
const MORE_MENU := [
	{"id": "missions", "label": "✦  Missions"},
	{"id": "build",  "label": "⌂  Infrastructure"},
	{"id": "shipyard", "label": "⚒  Shipyard"},
	{"id": "ship",   "label": "⛭  Ship Designer"},
	{"id": "bounty", "label": "◆  Bounty Board"},
	{"id": "standing", "label": "▤  Standing Orders"},
	{"id": "hazard", "label": "☢  Hazard Zones"},
	{"id": "warp",   "label": "✦  Warp Core"},
	{"id": "fleet",  "label": "❖  Fleet Command"},
	{"id": "atlas",  "label": "❒  Atlas / Codex"},
	{"id": "stats",  "label": "≡  Storage"},
	{"id": "settings", "label": "⚙  Settings"},
]

# ---- Design system tokens ----
const BG_TOP := "0d1426"      # app background gradient
const BG_BOT := "060912"
const SURFACE := "172238"     # card surface
const SURFACE_HI := "1f2c48"  # raised chips / segmented
const INSET := "0c1322"       # recessed wells
const LINE := "2b374f"        # hairline borders / dividers
const C_TEXT := "eef2fb"
const C_DIM := "b3c0db"      # secondary text — lifted for contrast
const C_MUTED := "8c9bbd"    # tertiary / locked text — lifted for contrast
const C_WARN := "ecb44a"
# Accents saturated for the art-direction pass — the muted originals read as a
# utility app; these push the "lit hardware" look while keeping the same hues.
const GOLD := "f5b942"
const CYAN := "4fdcf2"
const GREEN := "57e389"
const RED := "ff6f52"
const PURP := "c08bff"
const BUILD := "ff9d4d"
const C_BG := "0b1220"        # legacy refs
const C_PANEL := "111c2e"
const DOMAIN := {"gather": GOLD, "craft": CYAN, "combat": RED, "research": PURP, "more": CYAN}
# Hamburger drawer — every page reachable from one slide-out menu.
const NAV_ALL := [
	{"id": "gather",   "label": "Gather",         "icon": "↑"},
	{"id": "craft",    "label": "Craft",          "icon": "⚙"},
	{"id": "combat",   "label": "Combat",         "icon": "◎"},
	{"id": "research", "label": "Research",       "icon": "✦"},
	{"id": "missions", "label": "Missions",       "icon": "✦"},
	{"id": "build",    "label": "Infrastructure", "icon": "⌂"},
	{"id": "shipyard", "label": "Shipyard",       "icon": "⚒"},
	{"id": "ship",     "label": "Ship Designer",  "icon": "⛭"},
	{"id": "bounty",   "label": "Bounty Board",   "icon": "◆"},
	{"id": "standing", "label": "Standing Orders", "icon": "▤"},
	{"id": "hazard",   "label": "Hazard Zones",   "icon": "☢"},
	{"id": "warp",     "label": "Warp Core",      "icon": "✦"},
	{"id": "fleet",    "label": "Fleet Command",  "icon": "❖"},
	{"id": "atlas",    "label": "Atlas / Codex",  "icon": "❒"},
	{"id": "stats",    "label": "Storage",        "icon": "≡"},
	{"id": "settings", "label": "Settings",       "icon": "⚙"},
]
const DRAWER_W := 540.0

# Global text scale — bumps every font size for phone readability without
# touching individual call sites. Tune this one number to rescale the whole UI.
const FONT_SCALE := 1.65
func _fs(n: int) -> int:
	# Floor keeps ALL text readable — no squint-print anywhere (mobile-game type).
	return maxi(int(round(n * FONT_SCALE)), 14)

var content: Control
var pages := {}
var nav_items := {}
var drawer: Control
var drawer_panel: PanelContainer
var drawer_scrim: ColorRect
var drawer_open := false
var _ham_badge: Panel
var _ham_btn: Button
var _hdr_credits: Label
var _drift: Control
var _drift_y := 0.0
var _hit_flash: ColorRect
var _fx_layer: Control = null   # persistent overlay for spawned juice (never rebuilt)
var _gain_fx_live := 0          # concurrent floating-gain cap (fast loops can't flood)
var _hdr_cpill: PanelContainer = null   # header credits pill (gain-pop tween)
var _hdr_credits_val := -1              # last shown credits (count-up diff + de-dupe)
var _coach_banner: PanelContainer
var _coach_obj: Label
var _coach_hint: Label
var _pulse_tween: Tween
var _pulse_target: Control
# Unmissable on-target pointer: a glowing animated ring + a "▸ Tap here" chip that
# overlay (and track) the resolved coach target. Built lazily, hidden when no target.
var _coach_ptr: Control = null
var _coach_ring: Panel = null
var _coach_chip: PanelContainer = null
var _welcome: Control = null
var _welcome_done := false
var current := ""

# --- Global drag-to-scroll -------------------------------------------------
# Cards are covered by full-rect tap Buttons, which consume touch drags so the
# page can't be scrolled by dragging on a card. We intercept drags in _input
# (runs before GUI), scroll the innermost scrollable container under the finger,
# and cancel the pending tap so a drag doesn't also fire a click. Inertia gives
# a flick a little glide. Disabled while an overlay/drawer/char-select is up.
const DRAG_DEADZONE := 10.0
var _drag_active := false
var _drag_moved := false
var _drag_is_touch := false
var _drag_target: ScrollContainer = null
var _drag_start := Vector2.ZERO
var _drag_scroll0_v := 0
var _drag_scroll0_h := 0
var _drag_last_v := 0
var _drag_last_h := 0
var _drag_last_ms := 0
var _drag_vel := 0.0
var _drag_vel_h := 0.0
var _drag_cancel_btn: BaseButton = null   # button disabled mid-drag to suppress its tap
# Open modal overlays (top of stack = frontmost). Drag-scroll targets the top
# modal's own scroll container so its content scrolls instead of the page behind.
var _modal_stack: Array = []
var gather_cat := "terrestrial"
var craft_cat := "basics"
var munitions_type := "all"   # Munitions sub-filter: all / kinetic / energy / explosive
var craft_query := ""         # Craft search — matches across ALL categories (output material / name)
var _craft_results: VBoxContainer = null   # craft grid wrapper, refilled live on search
var combat_zone := 0
var research_tab := "Operations"
var atlas_mode := "materials"
var atlas_mat_cat := "gathered"
var atlas_query := ""
var _atlas_index := {}
var _atlas_results: VBoxContainer = null   # results container refilled live on search
var storage_query := ""                    # Storage page material-name filter
var _storage_results: VBoxContainer = null # storage grid wrapper refilled live on search
var _storage_qty_labels := {}              # sym -> qty Label, for live in-place updates
var _storage_tile_syms := []               # owned syms currently tiled (detect structure change)
var _storage_worth_label: Label = null     # the "Storage X/Y · worth ₡Z" header, updated live
var _debounce_gen := {}                     # per-key generation counters for _debounce
var _research_hs: ScrollContainer = null   # research 2D scroller, sized to the visible page
# Research-tree pinch zoom: a user multiplier on top of the auto-fit scale, driven
# by two-finger pinch (focal-preserving) and the on-screen +/- controls.
var _research_canvas: Control = null
var _research_frame: Control = null
var _research_zoom := 1.0          # user zoom (persists across rebuilds / tab switches)
var _research_base_fit := 1.0      # auto-fit-to-width scale computed per tree
var _res_cw := 0.0
var _res_ch := 0.0
var _touches := {}                 # active finger index -> screen position
var _pinch_active := false
var _pinch_start_dist := 0.0
var _pinch_start_zoom := 1.0
const RES_ZOOM_MIN := 0.5
const RES_ZOOM_MAX := 2.6
const RES_BOTTOM_PAD := 140.0      # unscaled pad so the last tree row clears the screen edge
var build_cat := "power"
var ship_view := "loadout"
var shipyard_view := "modules"  # Shipyard (fabrication) sub-tab — separate from ship_view
var shipyard_zone := 0          # Shipyard shop secondary filter: 0 = all, else a zone difficulty
var armory_sort := "power"      # Armory sort: "power" | "zone" | "rarity"
var armory_zone := 0            # Armory secondary filter: 0 = all, else a zone difficulty
const ARMORY_MAX := 60          # cap rendered Armory tiles (thousands froze the page)
var ship_mod_slot := "weapon"
var ship_target_slot := -1      # slot index the Armory equips INTO (slot-first flow; -1 = browse/auto)
var warp_view := "core"   # "core" | "mastery" — Warp Core page sub-view
var safe_margin: MarginContainer
var active_banner: PanelContainer
var _banner_chip: PanelContainer
var _banner_icon: Label
var _banner_kind: Label
var _banner_name: Label
var _banner_time: Label
var _banner_bar: ProgressBar
var _banner_rate: Label = null   # hero rate readout (right column of the active banner)
var _active_bar: ProgressBar = null
var _active_timer: Label = null
var _skill_bar: ProgressBar = null      # skill XP bar in the page banner — updated live
var _skill_xp_label: Label = null
var _skill_lv_label: Label = null
var _skill_medal: Control = null        # level medallion — scale-pops on level-up
var _held_label: Label = null           # active card's held-quantity chip (live per cycle)
var _held_sym := ""
var _skill_banner_id := ""
# Active gather/craft card's Mastery row — refreshed live in _process (the page is
# not rebuilt on loop completion, so the active action's bar must self-update).
var _mastery_bar: ProgressBar = null
var _mastery_left: Label = null
var _mastery_right: Label = null
var _mastery_id := ""
var _combat_hp_bar: ProgressBar = null
var _combat_hp_label: Label = null
var _enemy_hp_bar: ProgressBar = null
var _enemy_hp_label: Label = null
var _enemy_shield_bar: ProgressBar = null
var _player_shield_bar: ProgressBar = null
var _player_heat_bar: ProgressBar = null
var _enemy_anchor: Control = null
var _player_anchor: Control = null
var _enrage_chip: Control = null      # live ENRAGED indicator in the battle view
var _wave_label: Label = null         # live hazard "WAVE x/y" counter
var _enemy_atk_bar: ProgressBar = null  # enemy attack-timer bar (live)
var _weapon_rows: Array = []          # per-weapon {bar, ammo, slot, needs_ammo} — live fire/ammo readout
# Live "SALVAGE THIS RUN" panel — the session-loot container + the snapshot used
# to detect changes so _process only rebuilds rows when a drop actually lands.
var _loot_panel: VBoxContainer = null
var _loot_scroll: ScrollContainer = null   # caps the salvage list height; scrolls past it
var _loot_seen_count := -1
var _seen_events := 0
var _reset_armed := false
var _warp_armed := false

func _ready() -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
	_apply_theme()
	_build()
	GameState.resources_changed.connect(_on_resources)
	GameState.skills_changed.connect(_on_tick)
	GameState.research_changed.connect(_refresh_all)
	GameState.action_changed.connect(_on_action_changed)
	GameState.action_changed.connect(_refresh_banner)
	GameState.bounty_changed.connect(_on_tick)
	GameState.standing_orders_changed.connect(_on_orders_changed)
	GameState.missions_changed.connect(_on_missions_changed)
	GameState.offline_ready.connect(_on_offline_ready)
	GameState.cycle_completed.connect(_on_cycle_completed)   # idle juice: floating +N gains
	GameState.level_up.connect(_on_level_up)
	GameState.feature_revealed.connect(func(title: String, msg: String) -> void:
		_celebrate(title, msg, PURP))
	GameState.storage_full.connect(_on_storage_full)
	get_viewport().size_changed.connect(_update_safe_area)
	call_deferred("_update_safe_area")
	_refresh_top()
	_refresh_banner()
	# Boot lands on the Melvor-style character-select screen. No slot is active yet;
	# the game UI underneath is built but stays hidden behind the overlay until the
	# player picks a slot (Play) or creates a new character. _enter_game() runs the
	# original in-game entry flow once a slot is live.
	_show_char_select()

# ============================================================ COACHING
# Pulses the next thing to tap based on the active tutorial mission, and shows a
# directive banner — adapted from the desktop nav-hint system to the drawer UI.
# Base page per mission type. NOTE: "gather" is resolved dynamically (gather vs
# craft) by _coach_resolve, since several "gather" missions target crafted materials
# (the desc says "On the Craft tab"). visit_page routes to its own target page.
const COACH_PAGE := {"gather": "gather", "gather_multi": "craft", "research": "research", "research_multi": "research", "craft": "shipyard", "construct": "shipyard", "build": "build", "defeat": "combat", "loadout_check": "ship", "loadout_rare_weapon": "ship", "equip_consumables": "ship", "drop_rarity": "combat", "warp_perform": "warp", "discover": "research", "hack_apply": "ship", "overclock_install": "build"}

func _page_label(id: String) -> String:
	for t in NAV_ALL:
		if t.id == id:
			return t.label
	return id.capitalize()

func _coach_active_mission() -> String:
	# Prefer the actionable chapter/tutorial mission for the coach pointer — a
	# [CORE GOAL] (e.g. "perform your first Warp") can point at a page that isn't
	# in the menu yet, which dead-ends the "tap ☰ → …" guidance. Core goals still
	# show in the Missions list; they just don't hijack the pointer.
	# v133 ranking: claimable > tutorial (non-goal) > goals — via the shared helper.
	var picked := GameState.get_active_objective()
	if picked != "" and not String(GameData.MISSIONS.get(picked, {}).get("name", "")).begins_with("[CORE GOAL]"):
		return picked
	# Goals never hijack the pointer while any tutorial step is active.
	var first := picked
	var actionable := ""
	for mid in GameState.missions_active:
		if first == "":
			first = mid
		if actionable == "" and not String(GameData.MISSIONS.get(mid, {}).get("name", "")).begins_with("[CORE GOAL]"):
			actionable = mid
	return actionable if actionable != "" else first

func _gather_action_for(sym: String) -> String:
	var best := ""
	var best_lvl := 99999
	for gid in GameData.GATHER:
		for row in GameData.GATHER[gid].get("loot", []):
			if row[0] == sym:
				var lvl := int(GameData.GATHER[gid].get("level_req", 1))
				if lvl < best_lvl:
					best_lvl = lvl
					best = gid
	return best

# The earliest-unlocked CRAFT recipe that outputs `sym` — used to point "gather"
# missions whose material is actually crafted (e.g. Carbon, Lithium, Steel) at the
# right Craft card instead of a non-existent gather action.
func _craft_recipe_for(sym: String) -> String:
	# Pick the recipe that produces `sym` the player is most able to use, so the
	# coach points at the right card. Prefer ones whose RESEARCH is unlocked (and
	# then level met) over a lower-level recipe gated behind research they lack —
	# e.g. Advanced Circuit's recipe (research: Automation, unlocked) over Process
	# Colony Salvage (lower level but research: Deep Space Nav, not yet unlocked).
	var best := ""
	var best_score := -1
	var best_lvl := 99999
	var lv := GameState.level_of("fabrication")
	for cid in GameData.CRAFT:
		var r: Dictionary = GameData.CRAFT[cid]
		if not r.get("outputs", {}).has(sym):
			continue
		var lvl := int(r.get("level_req", 1))
		var rr: String = r.get("research_req", "")
		var research_ok: bool = rr == "" or GameState.is_research_unlocked(rr)
		var score := (2 if (research_ok and lv >= lvl) else (1 if research_ok else 0))
		if score > best_score or (score == best_score and lvl < best_lvl):
			best_score = score
			best_lvl = lvl
			best = cid
	return best

# The CRAFT recipe that produces ALL the outputs of a gather_multi target dict
# (e.g. {Fe, Si} -> Mineral Washing; {BasicBooster, EmergencyPatch} -> falls back to
# the recipe for the first output, since those are two separate recipes).
func _craft_recipe_for_multi(target: Dictionary) -> String:
	for cid in GameData.CRAFT:
		var outs: Dictionary = GameData.CRAFT[cid].get("outputs", {})
		var all := outs.size() > 0
		for sym in target:
			if not outs.has(sym):
				all = false
				break
		if all:
			return cid
	# No single recipe covers every output — point at the recipe for the first one.
	for sym in target:
		var r := _craft_recipe_for(sym)
		if r != "":
			return r
	return ""

# Earliest-zone enemy whose loot table drops `sym` — for "gather" missions that
# actually want a combat drop (e.g. Void Artifact: "defeat them on the Combat tab").
func _enemy_dropping(sym: String) -> String:
	var best := ""
	var best_zone := 99999
	for eid in GameData.ENEMIES:
		for row in GameData.ENEMIES[eid].get("loot", []):
			if row[0] == sym:
				var z := int(GameData.ENEMIES[eid].get("zone", 99))
				if z < best_zone:
					best_zone = z
					best = eid
	return best

# Research tab ("Operations"/"Engineering"/"Ships") that contains a research node —
# so the coach selects the right tab before the node card is built.
func _research_tab_for(node_id: String) -> String:
	for tab in GameData.RESEARCH_GRAPHS:
		if (GameData.RESEARCH_GRAPHS[tab].get("nodes", []) as Array).has(node_id):
			return tab
	return ""

# Zone sub-tab index that contains `eid` — so the coach can select the right sector
# before the enemy card is built into the combat grid.
func _zone_index_for_enemy(eid: String) -> int:
	for i in GameData.ZONES.size():
		if (GameData.ZONES[i].get("enemies", []) as Array).has(eid):
			return i
	return -1

# Resolves the active coach mission to a {page, card} pair. `card` is "" for
# navigate-only steps (loadout/warp/visit_page). Centralizes the page-split routing
# so _update_coach and the verifier agree.
func _coach_resolve(m: Dictionary) -> Dictionary:
	var type: String = m.get("type", "")
	var tgt = m.get("target", "")
	if type == "gather":
		var sym: String = tgt if tgt is String else ""
		var ga := _gather_action_for(sym)
		if ga != "":
			return {"page": "gather", "card": ga}
		var cr := _craft_recipe_for(sym)
		if cr != "":
			return {"page": "craft", "card": cr}     # crafted material → Craft card
		var ed := _enemy_dropping(sym)
		if ed != "":
			return {"page": "combat", "card": ed}    # combat-drop material → enemy card
		return {"page": "gather", "card": ""}
	if type == "gather_multi":
		return {"page": "craft", "card": _craft_recipe_for_multi(tgt if tgt is Dictionary else {})}
	if type == "research_multi":
		# Point at the FIRST not-yet-unlocked tech so the player has a concrete next
		# tap; once all are unlocked the card resolves to "" (navigate-only, claim).
		var locked := GameState.research_multi_first_locked(m)
		if locked == "" and tgt is Array and not (tgt as Array).is_empty():
			locked = String((tgt as Array)[0])
		return {"page": "research", "card": locked}
	if type == "visit_page":
		return {"page": String(tgt), "card": ""}     # target IS the page id
	if type == "discover":
		# A zone is "discovered" by unlocking its gating research — ring that node.
		for z in GameData.ZONES:
			if String(z.get("id", "")) == String(tgt):
				return {"page": "research", "card": String(z.get("research_req", ""))}
		return {"page": "research", "card": ""}
	var page: String = COACH_PAGE.get(type, "")
	var card: String = tgt if tgt is String else ""
	# Navigate-only steps point at a page, not a card.
	if type in ["loadout_check", "loadout_rare_weapon", "equip_consumables", "warp_perform", "drop_rarity"]:
		card = ""
	return {"page": page, "card": card}

func _update_coach() -> void:
	if _coach_banner == null:
		return
	var mid := _coach_active_mission()
	if mid == "" or not GameData.MISSIONS.has(mid):
		_coach_banner.visible = false
		_pulse_stop()
		return
	var m: Dictionary = GameData.MISSIONS[mid]
	_coach_banner.visible = true
	_coach_obj.text = "◆  OBJECTIVE: " + m.get("name", mid)
	var claim := GameState.mission_completed(mid)
	var res := _coach_resolve(m)
	var page: String = res["page"]
	var card: String = res["card"]
	var pulse: Control = null
	if claim:
		_coach_hint.text = "✓ Reward ready — open ☰ → Missions, then tap Claim."
		if current != "missions":
			pulse = _ham_btn
		if drawer_open and nav_items.has("missions"):
			pulse = nav_items["missions"]["btn"]
	elif page == "":
		_coach_hint.text = m.get("desc", "")
	elif drawer_open and page != current and nav_items.has(page):
		_coach_hint.text = "Tap " + _page_label(page) + " to continue"
		pulse = nav_items[page]["btn"]
	elif page != current:
		if drawer_open:
			# Target page isn't a tappable menu row yet (not unlocked/revealed) — the
			# nav_items.has(page) branch above already failed, so don't dead-end the
			# pointer on the hamburger while the menu is open.
			_coach_hint.text = m.get("desc", "")
			pulse = null
		else:
			_coach_hint.text = m.get("desc", "") + "   ·   tap ☰ → " + _page_label(page)
			pulse = _ham_btn
	elif drawer_open:
		# Already on the right page but the drawer is open over it — the target card
		# is occluded, so don't ring it (the ring draws on top of the drawer and
		# looks like it points at random menu rows). Nudge the player to close the
		# menu; the card re-highlights once it's shut.
		_coach_hint.text = "Close the menu to continue ›"
		pulse = null
	elif card != "" and _coach_step_in_progress(res):
		# Player already started the required process (the highlighted card's action
		# is the active task) — stop blinking; the banner just confirms it's underway.
		_coach_hint.text = "✓ In progress — keep it running"
		pulse = null
	elif card != "":
		_coach_hint.text = "▸ Tap the highlighted card to continue"
		pulse = _coach_find_card(card)
		# Card not in the tree yet (combat enemy lives behind a zone sub-tab) — point
		# at the page so the player at least knows they're on the right screen.
		if pulse == null:
			_coach_hint.text = m.get("desc", "")
	else:
		_coach_hint.text = m.get("desc", "")
	_pulse_start(pulse)

# True when the active task IS the coach's highlighted card (the player has started
# the required gather/craft/combat process), so the blinking highlight can stop.
func _coach_step_in_progress(res: Dictionary) -> bool:
	var card: String = res.get("card", "")
	if card == "" or GameState.active_type == "":
		return false
	match res.get("page", ""):
		"gather":
			return GameState.active_type == "gather" and GameState.active_id == card
		"craft", "shipyard":
			return GameState.active_type == "craft" and GameState.active_id == card
		"combat":
			return GameState.active_type == "combat" and GameState.active_id == card
	return false

func _coach_find_card(id: String) -> Control:
	if id == "" or not pages.has(current):
		return null
	var stack: Array = [pages[current]]
	while stack.size() > 0:
		var n = stack.pop_back()
		if n is Control and n.has_meta("coach_id") and String(n.get_meta("coach_id")) == id:
			return n
		for ch in n.get_children():
			stack.append(ch)
	return null

# Lazily builds the pointer overlay (glowing ring + "▸ Tap here" chip). The overlay
# is a full-rect, input-transparent Control layered above the page content but below
# the drawer/welcome, so the highlighted card stays fully tappable.
func _ensure_coach_ptr() -> void:
	if _coach_ptr != null and is_instance_valid(_coach_ptr):
		return
	_coach_ptr = Control.new()
	_coach_ptr.name = "CoachPointer"
	_coach_ptr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_coach_ptr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coach_ptr.visible = false
	add_child(_coach_ptr)
	# Glowing animated ring framing the target.
	_coach_ring = Panel.new()
	_coach_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color(0, 0, 0, 0)
	rs.set_border_width_all(3)
	rs.border_color = Color.html(GOLD)
	rs.set_corner_radius_all(12)
	rs.shadow_color = Color.html(GOLD)
	rs.shadow_color.a = 0.55
	rs.shadow_size = 10
	_coach_ring.add_theme_stylebox_override("panel", rs)
	_coach_ptr.add_child(_coach_ring)
	# Floating "▸ Tap here" chip pinned just above the target.
	_coach_chip = PanelContainer.new()
	_coach_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cs := _bordered(GOLD, _mix(GOLD, "000000", 0.4), 1, 9)
	cs.content_margin_left = 12
	cs.content_margin_right = 12
	cs.content_margin_top = 5
	cs.content_margin_bottom = 5
	_coach_chip.add_theme_stylebox_override("panel", cs)
	var cl := Label.new()
	cl.text = "▸ Tap here"
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_theme_font_size_override("font_size", _fs(11))
	cl.add_theme_color_override("font_color", Color.html(BG_BOT))
	_coach_chip.add_child(cl)
	_coach_ptr.add_child(_coach_chip)

func _pulse_start(c: Control) -> void:
	if c == _pulse_target and _pulse_tween != null and _pulse_tween.is_valid():
		return
	_pulse_stop()
	if c == null or not is_instance_valid(c):
		return
	_pulse_target = c
	_ensure_coach_ptr()
	_coach_ptr.visible = true
	# Keep the overlay drawn above the page content so the ring isn't occluded.
	move_child(_coach_ptr, get_child_count() - 1)
	_position_coach_ptr()
	# Breathing glow on the ring (modulate loop on the overlay, NOT the target —
	# the target stays at full opacity and fully interactive).
	_pulse_tween = _coach_ring.create_tween().set_loops()
	_pulse_tween.tween_property(_coach_ring, "modulate", Color(1.0, 1.0, 1.0, 0.45), 0.6).set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(_coach_ring, "modulate", Color(1.4, 1.25, 0.6, 1.0), 0.6).set_trans(Tween.TRANS_SINE)

# Overlay the ring + chip on the current target's screen rect. Called every frame
# while a target exists so the pointer tracks scroll / layout changes.
func _position_coach_ptr() -> void:
	if not is_instance_valid(_coach_ptr) or not is_instance_valid(_pulse_target):
		return
	# Suppressed while the intro splash covers the screen, or while the drawer is
	# open over the page (the nav-button pulse uses the same overlay path below).
	if (_welcome != null and not _welcome_done) \
			or not _pulse_target.is_visible_in_tree() or _pulse_target.size.x < 2.0:
		_coach_ptr.visible = false
		return
	_coach_ptr.visible = true
	var gr := _pulse_target.get_global_rect()
	var local := gr.position - _coach_ptr.global_position
	var pad := 5.0
	_coach_ring.position = local - Vector2(pad, pad)
	_coach_ring.size = gr.size + Vector2(pad, pad) * 2.0
	# Chip straddles the target's top-left edge — clearly attached to the card
	# without floating up into whatever sits above it (e.g. the sub-tab row).
	var chip_sz := _coach_chip.size
	var cx: float = clampf(local.x + 10.0, 8.0, _coach_ptr.size.x - chip_sz.x - 8.0)
	var cy := local.y - chip_sz.y * 0.55       # ~half over the top edge of the target
	if cy < 4.0:                                # target hugs the screen top — drop it just inside
		cy = local.y + 6.0
	_coach_chip.position = Vector2(cx, cy)

func _pulse_stop() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	if is_instance_valid(_pulse_target):
		_pulse_target.modulate = Color.WHITE
	_pulse_target = null
	if is_instance_valid(_coach_ptr):
		_coach_ptr.visible = false

# Branded intro splash shown on launch (tap or auto to continue); flows into the
# offline "welcome back" report afterward if there is one.
func _show_welcome() -> void:
	_welcome = Control.new()
	_welcome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_welcome.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_welcome)
	var bg := TextureRect.new()
	bg.texture = _space_tex()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_welcome.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_welcome.add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)
	var emblem := _wlabel(col, "✦", 64, CYAN)
	var title := _wlabel(col, "STELLAR FORGE", 38, C_TEXT)
	var tag := _wlabel(col, "Mine · Craft · Conquer the Sectors", 14, GOLD)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 26)
	col.add_child(sp)
	var boot := ["◇  Igniting reactor core", "◇  Calibrating fabrication bays", "◇  Syncing sector network", "◇  All systems nominal"]
	var line_labels := []
	for s in boot:
		line_labels.append(_wlabel(col, s, 12, C_DIM))
	var prompt := _wlabel(col, "tap to begin", 13, CYAN)
	var tap := Button.new()
	tap.flat = true
	tap.focus_mode = Control.FOCUS_NONE
	tap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var eb := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus"]:
		tap.add_theme_stylebox_override(st, eb)
	tap.pressed.connect(_dismiss_welcome)
	_welcome.add_child(tap)
	# Animate everything in, then hold and auto-continue.
	for nd in [emblem, title, tag, prompt] + line_labels:
		nd.modulate.a = 0.0
	var tw := _welcome.create_tween()   # bound to the splash so an early skip kills it cleanly
	tw.tween_property(emblem, "modulate:a", 1.0, 0.4)
	tw.tween_property(title, "modulate:a", 1.0, 0.4)
	tw.tween_property(tag, "modulate:a", 1.0, 0.3)
	for l in line_labels:
		tw.tween_property(l, "modulate:a", 1.0, 0.18)
	tw.tween_property(prompt, "modulate:a", 1.0, 0.3)
	tw.tween_callback(func() -> void:
		var p := prompt.create_tween().set_loops()
		p.tween_property(prompt, "modulate:a", 0.35, 0.7)
		p.tween_property(prompt, "modulate:a", 1.0, 0.7))
	tw.tween_interval(2.2)
	tw.tween_callback(_dismiss_welcome)

func _wlabel(parent: Node, text: String, size: int, color: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", _fs(size))
	l.add_theme_color_override("font_color", Color.html(color))
	parent.add_child(l)
	return l

func _dismiss_welcome() -> void:
	if _welcome == null or _welcome_done:
		return
	_welcome_done = true
	var t := create_tween()
	t.tween_property(_welcome, "modulate:a", 0.0, 0.3)
	t.tween_callback(func() -> void:
		if is_instance_valid(_welcome):
			_welcome.queue_free()
		_welcome = null
		if GameState.pending_offline != "":
			_show_offline(GameState.pending_offline)
			GameState.pending_offline = "")

# ============================================================ CHARACTER SELECT
var _char_select: Control = null

## Relative-time helper for slot summaries ("just now / 5m ago / 3h ago / 2d ago").
func _fmt_ago(unix: float) -> String:
	if unix <= 0.0:
		return "never"
	var d := Time.get_unix_time_from_system() - unix
	if d < 60.0: return "just now"
	if d < 3600.0: return "%dm ago" % int(d / 60.0)
	if d < 86400.0: return "%dh ago" % int(d / 3600.0)
	return "%dd ago" % int(d / 86400.0)

## Melvor-style title screen: "STELLAR FORGE" + a list of save slots. Filled slots
## show a summary + Play/Delete; empty slots offer "+ New Character". Shown on boot.
func _show_char_select() -> void:
	_char_select = Control.new()
	_char_select.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_char_select.mouse_filter = Control.MOUSE_FILTER_STOP
	_char_select.z_index = 50
	add_child(_char_select)
	var bg := TextureRect.new()
	bg.texture = _space_tex()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_char_select.add_child(bg)
	var scrim := ColorRect.new()           # darken the starfield for card contrast
	scrim.color = Color(0, 0, 0, 0.55)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_char_select.add_child(scrim)
	var sc := ScrollContainer.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_char_select.add_child(sc)
	# Fill the scroller's own width (the logical 720, NOT the physical pixel
	# width) so cards never run off the right edge; tall content scrolls. The
	# previous get_viewport_rect() min-width forced the device's raw pixel width.
	var mc := MarginContainer.new()
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for s in ["left", "right"]:
		mc.add_theme_constant_override("margin_" + s, 22)
	for s in ["top", "bottom"]:
		mc.add_theme_constant_override("margin_" + s, 40)
	sc.add_child(mc)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mc.add_child(col)
	# Title block: emblem in a glowing ring, wordmark, roster tagline.
	var ew := CenterContainer.new()
	ew.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(ew)
	ew.add_child(_emblem("✦", CYAN, 88))
	_wlabel(col, "STELLAR FORGE", 32, C_TEXT)
	_wlabel(col, "◆   COMMANDER ROSTER   ◆", 12, GOLD)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 14)
	col.add_child(sp)
	for n in range(1, GameState.SLOT_COUNT + 1):
		col.add_child(_slot_card(n))

# Circular insignia: a ringed disc with a centered glyph/initial. Used for the
# title crest and per-commander avatars on the roster.
func _emblem(glyph: String, accent: String, size: int) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(size, size)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_theme_stylebox_override("panel", _bordered(_mix(accent, INSET, 0.72), accent, 2, int(size / 2.0)))
	var cc := CenterContainer.new()
	p.add_child(cc)
	var l := Label.new()
	l.text = glyph
	l.add_theme_font_size_override("font_size", _fs(int(size * 0.42)))
	l.add_theme_color_override("font_color", Color.html(accent))
	cc.add_child(l)
	return p

## A roster entry: a filled commander card (emblem + name + stat chips + Deploy/
## Rename/Delete) or an empty "Recruit" slot with a Create button. `n` is 1..SLOT_COUNT.
func _slot_card(n: int) -> Control:
	var summary: Dictionary = GameState.slot_summary(n)
	var filled: bool = summary.get("exists", false)
	var accent := CYAN if filled else C_MUTED
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg := _mix(accent, SURFACE, 0.86) if filled else INSET
	panel.add_theme_stylebox_override("panel", _bordered(bg, _mix(accent, LINE, 0.45) if filled else LINE, 2 if filled else 1, 14))
	var pad := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + s, 12)
	panel.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 11)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(col)

	# Identity row: circular emblem + name/stats.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	col.add_child(top)
	var idv := VBoxContainer.new()
	idv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	idv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	idv.add_theme_constant_override("separation", 5)

	if filled:
		var nm_str := String(summary.get("name", "Commander"))
		top.add_child(_emblem(nm_str.substr(0, 1).to_upper(), accent, 58))
		top.add_child(idv)
		var nm := Label.new()
		nm.text = nm_str
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.add_theme_font_size_override("font_size", _fs(18))
		nm.add_theme_color_override("font_color", Color.html(C_TEXT))
		idv.add_child(nm)
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 6)
		chips.add_theme_constant_override("v_separation", 6)
		chips.add_child(_tag_chip("⚔ Lv %d" % int(summary.get("combat_level", 1)), RED))
		chips.add_child(_tag_chip("₡ %s" % GameData.fmt(int(summary.get("credits", 0))), GOLD))
		chips.add_child(_tag_chip("◎ %s" % String(summary.get("sector", "Lunar Orbit")), CYAN))
		idv.add_child(chips)
		var ago := Label.new()
		ago.text = "⏱ %s   ·   Slot %d" % [_fmt_ago(float(summary.get("last_played", 0.0))), n]
		ago.add_theme_font_size_override("font_size", _fs(10))
		ago.add_theme_color_override("font_color", Color.html(C_MUTED))
		idv.add_child(ago)
	else:
		top.add_child(_emblem("+", accent, 58))
		top.add_child(idv)
		var t := Label.new()
		t.text = "New Commander"
		t.add_theme_font_size_override("font_size", _fs(16))
		t.add_theme_color_override("font_color", Color.html(C_DIM))
		idv.add_child(t)
		var st := Label.new()
		st.text = "Empty Slot %d — recruit a commander" % n
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		st.add_theme_font_size_override("font_size", _fs(11))
		st.add_theme_color_override("font_color", Color.html(C_MUTED))
		idv.add_child(st)

	# Action row.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	if filled:
		var play := _card_button("▶  DEPLOY", CYAN, true)
		play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		play.custom_minimum_size = Vector2(0, 50)
		play.pressed.connect(_play_slot.bind(n))
		row.add_child(play)
		var ren := _card_button("✎", GOLD, true)
		ren.custom_minimum_size = Vector2(56, 50)
		ren.pressed.connect(_prompt_rename_character.bind(n))
		row.add_child(ren)
		var del := _card_button("✕", RED, true)
		del.custom_minimum_size = Vector2(56, 50)
		del.pressed.connect(_confirm_delete_slot.bind(n))
		row.add_child(del)
	else:
		var create := _card_button("＋  CREATE COMMANDER", GREEN, true)
		create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		create.custom_minimum_size = Vector2(0, 50)
		create.pressed.connect(_prompt_new_character.bind(n))
		row.add_child(create)
	return panel

## Name-entry modal → create a fresh character in slot n and enter the game.
func _prompt_new_character(n: int) -> void:
	var body := func(v: VBoxContainer, close: Callable) -> void:
		_clbl(v, "Name your commander", 12, C_DIM)
		var edit := LineEdit.new()
		edit.text = "Commander"
		edit.max_length = 16
		edit.select_all_on_focus = true
		edit.custom_minimum_size = Vector2(0, 48)
		edit.add_theme_font_size_override("font_size", _fs(15))
		edit.add_theme_stylebox_override("normal", _bordered(INSET, LINE, 1, 8))
		v.add_child(edit)
		var go := _card_button("Begin", GREEN, true)
		go.pressed.connect(func() -> void:
			var nm: String = edit.text.strip_edges()
			if nm == "":
				nm = "Commander"
			close.call()
			GameState.new_character(n, nm)
			_enter_game())
		v.add_child(go)
	_modal("NEW COMMANDER", GREEN, body, "★")

func _play_slot(n: int) -> void:
	GameState.select_slot(n)
	_enter_game()

## Rename an existing commander from the select screen (Play/Delete already there).
func _prompt_rename_character(n: int) -> void:
	var summary: Dictionary = GameState.slot_summary(n)
	var body := func(v: VBoxContainer, close: Callable) -> void:
		_clbl(v, "New name for your commander", 12, C_DIM)
		var edit := LineEdit.new()
		edit.text = String(summary.get("name", "Commander"))
		edit.max_length = 16
		edit.select_all_on_focus = true
		edit.custom_minimum_size = Vector2(0, 48)
		edit.add_theme_font_size_override("font_size", _fs(15))
		edit.add_theme_stylebox_override("normal", _bordered(INSET, LINE, 1, 8))
		v.add_child(edit)
		var go := _card_button("Save", GOLD, true)
		go.pressed.connect(func() -> void:
			GameState.rename_slot(n, edit.text)
			close.call()
			_rebuild_char_select())
		v.add_child(go)
	_modal("RENAME COMMANDER", GOLD, body, "✎")

func _confirm_delete_slot(n: int) -> void:
	var summary: Dictionary = GameState.slot_summary(n)
	var body := func(v: VBoxContainer, close: Callable) -> void:
		_clbl(v, "Permanently delete %s (Slot %d)?" % [String(summary.get("name", "Commander")), n], 13, C_TEXT)
		_clbl(v, "This cannot be undone.", 11, C_MUTED)
		var del := _card_button("Delete", RED, true)
		del.pressed.connect(func() -> void:
			GameState.delete_slot(n)
			close.call()
			_rebuild_char_select())
		v.add_child(del)
	_modal("DELETE COMMANDER", RED, body, "⚠")

## Tear down and rebuild the character-select overlay (after create/delete).
func _rebuild_char_select() -> void:
	if is_instance_valid(_char_select):
		_char_select.queue_free()
	_char_select = null
	_show_char_select()

## A slot is now active — remove the select overlay, refresh the UI to the loaded
## save, land on the right page, and run the original welcome + offline flow.
func _enter_game() -> void:
	if is_instance_valid(_char_select):
		_char_select.queue_free()
	_char_select = null
	# _show() rebuilds the target page itself, so only refresh the header here —
	# calling _refresh_all() first would build the (wrong) current page and then
	# immediately rebuild again in _show(), a redundant double-build that settles
	# visibly on entry.
	_refresh_top()
	_refresh_banner()
	_show("missions" if not GameState.has_mission_progress() else "gather")
	_update_badges()
	_prime_notifications()
	_update_coach()
	_show_welcome()

const SKILL_TITLE := {"harvesting": "HARVESTING", "fabrication": "ENGINEERING", "combat": "COMBAT", "infrastructure": "INFRASTRUCTURE"}
# Mixed-case skill name for inline copy. The crafting skill is "Engineering"
# (its internal id is "fabrication"); always show that, never "Fabrication", so
# the skill reads the same everywhere.
const SKILL_LABEL := {"harvesting": "Harvesting", "fabrication": "Engineering", "combat": "Combat", "infrastructure": "Infrastructure"}

func _skill_label(id: String) -> String:
	return SKILL_LABEL.get(id, id.capitalize())

# Milestone celebration: a centered "LEVEL UP" badge with a scale-pop + fade.
func _on_level_up(skill_id: String, level: int) -> void:
	var accent: String = DOMAIN.get({"harvesting": "gather", "fabrication": "craft", "combat": "combat", "infrastructure": "build"}.get(skill_id, ""), GOLD)
	_celebrate("⬆  LEVEL UP", "%s  Lv %d" % [SKILL_TITLE.get(skill_id, skill_id.to_upper()), level], accent)
	# The visible medallion scale-pops when ITS skill levels.
	if is_instance_valid(_skill_medal) and _skill_banner_id == skill_id and _skill_medal.is_visible_in_tree():
		_skill_medal.pivot_offset = _skill_medal.size / 2.0
		var tw := _skill_medal.create_tween()
		tw.tween_property(_skill_medal, "scale", Vector2(1.35, 1.35), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_skill_medal, "scale", Vector2(1.0, 1.0), 0.22)
	_refresh_banner()   # yield/rate changed
	# A level-up can unlock new cards on the list pages; the idle-loop guard
	# suppresses passive rebuilds, so refresh here so unlocks appear at once.
	if current in IDLE_LOOP_PAGES:
		_refresh_current()

## Reusable centered celebration badge (scale-pop + hold + fade-up).
# Storage full -> a new material drop was just lost. Drops fire many times a
# second while full, so throttle the toast to once per 10s.
var _storage_warn_ms := 0
func _on_storage_full() -> void:
	var now := Time.get_ticks_msec()
	if now - _storage_warn_ms < 10000:
		return
	_storage_warn_ms = now
	_celebrate("⚠ STORAGE FULL", "New drops are being lost!", RED)

# --- Idle-progress notifications -------------------------------------------
# Toast once when a mission finishes or a standing order completes in the
# background, nudging the player to come claim it. Edge-detected per id
# (announce once, mute until claimed/cleared) and silenced during offline
# catch-up — the Welcome Back modal lists those instead.
var _notified_missions := {}
var _notified_orders := {}

# Mission display name, minus the "[CORE GOAL]" tag the early-chain missions carry.
func _mission_title(mid: String) -> String:
	var nm: String = GameData.MISSIONS.get(mid, {}).get("name", mid)
	if nm.begins_with("[CORE GOAL]"):
		nm = nm.substr(11).strip_edges()
	return nm

func _on_missions_changed() -> void:
	if not GameState._suppress_fx:
		for mid in GameState.missions_active:
			if GameState.missions_claimed.has(mid) or not GameState.mission_completed(mid):
				_notified_missions.erase(mid)
				continue
			if not _notified_missions.has(mid):
				_notified_missions[mid] = true
				_celebrate("✦  MISSION READY", _mission_title(mid), PURP)
	_on_tick()

func _on_orders_changed() -> void:
	if not GameState._suppress_fx:
		var live := {}
		for q in GameState.standing_orders():
			var sid := String(q.get("id", ""))
			live[sid] = true
			if q.get("claimed", false) or not q.get("completed", false):
				_notified_orders.erase(sid)
				continue
			if not _notified_orders.has(sid):
				_notified_orders[sid] = true
				_celebrate("▤  ORDER READY", String(q.get("title", "Standing Order")), CYAN)
		# Drop ids no longer on the board so the dict can't grow unbounded.
		for sid in _notified_orders.keys():
			if not live.has(sid):
				_notified_orders.erase(sid)
	_on_tick()

# On entering a save, mark everything already claimable as "seen" so we don't
# dump a stack of toasts on load — only NEW completions during play announce.
func _prime_notifications() -> void:
	_notified_missions.clear()
	_notified_orders.clear()
	for mid in GameState.missions_active:
		if GameState.mission_completed(mid) and not GameState.missions_claimed.has(mid):
			_notified_missions[mid] = true
	for q in GameState.standing_orders():
		if q.get("completed", false) and not q.get("claimed", false):
			_notified_orders[String(q.get("id", ""))] = true

# Lines appended to the Welcome Back modal: missions/orders that finished while
# away and are waiting to be claimed. "Name\t<tag>" renders as a two-column row.
func _ready_to_claim_report() -> String:
	var lines := []
	for mid in GameState.missions_active:
		if GameState.mission_completed(mid) and not GameState.missions_claimed.has(mid):
			lines.append("%s\t✦ ready" % _mission_title(mid))
	for q in GameState.standing_orders():
		if q.get("completed", false) and not q.get("claimed", false):
			lines.append("%s\t▤ ready" % String(q.get("title", "Order")))
	if lines.is_empty():
		return ""
	return "★ Ready to Claim\n" + "\n".join(lines)

# Centre a celebrate pill horizontally by its real laid-out width (called deferred,
# after layout). Keeps the toast centred even if its text made it wider than 280.
func _center_pill(pill: Control) -> void:
	if is_instance_valid(pill):
		pill.position = Vector2(-pill.size.x / 2.0, -40.0)

func _celebrate(title: String, subtitle: String, accent: String) -> void:
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.z_index = 120
	add_child(holder)
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", _card_style(_mix(accent, BG_BOT, 0.45), accent, 2, true))
	pill.position = Vector2(-140, -40)
	pill.custom_minimum_size = Vector2(280, 0)
	holder.add_child(pill)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	pill.add_child(vb)
	_wlabel(vb, title, 13, accent)
	_wlabel(vb, subtitle, 16, C_TEXT)
	# Re-centre by the pill's ACTUAL laid-out width next frame (a longer message grows
	# the pill; the fixed -140 offset would otherwise push it off the right edge).
	call_deferred("_center_pill", pill)
	holder.pivot_offset = Vector2.ZERO
	holder.scale = Vector2(0.7, 0.7)
	holder.modulate.a = 0.0
	var tw := holder.create_tween()
	tw.tween_property(holder, "scale", Vector2(1.0, 1.0), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(holder, "modulate:a", 1.0, 0.18)
	tw.tween_interval(1.0)
	tw.tween_property(holder, "modulate:a", 0.0, 0.4)
	tw.parallel().tween_property(holder, "position:y", -28.0, 0.4).as_relative()
	tw.tween_callback(holder.queue_free)

# Background-resume catch-up finished — show the same report modal as a cold launch.
func _on_offline_ready() -> void:
	if GameState.pending_offline != "":
		_show_offline(GameState.pending_offline)
		GameState.pending_offline = ""
	_refresh_top()
	_refresh_current()

## Branded display font (Rajdhani) with Noto symbol fallbacks so glyph icons
## render on devices whose system font lacks them.
var _font_bold: FontFile = null   # Rajdhani SemiBold — display weight for headings/numbers

func _apply_theme() -> void:
	var fb: Array = []
	var s2 = load("res://assets/fonts/NotoSansSymbols2-Regular.ttf")
	var s1 = load("res://assets/fonts/NotoSansSymbols-VF.ttf")
	if s2: fb.append(s2)
	if s1: fb.append(s1)
	var f = load("res://assets/fonts/Rajdhani-Medium.ttf")
	if f is FontFile:
		f.fallbacks = fb
		var th := Theme.new()
		th.default_font = f
		th.default_font_size = _fs(14)
		theme = th
	# Display weight: SemiBold for headings + headline numbers (game-chrome type
	# hierarchy). Same glyph fallbacks so icons never regress.
	var b = load("res://assets/fonts/Rajdhani-SemiBold.ttf")
	if b is FontFile:
		b.fallbacks = fb
		_font_bold = b

# Swap a label to the display (SemiBold) weight. Safe no-op if the font failed
# to load — the label just stays Medium.
func _embolden(l: Label) -> Label:
	if _font_bold != null:
		l.add_theme_font_override("font", _font_bold)
	return l

# Heading label: bold, colored, left-aligned (the game-chrome sibling of _clbl).
func _hlabel(parent: Node, text: String, size: int, color: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", _fs(size))
	l.add_theme_color_override("font_color", Color.html(color))
	_embolden(l)
	parent.add_child(l)
	return l

# Headline number: a BIG bold value with a small muted unit beside it — the
# "label small, number big" idle-game pattern. Returns the value Label so
# callers can capture it for live updates.
func _big_stat(parent: Node, value: String, unit: String, color: String, size := 24) -> Label:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", _fs(size))
	v.add_theme_color_override("font_color", Color.html(color))
	_embolden(v)
	hb.add_child(v)
	if unit != "":
		var u := Label.new()
		u.text = unit
		u.size_flags_vertical = Control.SIZE_SHRINK_END
		u.add_theme_font_size_override("font_size", _fs(9))
		u.add_theme_color_override("font_color", Color.html(C_MUTED))
		hb.add_child(u)
	parent.add_child(hb)
	return v

## Pads the UI clear of the status bar / notch / gesture bar.
var _safe_top := -1
var _safe_bottom := -1

func _update_safe_area() -> void:
	if safe_margin == null:
		return
	var safe := DisplayServer.get_display_safe_area()
	var ws := DisplayServer.window_get_size()
	if ws.x <= 0 or ws.y <= 0:
		return
	var vp := get_viewport().get_visible_rect().size
	var top := maxi(int(safe.position.y * vp.y / ws.y), 0)
	var bottom := maxi(int((ws.y - safe.position.y - safe.size.y) * vp.y / ws.y), 0)
	# Idempotent: the viewport size_changed signal fires repeatedly (orientation
	# lock, keyboard, window settle on boot). Re-applying the same margins forces a
	# relayout that shifts the whole UI — the one-time jump seen on launch. Skip when
	# nothing changed.
	if top == _safe_top and bottom == _safe_bottom:
		return
	_safe_top = top
	_safe_bottom = bottom
	safe_margin.add_theme_constant_override("margin_top", top)
	safe_margin.add_theme_constant_override("margin_bottom", bottom)

func _process(_delta: float) -> void:
	# Drag-scroll inertia: after a flick, keep gliding with a little friction.
	if not _drag_active and is_instance_valid(_drag_target) and (absf(_drag_vel) > 6.0 or absf(_drag_vel_h) > 6.0):
		if _drag_target.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			_drag_target.scroll_vertical = int(_drag_target.scroll_vertical + _drag_vel * _delta)
		if _drag_target.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			_drag_target.scroll_horizontal = int(_drag_target.scroll_horizontal + _drag_vel_h * _delta)
		_drag_vel *= 0.90
		_drag_vel_h *= 0.90
	# Ambient starfield drift + twinkle (very slow; reads as a living sky).
	if is_instance_valid(_drift):
		_drift_y += _delta * 5.0
		if _drift_y >= 1280.0:
			_drift_y -= 1280.0
		_drift.position.y = _drift_y
		_drift.modulate.a = 0.62 + 0.30 * sin(Time.get_ticks_msec() / 1000.0 * 0.7)
	# Keep the coach pointer glued to its target as the page scrolls / relayouts.
	# No `_coach_ptr.visible` guard: _position_coach_ptr both hides AND re-shows
	# the pointer (it's the only un-hide path). Gating on visible latched the
	# pointer hidden forever once the welcome splash suppressed it — a brand-new
	# player never saw the ☰ ring directing them to Gather for the first mission.
	if is_instance_valid(_pulse_target) and is_instance_valid(_coach_ptr):
		_position_coach_ptr()
	if GameState.active_type != "":
		var dur := GameState.current_duration()
		if dur > 0.0:
			var pct := clampf(GameState.progress / dur * 100.0, 0.0, 100.0)
			if is_instance_valid(_active_bar):
				_active_bar.value = pct
			if is_instance_valid(_active_timer):
				_active_timer.text = "%.1fs / %.1fs" % [GameState.progress, dur]
			if is_instance_valid(_banner_bar):
				_banner_bar.value = pct
			if is_instance_valid(_banner_time):
				_banner_time.text = "%.1fs" % maxf(0.0, dur - GameState.progress)
	# Skill XP banner advances live too (it's only built on a structural refresh,
	# which no longer fires every loop completion).
	if _skill_banner_id != "" and is_instance_valid(_skill_bar):
		var sk := _skill_banner_id
		var lvl := GameState.level_of(sk)
		var cur := int(GameState.skills.get(sk, 0))
		var base := GameState.xp_for_level(lvl)
		var nxt := GameState.xp_for_level(lvl + 1)
		_skill_bar.value = 100.0 if nxt <= base else float(cur - base) / float(nxt - base) * 100.0
		if is_instance_valid(_skill_xp_label):
			_skill_xp_label.text = "%s / %s XP" % [GameData.fmt(cur - base), GameData.fmt(nxt - base)]
		if is_instance_valid(_skill_lv_label):
			_skill_lv_label.text = str(lvl)   # medallion shows the bare number
	# Active card's Mastery row advances live (the page is not rebuilt per loop).
	if _mastery_id != "" and is_instance_valid(_mastery_bar) \
			and is_instance_valid(_mastery_left) and is_instance_valid(_mastery_right):
		_fill_mastery_row(_mastery_id, _mastery_left, _mastery_right, _mastery_bar)
	if is_instance_valid(_combat_hp_bar):
		var mx := GameState.combat_max_hp()
		_combat_hp_bar.max_value = mx
		_combat_hp_bar.value = GameState.combat_hp
		if is_instance_valid(_combat_hp_label):
			_combat_hp_label.text = "%d / %d" % [int(GameState.combat_hp), int(mx)]
	if current == "combat" and GameState.active_type == "combat" and not GameState.enemy_inst.is_empty():
		var e: Dictionary = GameState.enemy_inst
		if is_instance_valid(_enemy_hp_bar):
			_enemy_hp_bar.max_value = e["max_hp"]
			_enemy_hp_bar.value = e["hp"]
			if is_instance_valid(_enemy_hp_label):
				_enemy_hp_label.text = "%d / %d" % [int(e["hp"]), int(e["max_hp"])]
		if is_instance_valid(_enemy_shield_bar):
			_enemy_shield_bar.max_value = maxf(1.0, e["max_shield"])
			_enemy_shield_bar.value = e["shield"]
		if is_instance_valid(_player_shield_bar):
			_player_shield_bar.max_value = maxf(1.0, GameState.player_max_shield())
			_player_shield_bar.value = GameState.player_shield
		if is_instance_valid(_player_heat_bar):
			_player_heat_bar.max_value = GameState.MAX_HEAT
			_player_heat_bar.value = GameState.player_heat
		if is_instance_valid(_enemy_atk_bar):
			var ei := maxf(0.5, float(e.get("interval", 2.5)))
			_enemy_atk_bar.max_value = ei
			_enemy_atk_bar.value = clampf(GameState._enemy_timer, 0.0, ei)
		# Per-weapon fire cooldown + live ammo count.
		for wr in _weapon_rows:
			var bar: ProgressBar = wr["bar"]
			if not is_instance_valid(bar):
				continue
			var w: Dictionary = wr["w"]
			var has_ammo := true
			if wr["needs_ammo"]:
				var aid: String = GameState.ammo_loadout.get(wr["slot"], "")
				var cnt := GameState.amount(aid) if aid != "" else 0
				has_ammo = aid != "" and cnt > 0
				if is_instance_valid(wr["ammo"]):
					wr["ammo"].text = ("⦿ %s" % GameData.fmt(cnt)) if has_ammo else "NO AMMO"
					wr["ammo"].add_theme_color_override("font_color", Color.html(GOLD if has_ammo else "ef6a52"))
			elif is_instance_valid(wr["ammo"]):
				wr["ammo"].text = "∞"
				wr["ammo"].add_theme_color_override("font_color", Color.html(C_MUTED))
			if not w.is_empty():
				var iv := maxf(0.1, float(w.get("interval", 1.0)))
				bar.max_value = iv
				bar.value = clampf(float(w.get("timer", 0.0)), 0.0, iv)
			bar.modulate = Color.WHITE if has_ammo else Color(0.5, 0.5, 0.5, 0.55)
		if is_instance_valid(_enrage_chip):
			_enrage_chip.visible = GameState.enemy_enraged()
		if is_instance_valid(_wave_label) and GameState.hazard_state.get("active", false):
			_wave_label.text = "WAVE %d/%d" % [int(GameState.hazard_state["wave"]) + 1, int(GameState.hazard_state["max_waves"])]
		# SALVAGE THIS RUN — rebuild rows only when the session-loot tally changed.
		# Signature = entry count + total qty, so both new ids and qty bumps are caught.
		if is_instance_valid(_loot_panel):
			var sig := GameState.session_loot.size()
			for _q in GameState.session_loot.values():
				sig += int(_q)
			if sig != _loot_seen_count:
				_loot_seen_count = sig
				_rebuild_loot_rows()
		_drain_combat_events()

# Pages whose content is static/expensive (positioned node-graph, big codex) or
# is changed only by the player's own actions (the Ship Designer) — don't rebuild
# them on passive ticks (gather/craft/infra loops fire resources_changed +
# skills_changed constantly), which otherwise flickers/jumps the view. These pages
# refresh explicitly from their own interaction handlers instead.
# Pages that must NOT be rebuilt by high-frequency passive signals (resources_changed
# / skills_changed fire constantly from gather/craft/infra loops), which recreates
# their cards and flickers/jumps the view. Every page here refreshes instead from:
# navigation, action start/stop, level-up, research_changed (_refresh_all), and its
# own interaction handlers (buy/sell/equip/build/claim/etc. all call _refresh_current).
# The header, notification badges and coach still update every tick (those run before
# the early-return in _on_resources/_on_tick). Live combat/progress bars animate in
# _process, independent of rebuilds.
const NO_TICK_REFRESH := ["research", "atlas", "ship", "shipyard", "combat",
	"more", "bounty", "standing", "warp", "fleet", "missions", "stats", "hazard", "settings"]
# Idle-loop pages: while an action is actively looping, every completion fires
# resources_changed + skills_changed. A full grid rebuild on each one destroys
# and recreates every card (and the progress-bar node), which reads as a freeze
# /flicker at 100%. The active card's bar already animates smoothly in _process,
# so on these pages we update only the lightweight chrome during a loop and defer
# the structural rebuild to navigation / action start-stop / level-up (which can
# add or unlock cards). When idle (active_type == ""), rebuild as normal so
# browsing and craft affordability stay live.
const IDLE_LOOP_PAGES := ["gather", "craft", "build"]

func _on_resources() -> void:
	_refresh_top()
	_update_badges()
	if current == "stats":
		_storage_live_update()   # in-place tile/worth refresh (no rebuild, no jump)
	if current in NO_TICK_REFRESH:
		_update_coach()
		return
	# Idle-loop pages (gather/craft/build) never rebuild on a passive tick — whether
	# an action is running OR the player is idle with buildings producing in the
	# background. A full rebuild recreates the cards and visibly jumps the view; the
	# active card animates in _process, and structural changes come from navigation,
	# action start/stop, level-up, research, and explicit taps (which refresh
	# themselves). This is why the jump vanished while gathering and returned on stop.
	if current in IDLE_LOOP_PAGES:
		_update_coach()
		return
	_request_tick_refresh()

# Guarded rebuild for frequent signals (skills/missions/bounty/action) — skips
# the graph/codex pages so their pan/scroll survives passive loops, and skips
# the destructive grid rebuild on idle-loop pages (active or idle).
func _on_tick() -> void:
	_update_badges()
	if current in NO_TICK_REFRESH:
		_update_coach()
		return
	if current in IDLE_LOOP_PAGES:
		_update_coach()
		_refresh_banner()
		return
	_request_tick_refresh()

# Passive signals (resources/skills/infra) can fire many times a second. A full
# page rebuild on each one resets the ScrollContainer and flickers/jumps the view.
# Throttle them: rebuild immediately on the first tick, then at most once per
# window, with a single trailing rebuild to catch the latest state. Live bars/
# timers still update every frame in _process, so the page never looks frozen.
# The window is short while something is actively running (the player is watching
# values move), but long when idle — passive infra/bounty accumulation doesn't
# need a snappy redraw, and a calm cadence stops the periodic idle jump.
const TICK_REFRESH_MS_ACTIVE := 300
const TICK_REFRESH_MS_IDLE := 2000
var _tick_refresh_last := 0
var _tick_refresh_pending := false

func _tick_refresh_window() -> int:
	return TICK_REFRESH_MS_ACTIVE if GameState.active_type != "" else TICK_REFRESH_MS_IDLE

# A rebuild destroys and recreates the page's nodes — including a focused search
# field, which drops focus and dismisses the on-screen keyboard. Never rebuild the
# page out from under an active text input; the next tick after the field is
# dismissed will catch up.
func _text_input_focused() -> bool:
	var f = get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit

func _request_tick_refresh() -> void:
	if _text_input_focused():
		return
	var win := _tick_refresh_window()
	var now := Time.get_ticks_msec()
	if now - _tick_refresh_last >= win:
		_tick_refresh_last = now
		_refresh_current(true)
		return
	if _tick_refresh_pending:
		return
	_tick_refresh_pending = true
	var wait := float(win - (now - _tick_refresh_last)) / 1000.0
	await get_tree().create_timer(maxf(0.01, wait)).timeout
	_tick_refresh_pending = false
	# Don't rebuild a page that's since opted out (navigated to a graph/codex page,
	# an idle-loop page, or while a text field is focused — match the entry guards).
	if _text_input_focused():
		return
	if current in NO_TICK_REFRESH:
		return
	if current in IDLE_LOOP_PAGES:
		return
	_tick_refresh_last = Time.get_ticks_msec()
	_refresh_current(true)

# Action started/stopped: the active card's controls change (Start↔Stop, the
# active highlight), so always do a full structural rebuild.
func _on_action_changed() -> void:
	_refresh_current()

# Notification beads: a claimable mission lights the ☰ button and the Missions row.
func _update_badges() -> void:
	var claim := GameState.has_claimable_mission()
	if is_instance_valid(_ham_badge):
		_ham_badge.visible = claim
	var mi = nav_items.get("missions")
	if mi != null and is_instance_valid(mi.get("badge")):
		mi["badge"].visible = claim

# ============================================================ SHELL
func _build() -> void:
	var bg := TextureRect.new()
	bg.texture = _space_tex()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# Ambient motion: a sparse star layer drifting slowly downward, twinkling.
	_drift = Control.new()
	_drift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_drift)
	for off in [-1280.0, 0.0]:
		var layer := TextureRect.new()
		layer.texture = _star_layer_tex()
		layer.position = Vector2(0, off)
		layer.size = Vector2(720, 1280)
		layer.stretch_mode = TextureRect.STRETCH_SCALE
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_drift.add_child(layer)
	safe_margin = MarginContainer.new()
	safe_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(safe_margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	safe_margin.add_child(root)

	# ---- Top HUD ----
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _hud_style())
	root.add_child(top)
	var topv := VBoxContainer.new()
	topv.add_theme_constant_override("separation", 8)
	top.add_child(topv)
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 10)
	var ham := Button.new()
	ham.text = "☰"
	ham.flat = true
	ham.focus_mode = Control.FOCUS_NONE
	ham.custom_minimum_size = Vector2(64, 58)
	ham.add_theme_font_size_override("font_size", _fs(28))
	ham.add_theme_color_override("font_color", Color.html(CYAN))
	ham.add_theme_color_override("font_color_hover", Color.html(CYAN))
	ham.add_theme_color_override("font_color_pressed", Color.html(GOLD))
	var empty_btn := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus"]:
		ham.add_theme_stylebox_override(st, empty_btn)
	ham.pressed.connect(_toggle_drawer)
	_ham_btn = ham
	_ham_badge = _make_badge()
	_ham_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_ham_badge.offset_left = -16
	_ham_badge.offset_top = 6
	_ham_badge.offset_right = -4
	ham.add_child(_ham_badge)
	hdr.add_child(ham)
	var title := Label.new()
	title.text = "✦  STELLAR FORGE"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.add_theme_font_size_override("font_size", _fs(15))
	title.add_theme_color_override("font_color", Color.html(CYAN))
	hdr.add_child(title)
	# Credits live in the header (primary currency, always visible) rather than
	# buried in the horizontally-scrolling resource bar.
	var cpill := PanelContainer.new()
	cpill.add_theme_stylebox_override("panel", _bordered(_mix(GOLD, INSET, 0.82), _mix(GOLD, LINE, 0.5), 1, 10))
	cpill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hdr_cpill = cpill   # captured for the gain-pop tween
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 4)
	cpill.add_child(ch)
	var cmark := Label.new()
	cmark.text = "₡"
	cmark.add_theme_font_size_override("font_size", _fs(15))
	cmark.add_theme_color_override("font_color", Color.html(GOLD))
	ch.add_child(cmark)
	_hdr_credits = Label.new()
	_hdr_credits.add_theme_font_size_override("font_size", _fs(15))
	_hdr_credits.add_theme_color_override("font_color", Color.html(GOLD))
	_embolden(_hdr_credits)   # the primary currency reads as a display number
	ch.add_child(_hdr_credits)
	hdr.add_child(cpill)
	topv.add_child(hdr)
	active_banner = _build_active_banner()
	topv.add_child(active_banner)
	# Coaching banner (tutorial guidance) — shows the current objective + a directive.
	_coach_banner = PanelContainer.new()
	_coach_banner.add_theme_stylebox_override("panel", _card_style(_mix(GOLD, SURFACE, 0.84), _mix(GOLD, LINE, 0.4), 1, false))
	_coach_banner.visible = false
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 1)
	_coach_banner.add_child(cv)
	_coach_obj = Label.new()
	_coach_obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_coach_obj.add_theme_font_size_override("font_size", _fs(12))
	_coach_obj.add_theme_color_override("font_color", Color.html(GOLD))
	cv.add_child(_coach_obj)
	_coach_hint = Label.new()
	_coach_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_coach_hint.add_theme_font_size_override("font_size", _fs(11))
	_coach_hint.add_theme_color_override("font_color", Color.html(CYAN))
	cv.add_child(_coach_hint)
	topv.add_child(_coach_banner)

	# ---- Content ----
	content = Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(content)
	for pid in PAGE_IDS:
		var page := _make_page()
		page.visible = false
		content.add_child(page)
		pages[pid] = page

	# ---- Slide-out navigation drawer (replaces the bottom nav) ----
	_build_drawer()
	# Red vignette flashed when the player's hull takes a hit (combat drama).
	_hit_flash = ColorRect.new()
	_hit_flash.color = Color(0.95, 0.25, 0.18, 0.0)
	_hit_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_flash.z_index = 90
	add_child(_hit_flash)
	# FX overlay: every spawned effect (floating gains, fly-to-header bursts)
	# parents HERE — built once, never rebuilt, input-transparent — so juice can
	# never trigger a page rebuild or fight the idle-loop no-rebuild guard.
	_fx_layer = Control.new()
	_fx_layer.name = "FxLayer"
	_fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.z_index = 95
	add_child(_fx_layer)

func _build_drawer() -> void:
	drawer = Control.new()
	drawer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	drawer.visible = false
	safe_margin.add_child(drawer)

	drawer_scrim = ColorRect.new()
	drawer_scrim.color = Color(0, 0, 0, 0.0)   # faded in on open
	drawer_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drawer_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	drawer_scrim.gui_input.connect(func(ev: InputEvent) -> void:
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
			_close_drawer())
	drawer.add_child(drawer_scrim)

	drawer_panel = PanelContainer.new()
	drawer_panel.add_theme_stylebox_override("panel", _card_style(_mix(SURFACE, BG_BOT, 0.5), LINE, 1, true))
	drawer_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	drawer_panel.offset_top = 0
	drawer_panel.offset_bottom = 0
	drawer_panel.offset_left = -DRAWER_W
	drawer_panel.offset_right = 0
	drawer_panel.clip_contents = true
	drawer.add_child(drawer_panel)
	# The drawer lives in the same universe — starfield under a dark scrim.
	var dbg := TextureRect.new()
	dbg.texture = _space_tex()
	dbg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dbg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	dbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drawer_panel.add_child(dbg)
	var dtint := ColorRect.new()
	dtint.color = Color(0.05, 0.08, 0.15, 0.78)
	dtint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drawer_panel.add_child(dtint)

	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14)
	drawer_panel.add_child(m)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	m.add_child(col)

	var dh := HBoxContainer.new()
	var dt := Label.new()
	dt.text = "✦  NAVIGATE"
	dt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dt.add_theme_font_size_override("font_size", _fs(15))
	dt.add_theme_color_override("font_color", Color.html(CYAN))
	dh.add_child(dt)
	var cx := Button.new()
	cx.text = "✕"
	cx.flat = true
	cx.focus_mode = Control.FOCUS_NONE
	cx.custom_minimum_size = Vector2(48, 48)
	cx.add_theme_font_size_override("font_size", _fs(16))
	cx.add_theme_color_override("font_color", Color.html(C_DIM))
	var eb := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus"]:
		cx.add_theme_stylebox_override(st, eb)
	cx.pressed.connect(_close_drawer)
	dh.add_child(cx)
	col.add_child(dh)

	var sep := HSeparator.new()
	col.add_child(sep)

	var list_sc := ScrollContainer.new()
	list_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(list_sc)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_sc.add_child(list)
	for t in NAV_ALL:
		if _nav_visible(t.id):
			list.add_child(_make_drawer_item(t.id, t.label, t.icon))

func _make_drawer_item(id: String, label: String, icon: String) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 86)
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.add_theme_constant_override("separation", 14)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.offset_left = 12
	hb.offset_right = -12
	btn.add_child(hb)
	var bar := Panel.new()                       # left accent bar (active indicator)
	bar.custom_minimum_size = Vector2(5, 34)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(bar)
	var ic := Label.new()
	ic.text = icon
	ic.custom_minimum_size = Vector2(30, 0)
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.add_theme_font_size_override("font_size", _fs(22))
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(ic)
	var lab := Label.new()
	lab.text = label
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lab.add_theme_font_size_override("font_size", _fs(17))
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(lab)
	var badge := _make_badge()
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(badge)
	btn.pressed.connect(_show.bind(id))
	nav_items[id] = {"btn": btn, "icon": ic, "label": lab, "bar": bar, "badge": badge}
	return btn

func _make_badge() -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(12, 12)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.visible = false
	var s := StyleBoxFlat.new()
	s.bg_color = Color.html(RED)
	s.set_corner_radius_all(6)
	s.set_border_width_all(2)
	s.border_color = Color.html(SURFACE)
	p.add_theme_stylebox_override("panel", s)
	return p

func _toggle_drawer() -> void:
	if drawer_open:
		_close_drawer()
	else:
		_open_drawer()

func _open_drawer() -> void:
	if drawer_open:
		return
	drawer_open = true
	drawer.visible = true
	_update_coach()   # re-evaluate the coach target for the open-drawer state
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(drawer_panel, "offset_left", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(drawer_panel, "offset_right", DRAWER_W, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(drawer_scrim, "color", Color(0, 0, 0, 0.55), 0.18)
	_update_coach()        # switch the pulse from the hamburger to the destination row

func _close_drawer() -> void:
	if not drawer_open:
		return
	drawer_open = false
	_update_coach()   # restore the on-page card highlight now the menu is closing
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(drawer_panel, "offset_left", -DRAWER_W, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(drawer_panel, "offset_right", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(drawer_scrim, "color", Color(0, 0, 0, 0.0), 0.16)
	tw.chain().tween_callback(func() -> void: drawer.visible = false)
	_update_coach()

func _make_page() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 10)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(m)
	var v := VBoxContainer.new()
	v.name = "List"
	v.add_theme_constant_override("separation", 9)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(v)
	return sc

# ============================================================ NAV
func _show(id: String) -> void:
	current = id
	# Drop any drag-scroll inertia so a flick doesn't keep gliding the old page.
	_drag_active = false
	_drag_vel = 0.0
	_drag_vel_h = 0.0
	_drag_uncancel()
	# When the coach sends the player to the Shipyard, land on the sub-tab that
	# matches the active fabrication step (construct → Hulls, craft → Modules).
	if id == "shipyard":
		var amid := _coach_active_mission()
		if amid != "" and GameData.MISSIONS.has(amid):
			var mtype: String = GameData.MISSIONS[amid].get("type", "")
			if mtype == "construct":
				shipyard_view = "hulls"
			elif mtype == "craft":
				shipyard_view = "modules"
	# When the coach sends the player to Combat (defeat, or a "gather" mission whose
	# material is a combat drop), pre-select the sector holding the target enemy so
	# its card (and the pointer) is reachable.
	if id == "combat":
		var amid := _coach_active_mission()
		if amid != "" and GameData.MISSIONS.has(amid):
			var rc := _coach_resolve(GameData.MISSIONS[amid])
			if rc["page"] == "combat" and rc["card"] != "":
				var zi := _zone_index_for_enemy(rc["card"])
				if zi >= 0 and _zone_unlocked(GameData.ZONES[zi]):
					combat_zone = zi
	# Gather/Craft/Research/Shipyard cards live behind a category/tab/slot sub-tab —
	# pre-select the one holding the coach target so the highlighted card renders.
	if id in ["gather", "craft", "research", "shipyard"]:
		var amid := _coach_active_mission()
		if amid != "" and GameData.MISSIONS.has(amid):
			var rc := _coach_resolve(GameData.MISSIONS[amid])
			if rc["page"] == id and rc["card"] != "":
				var cid: String = rc["card"]
				if id == "gather" and GameData.GATHER.has(cid):
					gather_cat = String(GameData.GATHER[cid].get("category", gather_cat))
				elif id == "craft" and GameData.CRAFT.has(cid):
					craft_cat = String(GameData.CRAFT[cid].get("category", craft_cat))
				elif id == "research":
					var rt := _research_tab_for(cid)
					if rt != "":
						research_tab = rt
				elif id == "shipyard" and shipyard_view == "modules" and GameData.MODULES.has(cid):
					ship_mod_slot = String(GameData.MODULES[cid].get("slot", ship_mod_slot))
	GameState.mission_visit_page(id)   # drive visit_page missions (e.g. Combat Briefing)
	_reset_armed = false
	_warp_armed = false
	GameState.equip_notice = ""        # transient; only shown right after a rejection
	for pid in pages:
		pages[pid].visible = (pid == id)
	for bid in nav_items:
		_style_nav(bid, bid == id)
	_close_drawer()
	_refresh_current()
	# A tab switch lands at the top of the new page (conventional, and deterministic
	# across platforms — don't depend on the rebuild's content-clear happening to
	# clamp the offset). Tick rebuilds use _refresh_current(true) and are exempt.
	if pages.has(id):
		pages[id].set_deferred("scroll_vertical", 0)
	_animate_page_in(id)

## Staggered fade-in of the page's top-level blocks on NAVIGATION only (tick
## rebuilds skip this) — pages arrive instead of just appearing. Alpha-only so
## container layout is untouched.
func _animate_page_in(id: String) -> void:
	var list = pages[id].find_child("List", true, false)
	if list == null:
		return
	var i := 0
	for child in list.get_children():
		if not (child is Control) or i >= 8:
			break
		child.modulate.a = 0.0
		var tw: Tween = child.create_tween()
		tw.tween_interval(0.035 * i)
		tw.tween_property(child, "modulate:a", 1.0, 0.16)
		i += 1

func _refresh_all() -> void:
	_refresh_top()
	_refresh_current()

func _refresh_current(preserve_scroll: bool = false) -> void:
	# A passive tick (resource/skill completion) can fire while the player is
	# scrolled partway down a page. Rebuilding the "List" VBox resets the
	# ScrollContainer to the top, yanking the view back up mid-read. On tick-driven
	# same-page rebuilds we capture the scroll offset and restore it after the
	# rebuild; navigation (_show / _refresh_all) passes the default false so a tab
	# switch still lands at the top.
	var saved_scroll := 0
	if preserve_scroll and pages.has(current):
		saved_scroll = pages[current].scroll_vertical
	_active_bar = null
	_active_timer = null
	_held_label = null
	_held_sym = ""
	_skill_bar = null
	_skill_xp_label = null
	_skill_lv_label = null
	_skill_banner_id = ""
	_mastery_bar = null
	_mastery_left = null
	_mastery_right = null
	_mastery_id = ""
	_combat_hp_bar = null
	_combat_hp_label = null
	_enemy_hp_bar = null
	_enemy_hp_label = null
	_enemy_shield_bar = null
	_player_shield_bar = null
	_player_heat_bar = null
	_enemy_anchor = null
	_player_anchor = null
	_enrage_chip = null
	_wave_label = null
	_enemy_atk_bar = null
	_weapon_rows = []
	_loot_panel = null
	_loot_seen_count = -1
	match current:
		"gather":   _build_gather()
		"craft":    _build_craft()
		"combat":   _build_combat()
		"build":    _build_infra()
		"shipyard": _build_shipyard()
		"ship":     _build_ship()
		"bounty":   _build_bounty()
		"standing": _build_standing()
		"warp":     _build_warp()
		"fleet":    _build_fleet()
		"missions": _build_missions()
		"atlas":    _build_atlas()
		"research": _build_research()
		"more":     _build_more()
		"stats":    _build_stats()
		"hazard":   _build_hazard()
		"settings": _build_settings()
	# Let touch drags fall through cards to the page's ScrollContainer so the
	# whole content surface scrolls (not just the dark background gaps). Panels
	# and containers default to MOUSE_FILTER_STOP, which eats the drag.
	if pages.has(current):
		_scroll_passthrough(pages[current])
		if preserve_scroll and saved_scroll > 0:
			# The new content is already re-added at this point, so the scroll range
			# is intact — restore immediately (no top-flash) and again deferred as a
			# safety net once layout settles.
			pages[current].scroll_vertical = saved_scroll
			pages[current].set_deferred("scroll_vertical", saved_scroll)
	_update_coach()

# Register an overlay/modal so the drag-scroll handler scrolls ITS content (not
# the page behind it) while it's open.
func _track_modal(o: Node) -> void:
	_modal_stack.append(o)
	o.tree_exiting.connect(func() -> void: _modal_stack.erase(o))

# Global drag-to-scroll. _input runs before GUI, so we see the drag even when it
# starts over a card's tap Button. We don't consume the PRESS (so a clean tap
# still clicks), but once the finger moves past the deadzone we scroll and cancel
# the tap.
func _input(event: InputEvent) -> void:
	if drawer_open or is_instance_valid(_char_select) or is_instance_valid(_welcome):
		return
	# Trackpad / OS pinch gesture (desktop + some devices) zooms the research tree.
	if event is InputEventMagnifyGesture:
		if current == "research" and is_instance_valid(_research_canvas):
			_set_research_zoom(_research_zoom * event.factor, event.position)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		_drag_is_touch = true
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_update_pinch_state()
		if _pinch_active:                       # two fingers on the tree -> zoom, not scroll
			get_viewport().set_input_as_handled()
			return
		if event.pressed:
			_drag_begin(event.position)
		else:
			_drag_end()
		return
	elif event is InputEventScreenDrag:
		if _touches.has(event.index):
			_touches[event.index] = event.position
		if _pinch_active:
			_pinch_update()
			get_viewport().set_input_as_handled()
			return
		_drag_move(event.position)
		return
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not _drag_is_touch:
		if event.pressed:
			_drag_begin(event.position)
		else:
			_drag_end()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) and not _drag_is_touch:
		_drag_move(event.position)

func _drag_begin(pos: Vector2) -> void:
	_drag_target = _scrollable_at(pos)
	_drag_active = _drag_target != null
	_drag_moved = false
	_drag_start = pos
	_drag_vel = 0.0
	_drag_vel_h = 0.0
	if _drag_active:
		_drag_scroll0_v = _drag_target.scroll_vertical
		_drag_scroll0_h = _drag_target.scroll_horizontal
		_drag_last_v = _drag_target.scroll_vertical
		_drag_last_h = _drag_target.scroll_horizontal
		_drag_last_ms = Time.get_ticks_msec()

func _drag_move(pos: Vector2) -> void:
	if not _drag_active or not is_instance_valid(_drag_target):
		return
	var d := pos - _drag_start
	if not _drag_moved:
		if d.length() < DRAG_DEADZONE:
			return
		_drag_moved = true
		# Cancel the tap the card/button under the finger started: disable it for the
		# duration of the drag. Disabling clears the button's press state, so the
		# finger-up won't fire `pressed` (which on Android's touch→mouse emulation
		# would otherwise open the card you only meant to scroll past). Re-enabled in
		# _drag_end. The card tap-overlays are transparent, so this is invisible.
		var root := _drag_root()
		if root != null:
			var b := _button_at(root, _drag_start)
			if b != null and not b.disabled:
				b.disabled = true
				_drag_cancel_btn = b
		_drag_last_ms = Time.get_ticks_msec()
	# Scroll relative to where the gesture began (1:1 with the finger).
	if _drag_target.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		_drag_target.scroll_vertical = _drag_scroll0_v - int(d.y)
	if _drag_target.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		_drag_target.scroll_horizontal = _drag_scroll0_h - int(d.x)
	# Velocity (scroll units/sec) from actual movement, for release inertia.
	var now := Time.get_ticks_msec()
	var dt := maxf(0.001, float(now - _drag_last_ms) / 1000.0)
	_drag_vel = clampf(float(_drag_target.scroll_vertical - _drag_last_v) / dt, -3500.0, 3500.0)
	_drag_vel_h = clampf(float(_drag_target.scroll_horizontal - _drag_last_h) / dt, -3500.0, 3500.0)
	_drag_last_v = _drag_target.scroll_vertical
	_drag_last_h = _drag_target.scroll_horizontal
	_drag_last_ms = now
	get_viewport().set_input_as_handled()

func _drag_end() -> void:
	_drag_active = false
	_drag_is_touch = false
	_drag_uncancel()
	if not _drag_moved:
		_drag_vel = 0.0
		_drag_vel_h = 0.0

# Re-enable the button a drag temporarily disabled to suppress its tap.
func _drag_uncancel() -> void:
	if _drag_cancel_btn != null and is_instance_valid(_drag_cancel_btn):
		_drag_cancel_btn.disabled = false
	_drag_cancel_btn = null

# The subtree a drag operates within: the frontmost open modal, else the page.
func _drag_root() -> Node:
	for i in range(_modal_stack.size() - 1, -1, -1):
		if is_instance_valid(_modal_stack[i]):
			return _modal_stack[i]
	return pages.get(current, null)

# Deepest visible BaseButton whose global rect contains the point (the tap that a
# drag should cancel), or null.
func _button_at(node: Node, pos: Vector2) -> BaseButton:
	var result: BaseButton = null
	for c in node.get_children():
		if c is CanvasItem and not (c as CanvasItem).visible:
			continue
		var deeper := _button_at(c, pos)
		if deeper != null:
			result = deeper
	if result == null and node is BaseButton and (node as Control).get_global_rect().has_point(pos):
		result = node
	return result

# Innermost scrollable ScrollContainer under a point (subtab strips, the research
# 2D canvas, or the page itself), or null if nothing there can scroll.
func _scrollable_at(pos: Vector2) -> ScrollContainer:
	# A modal is frontmost — only its own content scrolls (never the page behind).
	for i in range(_modal_stack.size() - 1, -1, -1):
		var m = _modal_stack[i]
		if is_instance_valid(m):
			return _deepest_scroll(m, pos)
	if current == "" or not pages.has(current):
		return null
	return _deepest_scroll(pages[current], pos)

func _deepest_scroll(node: Node, pos: Vector2) -> ScrollContainer:
	var found: ScrollContainer = null
	if node is ScrollContainer:
		var sc := node as ScrollContainer
		if sc.visible and sc.get_global_rect().has_point(pos) and _can_scroll(sc):
			found = sc
	for c in node.get_children():
		if c is CanvasItem and not (c as CanvasItem).visible:
			continue
		var deeper := _deepest_scroll(c, pos)
		if deeper != null:
			found = deeper
	return found

func _can_scroll(sc: ScrollContainer) -> bool:
	var vb := sc.get_v_scroll_bar()
	var hb := sc.get_h_scroll_bar()
	var v: bool = sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and (vb.max_value - vb.page) > 1.0
	var h: bool = sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and (hb.max_value - hb.page) > 1.0
	return v or h

# Recursively switch non-interactive controls from STOP to PASS so the parent
# ScrollContainer still receives touch-drag events. Buttons/sliders/inputs keep
# STOP so taps and drags on them keep working.
func _scroll_passthrough(node: Node) -> void:
	for c in node.get_children():
		if c is Control and not (c is BaseButton or c is Slider or c is LineEdit or c is TextEdit or c is ScrollContainer):
			if c.mouse_filter == Control.MOUSE_FILTER_STOP:
				c.mouse_filter = Control.MOUSE_FILTER_PASS
		_scroll_passthrough(c)

# Coalesce a burst of rapid calls (e.g. a search field's per-keystroke signal)
# into a single deferred run. Each call bumps a per-key generation; after `secs`
# of quiet the latest call's generation still matches and runs `cb` once. Keeps a
# heavy rebuild from firing on every keystroke.
func _debounce(key: String, secs: float, cb: Callable) -> void:
	var g: int = int(_debounce_gen.get(key, 0)) + 1
	_debounce_gen[key] = g
	await get_tree().create_timer(secs).timeout
	if int(_debounce_gen.get(key, 0)) == g:
		cb.call()

func _clear(id: String) -> VBoxContainer:
	var v: VBoxContainer = pages[id].find_child("List", true, false)
	for c in v.get_children():
		v.remove_child(c)
		c.queue_free()
	return v

# ============================================================ GATHER
func _build_gather() -> void:
	var v := _clear("gather")
	_skill_banner(v, "PLANETARY HARVESTING", "harvesting", GOLD)
	_subtabs(v, GameData.GATHER_CATS, gather_cat, GOLD, func(id: String) -> void:
		gather_cat = id
		_refresh_current())
	var g := _grid(v)
	var any := false
	var ids := []
	for id in GameData.GATHER:
		if GameData.GATHER[id].get("category", "terrestrial") == gather_cat:
			ids.append(id)
	# Order cards by unlock level (then name) so the earliest operations lead.
	ids.sort_custom(func(a: String, b: String) -> bool:
		var la := int(GameData.GATHER[a].get("level_req", 1))
		var lb := int(GameData.GATHER[b].get("level_req", 1))
		if la != lb:
			return la < lb
		return String(GameData.GATHER[a].get("name", a)) < String(GameData.GATHER[b].get("name", b)))
	for id in ids:
		any = true
		g.add_child(_gather_card(id, GameData.GATHER[id]))
	if not any:
		_empty(v, "No operations here yet.")

# Craft I/O as one wrapping "inputs → outputs" chip line. Input pills read
# affordability (green = have enough, amber = short); output pills carry the
# accent border; bonus rolls show as "+x%" pills.
func _io_chips(v: VBoxContainer, inputs: Dictionary, outputs: Dictionary, bonus: Array, accent: String) -> void:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 5)
	var mk := func(sym: String, txt: String, col: Color, border: String) -> void:
		var pill := PanelContainer.new()
		var sb := _bordered(INSET, border, 1, 8)
		sb.content_margin_left = 7
		sb.content_margin_right = 8
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		pill.add_theme_stylebox_override("panel", sb)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4)
		pill.add_child(hb)
		var icon := _mat_icon(sym, 18)
		if icon != null:
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hb.add_child(icon)
		var l := Label.new()
		l.text = txt
		l.add_theme_font_size_override("font_size", _fs(11))
		l.add_theme_color_override("font_color", col)
		_embolden(l)
		hb.add_child(l)
		flow.add_child(pill)
	for sym in inputs:
		var need: int = int(inputs[sym])
		var have: bool = GameState.amount(sym) >= need
		mk.call(String(sym), "×%d" % need, Color.html(GREEN if have else C_WARN), LINE)
	var arrow := Label.new()
	arrow.text = "→"
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.add_theme_font_size_override("font_size", _fs(13))
	arrow.add_theme_color_override("font_color", Color.html(accent))
	flow.add_child(arrow)
	for sym in outputs:
		mk.call(String(sym), "×%d" % int(outputs[sym]), Color.html(C_TEXT), _mix(accent, LINE, 0.4))
	for row in bonus:
		mk.call(String(row[0]), "+%d%%" % int(float(row[1]) * 100.0), _hex_color_safe(String(row[0])), _mix(accent, LINE, 0.4))
	v.add_child(flow)

# Identity head with the material's own tinted icon instead of a generic glyph —
# the card shows WHAT YOU GET as art. Falls back to _card_head when no icon.
func _card_head_mat(v: VBoxContainer, sym: String, glyph: String, name: String, badge: String, accent: String, lit: bool) -> void:
	var icon := _mat_icon(sym, 30) if sym != "" else null
	if icon == null:
		_card_head(v, glyph, name, badge, accent, lit)
		return
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(44, 44)
	chip.add_theme_stylebox_override("panel", _bordered(_mix(accent, INSET, 0.62) if lit else INSET, _mix(accent, LINE, 0.5) if lit else LINE, 1, 10))
	var cc := CenterContainer.new()
	chip.add_child(cc)
	if not lit:
		icon.modulate.a = 0.45
	cc.add_child(icon)
	hb.add_child(chip)
	var nm := Label.new()
	nm.text = name
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.add_theme_font_size_override("font_size", _fs(13))
	nm.add_theme_color_override("font_color", Color.html(C_TEXT if lit else C_MUTED))
	_embolden(nm)
	hb.add_child(nm)
	if badge != "":
		var bd := PanelContainer.new()
		bd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bsb := _bordered(_mix(accent, INSET, 0.8) if lit else INSET, accent if lit else LINE, 1, 8)
		bsb.content_margin_left = 7
		bsb.content_margin_right = 7
		bsb.content_margin_top = 2
		bsb.content_margin_bottom = 2
		bd.add_theme_stylebox_override("panel", bsb)
		var bl := Label.new()
		bl.text = badge
		bl.add_theme_font_size_override("font_size", _fs(9))
		bl.add_theme_color_override("font_color", Color.html(accent if lit else C_MUTED))
		bd.add_child(bl)
		hb.add_child(bd)
	v.add_child(hb)

# Compact yield/IO chips: one wrapping row of "icon xN" pills instead of a tall
# titled inset table — kills ~40% of the form-bloat per card.
func _yield_chips(v: VBoxContainer, loot: Array, accent: String) -> void:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 5)
	for row in loot:
		var sym: String = row[0]
		var pill := PanelContainer.new()
		var sb := _bordered(INSET, _mix(accent, LINE, 0.6), 1, 8)
		sb.content_margin_left = 7
		sb.content_margin_right = 8
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		pill.add_theme_stylebox_override("panel", sb)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4)
		pill.add_child(hb)
		var icon := _mat_icon(sym, 18)
		if icon != null:
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hb.add_child(icon)
		var lo := int(row[2])
		var hi := int(row[3])
		var txt := ("×%d" % hi) if lo == hi else ("×%d-%d" % [lo, hi])
		if sym == "credits":
			txt = "₡%d-%d" % [lo, hi]
		if float(row[1]) < 1.0:
			txt += " (%d%%)" % int(round(float(row[1]) * 100.0))
		var l := Label.new()
		l.text = txt
		l.add_theme_font_size_override("font_size", _fs(11))
		l.add_theme_color_override("font_color", _hex_color_safe(sym))
		_embolden(l)
		hb.add_child(l)
		flow.add_child(pill)
	v.add_child(flow)

func _hex_color_safe(sym: String) -> Color:
	if sym == "credits":
		return Color.html(GOLD)
	return Color.html(_hex(GameData.color_for(sym)))

# Held-quantity chip ("how much do I have of what this makes"). The ACTIVE
# card's chip is captured and refreshed per cycle from _on_cycle_completed.
func _held_chip(v: VBoxContainer, sym: String, active: bool) -> void:
	if sym == "" or sym == "credits":
		return
	var l := Label.new()
	l.text = "◈ %s held" % GameData.fmt(GameState.amount(sym))
	l.add_theme_font_size_override("font_size", _fs(10))
	l.add_theme_color_override("font_color", Color.html(C_DIM))
	v.add_child(l)
	if active:
		_held_label = l
		_held_sym = sym

# Primary (first non-credits) loot symbol of a gather action / craft output.
func _primary_sym(rows: Array) -> String:
	for row in rows:
		if String(row[0]) != "credits":
			return String(row[0])
	return ""

func _gather_card(id: String, a: Dictionary) -> Control:
	var unlocked := GameState.meets_requirements(a, "harvesting")
	var active := (GameState.active_type == "gather" and GameState.active_id == id)
	var v := _card(GOLD, unlocked or active)
	# Rows self-equalize: every card stretches to its row partner's height with
	# the controls pinned to the bottom — locked and unlocked always align.
	v.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.get_parent().set_meta("coach_id", id)
	if active:
		_breathe_active(v.get_parent())
	# Identity: the primary material IS the card art; yields are compact chips;
	# the rate is the hero number — de-formed from the label/table/button stack.
	var psym := _primary_sym(a.get("loot", []))
	_card_head_mat(v, psym if unlocked else "", "↑", a["name"], "Lv %d" % int(a.get("level_req", 1)), GOLD, unlocked)
	if unlocked:
		var rt := GameState.rate_text("gather", id)
		if rt != "":
			var rl := Label.new()
			rl.text = rt
			rl.add_theme_font_size_override("font_size", _fs(17))
			rl.add_theme_color_override("font_color", Color.html(GREEN))
			_embolden(rl)
			v.add_child(rl)
		_yield_chips(v, a.get("loot", []), GOLD)
		_held_chip(v, psym, active)
		_mastery_row(v, id, GOLD, active)
		var fill := Control.new()
		fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(fill)
		_action_controls(v, "gather", id, active, GOLD)
	else:
		_locked(v, a, "harvesting")
	return v.get_parent()

# ============================================================ CRAFT
func _build_craft() -> void:
	var v := _clear("craft")
	_skill_banner(v, "ENGINEERING", "fabrication", CYAN)
	# Search box: matches recipes by name OR output material across EVERY category,
	# so you find a recipe even when you're on the wrong tab. Typing refills only the
	# results wrapper (focus / keyboard stay put).
	var se := LineEdit.new()
	se.placeholder_text = "Search recipes & output materials…"
	se.text = craft_query
	se.clear_button_enabled = true
	se.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	se.add_theme_font_size_override("font_size", _fs(13))
	se.text_changed.connect(func(t: String) -> void:
		craft_query = t
		_debounce("craft", 0.18, _craft_rebuild_results))
	v.add_child(se)
	# Category tabs are only meaningful when not searching (search spans all tabs).
	if craft_query.strip_edges() == "":
		_subtabs(v, GameData.CRAFT_CATS, craft_cat, CYAN, func(id: String) -> void:
			craft_cat = id
			_refresh_current())
		# Munitions mixes three ammo damage types (Slugs=kinetic, Cells=energy,
		# Missiles=explosive); a second-level filter jumps to the matching type.
		if craft_cat == "munitions":
			_subtabs(v, [
				{"id": "all", "label": "All"},
				{"id": "kinetic", "label": "Kinetic"},
				{"id": "energy", "label": "Energy"},
				{"id": "explosive", "label": "Explosive"},
			], munitions_type, GOLD, func(id: String) -> void:
				munitions_type = id
				_refresh_current())
	# Results wrapper — refilled live on search without rebuilding the whole page.
	var rv := VBoxContainer.new()
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(rv)
	_craft_results = rv
	_craft_fill_results()

# Build the recipe grid into the live wrapper. When searching, ignore the category
# and match by recipe name / output material across all categories; otherwise show
# the selected category (and munitions type sub-filter).
func _craft_fill_results() -> void:
	if not is_instance_valid(_craft_results):
		return
	var v := _craft_results
	var q := craft_query.strip_edges().to_lower()
	var searching := q != ""
	var ids := []
	for id in GameData.CRAFT:
		var r: Dictionary = GameData.CRAFT[id]
		if searching:
			if not _craft_matches(r, q):
				continue
		else:
			if r.get("category", "misc") != craft_cat:
				continue
			if craft_cat == "munitions" and munitions_type != "all" and _ammo_type_of(r) != munitions_type:
				continue
		ids.append(id)
	# Order recipes by unlock level (then name) so early recipes lead.
	ids.sort_custom(func(a: String, b: String) -> bool:
		var la := int(GameData.CRAFT[a].get("level_req", 1))
		var lb := int(GameData.CRAFT[b].get("level_req", 1))
		if la != lb:
			return la < lb
		return String(GameData.CRAFT[a].get("name", a)) < String(GameData.CRAFT[b].get("name", b)))
	if ids.is_empty():
		_empty(v, "No recipes match “%s”." % craft_query.strip_edges() if searching else "No recipes in this category.")
		return
	var g := _grid(v)
	for id in ids:
		g.add_child(_craft_card(id, GameData.CRAFT[id]))
	_scroll_passthrough(v)   # keep new cards touch-droppable for scroll

func _craft_rebuild_results() -> void:
	if not is_instance_valid(_craft_results):
		return
	for c in _craft_results.get_children():
		_craft_results.remove_child(c)
		c.queue_free()
	_craft_fill_results()

# A recipe matches the query if the query is in its name, or in any output
# material's display name / symbol (the "output material" search the player wants),
# or a bonus output's name.
func _craft_matches(r: Dictionary, q: String) -> bool:
	if q in String(r.get("name", "")).to_lower():
		return true
	for sym in r.get("outputs", {}):
		if q in GameData.res_name(sym).to_lower() or q in String(sym).to_lower():
			return true
	for row in r.get("bonus", []):
		if q in GameData.res_name(row[0]).to_lower():
			return true
	return false

# Ammo damage type of a munitions recipe, from its output symbol (Slug=kinetic,
# Cell=energy, Missile/Torpedo=explosive). "" if the recipe isn't ammo.
func _ammo_type_of(r: Dictionary) -> String:
	for sym in r.get("outputs", {}):
		match String(GameState.ammo_bonus(sym)[0]):
			"k": return "kinetic"
			"e": return "energy"
			"x": return "explosive"
	return ""

func _craft_card(id: String, r: Dictionary) -> Control:
	var unlocked := GameState.meets_requirements(r, "fabrication")
	var active := (GameState.active_type == "craft" and GameState.active_id == id)
	var eff_inputs := GameState.effective_craft_inputs(r.get("inputs", {}))   # ENG_3 warp-tree reduction
	var affordable := GameState.can_afford(eff_inputs)
	var v := _card(CYAN, unlocked or active)
	v.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.get_parent().set_meta("coach_id", id)
	if active:
		_breathe_active(v.get_parent())
	# Identity: the primary OUTPUT is the card art; the rate is the hero number;
	# the two inset tables collapse into one "inputs → outputs" chip line.
	var out_syms := []
	for osym in r.get("outputs", {}):
		out_syms.append([osym, 1.0, 0, 0])
	var psym := _primary_sym(out_syms)
	_card_head_mat(v, psym if unlocked else "", "⚙", r["name"], "Lv %d" % int(r.get("level_req", 1)), CYAN, unlocked)
	# Ammo: show a color-coded damage-type chip so the player can tell kinetic /
	# energy / explosive apart at a glance (matches the weapon affinity colors).
	var ammo_type := _ammo_type_of(r)
	if ammo_type != "":
		var tag: Array = _dmg_type_tag(ammo_type)
		var trow := HBoxContainer.new()
		trow.add_child(_tag_chip("⦿ %s" % String(tag[0]), String(tag[1])))
		v.add_child(trow)
	if unlocked:
		var rt := GameState.rate_text("craft", id)
		if rt != "":
			var rl := Label.new()
			rl.text = rt
			rl.add_theme_font_size_override("font_size", _fs(17))
			rl.add_theme_color_override("font_color", Color.html(GREEN))
			_embolden(rl)
			v.add_child(rl)
		_io_chips(v, eff_inputs, r.get("outputs", {}), r.get("bonus", []), CYAN)
		_held_chip(v, psym, active)
		_mastery_row(v, id, CYAN, active)
		var fill := Control.new()
		fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(fill)
		if active or affordable:
			_action_controls(v, "craft", id, active, CYAN)
		else:
			v.add_child(_card_button("Missing Materials", C_MUTED, false))
			_progress(v, false, CYAN)
	else:
		_locked(v, r, "fabrication")
	return v.get_parent()

# ============================================================ COMBAT
func _build_combat() -> void:
	var v := _clear("combat")
	if GameState.active_type == "combat" and not GameState.enemy_inst.is_empty():
		_build_battle(v)
	else:
		_build_targets(v)

func _build_targets(v: VBoxContainer) -> void:
	_skill_banner(v, "BATTLE STATION", "combat", RED)
	# Hull status + repair (no passive regen)
	var hp := GameState.combat_hp
	var mhp := GameState.combat_max_hp()
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 8)
	var hl := Label.new()
	hl.text = "Hull  %d / %d" % [int(hp), int(mhp)]
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hl.add_theme_font_size_override("font_size", _fs(12))
	hl.add_theme_color_override("font_color", Color.html(GREEN if hp >= mhp else C_WARN))
	hrow.add_child(hl)
	if hp < mhp:
		var cost := GameState.repair_cost()
		var rb := _card_button("Repair ₡%s" % GameData.fmt(cost), GREEN, GameState.credits >= cost)
		rb.custom_minimum_size = Vector2(140, 34)
		if GameState.credits >= cost:
			rb.pressed.connect(func() -> void:
				GameState.repair_hull()
				_refresh_current())
		hrow.add_child(rb)
	v.add_child(hrow)
	# Desktop parity (get_available_zones): locked sectors are HIDDEN entirely —
	# their names/descriptions stay secret until the gating research/flag lands.
	var zone_items := []
	for z in GameData.ZONES:
		if _zone_unlocked(z):
			zone_items.append({"id": z["id"], "label": z["name"]})
	combat_zone = clampi(combat_zone, 0, GameData.ZONES.size() - 1)
	if not _zone_unlocked(GameData.ZONES[combat_zone]):
		combat_zone = 0   # selection fell on a hidden sector — snap to Lunar Orbit
	var cur_zone_id: String = GameData.ZONES[combat_zone]["id"]
	_subtabs(v, zone_items, cur_zone_id, RED, func(id: String) -> void:
		for i in GameData.ZONES.size():
			if GameData.ZONES[i]["id"] == id:
				combat_zone = i
		_refresh_current())
	var zone: Dictionary = GameData.ZONES[combat_zone]
	_section(v, zone.get("desc", ""), RED)
	if not _zone_unlocked(zone):
		# Sector access is research-gated, exactly as in the desktop game.
		var req: String = zone.get("research_req", "")
		var rname: String = GameData.RESEARCH.get(req, {}).get("name", req)
		var c := _card(RED, false)
		_card_head(c, "⊘", "SECTOR LOCKED", "", RED, false)
		var lr := Label.new()
		lr.text = "Requires research: %s" % rname
		lr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lr.add_theme_font_size_override("font_size", _fs(11))
		lr.add_theme_color_override("font_color", Color.html(C_WARN))
		c.add_child(lr)
		var gb := _card_button("Go to Research", PURP, true)
		gb.pressed.connect(func() -> void: _show("research"))
		c.add_child(gb)
		return
	var g := _grid(v)
	for eid in zone.get("enemies", []):
		if GameData.ENEMIES.has(eid):
			g.add_child(_enemy_card(eid, GameData.ENEMIES[eid]))

func _zone_unlocked(zone: Dictionary) -> bool:
	var fl: String = zone.get("unlock_flag", "")
	if fl != "" and not GameState.game_flags.get(fl, false):
		return false
	var req: String = zone.get("research_req", "")
	return req == "" or GameState.is_research_unlocked(req)

## Desktop parity: late-game systems stay hidden from navigation until their
## reveal moment (Warp Core @ Zone 6 research; Hazards once one is unlocked).
func _nav_visible(id: String) -> bool:
	match id:
		"warp":
			return GameState.game_flags.get("warp_revealed", false)
		"fleet":
			return GameState.fleet_unlocked()   # after the first warp
		"hazard":
			for hid in GameData.HAZARD_ZONES:
				if GameState.is_hazard_unlocked(hid):
					return true
			return false
	return true

# ---- Damage-type / resistance widgets (v109 headline mechanic) ----
# A short type tag + accent for an enemy's own attack damage type.
func _dmg_type_tag(dmg_type: String) -> Array:
	match dmg_type:
		"energy":    return ["NRG", CYAN]
		"explosive": return ["EXP", BUILD]
		"cryo":      return ["CRYO", "8fdcff"]
		_:           return ["KIN", GOLD]

# A compact color-coded chip (rounded pill). weak = green (good for player),
# resist = red/grey (bad for player). Reused on cards, intel, and atlas.
func _tag_chip(text: String, accent: String) -> Control:
	var pill := PanelContainer.new()
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := _bordered(_mix(accent, INSET, 0.82), _mix(accent, LINE, 0.5), 1, 7)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", _fs(9))
	l.add_theme_color_override("font_color", Color.html(accent))
	pill.add_child(l)
	return pill

# Row of WEAK / RESIST affinity chips for an enemy plus a "Deals: TYPE" chip.
# Negative resist = the enemy takes MORE of that type → ▼ WEAK (green, target it).
# Positive resist = takes LESS → ⛨ RESIST (red, avoid that weapon).
func _affinity_row(e: Dictionary) -> Control:
	var fc := HFlowContainer.new()
	fc.add_theme_constant_override("h_separation", 5)
	fc.add_theme_constant_override("v_separation", 5)
	# The enemy's own attack type — tells the player which armor matters.
	var dt: Array = _dmg_type_tag(String(e.get("dmg_type", "kinetic")))
	fc.add_child(_tag_chip("⚔ DEALS %s" % dt[0], dt[1]))
	# Warp-hardened: conventional damage is near-useless; flag it loudly.
	if bool(e.get("warp_hardened", false)):
		fc.add_child(_tag_chip("⚠ WARP-HARDENED · USE CRYO", PURP))
	for entry in [["resist_k", "KIN"], ["resist_e", "NRG"], ["resist_x", "EXP"], ["resist_cryo", "CRYO"]]:
		var val := float(e.get(entry[0], 0.0))
		if val < -0.05:
			fc.add_child(_tag_chip("▼ WEAK %s %d%%" % [entry[1], int(round(-val * 100.0))], GREEN))
		elif val > 0.05:
			fc.add_child(_tag_chip("⛨ RESIST %s %d%%" % [entry[1], int(round(val * 100.0))], RED))
	return fc

func _enemy_card(id: String, e: Dictionary) -> Control:
	var v := _card(RED, true)
	# Fill the grid row so both cards in a row match the taller one (enemies have
	# varying stat/loot line counts); a spacer pushes Engage to the bottom so the
	# buttons line up across the pair.
	var panel := v.get_parent()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.set_meta("coach_id", id)
	_card_head(v, "◎", e["name"], "", RED, true)
	var stats := [
		_line("HP %s" % GameData.fmt(e["hp"]), C_TEXT),
		_line("ATK %d / %.1fs" % [int(e.get("atk", 0)), float(e.get("interval", 2.0))], C_WARN),
		_line("DEF %d" % int(e.get("def", 0)), C_DIM),
	]
	if int(e.get("max_shield", 0)) > 0:
		stats.insert(1, _line("Shield %s" % GameData.fmt(e["max_shield"]), CYAN))
	_inset(v, "TARGET", stats, RED)
	# Headline mechanic: weakness / resist chips so the player picks the right gun.
	v.add_child(_affinity_row(e))
	# v114 Zone Tier-Gate: hardened back-half/boss — telegraph the wall and how
	# much of your current damage gets through, so "✗ Too strong" is explainable.
	var hardened := GameState.enemy_tier_hardened(id)
	if hardened > 0:
		var hrow := HFlowContainer.new()
		hrow.add_theme_constant_override("h_separation", 5)
		hrow.add_child(_tag_chip("⛛ HARDENED T%d" % hardened, PURP))
		var pen := GameState.tier_pen_avg(id)
		if pen < 0.999:
			hrow.add_child(_tag_chip("YOUR GUNS %d%% — fit Tier-%d gear" % [int(round(pen * 100.0)), hardened], RED))
		v.add_child(hrow)
	elif GameState.enemy_front_salvage(id):
		# Front-half salvage yard: materials only, no module rolls — strip it for parts.
		var srow := HFlowContainer.new()
		srow.add_child(_tag_chip("⛏ SALVAGE — materials only", GOLD))
		v.add_child(srow)
	# v133: mark mission-tasked enemies so the player locks the RIGHT target.
	if id in GameState.get_active_defeat_targets():
		var orow := HFlowContainer.new()
		orow.add_child(_tag_chip("◎ OBJECTIVE", GREEN))
		v.add_child(orow)
	_inset(v, "SALVAGE", _loot_lines(e.get("loot", [])), RED)
	# Idle combat preview: can you win/farm this, and how fast?
	var pv := GameState.combat_preview(id)
	if not pv.is_empty():
		var ptxt := ""
		var pcol := ""
		if not pv["has_weapon"]:
			ptxt = "⚠ Equip a weapon"
			pcol = C_WARN
		elif pv["farmable"]:
			ptxt = "✓ Farmable · %ds / kill" % int(ceil(pv["ttk"]))
			pcol = GREEN
		elif pv["win"]:
			ptxt = "◐ Winnable · %ds / kill" % int(ceil(pv["ttk"]))
			pcol = GOLD
		else:
			ptxt = "✗ Too strong"
			pcol = RED
		var pl := Label.new()
		pl.text = ptxt
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pl.add_theme_font_size_override("font_size", _fs(10))
		pl.add_theme_color_override("font_color", Color.html(pcol))
		v.add_child(pl)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var b := _card_button("Engage", RED, true)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: GameState.start_task("combat", id))
	row.add_child(b)
	var intel := _card_button("ⓘ", CYAN, true)
	intel.custom_minimum_size = Vector2(46, 0)
	intel.pressed.connect(func() -> void: _show_enemy_intel(id))
	row.add_child(intel)
	v.add_child(row)
	return panel

## Enemy "Intel" modal — full stats, guaranteed/rare drops, and the module
## drop pool with lock states (ported from the desktop enemy_info_modal).
func _show_enemy_intel(eid: String) -> void:
	var e: Dictionary = GameData.ENEMIES.get(eid, {})
	if e.is_empty():
		return
	# Shared modal chrome (fold of the old hand-rolled duplicate).
	_modal(String(e.get("name", eid)).to_upper(), RED, _enemy_intel_body.bind(e), "◎", "Close")

func _enemy_intel_body(v: VBoxContainer, _close: Callable, e: Dictionary) -> void:
	_big_stat(v, GameData.fmt(e.get("hp", 0)), "HP", RED, 24)
	var stat_lines := [
		_line("ATK %d / %.1fs" % [int(e.get("atk", 0)), float(e.get("interval", 2.0))], C_WARN),
		_line("DEF %d" % int(e.get("def", 0)), C_DIM),
		_line("Accuracy %d   ·   Evasion %d" % [int(e.get("accuracy", 0)), int(e.get("eva", 0))], C_DIM),
		_line("XP %d" % int(e.get("xp", 0)), GREEN),
	]
	if int(e.get("max_shield", 0)) > 0:
		stat_lines.insert(1, _line("Shield %s" % GameData.fmt(e["max_shield"]), CYAN))
	_inset(v, "COMBAT STATS", stat_lines, RED)
	# Damage-type profile (the headline mechanic) — full affinity breakdown.
	_section(v, "Damage Profile", GREEN)
	var dt: Array = _dmg_type_tag(String(e.get("dmg_type", "kinetic")))
	_clbl(v, "Attacks with %s damage" % dt[0], 11, dt[1])
	v.add_child(_affinity_row(e))
	if bool(e.get("enrage_at", 0.0) > 0.0):
		_clbl(v, "☠ Enrages below %d%% HP  (x%.1f ATK)" % [int(round(float(e["enrage_at"]) * 100.0)), float(e.get("enrage_atk_mult", 1.5))], 10, "ff5933")
	var guaranteed := []
	var rare := []
	for row2 in e.get("loot", []):
		if float(row2[1]) >= 1.0:
			guaranteed.append(_line("%s %d-%d" % [GameData.item_name(row2[0]), int(row2[2]), int(row2[3])], _hex(GameData.color_for(row2[0])), row2[0]))
		else:
			rare.append(_line("★ %s %d-%d  (%d%%)" % [GameData.item_name(row2[0]), int(row2[2]), int(row2[3]), int(float(row2[1]) * 100.0)], PURP, row2[0]))
	if not guaranteed.is_empty():
		_inset(v, "GUARANTEED DROPS", guaranteed, GOLD)
	if not rare.is_empty():
		_inset(v, "RARE DROPS", rare, PURP)
	var pool: Array = e.get("drop_pool", [])
	var chance := float(e.get("drop_chance", 0.0))
	if chance > 0.0 and not pool.is_empty():
		var mlines := []
		for mid in pool:
			var m: Dictionary = GameData.MODULES.get(mid, {})
			if m.is_empty():
				continue
			var unlocked := GameState.module_unlocked(mid)
			var nm: String = ("%s  [%s]" % [m.get("name", mid), GameData.SLOT_LABELS.get(m.get("slot", ""), "")])
			mlines.append(_line(("» " if unlocked else "⊘ ") + nm, CYAN if unlocked else C_MUTED))
		var head := "SUBSPACE SIGNAL — %d%% / kill" % int(round(chance * 100.0))
		_inset(v, head, mlines, CYAN)

# ---- Live battle view ----
func _build_battle(v: VBoxContainer) -> void:
	var e: Dictionary = GameState.enemy_inst
	_skill_banner(v, "BATTLE STATION", "combat", RED)

	# Hazard wave counter — live "WAVE x/y" during a gauntlet run.
	if GameState.hazard_state.get("active", false):
		var hz: Dictionary = GameData.HAZARD_ZONES.get(GameState.hazard_state["zone_id"], {})
		var wv := _card(PURP, true)
		_card_head(wv, "☢", hz.get("name", "Hazard Zone"), "", PURP, true)
		_wave_label = Label.new()
		_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_wave_label.add_theme_font_size_override("font_size", _fs(15))
		_wave_label.add_theme_color_override("font_color", Color.html(PURP))
		_wave_label.text = "WAVE %d/%d" % [int(GameState.hazard_state["wave"]) + 1, int(GameState.hazard_state["max_waves"])]
		wv.add_child(_wave_label)
		v.add_child(wv.get_parent())

	# Enemy combatant
	var ep := _card(RED, true)
	_card_head(ep, "◎", e["name"], "", RED, true)
	# Live affinity readout: weakness / resist + the enemy's own damage type so
	# the player can pick the right weapon mid-fight.
	ep.add_child(_affinity_row(e))
	# ENRAGED indicator — hidden until the enemy enrages (or a telegraph for bosses
	# that enrage below a HP threshold).
	_enrage_chip = _tag_chip("☠ ENRAGED", "ff5933")
	_enrage_chip.visible = GameState.enemy_enraged()
	var erow := HBoxContainer.new()
	erow.add_child(_enrage_chip)
	if not GameState.enemy_enraged() and float(e.get("enrage_at", 0.0)) > 0.0:
		erow.add_child(_tag_chip("☠ enrages < %d%% HP" % int(round(float(e["enrage_at"]) * 100.0)), C_WARN))
	ep.add_child(erow)
	var er := HBoxContainer.new()
	var ehl := Label.new()
	ehl.text = "ENEMY HULL"
	ehl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ehl.add_theme_font_size_override("font_size", _fs(9))
	ehl.add_theme_color_override("font_color", Color.html(RED))
	er.add_child(ehl)
	_enemy_hp_label = Label.new()
	_enemy_hp_label.add_theme_font_size_override("font_size", _fs(9))
	_enemy_hp_label.add_theme_color_override("font_color", Color.html(C_DIM))
	er.add_child(_enemy_hp_label)
	ep.add_child(er)
	_enemy_hp_bar = _mk_bar(ep, RED, 9)
	if float(e["max_shield"]) > 0.0:
		_enemy_shield_bar = _mk_bar(ep, CYAN, 5)
	# Enemy attack timer — fills toward its next strike (desktop combat HUD).
	var eatkl := Label.new()
	eatkl.text = "NEXT ATTACK"
	eatkl.add_theme_font_size_override("font_size", _fs(8))
	eatkl.add_theme_color_override("font_color", Color.html(C_MUTED))
	ep.add_child(eatkl)
	_enemy_atk_bar = _mk_bar(ep, "ef6a52", 5)
	_enemy_anchor = _add_anchor(ep)
	v.add_child(ep.get_parent())

	# Player combatant
	var pp := _card(CYAN, true)
	var hull: Dictionary = GameData.HULLS.get(GameState.active_hull, {})
	_card_head(pp, "◇", hull.get("name", "Ship"), "%d guns" % GameState.ship_weapons().size(), CYAN, true)
	var pr := HBoxContainer.new()
	var phl := Label.new()
	phl.text = "HULL"
	phl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phl.add_theme_font_size_override("font_size", _fs(9))
	phl.add_theme_color_override("font_color", Color.html(CYAN))
	pr.add_child(phl)
	_combat_hp_label = Label.new()
	_combat_hp_label.add_theme_font_size_override("font_size", _fs(9))
	_combat_hp_label.add_theme_color_override("font_color", Color.html(C_DIM))
	pr.add_child(_combat_hp_label)
	pp.add_child(pr)
	_combat_hp_bar = _mk_bar(pp, GREEN, 9)
	if GameState.player_max_shield() > 0.0:
		_player_shield_bar = _mk_bar(pp, CYAN, 5)
	var heatl := Label.new()
	heatl.text = "HEAT"
	heatl.add_theme_font_size_override("font_size", _fs(9))
	heatl.add_theme_color_override("font_color", Color.html(BUILD))
	pp.add_child(heatl)
	_player_heat_bar = _mk_bar(pp, BUILD, 5)
	_player_anchor = _add_anchor(pp)
	v.add_child(pp.get_parent())

	# WEAPON SYSTEMS — per-weapon fire-cooldown bar + live ammo count (desktop's
	# weapon battery). Each row's bar/ammo label is refreshed every frame in
	# _process; a weapon that needs ammo and has none reads "NO AMMO" and dims.
	_weapon_rows = []
	if not GameState._weapons.is_empty():
		var wc := _card(GOLD, true)
		_card_head(wc, "⌖", "WEAPON SYSTEMS", "", GOLD, true)
		for w in GameState._weapons:
			var slot: String = str(w.get("slot", ""))
			var wtype: String = str(w.get("type", "kinetic"))
			var needs_ammo: bool = slot != "" and wtype != "cryo"
			var head := HBoxContainer.new()
			head.add_theme_constant_override("separation", 6)
			var nm := Label.new()
			nm.text = str(w.get("name", "Weapon"))
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nm.add_theme_font_size_override("font_size", _fs(10))
			nm.add_theme_color_override("font_color", Color.html(C_TEXT))
			head.add_child(nm)
			var ammo := Label.new()
			ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			ammo.add_theme_font_size_override("font_size", _fs(10))
			head.add_child(ammo)
			wc.add_child(head)
			var bar := _mk_bar(wc, GOLD, 6)
			bar.max_value = 100
			# Store the live weapon dict (the engine mutates w["timer"] in place).
			_weapon_rows.append({"bar": bar, "ammo": ammo, "slot": slot, "needs_ammo": needs_ammo, "w": w})
		v.add_child(wc.get_parent())

	# v134h (desktop parity): in-fight loadout swap in ANY active combat. Load a
	# saved preset to re-arm mid-engagement (e.g. bring the matching exotic weapon).
	if GameState.can_swap_loadout_in_combat():
		var sc := _card("8fdcff", true)
		_card_head(sc, "⟳", "SWAP LOADOUT", "", "8fdcff", true)
		_clbl(sc, "Load a preset to re-arm mid-fight (resets weapon cooldowns).", 9, C_DIM)
		var any_preset := false
		for pi in [1, 2, 3]:
			if GameState._preset_has_no_modules(GameState.loadout_presets.get(pi, {})):
				continue
			any_preset = true
			var pname: String = GameState.loadout_presets[pi].get("name", "")
			if pname == "":
				pname = "Preset %d" % pi
			var pb := _card_button("⟳ %s" % pname, "8fdcff", true)
			pb.custom_minimum_size = Vector2(0, 42)
			var idx: int = pi
			pb.pressed.connect(func() -> void:
				GameState.swap_loadout_in_combat(idx)
				_refresh_current())
			sc.add_child(pb)
		if not any_preset:
			_clbl(sc, "⚠ Save a loadout as a preset (Ship Designer) to swap here.", 9, C_WARN)
		v.add_child(sc.get_parent())

	# Session loot — a running "SALVAGE THIS RUN" tally of everything dropped this
	# engagement (desktop session-loot parity). Rows live-rebuild in _process only
	# when GameState.session_loot changes (see _loot_seen_count).
	var lp := _card(GOLD, true)
	var lhdr := HBoxContainer.new()
	lhdr.add_theme_constant_override("separation", 6)
	var lt := Label.new()
	lt.text = "◆  SALVAGE THIS RUN"
	lt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lt.add_theme_font_size_override("font_size", _fs(12))
	lt.add_theme_color_override("font_color", Color.html(GOLD))
	lhdr.add_child(lt)
	var fbtn := _card_button("⚙ Filter", CYAN, true)
	fbtn.add_theme_font_size_override("font_size", _fs(10))
	fbtn.pressed.connect(_open_loot_filter)
	lhdr.add_child(fbtn)
	lp.add_child(lhdr)
	# Cap the salvage list height and scroll within it — a day of farming can drop
	# hundreds of distinct rows, which otherwise stretched the page endlessly.
	_loot_scroll = ScrollContainer.new()
	_loot_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_loot_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_loot_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lp.add_child(_loot_scroll)
	_loot_panel = VBoxContainer.new()
	_loot_panel.add_theme_constant_override("separation", 2)
	_loot_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loot_scroll.add_child(_loot_panel)
	v.add_child(lp.get_parent())
	_loot_seen_count = -1
	_rebuild_loot_rows()

	# Manual consumables (desktop combat page): hull / shield kits on demand,
	# shared cooldown — the early-game survival tool.
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	for kind in ["hull", "shield"]:
		var item: String = GameState.consumable_hull_slot if kind == "hull" else GameState.consumable_shield_slot
		if item == "" or GameState.amount(item) <= 0:
			for cid in GameData.CONSUMABLES:
				if GameData.CONSUMABLES[cid].get("type", "") == kind and GameState.amount(cid) > 0:
					item = cid
					break
		var owned := GameState.amount(item) if item != "" else 0
		var lbl := ("⚒ Repair" if kind == "hull" else "✦ Shield") + ("  x%d" % owned if owned > 0 else "")
		var cb := _card_button(lbl, GREEN if kind == "hull" else CYAN, owned > 0)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if owned > 0:
			var k: String = kind
			cb.pressed.connect(func() -> void:
				GameState.use_manual_consumable(k)
				_refresh_current())
		crow.add_child(cb)
	v.add_child(crow)

	var rb := _card_button("⛒ Retreat", RED, true)
	rb.custom_minimum_size = Vector2(0, 42)
	rb.pressed.connect(func() -> void: GameState.stop_task())
	v.add_child(rb)
	_seen_events = GameState._event_seq   # only show events from here on

# Resolve a session-loot id to a (display name, hex color) pair. Handles rolled /
# set / base modules (rarity-colored display name) and plain resources (element color).
func _loot_display(id: String) -> Array:
	if id == "credits":
		return ["Credits", GOLD]
	if GameState.custom_modules.has(id):
		var md: Dictionary = GameState.custom_modules[id]
		return [String(md.get("name", id)), GameState.RARITY_COLOR.get(int(md.get("rarity", 0)), C_TEXT)]
	# Rolled/set module that was sold or scrapped this run: its custom_modules entry
	# is gone but session_loot still lists it. Derive the base name from the cid so
	# the salvage row reads e.g. "Concussion Missile" instead of "cm_z3_missile_…".
	var cbase := _cid_base(id)
	if cbase != "":
		return [GameData.item_name(cbase), C_MUTED]
	if GameData.MODULES.has(id) or GameData.SET_MODULES.has(id):
		var bd: Dictionary = GameData.MODULES.get(id, GameData.SET_MODULES.get(id, {}))
		return [String(bd.get("name", id)), GameState.RARITY_COLOR.get(int(bd.get("rarity", 0)), C_TEXT)]
	return [GameData.res_name(id), _hex(GameData.color_for(id))]

# Base module id from a generated instance id: "cm_<base>_<ticks>_<rand>" or
# "set_<base>_<rand>" → "<base>" (base ids may themselves contain underscores).
func _cid_base(id: String) -> String:
	var parts := id.split("_")
	if parts.size() >= 4 and parts[0] == "cm":
		return "_".join(parts.slice(1, parts.size() - 2))
	if parts.size() >= 3 and parts[0] == "set":
		return "_".join(parts.slice(1, parts.size() - 1))
	return ""

# Rebuild the SALVAGE THIS RUN rows from GameState.session_loot. Cheap and only
# called when the loot dictionary actually grew (tracked by _loot_seen_count).
func _rebuild_loot_rows() -> void:
	if not is_instance_valid(_loot_panel):
		return
	for ch in _loot_panel.get_children():
		ch.queue_free()
	var loot: Dictionary = GameState.session_loot
	if loot.is_empty():
		_clbl(_loot_panel, "[ NO YIELD YET ]", 11, C_MUTED)
		if is_instance_valid(_loot_scroll):
			_loot_scroll.custom_minimum_size.y = 0
		return
	for id in loot:
		var disp := _loot_display(id)
		var txt := "%s × %s" % [disp[0], GameData.fmt(int(loot[id]))]
		var icon: TextureRect = _mat_icon(id, 16)
		if icon != null:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 5)
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(icon)
			var lbl := Label.new()
			lbl.text = txt
			lbl.add_theme_font_size_override("font_size", _fs(12))
			lbl.add_theme_color_override("font_color", Color.html(disp[1]))
			row.add_child(lbl)
			_loot_panel.add_child(row)
		else:
			_clbl(_loot_panel, txt, 12, disp[1])
	# Grow with content up to ~9 rows, then cap and scroll inside.
	if is_instance_valid(_loot_scroll):
		var row_h := maxi(_fs(12), 16) + 8
		_loot_scroll.custom_minimum_size.y = float(mini(loot.size(), 9) * row_h)

# Loot filter modal (desktop parity): toggle which module drops to keep by rarity,
# slot, and weapon damage type. Filtered drops are skipped at roll time.
func _open_loot_filter() -> void:
	_modal("LOOT FILTER", CYAN, func(v: VBoxContainer, _close: Callable) -> void:
		_clbl(v, "Drops concentrate to the types you keep (targeted farming) — narrow it to farm one slot or weapon type. Rarity still filters after the roll.", 9, C_MUTED)
		_section(v, "RARITY", CYAN)
		var rr := HFlowContainer.new()
		rr.add_theme_constant_override("h_separation", 6)
		rr.add_theme_constant_override("v_separation", 6)
		for r in [0, 1, 2, 3, 4]:
			var rlabel: String = GameState.RARITY_LABEL.get(r, "")
			if rlabel == "":
				rlabel = "Common"
			_filter_toggle(rr, GameState.loot_filter, r, rlabel, GameState.RARITY_COLOR.get(r, C_TEXT))
		v.add_child(rr)
		_section(v, "SLOT", CYAN)
		var sr := HFlowContainer.new()
		sr.add_theme_constant_override("h_separation", 6)
		sr.add_theme_constant_override("v_separation", 6)
		for slot in ["weapon", "armor", "shield", "engine", "battery", "sensor"]:
			_filter_toggle(sr, GameState.loot_type_filter, slot, String(GameData.SLOT_LABELS.get(slot, slot)), CYAN)
		v.add_child(sr)
		_section(v, "WEAPON DAMAGE TYPE", CYAN)
		var wr := HFlowContainer.new()
		wr.add_theme_constant_override("h_separation", 6)
		wr.add_theme_constant_override("v_separation", 6)
		for wt in ["kinetic", "energy", "explosive", "cryo"]:
			_filter_toggle(wr, GameState.loot_weapon_type_filter, wt, wt.capitalize(), CYAN)
		v.add_child(wr))

# A single keep/skip toggle pill bound to a filter dict key.
func _filter_toggle(parent: Node, dict: Dictionary, key, label: String, accent: String) -> void:
	var on := bool(dict.get(key, true))
	var b := _card_button(("● " if on else "○ ") + label, accent, true)
	b.add_theme_font_size_override("font_size", _fs(10))
	b.modulate.a = 1.0 if on else 0.38
	b.pressed.connect(func() -> void:
		var nv := not bool(dict.get(key, true))
		dict[key] = nv
		b.text = ("● " if nv else "○ ") + label
		b.modulate.a = 1.0 if nv else 0.38)
	parent.add_child(b)

func _drain_combat_events() -> void:
	for ev in GameState.combat_events:
		if int(ev.get("seq", -1)) >= _seen_events:
			_seen_events = int(ev["seq"]) + 1
			_spawn_popup(ev)

func _spawn_popup(ev: Dictionary) -> void:
	var anchor: Control = _enemy_anchor if ev.get("side", "enemy") == "enemy" else _player_anchor
	if not is_instance_valid(anchor) or anchor.size.x < 20.0:
		return
	var is_crit: bool = String(ev["text"]).begins_with("CRIT")
	var l := Label.new()
	l.text = ev["text"]
	l.add_theme_font_size_override("font_size", _fs(20 if is_crit else 16))
	l.add_theme_color_override("font_color", Color.html(ev["color"]))
	# Black outline keeps numbers readable over any art.
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 7)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(clampf(randf_range(16.0, anchor.size.x - 80.0), 8.0, maxf(8.0, anchor.size.x - 70.0)), anchor.size.y * 0.35)
	anchor.add_child(l)
	# Scale-pop entrance (bigger for crits), then drift up and fade.
	l.pivot_offset = Vector2(30, 12)
	l.scale = Vector2(1.5, 1.5) if is_crit else Vector2(1.25, 1.25)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2(1.0, 1.0), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "position:y", l.position.y - 34.0, 0.75)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.75).set_delay(0.25)
	tw.tween_callback(l.queue_free)
	# Taking hull damage lands physically: screen nudge + red vignette flash.
	if ev.get("side", "") == "player" and String(ev.get("color", "")) == "ef6a52":
		_shake()
		_flash_hit()

# ---- Floating gain popups (idle juice) ----------------------------------
# Generalized _spawn_popup: "+N ⟨icon⟩" that pops off `anchor`, drifts up and
# fades on the persistent _fx_layer. Capped concurrency; node-bound tweens.
func _float_gain(anchor: Control, tex: Texture2D, text: String, color: String) -> void:
	if _fx_layer == null or anchor == null or not is_instance_valid(anchor) or not anchor.is_visible_in_tree():
		return
	if _gain_fx_live >= 10:
		return
	_gain_fx_live += 1
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 3)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex != null:
		var ic := TextureRect.new()
		ic.texture = tex
		ic.custom_minimum_size = Vector2(20, 20)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(ic)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", _fs(13))
	l.add_theme_color_override("font_color", Color.html(color))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_embolden(l)
	hb.add_child(l)
	# _fx_layer is full-rect at the window origin, so globals map directly.
	var gr := anchor.get_global_rect()
	hb.position = Vector2(gr.position.x + gr.size.x * randf_range(0.25, 0.6), gr.position.y - 6.0)
	_fx_layer.add_child(hb)
	hb.pivot_offset = Vector2(20, 10)
	hb.scale = Vector2(1.3, 1.3)
	hb.modulate.a = 0.0
	var tw := hb.create_tween()
	tw.tween_property(hb, "scale", Vector2(1.0, 1.0), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(hb, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(hb, "position:y", hb.position.y - 40.0, 0.9)
	tw.tween_property(hb, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func() -> void:
		_gain_fx_live = maxi(0, _gain_fx_live - 1)
		hb.queue_free())

# Claim burst: a handful of material icons (or ₡ glyphs) fan out from the tapped
# control and fly to the header credits pill — the "loot goes to my wallet" beat.
# Pure tween fan-out on _fx_layer; ~6 nodes for under a second.
func _fly_to_credits(from: Control, sym: String, n := 5) -> void:
	if _fx_layer == null or from == null or not is_instance_valid(from) or not is_instance_valid(_hdr_credits):
		return
	var start := from.get_global_rect().get_center()
	var target := _hdr_credits.get_global_rect().get_center()
	var tex := _mat_icon_tex(sym) if sym != "" and sym != "credits" else null
	var count := clampi(n, 4, 6)
	for i in count:
		var node: Control
		if tex != null:
			var t := TextureRect.new()
			t.texture = tex
			t.custom_minimum_size = Vector2(22, 22)
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			node = t
		else:
			var l := Label.new()
			l.text = "₡"
			l.add_theme_font_size_override("font_size", _fs(16))
			l.add_theme_color_override("font_color", Color.html(GOLD))
			_embolden(l)
			node = l
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.position = start - Vector2(11, 11)
		_fx_layer.add_child(node)
		var mid := start + Vector2(randf_range(-60, 60), randf_range(-55, -15))
		var tw := node.create_tween()
		tw.tween_interval(0.05 * i)   # stagger
		tw.tween_property(node, "position", mid - Vector2(11, 11), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(node, "position", target - Vector2(11, 11), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(node, "scale", Vector2(0.4, 0.4), 0.45)
		tw.parallel().tween_property(node, "modulate:a", 0.6, 0.45)
		tw.tween_callback(node.queue_free)

# One gather/craft loop finished — pop its top gains off the active card (or the
# banner when browsing another page). NOTE: never call _refresh_* from here; this
# handler must not fight the idle-loop no-rebuild guard.
func _on_cycle_completed(_type: String, _id: String, gains: Dictionary) -> void:
	var anchor: Control = null
	if is_instance_valid(_active_bar) and _active_bar.is_visible_in_tree():
		anchor = _active_bar
	elif is_instance_valid(active_banner):
		anchor = active_banner
	if anchor == null:
		return
	# Top 3 gains by amount — enough to feel rich without spam.
	# Live-refresh the active card's held-quantity chip (captured handle — no rebuild).
	if is_instance_valid(_held_label) and _held_sym != "":
		_held_label.text = "◈ %s held" % GameData.fmt(GameState.amount(_held_sym))
	var syms := gains.keys()
	syms.sort_custom(func(a, b) -> bool: return int(gains[a]) > int(gains[b]))
	var shown := 0
	for sym in syms:
		if shown >= 3:
			break
		var amt := int(gains[sym])
		if sym == "credits":
			_float_gain(anchor, null, "+₡%s" % GameData.fmt(amt), GOLD)
		else:
			_float_gain(anchor, _mat_icon_tex(String(sym)), "+%s" % GameData.fmt(amt), _hex(GameData.color_for(String(sym))))
		shown += 1
	# XP conduit pulse — the skill banner's bar flashes brighter on each loop.
	# Modulate only; _process keeps owning `value`. Stack-guarded by the meta flag.
	if is_instance_valid(_skill_bar) and _skill_bar.is_visible_in_tree() and not _skill_bar.has_meta("pulsing"):
		_skill_bar.set_meta("pulsing", true)
		var tw := _skill_bar.create_tween()
		tw.tween_property(_skill_bar, "modulate", Color(1.4, 1.35, 1.1), 0.12)
		tw.tween_property(_skill_bar, "modulate", Color.WHITE, 0.25)
		tw.tween_callback(func() -> void:
			if is_instance_valid(_skill_bar):
				_skill_bar.remove_meta("pulsing"))

func _shake() -> void:
	if safe_margin == null:
		return
	var tw := create_tween()
	tw.tween_property(safe_margin, "position:x", 5.0, 0.04)
	tw.tween_property(safe_margin, "position:x", -4.0, 0.05)
	tw.tween_property(safe_margin, "position:x", 2.0, 0.04)
	tw.tween_property(safe_margin, "position:x", 0.0, 0.04)

func _flash_hit() -> void:
	if _hit_flash == null:
		return
	_hit_flash.color = Color(0.95, 0.25, 0.18, 0.14)
	var tw := create_tween()
	tw.tween_property(_hit_flash, "color:a", 0.0, 0.30)

func _mk_bar(parent: VBoxContainer, accent: String, h: int) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(0, h)
	b.show_percentage = false
	b.max_value = 100
	b.value = 100
	_style_bar(b, accent)
	parent.add_child(b)
	return b

func _add_anchor(vbox: VBoxContainer) -> Control:
	var a := Control.new()
	a.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.clip_contents = false
	vbox.get_parent().add_child(a)
	return a

# ============================================================ INFRASTRUCTURE
func _build_infra() -> void:
	var v := _clear("build")
	_back_header(v)
	_skill_banner(v, "INFRASTRUCTURE", "infrastructure", BUILD)
	var p := GameState.infra_power()
	var eff := int(float(p["eff"]) * 100.0)
	_stat_strip(v, [
		["⚡ GEN", "%d kW" % int(p["gen"]), GREEN],
		["USE", "%d kW" % int(p["cons"]), GOLD],
		["GRID", "%d%%" % eff, BUILD if float(p["eff"]) >= 1.0 else RED],
	])
	_subtabs(v, GameData.BUILDING_CATS, build_cat, BUILD, func(id: String) -> void:
		build_cat = id
		_refresh_current())
	var g := _grid(v)
	var any := false
	for bid in GameData.BUILDINGS:
		var d: Dictionary = GameData.BUILDINGS[bid]
		if d.get("category", "industry") != build_cat:
			continue
		any = true
		g.add_child(_building_card(bid, d))
	if not any:
		_empty(v, "Nothing here.")

func _building_card(bid: String, d: Dictionary) -> Control:
	var unlocked := GameState.building_unlocked(bid)
	var count := GameState.building_count(bid)
	var v := _card(BUILD, unlocked or count > 0)
	v.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.get_parent().set_meta("coach_id", bid)
	_card_head(v, "⌂", d["name"], "x%d" % count, BUILD, unlocked)
	if not unlocked:
		_locked(v, d, "infrastructure")
		return v.get_parent()
	if d.get("desc", "") != "":
		_clbl(v, d["desc"], 10, C_DIM)
	# effect (per building) lines
	var eff_lines := []
	for sym in d.get("yield", {}):
		var nm := "Credits" if sym == "credits" else GameData.res_name(sym)
		eff_lines.append(_line("+%s %s" % [str(d["yield"][sym]), nm], GREEN))
	for sym in d.get("input", {}):
		eff_lines.append(_line("-%d %s" % [int(d["input"][sym]), GameData.res_name(sym)], C_WARN, sym))
	if float(d.get("energy_gen", 0.0)) > 0.0:
		eff_lines.append(_line("+%d kW" % int(d["energy_gen"]), CYAN))
	if float(d.get("energy_cons", 0.0)) > 0.0:
		eff_lines.append(_line("-%d kW" % int(d["energy_cons"]), C_WARN))
	if not eff_lines.is_empty():
		_inset(v, "PER UNIT / %.0fs" % float(d.get("interval", 1.0)), eff_lines, BUILD)
	# Building Mastery: output scales with the linked recipe/action's Mastery,
	# and running the building feeds that Mastery back.
	var minfo := GameState.building_mastery_info(bid)
	if minfo.get("linked", false):
		var mid := String(minfo.get("id", ""))
		var mnm: String = String(GameData.CRAFT[mid].get("name", mid)) if GameData.CRAFT.has(mid) else String(GameData.GATHER.get(mid, {}).get("name", mid))
		_clbl(v, "◆ Mastery: %s  Lv %d  (+%d%% output)" % [mnm, int(minfo["level"]), int(minfo["bonus_pct"])], 10, PURP)
	var brt := GameState.building_rate_text(bid)
	if brt != "":
		_clbl(v, brt, 10, GREEN if count > 0 else C_DIM)
	# Throttle (any owned building — scales production and energy)
	if count > 0:
		var th := GameState.get_throttle(bid)
		var ocd := GameState.building_overclocked(bid)
		var ocmax := GameState.overclock_max_throttle(bid)
		var trow := HBoxContainer.new()
		trow.add_theme_constant_override("separation", 6)
		var minus := _card_button("−", BUILD, th > 0.0)
		minus.custom_minimum_size = Vector2(40, 30)
		minus.pressed.connect(func() -> void:
			GameState.set_throttle(bid, th - 0.25)
			_refresh_current())
		trow.add_child(minus)
		var tl := Label.new()
		tl.text = ("⚡ Overclock %d%%" % int(th * 100.0)) if th > 1.0 else ("Throttle %d%%" % int(th * 100.0))
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.add_theme_font_size_override("font_size", _fs(11))
		tl.add_theme_color_override("font_color", Color.html(PURP if th > 1.0 else C_DIM))
		trow.add_child(tl)
		var plus := _card_button("+", BUILD, th < ocmax)
		plus.custom_minimum_size = Vector2(40, 30)
		plus.pressed.connect(func() -> void:
			GameState.set_throttle(bid, th + 0.25)
			_refresh_current())
		trow.add_child(plus)
		v.add_child(trow)
		# Overclock: install a Boost Card to raise the cap to 200%, or a warning
		# once overclocked past 100% (input scales quadratically).
		if not ocd:
			var have_card := GameState.amount("BoostCard") > 0
			var ib := _card_button("⚡ Install Boost Card" if have_card else "⚡ Needs a Boost Card", BUILD, have_card)
			ib.custom_minimum_size = Vector2(0, 32)
			if have_card:
				ib.pressed.connect(func() -> void:
					var r: Dictionary = GameState.install_boost_card(bid)
					_celebrate("⚡ OVERCLOCK" if r.get("ok", false) else "✕", String(r.get("msg", "")), PURP if r.get("ok", false) else RED)
					_refresh_current())
			v.add_child(ib)
		elif th > 1.0:
			_clbl(v, "⚠ Input scales ² past 100% — 200% output costs 4× input.", 9, C_WARN)
	var bfill := Control.new()
	bfill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(bfill)
	# cost
	var maxed := d.has("max") and count >= int(d["max"])
	if maxed:
		v.add_child(_card_button("MAX BUILT", C_MUTED, false))
	else:
		var cost := GameState.building_cost(bid)
		var cost_lines := []
		for sym in cost:
			var have: bool = GameState.credits >= int(cost[sym]) if sym == "credits" else GameState.amount(sym) >= int(cost[sym])
			var label := "₡%s" % GameData.fmt(cost[sym]) if sym == "credits" else "%s %s" % [GameData.fmt(cost[sym]), GameData.res_name(sym)]
			cost_lines.append(_line(label, GREEN if have else C_WARN))
		_inset(v, "COST", cost_lines, BUILD)
		var can := GameState.building_can_afford(bid)
		var b := _card_button("Build", BUILD, can)
		if can:
			# Build is a user-initiated structural change. The build page is an
			# IDLE_LOOP_PAGE, so while an action is looping the resources_changed
			# signal won't rebuild it — refresh explicitly so the new count/cost
			# (and spent resources) show immediately instead of looking like a no-op.
			b.pressed.connect(func() -> void:
				GameState.build_building(bid)
				_refresh_current())
		v.add_child(b)
	return v.get_parent()

# ============================================================ MORE MENU
func _build_more() -> void:
	var v := _clear("more")
	var t := Label.new()
	t.text = "SYSTEMS"
	t.add_theme_font_size_override("font_size", _fs(16))
	t.add_theme_color_override("font_color", Color.html(CYAN))
	v.add_child(t)
	for it in MORE_MENU:
		if not _nav_visible(it["id"]):
			continue
		var b := Button.new()
		b.text = it["label"]
		b.custom_minimum_size = Vector2(0, 54)
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", _fs(15))
		b.add_theme_color_override("font_color", Color.html(C_TEXT))
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, _bordered("16243a", "2a3a55", 1, 8))
		var pid: String = it["id"]
		b.pressed.connect(func() -> void: _show(pid))
		v.add_child(b)
	_empty(v, "Fleet · Bounty · Warp coming next.")

# ============================================================ BOUNTY BOARD
func _build_bounty() -> void:
	var v := _clear("bounty")
	_back_header(v)
	var t := Label.new()
	t.text = "◆ BOUNTY BOARD"
	t.add_theme_font_size_override("font_size", _fs(16))
	t.add_theme_color_override("font_color", Color.html(GOLD))
	v.add_child(t)

	var rr := HBoxContainer.new()
	var rt := Label.new()
	var secs := int(GameState.bounty_refresh_timer)
	rt.text = "Auto-refresh in %dh %dm" % [secs / 3600, (secs % 3600) / 60]
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_size_override("font_size", _fs(11))
	rt.add_theme_color_override("font_color", Color.html(C_DIM))
	rr.add_child(rt)
	var cost := GameState.bounty_refresh_cost()
	var rb := _card_button("Refresh ₡%s" % GameData.fmt(cost), GOLD, GameState.credits >= cost)
	rb.custom_minimum_size = Vector2(150, 32)
	if GameState.credits >= cost:
		rb.pressed.connect(func() -> void:
			GameState.force_refresh_bounty()
			_refresh_current())
	rr.add_child(rb)
	v.add_child(rr)

	_section(v, "ACTIVE  (%d/%d)" % [GameState.bounty_active.size(), GameState.BOUNTY_MAX_ACTIVE], GOLD)
	if GameState.bounty_active.is_empty():
		_empty(v, "No active contracts — accept some below.")
	for c in GameState.bounty_active:
		v.add_child(_bounty_card(c, true))

	_section(v, "AVAILABLE", GOLD)
	if GameState.bounty_available.is_empty():
		_empty(v, "Board is empty.")
	for c in GameState.bounty_available:
		v.add_child(_bounty_card(c, false))

func _bounty_card(c: Dictionary, active: bool) -> Control:
	var elite: bool = c.get("is_elite", false)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bordered("16243a", GOLD if elite else "2a3a55", 2 if elite else 1))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	_lbl_wrap(vb, c.get("title", ""), 14, GOLD if elite else C_TEXT)
	_lbl_wrap(vb, c.get("desc", ""), 10, C_DIM)
	var reward := Label.new()
	reward.text = "Reward: ₡%s" % GameData.fmt(c.get("reward_credits", 0))
	reward.add_theme_font_size_override("font_size", _fs(11))
	reward.add_theme_color_override("font_color", Color.html(GOLD))
	vb.add_child(reward)

	var cid: String = c["id"]
	if active:
		if c["type"] == "hunt":
			var pg := Label.new()
			pg.text = "Progress: %d / %d" % [int(c["current_qty"]), int(c["target_qty"])]
			pg.add_theme_font_size_override("font_size", _fs(11))
			pg.add_theme_color_override("font_color", Color.html(GREEN if c["completed"] else C_DIM))
			vb.add_child(pg)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		if c["completed"]:
			var claim := _card_button("Claim", GREEN, true)
			claim.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			claim.pressed.connect(func() -> void:
				GameState.claim_contract(cid)
				_refresh_current())
			row.add_child(claim)
		var ab := _card_button("Abandon", C_WARN, true)
		ab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ab.pressed.connect(func() -> void:
			GameState.abandon_contract(cid)
			_refresh_current())
		row.add_child(ab)
		vb.add_child(row)
	else:
		var can := GameState.bounty_active.size() < GameState.BOUNTY_MAX_ACTIVE
		if c["type"] == "delivery":
			var need := int(c["target_qty"])
			var have := GameState.amount(c["target"])
			var nl := Label.new()
			nl.text = "You have %s / %s" % [GameData.fmt(have), GameData.fmt(need)]
			nl.add_theme_font_size_override("font_size", _fs(10))
			nl.add_theme_color_override("font_color", Color.html(GREEN if have >= need else C_WARN))
			vb.add_child(nl)
			can = can and have >= need
		var acc := _card_button("Accept" if can else ("Slots Full" if GameState.bounty_active.size() >= GameState.BOUNTY_MAX_ACTIVE else "Need Materials"), GOLD, can)
		if can:
			acc.pressed.connect(func() -> void:
				GameState.accept_contract(cid)
				_refresh_current())
		vb.add_child(acc)
	return panel

func _lbl_wrap(parent: Node, text: String, size: int, color: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", _fs(size))
	l.add_theme_color_override("font_color", Color.html(color))
	parent.add_child(l)

# ============================================================ STANDING ORDERS
# Second quest board (distinct from Bounties): passive tracking on every slot at
# once, instant claim with auto-replace, no accept/abandon, manual reroll.
func _build_standing() -> void:
	var v := _clear("standing")
	_back_header(v)
	var t := Label.new()
	t.text = "▤ STANDING ORDERS"
	t.add_theme_font_size_override("font_size", _fs(16))
	t.add_theme_color_override("font_color", Color.html(CYAN))
	v.add_child(t)
	_lbl_wrap(v, "Passive jobs tracked automatically — gather orders sync from your inventory, sweep orders count kills. Claim grants credits + a material bonus and auto-replaces the slot.", 10, C_DIM)

	var rr := HBoxContainer.new()
	rr.add_theme_constant_override("separation", 6)
	var done := 0
	for q in GameState.standing_orders():
		if q.get("completed", false) and not q.get("claimed", false):
			done += 1
	var st := Label.new()
	st.text = "%d ready to claim · %d completed" % [done, GameState.standing_total]
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	st.add_theme_font_size_override("font_size", _fs(11))
	st.add_theme_color_override("font_color", Color.html(C_DIM))
	rr.add_child(st)
	var rcost := GameState.standing_reroll_cost()
	var rb := _card_button("Reroll ₡%s" % GameData.fmt(rcost), CYAN, GameState.credits >= rcost)
	rb.custom_minimum_size = Vector2(160, 40)
	if GameState.credits >= rcost:
		rb.pressed.connect(func() -> void:
			GameState.reroll_standing_orders()
			_refresh_current())
	rr.add_child(rb)
	v.add_child(rr)

	_section(v, "ORDERS  (%d)" % GameState.standing_orders().size(), CYAN)
	if GameState.standing_orders().is_empty():
		_empty(v, "Board is empty.")
	for i in GameState.standing_orders().size():
		v.add_child(_standing_card(i, GameState.standing_orders()[i]))

func _standing_card(idx: int, q: Dictionary) -> Control:
	var complete: bool = q.get("completed", false)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bordered("16243a", GREEN if complete else "2a3a55", 2 if complete else 1))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	var ttag := "▤ " if q.get("type", "") == "gather" else "◎ "
	_lbl_wrap(vb, ttag + q.get("title", ""), 14, GREEN if complete else C_TEXT)
	_lbl_wrap(vb, q.get("desc", ""), 10, C_DIM)
	# Reward line: credits + (optional) material bonus.
	var rtxt := "Reward: ₡%s" % GameData.fmt(q.get("reward_credits", 0))
	var mat: Dictionary = q.get("reward_material", {})
	if not mat.is_empty():
		rtxt += "  +%d %s" % [int(mat["qty"]), GameData.res_name(mat["id"])]
	var reward := Label.new()
	reward.text = rtxt
	reward.add_theme_font_size_override("font_size", _fs(11))
	reward.add_theme_color_override("font_color", Color.html(GOLD))
	vb.add_child(reward)
	# Progress bar (gather syncs from inventory; hunt counts kills).
	var cur := int(q.get("current_qty", 0))
	var tgt := maxi(1, int(q.get("target_qty", 1)))
	var pg := Label.new()
	pg.text = "Progress: %s / %s" % [GameData.fmt(cur), GameData.fmt(tgt)]
	pg.add_theme_font_size_override("font_size", _fs(11))
	pg.add_theme_color_override("font_color", Color.html(GREEN if complete else C_DIM))
	vb.add_child(pg)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.show_percentage = false
	bar.max_value = tgt
	bar.value = cur
	_style_bar(bar, GREEN if complete else CYAN)
	vb.add_child(bar)
	if complete:
		var claim := _card_button("Claim", GREEN, true)
		claim.pressed.connect(func() -> void:
			GameState.claim_standing_order(idx)
			_fly_to_credits(claim, "credits")
			_refresh_current())
		vb.add_child(claim)
	return panel

# ============================================================ WARP CORE
func _build_missions() -> void:
	var v := _clear("missions")
	_back_header(v)
	var t := Label.new()
	t.text = "✦ MISSIONS"
	t.add_theme_font_size_override("font_size", _fs(16))
	t.add_theme_color_override("font_color", Color.html(PURP))
	v.add_child(t)
	_lbl_wrap(v, "%d completed" % GameState.missions_claimed.size(), 11, C_DIM)
	_section(v, "Active Objectives", PURP)
	if GameState.missions_active.is_empty():
		_empty(v, "All missions complete. Well done, Commander.")
	for mid in GameState.missions_active:
		v.add_child(_mission_card(mid))

func _mission_card(mid: String) -> Control:
	var m: Dictionary = GameData.MISSIONS[mid]
	var done := GameState.mission_completed(mid)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _card_style(SURFACE, GREEN if done else LINE, 1, done))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	_lbl_wrap(vb, m.get("name", mid), 14, GREEN if done else C_TEXT)
	_lbl_wrap(vb, m.get("desc", ""), 10, C_DIM)
	var mtype: String = m.get("type", "")
	var cur := int(GameState.missions_progress.get(mid, 0))
	var qty := int(m.get("qty", 1))
	if mtype == "gather_multi":
		cur = GameState.multi_have(m)
		for s in m.get("target", {}):
			var need := int(m["target"][s])
			var have := mini(GameState.amount(s), need)
			_lbl_wrap(vb, "%s  %d / %d" % [GameData.res_name(s), have, need], 10, GREEN if have >= need else C_DIM)
	elif mtype == "research_multi":
		cur = GameState.research_multi_have(m)
		for tid in m.get("target", []):
			var got := GameState.is_research_unlocked(String(tid))
			var tname: String = GameData.RESEARCH.get(String(tid), {}).get("name", String(tid))
			_lbl_wrap(vb, "%s %s" % ["✓" if got else "○", tname], 10, GREEN if got else C_DIM)
	elif mtype == "loadout_check":
		cur = qty if done else 0
		_lbl_wrap(vb, ("✓ Weapon + Shield equipped" if done else "Equip a Weapon and a Shield"), 10, GREEN if done else C_WARN)
	if qty > 1:
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 7)
		bar.show_percentage = false
		bar.max_value = qty
		bar.value = cur
		_style_bar(bar, GREEN if done else PURP)
		vb.add_child(bar)
		_lbl_wrap(vb, "%s / %s" % [GameData.fmt(cur), GameData.fmt(qty)], 9, C_MUTED)
	var rl := Label.new()
	rl.text = "Reward: ₡%s" % GameData.fmt(m.get("cr", 0))
	rl.add_theme_font_size_override("font_size", _fs(11))
	rl.add_theme_color_override("font_color", Color.html(GOLD))
	vb.add_child(rl)
	if done:
		var b := _card_button("Claim Reward", GREEN, true)
		b.pressed.connect(func() -> void:
			var cr := int(int(m.get("cr", 0)) * GameState.warp_production_mult())
			if GameState.claim_mission(mid):
				_celebrate("✦  MISSION COMPLETE", "+₡%s" % GameData.fmt(cr), GREEN)
				_fly_to_credits(b, "credits")
			_refresh_current())
		vb.add_child(b)
	return panel

# Fleet Command (v0.2.1 soft role): build escort ships that boost combat damage.
func _build_fleet() -> void:
	var v := _clear("fleet")
	_back_header(v)
	_clbl(v, "❖ FLEET COMMAND", 16, CYAN)
	if not GameState.fleet_unlocked():
		_empty(v, "Perform your first Warp to commission a fleet.")
		return
	_section(v, "Fleet  %d / %d   ·   +%d%% combat damage" % [GameState.fleet_count(), GameState.fleet_capacity(), GameState.fleet_combat_bonus_pct()], CYAN)
	_clbl(v, "Each ship adds 25% of your ship's damage (max +100%).", 10, C_DIM)
	# Owned ships.
	if GameState.fleet_ships.is_empty():
		_empty(v, "No ships yet — build one below.")
	else:
		for i in GameState.fleet_ships.size():
			var hid: String = String(GameState.fleet_ships[i].get("hull_id", ""))
			var c := _card(CYAN, true)
			_card_head(c, "⛭", String(GameState.FLEET_HULLS.get(hid, {}).get("name", hid)), "", CYAN, true)
			var idx := i
			var scrap := _card_button("Scrap (no refund)", RED, true)
			scrap.pressed.connect(func() -> void:
				GameState.fleet_scrap(idx)
				_refresh_current())
			c.add_child(scrap)
			v.add_child(c.get_parent())
	# Buildable hulls (unlocked by warp depth).
	_section(v, "COMMISSION", GOLD)
	var full := GameState.fleet_count() >= GameState.fleet_capacity()
	for hid in GameState.fleet_buildable_hulls():
		var hd: Dictionary = GameState.FLEET_HULLS[hid]
		var can := GameState.fleet_can_build(hid)
		var c := _card(GOLD, can)
		_card_head(c, "▣", String(hd.get("name", hid)), "", GOLD, can)
		var cl := []
		for sym in hd.get("cost", {}):
			var need := int(hd["cost"][sym])
			cl.append(_line("%s %s" % [GameData.fmt(need), GameData.res_name(sym)], GREEN if GameState.amount(sym) >= need else C_WARN, sym))
		_inset(c, "COST", cl, GOLD)
		var b := _card_button("Fleet full" if full else "Build", GOLD, can)
		if can:
			var h: String = String(hid)
			b.pressed.connect(func() -> void:
				GameState.fleet_build(h)
				_refresh_current())
		c.add_child(b)
		v.add_child(c.get_parent())

func _build_warp() -> void:
	var v := _clear("warp")
	_back_header(v)
	var t := Label.new()
	t.text = "✦ WARP CORE"
	t.add_theme_font_size_override("font_size", _fs(16))
	t.add_theme_color_override("font_color", Color.html(PURP))
	v.add_child(t)
	_subtabs(v, [{"id": "core", "label": "Warp Core"}, {"id": "mastery", "label": "Mastery Tree"}], warp_view, PURP, func(id: String) -> void:
		warp_view = id
		_refresh_current())
	match warp_view:
		"mastery": _warp_mastery(v)
		_:         _warp_core(v)

func _warp_core(v: VBoxContainer) -> void:
	_lbl_wrap(v, "Collapse your empire into a Warp Core for permanent Warp Shards. Skills keep 30%% XP, buildings/ship reset — but researched tech stays unlocked.", 10, C_DIM)

	# PRESTIGE HERO — the shard hoard as a dramatic full-bleed centerpiece.
	var hero := PanelContainer.new()
	hero.add_theme_stylebox_override("panel", _surface_style(_mix(PURP, SURFACE, 0.90), PURP, true))
	var hv := VBoxContainer.new()
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	hv.add_theme_constant_override("separation", 3)
	hero.add_child(hv)
	var hcap := Label.new()
	hcap.text = "✦ WARP SHARDS"
	hcap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hcap.add_theme_font_size_override("font_size", _fs(10))
	hcap.add_theme_color_override("font_color", Color.html(PURP))
	_embolden(hcap)
	hv.add_child(hcap)
	var hval := Label.new()
	hval.text = GameData.fmt(int(GameState.warp_shards))
	hval.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hval.add_theme_font_size_override("font_size", _fs(34))
	hval.add_theme_color_override("font_color", Color.html(C_TEXT))
	_embolden(hval)
	hv.add_child(hval)
	_clbl(hv, "Warps %d   ·   Tier %d" % [GameState.total_warps, GameState.warp_tier()], 10, C_DIM)
	# Progress toward the NEXT shard (log-scaled thresholds double per shard).
	var hero_earned: int = GameState.lifetime_credits - GameState.credits_at_warp_start
	var hero_b := 0
	for hbid in GameState.buildings:
		hero_b += int(GameState.buildings[hbid])
	var hero_score := float(hero_earned + hero_b * 1000) * GameState.tree_shard_score_mult()
	var hero_gain := GameState.warp_gain_preview()
	var next_thr := 500000.0 * pow(2.0, float(maxi(hero_gain, 0)))
	var hbar := ProgressBar.new()
	hbar.custom_minimum_size = Vector2(0, 16)
	hbar.show_percentage = false
	hbar.max_value = 100
	hbar.value = clampf(hero_score / next_thr * 100.0, 0.0, 100.0)
	_style_bar(hbar, PURP)
	hv.add_child(hbar)
	_clbl(hv, "next shard at ₡%s" % GameData.fmt(int(next_thr)), 9, C_MUTED)
	v.add_child(hero)

	_section(v, "PERMANENT BONUSES", PURP)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bordered("241f3e", "453c6b", 1, 6))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	_clbl(box, "Gathering  +%d%%" % int((GameState.warp_gathering_mult() - 1.0) * 100.0), 12, GREEN)
	_clbl(box, "All XP  +%d%%" % int((GameState.warp_xp_mult() - 1.0) * 100.0), 12, GREEN)
	_clbl(box, "Production  +%d%%" % int((GameState.warp_production_mult() - 1.0) * 100.0), 12, GREEN)
	_clbl(box, "Combat  +%d%%" % int((GameState.warp_combat_mult() - 1.0) * 100.0), 12, GREEN)
	v.add_child(panel)

	# Prestige preview
	var earned: int = GameState.lifetime_credits - GameState.credits_at_warp_start
	var bcount := 0
	for bid in GameState.buildings:
		bcount += int(GameState.buildings[bid])
	var score: int = earned + bcount * 1000
	var gain := GameState.warp_gain_preview()
	_section(v, "WARP READOUT", PURP)
	_lbl_wrap(v, "Progress score: ₡%s  (lifetime credits since last warp + buildings)" % GameData.fmt(score), 11, C_TEXT)
	if gain <= 0:
		_lbl_wrap(v, "Reach a score of ₡500K to earn your first Warp Shard.", 11, C_WARN)
	else:
		_lbl_wrap(v, "Warping now grants %d Warp Shard%s." % [gain, "s" if gain != 1 else ""], 12, GREEN)

	# v135a legibility: lead the warp screen with the persistent REWARD — the
	# standing multipliers Warp Shards grant, which carry across every warp. Neutral
	# state on a chosen screen (no "warp now" prompt).
	_section(v, "WARP REWARDS", PURP)
	_lbl_wrap(v, "Warp Shards permanently raise these standing bonuses (they persist through every warp):", 10, C_DIM)
	_clbl(v, "⚙ Production   ×%.2f" % GameState.warp_production_mult(), 11, GOLD)
	_clbl(v, "⚔ Combat       ×%.2f" % GameState.warp_combat_mult(), 11, GOLD)
	_clbl(v, "⛏ Gathering    ×%.2f" % GameState.warp_gathering_mult(), 11, GOLD)
	_clbl(v, "✦ XP           ×%.2f" % GameState.warp_xp_mult(), 11, GOLD)
	if gain > 0:
		_lbl_wrap(v, "You currently hold %s shards; warping banks +%d more." % [GameData.fmt(int(GameState.warp_shards)), gain], 10, C_DIM)

	# Warp-Core Charge: feed surplus bulk base materials for bonus shards this warp.
	var charge_bonus := GameState.get_charge_bonus_shards(gain)
	_section(v, "WARP-CORE CHARGE", PURP)
	_lbl_wrap(v, "Feed your surplus of bulk base materials into the Core for bonus shards on your next Warp. Charge is consumed when you Warp.", 10, C_DIM)
	_clbl(v, "Charge stored: %s   →   +%d bonus shard%s" % [GameData.fmt(int(GameState.warp_charge)), charge_bonus, "s" if charge_bonus != 1 else ""], 12, GREEN if charge_bonus > 0 else C_DIM)
	var any_feed := false
	for sym in GameState.CHARGE_WEIGHT:
		var have := GameState.amount(sym)
		if have <= 0:
			continue
		any_feed = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var icon := _mat_icon(sym, 20)
		if icon != null:
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(icon)
		var nl := Label.new()
		nl.text = "%s  ·  %s" % [GameData.res_name(sym), GameData.fmt(have)]
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nl.add_theme_font_size_override("font_size", _fs(11))
		nl.add_theme_color_override("font_color", Color.html(C_TEXT))
		row.add_child(nl)
		var cval := int(GameState.charge_value(sym, float(have)))
		var fb := _card_button("Feed +%s" % GameData.fmt(cval), PURP, true)
		fb.custom_minimum_size = Vector2(120, 40)
		var s: String = sym
		fb.pressed.connect(func() -> void:
			GameState.feed_core(s, float(GameState.amount(s)))
			_refresh_current())
		row.add_child(fb)
		v.add_child(row)
	if not any_feed:
		_lbl_wrap(v, "No feedable base materials in storage yet (Dirt, Water, Wood, ores, Fe/Si/C…).", 10, C_MUTED)

	var total_gain := gain + charge_bonus
	_section(v, "EXECUTE WARP", PURP)
	var wb := _card_button(("⚠ Tap again to WARP (+%d)" % total_gain) if _warp_armed else ("WARP for %d Shard%s" % [total_gain, "s" if total_gain != 1 else ""]), PURP, gain > 0)
	wb.custom_minimum_size = Vector2(0, 46)
	if gain > 0:
		wb.pressed.connect(func() -> void:
			if _warp_armed:
				var gained := GameState.execute_warp()
				_warp_armed = false
				_celebrate("✦  WARP COMPLETE", "+%d Warp Shard%s" % [gained, "s" if gained != 1 else ""], PURP)
				_fly_to_credits(wb, "credits")
				_show("warp")
			else:
				_warp_armed = true
				_refresh_current())
	v.add_child(wb)

# Warp Mastery Tree — 2 branches × 5 nodes, spent via available shards. Purchased
# nodes persist across warps (true meta-progression).
func _warp_mastery(v: VBoxContainer) -> void:
	var avail := GameState.available_warp_shards()
	var sh := Label.new()
	sh.text = "Available Shards: %s   ·   Spent: %s" % [GameData.fmt(int(avail)), GameData.fmt(int(GameState.warp_shards_spent))]
	sh.add_theme_font_size_override("font_size", _fs(13))
	sh.add_theme_color_override("font_color", Color.html(PURP))
	v.add_child(sh)
	_lbl_wrap(v, "Spend Warp Shards on permanent mastery nodes. Purchases survive every Warp. Branches unlock as you Warp. Spine (◆) nodes are repeatable — each level costs a little more.", 10, C_DIM)
	_warp_branch(v, "engineering", "ENGINEERING", GREEN)
	_warp_branch(v, "combat", "COMBAT", RED)
	_warp_branch(v, "recursion", "RECURSION", PURP)

func _warp_branch(v: VBoxContainer, branch: String, title: String, accent: String) -> void:
	var revealed := GameState.is_branch_revealed(branch)
	_section(v, title, accent)
	if not revealed:
		var need := int(GameState.BRANCH_REVEAL_WARP[branch])
		_empty(v, "Warp %d time%s to reveal this branch." % [need, "s" if need != 1 else ""])
		return
	for nid in GameState.TREE_BRANCH_ORDER[branch]:
		v.add_child(_warp_node_card(nid))

func _warp_node_card(nid: String) -> Control:
	var node: Dictionary = GameState.TREE_NODES[nid]
	var repeatable: bool = node.get("repeatable", false)
	var level := GameState.get_node_level(nid)
	var owned := GameState.is_node_purchased(nid)   # finite: bought; spine: level >= 1
	var can := GameState.can_purchase_node(nid)
	var impl: bool = node.get("implemented", true)
	var cost := GameState.get_node_cost(nid)
	var prereq_ok := true
	for p in node.get("prereq", []):
		if not GameState.is_node_purchased(p):
			prereq_ok = false
	var cap: int = int(node.get("cap", 0))
	var maxed := repeatable and cap > 0 and level >= cap
	# Lit gold when a finite node is owned or a spine has levels; accent-bordered when
	# affordable; dim otherwise.
	var lit := owned
	var border := GOLD if (owned and not repeatable) else (PURP if (repeatable and level > 0) else (CYAN if can else "2a3a55"))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bordered("16243a", border, 2 if (lit or can) else 1))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	panel.add_child(vb)
	var head := Label.new()
	var tag := "◆ " if repeatable else ""   # spine marker
	var check := "✔ " if (owned and not repeatable) else ""
	var lvtxt := ("  ·  Lv %d%s" % [level, ("/%d" % cap) if cap > 0 else ""]) if (repeatable and level > 0) else ""
	head.text = "%s%s%s%s" % [check, tag, node.get("name", nid), lvtxt]
	head.add_theme_font_size_override("font_size", _fs(13))
	head.add_theme_color_override("font_color", Color.html(GOLD if (owned and not repeatable) else (PURP if level > 0 else C_TEXT)))
	vb.add_child(head)
	_lbl_wrap(vb, node.get("desc", ""), 10, C_DIM)
	var cl := Label.new()
	cl.text = ("Next level: %d Shard%s" % [cost, "s" if cost != 1 else ""]) if repeatable else ("Cost: %d Shard%s" % [cost, "s" if cost != 1 else ""])
	cl.add_theme_font_size_override("font_size", _fs(10))
	cl.add_theme_color_override("font_color", Color.html(PURP))
	vb.add_child(cl)
	if owned and not repeatable:
		_clbl(vb, "PURCHASED", 11, GOLD)
	elif maxed:
		_clbl(vb, "MAXED  (Lv %d)" % level, 11, PURP)
	elif not impl:
		_clbl(vb, "Coming soon", 10, C_MUTED)
	elif not prereq_ok:
		var names := []
		for p in node.get("prereq", []):
			names.append(GameState.TREE_NODES.get(p, {}).get("name", p))
		_clbl(vb, "⊘ Requires: " + ", ".join(names), 10, C_WARN)
	else:
		var afford := GameState.available_warp_shards() >= float(cost)
		var label := ("Level up  (%d)" % cost) if repeatable else "Purchase"
		if not afford:
			label = "Need %d Shards" % cost
		var b := _card_button(label, PURP, can)
		if can:
			b.pressed.connect(func() -> void:
				GameState.purchase_tree_node(nid)
				_refresh_current())
		vb.add_child(b)
	return panel

func _back_header(v: VBoxContainer) -> void:
	var b := Button.new()
	b.text = "☰  Menu"
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", _fs(13))
	b.add_theme_color_override("font_color", Color.html(C_DIM))
	b.pressed.connect(_open_drawer)
	v.add_child(b)

# ============================================================ SHIPYARD
# Fabrication page: craft/buy modules (Module Shop) + construct/repair hulls.
# Loadout/Armory/Fittings live on the Ship Designer page.
func _build_shipyard() -> void:
	var v := _clear("shipyard")
	_back_header(v)
	var eyebrow := Label.new()
	eyebrow.text = "⚒ SHIPYARD"
	eyebrow.add_theme_font_size_override("font_size", _fs(16))
	eyebrow.add_theme_color_override("font_color", Color.html(CYAN))
	v.add_child(eyebrow)
	var sub := Label.new()
	sub.text = "Fabricate modules & construct hulls"
	sub.add_theme_font_size_override("font_size", _fs(12))
	sub.add_theme_color_override("font_color", Color.html(C_DIM))
	v.add_child(sub)
	_subtabs(v, [{"id": "modules", "label": "Modules"}, {"id": "hulls", "label": "Hulls"}], shipyard_view, CYAN, func(id: String) -> void:
		shipyard_view = id
		_refresh_current())
	match shipyard_view:
		"modules": _shipyard_modules(v)
		"hulls": _ship_hulls(v)

func _build_ship() -> void:
	var v := _clear("ship")
	_back_header(v)
	var eyebrow := Label.new()
	eyebrow.text = "⛭ SHIP DESIGNER"
	eyebrow.add_theme_font_size_override("font_size", _fs(16))
	eyebrow.add_theme_color_override("font_color", Color.html(CYAN))
	v.add_child(eyebrow)
	var h: Dictionary = GameData.HULLS.get(GameState.active_hull, {})
	var nm := Label.new()
	nm.text = h.get("name", "No Ship")
	nm.add_theme_font_size_override("font_size", _fs(12))
	nm.add_theme_color_override("font_color", Color.html(C_DIM))
	v.add_child(nm)
	var s := GameState.ship_stats()
	if not s.is_empty():
		_stat_strip(v, [
			["ATK", "%.0f" % s["atk"], RED],
			["HP", GameData.fmt(s["hp"]), GREEN],
			["DEF", "%.0f" % s["def"], CYAN],
			["SHIELD", GameData.fmt(s["shield"]), "3a9fff"],
		])
		var over: bool = s["energy_load"] > s["energy_cap"] and s["energy_cap"] > 0.0
		var erow := HBoxContainer.new()
		erow.add_theme_constant_override("separation", 8)
		var elab := Label.new()
		elab.text = "⚡ Energy"
		elab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		elab.add_theme_font_size_override("font_size", _fs(10))
		elab.add_theme_color_override("font_color", Color.html(C_DIM))
		erow.add_child(elab)
		var ebar := ProgressBar.new()
		ebar.custom_minimum_size = Vector2(0, 8)
		ebar.show_percentage = false
		ebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ebar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ebar.max_value = maxf(1.0, float(s["energy_cap"]))
		ebar.value = float(s["energy_load"])
		_style_bar(ebar, RED if over else CYAN)
		erow.add_child(ebar)
		var eval := Label.new()
		eval.text = "%d / %d kW%s" % [int(s["energy_load"]), int(s["energy_cap"]), "  ⚠" if over else ""]
		eval.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		eval.add_theme_font_size_override("font_size", _fs(10))
		eval.add_theme_color_override("font_color", Color.html(C_WARN if over else C_DIM))
		erow.add_child(eval)
		v.add_child(erow)
	# Ship Designer = LOADOUT: equipped slots, the Armory (owned-module pool you
	# equip FROM), and ammo/consumable fittings. Fabrication lives in the Shipyard.
	if ship_view in ["modules", "hulls"]:
		ship_view = "loadout"   # legacy state migration (those tabs moved to Shipyard)
	_subtabs(v, [{"id": "loadout", "label": "Loadout"}, {"id": "armory", "label": "Armory"}, {"id": "fittings", "label": "Fittings"}], ship_view, CYAN, func(id: String) -> void:
		ship_view = id
		if id != "armory":
			ship_target_slot = -1     # leaving the slot-first flow
		_refresh_current())
	match ship_view:
		"loadout": _ship_loadout(v, h)
		"armory": _ship_armory(v)
		"fittings": _ship_fittings(v, h)

func _ship_fittings(v: VBoxContainer, h: Dictionary) -> void:
	_section(v, "Auto-Consumables  (trigger at 50%)", CYAN)
	_consumable_picker(v, "hull", "Hull Repair Kit", GameState.consumable_hull_slot)
	_consumable_picker(v, "shield", "Shield Booster", GameState.consumable_shield_slot)
	_section(v, "Weapon Ammo  (consumed per shot, +damage)", CYAN)
	# Iterate EFFECTIVE slots (base + aux) and key off the equipped module's own
	# slot type, so an aux-slot weapon gets its ammo card too — and module_def
	# resolves custom rolls that GameData.MODULES wouldn't.
	var any := false
	for i in GameState.effective_slots().size():
		var akey := str(i)
		if not GameState.loadout.has(akey):
			continue
		var wmd: Dictionary = GameState.module_def(GameState.loadout[akey])
		if wmd.get("slot", "") == "weapon":
			any = true
			_ammo_picker(v, akey, wmd)
	if not any:
		_empty(v, "Equip weapons (Loadout) to load ammo.")

func _consumable_picker(v: VBoxContainer, kind: String, title: String, current: String) -> void:
	var c := _card(CYAN, true)
	_card_head(c, "✦", title, "", CYAN, true)
	_pick_button(c, kind == "hull" and current == "" or kind == "shield" and current == "", "None", current == "", func() -> void: GameState.set_consumable(kind, ""))
	for cid in GameData.CONSUMABLES:
		var d: Dictionary = GameData.CONSUMABLES[cid]
		if d.get("type", "") != kind:
			continue
		var owned := GameState.amount(cid)
		if owned <= 0 and cid != current:
			continue
		var label := "%s  x%d  (+%d%%)" % [d.get("name", cid), owned, int(float(d.get("heal_pct", 0)) * 100.0)]
		_pick_button(c, cid == current, label, cid == current, func() -> void: GameState.set_consumable(kind, cid))
	v.add_child(c.get_parent())

func _ammo_picker(v: VBoxContainer, slot: String, m: Dictionary) -> void:
	var st: Dictionary = m.get("stats", {})
	var letter := "k"
	if float(st.get("atk_energy", 0)) > 0: letter = "e"
	elif float(st.get("atk_explosive", 0)) > 0: letter = "x"
	var current: String = GameState.ammo_loadout.get(slot, "")
	var c := _card(CYAN, true)
	_card_head(c, "◆", m.get("name", "Weapon"), "", CYAN, true)
	_pick_button(c, current == "", "No Ammo (base damage)", current == "", func() -> void: GameState.set_ammo(slot, ""))
	for sym in GameData.RESOURCES:
		var ab := GameState.ammo_bonus(sym)
		if ab[0] != letter:
			continue
		var owned := GameState.amount(sym)
		if owned <= 0 and sym != current:
			continue
		_pick_button(c, sym == current, "%s  x%s  (+%d dmg)" % [GameData.res_name(sym), GameData.fmt(owned), int(ab[1])], sym == current, func() -> void: GameState.set_ammo(slot, sym))
	v.add_child(c.get_parent())

func _pick_button(parent: VBoxContainer, _ignored: bool, label: String, active: bool, cb: Callable) -> void:
	var b := _card_button(label, CYAN if active else C_MUTED, true)
	b.add_theme_font_size_override("font_size", _fs(12))
	b.pressed.connect(cb)
	parent.add_child(b)

## A wrapping row of compact stat pills: each [label, value, accent_hex].
func _stat_strip(v: VBoxContainer, pairs: Array) -> void:
	var fc := HFlowContainer.new()
	fc.add_theme_constant_override("h_separation", 6)
	fc.add_theme_constant_override("v_separation", 6)
	for p in pairs:
		var pill := PanelContainer.new()
		var sb := _bordered(_mix(p[2], INSET, 0.78), _mix(p[2], LINE, 0.55), 1, 8)
		sb.content_margin_left = 11
		sb.content_margin_right = 11
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		pill.add_theme_stylebox_override("panel", sb)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 5)
		pill.add_child(hb)
		var l := Label.new()
		l.text = p[0]
		l.add_theme_font_size_override("font_size", _fs(9))
		l.add_theme_color_override("font_color", Color.html(C_DIM))
		hb.add_child(l)
		var val := Label.new()
		val.text = str(p[1])
		val.add_theme_font_size_override("font_size", _fs(12))
		val.add_theme_color_override("font_color", Color.html(p[2]))
		_embolden(val)   # label small, number big+bold
		hb.add_child(val)
		fc.add_child(pill)
	v.add_child(fc)

# Human-readable label for a trinity bonus key (matches GameData bonus dicts).
func _trinity_bonus_label(key: String, val: float) -> String:
	var names := {
		"atk_speed_pct": "Attack Speed", "hp_regen_flat": "Hull Regen", "all_dmg_pct": "All Damage",
		"evasion_flat": "Evasion", "enemy_def_reduce_pct": "Enemy DEF Shred", "missile_dmg_pct": "Missile Damage",
		"def_pct": "Defense", "reflect_pct": "Damage Reflect", "accuracy_flat": "Accuracy",
		"shield_regen_pct": "Shield Regen", "def_flat": "Defense", "energy_dmg_pct": "Energy Damage",
		"crit_chance": "Crit Chance", "shield_hp_pct": "Shield HP", "atk_pct": "Attack",
	}
	var nm: String = names.get(key, key.replace("_", " ").capitalize())
	var suffix := "%" if key.ends_with("_pct") or key.ends_with("_chance") else ""
	return "+%d%s %s" % [int(round(val)), suffix, nm]

# Trinity-set panel: only sets the player has a piece of are shown — active ones
# lit with their full bonus list, in-progress ones as discoverable progress. Sets
# with zero equipped pieces are hidden (no point listing the whole catalog on the
# loadout). Reused on Ship and the sim.
func _trinity_view(v: VBoxContainer) -> void:
	var counts := GameState.equipped_set_counts()
	# Nothing from any set equipped → don't show the section header at all.
	var any_progress := false
	for sn in GameData.SETS:
		if int(counts.get(sn, 0)) > 0:
			any_progress = true
			break
	if not any_progress:
		return
	_section(v, "Trinity Set Bonuses", PURP)
	var active := GameState.active_trinity_sets()
	for sn in GameData.SETS:
		var sd: Dictionary = GameData.SETS.get(sn, {})
		var have := int(counts.get(sn, 0))
		# Only surface sets the player actually has a module equipped for.
		if have <= 0:
			continue
		var pieces := int(GameData.TRINITY_SET_BONUSES.get(sn, {}).get("pieces", 3))
		var is_active: bool = sn in active
		var c := _card(PURP, is_active)
		var badge := "%d/%d" % [have, pieces]
		_card_head(c, "✦" if is_active else "○", sd.get("name", sn), badge, PURP, is_active)
		var blines := []
		var bonus: Dictionary = GameData.TRINITY_SET_BONUSES.get(sn, {})
		for k in bonus:
			if k == "name" or k == "pieces":
				continue
			blines.append(_line(_trinity_bonus_label(k, float(bonus[k])), GOLD if is_active else C_MUTED))
		if sd.get("bonus_desc", "") != "":
			blines.append(_line("✦ " + sd["bonus_desc"], PURP if is_active else C_MUTED))
		_inset(c, "ACTIVE" if is_active else "EQUIP 3 PIECES TO ACTIVATE", blines, PURP, is_active)
		v.add_child(c.get_parent())

func _ship_loadout(v: VBoxContainer, h: Dictionary) -> void:
	var slots: Array = h.get("slots", [])
	if slots.is_empty():
		_empty(v, "No ship.")
		return
	_trinity_view(v)
	_section(v, "SHIP SLOTS — tap a slot to fit or swap a module", CYAN)
	var g := _grid(v)
	# The aux slot (CMB_3 warp node) renders after the base slots as an ANY-type
	# blade; effective_slots() appends it, so iterating that count draws it inline.
	var render_slots: Array = GameState.effective_slots()
	for i in render_slots.size():
		var stype: String = render_slots[i]
		var key := str(i)
		var equipped: String = GameState.loadout.get(key, "")
		var filled := equipped != ""
		# The aux slot reads warp-purple so the extra any-type blade is unmistakable.
		var scol: String = PURP if stype == "aux" else CYAN
		var c := _card(scol, filled)
		# Filled slots read bright; empty slots are de-emphasised so equipped gear pops.
		_card_head(c, "✦" if stype == "aux" else ("▣" if filled else "▢"), GameData.SLOT_LABELS.get(stype, stype), "", scol, filled)
		if filled:
			var md: Dictionary = GameState.module_def(equipped)
			var rcol: String = GameState.RARITY_COLOR.get(int(md.get("rarity", 0)), C_TEXT)
			_clbl(c, md.get("name", equipped), 12, rcol)
			for aid in md.get("affixes", {}):
				_clbl(c, _affix_text(aid, md["affixes"][aid]), 9, GameState.RARITY_COLOR.get(3, GOLD))
			_clbl(c, "tap to manage ›", 9, "5d6b88")
		else:
			_clbl(c, "Empty", 11, C_MUTED)
			_clbl(c, "tap to fit from Armory ›", 9, "5d6b88")
		# Whole slot is tappable: empty → Armory for this slot; filled → slot menu.
		var idx := i
		var st := stype
		var eq := equipped
		var tap := Button.new()
		tap.flat = true
		tap.focus_mode = Control.FOCUS_NONE
		tap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tap.pressed.connect(func() -> void:
			if eq != "":
				_open_slot_menu(idx, st, eq)
			else:
				_open_slot_armory(idx, st))
		c.get_parent().add_child(tap)
		g.add_child(c.get_parent())
	# Fittings as cards too (parity with module slots): the two auto-consumables and
	# one ammo card per equipped weapon. Tapping opens a picker modal.
	_section(v, "FITTINGS — tap to load ammo & consumables", CYAN)
	var fg := _grid(v)
	var hull_c: String = GameState.consumable_hull_slot
	_fitting_card(fg, "Hull Repair Kit", _consumable_label(hull_c), hull_c != "",
		func() -> void: _open_consumable_picker("hull", "Hull Repair Kit"))
	var shield_c: String = GameState.consumable_shield_slot
	_fitting_card(fg, "Shield Booster", _consumable_label(shield_c), shield_c != "",
		func() -> void: _open_consumable_picker("shield", "Shield Booster"))
	for i in slots.size():
		if slots[i] != "weapon" or not GameState.loadout.has(str(i)):
			continue
		var wslot := str(i)
		var wmod: Dictionary = GameState.module_def(GameState.loadout[wslot])
		var cur_ammo: String = GameState.ammo_loadout.get(wslot, "")
		_fitting_card(fg, "Ammo · " + String(wmod.get("name", "Weapon")), _ammo_label(cur_ammo), cur_ammo != "",
			func() -> void: _open_ammo_picker(wslot, wmod))
	_loadout_presets(v)

# A loadout fitting card (consumable or ammo) styled like a module slot card.
func _fitting_card(grid: GridContainer, title: String, current_label: String, filled: bool, on_tap: Callable) -> void:
	var c := _card(CYAN, filled)
	_card_head(c, "▣" if filled else "▢", title, "", CYAN, filled)
	_clbl(c, current_label, 12, CYAN if filled else C_MUTED)
	_clbl(c, "tap to manage ›", 9, "5d6b88")
	var tap := Button.new()
	tap.flat = true
	tap.focus_mode = Control.FOCUS_NONE
	tap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tap.pressed.connect(on_tap)
	c.get_parent().add_child(tap)
	grid.add_child(c.get_parent())

func _consumable_label(cid: String) -> String:
	if cid == "":
		return "None"
	var d: Dictionary = GameData.CONSUMABLES.get(cid, {})
	return "%s  x%d" % [d.get("name", cid), GameState.amount(cid)]

func _ammo_label(sym: String) -> String:
	if sym == "":
		return "No Ammo (base)"
	return "%s  x%s" % [GameData.res_name(sym), GameData.fmt(GameState.amount(sym))]

# Picker modal that closes + refreshes on selection (shared by the loadout fitting
# cards). One option per row.
func _fit_pick(v: VBoxContainer, label: String, active: bool, cb: Callable, close: Callable) -> void:
	var b := _card_button(("● " if active else "") + label, CYAN if active else C_MUTED, true)
	b.add_theme_font_size_override("font_size", _fs(12))
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(func() -> void:
		cb.call()
		close.call()
		_refresh_current())
	v.add_child(b)

func _open_consumable_picker(kind: String, title: String) -> void:
	var body := func(v: VBoxContainer, close: Callable) -> void:
		var cur: String = GameState.consumable_hull_slot if kind == "hull" else GameState.consumable_shield_slot
		_fit_pick(v, "None", cur == "", func() -> void: GameState.set_consumable(kind, ""), close)
		for cid in GameData.CONSUMABLES:
			var d: Dictionary = GameData.CONSUMABLES[cid]
			if d.get("type", "") != kind:
				continue
			var owned := GameState.amount(cid)
			if owned <= 0 and cid != cur:
				continue
			var label := "%s  x%d  (+%d%%)" % [d.get("name", cid), owned, int(float(d.get("heal_pct", 0)) * 100.0)]
			_fit_pick(v, label, cid == cur, func() -> void: GameState.set_consumable(kind, cid), close)
	_modal(title, CYAN, body, "◇")

func _open_ammo_picker(slot: String, m: Dictionary) -> void:
	var st: Dictionary = m.get("stats", {})
	var letter := "k"
	if float(st.get("atk_energy", 0)) > 0: letter = "e"
	elif float(st.get("atk_explosive", 0)) > 0: letter = "x"
	var body := func(v: VBoxContainer, close: Callable) -> void:
		var cur: String = GameState.ammo_loadout.get(slot, "")
		_fit_pick(v, "No Ammo (base damage)", cur == "", func() -> void: GameState.set_ammo(slot, ""), close)
		for sym in GameData.RESOURCES:
			var ab := GameState.ammo_bonus(sym)
			if ab[0] != letter:
				continue
			var owned := GameState.amount(sym)
			if owned <= 0 and sym != cur:
				continue
			_fit_pick(v, "%s  x%s  (+%d dmg)" % [GameData.res_name(sym), GameData.fmt(owned), int(ab[1])], sym == cur, func() -> void: GameState.set_ammo(slot, sym), close)
	_modal("Ammo · " + String(m.get("name", "Weapon")), CYAN, body, "▣")

# Auto-assign equip (Shipyard shop / quick-equip buttons): equip into the first
# free matching slot, then direct the player to ammo for that slot like the
# slot-first flow does. Finds the slot the module landed in.
func _equip_from_shop(mid: String) -> void:
	var before := {}
	for k in GameState.loadout:
		before[k] = GameState.loadout[k]
	var ok := GameState.equip_module(mid)
	_refresh_current()
	if not ok:
		return
	for k in GameState.loadout:
		if not before.has(k) and String(GameState.loadout[k]) == mid:
			_prompt_ammo_if_needed(int(k))
			return

## Open the Armory targeted at a specific slot index (slot-first equip flow).
func _open_slot_armory(idx: int, stype: String) -> void:
	ship_target_slot = idx
	ship_mod_slot = stype
	ship_view = "armory"
	_refresh_current()

# After a weapon is equipped/swapped into slot `idx`, direct the player to choose
# ammo: a swap clears the slot's ammo binding, so a non-cryo weapon lands with no
# ammo selected. Only prompts when the player actually owns matching ammo (else
# there's nothing to pick). Cryo weapons use no ammo and are skipped.
func _prompt_ammo_if_needed(idx: int) -> void:
	var key := str(idx)
	var mid: String = GameState.loadout.get(key, "")
	if mid == "":
		return
	var md: Dictionary = GameState.module_def(mid)
	if md.get("slot", "") != "weapon":
		return
	var st: Dictionary = md.get("stats", {})
	if float(st.get("atk_cryo", 0)) > 0:
		return   # cryo weapons fire without ammo
	var letter := "k"
	if float(st.get("atk_energy", 0)) > 0: letter = "e"
	elif float(st.get("atk_explosive", 0)) > 0: letter = "x"
	# Only prompt if there's ammo of this type to choose; otherwise skip silently.
	var has_ammo := false
	for sym in GameData.RESOURCES:
		if String(GameState.ammo_bonus(sym)[0]) == letter and GameState.amount(sym) > 0:
			has_ammo = true
			break
	if not has_ammo:
		return
	_open_ammo_picker(key, md)

## Filled-slot menu: shows the equipped module + Unequip / Open Armory / Cancel.
func _open_slot_menu(idx: int, stype: String, equipped: String) -> void:
	var md: Dictionary = GameState.module_def(equipped)
	var body := func(v: VBoxContainer, close: Callable) -> void:
		var rcol: String = GameState.RARITY_COLOR.get(int(md.get("rarity", 0)), C_TEXT)
		_clbl(v, "%s slot" % GameData.SLOT_LABELS.get(stype, stype), 11, C_DIM)
		_clbl(v, md.get("name", equipped), 16, rcol)
		_inset(v, "STATS", _module_stat_lines(md.get("stats", {})), CYAN)
		_durability_row(v, equipped, close)
		for aid in md.get("affixes", {}):
			_clbl(v, _affix_text(aid, md["affixes"][aid]), 10, GameState.RARITY_COLOR.get(3, GOLD))
		var une := _card_button("Unequip", RED, true)
		une.custom_minimum_size = Vector2(0, 44)
		une.pressed.connect(func() -> void:
			GameState.unequip_slot(str(idx))
			close.call())
		v.add_child(une)
		var arm := _card_button("Open Armory  ›", CYAN, true)
		arm.custom_minimum_size = Vector2(0, 44)
		arm.pressed.connect(func() -> void:
			close.call()
			_open_slot_armory(idx, stype))
		v.add_child(arm)
	_modal("MANAGE SLOT", CYAN, body, "⬡")

## Generic centered modal. `body.call(content_vbox, close_callable)` fills it;
## a Cancel button + tap-outside both dismiss. Used by the slot-first equip flow.
# Branded modal header band (the _show_offline treatment, parameterized): accent-
# tinted bar pinned above the scroll area, big icon glyph + bold title.
func _modal_header(outer: VBoxContainer, title: String, accent: String, icon: String) -> void:
	var head := PanelContainer.new()
	var hsb := _bordered(_mix(accent, "0a1120", 0.84), _mix(accent, LINE, 0.45), 0, 12)
	hsb.corner_radius_bottom_left = 0
	hsb.corner_radius_bottom_right = 0
	hsb.content_margin_top = 15
	hsb.content_margin_bottom = 13
	head.add_theme_stylebox_override("panel", hsb)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 10)
	head.add_child(hb)
	if icon != "":
		var hicon := Label.new()
		hicon.text = icon
		hicon.add_theme_font_size_override("font_size", _fs(24))
		hicon.add_theme_color_override("font_color", Color.html(accent))
		hb.add_child(hicon)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", _fs(17))
	t.add_theme_color_override("font_color", Color.html(accent))
	_embolden(t)
	hb.add_child(t)
	outer.add_child(head)

func _modal(title: String, accent: String, body: Callable, icon := "", cancel_label := "Cancel") -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Above everything — the character-select overlay (z 50) and the combat hit-flash
	# (z 90). Without this a modal opened from the select screen renders behind it and
	# is unreachable (looks like a freeze on Rename / Create / Delete).
	overlay.z_index = 100
	add_child(overlay)
	_track_modal(overlay)
	var close := func() -> void:
		if is_instance_valid(overlay):
			overlay.queue_free()
	var scrim := Button.new()                 # tap outside the panel to dismiss
	scrim.flat = true
	scrim.focus_mode = Control.FOCUS_NONE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.pressed.connect(func() -> void: close.call())
	overlay.add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	# Lit gradient surface (art-pass parity). Content margins zeroed so the header
	# band sits flush against the panel's top edge. Fallback if the corner seam
	# reads badly on device: _bordered("121b2e", accent, 2, 16).
	var psb := _surface_style("121b2e", accent, true)
	psb.content_margin_left = 0
	psb.content_margin_right = 0
	psb.content_margin_top = 0
	psb.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", psb)
	panel.custom_minimum_size = Vector2(340, 0)
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	panel.add_child(outer)
	# Header band OUTSIDE the scroll — pinned; the old inline title scrolled away.
	_modal_header(outer, title, accent, icon)
	var sc := ScrollContainer.new()
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.custom_minimum_size = Vector2(0, mini(500, int(get_viewport_rect().size.y * 0.62)))
	outer.add_child(sc)
	var mc := MarginContainer.new()
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + s, 12)
	sc.add_child(mc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mc.add_child(v)
	body.call(v, close)
	var cancel := _card_button(cancel_label, C_MUTED, true)
	cancel.custom_minimum_size = Vector2(0, 42)
	cancel.pressed.connect(func() -> void: close.call())
	v.add_child(cancel)
	# Body pills (PanelContainers) default MOUSE_FILTER_STOP and would eat drag-
	# scroll; passthrough exempts Buttons/Sliders/LineEdits so controls still work.
	_scroll_passthrough(v)
	# Entry: quick scale/fade pop (node-bound — dies with the panel). Nodes are
	# live and tappable from frame 1; only modulate/scale animate.
	panel.resized.connect(func() -> void:
		if is_instance_valid(panel):
			panel.pivot_offset = panel.size / 2.0)
	panel.scale = Vector2(0.95, 0.95)
	panel.modulate.a = 0.0
	var tw := panel.create_tween().set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.15)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Owned-module detail modal: stats + Equip (into the targeted slot) + Cancel.
func _open_module_detail(mid: String) -> void:
	# The module name IS the header band, in its rarity colour.
	_modal(String(GameState.module_def(mid).get("name", mid)), rcol_for(mid), _module_detail_body.bind(mid), "▣")

# Durability readout (+ repair CTA when worn): amber at the 50% "destroyable"
# floor so the offline-loss risk is visible before it bites.
func _durability_row(v: VBoxContainer, mid: String, close_after_repair: Callable = Callable()) -> void:
	if not GameState.custom_modules.has(mid):
		return
	var dur := GameState.get_module_durability(mid)
	var col := GREEN if dur > 50 else C_WARN
	_clbl(v, "⛨ Durability %d%%%s" % [dur, "  — worn: at risk in offline combat" if dur <= 50 else ""], 10, col)
	if dur < 100:
		var cost := GameState.module_repair_cost(mid)
		var have := GameState.amount("SparePart") >= cost
		var rb := _card_button("Repair  (%d ⚙ Spare Parts)" % cost, GREEN if have else C_MUTED, have)
		rb.custom_minimum_size = Vector2(0, 40)
		if have:
			rb.pressed.connect(func() -> void:
				GameState.repair_module(mid)
				if close_after_repair.is_valid():
					close_after_repair.call()
				_refresh_current())
		v.add_child(rb)

# Per-stone action rows for the module dialog. Owned + applicable stones show a
# button with the Lira cost; Refit Bay / Anchor Bolt open an affix picker.
func _hack_stone_rows(v: VBoxContainer, mid: String, close: Callable) -> void:
	if not is_research_unlocked_safe("firmware_hacking"):
		return
	var any := false
	for stone in GameState.HACK_STONE_IDS:
		if GameState.amount(stone) < 1:
			continue
		var chk: Dictionary = GameState.can_apply_hack_stone(stone, mid)
		if not bool(chk.get("ok", false)):
			continue
		if not any:
			_section(v, "⚡ HACK CARDS", PURP)
			any = true
		# Typed capture FIRST: `stone` iterates an untyped const Array (Variant),
		# and any `:=` whose RHS involves a Variant (a bare capture, or an
		# operator expression like `stone in [...]`) is a hard Godot 4 compile
		# error — two of these shipped builds that wouldn't boot.
		var st: String = stone
		var needs_pick: bool = st in ["RefitBay", "AnchorBolt"]
		var label := "%s  (x%d)" % [GameData.res_name(st), GameState.amount(st)]
		var b := _card_button(label, PURP, true)
		b.add_theme_font_size_override("font_size", _fs(11))
		b.tooltip_text = String(GameState.HACK_STONE_DESC.get(st, ""))
		b.pressed.connect(func() -> void:
			if needs_pick:
				_open_affix_picker(st, mid, close)
			else:
				var r: Dictionary = GameState.apply_hack_stone(st, mid)
				_celebrate("⚡ " + GameData.res_name(st).to_upper() if r.get("ok", false) else "✕", String(r.get("msg", "")), PURP if r.get("ok", false) else RED)
				close.call()
				var cid := String(r.get("cid", ""))
				if cid != "" and GameState.custom_modules.has(cid):
					_open_module_detail(cid)
				else:
					_refresh_current())
		v.add_child(b)
		_lbl_wrap(v, String(GameState.HACK_STONE_DESC.get(stone, "")), 9, C_MUTED)

# Godot 4 name-collision-safe research check for the UI layer.
func is_research_unlocked_safe(rid: String) -> bool:
	return GameState.is_research_unlocked(rid)

# Pick an affix for Refit Bay (reroll target) / Anchor Bolt (lock-release target).
func _open_affix_picker(stone: String, mid: String, parent_close: Callable) -> void:
	var body := func(v: VBoxContainer, close: Callable) -> void:
		var md: Dictionary = GameState.module_def(mid)
		var anch: Array = GameState._anchored_array(md)
		for aid in md.get("affixes", {}):
			var a := String(aid)
			var locked: bool = anch.has(a)
			if stone == "RefitBay" and locked:
				continue   # can't refit a locked affix
			var lbl := ("🔓 Release: " if (stone == "AnchorBolt" and locked) else ("🔒 Lock: " if stone == "AnchorBolt" else "↻ Reroll: ")) + _affix_text(a, md["affixes"][a])
			var b := _card_button(lbl, PURP, true)
			b.add_theme_font_size_override("font_size", _fs(11))
			b.pressed.connect(func() -> void:
				var r: Dictionary = GameState.apply_hack_stone(stone, mid, a)
				_celebrate("⚡ " + GameData.res_name(stone).to_upper() if r.get("ok", false) else "✕", String(r.get("msg", "")), PURP if r.get("ok", false) else RED)
				close.call()
				if parent_close.is_valid():
					parent_close.call()
				var cid := String(r.get("cid", ""))
				if cid != "" and GameState.custom_modules.has(cid):
					_open_module_detail(cid)
				else:
					_refresh_current())
			v.add_child(b)
	_modal(GameData.res_name(stone).to_upper(), PURP, body, "⚡")

func _module_detail_body(v: VBoxContainer, close: Callable, mid: String) -> void:
	var md: Dictionary = GameState.module_def(mid)
	var rcol: String = GameState.RARITY_COLOR.get(int(md.get("rarity", 0)), C_TEXT)
	var rlabel: String = GameState.RARITY_LABEL.get(int(md.get("rarity", 0)), "")
	var sub := "%s  ·  owned x%d" % [GameData.SLOT_LABELS.get(md.get("slot", ""), ""), int(GameState.module_inventory.get(mid, 0))]
	if rlabel != "":
		sub = rlabel + "  ·  " + sub
	_clbl(v, sub, 10, rcol)
	_durability_row(v, mid, close)
	_inset(v, "STATS", _module_stat_lines(md.get("stats", {})), CYAN)
	var _anch: Array = GameState._anchored_array(md) if GameState.custom_modules.has(mid) else []
	var _ga: Array = md.get("greater_affixes", [])
	for aid in md.get("affixes", {}):
		var marks := ""
		if _anch.has(String(aid)):
			marks += "🔒 "
		if _ga.has(String(aid)):
			marks += "★ "
		_clbl(v, marks + _affix_text(aid, md["affixes"][aid]), 10, GameState.RARITY_COLOR.get(3, GOLD))
	# Hack-stone workbench: one action row per applicable stone (validated by
	# can_apply_hack_stone — buttons only appear when you own the stone and the
	# module qualifies). Affix-picker stones (Refit/Anchor) chain a second dialog.
	_hack_stone_rows(v, mid, close)
	# Set pieces: surface the set + its trinity bonus + equipped progress, so the
	# real payoff (the bonus at full set) is visible (desktop "(Set) [x/3]" intent).
	var set_id: String = md.get("set", "")
	if set_id != "" and GameData.SETS.has(set_id):
		var sd: Dictionary = GameData.SETS[set_id]
		var have := int(GameState.equipped_set_counts().get(set_id, 0))
		var bonus: Dictionary = GameData.TRINITY_SET_BONUSES.get(set_id, {})
		var pieces := int(bonus.get("pieces", 3))
		var blines := []
		for k in bonus:
			if k == "name" or k == "pieces":
				continue
			blines.append(_line(_trinity_bonus_label(k, float(bonus[k])), GREEN if have >= pieces else C_MUTED))
		_inset(v, "✦ SET: %s  (%d/%d equipped)" % [sd.get("name", set_id), have, pieces], blines, PURP)
	# Custom (rolled) modules: keep their sockets + sell reachable from the detail.
	if GameState.custom_modules.has(mid):
		var sockets: Array = md.get("sockets", [])
		if sockets.size() > 0:
			var slines := []
			for gid in sockets:
				slines.append(_line(("◆ " + GameData.GEMS.get(gid, {}).get("name", gid)) if (gid != null and gid != "") else "◇ empty socket", "3a9fff" if (gid != null and gid != "") else C_MUTED))
			_inset(v, "SOCKETS", slines, "3a9fff")
			var has_empty := false
			for gid in sockets:
				if gid == null or gid == "":
					has_empty = true
			if has_empty:
				for gem in GameData.GEMS:
					if GameState.amount(gem) > 0:
						var gb := _card_button("Socket %s x%d" % [GameData.GEMS[gem]["name"], GameState.amount(gem)], "3a9fff", true)
						gb.add_theme_font_size_override("font_size", _fs(11))
						gb.pressed.connect(_socket_and_reopen.bind(mid, gem, close))
						v.add_child(gb)
			for i in sockets.size():
				if sockets[i] != null and sockets[i] != "":
					var rb := _card_button("Remove " + GameData.GEMS.get(sockets[i], {}).get("name", sockets[i]), C_MUTED, true)
					rb.add_theme_font_size_override("font_size", _fs(11))
					rb.pressed.connect(_unsocket_and_reopen.bind(mid, i, close))
					v.add_child(rb)
	var note := Label.new()                      # inline error slot (grid overload, etc.)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", _fs(11))
	note.add_theme_color_override("font_color", Color.html(RED))
	note.visible = false
	# Equip ABOVE Sell — the top button is where the habitual tap lands, and
	# equipping is reversible while selling is not (mis-sell guard below).
	var eq := _card_button("Equip", GREEN, true)
	eq.custom_minimum_size = Vector2(0, 46)
	eq.pressed.connect(_do_equip.bind(mid, close, note))
	v.add_child(eq)
	v.add_child(note)
	if GameState.custom_modules.has(mid):
		if not GameState._anchored_array(md).is_empty():
			_clbl(v, "⚠ This module has anchored affixes — selling loses the locks.", 9, C_WARN)
		v.add_child(_guarded_sell_button(GameState._module_sell_price(mid, int(md.get("rarity", 0))), _sell_and_close.bind(mid, close)))

func _do_equip(mid: String, close: Callable, note: Label) -> void:
	# Slot-first flow (opened from a specific slot): equip straight into it.
	if ship_target_slot >= 0:
		if GameState.equip_module_to_slot(ship_target_slot, mid):
			var eq_idx := ship_target_slot
			close.call()
			ship_target_slot = -1
			ship_view = "loadout"
			_refresh_current()
			_prompt_ammo_if_needed(eq_idx)
		elif is_instance_valid(note):
			note.text = "⚠ " + (GameState.equip_notice if GameState.equip_notice != "" else "Can't equip here.")
			note.visible = true
		return
	# Browse flow: the hull may have several slots of this type. With more than one,
	# let the player choose which slot to fill or replace (instead of silently
	# filling the first empty one, or doing nothing when they're all full).
	var stype: String = GameState.module_def(mid).get("slot", "")
	var idxs := _hull_slot_indices(stype)
	if idxs.is_empty():
		if is_instance_valid(note):
			note.text = "⚠ This hull has no %s slot." % GameData.SLOT_LABELS.get(stype, stype)
			note.visible = true
		return
	if idxs.size() == 1:
		if GameState.equip_module_to_slot(int(idxs[0]), mid):
			close.call()
			ship_view = "loadout"
			_refresh_current()
			_prompt_ammo_if_needed(int(idxs[0]))
		elif is_instance_valid(note):
			note.text = "⚠ " + (GameState.equip_notice if GameState.equip_notice != "" else "Can't equip here.")
			note.visible = true
		return
	close.call()
	_open_equip_slot_picker(mid, idxs)

# Hull slot indices that accept a given module slot type.
func _hull_slot_indices(stype: String) -> Array:
	var out := []
	var slots: Array = GameData.HULLS.get(GameState.active_hull, {}).get("slots", [])
	for i in slots.size():
		if slots[i] == stype:
			out.append(i)
	return out

# Pick which of several same-type slots to equip a module into (shows each slot's
# current occupant; selecting swaps it in).
func _open_equip_slot_picker(mid: String, idxs: Array) -> void:
	var stype: String = GameState.module_def(mid).get("slot", "")
	var body := func(v: VBoxContainer, close: Callable) -> void:
		_clbl(v, "Equip to which %s slot?" % GameData.SLOT_LABELS.get(stype, stype), 11, C_DIM)
		var note := Label.new()
		note.add_theme_font_size_override("font_size", _fs(11))
		note.add_theme_color_override("font_color", Color.html(RED))
		note.visible = false
		var n := 1
		for raw in idxs:
			var idx: int = int(raw)
			var occ: String = GameState.loadout.get(str(idx), "")
			var occ_name: String = "Empty" if occ == "" else String(GameState.module_def(occ).get("name", occ))
			var b := _card_button("Slot %d  ·  %s" % [n, occ_name], CYAN if occ == "" else GOLD, true)
			b.custom_minimum_size = Vector2(0, 46)
			b.pressed.connect(func() -> void:
				if GameState.equip_module_to_slot(idx, mid):
					close.call()
					ship_view = "loadout"
					_refresh_current()
					_prompt_ammo_if_needed(idx)
				elif is_instance_valid(note):
					note.text = "⚠ " + (GameState.equip_notice if GameState.equip_notice != "" else "Can't equip here.")
					note.visible = true)
			v.add_child(b)
			n += 1
		v.add_child(note)
	_modal("EQUIP TO SLOT", CYAN, body, "⬡")

func _socket_and_reopen(mid: String, gem: String, close: Callable) -> void:
	GameState.socket_gem(mid, gem)
	close.call()
	_open_module_detail(mid)

func _unsocket_and_reopen(mid: String, idx: int, close: Callable) -> void:
	GameState.unsocket_gem(mid, idx)
	close.call()
	_open_module_detail(mid)

func _sell_and_close(mid: String, close: Callable) -> void:
	GameState.sell_module(mid)
	close.call()
	_refresh_current()

# Mis-sell guard: selling a module is irreversible, so the Sell button is a
# two-tap confirm — the first tap ARMS it ("⚠ Tap again"), a second tap within
# 2.5s sells, and it quietly disarms back to the plain label otherwise.
func _guarded_sell_button(price: int, on_sell: Callable) -> Button:
	var label := "Sell ₡%s" % GameData.fmt(price)
	var b := _card_button(label, GOLD, true)
	var armed := {"on": false}
	b.pressed.connect(func() -> void:
		if armed["on"]:
			on_sell.call()
			return
		armed["on"] = true
		b.text = "⚠ Tap again to sell"
		get_tree().create_timer(2.5).timeout.connect(func() -> void:
			if is_instance_valid(b) and armed["on"]:
				armed["on"] = false
				b.text = label))
	return b

func rcol_for(mid: String) -> String:
	return GameState.RARITY_COLOR.get(int(GameState.module_def(mid).get("rarity", 0)), CYAN)

# 3 saved-build preset slots wired to the Phase-7 engine API. Save snapshots the
# current loadout/ammo/consumables; Load swaps to it; Clear empties the slot.
func _loadout_presets(v: VBoxContainer) -> void:
	_section(v, "LOADOUT PRESETS — save & swap builds", CYAN)
	for i in [1, 2, 3]:
		var preset: Dictionary = GameState.loadout_presets.get(i, {})
		var empty := GameState.is_loadout_preset_empty(i)
		var nm: String = preset.get("name", "")
		if nm == "":
			nm = "Build %d" % i
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _bordered("16243a", "2a3a55", 1))
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 4)
		panel.add_child(vb)
		var head := Label.new()
		head.text = "Slot %d:  %s" % [i, nm if not empty else "— empty —"]
		head.add_theme_font_size_override("font_size", _fs(13))
		head.add_theme_color_override("font_color", Color.html(CYAN if not empty else C_MUTED))
		vb.add_child(head)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var save := _card_button("Save", CYAN, true)
		save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		save.pressed.connect(func() -> void:
			GameState.save_loadout_preset(i)
			_refresh_current())
		row.add_child(save)
		var load := _card_button("Load", GREEN, not empty)
		load.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not empty:
			load.pressed.connect(func() -> void:
				GameState.load_loadout_preset(i)
				_refresh_current())
		row.add_child(load)
		var clear := _card_button("Clear", C_WARN, not empty)
		clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not empty:
			clear.pressed.connect(func() -> void:
				GameState.clear_loadout_preset(i)
				_refresh_current())
		row.add_child(clear)
		vb.add_child(row)
		v.add_child(panel)

# Slot filter strip shared by the Shipyard's Module Shop and the Armory.
func _ship_slot_tabs(v: VBoxContainer) -> void:
	var slot_items := []
	for st in ["weapon", "shield", "armor", "battery", "engine", "sensor", "cooling"]:
		slot_items.append({"id": st, "label": GameData.SLOT_LABELS.get(st, st)})
	_subtabs(v, slot_items, ship_mod_slot, CYAN, func(id: String) -> void:
		ship_mod_slot = id
		_refresh_current())

# Live energy grid readout (load / capacity) — shown atop Armory + Module Shop.
func _grid_readout(v: VBoxContainer) -> void:
	var ss := GameState.ship_stats()
	if ss.is_empty():
		return
	var grid := Label.new()
	var load := int(ss.get("energy_load", 0.0))
	var cap := int(ss.get("energy_cap", 0.0))
	grid.text = "⚡ Grid load %d / %d" % [load, cap]
	grid.add_theme_font_size_override("font_size", _fs(11))
	grid.add_theme_color_override("font_color", Color.html(RED if load > cap else C_DIM))
	v.add_child(grid)

# A "power" score for sorting the Armory: prefer an explicit power if one ever
# exists, else sum the module's combat-relevant base stats (faithful order).
func _module_power(stats: Dictionary) -> float:
	var p := 0.0
	for k in stats:
		if k == "atk_interval":
			continue   # lower is better — skip so it doesn't invert the sort
		p += abs(float(stats[k]))
	return p

# Resolve an owned module's display fields whether it's a rolled custom instance
# or a plain base module from MODULES.
func _owned_module_def(mid: String) -> Dictionary:
	if GameState.custom_modules.has(mid):
		return GameState.custom_modules[mid]
	return GameData.MODULES.get(mid, {})

# The zone (difficulty) a module belongs to. Custom rolls/set pieces carry it on
# their base module, so resolve through "base" when the instance lacks it.
func _module_zone(mid: String) -> int:
	var d := _owned_module_def(mid)
	var z := int(d.get("zone", 0))
	if z > 0:
		return z
	var base := String(d.get("base", ""))
	if GameData.MODULES.has(base):
		return int(GameData.MODULES[base].get("zone", 0))
	if GameData.SET_MODULES.has(base):
		return int(GameData.SET_MODULES[base].get("zone", 0))
	return 0

# Original zone display name for a difficulty number (e.g. 2 -> "Asteroid Belt").
func _zone_name(z: int) -> String:
	for zd in GameData.ZONES:
		if int(zd.get("difficulty", -1)) == z:
			return String(zd.get("name", "Zone %d" % z))
	return "Zone %d" % z

# ====================================================== SHIP DESIGNER · ARMORY
# Your owned/unequipped module pool. Tap a card to equip it (GameState.equip_module).
# Sortable by Power / Zone / Rarity to mirror the desktop designer's armory.
# Bulk-sell "scrap junk" controls — the answer to a crowded Armory. Sells every
# UNEQUIPPED module at or below a chosen rarity (across ALL slots, not just the
# open tab), with a confirm dialog. Pairs with the loot filter (stops the clutter)
# and sort (organises what's left).
func _armory_scrap_row(v: VBoxContainer) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	var any := false
	for spec in [["Commons", 0], ["≤ Uncommon", 1], ["≤ Rare", 2]]:
		var maxr: int = int(spec[1])
		var cnt: int = GameState.count_bulk_sell(maxr)
		if cnt <= 0:
			continue
		any = true
		var b := _card_button("Scrap %s (%d)" % [String(spec[0]), cnt], GOLD, true)
		b.add_theme_font_size_override("font_size", _fs(10))
		b.pressed.connect(_confirm_scrap.bind(maxr, String(spec[0])))
		row.add_child(b)
	if any:
		v.add_child(row)

func _confirm_scrap(max_rarity: int, label: String) -> void:
	var cnt := GameState.count_bulk_sell(max_rarity)
	if cnt <= 0:
		return
	var body := func(mv: VBoxContainer, close: Callable) -> void:
		_clbl(mv, "Sell %d unequipped %s module%s for credits + spare parts?" % [cnt, label, "" if cnt == 1 else "s"], 12, C_TEXT)
		_clbl(mv, "Equipped gear is never sold.", 10, C_DIM)
		var go := _card_button("Sell %d" % cnt, GOLD, true)
		go.custom_minimum_size = Vector2(0, 44)
		go.pressed.connect(func() -> void:
			var sold := GameState.bulk_sell_by_rarity(max_rarity)
			close.call()
			_refresh_current()
			GameState.equip_notice = "Scrapped %d module%s." % [sold, "" if sold == 1 else "s"])
		mv.add_child(go)
	_modal("SCRAP JUNK", GOLD, body, "⚠")

# v135a legibility: a neutral "trophy cabinet" of Unique-Set completion (X/3
# pieces owned). Gold at 3/3, normal while collecting, muted at 0/3. No zone or
# weak-type hint — the player self-discovers sets via drops.
func _unique_sets_panel(v: VBoxContainer) -> void:
	var counts: Dictionary = GameState.owned_set_counts()
	var ids: Array = GameData.SETS.keys()
	ids.sort()
	_section(v, "✦ UNIQUE SETS  ·  collection", PURP)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	for sid in ids:
		var total: int = (GameData.SETS[sid].get("pieces", []) as Array).size()
		var have := int(counts.get(sid, 0))
		var col: String = GOLD if (total > 0 and have >= total) else (C_TEXT if have > 0 else C_MUTED)
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", _card_style(_mix(col, SURFACE, 0.85), _mix(col, LINE, 0.4), 1, false))
		var lbl := Label.new()
		lbl.text = "  %s  %d/%d  " % [GameData.SETS[sid].get("name", sid), have, total]
		lbl.add_theme_font_size_override("font_size", _fs(10))
		lbl.add_theme_color_override("font_color", Color.html(col))
		chip.add_child(lbl)
		flow.add_child(chip)
	v.add_child(flow)

func _ship_armory(v: VBoxContainer) -> void:
	if GameState.equip_notice != "":
		var warn := Label.new()
		warn.text = "⚠ " + GameState.equip_notice
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.add_theme_font_size_override("font_size", _fs(11))
		warn.add_theme_color_override("font_color", Color.html(RED))
		v.add_child(warn)
	_grid_readout(v)
	if ship_target_slot >= 0:
		# Slot-first flow: the slot is fixed; show what we're fitting + a way back.
		_section(v, "FITTING  %s  SLOT" % GameData.SLOT_LABELS.get(ship_mod_slot, ship_mod_slot).to_upper(), GREEN)
		var back := _card_button("‹ Back to slots", C_MUTED, true)
		back.pressed.connect(func() -> void:
			ship_target_slot = -1
			ship_view = "loadout"
			_refresh_current())
		v.add_child(back)
	else:
		# Browse mode (opened via the Armory tab): pick a slot type to view.
		_unique_sets_panel(v)
		_ship_slot_tabs(v)
	# Collect every owned module for this slot: rolled customs + base modules.
	# The aux slot (CMB_3) fits any standard module type, so it lists everything
	# except cores.
	var aux_browse := ship_mod_slot == "aux"
	var slot_ok := func(sl: String) -> bool:
		return GameState._aux_accepts(sl) if aux_browse else sl == ship_mod_slot
	var owned := []
	for cid in GameState.custom_modules:
		if slot_ok.call(String(GameState.custom_modules[cid].get("slot", ""))) and int(GameState.module_inventory.get(cid, 0)) > 0:
			owned.append(cid)
	for mid in GameData.MODULES:
		if slot_ok.call(String(GameData.MODULES[mid].get("slot", ""))) and int(GameState.module_inventory.get(mid, 0)) > 0:
			owned.append(mid)
	# Zones represented in the owned gear. You only own gear from zones you've
	# played, so these are inherently unlocked — no locked-zone spoilers, and no
	# empty sections. Drives the optional secondary zone filter.
	var zones_present := {}
	for mid in owned:
		var mz := _module_zone(mid)
		if mz > 0:
			zones_present[mz] = true
	if armory_zone != 0 and not zones_present.has(armory_zone):
		armory_zone = 0   # selection no longer valid (e.g. slot changed)
	# Sort control (matches desktop armory_sort_mode).
	_subtabs(v, [{"id": "power", "label": "Power"}, {"id": "zone", "label": "Zone"}, {"id": "rarity", "label": "Rarity"}], armory_sort, PURP, func(id: String) -> void:
		armory_sort = id
		_refresh_current())
	# Secondary filter: narrow to one zone's gear (only zones you own gear from,
	# by their real names). Shown only when there's more than one to choose.
	if zones_present.size() > 1:
		var zkeys := zones_present.keys()
		zkeys.sort()
		var zitems := [{"id": "0", "label": "All Zones"}]
		for z in zkeys:
			zitems.append({"id": str(z), "label": _zone_name(z)})
		_subtabs(v, zitems, str(armory_zone), CYAN, func(id: String) -> void:
			armory_zone = int(id)
			_refresh_current())
	_armory_scrap_row(v)
	# Apply the zone filter.
	if armory_zone != 0:
		var filtered := []
		for mid in owned:
			if _module_zone(mid) == armory_zone:
				filtered.append(mid)
		owned = filtered
	if owned.is_empty():
		_section(v, "Armory — owned gear", PURP)
		_empty(v, "No gear yet — craft modules in the Shipyard or defeat enemies for drops.")
		return
	# Stable sort by the chosen key (descending power/rarity, ascending zone).
	owned.sort_custom(func(a: String, b: String) -> bool:
		var da := _owned_module_def(a)
		var db := _owned_module_def(b)
		match armory_sort:
			"rarity":
				return int(da.get("rarity", 0)) > int(db.get("rarity", 0))
			"zone":
				return _module_zone(a) < _module_zone(b)
			_:
				return _module_power(da.get("stats", {})) > _module_power(db.get("stats", {}))
		)
	# Cap rendered tiles — a heavy farm can own thousands of modules and building a
	# card for each froze the page. Show the top ARMORY_MAX (after sorting) and note
	# the rest; sort/scrap narrow it down.
	var total := owned.size()
	if total > ARMORY_MAX:
		owned = owned.slice(0, ARMORY_MAX)
	_section(v, "Armory — tap a module for details", PURP)
	var ig := _grid(v)
	for mid in owned:
		ig.add_child(_armory_tile(mid))
	if total > ARMORY_MAX:
		_clbl(v, "Showing %d of %d — sort or scrap to narrow." % [ARMORY_MAX, total], 10, C_DIM)

## Compact owned-module tile: name (rarity color) + key stats; tap → detail modal
## (stats + Equip/Cancel). The detail equips into ship_target_slot when set.
func _armory_tile(mid: String) -> Control:
	var md: Dictionary = _owned_module_def(mid)
	var rcol: String = GameState.RARITY_COLOR.get(int(md.get("rarity", 0)), CYAN)
	var owned := int(GameState.module_inventory.get(mid, 0))
	var c := _card(rcol, true)
	c.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.get_parent().set_meta("coach_id", mid)
	_card_head(c, "▣", md.get("name", mid), ("x%d" % owned) if owned > 1 else "", rcol, true)
	_inset(c, "STATS", _module_stat_lines(md.get("stats", {})), CYAN)
	_clbl(c, "tap for details ›", 9, "5d6b88")
	var tap := Button.new()
	tap.flat = true
	tap.focus_mode = Control.FOCUS_NONE
	tap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tap.pressed.connect(func() -> void: _open_module_detail(mid))
	c.get_parent().add_child(tap)
	return c.get_parent()

# A single owned-module card with stats + rarity color + TAP-to-equip. Rolled
# customs reuse the full _custom_module_card (sockets/affixes/sell); plain base
# modules get a compact equip card here.
func _armory_card(mid: String) -> Control:
	if GameState.custom_modules.has(mid):
		return _custom_module_card(mid)
	var m: Dictionary = GameData.MODULES.get(mid, {})
	var owned := int(GameState.module_inventory.get(mid, 0))
	var c := _card(CYAN, true)
	c.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.get_parent().set_meta("coach_id", mid)
	_card_head(c, "▣", m.get("name", mid), ("x%d" % owned) if owned > 1 else "", CYAN, true)
	_inset(c, "STATS", _module_stat_lines(m.get("stats", {})), CYAN)
	var eq := _card_button("Equip", CYAN, true)
	eq.pressed.connect(func() -> void: _equip_from_shop(mid))
	c.add_child(eq)
	return c.get_parent()

# ====================================================== SHIPYARD · MODULE SHOP
# Fabrication: craft/buy new modules. The owned pool moved to the Designer's Armory.
func _shipyard_modules(v: VBoxContainer) -> void:
	if GameState.equip_notice != "":
		var warn := Label.new()
		warn.text = "⚠ " + GameState.equip_notice
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.add_theme_font_size_override("font_size", _fs(11))
		warn.add_theme_color_override("font_color", Color.html(RED))
		v.add_child(warn)
	_grid_readout(v)
	_ship_slot_tabs(v)
	# Secondary zone filter — only zones you've UNLOCKED are offered, by their real
	# names, so the chip row never spoils how many zones lie ahead. "All Zones" keeps
	# the shop's normal forward preview.
	var unlocked_zones := []
	for z in GameData.ZONES:
		if _zone_unlocked(z):
			unlocked_zones.append(int(z.get("difficulty", 0)))
	unlocked_zones.sort()
	if shipyard_zone != 0 and not (shipyard_zone in unlocked_zones):
		shipyard_zone = 0
	if unlocked_zones.size() > 1:
		var zitems := [{"id": "0", "label": "All Zones"}]
		for z in unlocked_zones:
			zitems.append({"id": str(z), "label": _zone_name(z)})
		_subtabs(v, zitems, str(shipyard_zone), CYAN, func(id: String) -> void:
			shipyard_zone = int(id)
			_refresh_current())
	_section(v, "Module Shop", CYAN)
	var g := _grid(v)
	var any := false
	for mid in GameData.MODULES:
		var m: Dictionary = GameData.MODULES[mid]
		if m.get("slot", "") != ship_mod_slot:
			continue
		if shipyard_zone != 0 and _module_zone(mid) != shipyard_zone:
			continue
		any = true
		g.add_child(_module_card(mid, m))
	if not any:
		_empty(v, "No modules in this zone for this slot.")

func _custom_module_card(cid: String) -> Control:
	var md: Dictionary = GameState.custom_modules[cid]
	var rcol: String = GameState.RARITY_COLOR.get(int(md.get("rarity", 0)), C_TEXT)
	var owned := int(GameState.module_inventory.get(cid, 0))
	var c := _card(rcol, true)
	c.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card_head(c, "◆", md.get("name", cid), ("x%d" % owned) if owned > 1 else "", rcol, true)
	_inset(c, "STATS", _module_stat_lines(md.get("stats", {})), rcol)
	if not md.get("affixes", {}).is_empty():
		var alines := []
		for aid in md["affixes"]:
			alines.append(_line(_affix_text(aid, md["affixes"][aid]), rcol))
		_inset(c, "AFFIXES", alines, rcol, true)
	# Gem sockets
	var sockets: Array = md.get("sockets", [])
	if sockets.size() > 0:
		var slines := []
		var has_empty := false
		for i in sockets.size():
			var gid = sockets[i]
			if gid != null and gid != "":
				slines.append(_line("◆ " + GameData.GEMS.get(gid, {}).get("name", gid), "3a9fff"))
			else:
				slines.append(_line("◇ empty socket", C_MUTED))
				has_empty = true
		_inset(c, "SOCKETS", slines, "3a9fff")
		if has_empty:
			for gem in GameData.GEMS:
				if GameState.amount(gem) > 0:
					var gb := _card_button("Socket %s x%d" % [GameData.GEMS[gem]["name"], GameState.amount(gem)], "3a9fff", true)
					gb.add_theme_font_size_override("font_size", _fs(11))
					gb.pressed.connect(func() -> void: GameState.socket_gem(cid, gem))
					c.add_child(gb)
		for i in sockets.size():
			var gid2 = sockets[i]
			if gid2 != null and gid2 != "":
				var idx := i
				var rb := _card_button("Remove " + GameData.GEMS.get(gid2, {}).get("name", gid2), C_MUTED, true)
				rb.add_theme_font_size_override("font_size", _fs(11))
				rb.pressed.connect(func() -> void: GameState.unsocket_gem(cid, idx))
				c.add_child(rb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var eq := _card_button("Equip", CYAN, true)
	eq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eq.pressed.connect(func() -> void: _equip_from_shop(cid))
	row.add_child(eq)
	var sell := _guarded_sell_button(GameState.RARITY_SELL.get(int(md.get("rarity", 0)), 100), func() -> void:
		GameState.sell_module(cid)
		_refresh_current())
	sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sell)
	c.add_child(row)
	return c.get_parent()

func _affix_text(aid: String, val: float) -> String:
	var cfg: Dictionary = GameState.AFFIX_DB.get(aid, {})
	var d: String = cfg.get("desc", aid)
	if "%d%%" in d:
		return "◆ " + (d % int(round(val * 100.0)))
	return "◆ " + cfg.get("name", aid)

func _module_card(mid: String, m: Dictionary) -> Control:
	var unlocked := GameState.module_unlocked(mid)
	var owned := int(GameState.module_inventory.get(mid, 0))
	var c := _card(CYAN, unlocked)
	c.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.get_parent().set_meta("coach_id", mid)
	_card_head(c, "▣", m.get("name", mid), ("x%d" % owned) if owned > 0 else "", CYAN, unlocked)
	if not unlocked:
		_locked(c, m, "combat")
		return c.get_parent()
	_inset(c, "STATS", _module_stat_lines(m.get("stats", {})), CYAN)
	var mfill := Control.new()
	mfill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.add_child(mfill)
	var cost_lines := []
	var eff_cost := GameState.effective_module_cost(mid)   # v114: zone alloy injected when gated
	for sym in eff_cost:
		var have: bool = GameState.credits >= int(eff_cost[sym]) if sym == "credits" else GameState.amount(sym) >= int(eff_cost[sym])
		var label := "₡%s" % GameData.fmt(eff_cost[sym]) if sym == "credits" else "%s %s" % [GameData.fmt(eff_cost[sym]), GameData.res_name(sym)]
		cost_lines.append(_line(label, GREEN if have else C_WARN, "" if sym == "credits" else String(sym)))
	_inset(c, "COST", cost_lines, CYAN)
	if owned > 0:
		var eq := _card_button("Equip", CYAN, true)
		eq.pressed.connect(func() -> void: _equip_from_shop(mid))
		c.add_child(eq)
	var buy := _card_button("Buy", GOLD, GameState.module_can_buy(mid))
	if GameState.module_can_buy(mid):
		buy.pressed.connect(func() -> void:
			GameState.buy_module(mid)
			_refresh_current())
	c.add_child(buy)
	return c.get_parent()

func _ship_hulls(v: VBoxContainer) -> void:
	_section(v, "HULLS", CYAN)
	var g := _grid(v)
	for hid in GameData.HULLS:
		g.add_child(_hull_card(hid, GameData.HULLS[hid]))

func _hull_card(hid: String, h: Dictionary) -> Control:
	var unlocked := GameState.hull_unlocked(hid)
	var owned := GameState.hull_owned(hid)
	var active: bool = GameState.active_hull == hid
	var c := _card(CYAN, unlocked or owned)
	c.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.get_parent().set_meta("coach_id", hid)
	_card_head(c, "⛭", h.get("name", hid), "T%d" % int(h.get("tier", 0)), CYAN, unlocked)
	if not unlocked:
		_locked(c, h, "combat")
		return c.get_parent()
	_inset(c, "HULL", [
		_line("HP %s" % GameData.fmt(h.get("hp", 0)), C_TEXT),
		_line("ATK %d" % int(h.get("atk", 0)), C_WARN),
		_line("%d slots" % (h.get("slots", []) as Array).size(), C_DIM),
	], CYAN)
	var hfill := Control.new()
	hfill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.add_child(hfill)
	if active:
		c.add_child(_card_button("ACTIVE", C_MUTED, false))
	elif owned:
		var sw := _card_button("Switch", CYAN, true)
		sw.pressed.connect(func() -> void:
			GameState.select_hull(hid)
			_refresh_current())
		c.add_child(sw)
	else:
		var cost_lines := []
		for sym in h.get("cost", {}):
			var have: bool = GameState.credits >= int(h["cost"][sym]) if sym == "credits" else GameState.amount(sym) >= int(h["cost"][sym])
			var label := "₡%s" % GameData.fmt(h["cost"][sym]) if sym == "credits" else "%s %s" % [GameData.fmt(h["cost"][sym]), GameData.res_name(sym)]
			cost_lines.append(_line(label, GREEN if have else C_WARN))
		if not cost_lines.is_empty():
			_inset(c, "COST", cost_lines, CYAN)
		var b := _card_button("Build", GOLD, GameState.hull_can_get(hid))
		if GameState.hull_can_get(hid):
			b.pressed.connect(func() -> void:
				GameState.select_hull(hid)
				_refresh_current())
		c.add_child(b)
	return c.get_parent()

func _module_stat_lines(stats: Dictionary) -> Array:
	var labels := {
		"atk_energy": "Energy Dmg", "atk_kinetic": "Kinetic Dmg", "atk_explosive": "Explosive Dmg",
		"atk_interval": "Interval", "energy_load": "Energy Use", "energy_capacity": "Energy Cap",
		"hp": "Hull HP", "def": "Armor", "max_shield": "Shield", "shield_regen": "Shield Regen",
		"shield_regen_mult": "Regen x", "atk_speed_bonus": "Fire Rate +", "atk_speed_mult": "Fire Rate x",
		"accuracy": "Accuracy", "crit_chance": "Crit", "eva": "Evasion", "jamming_strength": "Jamming",
	}
	var lines := []
	for k in stats:
		var v = stats[k]
		var txt: String
		if k == "atk_interval":
			txt = "%s %.1fs" % [labels.get(k, k), float(v)]
		elif k == "eva":
			# Evasion is a FLAT stat (dodge = eva/(eva+k)), not a percentage — show
			# the raw points, trimmed to a decimal only when fractional.
			var ev := float(v)
			txt = "%s %s" % [labels.get(k, k), ("%.0f" % ev) if ev == floor(ev) else ("%.1f" % ev)]
		elif k in ["atk_speed_bonus", "crit_chance"]:
			txt = "%s %d%%" % [labels.get(k, k), int(float(v) * 100.0)]
		else:
			txt = "%s %s" % [labels.get(k, k), str(v)]
		lines.append(_line(txt, C_TEXT))
	return lines

# ============================================================ RESEARCH
# Faithful port of the desktop research_page graph: per-discipline tabs, each a
# 2D canvas of positioned nodes with parent→child branch lines drawn between them.
const RES_NODE_W := 200.0
const RES_NODE_H := 104.0
# RESEARCH_GRAPHS positions are generated in mobile pixels (desktop tree
# layout with node-sized slots baked in), so no axis stretching is needed.
const RES_SX := 1.0
const RES_SY := 1.0
const RES_PAD := 12.0

func _build_research() -> void:
	var v := _clear("research")
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "RESEARCH NETWORK"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.add_theme_font_size_override("font_size", _fs(16))
	title.add_theme_color_override("font_color", Color.html(PURP))
	head.add_child(title)
	var cr := Label.new()
	cr.text = "₡%s" % GameData.fmt(GameState.credits)
	cr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cr.add_theme_font_size_override("font_size", _fs(13))
	cr.add_theme_color_override("font_color", Color.html(GOLD))
	head.add_child(cr)
	v.add_child(head)

	var tabs: Array = GameData.RESEARCH_TABS.duplicate()
	tabs.append("Recursion")
	if not tabs.has(research_tab):
		research_tab = tabs[0]
	var tab_items := []
	for t in tabs:
		tab_items.append({"id": t, "label": t})
	_subtabs(v, tab_items, research_tab, PURP, func(id: String) -> void:
		research_tab = id
		_refresh_current())

	if research_tab == "Recursion":
		_build_recursion(v)
		return

	var graph: Dictionary = GameData.RESEARCH_GRAPHS[research_tab]
	var pos: Dictionary = graph["pos"]
	var nodes: Array = graph["nodes"]
	var maxx := 0.0
	var maxy := 0.0
	for nid in pos:
		var p: Vector2 = pos[nid]
		maxx = maxf(maxx, p.x)
		maxy = maxf(maxy, p.y)
	# Node names are capped to 2 lines (below), so RES_NODE_H bounds every node;
	# extra slack guarantees edge nodes pan fully into view.
	var cw: float = maxx * RES_SX + RES_NODE_W + RES_PAD * 4.0
	var ch: float = maxy * RES_SY + RES_NODE_H + RES_PAD * 4.0

	# One both-axis scroller pans the wide/tall tree in 2D (desktop parity). The
	# page's own vertical scroll is disabled for this page so the two scrollers
	# don't compete for the same drag — that was blocking all movement.
	pages["research"].vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var hs := ScrollContainer.new()
	hs.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Size the scroller to the VISIBLE page area (a disabled outer scroll sizes its
	# child to min, not the viewport). It must NOT exceed the visible height, or the
	# scroller overflows below the screen and its lower nodes become unreachable
	# (the page's own vertical scroll is off). Use a logical fallback — never the
	# physical viewport — then correct to the real size on layout/resize.
	_research_hs = hs
	var avail: float = pages["research"].size.y
	if avail < 200.0:
		avail = 820.0   # logical page height fallback (header+banners+nav chrome)
	hs.custom_minimum_size = Vector2(0, maxf(300.0, avail - 112.0))
	# Correct to the real page height next frame (size is often stale at build time).
	call_deferred("_size_research_scroller")
	# Fit the tree to the screen WIDTH so right-edge nodes don't hang off the
	# visible area (the original complaint: the tree drifts outside the view).
	# Scale down only — never enlarge — with a floor so deep trees stay legible;
	# anything past the floor still pans horizontally. Vertical panning is kept.
	var avail_w: float = pages["research"].size.x
	if avail_w < 100.0:
		avail_w = 720.0 - RES_PAD * 2.0
	var fit: float = clampf(avail_w / cw, 0.62, 1.0)
	# Base auto-fit, then the user's pinch zoom on top. Stored so pinch / +- can
	# rescale live without a rebuild.
	_research_base_fit = fit
	_res_cw = cw
	_res_ch = ch
	var eff: float = fit * _research_zoom
	var canvas := Control.new()
	canvas.custom_minimum_size = Vector2(cw, ch)
	canvas.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	canvas.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	canvas.scale = Vector2(eff, eff)
	canvas.draw.connect(_draw_research_branches.bind(canvas, nodes, pos))
	_research_canvas = canvas
	for nid in nodes:
		if not GameData.RESEARCH.has(nid):
			continue
		var node := _research_node(nid)
		var np: Vector2 = pos[nid]
		node.position = Vector2(np.x * RES_SX + RES_PAD, np.y * RES_SY + RES_PAD)
		node.size = Vector2(RES_NODE_W, RES_NODE_H)
		canvas.add_child(node)
	# A plain frame carries the SCALED footprint so the scroller measures the
	# fitted size (a child's `scale` doesn't change its combined minimum size).
	# Add a fixed (unscaled) bottom pad so the last row can scroll up clear of the
	# screen edge / system nav bar instead of resting under it at max scroll.
	var frame := Control.new()
	frame.custom_minimum_size = Vector2(cw * eff, ch * eff + RES_BOTTOM_PAD)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.add_child(canvas)
	hs.add_child(frame)
	_research_frame = frame
	v.add_child(hs)

# Clamp the research scroller to the real visible page height so it scrolls
# internally instead of overflowing below the screen. Re-run on every page resize.
func _size_research_scroller() -> void:
	if not is_instance_valid(_research_hs) or not pages.has("research"):
		return
	var ph: float = pages["research"].size.y
	if ph < 200.0:
		return   # not laid out yet; the resized signal will call us again
	_research_hs.custom_minimum_size.y = maxf(300.0, ph - 112.0)

# Rescale the tree live (no rebuild). `focal` (screen px) stays pinned under the
# fingers so zooming feels anchored rather than jumping to a corner.
func _set_research_zoom(z: float, focal: Vector2) -> void:
	z = clampf(z, RES_ZOOM_MIN, RES_ZOOM_MAX)
	if not (is_instance_valid(_research_canvas) and is_instance_valid(_research_frame) and is_instance_valid(_research_hs)):
		return
	var hs := _research_hs
	var old_eff: float = _research_base_fit * _research_zoom
	var new_eff: float = _research_base_fit * z
	var rel: Vector2 = focal - hs.get_global_rect().position
	var canvas_pt: Vector2 = (Vector2(hs.scroll_horizontal, hs.scroll_vertical) + rel) / maxf(0.0001, old_eff)
	_research_zoom = z
	_research_canvas.scale = Vector2(new_eff, new_eff)
	_research_frame.custom_minimum_size = Vector2(_res_cw * new_eff, _res_ch * new_eff + RES_BOTTOM_PAD)
	var target: Vector2 = canvas_pt * new_eff - rel
	var sx := int(maxf(0.0, target.x))
	var sy := int(maxf(0.0, target.y))
	hs.scroll_horizontal = sx
	hs.scroll_vertical = sy
	hs.set_deferred("scroll_horizontal", sx)   # re-apply after the frame relayouts
	hs.set_deferred("scroll_vertical", sy)

# Two-finger pinch bookkeeping (research tree only). _touches is maintained in _input.
func _update_pinch_state() -> void:
	var want: bool = current == "research" and is_instance_valid(_research_canvas) and _touches.size() >= 2
	if want and not _pinch_active:
		_pinch_active = true
		_drag_active = false          # cancel any single-finger scroll that had started
		_drag_vel = 0.0
		_drag_vel_h = 0.0
		var pts: Array = _touches.values()
		_pinch_start_dist = maxf(1.0, pts[0].distance_to(pts[1]))
		_pinch_start_zoom = _research_zoom
	elif not want and _pinch_active:
		_pinch_active = false

func _pinch_update() -> void:
	if _touches.size() < 2:
		return
	var pts: Array = _touches.values()
	var dist: float = maxf(1.0, pts[0].distance_to(pts[1]))
	var focal: Vector2 = (pts[0] + pts[1]) * 0.5
	_set_research_zoom(_pinch_start_zoom * dist / _pinch_start_dist, focal)

func _draw_research_branches(canvas: Control, nodes: Array, pos: Dictionary) -> void:
	for nid in nodes:
		if not GameData.RESEARCH.has(nid):
			continue
		var par: String = GameData.RESEARCH[nid].get("parent", "")
		# Cross-tab parents (not in this layout) are treated as roots — no line.
		if par == "" or not pos.has(par) or not pos.has(nid):
			continue
		var pp: Vector2 = pos[par]
		var pn: Vector2 = pos[nid]
		var p1 := Vector2(pp.x * RES_SX + RES_PAD + RES_NODE_W, pp.y * RES_SY + RES_PAD + RES_NODE_H * 0.5)
		var p2 := Vector2(pn.x * RES_SX + RES_PAD, pn.y * RES_SY + RES_PAD + RES_NODE_H * 0.5)
		var col := Color.html(GREEN) if GameState.is_research_unlocked(nid) else Color(0.42, 0.46, 0.62, 0.7)
		# Elbow connector (horizontal out of parent, vertical, into child) reads
		# cleaner on dense trees than a single diagonal.
		var midx := (p1.x + p2.x) * 0.5
		canvas.draw_line(p1, Vector2(midx, p1.y), col, 2.0)
		canvas.draw_line(Vector2(midx, p1.y), Vector2(midx, p2.y), col, 2.0)
		canvas.draw_line(Vector2(midx, p2.y), p2, col, 2.0)

func _research_node(id: String) -> Control:
	var t: Dictionary = GameData.RESEARCH[id]
	var researched := GameState.is_research_unlocked(id)
	var available := GameState.research_available(id)
	var border := GREEN if researched else (C_WARN if available else "39425e")
	var fill := _mix(GREEN, INSET, 0.82) if researched else (_mix(PURP, INSET, 0.86) if available else "151b2c")
	# Plain Panel (not PanelContainer) so the node keeps a fixed, uniform height
	# regardless of name length; overflow is clipped instead of growing the node
	# (which would push edge nodes past the canvas bounds).
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(RES_NODE_W, RES_NODE_H)
	panel.clip_contents = true
	panel.set_meta("coach_id", id)
	panel.add_theme_stylebox_override("panel", _bordered(fill, border, 2 if (available or researched) else 1, 8))
	panel.tooltip_text = t.get("desc", "")
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 6)
	panel.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m.add_child(vb)
	var nm := Label.new()
	nm.text = t.get("name", id)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nm.add_theme_font_size_override("font_size", _fs(10))
	nm.add_theme_color_override("font_color", Color.html(C_TEXT if (available or researched) else C_MUTED))
	vb.add_child(nm)
	var status := Label.new()
	status.add_theme_font_size_override("font_size", _fs(10))
	if researched:
		status.text = "✓ Researched"
		status.add_theme_color_override("font_color", Color.html(GREEN))
	else:
		var cred := int(t.get("credits", 0))
		var extra: int = t.get("items", {}).size()
		status.text = "₡%s%s" % [GameData.fmt(cred), ("  +%d mat" % extra) if extra > 0 else ""]
		status.add_theme_color_override("font_color", Color.html(GREEN if GameState.credits >= cred else C_WARN))
	vb.add_child(status)
	if not researched:
		# Tap opens a detail modal with the full requirements (incl. material names)
		# — even when not yet affordable, so the player can see what's needed.
		var overlay := Button.new()
		overlay.flat = true
		overlay.focus_mode = Control.FOCUS_NONE
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.pressed.connect(func() -> void: _show_research_detail(id))
		panel.add_child(overlay)
	return panel

## Research node detail modal: name, description, full requirements (credits +
## each material with have/need), parent gate, and a Research button.
# Everything a research tech unlocks (recipes, modules, buildings, hulls, zones,
# follow-on techs) — gathered by scanning what gates on this tech id, so the detail
# modal can show "what do I get?" (desktop research_detail UNLOCKS section).
func _research_unlocks(rid: String) -> Array:
	var out := []
	for cid in GameData.CRAFT:
		if GameData.CRAFT[cid].get("research_req", "") == rid:
			out.append("⚙ " + String(GameData.CRAFT[cid].get("name", cid)))
	for gid in GameData.GATHER:
		if GameData.GATHER[gid].get("research_req", "") == rid:
			out.append("⛏ " + String(GameData.GATHER[gid].get("name", gid)))
	for mid in GameData.MODULES:
		if GameData.MODULES[mid].get("research_req", "") == rid:
			out.append("▣ " + String(GameData.MODULES[mid].get("name", mid)))
	for bid in GameData.BUILDINGS:
		if GameData.BUILDINGS[bid].get("research_req", "") == rid:
			out.append("⌂ " + String(GameData.BUILDINGS[bid].get("name", bid)))
	for hid in GameData.HULLS:
		if GameData.HULLS[hid].get("research_req", "") == rid:
			out.append("⛭ " + String(GameData.HULLS[hid].get("name", hid)))
	for z in GameData.ZONES:
		if z.get("research_req", "") == rid:
			out.append("◎ " + String(z.get("name", "")))
	for tid in GameData.RESEARCH:
		var rt: Dictionary = GameData.RESEARCH[tid]
		if rt.get("parent", "") == rid or (rt.get("req_tech", []) as Array).has(rid):
			out.append("✦ " + String(rt.get("name", tid)))
	return out

func _show_research_detail(id: String) -> void:
	# Shared modal chrome (fold of the old hand-rolled duplicate).
	_modal(String(GameData.RESEARCH[id].get("name", id)).to_upper(), PURP, _research_detail_body.bind(id), "✦", "Close")

func _research_detail_body(v: VBoxContainer, close: Callable, id: String) -> void:
	var t: Dictionary = GameData.RESEARCH[id]
	var researched := GameState.is_research_unlocked(id)
	var available := GameState.research_available(id)
	if t.get("desc", "") != "":
		var d := Label.new()
		d.text = t["desc"]
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.add_theme_font_size_override("font_size", _fs(11))
		d.add_theme_color_override("font_color", Color.html(C_DIM))
		v.add_child(d)
	# What researching this grants (recipes / modules / buildings / hulls / zones /
	# follow-on techs) — desktop parity.
	var unlocks := _research_unlocks(id)
	if not unlocks.is_empty():
		var ulines := []
		var cap := mini(14, unlocks.size())
		for i in cap:
			ulines.append(_line(unlocks[i], CYAN))
		if unlocks.size() > cap:
			ulines.append(_line("+%d more" % (unlocks.size() - cap), C_MUTED))
		_inset(v, "UNLOCKS", ulines, CYAN)
	var lines := []
	var cred := int(t.get("credits", 0))
	lines.append(_line("₡ Credits   %s / %s" % [GameData.fmt(GameState.credits), GameData.fmt(cred)], GREEN if GameState.credits >= cred else C_WARN))
	for sym in t.get("items", {}):
		var need := int(t["items"][sym])
		var have := GameState.amount(sym)
		lines.append(_line("%s   %s / %d" % [GameData.res_name(sym), GameData.fmt(have), need], GREEN if have >= need else C_WARN, sym))
	_inset(v, "REQUIREMENTS", lines, PURP)
	var par: String = t.get("parent", "")
	if par != "" and not GameState.is_research_unlocked(par):
		_clbl(v, "⊘ First research: " + GameData.RESEARCH.get(par, {}).get("name", par), 11, C_WARN)
	if researched:
		var done := Label.new()
		done.text = "✓ Researched"
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		done.add_theme_font_size_override("font_size", _fs(13))
		done.add_theme_color_override("font_color", Color.html(GREEN))
		_embolden(done)
		v.add_child(done)
	else:
		var rb := _card_button("Research", PURP, available)
		rb.custom_minimum_size = Vector2(0, 42)
		if available:
			rb.pressed.connect(func() -> void:
				GameState.unlock_research(id)
				close.call())
		v.add_child(rb)

# Recursion tab: infinite repeatable research (+5%/level sinks).
func _build_recursion(v: VBoxContainer) -> void:
	pages["research"].vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_section(v, "Recursion — infinite upgrades (+5% / level)", PURP)
	for rid in GameState.REPEATABLE_ORDER:
		var rd: Dictionary = GameState.REPEATABLE[rid]
		var lvl := GameState.repeatable_level(rid)
		var c := _card(PURP, true)
		_card_head(c, "∞", rd["name"], "Lv %d" % lvl, PURP, true)
		_clbl(c, "%s · %s" % [rd["field"], rd["desc"]], 11, C_DIM)
		_clbl(c, "Current bonus: +%d%%" % int(round(lvl * float(rd["bonus_value"]) * 100.0)), 11, GREEN)
		var cost: Dictionary = GameState.repeatable_cost(rid)
		var cost_lines := []
		for res in cost:
			var have: bool = (GameState.credits >= int(cost[res])) if res == "credits" else (GameState.amount(res) >= int(cost[res]))
			var lbl: String = ("₡%s" % GameData.fmt(cost[res])) if res == "credits" else ("%s %s" % [GameData.fmt(cost[res]), GameData.res_name(res)])
			cost_lines.append(_line(lbl, GREEN if have else C_WARN))
		_inset(c, "NEXT LEVEL COST", cost_lines, PURP)
		var can := GameState.can_unlock_repeatable(rid)
		var b := _card_button("Research Lv %d" % (lvl + 1), PURP, can)
		if can:
			b.pressed.connect(func() -> void: GameState.unlock_repeatable(rid))
		c.add_child(b)
		v.add_child(c.get_parent())     # attach the card panel to the page

# ============================================================ ATLAS / CODEX
func _build_atlas() -> void:
	var v := _clear("atlas")
	_back_header(v)
	_clbl(v, "ATLAS / CODEX", 16, CYAN)
	# Search box: filters materials & enemies by name. Typing refills only the
	# results container below (not this field), so focus / the keyboard stay put.
	var se := LineEdit.new()
	se.placeholder_text = "Search materials & enemies…"
	se.text = atlas_query
	se.clear_button_enabled = true
	se.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	se.add_theme_font_size_override("font_size", _fs(13))
	se.text_changed.connect(func(t: String) -> void:
		atlas_query = t
		_debounce("atlas", 0.18, _atlas_rebuild_results))
	v.add_child(se)
	_subtabs(v, [{"id": "materials", "label": "Materials"}, {"id": "enemies", "label": "Enemies"}], atlas_mode, CYAN, func(id: String) -> void:
		atlas_mode = id
		_refresh_current())
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(rv)
	_atlas_results = rv
	_atlas_fill_results()

func _atlas_fill_results() -> void:
	if not is_instance_valid(_atlas_results):
		return
	if atlas_mode == "materials":
		_atlas_materials(_atlas_results)
	else:
		_atlas_enemies(_atlas_results)
	_scroll_passthrough(_atlas_results)   # keep new rows touch-droppable for scroll

func _atlas_rebuild_results() -> void:
	if not is_instance_valid(_atlas_results):
		return
	for c in _atlas_results.get_children():
		_atlas_results.remove_child(c)
		c.queue_free()
	_atlas_fill_results()

func _atlas_matches(name: String) -> bool:
	var q := atlas_query.strip_edges().to_lower()
	return q == "" or q in name.to_lower()

func _atlas_get_index() -> Dictionary:
	if not _atlas_index.is_empty():
		return _atlas_index
	var idx := {}
	for gid in GameData.GATHER:
		var a: Dictionary = GameData.GATHER[gid]
		for row in a.get("loot", []):
			_atlas_add(idx, row[0], "sources", "⛏ " + a.get("name", gid))
	for rid in GameData.CRAFT:
		var r: Dictionary = GameData.CRAFT[rid]
		for s in r.get("outputs", {}):
			_atlas_add(idx, s, "sources", "⚙ " + r.get("name", rid))
		for row in r.get("bonus", []):
			_atlas_add(idx, row[0], "sources", "⚙ " + r.get("name", rid))
		for s in r.get("inputs", {}):
			_atlas_add(idx, s, "uses", "⚙ " + r.get("name", rid))
	for eid in GameData.ENEMIES:
		var e: Dictionary = GameData.ENEMIES[eid]
		for row in e.get("loot", []):
			_atlas_add(idx, row[0], "sources", "◎ " + e.get("name", eid))
		# Boss cores drop via the boss_core field, not the loot array — index the
		# boss as the source so e.g. a Cryofield Core shows "FROM: Cryo Overseer".
		var bc: String = String(e.get("boss_core", ""))
		if bc != "":
			_atlas_add(idx, bc, "sources", "◎ " + e.get("name", eid))
	for bid in GameData.BUILDINGS:
		var b: Dictionary = GameData.BUILDINGS[bid]
		for s in b.get("yield", {}):
			_atlas_add(idx, s, "sources", "⌂ " + b.get("name", bid))
		for s in b.get("input", {}):
			_atlas_add(idx, s, "uses", "⌂ " + b.get("name", bid))
		for s in b.get("cost", {}):
			if s != "credits":
				_atlas_add(idx, s, "uses", "⌂ " + b.get("name", bid))
	for hid in GameData.HULLS:
		for s in GameData.HULLS[hid].get("cost", {}):
			if s != "credits":
				_atlas_add(idx, s, "uses", "⛭ " + GameData.HULLS[hid].get("name", hid))
	for mid in GameData.MODULES:
		for s in GameData.MODULES[mid].get("cost", {}):
			if s != "credits":
				_atlas_add(idx, s, "uses", "▣ " + GameData.MODULES[mid].get("name", mid))
	for tid in GameData.RESEARCH:
		for s in GameData.RESEARCH[tid].get("items", {}):
			_atlas_add(idx, s, "uses", "✦ " + GameData.RESEARCH[tid].get("name", tid))
	_atlas_index = idx
	return idx

func _atlas_add(idx: Dictionary, sym: String, key: String, label: String) -> void:
	if not idx.has(sym):
		idx[sym] = {"sources": [], "uses": []}
	if not idx[sym][key].has(label):
		idx[sym][key].append(label)

const ATLAS_CATS := [
	{"id": "gathered", "label": "Gathered", "icon": "⛏"},
	{"id": "crafted",  "label": "Crafted",  "icon": "⚙"},
	{"id": "combat",   "label": "Combat",   "icon": "◎"},
	{"id": "built",    "label": "Built",    "icon": "⌂"},
	{"id": "other",    "label": "Other",    "icon": ""},
]

func _atlas_materials(v: VBoxContainer) -> void:
	var idx := _atlas_get_index()
	var searching := atlas_query.strip_edges() != ""
	# While searching, the category sub-filter is irrelevant (we match by name across
	# every category), so hide the category tabs to avoid implying a sub-scope.
	if not searching:
		var cat_items := []
		for c in ATLAS_CATS:
			cat_items.append({"id": c.id, "label": c.label})
		_subtabs(v, cat_items, atlas_mat_cat, CYAN, func(id: String) -> void:
			atlas_mat_cat = id
			_refresh_current())
	var want_icon := ""
	for c in ATLAS_CATS:
		if c.id == atlas_mat_cat:
			want_icon = c.icon
	var shown := 0
	var total := 0
	# Cap rendered rows so the list stays light (scrolling/searching hundreds of
	# resource panels stuttered). The remainder is summarised; search narrows it.
	for sym in GameData.RESOURCES:
		var info = idx.get(sym, null)
		if info == null or (info["sources"].is_empty() and info["uses"].is_empty()):
			continue
		if not _atlas_matches(GameData.item_name(sym)):
			continue
		# Name search spans all categories; otherwise filter by the source category.
		var match_cat := searching
		if not searching:
			if atlas_mat_cat == "other":
				match_cat = info["sources"].is_empty()
			else:
				for s in info["sources"]:
					if (s as String).begins_with(want_icon):
						match_cat = true
						break
		if not match_cat:
			continue
		total += 1
		if shown >= ATLAS_MAT_MAX_ROWS:
			continue   # counted for the summary, but don't build a node
		shown += 1
		v.add_child(_atlas_material_card(sym, info))
	if total == 0:
		_empty(v, "No materials found." if atlas_query.strip_edges() != "" else "No materials catalogued.")
	elif total > shown:
		_clbl(v, "Showing %d of %d — type to search." % [shown, total], 10, C_DIM)

# Atlas cards (materials AND enemies) are now lightweight — name + Info button,
# detail deferred to a tap modal — so both lists can render the whole catalogue
# without the stutter the old inline-detail cards caused. A generous safety cap.
const ATLAS_MAT_MAX_ROWS := 300

# Lightweight material card: just the name, value, and an Info button. The heavy
# FROM / USED IN detail is deferred to a tap (_show_material_info) so the list
# stays cheap to render and scroll even with many matches.
func _atlas_material_card(sym: String, info: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bordered(SURFACE, LINE, 1, 8))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 9)
	panel.add_child(m)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 8)
	m.add_child(hrow)
	var nm := Label.new()
	nm.text = GameData.item_name(sym)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nm.add_theme_font_size_override("font_size", _fs(14))
	nm.add_theme_color_override("font_color", GameData.color_for(sym))
	hrow.add_child(nm)
	var val := Label.new()
	val.text = "₡%d" % GameData.value_of(sym)
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	val.add_theme_font_size_override("font_size", _fs(12))
	val.add_theme_color_override("font_color", Color.html(GOLD))
	hrow.add_child(val)
	var ib := _card_button("ⓘ Info", CYAN, true)
	ib.pressed.connect(func() -> void: _show_material_info(sym, info))
	hrow.add_child(ib)
	return panel

# Material detail modal: value, optional description, and the FROM / USED IN
# source-and-use blocks (the data that used to render on every card).
func _show_material_info(sym: String, info: Dictionary) -> void:
	# The material's own (saturated) colour drives the whole chrome.
	_modal(GameData.item_name(sym), _hex(GameData.color_for(sym)), _material_info_body.bind(sym, info), "◈")

func _material_info_body(v: VBoxContainer, _close: Callable, sym: String, info: Dictionary) -> void:
	var big := _mat_icon(sym, 44)
	if big != null:
		var icc := CenterContainer.new()
		icc.add_child(big)
		v.add_child(icc)
	_big_stat(v, "₡%d" % GameData.value_of(sym), "each", GOLD, 22)
	var desc := String(GameData.RESOURCES.get(sym, {}).get("desc", ""))
	if desc != "":
		_lbl_wrap(v, desc, 11, C_TEXT)
	var sources: Array = info.get("sources", [])
	var uses: Array = info.get("uses", [])
	# v135a: split combat drops out and group them under their SECTOR (Lunar Orbit ›
	# mites, drones…), sorted by tier; non-combat sources stay flat on top.
	var non_combat := []
	for s in sources:
		if not String(s).begins_with("◎"):
			non_combat.append(s)
	if not non_combat.is_empty():
		_atlas_kv(v, "FROM", non_combat, GREEN)
	var zone_groups := _combat_sources_by_zone(sym)
	if not zone_groups.is_empty():
		_section(v, "DROPPED IN COMBAT", GREEN)
		for grp in zone_groups:
			_clbl(v, "◎ " + String(grp["zone"]), 11, CYAN)
			var body := Label.new()
			body.text = "      " + ", ".join(grp["enemies"])
			body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.add_theme_font_size_override("font_size", _fs(10))
			body.add_theme_color_override("font_color", Color.html(C_TEXT))
			v.add_child(body)
	if not uses.is_empty():
		_atlas_kv(v, "USED IN", uses, C_DIM)
	if sources.is_empty() and uses.is_empty():
		_clbl(v, "No recorded sources or uses.", 10, C_DIM)

# Combat drops of `sym` grouped under their sector, ascending by tier. Returns
# [{zone, enemies:[names]}] — an enemy contributes via its loot array OR boss_core.
func _combat_sources_by_zone(sym: String) -> Array:
	var zone_names := {}
	var zone_ord := {}
	for z in GameData.ZONES:
		var d := int(z.get("difficulty", 0))
		zone_names[d] = String(z.get("name", "Zone %d" % d))
	var by_zone := {}
	for eid in GameData.ENEMIES:
		var e: Dictionary = GameData.ENEMIES[eid]
		var drops := String(e.get("boss_core", "")) == sym
		if not drops:
			for row in e.get("loot", []):
				if String(row[0]) == sym:
					drops = true
					break
		if not drops:
			continue
		var zo := int(e.get("zone", 0))
		if not by_zone.has(zo):
			by_zone[zo] = []
		var enm := String(e.get("name", eid))
		if not by_zone[zo].has(enm):
			by_zone[zo].append(enm)
	var ords: Array = by_zone.keys()
	ords.sort()
	var out := []
	for zo in ords:
		out.append({"zone": String(zone_names.get(zo, "Zone %d" % zo)), "enemies": by_zone[zo]})
	return out

# A labelled, wrapping list block (eyebrow + body). Rendered only inside the
# material detail modal now, so it lists generously before truncating.
func _atlas_kv(parent: VBoxContainer, label_text: String, items: Array, color: String) -> void:
	_section(parent, label_text, color)
	var shown := items
	var more := 0
	if items.size() > 24:
		shown = items.slice(0, 24)
		more = items.size() - 24
	var body := Label.new()
	body.text = ", ".join(shown) + ("  +%d more" % more if more > 0 else "")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", _fs(11))
	body.add_theme_color_override("font_color", Color.html(color))
	parent.add_child(body)

# ============================================================ HAZARD ZONES
# Gauntlet runs (GameData.HAZARD_ZONES): locked until the unlock boss falls,
# warn if the counter module isn't fitted, then a max-waves gauntlet that calls
# GameState.start_hazard. Live wave counter shows on the battle view.
func _build_hazard() -> void:
	var v := _clear("hazard")
	_back_header(v)
	var eyebrow := Label.new()
	eyebrow.text = "☢ HAZARD ZONES"
	eyebrow.add_theme_font_size_override("font_size", _fs(16))
	eyebrow.add_theme_color_override("font_color", Color.html(PURP))
	v.add_child(eyebrow)
	_section(v, "Wave-survival gauntlets. Defeat the unlock boss, fit the counter module, then clear every wave for a one-time reward.", PURP)

	# Active run banner.
	if GameState.hazard_state.get("active", false):
		var ahz: Dictionary = GameData.HAZARD_ZONES.get(GameState.hazard_state["zone_id"], {})
		var rc := _card(GREEN, true)
		_card_head(rc, "☢", "IN PROGRESS — " + ahz.get("name", ""), "", GREEN, true)
		_clbl(rc, "WAVE %d/%d" % [int(GameState.hazard_state["wave"]) + 1, int(GameState.hazard_state["max_waves"])], 15, GREEN)
		var go := _card_button("Go to Battle", RED, true)
		go.pressed.connect(func() -> void: _show("combat"))
		rc.add_child(go)
		v.add_child(rc.get_parent())

	for hz_id in GameData.HAZARD_ZONES:
		var hz: Dictionary = GameData.HAZARD_ZONES[hz_id]
		var unlocked := GameState.is_hazard_unlocked(hz_id)
		var c := _card(PURP, unlocked)
		var badge := "★%d" % int(hz.get("difficulty", 1))
		_card_head(c, "☢", hz.get("name", hz_id), badge, PURP, unlocked)
		var ht: String = hz.get("hazard_type", "")
		_clbl(c, hz.get("desc", ""), 11, C_DIM)
		var info := [
			_line("Type: %s" % ht.replace("_", " ").to_upper(), PURP),
			_line("Waves: %d  (elite + boss finale)" % int(hz.get("max_waves", 7)), C_TEXT),
		]
		_inset(c, "GAUNTLET", info, PURP)
		if not unlocked:
			# Tell the player exactly which boss to defeat.
			var boss_id: String = hz.get("unlock_boss", "")
			var boss_nm: String = GameData.ENEMIES.get(boss_id, {}).get("name", boss_id)
			_clbl(c, "⊘ LOCKED — defeat %s to unlock" % boss_nm, 11, C_WARN)
		else:
			# Counter-module warning: survivable but punishing without it.
			var counter: String = hz.get("counter_module", "")
			if counter != "" and not GameState.has_counter_module(hz_id):
				var cm_nm: String = GameData.MODULES.get(counter, {}).get("name", counter)
				_clbl(c, "⚠ Fit %s (Ship › Modules) or weapons jam!" % cm_nm, 11, RED)
			elif counter != "":
				_clbl(c, "✓ %s equipped" % GameData.MODULES.get(counter, {}).get("name", counter), 10, GREEN)
			if hz.get("first_clear_reward", "") != "" and not GameState.hazard_clears.get(hz_id, false):
				_clbl(c, "First-clear reward: %s" % GameData.res_name(hz["first_clear_reward"]), 10, GOLD)
			var running: bool = GameState.hazard_state.get("active", false)
			var eb := _card_button("☢ Enter Gauntlet" if not running else "Run in progress", RED, not running and GameState.active_hull != "")
			if not running and GameState.active_hull != "":
				var zid: String = hz_id
				eb.pressed.connect(func() -> void:
					if GameState.start_hazard(zid):
						_show("combat"))
			c.add_child(eb)
		v.add_child(c.get_parent())

func _atlas_enemies(v: VBoxContainer) -> void:
	var found := 0
	var truncated := false
	for z in GameData.ZONES:
		# Collect this zone's matching enemies first so an empty section header is
		# never shown while searching.
		var zids := []
		for eid in z.get("enemies", []):
			if GameData.ENEMIES.has(eid) and _atlas_matches(GameData.ENEMIES[eid].get("name", eid)):
				zids.append(eid)
		if zids.is_empty():
			continue
		if found >= ATLAS_MAT_MAX_ROWS:
			truncated = true
			break
		_section(v, "%s  (★%d)" % [z.get("name", ""), int(z.get("difficulty", 1))], RED)
		for eid in zids:
			if found >= ATLAS_MAT_MAX_ROWS:
				truncated = true
				break
			found += 1
			v.add_child(_atlas_enemy_card(eid, "◎", RED))
	# Hazard-zone gauntlet enemies aren't in any sector pool — list them so the
	# codex is complete (incl. hz_ drones / elites / overlords). Hidden until
	# the hazard is unlocked (desktop never lists them before that).
	var hz_seen := {}
	for hz_id in GameData.HAZARD_ZONES:
		if not GameState.is_hazard_unlocked(hz_id):
			continue
		var hz: Dictionary = GameData.HAZARD_ZONES[hz_id]
		var pool: Array = []
		pool.append_array(hz.get("enemy_pool", []))
		if hz.get("elite_enemy", "") != "":
			pool.append(hz["elite_enemy"])
		if hz.get("boss_enemy", "") != "":
			pool.append(hz["boss_enemy"])
		var hz_ids := []
		for eid in pool:
			if not hz_seen.has(eid) and GameData.ENEMIES.has(eid) and _atlas_matches(GameData.ENEMIES[eid].get("name", eid)):
				hz_ids.append(eid)
		if hz_ids.is_empty():
			continue
		if found >= ATLAS_MAT_MAX_ROWS:
			truncated = true
			break
		_section(v, "☢ %s  (Hazard)" % hz.get("name", hz_id), PURP)
		for eid in hz_ids:
			if found >= ATLAS_MAT_MAX_ROWS:
				truncated = true
				break
			hz_seen[eid] = true
			found += 1
			v.add_child(_atlas_enemy_card(eid, "☢", PURP))
	if found == 0 and atlas_query.strip_edges() != "":
		_empty(v, "No enemies found.")
	elif truncated:
		_clbl(v, "Showing first %d — type to search." % ATLAS_MAT_MAX_ROWS, 10, C_DIM)

# Lightweight enemy card: icon + name, an optional DROPS badge, and an Intel
# button that opens the full _show_enemy_intel modal. Stats / affinity / loot are
# deferred to that modal so the list stays cheap to build and scroll.
func _atlas_enemy_card(eid: String, icon: String, accent: String) -> Control:
	var e: Dictionary = GameData.ENEMIES[eid]
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bordered(SURFACE, LINE, 1, 8))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 9)
	panel.add_child(m)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 8)
	m.add_child(hrow)
	var nm := Label.new()
	nm.text = "%s %s" % [icon, e.get("name", eid)]
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nm.add_theme_font_size_override("font_size", _fs(14))
	nm.add_theme_color_override("font_color", Color.html(accent))
	hrow.add_child(nm)
	if float(e.get("drop_chance", 0.0)) > 0.0 and not (e.get("drop_pool", []) as Array).is_empty():
		var bd := Label.new()
		bd.text = "DROPS"
		bd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bd.add_theme_font_size_override("font_size", _fs(9))
		bd.add_theme_color_override("font_color", Color.html(GOLD))
		hrow.add_child(bd)
	var ib := _card_button("ⓘ Intel", CYAN, true)
	ib.pressed.connect(func() -> void: _show_enemy_intel(eid))
	hrow.add_child(ib)
	return panel

# ============================================================ STATS / STORAGE
func _build_stats() -> void:
	var v := _clear("stats")
	_back_header(v)
	# Credits banner
	var cpanel := PanelContainer.new()
	cpanel.add_theme_stylebox_override("panel", _card_style(_mix(GOLD, SURFACE, 0.86), _mix(GOLD, LINE, 0.4), 1, false))
	var crow := HBoxContainer.new()
	cpanel.add_child(crow)
	var cl := Label.new()
	cl.text = "CREDITS"
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cl.add_theme_font_size_override("font_size", _fs(12))
	cl.add_theme_color_override("font_color", Color.html(C_DIM))
	crow.add_child(cl)
	var cv := Label.new()
	cv.text = "₡%s" % GameData.fmt(GameState.credits)
	cv.add_theme_font_size_override("font_size", _fs(18))
	cv.add_theme_color_override("font_color", Color.html(GOLD))
	crow.add_child(cv)
	v.add_child(cpanel)

	# (Crew skill bars live on their own pages — Harvesting on Gather, Engineering
	# on Shipyard, etc. — so they're not duplicated here.)
	var used := GameState.used_slots()
	var cap := GameState.max_slots()
	# Total inventory worth — the honest credit readout for a sell-driven economy.
	var worth := 0
	for sym in GameData.RESOURCES:
		var amt := GameState.amount(sym)
		if amt > 0:
			worth += amt * maxi(1, GameData.value_of(sym))
	var full := used >= cap
	_storage_worth_label = _section(v, "Storage  %d / %d slots  ·  worth ₡%s — tap a slot to sell" % [used, cap, GameData.fmt(worth)], RED if full else GOLD)
	if full:
		_clbl(v, "⚠ STORAGE FULL — new material types are being lost. Sell below or expand storage.", 11, RED)
	# Search box: filters the material grid by name. Typing refills only the grid
	# wrapper below (not this field), so focus / the keyboard stay put.
	var se := LineEdit.new()
	se.placeholder_text = "Search materials…"
	se.text = storage_query
	se.clear_button_enabled = true
	se.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	se.add_theme_font_size_override("font_size", _fs(13))
	se.text_changed.connect(func(t: String) -> void:
		storage_query = t
		_debounce("storage", 0.18, _storage_rebuild_grid))
	v.add_child(se)
	# Grid wrapper — refilled live on search without rebuilding the whole page.
	var gw := VBoxContainer.new()
	gw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(gw)
	_storage_results = gw
	_storage_fill_grid()
	# Expand storage (credit sink): +1 slot at 1000·1.5^n.
	var up_cost := GameState.storage_upgrade_cost()
	var can_up := GameState.credits >= up_cost
	var up := _card_button("Expand Storage  +1 slot   ₡%s" % GameData.fmt(up_cost), GOLD, can_up)
	up.custom_minimum_size = Vector2(0, 42)
	if can_up:
		up.pressed.connect(func() -> void:
			GameState.upgrade_storage()
			_refresh_current())
	v.add_child(up)

# Build the storage tile grid into the live wrapper, honoring the search filter.
# Empty padding slots are only drawn for the full (unfiltered) view so a search
# shows just its matches.
func _storage_fill_grid() -> void:
	if not is_instance_valid(_storage_results):
		return
	var q := storage_query.strip_edges().to_lower()
	_storage_qty_labels = {}
	var owned := []
	for sym in GameData.RESOURCES:
		if GameState.amount(sym) <= 0:
			continue
		if q != "" and not (q in GameData.res_name(sym).to_lower() or q in sym.to_lower()):
			continue
		owned.append(sym)
	_storage_tile_syms = owned.duplicate()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 7)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_storage_results.add_child(grid)
	for sym in owned:
		grid.add_child(_storage_tile(sym))
	if q == "":
		# Pad with empty slots up to capacity only in the unfiltered view.
		var cap := GameState.max_slots()
		var total: int = maxi(cap, int(ceil(owned.size() / 4.0)) * 4)
		for _i in range(total - owned.size()):
			grid.add_child(_storage_slot_empty())
		if owned.is_empty():
			_empty(_storage_results, "Storage empty — go gather something.")
	elif owned.is_empty():
		_empty(_storage_results, "No materials match “%s”." % storage_query.strip_edges())
	_scroll_passthrough(_storage_results)   # keep new tiles touch-droppable for scroll

func _storage_rebuild_grid() -> void:
	if not is_instance_valid(_storage_results):
		return
	for c in _storage_results.get_children():
		_storage_results.remove_child(c)
		c.queue_free()
	_storage_fill_grid()

# Live storage refresh on resource ticks WITHOUT a grid rebuild (which would jump
# the page). Updates each tile's quantity label and the worth header in place. If
# the set of owned materials changed (a new type appeared, or one was sold/depleted
# to 0), the grid structure must change — only then do a full rebuild.
func _storage_live_update() -> void:
	if not is_instance_valid(_storage_results):
		return
	var q := storage_query.strip_edges().to_lower()
	# Detect a structure change against the currently-tiled set.
	var owned := []
	for sym in GameData.RESOURCES:
		if GameState.amount(sym) <= 0:
			continue
		if q != "" and not (q in GameData.res_name(sym).to_lower() or q in sym.to_lower()):
			continue
		owned.append(sym)
	if owned != _storage_tile_syms:
		_storage_rebuild_grid()
		return
	# Same set — just refresh quantities (and total worth) in place.
	for sym in _storage_qty_labels:
		var l = _storage_qty_labels[sym]
		if is_instance_valid(l):
			l.text = GameData.fmt(GameState.amount(sym))
	if is_instance_valid(_storage_worth_label):
		var used := GameState.used_slots()
		var cap := GameState.max_slots()
		var worth := 0
		for sym in GameData.RESOURCES:
			var amt := GameState.amount(sym)
			if amt > 0:
				worth += amt * maxi(1, GameData.value_of(sym))
		_storage_worth_label.text = ("Storage  %d / %d slots  ·  worth ₡%s — tap a slot to sell" % [used, cap, GameData.fmt(worth)]).to_upper()

# ============================================================ SETTINGS
func _build_settings() -> void:
	var v := _clear("settings")
	_back_header(v)
	_clbl(v, "SETTINGS", 16, CYAN)
	_section(v, "System", CYAN)
	# Offline-combat toggle (off by default, like desktop).
	var oc := GameState.offline_combat
	var oc_btn := _card_button("Offline Combat: %s" % ("ON" if oc else "OFF"), GREEN if oc else C_MUTED, true)
	oc_btn.custom_minimum_size = Vector2(0, 44)
	oc_btn.pressed.connect(func() -> void:
		GameState.offline_combat = not GameState.offline_combat
		_refresh_current())
	v.add_child(oc_btn)
	_lbl_wrap(v, "⛨ Away combat carries the durability risk: modules already worn to 50% can be destroyed while you're gone (~5%/hr each, capped 35%). Repair before logging off for zero risk.", 9, C_MUTED)
	_clbl(v, "Progress saves automatically.", 10, C_DIM)
	var reset_btn := _card_button("⚠ Tap again to wipe save" if _reset_armed else "Reset Game", RED, true)
	reset_btn.custom_minimum_size = Vector2(0, 44)
	reset_btn.pressed.connect(func() -> void:
		if _reset_armed:
			GameState.hard_reset()
			_show("gather")
		else:
			_reset_armed = true
			_refresh_current())
	v.add_child(reset_btn)

func _storage_tile(sym: String) -> Control:
	var amt := GameState.amount(sym)
	var rcol := _hex(GameData.color_for(sym))
	var val: int = maxi(1, GameData.value_of(sym))
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 122)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _bordered(_mix(rcol, SURFACE, 0.9), rcol, 1, 8))
	panel.tooltip_text = "%s — tap to sell (choose quantity)" % GameData.res_name(sym)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 5)
	panel.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(vb)
	var ic := _mat_icon(sym, 34)
	if ic != null:
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(ic)
	var nm := Label.new()
	nm.text = GameData.res_name(sym)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nm.add_theme_font_size_override("font_size", _fs(9))
	nm.add_theme_color_override("font_color", Color.html(rcol))
	vb.add_child(nm)
	var qty := Label.new()
	qty.text = GameData.fmt(amt)
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty.add_theme_font_size_override("font_size", _fs(14))
	qty.add_theme_color_override("font_color", Color.html(C_TEXT))
	vb.add_child(qty)
	_storage_qty_labels[sym] = qty   # for live in-place quantity updates
	var pv := Label.new()
	pv.text = "₡%s" % GameData.fmt(amt * val)
	pv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_theme_font_size_override("font_size", _fs(9))
	pv.add_theme_color_override("font_color", Color.html(GOLD))
	vb.add_child(pv)
	var overlay := Button.new()
	overlay.flat = true
	overlay.focus_mode = Control.FOCUS_NONE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.pressed.connect(func() -> void: _open_sell_picker(sym))
	panel.add_child(overlay)
	return panel

# Sell-quantity picker: a slider + quick-set buttons so a tap no longer dumps the
# whole stack. Confirms with "Sell N → ₡Y"; Cancel (added by _modal) backs out.
func _open_sell_picker(sym: String) -> void:
	var owned: int = GameState.amount(sym)
	if owned <= 0:
		return
	var val: int = maxi(1, GameData.value_of(sym))
	_modal("Sell " + GameData.res_name(sym), GOLD, func(v: VBoxContainer, close: Callable) -> void:
		var state := {"qty": owned}
		_clbl(v, "Owned %s  ·  ₡%d each" % [GameData.fmt(owned), val], 11, C_DIM)
		var readout := Label.new()
		readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		readout.add_theme_font_size_override("font_size", _fs(20))
		readout.add_theme_color_override("font_color", Color.html(GOLD))
		_embolden(readout)
		v.add_child(readout)
		var sl := HSlider.new()
		sl.min_value = 1
		sl.max_value = owned
		sl.step = 1
		sl.value = owned
		sl.custom_minimum_size = Vector2(0, 30)
		_style_slider(sl, GOLD)
		v.add_child(sl)
		var sync := func() -> void:
			readout.text = "Sell %s  →  ₡%s" % [GameData.fmt(int(state["qty"])), GameData.fmt(int(state["qty"]) * val)]
		var set_qty := func(q: int) -> void:
			state["qty"] = clampi(q, 1, owned)
			sl.set_value_no_signal(state["qty"])
			sync.call()
		sl.value_changed.connect(func(value: float) -> void:
			state["qty"] = clampi(int(value), 1, owned)
			sync.call())
		var row1 := HBoxContainer.new()
		row1.add_theme_constant_override("separation", 6)
		for delta in [-10, -1, 1, 10]:
			var b := _card_button("%+d" % delta, CYAN, true)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var dlt: int = delta
			b.pressed.connect(func() -> void: set_qty.call(int(state["qty"]) + dlt))
			row1.add_child(b)
		v.add_child(row1)
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 6)
		for spec in [["25%", maxi(1, owned / 4)], ["50%", maxi(1, owned / 2)], ["Max", owned]]:
			var b := _card_button(String(spec[0]), CYAN, true)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var q: int = int(spec[1])
			b.pressed.connect(func() -> void: set_qty.call(q))
			row2.add_child(b)
		v.add_child(row2)
		var sell := _card_button("Sell", GOLD, true)
		sell.custom_minimum_size = Vector2(0, 44)
		sell.pressed.connect(func() -> void:
			GameState.sell_resource(sym, int(state["qty"]))
			_fly_to_credits(sell, sym)
			close.call()
			_refresh_current())
		v.add_child(sell)
		sync.call())

func _storage_slot_empty() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 122)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _bordered(INSET, LINE, 1, 8))
	var cc := CenterContainer.new()
	panel.add_child(cc)
	var dot := Label.new()
	dot.text = "·"
	dot.add_theme_font_size_override("font_size", _fs(16))
	dot.add_theme_color_override("font_color", Color.html(C_MUTED))
	cc.add_child(dot)
	return panel

# ============================================================ SHARED CARD PIECES
func _action_controls(v: VBoxContainer, type: String, id: String, active: bool, accent: String, start_label := "Start", stop_label := "Stop") -> void:
	var b := _card_button(stop_label if active else start_label, accent, true)
	b.pressed.connect(func() -> void: GameState.start_task(type, id))
	v.add_child(b)
	var t := Label.new()
	t.text = "%.1fs / %.1fs" % [GameState.progress if active else 0.0, GameState.effective_duration(type, id)]
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", _fs(10))
	t.add_theme_color_override("font_color", Color.html(C_MUTED))
	v.add_child(t)
	if active:
		_active_timer = t
	_progress(v, active, accent)

func _locked(v: VBoxContainer, def: Dictionary, skill: String) -> void:
	var top := Control.new()
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(top)
	_clbl(v, "LOCKED", 13, C_WARN)
	var r := Label.new()
	r.text = _req_text(def, skill)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_theme_font_size_override("font_size", _fs(10))
	r.add_theme_color_override("font_color", Color.html(C_MUTED))
	v.add_child(r)
	var bot := Control.new()
	bot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(bot)

func _loot_lines(loot: Array) -> Array:
	var lines := []
	for row in loot:
		var sym: String = row[0]
		var is_credits: bool = sym == "credits"
		var label: String
		var col: String
		if is_credits:
			label = "Credits"
			col = GOLD
		elif GameData.MODULES.has(sym) or GameData.SET_MODULES.has(sym):
			# Module drops (unique set pieces live in SET_MODULES) carry a display
			# name + rarity — show those, not the raw "z1_unique_weapon" id. Checked
			# BEFORE res_name because the loot symbol also has an auto-generated
			# resource stub whose name is the raw id.
			var md: Dictionary = GameData.MODULES.get(sym, GameData.SET_MODULES.get(sym, {}))
			label = String(md.get("name", sym))
			col = GameState.RARITY_COLOR.get(int(md.get("rarity", 0)), C_TEXT)
		else:
			label = GameData.res_name(sym)
			col = _hex(GameData.color_for(sym))
		var txt := "%s%s %d-%d" % ["₡ " if is_credits else "", label, int(row[2]), int(row[3])]
		if float(row[1]) < 1.0:
			txt += " (%d%%)" % int(float(row[1]) * 100.0)
		# Pass the symbol so _inset draws the material icon (credits/modules have
		# no material art and fall back to text).
		lines.append(_line(txt, col, "" if is_credits else sym))
	return lines

func _empty(v: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color.html(C_MUTED))
	l.add_theme_font_size_override("font_size", _fs(12))
	v.add_child(l)

# ============================================================ WIDGET HELPERS
func _grid(v: VBoxContainer) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Self-equalizing: every card's min height is raised to the tallest card's
	# natural height, so ALL rows match (locked, unlocked, active) at any text
	# scale. Measured one frame AFTER the first real-width layout — autowrap
	# labels report garbage minimums until they've been fitted once.
	var applied := [false]
	g.sort_children.connect(func() -> void:
		if applied[0] or g.size.x < 100.0:
			return
		applied[0] = true
		g.get_tree().process_frame.connect(func() -> void:
			if not is_instance_valid(g):
				return
			var maxh := 0.0
			for ch in g.get_children():
				if ch is Control:
					maxh = maxf(maxh, (ch as Control).get_combined_minimum_size().y)
			if maxh <= 0.0:
				return
			for ch in g.get_children():
				if ch is Control:
					(ch as Control).custom_minimum_size.y = maxh,
			CONNECT_ONE_SHOT))
	v.add_child(g)
	return g

func _subtabs(v: VBoxContainer, items: Array, current_id: String, accent: String, on_select: Callable) -> void:
	# Chips wrap onto multiple rows instead of a single horizontally-scrolling strip,
	# so a page with many categories (Craft has 14) shows them all at once — no
	# left/right sliding to reach a tab. Few-tab pages still render as one row.
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 7)
	flow.add_theme_constant_override("v_separation", 7)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for it in items:
		var on: bool = it["id"] == current_id
		var b := Button.new()
		b.text = it["label"]
		b.focus_mode = Control.FOCUS_NONE
		# PASS so a vertical drag over a chip reaches the page ScrollContainer
		# (which then scrolls and cancels the tap); a clean tap still selects.
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.custom_minimum_size = Vector2(0, 42)
		b.add_theme_font_size_override("font_size", _fs(12))
		var fill := accent if on else SURFACE_HI
		var txt := _ideal_text(accent) if on else C_DIM
		b.add_theme_color_override("font_color", Color.html(txt))
		b.add_theme_color_override("font_color_hover", Color.html(txt))
		b.add_theme_color_override("font_color_pressed", Color.html(txt))
		var sb := _bordered(fill, accent if on else LINE, 1, 16)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, sb)
		var sel_id: String = it["id"]
		b.pressed.connect(func() -> void: on_select.call(sel_id))
		flow.add_child(b)
	v.add_child(flow)

func _style_nav(id: String, active: bool) -> void:
	var item = nav_items.get(id)
	if item == null:
		return
	var accent: String = DOMAIN.get(id, CYAN)
	item["icon"].add_theme_color_override("font_color", Color.html(accent if active else C_DIM))
	item["label"].add_theme_color_override("font_color", Color.html(C_TEXT if active else C_DIM))
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color.html(accent) if active else Color(0, 0, 0, 0)
	bs.set_corner_radius_all(2)
	item["bar"].add_theme_stylebox_override("panel", bs)
	var nbg := StyleBoxFlat.new()
	nbg.bg_color = Color.html(_mix(accent, SURFACE, 0.8)) if active else Color(0, 0, 0, 0)
	nbg.set_corner_radius_all(8)
	for st in ["normal", "hover", "pressed", "focus"]:
		item["btn"].add_theme_stylebox_override(st, nbg)

func _card(accent: String, lit: bool, min_h: int = 0) -> VBoxContainer:
	var panel := PanelContainer.new()
	# Gradient-lit 9-slice surface (art-direction pass). To revert to the flat
	# look, swap this one line back to _card_style(SURFACE, ..., 1, lit).
	panel.add_theme_stylebox_override("panel", _surface_style(_mix(accent, SURFACE, 0.93) if lit else SURFACE, accent if lit else LINE, lit))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if min_h > 0:
		# Uniform card height via a minimum size (NOT SIZE_FILL, which breaks
		# the parent ScrollContainer's scroll range).
		panel.custom_minimum_size = Vector2(0, min_h)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	# Edge-light: a thin accent strip along the card's top — the "lit hardware"
	# bevel every card carries (bright in its domain color when lit, a faint
	# white catch-light when locked).
	var edge := ColorRect.new()
	edge.custom_minimum_size = Vector2(0, 2)
	edge.color = Color(Color.html(accent), 0.35) if lit else Color(1, 1, 1, 0.06)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(edge)
	return v

func _card_head(v: VBoxContainer, icon: String, name: String, badge: String, accent: String, lit: bool) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 7)
	if icon != "":
		# Bigger, brighter identity chip — the icon reads as game iconography,
		# not a list-row glyph.
		var chip := PanelContainer.new()
		chip.custom_minimum_size = Vector2(38, 38)
		chip.add_theme_stylebox_override("panel", _bordered(_mix(accent, INSET, 0.62) if lit else INSET, _mix(accent, LINE, 0.5) if lit else LINE, 1, 10))
		var cc := CenterContainer.new()
		chip.add_child(cc)
		var ic := Label.new()
		ic.text = icon
		ic.add_theme_font_size_override("font_size", _fs(17))
		ic.add_theme_color_override("font_color", Color.html(accent if lit else C_MUTED))
		cc.add_child(ic)
		hb.add_child(chip)
	var nm := Label.new()
	nm.text = name
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.add_theme_font_size_override("font_size", _fs(13))
	nm.add_theme_color_override("font_color", Color.html(C_TEXT if lit else C_MUTED))
	_embolden(nm)   # display weight — card titles read as game chrome
	hb.add_child(nm)
	if badge != "":
		var bd := PanelContainer.new()
		bd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bsb := _bordered(_mix(accent, INSET, 0.8) if lit else INSET, accent if lit else LINE, 1, 8)
		bsb.content_margin_left = 7
		bsb.content_margin_right = 7
		bsb.content_margin_top = 2
		bsb.content_margin_bottom = 2
		bd.add_theme_stylebox_override("panel", bsb)
		var bl := Label.new()
		bl.text = badge
		bl.add_theme_font_size_override("font_size", _fs(9))
		bl.add_theme_color_override("font_color", Color.html(accent if lit else C_MUTED))
		bd.add_child(bl)
		hb.add_child(bd)
	v.add_child(hb)

# --- Material icons (ported from the desktop assets/icons/materials) --------
# 64x64 monochrome SVGs keyed by resource symbol, tinted by the material's color.
# Cached. Symbols with no icon (equipment instances, credits, blueprints) return
# null and the caller falls back to the plain text / colour treatment.
var _mat_icon_cache := {}

func _mat_icon_tex(sym: String) -> Texture2D:
	if _mat_icon_cache.has(sym):
		return _mat_icon_cache[sym]
	var tex: Texture2D = null
	var path := "res://assets/icons/materials/%s.svg" % sym
	if ResourceLoader.exists(path):
		var src := load(path) as Texture2D
		if src != null:
			# Rebuild the icon so it renders correctly even where the imported
			# texture's transparency is dropped on device (the sparse-icon
			# "black square" bug). Alpha is DERIVED from source brightness — white
			# glyph → opaque, black/transparent background → clear — and the material
			# colour is baked in, so it never relies on the source alpha channel or a
			# modulate. Cached per symbol.
			var img := src.get_image()
			if img != null:
				if img.is_compressed():
					img.decompress()
				img.convert(Image.FORMAT_RGBA8)
				var col := GameData.color_for(sym)
				var w := img.get_width()
				var h := img.get_height()
				for y in h:
					for x in w:
						var p := img.get_pixel(x, y)
						var lum: float = maxf(p.r, maxf(p.g, p.b))
						img.set_pixel(x, y, Color(col.r, col.g, col.b, lum))
				tex = ImageTexture.create_from_image(img)
			else:
				tex = src
	_mat_icon_cache[sym] = tex
	return tex

# A square TextureRect for a material's icon (tinted by its colour), or null when
# the symbol has no icon. px = side length in virtual pixels.
func _mat_icon(sym: String, px: int) -> TextureRect:
	var tex := _mat_icon_tex(sym)
	if tex == null:
		return null
	var t := TextureRect.new()
	t.texture = tex
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Tint is baked into the texture by _mat_icon_tex (device alpha-drop workaround),
	# so no modulate here.
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

# Reverse map for places that only have a material's display name (e.g. the
# offline report strings) and need its symbol back to draw an icon. Built once.
var _res_name_to_sym := {}
func _sym_for_name(nm: String) -> String:
	if _res_name_to_sym.is_empty():
		for s in GameData.RESOURCES:
			var rn: String = GameData.RESOURCES[s].get("name", s)
			if not _res_name_to_sym.has(rn):
				_res_name_to_sym[rn] = s
	return _res_name_to_sym.get(nm, "")

func _inset(v: VBoxContainer, title: String, lines: Array, accent: String, highlight := false) -> void:
	var panel := PanelContainer.new()
	var sb := _bordered(INSET, accent if highlight else LINE, 1, 8)
	if highlight:
		sb.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", _fs(8))
	t.add_theme_color_override("font_color", Color.html(accent if highlight else C_MUTED))
	box.add_child(t)
	for ln in lines:
		var sym: String = ln.get("sym", "")
		var icon: TextureRect = _mat_icon(sym, 18) if sym != "" else null
		if icon != null:
			# Material row: tinted icon + label, centred together.
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 5)
			row.add_child(icon)
			var lbl := Label.new()
			lbl.text = ln["text"]
			lbl.add_theme_font_size_override("font_size", _fs(12))
			lbl.add_theme_color_override("font_color", Color.html(ln["color"]))
			row.add_child(lbl)
			box.add_child(row)
		else:
			_clbl(box, ln["text"], 12, ln["color"])
	v.add_child(panel)

func _clbl(parent: Node, text: String, size: int, color: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", _fs(size))
	l.add_theme_color_override("font_color", Color.html(color))
	parent.add_child(l)

func _line(text: String, color: String, sym := "") -> Dictionary:
	# sym (optional): material symbol — when it has an icon, _inset draws it.
	return {"text": text, "color": color, "sym": sym}

func _card_button(text: String, accent: String, enabled: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 54)
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	if _font_bold != null:
		b.add_theme_font_override("font", _font_bold)   # chunky CTA type
	# Chunky game CTA: darker bottom edge fakes a 3D bevel; pressing flattens the
	# edge and nudges the label down — classic mobile-game button feel.
	var normal := _bordered(accent if enabled else "232f48", _mix(accent, "000000", 0.45) if enabled else LINE, 1, 10)
	if enabled:
		normal.border_width_bottom = 4
		normal.content_margin_bottom = 9
		normal.shadow_color = Color(0, 0, 0, 0.35)
		normal.shadow_size = 4
		normal.shadow_offset = Vector2(0, 2)
	var pressed := _bordered(_mix(accent, "000000", 0.30) if enabled else "232f48", _mix(accent, "000000", 0.45) if enabled else LINE, 1, 10)
	if enabled:
		pressed.content_margin_top = 9
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", _bordered("232f48", LINE, 1, 10))
	var tc := _ideal_text(accent) if enabled else C_MUTED
	b.add_theme_color_override("font_color", Color.html(tc))
	b.add_theme_color_override("font_color_hover", Color.html(tc))
	b.add_theme_color_override("font_color_pressed", Color.html(tc))
	b.add_theme_color_override("font_color_disabled", Color.html(C_MUTED))
	b.add_theme_font_size_override("font_size", _fs(13))
	return b

func _progress(v: VBoxContainer, active: bool, accent: String) -> void:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(0, 22)   # chunky conduit, not a hairline
	var bar := ProgressBar.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = 0
	_style_bar(bar, accent)
	wrap.add_child(bar)
	if not active:
		var lbl := Label.new()
		lbl.text = "READY"
		lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", _fs(9))
		lbl.add_theme_color_override("font_color", Color.html(accent))
		_embolden(lbl)
		wrap.add_child(lbl)
		# Shimmer: READY breathes. Node-bound tween — dies with the label on
		# rebuild, so it can't leak or fight the idle-loop no-rebuild guard.
		var tw := lbl.create_tween().set_loops()
		tw.tween_property(lbl, "modulate:a", 0.45, 0.9).set_trans(Tween.TRANS_SINE)
		tw.tween_property(lbl, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	v.add_child(wrap)
	if active:
		_active_bar = bar

func _skill_banner(v: VBoxContainer, title: String, skill_id: String, accent: String) -> void:
	var lvl := GameState.level_of(skill_id)
	var cur := int(GameState.skills.get(skill_id, 0))
	var base := GameState.xp_for_level(lvl)
	var next := GameState.xp_for_level(lvl + 1)
	var pct: float = 100.0 if next <= base else float(cur - base) / float(next - base) * 100.0
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _card_style(_mix(accent, SURFACE, 0.88), _mix(accent, LINE, 0.4), 1, true))
	# Oversized watermark glyph behind the content — page identity at a glance.
	var wm_glyph: String = {"harvesting": "↑", "fabrication": "⚙", "combat": "◎", "infrastructure": "⌂"}.get(skill_id, "✦")
	var wm_wrap := MarginContainer.new()
	wm_wrap.add_theme_constant_override("margin_right", 14)
	wm_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wm := Label.new()
	wm.text = wm_glyph
	wm.size_flags_horizontal = Control.SIZE_SHRINK_END
	wm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wm.add_theme_font_size_override("font_size", _fs(44))
	var wm_col := Color.html(accent)
	wm_col.a = 0.12
	wm.add_theme_color_override("font_color", wm_col)
	wm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wm_wrap.add_child(wm)
	panel.add_child(wm_wrap)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	var hb := HBoxContainer.new()
	var t := Label.new()
	t.text = title
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_font_size_override("font_size", _fs(14))
	t.add_theme_color_override("font_color", Color.html(accent))
	_embolden(t)
	hb.add_child(t)
	# Level MEDALLION — a circled display number instead of "Lv N" text.
	var medal := PanelContainer.new()
	medal.custom_minimum_size = Vector2(58, 58)
	medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var msb := StyleBoxFlat.new()
	msb.bg_color = Color.html(_mix(accent, INSET, 0.72))
	msb.set_corner_radius_all(29)
	msb.set_border_width_all(2)
	msb.border_color = Color.html(accent)
	var mglow := Color.html(accent)
	mglow.a = 0.35
	msb.shadow_color = mglow
	msb.shadow_size = 8
	medal.add_theme_stylebox_override("panel", msb)
	var mv := VBoxContainer.new()
	mv.alignment = BoxContainer.ALIGNMENT_CENTER
	mv.add_theme_constant_override("separation", 0)
	medal.add_child(mv)
	var lv := Label.new()
	lv.text = str(lvl)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_embolden(lv)
	lv.add_theme_font_size_override("font_size", _fs(19))
	lv.add_theme_color_override("font_color", Color.html(C_TEXT))
	mv.add_child(lv)
	var lvc := Label.new()
	lvc.text = "LV"
	lvc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvc.add_theme_font_size_override("font_size", _fs(7))
	lvc.add_theme_color_override("font_color", Color.html(accent))
	mv.add_child(lvc)
	hb.add_child(medal)
	box.add_child(hb)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 14)   # XP conduit — thick enough to read as a fixture
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = pct
	_style_bar(bar, accent)
	box.add_child(bar)
	var xpl := Label.new()
	xpl.text = "%s / %s XP" % [GameData.fmt(cur - base), GameData.fmt(next - base)]
	xpl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	xpl.add_theme_font_size_override("font_size", _fs(9))
	xpl.add_theme_color_override("font_color", Color.html(C_MUTED))
	box.add_child(xpl)
	v.add_child(panel)
	# Keep handles so _process can advance the XP bar/labels live (the page is
	# no longer rebuilt on every loop completion).
	_skill_bar = bar
	_skill_xp_label = xpl
	_skill_lv_label = lv
	_skill_medal = medal
	_skill_banner_id = skill_id

func _section(v: VBoxContainer, text: String, accent: String) -> Label:
	if text == "":
		return null
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 7)
	var tick := Panel.new()
	tick.custom_minimum_size = Vector2(3, 12)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color.html(accent)
	ts.set_corner_radius_all(2)
	tick.add_theme_stylebox_override("panel", ts)
	hb.add_child(tick)
	var l := Label.new()
	l.text = text.to_upper()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", _fs(11))
	l.add_theme_color_override("font_color", Color.html(C_DIM))
	_embolden(l)
	hb.add_child(l)
	# Console-style framing: a faint accent rule under the title.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.add_child(hb)
	var rule := ColorRect.new()
	rule.color = Color(Color.html(accent), 0.25)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)
	v.add_child(col)
	return l

func _connector(v: VBoxContainer) -> void:
	var c := CenterContainer.new()
	var line := ColorRect.new()
	line.color = Color.html(PURP)
	line.custom_minimum_size = Vector2(3, 14)
	c.add_child(line)
	v.add_child(c)

# Count a label's number from -> to over `dur` (event-driven; one tween per
# discrete gain, not per frame). Kills any prior count on the same label.
func _tween_number(l: Label, from: float, to: float, fmt: Callable, dur := 0.5) -> void:
	if l.has_meta("cnt_tw"):
		var old = l.get_meta("cnt_tw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	var tw := l.create_tween()
	l.set_meta("cnt_tw", tw)
	var setter := func(v: float) -> void:
		if is_instance_valid(l):
			l.text = str(fmt.call(v))
	tw.tween_method(setter, from, to, dur)

func _refresh_top() -> void:
	# Header shows credits only — material holdings live on the Storage page.
	if not is_instance_valid(_hdr_credits):
		return
	var now := GameState.credits
	if now == _hdr_credits_val:
		return   # de-dupe the high-frequency resources_changed churn
	var prev := _hdr_credits_val
	_hdr_credits_val = now
	if prev < 0:
		_hdr_credits.text = GameData.fmt(now)   # first paint: snap
		return
	if now > prev:
		# Earned: count up + pill pop. Gaining should feel earned.
		_tween_number(_hdr_credits, float(prev), float(now), func(v: float): return GameData.fmt(int(v)))
		if is_instance_valid(_hdr_cpill):
			_hdr_cpill.pivot_offset = _hdr_cpill.size / 2.0
			var tw := _hdr_cpill.create_tween()
			tw.tween_property(_hdr_cpill, "scale", Vector2(1.12, 1.12), 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(_hdr_cpill, "scale", Vector2(1.0, 1.0), 0.16)
	else:
		# Spent: snap immediately (spending must feel instant) + brief red tint.
		_hdr_credits.text = GameData.fmt(now)
		var tw2 := _hdr_credits.create_tween()
		_hdr_credits.modulate = Color(1.0, 0.5, 0.4)
		tw2.tween_property(_hdr_credits, "modulate", Color.WHITE, 0.3)

func _build_active_banner() -> PanelContainer:
	# HERO panel — the running action is the game's centerpiece, visible on every
	# page: big lit icon, bold name, and the production rate as a headline number.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bordered(INSET, LINE, 1, 12))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	panel.add_child(hb)
	_banner_chip = PanelContainer.new()
	_banner_chip.custom_minimum_size = Vector2(64, 64)
	_banner_chip.add_theme_stylebox_override("panel", _bordered(SURFACE_HI, LINE, 1, 12))
	var cc := CenterContainer.new()
	_banner_chip.add_child(cc)
	_banner_icon = Label.new()
	_banner_icon.add_theme_font_size_override("font_size", _fs(26))
	cc.add_child(_banner_icon)
	hb.add_child(_banner_chip)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vb.add_theme_constant_override("separation", 3)
	hb.add_child(vb)
	_banner_kind = Label.new()
	_banner_kind.add_theme_font_size_override("font_size", _fs(9))
	vb.add_child(_banner_kind)
	_banner_name = Label.new()
	_banner_name.add_theme_font_size_override("font_size", _fs(17))
	_banner_name.add_theme_color_override("font_color", Color.html(C_TEXT))
	_embolden(_banner_name)
	vb.add_child(_banner_name)
	_banner_bar = ProgressBar.new()
	_banner_bar.custom_minimum_size = Vector2(0, 10)
	_banner_bar.show_percentage = false
	_banner_bar.max_value = 100
	vb.add_child(_banner_bar)
	# Right column: the RATE as a headline number over the cycle countdown.
	var rcol := VBoxContainer.new()
	rcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rcol.add_theme_constant_override("separation", 0)
	_banner_rate = Label.new()
	_banner_rate.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_banner_rate.add_theme_font_size_override("font_size", _fs(19))
	_banner_rate.add_theme_color_override("font_color", Color.html(GREEN))
	_embolden(_banner_rate)
	rcol.add_child(_banner_rate)
	_banner_time = Label.new()
	_banner_time.custom_minimum_size = Vector2(46, 0)
	_banner_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_banner_time.add_theme_font_size_override("font_size", _fs(12))
	_banner_time.add_theme_color_override("font_color", Color.html(C_DIM))
	rcol.add_child(_banner_time)
	hb.add_child(rcol)
	return panel

func _refresh_banner() -> void:
	if _banner_icon == null:
		return
	var t := GameState.active_type
	var accent := C_MUTED
	var icon := "✦"
	var kind := "IDLE"
	var nm := "Tap an action to begin"
	if t == "gather":
		accent = GOLD; icon = "↑"; kind = "HARVESTING"; nm = GameData.GATHER[GameState.active_id]["name"]
	elif t == "craft":
		accent = CYAN; icon = "⚙"; kind = "ENGINEERING"; nm = GameData.CRAFT[GameState.active_id]["name"]
	elif t == "combat":
		accent = RED; icon = "◎"; kind = "IN COMBAT"
		# During a hazard gauntlet active_id is the hazard zone, not an enemy —
		# read the live enemy instance (or the hazard name) instead.
		if GameState.hazard_state.get("active", false):
			icon = "☢"; kind = "HAZARD"
			nm = String(GameState.enemy_inst.get("name", GameData.HAZARD_ZONES.get(GameState.active_id, {}).get("name", "Hazard")))
		else:
			nm = GameData.ENEMIES.get(GameState.active_id, {}).get("name", "Combat")
	_banner_icon.text = icon
	_banner_icon.add_theme_color_override("font_color", Color.html(accent))
	# The hero lights up when the factory is running: lit accent chip + tinted
	# panel; dim inset when idle.
	_banner_chip.add_theme_stylebox_override("panel", _bordered(_mix(accent, INSET, 0.62) if t != "" else SURFACE_HI, accent if t != "" else LINE, 1, 12))
	if is_instance_valid(active_banner):
		active_banner.add_theme_stylebox_override("panel", _bordered(_mix(accent, INSET, 0.90) if t != "" else INSET, _mix(accent, LINE, 0.45) if t != "" else LINE, 1, 12))
	# The rate is the hero number (right column), not a suffix on the kind line.
	if is_instance_valid(_banner_rate):
		_banner_rate.text = GameState.action_rate_text() if t != "" else "—"
		_banner_rate.add_theme_color_override("font_color", Color.html(GREEN if t != "" else C_MUTED))
	_banner_kind.text = kind
	_banner_kind.add_theme_color_override("font_color", Color.html(accent))
	_banner_name.text = nm
	_banner_name.add_theme_color_override("font_color", Color.html(C_TEXT if t != "" else C_DIM))
	_banner_bar.visible = t != ""        # collapse the bar's row when idle (tighter header)
	_style_bar(_banner_bar, accent)
	if t == "":
		_banner_time.text = ""
		_banner_bar.value = 0.0

# ============================================================ MODAL
func _show_offline(text: String) -> void:
	# Append any missions/orders that finished while away, so the welcome-back
	# report doubles as a "go claim these" checklist.
	var claim := _ready_to_claim_report()
	if claim != "":
		text = (text + "\n\n" if text.strip_edges() != "" else "") + claim
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	_track_modal(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bordered("121b2e", CYAN, 2, 16))
	panel.custom_minimum_size = Vector2(336, 0)
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	panel.add_child(outer)

	# ---- Header band: icon + branded title, on a darker inset bar ----
	var head := PanelContainer.new()
	var hsb := _bordered(_mix(CYAN, "0a1120", 0.84), _mix(CYAN, LINE, 0.45), 0, 14)
	hsb.corner_radius_bottom_left = 0
	hsb.corner_radius_bottom_right = 0
	hsb.content_margin_top = 18
	hsb.content_margin_bottom = 15
	head.add_theme_stylebox_override("panel", hsb)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 11)
	head.add_child(hb)
	var hicon := Label.new()
	hicon.text = "◷"
	hicon.add_theme_font_size_override("font_size", _fs(30))
	hicon.add_theme_color_override("font_color", Color.html(CYAN))
	hb.add_child(hicon)
	var htext := VBoxContainer.new()
	htext.add_theme_constant_override("separation", 0)
	hb.add_child(htext)
	var t1 := Label.new()
	t1.text = "WELCOME BACK"
	t1.add_theme_font_size_override("font_size", _fs(18))
	t1.add_theme_color_override("font_color", Color.html(CYAN))
	htext.add_child(t1)
	var t2 := Label.new()
	t2.text = "Commander"
	t2.add_theme_font_size_override("font_size", _fs(11))
	t2.add_theme_color_override("font_color", Color.html(C_DIM))
	htext.add_child(t2)
	outer.add_child(head)

	# ---- Body ----
	var mc := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + s, 15)
	outer.add_child(mc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	mc.add_child(v)

	# Parse the report. "Name\t+Qty" rows become icon rows; prefixed lines style
	# by kind (time-away pill, INFRASTRUCTURE / claim sections, ⚠ warnings).
	for raw in text.split("\n"):
		var line := String(raw)
		var stripped := line.strip_edges()
		if stripped == "":
			continue
		if stripped.begins_with("Away for "):
			var pc := CenterContainer.new()
			var pill := PanelContainer.new()
			var psb := _bordered(SURFACE_HI, _mix(CYAN, LINE, 0.5), 1, 11)
			psb.content_margin_left = 12
			psb.content_margin_right = 12
			psb.content_margin_top = 4
			psb.content_margin_bottom = 4
			pill.add_theme_stylebox_override("panel", psb)
			var pl := Label.new()
			pl.text = "◷  " + stripped.substr(9).strip_edges()
			pl.add_theme_font_size_override("font_size", _fs(12))
			pl.add_theme_color_override("font_color", Color.html(C_DIM))
			pill.add_child(pl)
			pc.add_child(pill)
			v.add_child(pc)
		elif stripped.begins_with("Infrastructure:"):
			# A comma-joined summary → a proper section with one row per yield.
			_section(v, "⌂  Infrastructure", BUILD)
			for piece in stripped.substr(15).split(","):
				var pz := String(piece).strip_edges()
				if pz == "":
					continue
				if pz.begins_with("+₡"):
					_off_row(v, "Credits", pz, GOLD, "")
				else:
					var sp := pz.find(" ")
					if sp > 0:
						_off_row(v, pz.substr(sp + 1), pz.substr(0, sp), GOLD, _sym_for_name(pz.substr(sp + 1)))
					else:
						_off_row(v, pz, "", GOLD, "")
		elif stripped.begins_with("★"):
			_section(v, stripped.substr(1).strip_edges(), GOLD)
		elif stripped.begins_with("⚠"):
			var wl := Label.new()
			wl.text = stripped
			wl.custom_minimum_size = Vector2(300, 0)
			wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			wl.add_theme_font_size_override("font_size", _fs(12))
			wl.add_theme_color_override("font_color", Color.html(C_WARN))
			v.add_child(wl)
		elif "\t" in line:
			var parts := line.split("\t")
			var nm: String = String(parts[0]).strip_edges()
			var amt: String = String(parts[1]).strip_edges() if parts.size() > 1 else ""
			if amt.ends_with("ready"):
				# Ready-to-claim (mission / standing order) — no material icon.
				_off_row(v, nm, "● READY", GOLD, "", CYAN)
			elif nm == "Credits":
				_off_row(v, nm, amt, GOLD, "")
			elif nm.ends_with("XP"):
				_off_row(v, nm, amt, GREEN, "")
			elif nm == "Modules":
				_off_row(v, nm, amt, PURP, "")
			else:
				_off_row(v, nm, amt, GOLD, _sym_for_name(nm))
		else:
			# Generic header line (e.g. "Destroyed 12 Raider").
			var hl := Label.new()
			hl.text = stripped
			hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hl.custom_minimum_size = Vector2(300, 0)
			hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hl.add_theme_font_size_override("font_size", _fs(12))
			hl.add_theme_color_override("font_color", Color.html(C_DIM))
			v.add_child(hl)

	var ok := _card_button("Collect", CYAN, true)
	ok.custom_minimum_size = Vector2(0, 50)
	ok.pressed.connect(func() -> void:
		_fly_to_credits(ok, "credits")
		overlay.queue_free())
	v.add_child(ok)

# One offline-report line: a recessed pill with an optional tinted material icon,
# the name (left) and the amount (right).
func _off_row(parent: VBoxContainer, item_name: String, amt: String, amt_col: String, sym: String, name_col := C_TEXT) -> void:
	var panel := PanelContainer.new()
	var sb := _bordered(INSET, LINE, 0, 8)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var icon: TextureRect = _mat_icon(sym, 20) if sym != "" else null
	if icon != null:
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
	else:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(20, 20)
		row.add_child(spacer)
	var nl := Label.new()
	nl.text = item_name
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nl.add_theme_font_size_override("font_size", _fs(13))
	nl.add_theme_color_override("font_color", Color.html(name_col))
	row.add_child(nl)
	var al := Label.new()
	al.text = amt
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	al.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	al.add_theme_font_size_override("font_size", _fs(13))
	al.add_theme_color_override("font_color", Color.html(amt_col))
	_embolden(al)
	row.add_child(al)
	parent.add_child(panel)
	# Count plain "+N" amounts up from 0, staggered by row — the report reads as
	# loot pouring in. K/M-suffixed and non-numeric amounts stay static, and only
	# the first ~12 rows animate so long reports don't turn into a light show.
	var ridx := parent.get_child_count()
	if ridx <= 12:
		var re := RegEx.new()
		re.compile("^\\+(₡?)(\\d+)$")
		var mm := re.search(amt)
		if mm != null:
			var mark := mm.get_string(1)
			var target := int(mm.get_string(2))
			var setter := func(v: float) -> void:
				if is_instance_valid(al):
					al.text = "+%s%d" % [mark, int(v)]
			var tw := al.create_tween()
			tw.tween_interval(0.06 * ridx)
			tw.tween_method(setter, 0.0, float(target), 0.6)

# ============================================================ TEXT
func _active_text() -> String:
	if GameState.active_type == "gather":
		return "▶ Harvesting: " + GameData.GATHER[GameState.active_id]["name"]
	elif GameState.active_type == "craft":
		return "▶ Crafting: " + GameData.CRAFT[GameState.active_id]["name"]
	elif GameState.active_type == "combat":
		if GameState.hazard_state.get("active", false):
			return "☢ Hazard: " + String(GameState.enemy_inst.get("name", "—"))
		return "▶ Engaging: " + GameData.ENEMIES.get(GameState.active_id, {}).get("name", "Combat")
	return "Idle — tap an action to begin"

func _req_text(def: Dictionary, skill: String) -> String:
	var parts := []
	if int(def.get("level_req", 1)) > 1:
		parts.append("Lv %d %s" % [int(def["level_req"]), _skill_label(skill)])
	var rr: String = def.get("research_req", "")
	if rr != "":
		parts.append("Research: " + GameData.RESEARCH.get(rr, {}).get("name", rr))
	if parts.is_empty():
		return "Locked"
	return "Requires " + ", ".join(parts)

func _hex(c: Color) -> String:
	return c.to_html(false)

# ============================================================ STYLE
func _bordered(bg: String, border: String, width := 2, radius := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color.html(bg)
	s.set_corner_radius_all(radius)
	s.set_border_width_all(width)
	s.border_color = Color.html(border)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

func _style_panel(p: Control, hex: String) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color.html(hex)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", s)

func _style_tab(b: Button, active: bool) -> void:
	b.add_theme_color_override("font_color", Color.html(CYAN if active else C_MUTED))
	b.add_theme_color_override("font_color_hover", Color.html(CYAN if active else C_DIM))
	b.add_theme_color_override("font_color_pressed", Color.html(CYAN))
	b.add_theme_font_size_override("font_size", _fs(12))
	var bgc := "16273f" if active else "00000000"
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.html(bgc)
		sb.set_corner_radius_all(8)
		b.add_theme_stylebox_override(state, sb)

# Compact per-action Mastery row on a gather/craft card (mirrors desktop
# gathering_action_widget formatting, adapted to the mobile card style): a caption
# row "MASTERY  LV n  ·  −x% time" + right teaser "in / needed ▸ LV m", and a thin
# progress bar. The ACTIVE card's nodes are captured into members for live refresh.
func _mastery_row(v: VBoxContainer, id: String, accent: String, active: bool) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var cap := HBoxContainer.new()
	var left := Label.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_font_size_override("font_size", _fs(8))
	cap.add_child(left)
	var right := Label.new()
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_theme_font_size_override("font_size", _fs(8))
	cap.add_child(right)
	box.add_child(cap)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 5)
	bar.show_percentage = false
	bar.max_value = 100
	_style_bar(bar, accent)
	box.add_child(bar)
	v.add_child(box)
	_fill_mastery_row(id, left, right, bar)
	# Tap the row to see the full milestone schedule (desktop's MASTERY tooltip).
	var tap := Button.new()
	tap.flat = true
	tap.focus_mode = Control.FOCUS_NONE
	tap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tap.pressed.connect(_open_mastery_schedule.bind(id))
	box.add_child(tap)
	if active:
		_mastery_id = id
		_mastery_left = left
		_mastery_right = right
		_mastery_bar = bar

# Shared text/value fill so the static build and the live _process refresh agree.
func _fill_mastery_row(id: String, left: Label, right: Label, bar: ProgressBar) -> void:
	var level := GameState.mastery_level(id)
	var prog := GameState.mastery_progress(id)
	var in_lvl := int(prog["in_level"])
	var needed := maxi(1, int(prog["needed"]))
	var pct := clampf(float(in_lvl) / float(needed) * 100.0, 0.0, 100.0)
	var bonus_pct := int(round((1.0 - GameState.mastery_dur_mult(id)) * 100.0))
	var suffix := ("  ·  −%d%% time" % bonus_pct) if bonus_pct > 0 else ""
	var next_m := GameState.next_mastery_milestone(id)
	# Brighten with progress so a leveled action reads as "alive" vs a fresh one.
	var col := C_MUTED
	if level >= 100:
		col = GOLD
	elif level >= 50:
		col = GOLD
	elif level > 0:
		col = C_DIM
	if level >= 100:
		left.text = "MASTERY ⓘ  LV 100  ✓%s" % suffix
		right.text = "LV 100 ✓"
		bar.value = 100.0
	else:
		left.text = "MASTERY ⓘ  LV %d%s" % [level, suffix]
		right.text = "%d / %d  ▸  LV %d" % [in_lvl, needed, next_m]
		bar.value = pct
	left.add_theme_color_override("font_color", Color.html(col))
	right.add_theme_color_override("font_color", Color.html(col))

## Milestone schedule popup (desktop's tappable MASTERY tooltip): lists every
## mastery milestone and its speed bonus, marking the ones already reached.
func _open_mastery_schedule(id: String) -> void:
	_modal("MASTERY", GOLD, _mastery_schedule_body.bind(id), "★")

func _mastery_schedule_body(v: VBoxContainer, _close: Callable, id: String) -> void:
	var nm := ""
	if GameData.GATHER.has(id):
		nm = GameData.GATHER[id].get("name", id)
	elif GameData.CRAFT.has(id):
		nm = GameData.CRAFT[id].get("name", id)
	var level := GameState.mastery_level(id)
	var cur_bonus := int(round((1.0 - GameState.mastery_dur_mult(id)) * 100.0))
	_clbl(v, nm, 13, C_TEXT)
	_big_stat(v, str(level), "MASTERY LV", GOLD, 24)
	_clbl(v, "−%d%% action time now" % cur_bonus, 11, GOLD if cur_bonus > 0 else C_DIM)
	_clbl(v, "Each completion earns +1 Mastery XP (online & offline). Faster actions at every milestone:", 10, C_DIM)
	var lines := []
	var ms: Array = GameState.MASTERY_MILESTONES
	var tbl: Array = GameState.MASTERY_DURATION_BONUS_TABLE
	for i in ms.size():
		var m: int = int(ms[i])
		var red := int(round(float(tbl[i + 1]) * 100.0)) if (i + 1) < tbl.size() else 0
		var done := level >= m
		var mark := "✓ " if done else "•  "
		var col: String = (GOLD if m >= 50 else GREEN) if done else C_MUTED
		lines.append(_line("%sLv %-3d  −%d%% action time" % [mark, m, red], col))
	_inset(v, "MILESTONES", lines, GOLD)

# Slider in the conduit language: recessed track, glowing accent fill area.
func _style_slider(sl: Slider, accent: String) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color.html(INSET)
	track.set_corner_radius_all(4)
	track.set_border_width_all(1)
	track.border_color = Color.html(LINE)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color.html(accent)
	fill.set_corner_radius_all(4)
	var glow := Color.html(accent)
	glow.a = 0.5
	fill.shadow_color = glow
	fill.shadow_size = 4
	sl.add_theme_stylebox_override("slider", track)
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)

func _style_bar(b: ProgressBar, accent: String) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color.html("0a1120")
	bg.set_corner_radius_all(6)
	bg.set_border_width_all(1)
	bg.border_color = Color.html(LINE)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color.html(accent)
	fg.set_corner_radius_all(6)
	# Energy-glow on the fill — bars read as charged conduits. A lighter top
	# edge on the fill fakes a lit gradient (StyleBoxFlat has no gradients).
	fg.border_width_top = 2
	fg.border_color = Color.html(_mix(accent, "ffffff", 0.55))
	var glow := Color.html(accent)
	glow.a = 0.6
	fg.shadow_color = glow
	fg.shadow_size = 5
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)

# ---- Gradient card surface (art-direction pass) ----
# StyleBoxFlat can't do gradients, so cards use a generate-once 9-slice texture:
# vertical light-to-dark gradient fill, 1px border, and (when elevated) an accent
# halo baked into a transparent padding ring that draws OUTSIDE the control via
# expand margins. Cached per (bg, border, elevated) — ~a dozen combos.
var _surface_tex_cache := {}

func _surface_tex(bg: String, border: String, elevated: bool) -> ImageTexture:
	var key := "%s|%s|%d" % [bg, border, 1 if elevated else 0]
	if _surface_tex_cache.has(key):
		return _surface_tex_cache[key]
	var sz := 64
	var pad := 10
	var radius := 14.0
	var full := sz + pad * 2
	var img := Image.create(full, full, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# _mix lerps TOWARD the second color: subtle 6% top light, 8% bottom shade.
	var top := Color.html(_mix(bg, "ffffff", 0.06))
	var bot := Color.html(_mix(bg, "000000", 0.08))
	var bc := Color.html(border)
	var halo := Color.html(border)
	var half := sz / 2.0
	var cx := full / 2.0
	for y in full:
		var t := clampf((y - pad) / float(sz), 0.0, 1.0)
		var fill := top.lerp(bot, t)
		for x in full:
			# Rounded-rect signed distance from the inner 64x64 box.
			var qx := absf(x + 0.5 - cx) - (half - radius)
			var qy := absf(y + 0.5 - cx) - (half - radius)
			var dist := Vector2(maxf(qx, 0.0), maxf(qy, 0.0)).length() + minf(maxf(qx, qy), 0.0) - radius
			if dist <= -1.5:
				img.set_pixel(x, y, fill)
			elif dist <= 0.0:
				img.set_pixel(x, y, bc)
			elif elevated and dist < pad:
				var a := 0.30 * pow(1.0 - dist / pad, 2.0)
				img.set_pixel(x, y, Color(halo.r, halo.g, halo.b, a))
	var tex := ImageTexture.create_from_image(img)
	_surface_tex_cache[key] = tex
	return tex

func _surface_style(bg: String, border: String, elevated: bool) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = _surface_tex(bg, border, elevated)
	# 9-slice: corner regions cover pad+radius so they never stretch; the middle
	# band's linear gradient stretches cleanly. Expand margins push the baked halo
	# ring outside the control rect (transparent ring = no-op for non-elevated).
	var m := 10 + 14
	s.texture_margin_left = m
	s.texture_margin_right = m
	s.texture_margin_top = m
	s.texture_margin_bottom = m
	s.expand_margin_left = 10
	s.expand_margin_right = 10
	s.expand_margin_top = 10
	s.expand_margin_bottom = 10
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s

# The ACTIVE card breathes — a slow warm modulate pulse says "this is running"
# at a glance. Modulate only (NEVER tween a stylebox: they're shared cached
# resources and would light every card). Node-bound: rebuilds auto-kill it.
func _breathe_active(panel: Control) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	var tw := panel.create_tween().set_loops()
	tw.tween_property(panel, "modulate", Color(1.10, 1.08, 1.0, 1.0), 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_property(panel, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.8).set_trans(Tween.TRANS_SINE)

# ---- Design helpers ----
func _card_style(bg: String, border: String, width := 1, elevated := false) -> StyleBoxFlat:
	var s := _bordered(bg, border, width, 14)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	if elevated:
		# Lit surface: the card FILL carries a whisper of its accent (not just the
		# border), and the neon halo is stronger — unlocked content radiates.
		s.bg_color = Color.html(_mix(border, bg, 0.93))
		var glow := Color.html(border)
		glow.a = 0.30
		s.shadow_color = glow
		s.shadow_size = 12
		s.shadow_offset = Vector2(0, 0)
	else:
		s.shadow_color = Color(0, 0, 0, 0.30)
		s.shadow_size = 4
		s.shadow_offset = Vector2(0, 2)
	return s

func _hud_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color.html("0f1830")
	s.border_width_bottom = 1
	s.border_color = Color.html(LINE)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 2)
	return s

func _nav_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color.html("0f1830")
	s.border_width_top = 1
	s.border_color = Color.html(LINE)
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

func _grad_tex(top: String, bot: String) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color.html(top))
	g.set_color(1, Color.html(bot))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 8
	tex.height = 256
	return tex

var _space_cache: ImageTexture = null
var _star_layer_cache: ImageTexture = null

## Sparse transparent star layer for the slow parallax drift.
func _star_layer_tex() -> ImageTexture:
	if _star_layer_cache != null:
		return _star_layer_cache
	var w := 720
	var h := 1280
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for _i in range(130):
		var x := rng.randi_range(0, w - 2)
		var y := rng.randi_range(0, h - 2)
		var lum := rng.randf_range(0.4, 1.0)
		var col := Color(lum, lum, lum * 1.05, rng.randf_range(0.35, 0.8))
		img.set_pixel(x, y, col)
		if lum > 0.8:
			img.set_pixel(x + 1, y, Color(col.r, col.g, col.b, col.a * 0.6))
	_star_layer_cache = ImageTexture.create_from_image(img)
	return _star_layer_cache

## Procedural deep-space backdrop: vertical gradient + nebula blooms + starfield.
## Generated once and cached — this is what makes the app read as a *game*.
func _space_tex() -> ImageTexture:
	if _space_cache != null:
		return _space_cache
	var w := 720
	var h := 1280
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var top := Color.html(BG_TOP)
	var bot := Color.html(BG_BOT)
	var band := 8
	for y in range(0, h, band):
		img.fill_rect(Rect2i(0, y, w, band), top.lerp(bot, float(y) / float(h)))
	# Nebula blooms — soft radial tints in the brand colours.
	var blobs := [
		[Vector2i(560, 160), 460, Color(0.45, 0.30, 0.85, 0.07)],
		[Vector2i(90, 760), 520, Color(0.20, 0.65, 0.80, 0.05)],
		[Vector2i(420, 1180), 420, Color(0.85, 0.55, 0.25, 0.04)],
	]
	for bdef in blobs:
		var bsize: int = bdef[1]
		var grad := Gradient.new()
		grad.set_color(0, bdef[2])
		grad.set_color(1, Color(bdef[2].r, bdef[2].g, bdef[2].b, 0.0))
		var rt := GradientTexture2D.new()
		rt.gradient = grad
		rt.fill = GradientTexture2D.FILL_RADIAL
		rt.fill_from = Vector2(0.5, 0.5)
		rt.fill_to = Vector2(0.5, 0.0)
		rt.width = bsize
		rt.height = bsize
		var bimg := rt.get_image()
		bimg.convert(Image.FORMAT_RGBA8)
		img.blend_rect(bimg, Rect2i(0, 0, bsize, bsize), bdef[0] - Vector2i(bsize / 2, bsize / 2))
	# Starfield — deterministic so every launch looks the same.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20771
	for _i in range(420):
		var x := rng.randi_range(0, w - 2)
		var y2 := rng.randi_range(0, h - 2)
		var lum := rng.randf_range(0.25, 1.0)
		var tint := rng.randf()
		var col := Color(lum, lum, lum * 1.06, rng.randf_range(0.5, 1.0))
		if tint < 0.12:
			col = Color(lum * 0.7, lum * 0.9, lum, col.a)        # cool blue
		elif tint > 0.92:
			col = Color(lum, lum * 0.85, lum * 0.6, col.a)       # warm gold
		img.set_pixel(x, y2, col)
		if lum > 0.82:
			img.set_pixel(x + 1, y2, Color(col.r, col.g, col.b, col.a * 0.7))
			img.set_pixel(x, y2 + 1, Color(col.r, col.g, col.b, col.a * 0.7))
	# A handful of hero stars with a cross flare.
	for _j in range(7):
		var hx := rng.randi_range(4, w - 5)
		var hy := rng.randi_range(4, h - 5)
		var hc := Color(1, 1, 1, 0.9)
		img.set_pixel(hx, hy, hc)
		for d in range(1, 3):
			var fa := 0.45 / d
			img.set_pixel(hx + d, hy, Color(1, 1, 1, fa))
			img.set_pixel(hx - d, hy, Color(1, 1, 1, fa))
			img.set_pixel(hx, hy + d, Color(1, 1, 1, fa))
			img.set_pixel(hx, hy - d, Color(1, 1, 1, fa))
	_space_cache = ImageTexture.create_from_image(img)
	return _space_cache

func _mix(a: String, b: String, t: float) -> String:
	return Color.html(a).lerp(Color.html(b), t).to_html(false)

## Dark text on bright accents, light text on dark ones — keeps CTAs legible.
func _ideal_text(accent: String) -> String:
	var c := Color.html(accent)
	var lum := 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
	return "0b1220" if lum > 0.55 else "f4f7fc"
