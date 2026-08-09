extends RefCounted

# Verbose per-tick mission-progress tracing. Off in production (and during
# headless balance-sim runs, where it would emit tens of thousands of lines).
const DEBUG_LOG := false

# v134: added the mid-chapter beats (m027b bounty intro, m029a1-a5 AdvCircuit
# arc, m030i/m032a boss-core farms) — they sat between [CHAPTER 2] missions but
# rendered as [TUTORIAL], which read as the game mislabeling its own acts.
const CHAPTER_2_IDS = ["m027", "m027b", "m028", "m029",
	"m029a1", "m029a2", "m029a3", "m029a4", "m029a5", "m029a6", "m029a6t", "m029a7", "m029a8", "m029a9", "m029b", "m030", "m030c",
	"m030c2", "m030c3", "m030d", "m030e", "m030f", "m030fa", "m030fb", "m030f1", "m030f2", "m030g", "m030h", "m030i",
	"m031", "m032", "m032a", "m032b", "m032d", "m032c", "m033"]
# v134g: the reordered tail runs m034 → m033b → m033c, so the [ENDGAME] tag must
# cover all three — otherwise the badge reads [ENDGAME] then two [CHAPTER 2] after it.
const ENDGAME_IDS = ["m034", "m033b", "m033c"]

var missions = {}
var active_missions = []

signal mission_updated()

func _init():
	init_missions()

func connect_signals():
	if GameState.resources:
		if not GameState.resources.element_added.is_connected(_on_element_added):
			GameState.resources.element_added.connect(_on_element_added)
		if not GameState.resources.currency_added.is_connected(_on_currency_added):
			GameState.resources.currency_added.connect(_on_currency_added)
			
	if GameState.research_manager:
		if not GameState.research_manager.tech_unlocked.is_connected(_on_tech_unlocked):
			GameState.research_manager.tech_unlocked.connect(_on_tech_unlocked)
			
	if GameState.shipyard_manager:
		if not GameState.shipyard_manager.module_crafted.is_connected(_on_module_crafted):
			GameState.shipyard_manager.module_crafted.connect(_on_module_crafted)
		if not GameState.shipyard_manager.hull_constructed.is_connected(_on_hull_constructed):
			GameState.shipyard_manager.hull_constructed.connect(_on_hull_constructed)
		if not GameState.shipyard_manager.inventory_updated.is_connected(_on_shipyard_updated):
			GameState.shipyard_manager.inventory_updated.connect(_on_shipyard_updated)
		if not GameState.shipyard_manager.hack_stone_applied.is_connected(_on_hack_stone_applied):
			GameState.shipyard_manager.hack_stone_applied.connect(_on_hack_stone_applied)
			
	if GameState.combat_manager:
		if not GameState.combat_manager.enemy_defeated.is_connected(_on_enemy_defeated):
			GameState.combat_manager.enemy_defeated.connect(_on_enemy_defeated)
		if not GameState.combat_manager.zone_entered.is_connected(_on_zone_entered):
			GameState.combat_manager.zone_entered.connect(_on_zone_entered)
			
	if GameState.infrastructure_manager:
		if not GameState.infrastructure_manager.building_constructed.is_connected(_on_building_constructed):
			GameState.infrastructure_manager.building_constructed.connect(_on_building_constructed)
		if not GameState.infrastructure_manager.boost_card_installed.is_connected(_on_boost_card_installed):
			GameState.infrastructure_manager.boost_card_installed.connect(_on_boost_card_installed)
			
	sync_progress()

