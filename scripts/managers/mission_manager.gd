extends RefCounted

# Verbose per-tick mission-progress tracing. Off in production (and during
# headless balance-sim runs, where it would emit tens of thousands of lines).
const DEBUG_LOG := false

# v134: added the mid-chapter beats (m027b bounty intro, m029a1-a5 AdvCircuit
# arc, m030i/m032a boss-core farms) — they sat between [CHAPTER 2] missions but
# rendered as [TUTORIAL], which read as the game mislabeling its own acts.
const CHAPTER_2_IDS = ["m027", "m027b", "m028", "m029",
	"m029a1", "m029a2", "m029a3", "m029a4", "m029a5", "m029b", "m030", "m030c",
	"m030e", "m030f", "m030g", "m030h", "m030i",
	"m031", "m032", "m032a", "m032b", "m032d", "m032c", "m033", "m033b", "m033c"]
const ENDGAME_IDS = ["m034"]

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
		["m001", "Stranded in Orbit", "Gather 350 Dirt to begin basic repairs.", "gather", "Dirt", 350, 600, 50, "m002"],
		# P-onboard: a single foundational research. Applied Physics + Fluid Dynamics were
		# folded into Basic Engineering, so one research opens refining, water, and the
		# ship/combat screens. m002b/m003 below are re-pointed to basic_engineering so any
		# in-flight save mid-chain auto-completes.
		["m002", "Foundational Research", "Open the Research tab and unlock Basic Engineering.", "research", "basic_engineering", 1, 900, 200, "m004"],
		# P0-30: Physics Paradox Fix - Applied Physics moved here
		["m002b", "Foundational Research", "Unlock Basic Engineering in the Research tab.", "research", "basic_engineering", 1, 300, 100, "m003"],
		["m003", "Pump Master", "Unlock Basic Engineering in the Research tab.", "research", "basic_engineering", 1, 300, 50, "m004"],
		["m004", "Hydration", "Gather 350 units of Water.", "gather", "Water", 350, 500, 100, "m005"],
		["m005", "Mineral Washing", "Open the Engineering page and process Dirt to extract 100 Silicon and 80 Iron.", "gather_multi", {"Si": 100, "Fe": 80}, 180, 1000, 200, "m007"],
		
		# m006 Removed (Moved to m002b)
		["m007", "Mobility Check", "Craft a 'Basic Thruster' in the Shipyard.", "craft", "z1_engine", 1, 1000, 100, "m007b"],
		# P1 Onboarding: close the engine arc — craft → equip. Without this the
		# Thruster sat in inventory and the player never saw its +Evasion effect.
		["m007b", "Spacewalk Test", "Open the Ship Designer, then DRAG the Basic Thruster from your Armory (right panel) onto an empty ENGINE slot.", "loadout_check", "engine", 1, 500, 100, "m008"],
		["m008", "Materials Science", "Research the 'Materials Science' hub.", "research", "materials_science", 1, 300, 100, "m009"],
		# v129: research-trip diet — the tutorial routed to Research ~8 times before the
		# first boss, which reads as homework. Five stops are cut from the CHAIN (m010,
		# m020, m014, m023, m018b) and the T1 starter-kit gates they served were unbound
		# (battery/missile recipes, T1 ammo equip). The missions stay DEFINED as orphans
		# so in-flight saves sitting on them still complete + chain onward (m003 pattern).
		# Research beats that remain early: m002 (tutorial), m008 (hub), m018, m025/m026
		# (batched: smelting -> power_systems -> shipwright_1 in one visit).
		["m009", "Deforestation", "Gather 100 units of Wood.", "gather", "Wood", 100, 500, 100, "m011"],
		["m010", "Organic Combustion", "Research 'Organic Combustion' to unlock the Kiln.", "research", "combustion", 1, 500, 150, "m011"],
		["m011", "Essential Carbon", "Use the Charcoal Kiln to produce 50 Carbon.", "gather", "C", 50, 600, 150, "m012"],
		["m012", "Lithium Discovery", "In the Mine page, extract 100 Lithium Ore.", "gather", "Spodumene", 100, 800, 200, "m013"],
		["m013", "Voltaic Storage", "Refine 50 Lithium in the Engineering tab.", "gather", "Li", 50, 1000, 250, "m013b"],
		["m013b", "Copper Prospecting", "Gather 100 Malachite Ore.", "gather", "Malachite", 100, 1200, 300, "m013c"],
		["m013c", "Conductivity", "Refine 50 Copper in the Engineering tab.", "gather", "Cu", 50, 1500, 350, "m021"],
		["m014", "Ballistics Theory", "Research 'Kinetic Weapons Theory' in the Research tree.", "research", "kinetics_101", 1, 1200, 100, "m015"],
		["m015", "Prototype Arsenal", "Craft a 'Mass Driver Mk.I' in the Shipyard.", "craft", "z1_kinetic", 1, 1500, 200, "m015b"],
		# P1 Onboarding: close the weapon arc — craft → equip. Ammo comes next
		# and now reads correctly as "feed your equipped weapon".
		["m015b", "Weapons Hot", "Open the Ship Designer, then DRAG the Mass Driver from your Armory (right panel) onto an empty WEAPON slot.", "loadout_check", "weapon", 1, 500, 100, "m016"],
		["m016", "Kinetic Munitions", "In the Engineering page, produce 100 Ferrite Rounds (SlugT1) to feed your weapon.", "gather", "SlugT1", 100, 1000, 100, "m024"],
		# Shield Section Moved Here (m023 -> m024)
		# P2-12: Combat Readiness Checkpoint - ensure player is equipped before first combat
		["m016b", "Combat Ready", "Equip a WEAPON and SHIELD in your Ship Designer.", "loadout_check", "combat_ready", 1, 300, 100, "m017"],
		["m017", "Target Locked", "Defeat 1 Lunar Drone in Lunar Orbit.", "defeat", "z1_lunar_drone", 1, 2500, 500, "m017a"],
		# v128: damage-triangle onboarding. The Lunar Drone (m017) taught KINETIC; this
		# pair teaches ENERGY against the energy-weak Survey Probe (resist_e -0.30, resists
		# kinetic +0.30). The EXPLOSIVE leg is the Scrap Collector pair (m017c/d).
		# (v131: the Rogue Architect boss has NO resists — pure rarity check.)
		["m017a", "Energy Doctrine", "Not every hostile falls to slugs. The Survey Probe RESISTS kinetic fire but is WEAK TO ENERGY. In the Shipyard, craft a 'Pulse Laser Mk.I'.", "craft", "z1_energy", 1, 1500, 200, "m017a2"],
		# v134: energy leg now mirrors the kinetic leg (craft -> produce ammo -> equip & fight).
		# It used to jump from craft straight to "destroy with Focus Crystals loaded" with NO
		# step that made the player PRODUCE the ammo — so a correctly-built laser fought empty.
		["m017a2", "Charge the Crystals", "The Pulse Laser runs on Focus Crystals. In the Engineering tab, produce 60 Focus Crystals (CellT1) — its ammunition.", "gather", "CellT1", 60, 1500, 200, "m017b"],
		["m017b", "Pulse Fire", "In the Ship Designer, drag your Pulse Laser onto a WEAPON slot (that auto-loads the Focus Crystals), then destroy a Survey Probe in Lunar Orbit. Energy melts what kinetic shrugged off — always match the weapon to the weakness.", "defeat", "z1_survey_probe", 1, 3000, 500, "m017c"],
		# v128: EXPLOSIVE leg — the Scrap Collector is now armored vs kinetic + energy and
		# WEAK to explosive (resist_x -0.30), so all three types are taught against regular
		# Lunar Orbit enemies. combustion is already researched at m010, so missiles craft here.
		["m017c", "Explosive Doctrine", "The Scrap Collector is armored against kinetic AND energy — but blows apart under EXPLOSIVE ordnance. In the Shipyard, craft a 'Micro-Missile Launcher'.", "craft", "z1_missile", 1, 1800, 250, "m017c2"],
		# v134: explosive leg scaffolds ammo like the others. It used to go craft ->
		# "destroy with HE Missiles loaded" with NO produce-ammo step (and equip_module
		# auto-loaded a phantom "missile" ammo id instead of MissileT1 — both now fixed).
		["m017c2", "Stock the Warheads", "The launcher fires HE Missiles. In the Engineering tab, produce 60 HE Missiles (MissileT1) — its ammunition.", "gather", "MissileT1", 60, 1800, 250, "m017d"],
		["m017d", "Warhead", "In the Ship Designer, drag your Micro-Missile Launcher onto a WEAPON slot (that auto-loads the HE Missiles), then destroy a Scrap Collector in Lunar Orbit. Three weapon types, three weaknesses — now you command the damage triangle.", "defeat", "z1_scrap_collector", 1, 3500, 600, "m018"],
		["m018", "Industrial Logistics", "Research the 'Industrial Logistics' hub.", "research", "industrial_logistics", 1, 500, 100, "m019"],
		["m018b", "Automated Intelligence", "Research 'Automated Logistics' for circuitry.", "research", "automated_logistics", 1, 1000, 200, "m019"],
		# v134: the Circuit recipe needs TIN (Sn) — a material the chain never introduced
		# (Cassiterite mining was only taught at m028, nine missions later). Name the
		# full path so the player isn't stared down by an unexplained missing input.
		["m019", "Cybernetic Integration", "Craft 10 Basic Circuitry in the Engineering tab. Its recipe needs Tin: mine Cassiterite in the Mine page, then smelt it into Tin (Engineering tab) first.", "gather", "Circuit", 10, 2000, 300, "m019b"],
		# P-onboard: close two long-standing teaching holes before the smelting push.
		# Both are visit_page (auto-complete on navigation → can never soft-lock) and
		# fire the existing per-page coach card the moment the player lands.
		["m019b", "Cargo Hold", "Open your Inventory (left sidebar). Cargo is slot-limited — when it fills, NEW gathered materials are LOST, not paused. Expand storage here as you take on more material types.", "visit_page", "inventory", 1, 2000, 200, "m019c"],
		["m019c", "Background Industry", "Open Infrastructure (left sidebar). Buildings auto-produce in the background — always running while you gather, fight, or are offline. Build them whenever you can; the background should always pay.", "visit_page", "infrastructure", 1, 2000, 200, "m025"],
		["m020", "Advanced Energy", "Research 'Power Systems' for batteries.", "research", "power_systems", 1, 500, 100, "m021"],
		["m021", "Industrial Energy", "Craft 5 Basic Batteries in the Engineering tab.", "gather", "BatteryT1", 5, 1000, 100, "m022"],
		["m022", "Power Storage", "Craft a 'Basic Battery' in the Shipyard.", "craft", "z1_battery", 1, 1500, 150, "m022b"],
		# P1 Onboarding: close the energy arc — craft → equip. Without this the
		# Battery was a one-and-done craft with no ship-state payoff.
		["m022b", "Power Online", "Open the Ship Designer, then DRAG the Basic Battery from your Armory (right panel) onto an empty BATTERY slot.", "loadout_check", "battery", 1, 500, 100, "m015"],
		["m023", "Hull Integrity", "Research 'Energy Fields' to unlock shielding.", "research", "energy_shields", 1, 1000, 150, "m024"],
		["m024", "Aegis System", "Craft a 'Basic Shield' for protection.", "craft", "z1_shield", 1, 2500, 200, "m024c"],
		# P1 Onboarding: close the shield arc — craft → equip. Player sees
		# max_shield jump from 0 → positive the moment it seats.
		["m024c", "Shields Up", "Open the Ship Designer, then DRAG the Basic Shield from your Armory (right panel) onto an empty SHIELD slot. Incoming damage hits the shield before your hull.", "loadout_check", "shield", 1, 500, 100, "m024b"],
		# Split for onboarding: teach what consumables are + where to make them,
		# THEN how to equip them (was one sudden compound objective).
		# v134: "Processing page" — no such page exists; the sidebar label is Engineering.
		["m024b", "Field Supplies", "Repair kits keep you alive in combat. In the Engineering page, craft 5 Emergency Hull Patches and 5 Basic Shield Boosters.", "gather_multi", {"EmergencyPatch": 5, "BasicBooster": 5}, 10, 2000, 150, "m024b2"],
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
		["m016c", "Combat Briefing", "Open the Combat page (left sidebar). Pick a sector → pick a target → ENGAGE. Your Shield absorbs hits first; your Hull takes overflow. Auto-consumables fire when each drops below the threshold you set in Research.", "visit_page", "combat", 1, 200, 50, "m017"],
		# v132: smelting's tree parent is Organic Combustion — name BOTH so the
		# player isn't surprised by a locked node (one Research visit, two clicks).
		["m025", "Refining Mastery", "Research 'Organic Combustion', then 'Efficient Smelting' beneath it, for alloys.", "research", "smelting", 1, 15000, 500, "m025a"],
		# v134: modern smelting now consumes Oxygen (Basic-Oxygen furnace), so teach
		# electrolysis BEFORE the first steel — otherwise the steel recipe silently needs
		# an input the tutorial never introduced. Electrolysis also feeds the later O/H
		# recipes (zinc/nickel roasting, missile propellant). 50 steel = 10 crafts = 20 O.
		["m025a", "Split the Water", "Modern foundries burn Oxygen. In the Engineering tab, run Water Electrolysis to split Water into Hydrogen and Oxygen — stock 30 Oxygen (O).", "gather", "O", 30, 3000, 300, "m025b"],
		["m025b", "Alloy Production", "Now smelt 50 Steel in the Engineering tab — the Basic-Oxygen furnace blows your Oxygen through the molten iron (Basic Steel Smelting recipe).", "gather", "Steel", 50, 5000, 500, "m026"],
		["m026", "Master Constructor", "Research 'Shipwright I' for hull reinforcement.", "research", "shipwright_1", 1, 5000, 500, "m026b"],
		["m026b", "Hull Modernization I", "Construct an 'Industrial Frigate' in the Shipyard.", "construct", "frigate_hull", 1, 10000, 1000, "m026c"],
		["m026c", "Elite Salvage", "Defeated enemies drop gear of varying rarity. Farm Lunar Orbit until you get a RARE (blue) module drop.", "drop_rarity", "2", 1, 5000, 500, "m026d"],
		# v131: Architect resists zeroed — chain goes straight to the boss fight; any
		# RARE+ weapon type works. m026d2/d3 (the old explosive-forcing pair) stay
		# DEFINED below for saves mid-arc, but no fresh game routes into them.
		["m026d", "Combat Overhaul", "Equip at least 1 RARE+ Weapon.", "loadout_rare_weapon", "2", 1, 10000, 1000, "m026e"],
		# v119: type-matching teach beat before the Z1 boss. The Architect RESISTS
		# kinetic + energy (+0.25) but is WEAK to explosive (-0.30), so the right TYPE
		# beats raw rarity. Combustion is already unlocked (smelting required it at m025).
		["m026d2", "Munitions Run", "Produce 60 HE Missiles in the Engineering tab to arm a missile launcher — explosive warheads punch through armor better than anything else.", "gather", "MissileT1", 60, 8000, 800, "m026d3"],
		["m026d3", "Explosive Payload", "Equip a RARE+ EXPLOSIVE weapon — explosive fire ignores most enemy armor, and the rare-tier punch ends fights fast.", "loadout_rare_weapon_type", "explosive", 1, 12000, 1200, "m026e"],
		["m026e", "Final Confrontation", "Defeat the Rogue Architect boss in Lunar Orbit.", "defeat", "z1_boss_architect", 1, 25000, 2500, "m027"],
		# P0 Fix: Progression Deadlock Re-alignment
		["m027", "Scanning Horizon", "Research 'Asteroid Belt Authorization' in the Research tree to unlock the Asteroid Belt combat zone.", "research", "zone_2_access", 1, 5000, 500, "m027b"],
		# P-onboard: introduce the Bounty Board the moment it unlocks (Asteroid Belt).
		# visit_page → auto-completes on navigation, can never soft-lock.
		["m027b", "Open Contracts", "Open the Bounty Board (left sidebar — it just unlocked). Accept a contract: it pays out in the background while you do anything else. Optional, always-on income.", "visit_page", "bounty", 1, 6000, 500, "m028"],
		["m028", "Belt Mining", "In the Mine page, mine 100 Cassiterite (tin ore).", "gather", "Cassiterite", 100, 10000, 2000, "m029"],
		["m029", "Hardened Shell", "Craft 'Carbon Fiber Plate' in the Shipyard.", "craft", "z2_armor", 1, 15000, 5000, "m029a1"],
		# v107 Mission flow — split the silent AdvCircuit wall into discoverable
		# beats (Koster pattern-injection). m029b previously dropped the player
		# off a cliff: lvl 45 Engineering + 4 unnamed research gates + a 5-input
		# recipe none of whose intermediates had been introduced. Each beat
		# below surfaces ONE node and delivers materials the final mission needs.
		# Save-compat: in-flight players sitting on m029b stay valid (it still
		# exists with the same id); only m029.next_mission_id was rerouted.
		["m029a1", "Material Sciences", "Research 'Advanced Materials' in the Research tree to unlock heavier industrial recipes.", "research", "adv_materials", 1, 5000, 500, "m029a2"],
		["m029a2", "Structural Doctrine", "Research 'Advanced Metallurgy' to fabricate universal components.", "research", "metallurgy_advanced", 1, 5000, 500, "m029a3"],
		["m029a3", "First Components", "Craft 10 Structural Components in the Engineering tab. They are the universal building block of heavy industry.", "gather", "StructuralComponent", 10, 8000, 1000, "m029a5"],
		# v132: ORPHANED (m029a3 → m029a5). Combustion is already owned by this
		# point — it's Efficient Smelting's tree parent, bought at m025 — so this
		# beat auto-completed the instant it appeared. Kept for in-flight saves.
		["m029a4", "Chemical Heat", "Research 'Organic Combustion' to unlock Germanium extraction (needed for semiconductors).", "research", "combustion", 1, 5000, 500, "m029a5"],
		["m029a5", "Factory Lights", "Research 'Factory Automation' — the last gate before Advanced Circuits.", "research", "automation", 1, 10000, 1000, "m029b"],
		["m029b", "Complex Electronics", "Craft 5 Advanced Circuits in the Engineering tab. (Combines Semiconductor + Gold + Silver + Tin + Structural Components — your earlier research unlocked each one.)", "gather", "AdvCircuit", 5, 20000, 5000, "m030"],
		# v103f: Removed forced Fabricator mission (m030b) — it gated nothing
		# (Fabricator is optional QoL, still buildable). m030 -> m030c directly.
		["m030", "Naval Expansion", "Research 'Shipwright II' to unlock Destroyer-class hulls.", "research", "shipwright_2", 1, 4000, 1000, "m030c"],
		["m030c", "Hull Modernization II", "Construct a 'Destroyer' hull in the Shipyard.", "construct", "destroyer_hull", 1, 25000, 2000, "m030e"],
		# Mission bridge from Asteroid Belt to Sector Alpha (zones 3-4 introduction)
		["m030e", "Mars Beachhead", "Research 'Mars Debris Clearance' in the Research tree to unlock the Mars Debris combat zone.", "research", "zone_3_access", 1, 40000, 5000, "m030f"],
		["m030f", "Salvage Operations", "Defeat 3 Scavenger Mechs in the Mars Debris combat zone. Their relics feed Wreckforged Alloy crafting.", "defeat", "z3_scavenger_mech", 3, 60000, 8000, "m030g"],
		["m030g", "Glacier Belt Survey", "Research 'Glacier Belt Expedition' in the Research tree to unlock the Glacier Belt combat zone.", "research", "zone_4_access", 1, 80000, 10000, "m030h"],
		["m030h", "Frozen Frontier", "Defeat 3 Ice Wraiths in the Glacier Belt. Glacial Essence powers cryo-alloy and coolant crafting.", "defeat", "z4_ice_wraith", 3, 100000, 12000, "m030i"],

		# v132 funnel repair (m030i..m034): the tail directed the WRONG techs.
		# The real sector doors are zone_5/6/7_access and each costs BOSS CORES
		# (Z4_Core x2, Z5_Core x3, Z6_Core x3) the chain never told the player to
		# farm. sector_alpha_decryption is an optional scan child; deep_space_nav/
		# radiation_shielding are the Exotics research branch, NOT zone unlocks —
		# their old mission texts lied. New boss-farm beats (m030i, m032a) feed
		# the cores, research beats now target the actual doors, and the tail is
		# reordered m033 → m034 (Beta boss farm) → m033b (Gamma door) → m033c.
		["m030i", "Overseer's Core", "The Sector Alpha charter is encrypted — decrypting it takes two GLACIAL OVERSEER cores. Defeat the Glacier Belt boss twice and salvage them.", "defeat", "z4_boss_overseer", 2, 120000, 15000, "m031"],
		["m031", "Alpha Decryption", "Research 'Sector Alpha Decryption' in the Research tree (it consumes the Overseer cores) to breach Sector Alpha.", "research", "zone_5_access", 1, 50000, 10000, "m032"],
		["m032", "Alpha Sector Dominance", "Defeat 3 Alien Frigates in Sector Alpha.", "defeat", "z5_alien_frigate", 3, 75000, 15000, "m032a"],
		["m032a", "Harbinger Hunt", "The Beta Colony Charter demands three XENON HARBINGER cores. Defeat the Sector Alpha boss three times.", "defeat", "z5_boss_harbinger", 3, 150000, 20000, "m032b"],
		["m032b", "Beta Colony Charter", "Research 'Beta Colony Charter' in the Research tree (it consumes the Harbinger cores) to unlock Sector Beta.", "research", "zone_6_access", 1, 50000, 5000, "m032d"],
		["m032d", "Void Research", "Void Artifacts drop from Sector Alpha ships — defeat them in Combat until you collect 5.", "gather", "VoidArtifact", 5, 100000, 10000, "m032c"],
		# P0-28: Construct Battlecruiser
		["m032c", "Capital Doctrine", "Construct a 'Battlecruiser' in the Shipyard.", "construct", "battlecruiser_hull", 1, 250000, 25000, "m033"],

		["m033", "Beta Sector Expansion", "Defeat 5 Ore Guardians in Sector Beta to expand your influence.", "defeat", "z6_ore_guardian", 5, 150000, 25000, "m034"],
		["m034", "Break the Blockade", "Defeat the BETA COLOSSUS 3 times — its cores are the key to Gamma Sector Clearance.", "defeat", "z6_boss_colossus", 3, 300000, 50000, "m033b"],
		["m033b", "Gamma Clearance", "Research 'Gamma Sector Clearance' in the Research tree (it consumes the Colossus cores) to unlock Sector Gamma.", "research", "zone_7_access", 1, 100000, 10000, "m033c"],
		["m033c", "Titan Construction", "Construct a 'Dreadnought' in the Shipyard. Its blueprints sit behind 'Delta Sector Survey' research — four Sector Gamma boss cores. The final climb is yours to chart.", "construct", "dreadnought_hull", 1, 1000000, 50000, ""],
		# v134: goal XP re-tuned now that reward_xp is actually GRANTED (it was a dead
		# field). Legacy values (1M/250K/2M) were written when XP paid nothing — live,
		# they'd insta-level a skill past the 30%-retention warp design. Sized as
		# one-time "lamps": a satisfying chunk (~1-3 levels at claim era), not a skip.
		["goal_001", "THE GREAT EXPEDITION", "Reach Sector Epsilon and discover the Primordial Core.", "discover", "sector_epsilon", 1, 0, 250000, ""],
		["goal_002", "INTO THE VOID", "Perform your first Warp. Your Liras and materials reset, but you gain Exotic Matter Shards for permanent multipliers that make each run stronger.", "warp_perform", "warp", 1, 0, 50000, ""],
		["goal_003", "PRESTIGE VETERAN", "Perform 5 Warps total to fully unlock Warp Tier scaling.", "warp_perform", "warp", 5, 0, 500000, ""],
		["goal_cryo_1", "FORGE CRYOGENIC ARMS", "The Threshold (Sector 11) is warp-hardened - only Cryo weapons breach it. Research Cryogenic Armaments in the new Warp Tech research tab.", "research", "cryo_armaments", 1, 3000000, 0, "goal_cryo_2"],
		["goal_cryo_2", "FORGE CRYOGENIC ARMS", "Craft a Cryo Lance in the Shipyard. It needs Cryo Catalyst - farm it from Sector 10 enemies.", "craft", "cryo_lance", 1, 6000000, 0, "goal_cryo_3"],
		["goal_cryo_3", "BREACH THE THRESHOLD", "Destroy a Warp Revenant in The Threshold (Sector 11) with your Cryo armaments.", "defeat", "z11_warp_revenant", 1, 15000000, 0, ""],
		# v128: Hack-Card onboarding arc (research -> loot -> apply). Reveals once
		# kinetics_101 is researched (~Sector 3), right as the loot-refine need appears.
		# Step 2 uses the "gather" type: element_added fires for combat loot too, so a
		# dropped Splice Chip counts. Step 3 uses the new "hack_apply" type.
		["goal_hack_1", "REWRITE THE FIRMWARE", "Salvaged modules can be re-forged. Research Firmware Hacking (Combat research tab) to unlock Hack Cards — module affix crafting.", "research", "firmware_hacking", 1, 20000, 0, "goal_hack_2"],
		["goal_hack_2", "SALVAGE A HACK CARD", "Hack Cards now drop in combat. Defeat enemies until a Splice Chip drops.", "gather", "SpliceChip", 1, 15000, 0, "goal_hack_3"],
		["goal_hack_3", "AWAKEN A MODULE", "Open the Ship Designer and drag a Splice Chip onto a Common component to awaken it into a custom module with a random affix.", "hack_apply", "SpliceChip", 1, 30000, 0, ""],
		# v130: Boost-Card onboarding arc (craft -> install). Reveals once Engineering
		# hits the fabricate recipe's level (45). Step 1 uses "gather" (element_added
		# fires for processing outputs); step 2 uses the new "overclock_install" type.
		["goal_boost_1", "OVERCLOCK PROTOCOL", "Your grid can run hotter. Fabricate a Boost Card in the Engineering tab — it takes Advanced Circuits, Superalloy, and a Quantum Core (Sector Alpha hostiles drop them).", "gather", "BoostCard", 1, 40000, 0, "goal_boost_2"],
		["goal_boost_2", "RUNNING HOT", "Open Infrastructure and INSTALL the Boost Card on a building you own — it permanently unlocks that building type's Efficiency slider up to 200%. Careful: output scales linearly, but input draw scales QUADRATICALLY past 100% (200% output costs 4x input).", "overclock_install", "BoostCard", 1, 60000, 0, ""]
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
		if mid.begins_with("m"):
			if mid in ENDGAME_IDS:
				m_name = "[ENDGAME] " + m_name
			elif mid in CHAPTER_2_IDS:
				m_name = "[CHAPTER 2] " + m_name
			else:
				m_name = "[TUTORIAL] " + m_name
		else:
			m_name = "[CORE GOAL] " + m_name
		
		missions[mid] = {
			"id": mid,
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

func _grant_reward_xp(m: Dictionary) -> void:
	var xp: float = float(m["reward_xp"])
	if xp <= 0.0:
		return
	var skill = null
	match str(m["type"]):
		"defeat", "discover", "drop_rarity", "loadout_check", "loadout_rare_weapon", \
		"loadout_rare_weapon_type", "equip_consumables", "warp_perform", "hack_apply":
			skill = GameState.combat_manager
		"gather", "gather_multi":
			skill = GameState.processing_manager if _is_processed_target(m["target"]) else GameState.gathering_manager
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
	return changed

func _reveal_goal(gid: String) -> bool:
	if not gid in missions: return false
	var m = missions[gid]
	if m["active"] or m["completed"]: return false
	m["active"] = true
	if not gid in active_missions:
		active_missions.append(gid)
	return true

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
			var slot_filled = false
			for mid_v in sm2.loadout.values():
				if mid_v and mid_v in sm2.modules:
					if sm2.modules[mid_v].get("slot_type", "") == slot_target:
						slot_filled = true
						break
			if slot_filled:
				m["current_qty"] = 1

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