func init_missions():
	missions.clear()
	active_missions.clear()
	
	# Tutorial Missions Sequence
	# Structure: [id, name, description, type, target, target_qty, reward_cr, reward_xp, next_mission_id]
	var m_list = [
		# ID, Name, Desc, Type, Target, TargetQty, RewardCr, RewardXP, NextID
		["m001", "Stranded in Orbit", "Gather 350 Dirt.", "gather", "Dirt", 350, 600, 50, "m004"],
		# P-onboard: a single foundational research. Applied Physics + Fluid Dynamics were
		# folded into Basic Engineering, so one research opens refining, water, and the
		# ship/combat screens. m002b/m003 below are re-pointed to basic_engineering so any
		# in-flight save mid-chain auto-completes.
		["m002", "Foundational Research", "You have raw Dirt and Water and nothing to do with them. Open the Research tab and unlock Basic Engineering.", "research", "basic_engineering", 1, 900, 200, "m005"],
		# P0-30: Physics Paradox Fix - Applied Physics moved here
		["m002b", "Foundational Research", "Unlock Basic Engineering in the Research tab.", "research", "basic_engineering", 1, 300, 100, "m003"],
		["m003", "Pump Master", "Unlock Basic Engineering in the Research tab.", "research", "basic_engineering", 1, 300, 50, "m004"],
		["m004", "Hydration", "Gather 350 units of Water.", "gather", "Water", 350, 500, 100, "m002"],
		["m005", "Mineral Washing", "Open the Engineering page and process Dirt to extract 100 Silicon and 80 Iron.", "gather_multi", {"Si": 100, "Fe": 80}, 180, 1000, 200, "m005b"],

		# v134g: POWER-FIRST onboarding. The battery-only model means every module
		# draws power, so the FIRST loadout lesson is batteries — craft + equip 2
		# BEFORE the engine, so the engine visibly draws from them (was: engine
		# first, powered by invisible starter batteries; the old battery-equip step
		# m022b auto-completed because those starter batteries pre-filled the slots).
		# New games start UNPOWERED (see shipyard reset); warps keep starter batteries.
		["m005b", "Power Cells", "Your corvette is UNPOWERED — every module you equip draws power, and batteries supply it. In the Shipyard, craft 2 'Basic Battery' modules.", "craft", "z1_battery", 2, 1500, 200, "m005c"],
		["m005c", "Power Online", "Open the Ship Designer and equip BOTH Basic Batteries into the ship's BATTERY slots. Watch the GRID fill — now the ship can run modules.", "loadout_check", "battery", 2, 800, 150, "m007"],

		# m006 Removed (Moved to m002b)
		["m007", "Mobility Check", "Craft a 'Basic Thruster' in the Shipyard.", "craft", "z1_engine", 1, 1000, 100, "m007b"],
		# P1 Onboarding: close the engine arc — craft → equip. Without this the
		# Thruster sat in inventory and the player never saw its +Evasion effect.
		["m007b", "Spacewalk Test", "Open the Ship Designer, then DRAG the Basic Thruster from your Armory (right panel) onto an empty ENGINE slot.", "loadout_check", "engine", 1, 500, 100, "m009"],
		# v145 (D): ORPHANED (m007b → m009). Materials Science costs 625 Liras, has NO
		# cost_items, unlocks NOTHING, and its only effect is a hidden +10% ship max HP —
		# so this beat sat between "equip your thruster" and "chop wood" and changed
		# nothing the player could see. Its real job is being the tree parent of
		# combustion → smelting, first needed ~17 missions later at m025, so that is where
		# it is now named (see m025's text). The TECH stays in the tree untouched; only
		# the mission stop is removed. Kept DEFINED for in-flight saves (the m003 pattern):
		# a player sitting on m008 still completes it and still chains onward to m009.
		["m008", "Materials Science", "Research the 'Materials Science' hub.", "research", "materials_science", 1, 300, 100, "m009"],
		# v129: research-trip diet — the tutorial routed to Research ~8 times before the
		# first boss, which reads as homework. Five stops are cut from the CHAIN (m010,
		# m020, m014, m023, m018b) and the T1 starter-kit gates they served were unbound
		# (battery/missile recipes, T1 ammo equip). The missions stay DEFINED as orphans
		# so in-flight saves sitting on them still complete + chain onward (m003 pattern).
		# Research beats that remain early: m002 (tutorial), m008 (hub), m018, m025/m026
		# (batched: smelting -> power_systems -> shipwright_1 in one visit).
		["m009", "Deforestation", "Gather 100 units of Wood.", "gather", "Wood", 100, 500, 100, "m011"],
		["m010", "Organic Combustion", "Research 'Organic Combustion' to unlock the Industrial Kiln, Carbon Fiber, and combustion-powered generators. (The manual Charcoal Kiln needs no research.)", "research", "combustion", 1, 500, 150, "m011"],
		# v145 (E): m011-m013c was a five-step shopping run with no stated purpose. The
		# NUMBERS were already a perfect chain — the game just never said so:
		#   m011  50 Carbon    -> smelt_copper burns 1 C per Cu, so 50 C = the 50 Cu below
		#   m012 100 Spodumene -> refine_lithium is 2:1, so 100 ore = the 50 Li below
		#   m013  50 Lithium   -> craft_battery_t1 is 5 Li each; m024b's 5 Shield Boosters
		#                         need 5 Battery Cells = 25 Li, rest keeps for m029a3
		#   m013b 100 Malachite-> smelt_copper is 2:1, so 100 ore = the 50 Cu below
		#   m013c 50 Copper    -> 2 Micro-Missile Launchers (m017c) = 20 Cu
		#                         + 10 Circuit Boards (m019) x 3 Cu = 30 Cu. Exactly 50.
		# So this is a pure reword — every quantity stays, each one now names its consumer.
		["m011", "Essential Carbon", "In the Engineering page, use the Charcoal Kiln to produce 50 Carbon. Copper smelting burns one Carbon per unit, and the copper run coming up needs all 50.", "gather", "C", 50, 600, 150, "m012"],
		["m012", "Lithium Discovery", "In the Mine page, extract 100 Lithium Ore. It refines two-to-one, so this is the 50 Lithium your battery cells will need.", "gather", "Spodumene", 100, 800, 200, "m013"],
		# v145 (E): retitled. "Voltaic Storage" pointed at a payoff that no longer exists —
		# the ship's Basic Battery costs Liras + Iron and NO lithium, and both batteries
		# were already built and equipped at m005b/m005c. The v134g power-first reorder
		# orphaned the old Li -> Battery Cell beat (m021) and left this mission's name
		# aimed at nothing. Its real consumer is the Battery Cell inside the Shield
		# Boosters at m024b, so say that instead.
		["m013", "Battery Electrolyte", "Refine 50 Lithium in the Engineering tab. Lithium is the electrolyte in Battery Cells — the shield repair kits you craft before your first fight each need one.", "gather", "Li", 50, 1000, 250, "m013b"],
		["m013b", "Copper Prospecting", "Gather 100 Malachite Ore. It smelts two-to-one, one Carbon per unit — exactly the 50 Copper and the 50 Carbon you stocked.", "gather", "Malachite", 100, 1200, 300, "m013c"],
		# v134g: batteries are now taught up front (m005b/m005c), so the old battery
		# block (m020/m021/m022/m022b) is redundant — skip straight to the weapon
		# arc. Those missions stay DEFINED below as orphans so in-flight saves sitting
		# on them still complete + chain onward (the m003 pattern).
		["m013c", "Conductivity", "Refine 50 Copper in the Engineering tab. 20 goes into the pair of Micro-Missile Launchers you will build, the other 30 into your first Circuit Boards.", "gather", "Cu", 50, 1500, 350, "m015"],
		["m014", "Ballistics Theory", "Research 'Kinetic Weapons Theory' in the Research tree.", "research", "kinetics_101", 1, 1200, 100, "m015"],
		# v134g: craft 2 of each weapon type — the corvette has 2 WEAPON slots, so
		# filling both (double DPS) is the difference between comfortable and painful
		# early fights. The equip step below requires both slots filled.
		["m015", "Prototype Arsenal", "Craft 2 'Mass Driver Mk.I' in the Shipyard.", "craft", "z1_kinetic", 2, 1500, 200, "m015b"],
		# P1 Onboarding: close the weapon arc — craft → equip. Ammo comes next
		# and now reads correctly as "feed your equipped weapon".
		["m015b", "Weapons Hot", "Open the Ship Designer and equip BOTH Mass Drivers into your two WEAPON slots — twice the guns, twice the DPS.", "loadout_check", "weapon", 2, 500, 100, "m016"],
		["m016", "Kinetic Munitions", "In the Engineering page, produce 100 Ferrite Rounds to feed both your weapons.", "gather", "SlugT1", 100, 1000, 100, "m024"],
		# Shield Section Moved Here (m023 -> m024)
		# P2-12: Combat Readiness Checkpoint - ensure player is equipped before first combat
		["m016b", "Combat Ready", "Equip a WEAPON and SHIELD in your Ship Designer.", "loadout_check", "combat_ready", 1, 300, 100, "m017"],
		# v143: two-step. Combat keeps running after the kill, so a new player would
		# wander off to gather or craft with the ship still trading fire and come back
		# to a wreck. The kill alone no longer completes it — they must also pull out,
		# which teaches Retreat at the first moment it matters instead of letting a
		# death teach it. Progress still reads as the kill; the retreat is the gate.
		["m017", "Target Locked", "Defeat 1 Lunar Drone in Lunar Orbit, then click RETREAT to pull your ship out.", "defeat_retreat", "z1_lunar_drone", 1, 2500, 500, "m018"],
		# v128: damage-triangle onboarding. The Lunar Drone (m017) taught KINETIC; this
		# pair teaches ENERGY against the energy-weak Survey Probe (resist_e -0.30, resists
		# kinetic +0.30). The EXPLOSIVE leg is the Scrap Collector pair (m017c/d).
		# (v131: the Rogue Architect boss has NO resists — pure rarity check.)
		["m017a", "Energy Doctrine", "Not every hostile falls to slugs. The Silicate Golem in the Asteroid Belt RESISTS kinetic fire but is WEAK TO ENERGY. In the Shipyard, craft 2 'Pulse Laser Mk.I'", "craft", "z1_energy", 2, 1500, 200, "m017a2"],
		# v134: energy leg now mirrors the kinetic leg (craft -> produce ammo -> equip & fight).
		# It used to jump from craft straight to "destroy with Focus Crystals loaded" with NO
		# step that made the player PRODUCE the ammo — so a correctly-built laser fought empty.
		["m017a2", "Charge the Crystals", "The Pulse Laser runs on Focus Crystals. In the Engineering tab, produce 60 Focus Crystals", "gather", "CellT1", 60, 1500, 200, "m017b"],
		["m017b", "Pulse Fire", "Keep builds in separate slots: click LOADOUT 2, equip BOTH Pulse Lasers there, then destroy a Silicate Golem in the Asteroid Belt.", "defeat", "z2_silicate_golem", 1, 3000, 500, "m027b"],
		# v128: EXPLOSIVE leg — the Scrap Collector is now armored vs kinetic + energy and
		# WEAK to explosive (resist_x -0.30), so all three types are taught against regular
		# Lunar Orbit enemies. v129: T1 missiles + the launcher no longer require combustion
		# (research gate removed), so they craft here freely; combustion is first taught at m025.
		["m017c", "Explosive Doctrine", "The Scavenger Mech in Mars Debris is armored against kinetic but blows apart under EXPLOSIVE ordnance. In the Shipyard, craft 2 'Micro-Missile Launcher'", "craft", "z1_missile", 2, 1800, 250, "m017c2"],
		# v134: explosive leg scaffolds ammo like the others. It used to go craft ->
		# "destroy with HE Missiles loaded" with NO produce-ammo step (and equip_module
		# auto-loaded a phantom "missile" ammo id instead of MissileT1 — both now fixed).
		["m017c2", "Stock the Warheads", "The launcher fires Missiles. In the Engineering tab, produce 60 HE Missiles.", "gather", "MissileT1", 60, 1800, 250, "m017d"],
		["m017d", "Warhead", "Click LOADOUT 3, equip BOTH Micro-Missile Launchers there, then destroy a Scavenger Mech in Mars Debris. Kinetic / Energy / Explosive now live in Loadouts 1 / 2 / 3 — before a fight, one click swaps your WHOLE ship modules.", "defeat", "z3_scavenger_mech", 1, 3500, 600, "m030f"],
		["m018", "Industrial Logistics", "Research the 'Industrial Logistics' hub.", "research", "industrial_logistics", 1, 500, 100, "m018t1"],
		# v136: automated_logistics tech removed (collapsed). This already-orphaned beat
		# retargets to industrial_logistics so any in-flight save on it auto-completes.
		["m018b", "Automated Intelligence", "Research the 'Industrial Logistics' hub.", "research", "industrial_logistics", 1, 1000, 200, "m018t1"],
		# v139c: the Circuit recipe needs TIN (Sn), but Cassiterite mining was only
		# TAUGHT at m028 — nine missions AFTER m019 demanded it. The v134 text-only fix
		# (naming Tin inside m019) left the player bounced between "need Circuit" and
		# "need Tin" with no guided path ("rotates around tin and circuit board").
		# Fixed like the m029 AdvCircuit wall: explicit ordered sub-steps that mine the
		# ore and smelt the Tin BEFORE the Circuit craft. So the flow reads
		# ore → tin → circuit instead of dropping a hidden input on the player.
		["m018t1", "Tin Prospecting", "In the Mine page, extract 40 Cassiterite (tin ore). It smelts into the Tin your circuits will need.", "gather", "Cassiterite", 40, 1500, 200, "m018t2"],
		["m018t2", "Tin Smelting", "In the Engineering tab, smelt Cassiterite into 24 Tin (Sn) — the 'Tin Smelting' recipe (it also uses a little Carbon).", "gather", "Sn", 24, 1500, 200, "m019"],
		["m019", "Cybernetic Integration", "Craft 10 Circuit Boards in the Engineering tab — they use the Tin you just smelted, plus Copper and Silicon.", "gather", "Circuit", 10, 2000, 300, "m019b"],
		# P-onboard: close two long-standing teaching holes before the smelting push.
		# Both are visit_page (auto-complete on navigation → can never soft-lock) and
		# fire the existing per-page coach card the moment the player lands.
		["m019b", "Cargo Hold", "Open your Inventory (left sidebar). Cargo is slot-limited — when it fills, new materials are LOST, not paused. Expand storage here as you grow.", "visit_page", "inventory", 1, 2000, 200, "m019c"],
		["m019c", "Background Industry", "Open Infrastructure (left sidebar). Buildings auto-produce in the background — always running, even offline. Build them whenever you can.", "visit_page", "infrastructure", 1, 2000, 200, "m019d"],
		# v135: the player-bot sim proved a mission-literal player owns ZERO
		# buildings after 14 days (6M Liras unspent) — m019c only VISITS the page.
		# One cheap directed build closes the teaching hole; "build" completes on
		# building_constructed + sync (retroactive-safe, can never soft-lock).
		["m019d", "First Foundation", "Construct a Solar Array in Infrastructure — it generates power and keeps running even while you're away.", "build", "solar_panel", 1, 2500, 200, "m019e"],
		# Atlas-lookup teaching beat — inserted BEFORE the first material the player
		# can't hand-gather: Efficient Smelting (m025) and Shipwright I (m026) both cost
		# COMMON ARTIFACT (Res1), a COMBAT drop with no obvious source. Teaches the
		# universal skill "trace any unknown material to its source in the Atlas".
		# Completes when the player opens Res1's Atlas entry (atlas_lookup) — event-
		# driven like visit_page, so it can never soft-lock. atlas_page fires the
		# progress + glows the SOURCED FROM panel + pops a coach card on that open.
		["m019e", "Field Manual", "The next research, Efficient Smelting, needs COMMON ARTIFACT — a material you don't craft or mine. When a mission names something you don't recognise, the ATLAS shows where it comes from. Open the Atlas (left sidebar), switch to the MATERIALS tab, type \"Common Artifact\" in the search box, and open its entry to see which enemies drop it.", "atlas_lookup", "Res1", 1, 2000, 150, "m025"],
		["m020", "Advanced Energy", "Research 'Power Systems' for batteries.", "research", "power_systems", 1, 500, 100, "m021"],
		["m021", "Industrial Energy", "Craft 5 Battery Cells in the Engineering tab.", "gather", "BatteryT1", 5, 1000, 100, "m022"],
		["m022", "Power Storage", "Craft a 'Basic Battery' in the Shipyard.", "craft", "z1_battery", 1, 1500, 150, "m022b"],
		# P1 Onboarding: close the energy arc — craft → equip. Without this the
		# Battery was a one-and-done craft with no ship-state payoff.
		["m022b", "Power Online", "Open the Ship Designer, then DRAG the Basic Battery from your Armory (right panel) onto an empty BATTERY slot.", "loadout_check", "battery", 1, 500, 100, "m015"],
		["m023", "Hull Integrity", "Research 'Energy Fields' to unlock shielding.", "research", "energy_shields", 1, 1000, 150, "m024"],
		["m024", "Aegis System", "Craft a 'Basic Shield' for protection.", "craft", "z1_shield", 1, 2500, 200, "m024c"],
		# P1 Onboarding: close the shield arc — craft → equip. Player sees
		# max_shield jump from 0 → positive the moment it seats.
		["m024c", "Shields Up", "Open the Ship Designer, then DRAG the Basic Shield from your Armory (right panel) onto an empty SHIELD slot. Incoming damage hits the shield before your hull.", "loadout_check", "shield", 1, 500, 100, "m024a1"],
		# v140: armor arc mirrors the shield arc (craft → equip). The corvette's ARMOR
		# slot sat empty through the whole tutorial; Iron Plate needs no research gate.
		["m024a1", "Plate the Hull", "Craft an 'Iron Plate' in the Shipyard for hull armor.", "craft", "z1_armor", 1, 2500, 200, "m024a2"],
		["m024a2", "Bolt It On", "Open the Ship Designer, then DRAG the Iron Plate from your Armory onto the empty ARMOR slot. It cuts incoming hull damage.", "loadout_check", "armor", 1, 500, 100, "m024b"],
		# Split for onboarding: teach what consumables are + where to make them,
		# THEN how to equip them (was one sudden compound objective).
		# v134: "Processing page" — no such page exists; the sidebar label is Engineering.
		# v134g: Basic Shield Booster's recipe consumes a Battery Cell (BatteryT1) each —
		# a sub-component the power-first reorder no longer teaches on the main path (m021
		# is orphaned). Name the sub-step like m019 does for Tin so the player isn't walled
		# by an unexplained input; the router (main.gd) also routes to the cell craft first.
		["m024b", "Field Supplies", "Repair kits keep you alive in combat. In the Engineering page, craft 5 Emergency Hull Patches and 5 Basic Shield Boosters. Boosters each need a Battery Cell — craft those first.", "gather_multi", {"EmergencyPatch": 5, "BasicBooster": 5}, 10, 2000, 150, "m024b2"],
		# Re-routed: m016b (catch-all weapon+shield equip) is now redundant —
		# each module already has its own per-arc equip mission (m007b / m015b /
		# m022b / m024c). m024b2 now flows into m016c "Combat Briefing", which
		# orients the player before their first fight. m016b is kept in the
		# data as an orphan for save-compat with any in-progress runs that
		# happened to be sitting on it.
		["m024b2", "Combat Triage", "Now equip a Hull and a Shield repair kit in your Ship Designer's consumable slots. In combat, tap the HULL / SHLD buttons to spend one and patch up.", "equip_consumables", "1", 1, 2000, 200, "m016c"],
		# P1 Onboarding: combat orientation. Auto-completes when the player
		# opens the Combat page (main.gd hooks page navigation into
		# _update_progress("visit_page", page_name, 1)).
		["m016c", "Combat Briefing", "Open the Combat page (left sidebar). Pick a sector → a target → ENGAGE. Your Shield absorbs hits first, your Hull takes the overflow. Repair kits can auto-fire — set the threshold in Research.", "visit_page", "combat", 1, 200, 50, "m017"],
		# v132: smelting's tree parent is Organic Combustion — name BOTH so the
		# player isn't surprised by a locked node (one Research visit, two clicks).
		# v145 (D): Materials Science is Organic Combustion's parent and is no longer
		# bought at m008, so name the full walk here — three clicks, one Research visit,
		# at the first moment any of it does something visible. Its own bill (20 Common
		# Artifacts + 10 Circuit Boards, both cost layers applied) is named too.
		["m025", "Refining Mastery", "Open Research and walk the branch: 'Materials Science' → 'Organic Combustion' → 'Efficient Smelting'. The last one bills 20 Common Artifacts and 10 Circuit Boards and opens alloys.", "research", "smelting", 1, 15000, 500, "m025a"],
		# v134: modern smelting now consumes Oxygen (Basic-Oxygen furnace), so teach
		# electrolysis BEFORE the first steel — otherwise the steel recipe silently needs
		# an input the tutorial never introduced. Electrolysis also feeds the later O/H
		# recipes (zinc/nickel roasting, missile propellant). 50 steel = 10 crafts = 20 O.
		# v145 (F): the Oxygen ask is DERIVED from the Steel ask below — 5 Steel per
		# Basic-Oxygen craft, 2 Oxygen per craft. 160 Steel = 32 crafts = 64 Oxygen, so
		# the stock must be 64+, not 30. One Water Electrolysis run yields 10 O in 2s,
		# so 70 is ~14s of processing — the number was short, not the pacing.
		["m025a", "Split the Water", "Modern foundries burn Oxygen. In the Engineering tab, run Water Electrolysis to split Water — stock 70 Oxygen. The steel run ahead burns 2 per batch.", "gather", "O", 70, 3000, 300, "m025b"],
		# v145 (F) HARD BUG: this said 50 Steel and the very next two missions spend 156.
		#   Shipwright I (m026): raw Steel 15 -> ceil(15 x 2.5 MID stage) = 38
		#                        -> x2.0 MATERIAL_MULTIPLIER at check = 76
		#   Industrial Frigate (m026b): hull 50 Steel + 3 Reinforced Plating x 10 Steel = 80
		#   TOTAL 156. Ask 160 (margin 4). The player was doing exactly what they were
		#   told and still coming up 106 short — a trust breaker, not a pacing nit.
		# Time cost is small: smelt_steel_basic is 5 Steel / 5s, so 160 Steel is ~2.7 min
		# of processing. The work was ALWAYS required; it just wasn't directed.
		["m025b", "Alloy Production", "Now smelt 160 Steel in the Engineering tab — the Basic-Oxygen furnace blows your Oxygen through molten Iron and Carbon. Shipwright I burns most of this stock; the Frigate frame after it takes the rest.", "gather", "Steel", 160, 5000, 500, "m026"],
		# v145 (F): name the FULL bill. Shipwright I costs 76 Steel, 30 Circuit Boards and
		# 60 Common Artifacts once both cost layers apply — the Circuit and Artifact halves
		# have no directed producer beat, so the text is the only place the player can learn
		# them before they open the node and find it red.
		["m026", "Master Constructor", "Research 'Shipwright I' for hull reinforcement. It bills 76 Steel (the stock you just smelted), 30 Circuit Boards, and 60 Common Artifacts from combat salvage — top up the circuits in Engineering before you open the node.", "research", "shipwright_1", 1, 5000, 500, "m026b"],
		# v134h: the frigate silently needs Reinforced Plating — a crafted component the
		# old one-line text never named (m019/m024b-class hidden input). Name it + its inputs.
		# v145: the text said "4 Reinforced Plating"; the hull cost is 3 (v139c band surgery
		# trimmed 4 -> 3 and never updated the mission). Same stale-number class as F/G.
		# The 50 Steel of the hull frame itself was never named either — it is now.
		["m026b", "Hull Modernization I", "Construct an 'Industrial Frigate' in the Shipyard. Its frame needs 50 Steel and 3 Reinforced Plating — craft the plating in Engineering from Salvaged Alloy + Damaged Circuitry (Lunar Orbit drops, or the Steel/Circuit reclaim recipes).", "construct", "frigate_hull", 1, 10000, 1000, "m026c"],
		["m026c", "Elite Salvage", "Defeated enemies drop gear of varying rarity. Farm Lunar Orbit until you get a RARE (blue) module drop.", "drop_rarity", "2", 1, 5000, 500, "m026d"],
		# v131: Architect resists zeroed — chain goes straight to the boss fight; any
		# RARE+ weapon type works. m026d2/d3 (the old explosive-forcing pair) stay
		# DEFINED below for saves mid-arc, but no fresh game routes into them.
		["m026d", "Combat Overhaul", "Equip at least 1 RARE+ Weapon.", "loadout_rare_weapon", "2", 1, 10000, 1000, "m026e"],
		# v119: type-matching teach beat before the Z1 boss. The Architect RESISTS
		# kinetic + energy (+0.25) but is WEAK to explosive (-0.30), so the right TYPE
		# beats raw rarity. Combustion is already unlocked (smelting required it at m025).
		["m026d2", "Munitions Run", "Produce 60 HE Missiles in the Engineering tab to arm a missile launcher — the Architect ahead is WEAK TO EXPLOSIVE.", "gather", "MissileT1", 60, 8000, 800, "m026d3"],
		["m026d3", "Explosive Payload", "Equip a RARE+ EXPLOSIVE weapon — the Architect is WEAK TO EXPLOSIVE, and the rare-tier punch ends fights fast.", "loadout_rare_weapon_type", "explosive", 1, 12000, 1200, "m026e"],
		["m026e", "Final Confrontation", "Defeat the Rogue Architect boss in Lunar Orbit.", "defeat", "z1_boss_architect", 1, 25000, 2500, "m027"],
		# P0 Fix: Progression Deadlock Re-alignment
		["m027", "Scanning Horizon", "Research 'Asteroid Belt Authorization' in the Research tree to unlock the Asteroid Belt combat zone.", "research", "zone_2_access", 1, 5000, 500, "m017a"],
		# P-onboard: introduce the Bounty Board the moment it unlocks (Asteroid Belt).
		# visit_page → auto-completes on navigation, can never soft-lock.
		["m027b", "Open Contracts", "Open Bounties (left sidebar — it just unlocked). Each sector runs its own combat contract board: accept one, and kills in that sector count toward it automatically. Pays Liras + a ship module.", "visit_page", "bounty", 1, 6000, 500, "m028"],
		# v145 (C): was "mine 100 Cassiterite" — raw ore, and the mission never told the
		# player to smelt it. The next mission (m029, Carbon Fiber Plate) costs C / Fe /
		# ReinforcedPlating and zero tin, so 100 units of ore sat in a 28-slot hold for
		# ~8 missions doing nothing. Retargeted to the SMELTED output: the electronics arc
		# that starts two beats later runs on Circuit Boards (2 Sn each) and Advanced
		# Circuits (1 Sn each), so tin is the thing with a consumer, not the ore.
		# 70 Sn = 105 Cassiterite at the 3-ore -> 2-Sn ratio, so the mining load is
		# unchanged; only the finished form and the stated purpose are different.
		["m028", "Belt Metallurgy", "In the Mine page extract Cassiterite, then smelt it into 70 Tin in Engineering. Tin is the solder in every Circuit Board and Advanced Circuit — the electronics push ahead runs on it.", "gather", "Sn", 70, 10000, 2000, "m029"],
		["m029", "Hardened Shell", "Craft 'Carbon Fiber Plate' in the Shipyard.", "craft", "z2_armor", 1, 15000, 5000, "m029a1"],
		# v107 Mission flow — split the silent AdvCircuit wall into discoverable
		# beats (Koster pattern-injection). m029b previously dropped the player
		# off a cliff: lvl 45 Engineering + 4 unnamed research gates + a 5-input
		# recipe none of whose intermediates had been introduced. Each beat
		# below surfaces ONE node and delivers materials the final mission needs.
		# Save-compat: in-flight players sitting on m029b stay valid (it still
		# exists with the same id); only m029.next_mission_id was rerouted.
		["m029a1", "Material Sciences", "Research 'Advanced Materials' to unlock heavier industrial recipes. It spends Common Artifacts from combat salvage.", "research", "adv_materials", 1, 5000, 500, "m029a2"],
		# v134h: name the hidden Nickel cost. metallurgy_advanced costs Ni, and
		# Advanced Materials (just researched) unlocks the Pentlandite mining that feeds it.
		# v145: the text said 100 Nickel; the AUTHORED 100 is doubled by
		# MATERIAL_MULTIPLIER at can_unlock/unlock_tech time, so the player is billed 200.
		# Same F-class stale-number error as m025b — the taught number must be the
		# effective one, since that is the only number the player can act on.
		["m029a2", "Structural Doctrine", "Research 'Advanced Metallurgy'. It bills 200 Nickel — mine Pentlandite (just unlocked), then refine it with Carbon + Oxygen first.", "research", "metallurgy_advanced", 1, 5000, 500, "m029a3"],
		# v145 (A): was 10. craft_adv_circuit consumes ONE Structural Component each
		# (processing_manager:840, v139c trimmed 2 -> 1), and m029b now asks for 6 Advanced
		# Circuits — so 6 is the exact bill and the other 4 had no consumer this side of
		# Zone 3. In a 28-slot inventory, four permanently-parked components is a sink the
		# player pays for and never spends. Named the consumer so the thread is visible:
		# 6 components -> 6 Advanced Circuits -> Shipwright II's 6.
		["m029a3", "First Components", "Craft 6 Structural Components in the Engineering tab — the universal building block of heavy industry, and one goes into every Advanced Circuit you are about to build.", "gather", "StructuralComponent", 6, 8000, 1000, "m029a5"],
		# v132: ORPHANED (m029a3 → m029a5). Combustion is already owned by this
		# point — it's Efficient Smelting's tree parent, bought at m025 — so this
		# beat auto-completed the instant it appeared. Kept for in-flight saves.
		["m029a4", "Chemical Heat", "Research 'Organic Combustion' to unlock Germanium extraction (needed for semiconductors).", "research", "combustion", 1, 5000, 500, "m029a5"],
		["m029a5", "Factory Lights", "Research 'Factory Automation' — the last gate before Advanced Circuits.", "research", "automation", 1, 10000, 1000, "m029a6"],
		# ── v139g BEAT 2 (owner: shift gather+craft -> infrastructure): the
		# industrialization arc. Inserted at the measured m029-m030 desert — the
		# band where players hand-crank Circuits that a factory should make.
		# Four beats force TWO building families (power + industry) and teach
		# feed chains (Wood -> Biomass; Si/Cu/Resin -> Assembler) + throttling.
		# Rewards (65K total) roughly bankroll the ~75K industrial investment.
		# Save-compat: players already past m029a5 skip the arc (standard
		# insertion pattern, see v134 note above).
		# v145 (G) HARD BUG: this is the mission whose whole job is powering the line, and
		# it under-supplied it. ONE Biomass Plant is 1,000 kW (infrastructure_manager:103)
		# against the Electronics Assembler's 1,500 kW draw (:734) — a 485 kW deficit even
		# counting the 15 kW Solar Array from m019d. recalc_energy sets net_energy < 0, the
		# grid buffer drains, and energy_efficiency falls to 0: the assembler the previous
		# three beats paid for simply stops. TWO plants = 2,000 kW vs 1,500 kW draw
		# (+515 kW with the Solar Array), which is the first configuration that holds.
		# Chose quantity over swapping the building: Biomass is already the taught power
		# unit here and doubling it keeps the arc to two building families as designed.
		# Fuel note: Wood only fills the surplus buffer — energy_efficiency keys off the
		# static net_energy, so a wood-dry plant no longer throttles the line.
		["m029a6", "Industrial Baseload", "Construct 2 Biomass Plants in Infrastructure — 1,000 kW each. The assembly line ahead draws 1,500 kW, so a single plant leaves it starved. They burn Wood, so keep a stock coming.", "build", "biomass_plant", 2, 12000, 1500, "m029a6t"],
		# v145 (H): the missing titanium beat. Nothing in the chain has ever named Ti, yet
		# the next two missions both bill it:
		#   Automated Smelting (m029a7's tree parent): raw Ti 20 x2.0 MATERIAL_MULTIPLIER = 40
		#   Electronics Assembler (m029a8):            Ti 50 flat
		#   TOTAL 90. Ask 100 (margin 10).
		# Both mine_dolomite and refine_titanium unlocked back at m029a1 (Advanced
		# Materials) and were never taught — the same hidden-input class as the Tin wall
		# m018t1/m018t2 already fixed. Kept to ONE beat (mine + refine in a single gather
		# target) and paid for by dropping m008 from the chain, so net chain length is flat.
		["m029a6t", "Titanium Reduction", "The industrial tier runs on titanium. In the Mine page quarry Dolomite, then run Titanium Reduction in Engineering until you hold 100 Ti — Automated Smelting takes 40 and the assembler after it takes 50.", "gather", "Ti", 100, 10000, 1200, "m029a7"],
		["m029a7", "Industrial Automation", "Research 'Industrial Automation'. The Infrastructure branch runs Blast Furnace → Automated Smelting → Industrial Automation, and Automated Smelting spends 40 of your titanium. Hand-soldering ends here.", "research", "industrial_automation", 1, 8000, 1000, "m029a8"],
		# v145 (H): name the two silent inputs — 50 Titanium (from the beat above) and 12
		# Salvage Data, a combat drop with no craft recipe. Power line now reads honestly:
		# the two plants from m029a6 cover this draw with room to spare.
		["m029a8", "The Assembly Line", "Commission an Electronics Assembler. It costs 50 Titanium and 12 Salvage Data — Salvage Data drops from wrecked hostiles, so run a sector if you are short. It draws 1,500 kW, which your two Biomass Plants cover. It consumes Silicon, Copper and Resin from storage.", "build", "electronics_assembler", 1, 20000, 2500, "m029a9"],
		# v139g funnel tune 2: 250 -> 100 Circuits. The hidden bill of 250 was the
		# upstream Resin chain (~1 Resin per Circuit) — walled 2/3 follower seeds
		# 55h active on m029a9. 100 keeps the watch-the-line-fill teaching beat;
		# m030g's own research bill provides the rest of the era's Circuit demand.
		["m029a9", "Passive Supply", "Accumulate 100 Circuits. The Assembler produces them while you mine, fight — or sleep. Hand-crafting still works; the line just never gets tired.", "gather", "Circuit", 100, 25000, 4000, "m029b"],
		# v134h: the recipe's three opaque sub-inputs are now breadcrumbed. Semiconductor,
		# Gold, and Silver each have a hidden sub-chain the old "your earlier research
		# unlocked each one" text glossed over (Silver especially — only a Zinc byproduct).
		# v138c ATTEMPTED 5 -> 3, REVERTED same session: shipwright_2 (the very next
		# mission) effectively spends ~5 AdvCircuit (base 1 x stage x MATERIAL_MULTIPLIER
		# — see research_manager:189, a DELIBERATE pairing with this mission's count).
		# Cutting to 3 left the player short at m030, which stalled UNDIRECTED farming
		# AdvCircuit (measured: 2/3 seeds walled at m030, destroyer slipped 7.9d -> 13.5d).
		# v139c: DO NOT trim the 5 below — it is load-bearing. Shipwright II's
		# AdvCircuit bill (~6 effective) is priced against the stock + warmed-up
		# production chain these 5 mission-directed crafts leave behind; a 2-craft
		# variant re-opened the historical m030 wall (measured: 55h livelock).
		# v145 (B + F-class): 5 -> 6, and the description now names ALL five inputs.
		#   Shipwright II (m030): raw AdvCircuit 1 -> ceil(1 x 2.5 MID stage) = 3
		#                         -> x2.0 MATERIAL_MULTIPLIER = 6 effective.
		# The old 5 left the player exactly one short of the very next mission and the
		# v139c note above openly relied on them noticing and crafting a 6th. Raising to 6
		# honours that note's floor (never below 5) while removing the ambush.
		# The old text listed 3 of the 5 recipe inputs and OMITTED StructuralComponent —
		# the component m029a3 had just made — so the thread was cut at both ends.
		["m029b", "Complex Electronics", "Craft 6 Advanced Circuits in the Engineering tab — Shipwright II next door spends all 6. Each one takes a Structural Component (the ones you machined), Tin, plus three that need prep: Semiconductor (Silicon + Germanium), Gold (Gold Panning — Dirt + Water), and Silver (a Zinc Reduction byproduct).", "gather", "AdvCircuit", 6, 20000, 5000, "m030"],
		# v103f: Removed forced Fabricator mission (m030b) — it gated nothing
		# (Fabricator is optional QoL, still buildable). m030 -> m030c directly.
		["m030", "Naval Expansion", "Research 'Shipwright II' to unlock Destroyer-class hulls.", "research", "shipwright_2", 1, 4000, 1000, "m030c"],
		# v134h: destroyer needs Reinforced Plating (same component as the frigate) —
		# name it so the quantity isn't a silent grind wall. v138c: 10 -> 5 (see
		# shipyard destroyer_hull cost note). Reroute -> m030c2 (Z2 weapons).
		# v145: text said "5 Reinforced Plating"; destroyer_hull costs 3 (v139c trimmed
		# 5 -> 3 and the mission text was not updated). Same stale-number class as F/G.
		["m030c", "Hull Modernization II", "Construct a 'Destroyer' hull in the Shipyard. Needs 100 Steel and 3 Reinforced Plating (same recipe as the Frigate) — stock Salvaged Alloy + Damaged Circuitry.", "construct", "destroyer_hull", 1, 25000, 2000, "m030c2"],
		# v135a: the chain never USES Zone-2 fabrication (unlocked at m027) — the player reaches
		# the 5280-HP Z2 boss on a Z2 Destroyer still fielding Z1 batteries + Z1 guns (the m030d
		# funnel wall). Refit for Zone 2 in two beats, mirroring the m029 Z2-armor beat:
		#   1) POWER — Z1 batteries (50 cap) can't run heavier Z2 ordnance; Improved Battery = 110.
		#   2) ORDNANCE — v156 boss channel reassignment: the Monolith now RESISTS
		#      explosive (the Belt's own farming channel) and is WEAK TO ENERGY.
		#      Measured (boss_gearcheck loadout logic, 25 trials): a full LEGENDARY
		#      explosive set CANNOT kill it (boss at 53% HP); Rare ENERGY wins 14/25.
		#      So this beat crafts z2_energy — the chain arms the swap the whole
		#      boss ladder now runs on.
		["m030c2", "Power Refit", "A Destroyer draws more power than your Zone-1 batteries supply. Fabricate 3 'Improved Battery' (Z2) and equip one per battery slot — you'll need the headroom for Zone-2 weapons.", "craft", "z2_battery", 3, 30000, 3000, "m030c3"],
		["m030c3", "Heavier Ordnance", "Your Zone-1 guns barely dent Zone-2 armor. And the boss breaks the Belt's pattern: the Silicate Monolith shrugs off explosive and is WEAK TO ENERGY. Fabricate 3 'Plasma Cutter' (Z2 ENERGY) and equip one per weapon slot before the fight.", "craft", "z2_energy", 3, 30000, 3000, "m030d"],
		# v134h: zone_3_access (Mars Debris Clearance) COSTS a Z2 boss core the chain never
		# told the player to farm. Insert an explicit boss-farm beat (mirrors m030i/m032a).
		["m030d", "Belt Overseer", "Defeat the Silicate Monolith (Asteroid Belt boss) to salvage a Z2 Sector Core for the Mars Debris charter. Bosses demand a full RARE loadout — Common and Uncommon gear will not cut through. Work the Asteroid Belt BOUNTY BOARD: hunt contracts pay a GUARANTEED Rare module on claim. ENERGY hits it hardest — swap loadouts before the fight.", "defeat", "z2_boss_monolith", 1, 50000, 6000, "m030e"],
		# Mission bridge from Asteroid Belt to Sector Alpha (zones 3-4 introduction)
		["m030e", "Mars Beachhead", "Research 'Mars Debris Clearance' (spends the Monolith core you just salvaged) to unlock the Mars Debris zone.", "research", "zone_3_access", 1, 40000, 5000, "m017c"],
		["m030f", "Salvage Operations", "Defeat 3 Scavenger Mechs in the Mars Debris zone.", "defeat", "z3_scavenger_mech", 3, 60000, 8000, "m030fa"],
		# v135a: full Zone-3 refit before the Warmaster (17k-hull boss, atk 210) — the SAME gap the
		# Z2 boss had, but the boss out-DPSes a Z2-geared hull in ~15s, so the refit must cover
		# SURVIVAL (Z3 armor + shield) as well as ordnance. Regular Z3 enemies fall to Z2 gear; the
		# BOSS needs the tier. Three beats: plating -> shielding -> ordnance, then the fight.
		["m030fa", "Zone-3 Plating", "The Warmaster will shred Zone-2 armor. Fabricate 2 'Composite Plate' (Z3 armor) and equip one per armor slot.", "craft", "z3_armor", 2, 40000, 5000, "m030fb"],
		["m030fb", "Zone-3 Shielding", "Reinforce your deflectors too. Fabricate 2 'Hardened Shield' (Z3) and equip one per shield slot before the Warmaster.", "craft", "z3_shield", 2, 40000, 5000, "m030f1"],
		# v156: the Warmaster now resists explosive, is neutral to energy (the zone's
		# own farming channel) and is WEAK TO KINETIC — this beat crafts z3_kinetic
		# and repeats the swap lesson m030c3 opened (mirrors the m030c3 beat).
		["m030f1", "Zone-3 Ordnance", "The Warmaster breaks the zone's pattern too: it is WEAK TO KINETIC, not energy. Fabricate 3 'Autocannon' (Z3 KINETIC) and equip one per weapon slot — swap before the fight.", "craft", "z3_kinetic", 3, 50000, 6000, "m030f2"],
		# v134h: zone_4_access COSTS 2 Z3 boss cores the chain never directed. Explicit
		# boss-farm beat before the research (m030f only killed regular Scavenger Mechs).
		["m030f2", "Warmaster's Core", "Defeat the Martian Warmaster (Mars Debris boss) — its core decrypts the Glacier Belt charter.", "defeat", "z3_boss_warmaster", 1, 90000, 12000, "m030g"],
		["m030g", "Glacier Belt Survey", "Research 'Glacier Belt Expedition' (spends the Warmaster core) to unlock the Glacier Belt zone.", "research", "zone_4_access", 1, 80000, 10000, "m030h"],
		["m030h", "Frozen Frontier", "Defeat 3 Ice Wraiths in the Glacier Belt.", "defeat", "z4_ice_wraith", 3, 100000, 12000, "m030i"],

		# v132 funnel repair (m030i..m034): the tail directed the WRONG techs.
		# The real sector doors are zone_5/6/7_access and each costs BOSS CORES
		# (Z4_Core x2, Z5_Core x3, Z6_Core x3) the chain never told the player to
		# farm. sector_alpha_decryption is an optional scan child; deep_space_nav/
		# radiation_shielding are the Exotics research branch, NOT zone unlocks —
		# their old mission texts lied. New boss-farm beats (m030i, m032a) feed
		# the cores, research beats now target the actual doors, and the tail is
		# reordered m033 → m034 (Beta boss farm) → m033b (Gamma door) → m033c.
		["m030i", "Overseer's Core", "Decrypting the Sector Alpha charter takes two Glacial Overseer cores — defeat the Glacier Belt boss twice.", "defeat", "z4_boss_overseer", 2, 120000, 15000, "m031"],
		["m031", "Alpha Decryption", "Research 'Sector Alpha Decryption' (consumes the Overseer cores + a stock of Superalloy — craft it in Engineering) to breach Sector Alpha.", "research", "zone_5_access", 1, 50000, 10000, "m032"],
		["m032", "Alpha Sector Dominance", "Defeat 3 Alien Frigates in Sector Alpha.", "defeat", "z5_alien_frigate", 3, 75000, 15000, "m032a"],
		["m032a", "Harbinger Hunt", "The Beta Colony Charter demands three XENON HARBINGER cores. Defeat the Sector Alpha boss three times.", "defeat", "z5_boss_harbinger", 3, 150000, 20000, "m032b"],
		["m032b", "Beta Colony Charter", "Research 'Beta Colony Charter' (consumes the Harbinger cores + a large Superalloy + Titanium stock) to unlock Sector Beta.", "research", "zone_6_access", 1, 50000, 5000, "m032d"],
		["m032d", "Void Research", "Void Artifacts drop from Sector Alpha ships — defeat them in Combat until you collect 5.", "gather", "VoidArtifact", 5, 100000, 10000, "m032c"],
		# P0-28: Construct Battlecruiser
		["m032c", "Capital Doctrine", "Construct a 'Battlecruiser' in the Shipyard.", "construct", "battlecruiser_hull", 1, 250000, 25000, "m033"],

		["m033", "Beta Sector Expansion", "Defeat 5 Ore Guardians in Sector Beta.", "defeat", "z6_ore_guardian", 5, 150000, 25000, "m034"],
		["m034", "Break the Blockade", "Defeat the BETA COLOSSUS 3 times — its cores are the key to Gamma Sector Clearance.", "defeat", "z6_boss_colossus", 3, 300000, 50000, "m033b"],
		["m033b", "Gamma Clearance", "Research 'Gamma Sector Clearance' (consumes the Colossus cores + a heavy Superalloy + Tungsten stock) to unlock Sector Gamma.", "research", "zone_7_access", 1, 100000, 10000, "m033c"],
		["m033c", "Titan Construction", "Construct a 'Dreadnought' in the Shipyard. Its blueprints sit behind 'Delta Sector Survey' research — four Sector Gamma boss cores.", "construct", "dreadnought_hull", 1, 1000000, 50000, ""],
		# v134: goal XP re-tuned now that reward_xp is actually GRANTED (it was a dead
		# field). Legacy values (1M/250K/2M) were written when XP paid nothing — live,
		# they'd insta-level a skill past the 30%-retention warp design. Sized as
		# one-time "lamps": a satisfying chunk (~1-3 levels at claim era), not a skip.
		["goal_001", "THE GREAT EXPEDITION", "Reach Sector Epsilon and discover the Primordial Core.", "discover", "sector_epsilon", 1, 0, 250000, ""],
		["goal_002", "INTO THE VOID", "Perform your first Warp. Your Liras and materials reset, but you gain Exotic Matter Shards for permanent multipliers that make each run stronger.", "warp_perform", "warp", 1, 0, 50000, ""],
		["goal_003", "PRESTIGE VETERAN", "Perform 5 Warps total to fully unlock Warp Tier scaling.", "warp_perform", "warp", 5, 0, 500000, ""],
		["goal_cryo_1", "FORGE CRYOGENIC ARMS", "The Threshold (Sector 11) is warp-hardened — only Cryo weapons breach it. Research Cryogenic Armaments in the Warp Tech tab (prereqs: Energy Metrics, then Cryogenic Systems).", "research", "cryo_armaments", 1, 3000000, 0, "goal_cryo_2"],
		["goal_cryo_2", "FORGE CRYOGENIC ARMS", "Craft a Cryo Lance in the Shipyard. It needs Cryo Catalyst - farm it from Sector 10 enemies.", "craft", "cryo_lance", 1, 6000000, 0, "goal_cryo_3"],
		["goal_cryo_3", "BREACH THE THRESHOLD", "Destroy a Warp Revenant in The Threshold (Sector 11) with your Cryo armaments.", "defeat", "z11_warp_revenant", 1, 15000000, 0, ""],
		# v128: Hack-Card onboarding arc (research -> loot -> apply). Reveals once
		# kinetics_101 is researched (~Sector 3), right as the loot-refine need appears.
		# Step 2 uses the "gather" type: element_added fires for combat loot too, so a
		# dropped Splice Chip counts. Step 3 uses the new "hack_apply" type.
		# v141c: "(Combat tab)" read as the Combat PAGE — the sidebar has a Combat
		# button, and the directive arrow points at sidebar buttons. Both techs live
		# in the Research Lab's Combat CATEGORY; say so explicitly.
		["goal_hack_1", "REWRITE THE FIRMWARE", "Salvaged modules can be re-forged. In the Research Lab, open the Combat category: research Kinetic Weapons Theory, then Firmware Hacking beneath it, to unlock Hack Cards — module affix crafting.", "research", "firmware_hacking", 1, 20000, 0, "goal_hack_2"],
		["goal_hack_2", "SALVAGE A HACK CARD", "Hack Cards now drop in combat. Defeat enemies until a Splice Chip drops.", "gather", "SpliceChip", 1, 15000, 0, "goal_hack_3"],
		["goal_hack_3", "AWAKEN A MODULE", "Open the Ship Designer and drag a Splice Chip onto a Common component to awaken it into a custom module with a random affix.", "hack_apply", "SpliceChip", 1, 30000, 0, ""],
		# v130: Boost-Card onboarding arc (craft -> install). Reveals once Engineering
		# hits the fabricate recipe's level (45). Step 1 uses "gather" (element_added
		# fires for processing outputs); step 2 uses the new "overclock_install" type.
		["goal_boost_1", "OVERCLOCK PROTOCOL", "Your grid can run hotter. Fabricate a Boost Card in the Engineering tab — it takes Advanced Circuits, Superalloy, and a Quantum Core (Sector Alpha hostiles drop them).", "gather", "BoostCard", 1, 40000, 0, "goal_boost_2"],
		["goal_boost_2", "RUNNING HOT", "Open Infrastructure and INSTALL the Boost Card on a building you own — it unlocks that building's Efficiency slider up to 200%. Careful: output scales linearly, but input draw scales QUADRATICALLY (200% output = 4x input).", "overclock_install", "BoostCard", 1, 60000, 0, ""],
		# v139f: Matrix-Core onboarding arc (synthesize -> socket). Currently the ONLY
		# guidance for the socket system — matrix_synthesis unlocks at zone_2_access but
		# nothing taught it. Reveals once synthesis is craftable AND the player has an
		# equipped module with an OPEN socket, so BOTH steps are always completable when
		# the arc surfaces (mirrors the Hack/Boost card arcs; no soft-wall on either verb).
		["goal_matrix_1", "ATTUNE A MATRIX CORE", "Rare, Legendary and Unique modules carry SOCKETS. In the Shipyard, craft 'Matrix Synthesis' to synthesize a Matrix Core — a gem that empowers whatever module you socket it into.", "craft_matrix", "matrix", 1, 40000, 0, "goal_matrix_2"],
		["goal_matrix_2", "SLOT THE CORE", "Open the Ship Designer and drag your Matrix Core from the Armory onto an empty socket on one of your EQUIPPED modules. Its facet bonus applies while that module stays equipped.", "socket_check", "matrix", 1, 60000, 0, ""]
	]
	
	for i in range(m_list.size()):
		var entry = m_list[i]
		var mid = entry[0]
		var stage = i + 1 # missions index for scaling
		
		# Use hand-tuned base reward from mission definition
		# Apply gentle linear scaling: Base * (1 + 0.05 * stage)
		# This gives ~50% more at stage 10, ~150% more at stage 30
		# Much gentler than the old 1.15^stage which was causing hyperinflation
		var base_reward = entry[6]
		var scaled_reward = int(float(base_reward) * (1.0 + 0.05 * float(stage)))
		
		# v132: the chain now ends at m033c (its row's next is "") — the old
		# hard cutoff at m034 would sever the reordered tail (m034 → m033b).
		var next_id = entry[8]
		
		var m_name = entry[1]
		var tag = ""
		if mid.begins_with("m"):
			if mid in ENDGAME_IDS:
				tag = "[ENDGAME]"
			elif mid in CHAPTER_2_IDS:
				tag = "[CHAPTER 2]"
			else:
				tag = "[TUTORIAL]"
		else:
			tag = "[CORE GOAL]"
		
		missions[mid] = {
			"id": mid,
			"tag": tag,
			"name": m_name,
			"description": entry[2],
			"type": entry[3],
			"target": entry[4],
			"target_qty": entry[5],
			"reward_cr": scaled_reward,
			"reward_xp": entry[7],
			"next_mission": next_id,
			"current_qty": 0.0,
			"multi_progress": {}, # For gather_multi
			"completed": false,
			"claimed": false,
			# Tutorial starts at m001. Core Goals are NOT active from the start —
			# showing endgame/prestige goals (warp, 5 warps, final sector) at 0%
			# to a brand-new player is pure confusion. They reveal when relevant
			# via _check_goal_reveals() (warp goals at Warp-Core reveal; the
			# 5-warp veteran goal after the first warp).
			"active": (mid == "m001")
		}
		if missions[mid]["active"]:
			active_missions.append(mid)
	
	mission_updated.emit()

func _on_element_added(symbol, amount):
	_update_progress("gather", symbol, amount)
	_update_multi_progress(symbol, amount)

func _on_currency_added(type, amount):
	_update_progress("sell", type, amount)

func _on_tech_unlocked(tech_id):
	_update_progress("research", tech_id, 1)
	_update_research_multi(tech_id)

func _on_module_crafted(module_id):
	_update_progress("craft", module_id, 1)

# v128: a Hack Card was successfully applied to a module (fires "hack_apply" for the arc).
func _on_hack_stone_applied(stone_id):
	_update_progress("hack_apply", stone_id, 1)

func _on_hull_constructed(hull_id):
	_update_progress("construct", hull_id, 1)

func _on_enemy_defeated(enemy_id):
	_update_progress("defeat", enemy_id, 1)
	# v143: "defeat_retreat" banks the kill in _kills rather than current_qty, so the
	# mission cannot complete on the kill alone — sync_progress releases current_qty
	# only once the ship is also out of combat. Counted here (not in the state check)
	# because a state poll would miss kills that happen between polls.
	for _mid in active_missions:
		var _m: Dictionary = missions[_mid]
		if str(_m.get("type", "")) == "defeat_retreat" and str(_m.get("target", "")) == str(enemy_id):
			_m["_kills"] = int(_m.get("_kills", 0)) + 1

# v128: player deployed into a sector — completes "discover" missions (e.g. goal_001
# "reach Sector Epsilon"). Fires on every entry; check_completion caps at target_qty.
func _on_zone_entered(zone_id):
	_update_progress("discover", zone_id, 1)

func _on_building_constructed(building_id):
	_update_progress("build", building_id, 1)

# v130: a Boost Card was installed on a building (fires "overclock_install").
func _on_boost_card_installed(_building_id):
	_update_progress("overclock_install", "BoostCard", 1)

func _on_shipyard_updated():
	sync_progress()

func _update_progress(type, target, amount):
	for mid in active_missions:
		var m = missions[mid]
		if not m["completed"] and m["type"] == type and m["target"] == target:
			m["current_qty"] += amount
			if DEBUG_LOG: print("[MissionDebug] ID: %s, Progress: %d/%d (added %d)" % [mid, m["current_qty"], m["target_qty"], amount])
			check_completion(m)
			mission_updated.emit()

func _update_multi_progress(symbol, amount):
	for mid in active_missions:
		var m = missions[mid]
		if not m["completed"] and m["type"] == "gather_multi":
			if symbol in m["target"]:
				var current = m["multi_progress"].get(symbol, 0.0)
				var to_add = min(amount, m["target"][symbol] - current)
				if to_add > 0:
					m["multi_progress"][symbol] = current + to_add
					m["current_qty"] += to_add
					if DEBUG_LOG: print("[MissionDebug] ID: %s, Multi-Progress: %d/%d (added %d %s)" % [mid, m["current_qty"], m["target_qty"], to_add, symbol])
				
				# Check overall completion
				var all_done = true
				for s in m["target"]:
					if m["multi_progress"].get(s, 0.0) < m["target"][s]:
						all_done = false
						break
				if all_done:
					check_completion(m)
				
				mission_updated.emit()


# research_multi: one mission that requires several techs (the founding chain). Each
# unlocked tech is tracked in multi_progress so the card shows clean "N / total"
# progress instead of sitting at 0/1 until the very last one lands.
func _update_research_multi(tech_id):
	for mid in active_missions:
		var m = missions[mid]
		if m["completed"] or m["type"] != "research_multi":
			continue
		if tech_id in m["target"] and not m["multi_progress"].get(tech_id, false):
			m["multi_progress"][tech_id] = true
			var done := 0
			for t in m["target"]:
				if m["multi_progress"].get(t, false):
					done += 1
			m["current_qty"] = done
			check_completion(m)
			mission_updated.emit()

func check_completion(mission):
	if mission["current_qty"] >= mission["target_qty"]:
		mission["current_qty"] = mission["target_qty"]
		mission["completed"] = true

func claim_reward(mission_id) -> bool:
	if not mission_id in missions: return false
	var m = missions[mission_id]
	if m["completed"] and not m["claimed"]:
		m["claimed"] = true
		# v138d: also clear the ACTIVE flag — claim only erased the runtime list,
		# leaving active:true in the save forever (observed live: a claimed mission's
		# stale flag can resurrect its navigation hint, directing the player at a
		# tech they already researched). The flag must tell the truth at the source.
		m["active"] = false

		# Remove from active list
		active_missions.erase(mission_id)
		
		# Grant Rewards
		if m["reward_cr"] > 0:
			var reward = m["reward_cr"]
			# Audit v3.0: Apply prestige multiplier to mission rewards
			if GameState.warp_manager:
				reward = int(reward * GameState.warp_manager.get_production_multiplier())
			GameState.resources.add_currency("credits", reward)

		# v134: reward_xp existed on every mission but was NEVER granted (dead field).
		# Wire it: the XP lands on the skill the mission actually exercised — combat
		# for fight/loadout beats, Engineering for craft/research/industry, Mining for
		# raw-material gathers (see _grant_reward_xp).
		if m["reward_xp"] > 0:
			_grant_reward_xp(m)

		# v128: bootstrap the crafting loop — finishing the awaken tutorial hands the
		# player 2 more Splice Chips so they can keep experimenting past the mission.
		if mission_id == "goal_hack_3":
			GameState.resources.add_element("SpliceChip", 2)

		# v130: same pattern for the overclock arc — one bonus Boost Card so the
		# player immediately picks a SECOND building to overclock (the real choice).
		if mission_id == "goal_boost_2":
			GameState.resources.add_element("BoostCard", 1)

		# Auto-unlock next mission
		if m["next_mission"] != "" and m["next_mission"] in missions:
			var next_id = m["next_mission"]
			missions[next_id]["active"] = true
			if not next_id in active_missions:
				active_missions.append(next_id)
		
		sync_progress() # Sync the new mission immediately
		mission_updated.emit()
		return true
	return false

# v134: route mission XP to the skill whose loop the mission taught. "gather"
# targets that are PROCESSING OUTPUTS (Steel, Circuit, ammo...) pay Engineering
# XP — the player crafted them; raw materials (Dirt, ores...) pay Mining XP.
var _processed_symbols := {}
# v134c: combat-loot-only targets (VoidArtifact, SpliceChip…) use the "gather"
# type as a signal-plumbing necessity (element_added fires on loot), but the
# loop the player actually ran is COMBAT — route their XP there, not to Mining.
var _gatherable_symbols := {}

func _is_processed_target(target) -> bool:
	if _processed_symbols.is_empty() and GameState.processing_manager:
		for rid in GameState.processing_manager.recipes:
			var r = GameState.processing_manager.recipes[rid]
			for sym in r.get("output", {}):
				_processed_symbols[sym] = true
			for row in r.get("output_table", []):
				_processed_symbols[row[0]] = true
	if target is Dictionary:
		for sym in target:
			if sym in _processed_symbols:
				return true
		return false
	return str(target) in _processed_symbols

func _is_gatherable_target(target) -> bool:
	if _gatherable_symbols.is_empty() and GameState.gathering_manager:
		for aid in GameState.gathering_manager.actions:
			for entry in GameState.gathering_manager.actions[aid].get("loot_table", []):
				_gatherable_symbols[str(entry[0])] = true
	if target is Dictionary:
		for sym in target:
			if str(sym) in _gatherable_symbols:
				return true
		return false
	return str(target) in _gatherable_symbols

func _grant_reward_xp(m: Dictionary) -> void:
	var xp: float = float(m["reward_xp"])
	if xp <= 0.0:
		return
	var skill = null
	match str(m["type"]):
		"defeat", "discover", "drop_rarity", "loadout_check", "loadout_rare_weapon", \
		"loadout_rare_weapon_type", "equip_consumables", "warp_perform", "hack_apply", \
		"defeat_retreat":
			skill = GameState.combat_manager
		"gather", "gather_multi":
			# crafted → Engineering; minable → Mining; neither (combat loot
			# like VoidArtifact) → Combat, the loop that actually produced it.
			if _is_processed_target(m["target"]):
				skill = GameState.processing_manager
			elif _is_gatherable_target(m["target"]):
				skill = GameState.gathering_manager
			else:
				skill = GameState.combat_manager
		_:
			# research / craft / construct / build / overclock_install / visit_page
			skill = GameState.processing_manager
	if skill:
		skill.add_xp(xp)

func get_save_data_manager() -> Dictionary:
	var m_data = {}
	for mid in missions:
		var m = missions[mid]
		m_data[mid] = {
			"current_qty": m["current_qty"],
			"multi_progress": m["multi_progress"],
			"completed": m["completed"],
			"claimed": m["claimed"],
			"active": m["active"]
		}
	return {"missions": m_data}

# Reveal long-term Core Goals only when the player can actually engage them,
# so early-game Mission Control shows the tutorial, not 0%-progress endgame
# goals. Safe to call every tick (cheap; no-ops once revealed/completed).
func _check_goal_reveals() -> bool:
	var changed := false
	# The Great Expedition (reach the final sector) + Into the Void (first warp)
	# surface at the Warp-Core reveal — the milestone where the meta game opens.
	if GameState.game_settings.get("warp_first_revealed", false):
		changed = _reveal_goal("goal_001") or changed
		changed = _reveal_goal("goal_002") or changed
	# "Perform 5 Warps" only makes sense once the player has warped at least once.
	if GameState.warp_manager and GameState.warp_manager.total_warps >= 1:
		changed = _reveal_goal("goal_003") or changed
		# v113 (NG+): the Cryo arming chain reveals once Z11 is unlocked (player
		# cleared Z10 and warped). Hand-holds research -> craft -> breach.
		if GameState.game_settings.get("z11_unlocked", false):
			changed = _reveal_goal("goal_cryo_1") or changed
	# v128: Hack-Card arc reveals at the Z2 gate (~the era loot starts wanting a refine).
	# v129: trigger moved kinetics_101 -> zone_2_access — the tutorial no longer routes
	# through kinetics_101 (research-trip diet), so it can't be the reveal key anymore.
	# The arc's firmware_hacking research buys its kinetics_101 parent in the same visit.
	if GameState.research_manager and GameState.research_manager.is_tech_unlocked("zone_2_access"):
		changed = _reveal_goal("goal_hack_1") or changed
	# v130: Boost-Card arc reveals once Engineering reaches the fabricate recipe's
	# level gate (45) — the exact moment the overclock verb becomes actionable.
	if GameState.processing_manager and GameState.processing_manager.get_level() >= 45:
		changed = _reveal_goal("goal_boost_1") or changed
	# v139f: Matrix-Core arc reveals once Matrix Synthesis is craftable (zone_2_access)
	# AND the player has an equipped module with an OPEN socket — so the craft AND the
	# socket step are both completable the moment the arc appears (never soft-walls).
	if GameState.research_manager and GameState.research_manager.is_tech_unlocked("zone_2_access") \
			and _has_open_socket():
		changed = _reveal_goal("goal_matrix_1") or changed
	return changed

func _reveal_goal(gid: String) -> bool:
	if not gid in missions: return false
	var m = missions[gid]
	if m["active"] or m["completed"]: return false
	m["active"] = true
	if not gid in active_missions:
		active_missions.append(gid)
	return true

# v139f: true if the player has an EQUIPPED module with at least one empty socket.
# Socketing is done on equipped gear (drag a core onto its socket pip), so this is the
# precondition that makes the goal_matrix_2 socket step completable — it gates the arc
# reveal so the mechanic is only taught once it's actionable.
func _has_open_socket() -> bool:
	var sm = GameState.shipyard_manager
	if not sm: return false
	for mid in sm.loadout.values():
		if mid and mid in sm.modules:
			for s in sm.modules[mid].get("sockets", []):
				if s == null:
					return true
	return false

# v139f: count Matrix Cores currently socketed into modules the player owns (equipped
# OR stored). Drives the socket_check mission type. Any non-null socket entry that names
# a matrix-core symbol counts (matrix cores are the only socketable gem).
func _count_socketed_matrix_cores() -> int:
	var sm = GameState.shipyard_manager
	if not sm: return 0
	var cores: Array = ElementDB.CATEGORIES.get("matrix_cores", [])
	var ids: Array = []
	ids.append_array(sm.loadout.values())
	ids.append_array(sm.module_inventory.keys())
	var seen := {}
	var n := 0
	for mid in ids:
		if mid == null or mid == "" or mid in seen:
			continue
		seen[mid] = true
		if not mid in sm.modules:
			continue
		for s in sm.modules[mid].get("sockets", []):
			if s != null and s in cores:
				n += 1
	return n

# v174: which TUTORIAL mission currently owns the guidance arrow — the LAST
# (furthest-along) active, incomplete, [TUTORIAL]-tagged mission in definition
# order. A stale early beat, e.g. an atlas_lookup that a mid-chain insert
# re-activated on an old save, must never outrank the player's real current step.
#
# Lifted out of main.gd::_generic_mission_pulse. Which mission the player is on
# is mission state, not presentation, and the UI copy could not be tested without
# standing up the whole scene — so stale_mission_check kept its own duplicate of
# this loop and drifted into asserting an outcome the loop cannot produce.
# Returns "" when no tutorial mission is live.
func get_tutorial_frontier_id() -> String:
	var chosen := ""
	for mid in missions:
		if not mid in active_missions:
			continue
		var m: Dictionary = missions[mid]
		if m.is_empty() or m.get("completed", false) or String(m.get("tag", "")) != "[TUTORIAL]":
			continue
		chosen = String(mid)
	return chosen

func sync_progress():
	if not GameState.resources: return

	var changed = _check_goal_reveals()
	for mid in active_missions:
		var m = missions[mid]
		if m["completed"]: continue
		
		var old_qty = m["current_qty"]
		
		if m["type"] == "gather":
			var inv_qty = GameState.resources.get_element_amount(m["target"])
			# Persistence: Only update if it helps progression or if we haven't hit completion yet
			m["current_qty"] = max(m["current_qty"], min(inv_qty, m["target_qty"]))
		
		elif m["type"] == "gather_multi":
			for s in m["target"]:
				var inv_qty = GameState.resources.get_element_amount(s)
				var req = m["target"][s]
				var prog = min(inv_qty, req)
				m["multi_progress"][s] = max(m["multi_progress"].get(s, 0.0), prog)
			
			# Recalculate total current_qty from locked-in sub-progress
			var total_p = 0.0
			for s in m["multi_progress"]:
				total_p += m["multi_progress"][s]
			m["current_qty"] = total_p
		
		elif m["type"] == "research":
			if GameState.research_manager.is_tech_unlocked(m["target"]):
				m["current_qty"] = 1

		elif m["type"] == "research_multi":
			var done := 0
			for t in m["target"]:
				if GameState.research_manager.is_tech_unlocked(t):
					m["multi_progress"][t] = true
					done += 1
			m["current_qty"] = done
				
		elif m["type"] == "craft":
			var inv_count = GameState.shipyard_manager.module_inventory.get(m["target"], 0)
			# Also check if equipped
			for slot in GameState.shipyard_manager.loadout:
				if GameState.shipyard_manager.loadout[slot] == m["target"]:
					inv_count += 1
			m["current_qty"] = max(m["current_qty"], min(inv_count, m["target_qty"]))

		elif m["type"] == "construct":
			if GameState.shipyard_manager.active_hull == m["target"]:
				m["current_qty"] = 1
			# Also check if we passed this tier (e.g. have a Destroyer but mission wants Frigate)
			# Assuming linear progression: Corvette -> Frigate -> Destroyer
			# Quick hack: Check if current tier >= target tier
			var target_tier = GameState.shipyard_manager.hulls[m["target"]].get("tier", 0)
			var current_tier = GameState.shipyard_manager.hulls[GameState.shipyard_manager.active_hull].get("tier", 0)
			if current_tier >= target_tier:
				m["current_qty"] = 1

		elif m["type"] == "build":
			if GameState.infrastructure_manager:
				var count = GameState.infrastructure_manager.get_building_count(m["target"])
				m["current_qty"] = max(m["current_qty"], min(count, m["target_qty"]))

		# v143: kill-then-disengage. The kill is counted in _on_enemy_defeated (which
		# parks it in _kills, NOT current_qty, so the mission cannot self-complete on
		# the kill alone). Here we hold current_qty one short of target until the ship
		# is actually out of combat — that is the second half of the objective.
		# Deliberately a STATE check rather than a signal on retreat(): leaving by
		# zone-switch is an equally correct answer to "stop fighting before you walk
		# away", and this way combat_manager needs no new signal.
		elif m["type"] == "defeat_retreat":
			# Save compat: m017 shipped as plain "defeat". A save already holding the
			# kill has current_qty >= 1 but no _kills key, so seed it from current_qty
			# instead of resetting them to 0 and demanding a second drone.
			if not m.has("_kills"):
				m["_kills"] = int(m.get("current_qty", 0))
			var _k: int = int(m.get("_kills", 0))
			var _tq: int = int(m["target_qty"])
			var _out: bool = GameState.combat_manager != null and not GameState.combat_manager.in_combat
			m["current_qty"] = _tq if (_k >= _tq and _out) else min(_k, max(0, _tq - 1))

		# P2-12: Combat readiness checkpoint - checks loadout for weapon AND shield
		elif m["type"] == "loadout_check" and m["target"] == "combat_ready":
			var has_weapon = false
			var has_shield = false
			var sm = GameState.shipyard_manager
			for mid_equipped in sm.loadout.values():
				if mid_equipped and mid_equipped in sm.modules:
					var mod = sm.modules[mid_equipped]
					var st = mod.get("slot_type", "")
					if st == "weapon": has_weapon = true
					elif st == "shield": has_shield = true

			# Fail-safe: Check calculated stats (Base Corvette has 0 shield, >0 means shield equipped)
			if sm.max_shield > 0: has_shield = true
			# v119: hull base attack removed — aggregate attack is weapons-only now,
			# so any nonzero total means a weapon is equipped.
			if (sm.attack_kinetic + sm.attack_energy + sm.attack_explosive) > 0:
				has_weapon = true

			if has_weapon and has_shield:
				m["current_qty"] = 1

		# Per-module equip checkpoint — completes when ANY module of the
		# named slot_type is equipped. Used by the post-craft equip missions
		# (m007b engine / m022b battery / m015b weapon / m024c shield) to
		# close each module's craft → equip → use arc.
		elif m["type"] == "loadout_check":
			var slot_target: String = str(m["target"])
			var sm2 = GameState.shipyard_manager
			# v134g: COUNT filled slots of the type so a mission can require N (e.g.
			# m005c "equip 2 batteries"). target_qty 1 still completes at 1 filled.
			var filled := 0
			for mid_v in sm2.loadout.values():
				if mid_v and mid_v in sm2.modules:
					if sm2.modules[mid_v].get("slot_type", "") == slot_target:
						filled += 1
			m["current_qty"] = max(m["current_qty"], min(filled, m["target_qty"]))

		# v139f: owns any Matrix Core. matrix_synthesis outputs a RANDOM color/tier, so
		# match the whole category rather than a single symbol. Driven by inventory_updated
		# (matrix_synthesis emits it on craft) -> _on_shipyard_updated -> sync_progress.
		elif m["type"] == "craft_matrix":
			var have := 0
			for sym in ElementDB.CATEGORIES.get("matrix_cores", []):
				have += int(GameState.resources.get_element_amount(sym))
			m["current_qty"] = max(m["current_qty"], min(have, m["target_qty"]))

		# v139f: a Matrix Core has been socketed into a module the player owns.
		elif m["type"] == "socket_check":
			var socketed := _count_socketed_matrix_cores()
			m["current_qty"] = max(m["current_qty"], min(socketed, m["target_qty"]))

		elif m["type"] == "drop_rarity":
			var target_rarity = int(m["target"])
			var has_rarity = false
			var sm = GameState.shipyard_manager
			for inv_mid in sm.module_inventory:
				if sm.get_module_rarity(inv_mid) >= target_rarity:
					has_rarity = true
					break
			if not has_rarity:
				for equipped_mid in sm.loadout.values():
					if equipped_mid and sm.get_module_rarity(equipped_mid) >= target_rarity:
						has_rarity = true
						break
			if has_rarity:
				m["current_qty"] = 1

		elif m["type"] == "loadout_rare_weapon":
			var target_rarity = int(m["target"])
			var sm = GameState.shipyard_manager
			var has_weapon = false
			
			for mid_in_slot in sm.loadout.values():
				if mid_in_slot and mid_in_slot in sm.modules:
					if sm.get_module_rarity(mid_in_slot) >= target_rarity:
						if sm.modules[mid_in_slot].get("slot_type", "") == "weapon":
							has_weapon = true
							break
						
			if has_weapon:
				m["current_qty"] = 1

		# v119: equip N RARE+ weapons of a given damage type — teaches that the right
		# TYPE *and* tier matter (a rare explosive vs the kin/energy-resistant Z1 boss).
		elif m["type"] == "loadout_rare_weapon_type":
			var want_type: String = str(m["target"])
			var sm = GameState.shipyard_manager
			var cnt := 0
			for mid_in_slot in sm.loadout.values():
				if mid_in_slot and mid_in_slot in sm.modules:
					var md = sm.modules[mid_in_slot]
					if md.get("slot_type", "") == "weapon" and sm.get_module_rarity(mid_in_slot) >= 2:  # 2 = Rarity.RARE
						var st = md.get("stats", {})
						var wt := "kinetic"
						if st.get("atk_energy", 0) > 0: wt = "energy"
						elif st.get("atk_explosive", 0) > 0: wt = "explosive"
						elif st.get("atk_cryo", 0) > 0: wt = "cryo"
						if wt == want_type:
							cnt += 1
			m["current_qty"] = min(cnt, m["target_qty"])

		elif m["type"] == "equip_consumables":
			var required_qty = int(m["target"])
			var sm = GameState.shipyard_manager
			var hull_ok = false
			var shield_ok = false
			
			if sm.consumable_hull_slot != "":
				if GameState.resources.get_element_amount(sm.consumable_hull_slot) >= required_qty:
					hull_ok = true
			
			if sm.consumable_shield_slot != "":
				if GameState.resources.get_element_amount(sm.consumable_shield_slot) >= required_qty:
					shield_ok = true
					
			if hull_ok and shield_ok:
				m["current_qty"] = 1

		elif m["type"] == "warp_perform":
			if GameState.warp_manager:
				m["current_qty"] = max(m["current_qty"], min(GameState.warp_manager.total_warps, m["target_qty"]))

		elif m["type"] == "atlas_lookup":
			# Retroactive-safe: owning the named material means the player already found
			# it. It also self-heals a mid-chain insert (m019e) that orphan-rescue
			# spuriously re-activated on an OLD save long past that beat — auto-complete
			# so a stale lesson can't hijack the objective arrow.
			if GameState.resources and GameState.resources.get_element_amount(m["target"]) > 0:
				m["current_qty"] = m["target_qty"]

		if m["current_qty"] != old_qty:
			changed = true
			
		check_completion(m)
	
	if changed:
		mission_updated.emit()

func load_save_data_manager(data: Dictionary):
	if data.is_empty(): return
	var m_data = data.get("missions", {})
	active_missions.clear()
	for mid in m_data:
		if mid in missions:
			var saved = m_data[mid]
			var m = missions[mid]
			m["current_qty"] = saved.get("current_qty", 0.0)
			m["multi_progress"] = saved.get("multi_progress", {})
			m["completed"] = saved.get("completed", false)
			m["claimed"] = saved.get("claimed", false)
			m["active"] = saved.get("active", false)
			if m["active"] and not m["claimed"]:
				active_missions.append(mid)
	# Save migration: if a mission in the chain was removed in an update, the
	# player can end up stuck because the gone mission was their active link.
	# Walk every claimed mission and ensure its next_mission is activated.
	_rescue_orphan_chains()

func _rescue_orphan_chains():
	# For every claimed mission, make sure its next_mission is active or already claimed.
	# Iterates until no further activations happen (handles claimed-mission cascades).
	var changed = true
	while changed:
		changed = false
		for mid in missions:
			var m = missions[mid]
			if not m["claimed"]: continue
			var next_id: String = m.get("next_mission", "")
			if next_id == "" or not next_id in missions: continue
			var next_m = missions[next_id]
			if next_m["claimed"] or next_m["active"]: continue
			next_m["active"] = true
			if not next_id in active_missions:
				active_missions.append(next_id)
			changed = true

func reset():
	init_missions()

# v138d: self-heal — drop any CLAIMED mission that lingers in active_missions
# (stale save flags, historical claim paths, anything). A claimed mission must
# never drive navigation hints / objective chips again. Cheap (tiny array);
# called from main's hint ladder every frame and safe to call from anywhere.
func purge_claimed_actives() -> void:
	for i in range(active_missions.size() - 1, -1, -1):
		var m = missions.get(active_missions[i])
		if m == null or m["claimed"]:
			if m != null:
				m["active"] = false
			active_missions.remove_at(i)

func has_progress() -> bool:
	for mid in missions:
		var m = missions[mid]
		if m["claimed"] or m["completed"]:
			return true
	return false

func count_claimable_missions() -> int:
	# Total missions completed-but-not-yet-claimed across tutorial, chapter, endgame, and goal tracks.
	var n = 0
	for mid in active_missions:
		var m = missions.get(mid)
		if m and m["completed"] and not m["claimed"]:
			n += 1
	return n

func get_active_objective() -> Dictionary:
	# The single mission the header "Current Objective" chip should surface: prefer a
	# completed-unclaimed step (reads "CLAIM"), else the active tutorial step (m*),
	# else any active goal. Returns {} when there's nothing to show.
	var best: Dictionary = {}
	var best_rank := 99
	for mid in active_missions:
		var m = missions.get(mid)
		if m == null or m.get("claimed", false):
			continue
		var rank := 2
		if m.get("completed", false):
			rank = 0
		elif str(mid).begins_with("m"):
			rank = 1
		if rank < best_rank:
			best_rank = rank
			best = m
	return best

# v133: enemy ids the player is currently tasked to defeat (active, incomplete
# "defeat" missions). The Sector Chart marks these as OBJECTIVE so the player locks
# the RIGHT target instead of any hostile in the sector.
func get_active_defeat_targets() -> Array:
	var out: Array = []
	for mid in active_missions:
		var m = missions.get(mid)
		if m == null or m.get("completed", false) or m.get("claimed", false):
			continue
		if str(m.get("type", "")) == "defeat":
			var t := str(m.get("target", ""))
			if t != "" and not out.has(t):
				out.append(t)
	return out
