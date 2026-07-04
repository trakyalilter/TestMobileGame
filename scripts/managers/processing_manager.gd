extends Skill

var is_active: bool = false
var current_recipe: Dictionary = {}
var current_recipe_id: String = ""
var action_progress: float = 0.0

var events: Array = []

# P1 Mastery — per-recipe long-tail layered learning. Mirror of gathering's
# mastery: milestones at 10/25/50/75/100, table-driven cumulative duration
# reductions (cap 30%). Lv 50 is the "big-step" milestone (+10% in one shot)
# replacing the cut alt-recipe unlock; Lv 100 still grants the Hearthstone
# gold-tier cosmetic. Persists across warps; cleared only on hard reset.
const MASTERY_XP_PER_COMPLETION := 1.0
const MASTERY_MILESTONES: Array[int] = [10, 25, 50, 75, 100]
# v109: cumulative bonus table, index = milestones_passed (0..5). Mirrors
# gathering_manager.MASTERY_DURATION_BONUS_TABLE so the two skills stay in
# lockstep — the player only learns one curve.
const MASTERY_DURATION_BONUS_TABLE: Array[float] = [0.0, 0.05, 0.10, 0.20, 0.25, 0.30]
const MASTERY_DURATION_BONUS_MAX := 0.30
const MASTERY_LEVEL_CAP := 100

var mastery: Dictionary = {}  # {recipe_id: xp_total_float}

var recipes: Dictionary = {
	"charcoal_burning": {
		"name": "Charcoal Kiln",
		"description": "Burn Wood to produce Carbon. The backbone of metallurgy.",
		"input": {"Wood": 5},
		"output": {"C": 16},
		"duration": 4.0,
		"level_req": 2,
		"xp": 5,
		"category": "basics"
	},
	"electrolysis": {
		"name": "Water Electrolysis",
		"description": "Split Water into Hydrogen and Oxygen.",
		"input": {"Water": 5},
		"output": {"H": 20, "O": 10},
		"duration": 2.0,
		"level_req": 2,
		"xp": 5,
		"research_req": "basic_engineering",
		"category": "basics"
	},
	"centrifuge_dirt": {
		"name": "Mineral Washing",
		"description": "Wash Dirt with Water to extract Iron more efficiently.",
		"input": {"Dirt": 5, "Water": 5},
		"output": {"Fe": 5, "Si": 3},
		"duration": 3.0,
		"level_req": 1,
		"xp": 5,
		"research_req": "basic_engineering",
		"category": "basics"
	},
	"smelt_steel_basic": {
		"name": "Basic Steel Smelting",
		"description": "Basic-oxygen furnace — blow Oxygen through the molten Iron and Carbon to burn off impurities into Steel.",
		"input": {"Fe": 5, "C": 2, "O": 2},
		"output": {"Steel": 5},
		"duration": 5.0,
		"level_req": 12,
		"xp": 20,
		"research_req": "smelting"
	},
	"smelt_copper": {
		"name": "Copper Smelting",
		"description": "Refine Malachite ore into pure Copper.",
		"input": {"Malachite": 2, "C": 1},
		"output": {"Cu": 1},
		"duration": 5.0,
		"level_req": 5,
		"xp": 15,
		"research_req": "basic_engineering"
	},
	"smelt_zinc": {
		"name": "Zinc Reduction",
		"description": "Roast the Zinc sulfide ore in Oxygen, then reduce with Carbon.",
		"input": {"ZincOre": 3, "C": 1, "O": 1},
		"output": {"Zn": 2},
		"output_table": [["Ag", 0.4, 1, 1]], # v80.4 Fix: Ag byproduct added to Zn refining (fixes catalyst deadlock)
		"duration": 4.0,
		"level_req": 18,
		"xp": 12
	},
	# ========== AUDIT v39.0: MISSING ORE REFINING ==========
	"refine_cassiterite": {
		"name": "Tin Smelting",
		"description": "Smelt Cassiterite to extract Tin (Sn).",
		"input": {"Cassiterite": 3, "C": 1},
		"output": {"Sn": 2},
		"duration": 6.0,
		"level_req": 12,
		"xp": 25,
		"research_req": "basic_engineering"
	},
	"refine_pentlandite": {
		"name": "Nickel Extraction",
		"description": "Roast Pentlandite sulfide in Oxygen, then reduce with Carbon for Nickel (Ni).",
		"input": {"Pentlandite": 3, "C": 1, "O": 1},
		"output": {"Ni": 2},
		"output_table": [["Co", 0.4, 1, 1]], # v80.4 Fix: Co byproduct added to Ni refining (fixes major deadlock)
		"duration": 6.0,
		"level_req": 22,
		"xp": 30,
		"research_req": "smelting"
	},
	"refine_chromite": {
		"name": "Chromium Reduction",
		"description": "Reduce Chromite to Chromium (Cr) via aluminum thermite.",
		"input": {"Chromite": 3, "Al": 1},
		"output": {"Cr": 2},
		"duration": 8.0,
		"level_req": 25,
		"xp": 35,
		"research_req": "metallurgy_advanced"
	},
	"smelt_quartz": {
		"name": "Silicon Smelting",
		"description": "Refine Quartz into industrial Silicon.",
		"input": {"Quartz": 2, "C": 1},
		"output": {"Si": 1},
		"duration": 6.0,
		"level_req": 20,
		"xp": 20
	},
	# v131: Quartz's second purpose — polished into a Focusing Crystal, the optics
	# core every mid+ energy & cryo beam weapon needs (see shipyard weapon costs).
	"cut_focusing_crystal": {
		"name": "Cut Focusing Crystal",
		"description": "Polish Quartz into a Focusing Crystal — optics for energy & cryo weapons.",
		"input": {"Quartz": 6},
		"output": {"FocusingCrystal": 1},
		"duration": 5.0,
		"level_req": 18,
		"xp": 22,
		"category": "components"
	},
	"smelt_steel_oxygen": {
		"name": "Oxygen-Enriched Smelting",
		"description": "Use Oxygen to blast smelt Steel efficiently. Manganese deoxidises the melt for a higher yield.",
		"input": {"Fe": 10, "C": 4, "O": 4, "Mn": 2},
		"output": {"Steel": 10},
		"duration": 5.0,
		"level_req": 40,
		"xp": 25,
		"research_req": "smelting"
	},
	"press_graphite": {
		"name": "Graphite Press",
		"description": "Compress Carbon into high-density Graphite.",
		"input": {"C": 5},
		"output": {"Graphite": 1},
		"duration": 6.0,
		"level_req": 25, # Increased from 5
		"xp": 20, # Reduced from 25
		"research_req": "adv_materials"
	},
	"analyze_artifact": {
		"name": "Analyze Void Artifact",
		"description": "Decipher the secrets of the artifact.",
		"input": {"VoidArtifact": 1},
		# Dynamic Output
		"output_table": [
			["Cu", 1.0, 10, 20],
			["Chip", 0.3, 1, 2],
			["NavData", 0.2, 1, 2],
			["AncientTech", 0.05, 1, 1] # v80.4 Fix: Renamed from AncientComponent to match Costs
		],
		"duration": 10.0,
		"level_req": 50, # Increased from 5
		"xp": 200, # Increased from 100
		"research_req": "xeno_archaeology"
	},
	"decrypt_nav_data": {
		"name": "Decrypt Nav-Data",
		"description": "Synthesize navigation data from salvaged schematics and Liras.",
		"input": {"SalvageData": 5},
		"credits_cost": 500, # Manual check in implementation or handled via logic
		"output": {"NavData": 1},
		"duration": 30.0,
		"level_req": 20,
		"xp": 50,
		"research_req": "basic_engineering"
	},


	# Research Fragment Upgrade Chain
	"upgrade_rare_artifact": {
		"name": "Synthesize Rare Artifact",
		"description": "Combine Common artifacts and recovered Martian relics with circuits to create Rare research data.",
		"input": {"Res1": 100, "Circuit": 10, "MartianRelics": 5},
		"output": {"Res2": 1},
		"duration": 8.0,
		"level_req": 35, # Increased from 8
		"xp": 100, # Increased from 50
		"research_req": "smelting"
	},
	"upgrade_exotic_artifact": {
		"name": "Compile Exotic Artifact",
		"description": "Merge Rare artifacts with advanced tech to unlock capital-class research.",
		"input": {"Res2": 5, "AdvCircuit": 2, "NavData": 5, "XenoFragment": 3},
		"output": {"Res3": 1},
		"duration": 60.0,
		"level_req": 60, # Increased from 15
		"xp": 300, # Increased from 150
		"research_req": "sector_alpha_decryption"
	},
	"craft_carbon_fiber": {
		"name": "Carbon Fiber",
		"description": "Reinforce Carbon strands.",
		"input": {"C": 3},
		"output": {"Fiber": 1},
		"duration": 5.0,
		"level_req": 8, # Increased from 2
		"xp": 10, # Reduced from 15
		"research_req": "combustion"
	},
	"craft_polymer": {
		"name": "Polymer Resin",
		"description": "Synthesize resin from hydrocarbons.",
		"input": {"C": 1, "H": 2, "O": 1},
		"output": {"Resin": 1},
		"duration": 5.0,
		"level_req": 10, # Increased from 2
		"xp": 10, # Reduced from 15
	},
	"craft_aluminum_alloy": {
		"name": "Aluminum-Magnesium Alloy",
		"description": "Lightweight aerospace alloy. High strength-to-weight ratio.",
		"input": {"Al": 3, "Mg": 1},
		"output": {"AlMgAlloy": 2},
		"duration": 5.0,
		"level_req": 24,
		"xp": 30,
		"research_req": "lightweight_alloys"
	},
	"galvanize_steel": {
		"name": "Galvanized Steel",
		"description": "Zinc-coated steel. Corrosion resistant.",
		"input": {"Steel": 2, "Zn": 1},
		"output": {"GalvanizedSteel": 2},
		"duration": 4.0,
		"level_req": 25,
		"xp": 40,
		"research_req": "smelting"
	},
	"craft_stainless_steel": {
		"name": "Stainless Steel Alloy",
		"description": "Fe-Cr-Ni alloy. Superior corrosion resistance and strength.",
		"input": {"Fe": 5, "Cr": 2, "Ni": 1},
		"output": {"StainlessSteel": 4},
		"duration": 8.0,
		"level_req": 30,
		"xp": 60,
		"research_req": "metallurgy_advanced"
	},
	# Audit v2.0: Early consumables for combat accessibility
	"craft_emergency_patch": {
		"name": "Emergency Hull Patch",
		"description": "Quick patch from basic metals. Restores 10% Hull Integrity.",
		"input": {"Fe": 20,},
		"output": {"EmergencyPatch": 1},
		"duration": 10.0,
		"level_req": 1,
		"xp": 10,
		"category": "consumables_hull"
	},
	# v62.0 Fix: Added Consumer for AlWire and Circuit
	"craft_adv_maintenance_kit": {
		"name": "Adv. Maintenance Kit",
		"description": "High-tech repair kit. Restores 50% Hull Integrity. Galvanised plating and zinc inhibitor resist corrosion.",
		"input": {"AlWire": 3, "Circuit": 5, "Superalloy": 1, "Steel": 50, "Ti": 15, "Zn": 4, "GalvanizedSteel": 5},
		"output": {"AdvMaintenanceKit": 1},
		"duration": 15.0,
		"level_req": 40,
		"xp": 40,
		"research_req": "basic_electronics",
		"category": "consumables_hull"
	},
	"craft_capacitor_shard": {
		"name": "Capacitor Shard",
		"description": "Basic energy storage. Restores 10% Shield Integrity.",
		"input": {"Si": 5, "Al": 2},
		"output": {"CapacitorShard": 1},
		"duration": 5.0,
		"level_req": 20,
		"xp": 20,
		"category": "consumables_shield"
	},
	"craft_basic_booster": {
		"name": "Basic Shield Booster",
		"description": "Crude energy cells. Restores 15% Shield Integrity.",
		"input": {"Si": 20, "BatteryT1": 1},
		"output": {"BasicBooster": 1},
		"duration": 10.0,
		"level_req": 2,
		"xp": 5,
		"category": "consumables_shield"
	},
	"craft_ion_field": {
		"name": "Ion Field Projector",
		"description": "Projected ion barrier. Restores 25% Shield Integrity.",
		"input": {"AlWire": 5, "MgBattery": 1},
		"output": {"IonField": 1},
		"duration": 15.0,
		"level_req": 18,
		"xp": 25,
		"research_req": "basic_electronics",
		"category": "consumables_shield"
	},
	"craft_nanoweave": {
		"name": "Nanoweave Mesh",
		"description": "Weave fiber for hull reinforcement. Restores 25% Hull Integrity.",
		"input": {"Fiber": 5, "Si": 10},
		"output": {"Mesh": 1},
		"duration": 15.0,
		"level_req": 15, # Rebalanced
		"xp": 25, # Reduced from 30
		"category": "consumables_hull"
	},
	"craft_sealant": {
		"name": "Hull Sealant",
		"description": "Mix polymer for rapid hull patching. Restores 35% Hull Integrity.",
		"input": {"Resin": 10, "Steel": 8},
		"output": {"Seal": 1},
		"duration": 15.0,
		"level_req": 25, # Rebalanced
		"xp": 30, # Reduced from 40
		"research_req": "metallurgy_advanced",
		"category": "consumables_hull"
	},
	"craft_chitin_patch": {
		"name": "Biosynthetic Hull Patch",
		"description": "Utilize mite chitin for emergency hull repairs. Restores 15% Hull Integrity.",
		"input": {"MiteChitin": 10, "Steel": 5},
		"output": {"ChitinPatch": 1},
		"duration": 8.0,
		"level_req": 5,
		"xp": 8,
		"research_req": "basic_engineering",
		"category": "consumables_hull"
	},
	"craft_slug_t1": {
		"name": "Ferrite Rounds",
		"description": "Mass produce iron slugs.",
		"input": {"Fe": 1},
		"output": {"SlugT1": 20},
		"duration": 5.0,
		"level_req": 1,
		"xp": 5 # Reduced from 10
	},
	"craft_cell_t1": {
		"name": "Focus Crystal",
		"description": "Cut silicate for lenses.",
		"input": {"Si": 1},
		"output": {"CellT1": 20},
		"duration": 5.0,
		"level_req": 2, # Increased from 1
		"xp": 7 # Reduced from 10
	},
	"craft_slug_t2": {
		"name": "Tungsten Sabot",
		"description": "Heavy kinetic penetrators.",
		"input": {"Steel": 1, "W": 1},
		"output": {"SlugT2": 20},
		"duration": 10.0,
		"level_req": 24, # v126: 32->24 — closes the W idle gap (Tungsten gathers at lvl 20; this is its first real sink)
		"xp": 40,
		"research_req": "processing_tungsten"
	},
	"craft_slug_t1s": {
		"name": "Steel Slugs",
		"description": "Armor-piercing heavy slugs.",
		"input": {"Steel": 1},
		"output": {"SlugT1S": 20},
		"duration": 10.0,
		"level_req": 24,
		"xp": 20
	},
	"craft_cell_t2": {
		"name": "Plasma Cell",
		"description": "Contain superheated gas.",
		"input": {"H": 5, "Resin": 1},
		"output": {"CellT2": 20},
		"duration": 10.0,
		"level_req": 34, # Increased from 4
		"xp": 40, # Increased from 20
	},
	"craft_coolant_cell": {
		"name": "Helium Coolant Cell",
		"description": "Pressurized helium and nitrogen for weapon cooling, charged with recovered cryo-essence.",
		"input": {"He": 10, "NitroCoolant": 5, "Steel": 2, "Li": 2, "CryoEssence": 3},
		"output": {"CoolantCell": 1},
		"duration": 15.0,
		"level_req": 42, # Increased from 12
		"xp": 80, # Increased from 60
		"research_req": "cryogenic_systems"
	},
	"cryogenic_distillation": {
		"name": "Cryogenic Distillation",
		"description": "Extract Nitrogen from liquid Hydrogen/Oxygen mix.",
		"input": {"H": 10, "O": 10},
		"output": {"N": 5},
		"duration": 20.0,
		"level_req": 25,
		"xp": 30,
		"research_req": "basic_engineering"
	},
	# v111: CryoEssence BULK production. CryoEssence used to drop ONLY from
	# Zone 4 (Cryofield) with no craft path — forcing a post-warp backtrack to
	# a trivial early zone to gear the Cryo weapon tier. This manufactures it
	# from the cryogenic gas chain (He from harvest_nebula, N from
	# cryogenic_distillation, Li gathered) so the engineering loop supplies the
	# prestige weapons.
	#
	# Power gate: requires a PrimordialShard per batch — the deepest CONVENTIONAL
	# drop (Z9-Z10, boss 20-50). This forces the player to master the top of the
	# conventional climb before bulk-producing cryo power; it is NOT circular
	# (Z9-Z10 fall to conventional weapons, unlike warp-hardened Z11). The mid-
	# game Z4 CryoEssence drop stays intact for the small-quantity consumers
	# (NitroCoolant, RimeAlloy); this craft is the endgame bulk path only.
	"distill_cryo_essence": {
		"name": "Cryo-Essence Condenser",
		"description": "Infuse supercooled helium-nitrogen with a Primordial Shard, condensing concentrated Cryo-Essence — the active medium of cryogenic armaments. The Shard's exotic resonance is what makes the essence bite Warp-Hardened hulls.",
		"input": {"He": 8, "N": 10, "Li": 2, "PrimordialShard": 1},
		"output": {"CryoEssence": 3},
		"duration": 15.0,
		"level_req": 60,
		"xp": 120,
		"research_req": "cryogenic_systems",
		"category": "components"
	},
	# ── v114 (Zone Tier-Gate): per-zone signature-alloy refines (docs/ZONE_TIER_GATE.md).
	# Each Z2-Z10 common weapon/armor/shield needs its zone alloy (injected at craft
	# time when the gate is on). Refined from the zone's signature material — a revived
	# dead/thin drop, or the minted raw (Z4 Rimeplate, Z10 Aeon) — + a processed
	# co-input, so Processing is pulled into mandatory demand. ~3 signature + 2 co →
	# 1 alloy (Z4 reference; ratios are sim/playtest knobs). Gated by zone access.
	"refine_chondrite_alloy": {
		"name": "Chondrite Alloy",
		"description": "Smelt asteroid-pirate salvage into workable hull alloy — the Asteroid Belt's gear-grade stock.",
		"input": {"PirateSalvage": 3, "Circuit": 2}, "output": {"ChondriteAlloy": 1},
		"duration": 12.0, "level_req": 15, "xp": 25, "research_req": "zone_2_access", "category": "alloys"
	},
	"refine_wreckforged_alloy": {
		"name": "Wreckforged Alloy",
		"description": "Reforge Martian war-debris into structural plate.",
		"input": {"MartianRelics": 3, "Steel": 2}, "output": {"WreckforgedAlloy": 1},
		"duration": 13.0, "level_req": 25, "xp": 35, "research_req": "zone_3_access", "category": "alloys"
	},
	"refine_rime_alloy": {
		"name": "Rime Alloy",
		"description": "Temper frost-fused hull scrap with glacial essence into cold-rated alloy.",
		"input": {"RimeplateScrap": 3, "CryoEssence": 2}, "output": {"RimeAlloy": 1},
		"duration": 14.0, "level_req": 35, "xp": 50, "research_req": "zone_4_access", "category": "alloys"
	},
	"refine_xenoforged_alloy": {
		"name": "Xenoforged Alloy",
		"description": "Reverse-engineer xenon fragments into an exotic structural alloy.",
		"input": {"XenoFragment": 3, "AdvCircuit": 2}, "output": {"XenoforgedAlloy": 1},
		"duration": 15.0, "level_req": 45, "xp": 70, "research_req": "zone_5_access", "category": "alloys"
	},
	"refine_colony_alloy": {
		"name": "Colony-Forged Alloy",
		"description": "Recast colony reactor-salvage into a heavy mining-grade alloy.",
		"input": {"ColonySalvage": 3, "Superalloy": 2}, "output": {"ColonyAlloy": 1},
		"duration": 15.0, "level_req": 55, "xp": 95, "research_req": "zone_6_access", "category": "alloys"
	},
	"refine_gamma_alloy": {
		"name": "Gamma Alloy",
		"description": "Stabilize charged exotic isotopes into a radiation-tempered alloy.",
		"input": {"ExoticIsotope": 3, "VoidCrystal": 2}, "output": {"GammaAlloy": 1},
		"duration": 16.0, "level_req": 65, "xp": 120, "research_req": "zone_7_access", "category": "alloys"
	},
	"refine_prismatic_alloy": {
		"name": "Prismatic Alloy",
		"description": "Lattice antimatter particles into a prismatic crystalline alloy.",
		"input": {"AntimatterParticle": 3, "VoidCrystal": 2}, "output": {"PrismaticAlloy": 1},
		"duration": 16.0, "level_req": 72, "xp": 150, "research_req": "zone_8_access", "category": "alloys"
	},
	"refine_bioforged_alloy": {
		"name": "Bioforged Alloy",
		"description": "Bind biohazard residue with regenerative plating into a self-knitting bio-alloy.",
		"input": {"BiohazardSample": 3, "RegenPlating": 1}, "output": {"BioforgedAlloy": 1},
		"duration": 17.0, "level_req": 80, "xp": 190, "research_req": "zone_9_access", "category": "alloys"
	},
	"refine_aeon_alloy": {
		"name": "Aeon Alloy",
		"description": "Fuse aeon residuum with void essence into a primordial-grade alloy.",
		"input": {"AeonResiduum": 3, "VoidEssence": 2}, "output": {"AeonAlloy": 1},
		"duration": 18.0, "level_req": 88, "xp": 240, "research_req": "zone_10_access", "category": "alloys"
	},
	"nitrogen_coolant": {
		"name": "Cryo-Shield Matrix",
		"description": "Supercools shield generators for rapid integrity restoration. Restores 35% Shield.",
		"input": {"Circuit": 5, "AlMgAlloy": 10, "N": 250, "Li": 5},
		"output": {"NitroCoolant": 1},
		"duration": 15.0,
		"level_req": 32,
		"xp": 60,
		"research_req": "basic_engineering",
		"category": "consumables_shield"
	},
	"refine_diamond_lens": {
		"name": "Diamond Sensor Lens",
		"description": "Cut a flawless diamond into a precision sensor lens and decode it into exotic research data.",
		"input": {"Diamond": 1, "AdvCircuit": 5, "Au": 2},
		"output": {"Res3": 2},
		"duration": 30.0,
		"level_req": 60,
		"xp": 150
	},
	"craft_zero_point": {
		"name": "Zero-Point Injector",
		"description": "Vacuum energy extraction. Restores 50% Shield Integrity.",
		"input": {"BatteryT3": 1, "Superalloy": 2},
		"output": {"ZeroPoint": 1},
		"duration": 20.0,
		"level_req": 42,
		"xp": 60,
		"research_req": "energy_metrics", # Assumed research for late game
		"category": "consumables_shield"
	},
	"craft_slug_t3": {
		"name": "Depleted Uranium Round",
		"description": "Armor-shredding heavy rounds.",
		"input": {"SlugT2": 20, "U": 1, "StructuralComponent": 5},
		"output": {"SlugT3": 20},
		"duration": 15.0,
		"level_req": 55, # Increased from 8
		"xp": 120, # Increased from 50
		"research_req": "ballistics_optimization"
	},
	"craft_slug_t4": {
		"name": "Hyper-Velocity Slug",
		"description": "Tungsten-Superalloy sabot for railguns. Extreme kinetic impact.",
		"input": {"W": 10, "U": 3, "Superalloy": 1, "NanoSubstrate": 2, "IrWAlloy": 4},
		"output": {"SlugT4": 50},
		"duration": 20.0,
		"level_req": 65,
		"xp": 180,
		"research_req": "ballistics_optimization"
	},
	"craft_cell_t3": {
		"name": "Vaporizer Cell",
		"description": "Matter-disintegrating energy.",
		"input": {"CellT2": 20, "U": 1, "StructuralComponent": 5},
		"output": {"CellT3": 20},
		"duration": 15.0,
		"level_req": 58, # Increased from 8
		"xp": 120, # Increased from 50
		"research_req": "energy_metrics"
	},
	"craft_cell_t4": {
		"name": "Heavy Plasma Cell",
		"description": "Unstable fusion plasma containment. Extreme damage.",
		"input": {"He": 10, "U": 3, "Superalloy": 1, "NanoSubstrate": 2, "SuperconductingMagnet": 2},
		"output": {"CellT4": 20},
		"duration": 20.0,
		"level_req": 65,
		"xp": 180,
		"research_req": "energy_metrics"
	},
	"craft_missile_t1": {
		"name": "HE Missile",
		"description": "Standard high-explosive ordnance.",
		"input": {"Fe": 5, "C": 2},
		"output": {"MissileT1": 20},
		"duration": 12.0,
		"level_req": 5,
		"xp": 20,
		# v129: research gate removed — T1 ammo is part of the starter combat kit
		# (the damage-triangle tutorial needs missiles pre-research). combustion
		# still gates Fiber/Germanium/Mg + the kiln buildings.
	},
	"craft_turret_core": {
		"name": "Turret Core",
		"description": "Fabricate an automated turret control core from circuits and structural alloy.",
		"input": {"Circuit": 20, "Steel": 30, "AdvCircuit": 5, "StainlessSteel": 10},
		"output": {"TurretCore": 1},
		"duration": 25.0,
		"level_req": 35,
		"xp": 90
	},
	"craft_missile_t2": {
		"name": "Seeker Missile",
		"description": "Guided missile with logic circuits and a Hydrogen-fuelled sustainer motor.",
		"input": {"Steel": 2, "Circuit": 1, "TargetingChip": 1, "StructuralComponent": 3, "PirateSalvage": 2, "H": 10},
		"output": {"MissileT2": 20},
		"duration": 20.0,
		"level_req": 25,
		"xp": 50,
		"research_req": "advanced_rocketry"
	},
	"craft_missile_t3": {
		"name": "Heavy Missile",
		"description": "High-yield thermobaric ordnance in a corrosion-resistant casing.",
		"input": {"Steel": 5, "AlMgAlloy": 2, "H": 20, "StructuralComponent": 5, "GalvanizedSteel": 3, "StainlessSteel": 4},
		"output": {"MissileT3": 20},
		"duration": 30.0,
		"level_req": 48,
		"xp": 100,
		"research_req": "advanced_rocketry"
	},
	"craft_missile_t4": {
		"name": "Photon Torpedo",
		"description": "Antimatter-infused capital buster.",
		"input": {"Superalloy": 2, "ExoticMatter": 1, "NanoSubstrate": 3, "OsCore": 2},
		"output": {"MissileT4": 20},
		"duration": 45.0,
		"level_req": 65,
		"xp": 250,
		"research_req": "capital_ship_armament"
	},
	# Components
	"craft_circuit": {
		"name": "Circuit Board",
		# v80.3 Fix: DroneCore requires SwarmFragment which no enemy drops — deadlock
		"description": "Combine conductive copper traces with silicon wafers.",
		"input": {"Cu": 3, "Si": 4,"Sn":2},
		"output": {"Circuit": 1},
		"duration": 6.0,
		"level_req": 6,
		"xp": 50
	},
	# v62.0 Fix: Added AlWire source (Component)
	"craft_aluminum_wire": {
		"name": "Aluminum Wiring",
		"description": "High-conductivity cables.",
		"input": {"Al": 2, "Resin": 1},
		"output": {"AlWire": 2},
		"duration": 5.0,
		"level_req": 30,
		"xp": 35,
		"research_req": "basic_electronics"
	},
	# Audit v18.0: Industrial Path (No combat required)
	"assemble_circuit_standard": {
		"name": "Standard Circuit Assembly",
		"description": "Fabricate circuits from raw conductive materials. No Drone Core required.",
		"input": {"Cu": 2, "Si": 3,"Sn":2,"Resin": 1},
		"output": {"Circuit": 3},
		"duration": 6.0,
		"level_req": 12,
		"xp": 40,
		"research_req": "basic_electronics"
	},

	"craft_hydraulics": {
		"name": "Hydraulic Servo",
		"description": "Precision machined actuator.",
		"input": {"Steel": 2, "Resin": 1},
		"output": {"Hydraulics": 1},
		"duration": 10.0,
		"level_req": 10,
		"xp": 40,
		"research_req": "industrial_logistics"
	},
	# Lithium Chain
	"refine_lithium": {
		"name": "Refine Lithium",
		"description": "Extract Lithium from raw Lithium Ore.",
		"input": {"Spodumene": 2},
		"output": {"Li": 1},
		"duration": 5.0,
		"level_req": 3,
		"xp": 7,
		"research_req": "basic_engineering"
	},
	# Basic metallurgy moved to top
	# Germanium / Advanced Electronics
	"extract_germanium": {
		"name": "Germanium Extraction",
		# v80.4 Fix: Germanit has no source. Reworked to use Si+Cu
		"description": "Extract trace Germanium from refined Silicon.",
		"input": {"Si": 10, "Cu": 5},
		"output": {"Germanium": 1},
		"duration": 8.0,
		"level_req": 36,
		"xp": 40,
		"research_req": "combustion"
	},
	"refine_germanite": {
		"name": "Germanite Refining",
		"description": "Directly smelt Germanite ore for high-purity Germanium.",
		"input": {"Germanit": 3},
		"output": {"Germanium": 2},
		"duration": 10.0,
		"level_req": 35,
		"xp": 50,
		"research_req": "adv_materials"
	},
	"craft_semiconductor": {
		"name": "Semiconductor Wafer",
		"description": "Dope Silicon with Germanium for conductivity.",
		"input": {"Si": 2, "Germanium": 1},
		"output": {"Semiconductor": 1},
		"duration": 10.0,
		"level_req": 38, # Increased from 6
		"xp": 50, # Increased from 35
		"research_req": "adv_materials"
	},
	"refine_gold": {
		"name": "Gold Panning",
		"description": "Sift large amounts of dirt for Gold flakes.",
		"input": {"Dirt": 50, "Water": 50},
		"output": {"Au": 2},
		"duration": 12.0,
		"level_req": 20, # Increased from 6
		"xp": 30,
		"research_req": "basic_engineering"
	},
	"gold_leaching": {
		"name": "Chemical Leaching",
		"description": "Dissolve gold from soil using chemical solvents.",
		"input": {"Dirt": 70, "Water": 30, "H": 10},
		"output": {"Au": 5},
		"duration": 20.0,
		"level_req": 48, # Increased from 15
		"xp": 100,
		"research_req": "industrial_electrolysis"
	},
	"craft_adv_circuit": {
		"name": "Advanced Circuitry",
		"description": "High-performance integrated circuit. Silver traces and tin solder for low-loss interconnects.",
		"input": {"Semiconductor": 1, "Au": 1, "StructuralComponent": 2, "Ag": 2, "Sn": 1},
		"output": {"AdvCircuit": 1},
		"duration": 15.0,
		"level_req": 45, # Increased from 8
		"xp": 80, # Increased from 50
		"research_req": "automation"
	},
	"craft_chip": {
		"name": "Chip Fabrication",
		"description": "High-precision logic unit. Requires nitrogen cooling for etching.",
		"input": {"Semiconductor": 2,"Sn":3, "Au": 1, "N": 5},
		"output": {"Chip": 1},
		"duration": 20.0,
		"level_req": 40,
		"xp": 60,
		"research_req": "adv_materials"
	},
	"craft_battery_t1": {
		"name": "Assemble Battery Cell",
		"description": "Basic energy storage for ships.",
		"input": {"Li": 5, "Fe": 2},
		"output": {"BatteryT1": 1},
		"duration": 10.0,
		"level_req": 6,
		"xp": 60, # Increased from 50
		# v129: research gate removed — the T1 starter combat kit is level-gated only
		# (fewer forced early Research trips). power_systems still gates the Cell
		# Factory building + the T2 battery line.
	},
	"craft_battery_t2": {
		"name": "Graphene Matrix Battery",
		"description": "Advanced high-density battery. Requires Sulfur for electrolyte.",
		"input": {"BatteryT1": 10, "Chip": 5, "Graphite": 5, "AdvCircuit": 5, "StructuralComponent": 3},
		"output": {"BatteryT2": 1},
		"duration": 20.0,
		"level_req": 55, # Increased from 15
		"xp": 200, # Increased from 150
		"research_req": "adv_materials"
	},
	"craft_battery_t3": {
		"name": "Zero-Point Module",
		"description": "Experimental infinite energy containment.",
		"input": {"BatteryT2": 1, "VoidArtifact": 1, "Circuit": 20, "NanoSubstrate": 2},
		"output": {"BatteryT3": 1},
		"duration": 60.0,
		"level_req": 80, # Increased from 30
		"xp": 800, # Increased from 500
		"research_req": "warp_drive"
	},
	# Early Game Element Processing
	"smelt_bauxite": {
		"name": "Bauxite Smelting",
		"description": "Extract Aluminum from Bauxite ore using oxygen.",
		"input": {"Bauxite": 3, "O": 2},
		"output": {"Al": 2},
		"duration": 3.0,
		"level_req": 16, # Increased from 4
		"xp": 15, # Reduced from 20
		"research_req": "basic_engineering"
	},
	"process_dolomite": {
		"name": "Dolomite Calcination",
		"description": "Extract Magnesium from Dolomite through heating.",
		"input": {"Dolomite": 4, "C": 1},
		"output": {"Mg": 1},
		"duration": 6.0,
		"level_req": 15, # Increased from 4
		"xp": 15, # Reduced from 25
		"research_req": "combustion"
	},
	"refine_titanium": {
		"name": "Titanium Reduction",
		"description": "Reduce Dolomite ore into metallic Titanium sponge — the hand path before the Titanium Refinery.",
		"input": {"Dolomite": 2},
		"output": {"Ti": 1},
		"duration": 8.0,
		"level_req": 15,
		"xp": 25,
		"research_req": "adv_materials"
	},
	# Removed misplaced alloys here (moved up)
	"craft_cobalt_battery": {
		"name": "Lithium-Cobalt Battery",
		"description": "Advanced battery tech. High energy density.",
		"input": {"Li": 2, "Co": 3, "Al": 2, "Circuit": 1},
		"output": {"CoBattery": 1},
		"duration": 10.0,
		"level_req": 15,
		"xp": 100,
		"research_req": "advanced_batteries"
	},
	"craft_mg_ion_battery": {
		"name": "Magnesium-Ion Battery",
		"description": "Lightweight alternative to Li-ion. Fast charging.",
		"input": {"Mg": 4, "Mn": 2, "AlWire": 2},
		"output": {"MgBattery": 1},
		"duration": 8.0,
		"level_req": 14,
		"xp": 80,
		"research_req": "advanced_batteries"
	},
	"electrolysis_nickel_catalyst": {
		"name": "Nickel-Catalyzed Electrolysis",
		"description": "Ni catalyst speeds H2 production. More efficient.",
		"input": {"Water": 10, "Ni": 1},
		"output": {"H": 30, "O": 20},
		"duration": 20.0,
		"level_req": 12,
		"xp": 300,
		"research_req": "catalytic_electrodes"
	},
	"craft_superalloy": {
		"name": "Superalloy",
		"description": "Heat-resistant alloy for engines and reactors.",
		"input": {"Fe": 2, "Al": 2, "Co": 2, "Ni": 2, "Cr": 1, "Ti": 1},
		"output": {"Superalloy": 1},
		"duration": 10.0,
		"level_req": 18,
		"xp": 200,
		"research_req": "superalloy_engineering"
	},
	# Late-Game Rare Metal Processing
	"craft_platinum_catalyst": {
		"name": "Platinum Catalyst Matrix",
		"description": "Pt-ceramic catalyst. Increases ALL processing speed by 25%.",
		"input": {"Pt": 10, "Si": 50, "AdvCircuit": 5},
		"output": {"PtCatalyst": 1},
		"duration": 20.0,
		"level_req": 25,
		"xp": 300,
		"research_req": "industrial_catalysis"
	},
	"craft_silver_catalyst": {
		"name": "Silver Catalyst",
		"description": "High-efficiency chemical catalyst. +15% Processing Speed.",
		"input": {"Ag": 10, "Si": 20, "Circuit": 5},
		"output": {"AgCatalyst": 1},
		"duration": 15.0,
		"level_req": 30,
		"xp": 150,
		"research_req": "industrial_catalysis"
	},
	"craft_magnet": {
		"name": "Superconducting Magnet",
		"description": "Sn-Nb alloy magnets for advanced shielding and engines.",
		"input": {"Sn": 20, "Fe": 10, "Cu": 10},
		"output": {"SuperconductingMagnet": 1},
		"duration": 15.0,
		"level_req": 35,
		"xp": 200,
		"research_req": "metallurgy_advanced"
	},
	"craft_palladium_cell": {
		"name": "Palladium Fuel Cell",
		"description": "Pd-H2 fuel cell. High efficiency energy generation.",
		"input": {"Pd": 5, "H": 20, "Circuit": 3},
		"credits_cost": 20000,
		"output": {"PdFuelCell": 1},
		"duration": 15.0,
		"level_req": 30,
		"xp": 100,
		"research_req": "fuel_cell_tech"
	},
	# ========== AUDIT v24.0: RARE METAL REFINING ==========
	# Audit v39.0: Removed duplicate refine_platinum (kept refine_platinum_ore which has Pd byproduct)

	"craft_iridium_plate": {
		"name": "Iridium Armor Plating",
		"description": "Nearly indestructible Ir plating. Ultimate defense.",
		"input": {"Ir": 8, "Ti": 20, "Graphite": 10},
		"output": {"IrPlate": 5},
		"duration": 25.0,
		"level_req": 28,
		"xp": 400,
		"research_req": "iridium_metallurgy"
	},
	"craft_osmium_core": {
		"name": "Osmium Reactor Core",
		"description": "Densest material. Extreme HP and mass.",
		"input": {"Os": 5, "VoidCrystal": 2, "QuantumCore": 1},
		"output": {"OsCore": 1},
		"duration": 30.0,
		"level_req": 30,
		"xp": 800,
		"research_req": "exotic_metallurgy"
	},
	"refine_platinum_ore": {
		"name": "Platinum Extraction",
		"description": "Extract pure Pt from asteroid samples.",
		"input": {"PtOre": 10},
		"output": {"Pt": 2},
		"output_table": [["Pd", 0.3, 1, 2]], # 30% chance for Pd byproduct
		"duration": 8.0,
		"level_req": 20,
		"xp": 100,
		"research_req": "precious_metal_refining"
	},
	"craft_iridium_tungsten_alloy": {
		"name": "Iridium-Tungsten Alloy",
		"description": "Ir-W armor-piercing penetrator cores.",
		"input": {"Ir": 3, "W": 5},
		"output": {"IrWAlloy": 4},
		"duration": 12.0,
		"level_req": 26,
		"xp": 250,
		"research_req": "iridium_metallurgy"
	},
	# ========== ENDGAME RECIPES (P1-12: Sector Epsilon Resource Uses) ==========
	"craft_void_battery": {
		"name": "Void Battery",
		"description": "Ultimate power storage using void essence compression.",
		"input": {"VoidEssence": 10, "ExoticMatter": 5, "QuantumCore": 2, "NuclearFuel": 5},
		"output": {"VoidBattery": 1},
		"duration": 60.0,
		"level_req": 80,
		"xp": 2000,
		"research_req": "exotic_metallurgy",
		"category": "endgame"
	},
	"craft_temporal_module": {
		"name": "Temporal Stabilizer",
		"description": "Manipulates local time flow. Grants massive combat speed boost.",
		"input": {"ChronoCore": 5, "QuantumCore": 10, "AdvCircuit": 20, "NanoSubstrate": 5},
		"output": {"TemporalModule": 1},
		"duration": 90.0,
		"level_req": 85,
		"xp": 3000,
		"research_req": "exotic_metallurgy",
		"category": "endgame"
	},
	"craft_primordial_armor": {
		"name": "Primordial Forge",
		"description": "Legendary armor forged from titan remains. Best-in-slot defense.",
		"input": {"PrimordialShard": 3, "OmegaPlating": 10, "IrPlate": 5, "NanoSubstrate": 3, "CompositeWeave": 8},
		"output": {"PrimordialArmor": 1},
		"duration": 120.0,
		"level_req": 90,
		"xp": 5000,
		"research_req": "exotic_metallurgy",
		"category": "endgame"
	},
	"craft_omega_accelerator": {
		"name": "Omega Accelerator",
		"description": "Massively increases all production rates. Ultimate prestige item.",
		"input": {"OmegaPlating": 5, "ChronoCore": 3, "VoidEssence": 5, "QuantumCore": 5, "NanoSubstrate": 5, "PurifiedCompound": 4},
		"output": {"OmegaAccelerator": 1},
		"duration": 180.0,
		"level_req": 95,
		"xp": 10000,
		"research_req": "exotic_metallurgy",
		"category": "endgame"
	},
	"distill_void_essence": {
		"name": "Void Distillation",
		"description": "Concentrate void energy into pure exotic matter.",
		"input": {"VoidEssence": 20},
		"output": {"ExoticMatter": 10},
		"duration": 45.0,
		"level_req": 75,
		"xp": 1500,
		"research_req": "exotic_matter_analysis",
		"category": "endgame"
	},
	# ========== Phase B: LATE DEEP-CRAFT SPINE (Z8-10 module intermediates) ==========
	# Z8 depth rung: crafted intermediate ABOVE QuantumCore so Z8's longest root > Z7's.
	"refine_structural_lattice": {
		"name": "Structural Lattice Press",
		"description": "Bind a quantum core into an osmium-superalloy frame for capital-grade structure.",
		"input": {"QuantumCore": 1, "Os": 3, "Superalloy": 8},
		"output": {"StructuralLattice": 1},
		"duration": 30.0,
		"level_req": 78,
		"xp": 1600,
		"research_req": "zone_8_access",
		"category": "endgame"
	},
	# Rung 1 intermediate gated at Z8 (Neutronium drop + mid Superalloy).
	"refine_neutronium_plate": {
		"name": "Neutronium Press",
		"description": "Compress raw Neutronium with osmium and superalloy into structural plate.",
		"input": {"Neutronium": 4, "Os": 2, "Superalloy": 5},
		"output": {"NeutroniumPlate": 1},
		"duration": 32.0,
		"level_req": 80,
		"xp": 1800,
		"research_req": "zone_8_access",
		"category": "endgame"
	},
	# Rung 1 intermediates gated at neutronium_synthesis (Z9 drops + mid QuantumCore).
	"synth_bioreactor_core": {
		"name": "Bio-Reactor Synthesis",
		"description": "Culture pathogen samples around a quantum core into a self-sustaining bio-reactor.",
		"input": {"BiohazardSample": 12, "PathogenCore": 3, "QuantumCore": 2},
		"output": {"BioReactorCore": 1},
		"duration": 35.0,
		"level_req": 82,
		"xp": 2000,
		"research_req": "neutronium_synthesis",
		"category": "endgame"
	},
	"weave_void_lattice": {
		"name": "Void Lattice Weave",
		"description": "Crystallize void essence around a quantum-core scaffold into a load-bearing lattice.",
		"input": {"VoidEssence": 6, "VoidCrystal": 4, "QuantumCore": 2},
		"output": {"VoidLattice": 1},
		"duration": 35.0,
		"level_req": 85,
		"xp": 2200,
		"research_req": "neutronium_synthesis",
		"category": "endgame"
	},
	# Rung 2 intermediates (deeper — consume rung-1 intermediates + mid gate).
	"forge_omega_composite": {
		"name": "Omega Forge",
		"description": "Laminate omega plating over a neutronium plate with advanced circuitry.",
		"input": {"OmegaPlating": 6, "NeutroniumPlate": 2, "AdvCircuit": 30},
		"output": {"OmegaComposite": 1},
		"duration": 60.0,
		"level_req": 90,
		"xp": 4000,
		"research_req": "primordial_engineering",
		"category": "endgame"
	},
	# Rung 3 intermediate (deepest Z10 root: VoidEssence->VoidCrystal->VoidLattice->PrimordialMatrix).
	"crystallize_primordial_matrix": {
		"name": "Primordial Crystallizer",
		"description": "Bind a primordial shard to diamond and a void lattice into a stable matrix.",
		"input": {"PrimordialShard": 5, "Diamond": 3, "VoidLattice": 2},
		"output": {"PrimordialMatrix": 1},
		"duration": 90.0,
		"level_req": 95,
		"xp": 6000,
		"research_req": "primordial_engineering",
		"category": "endgame"
	},
	# ========== v86.0: UNIVERSAL COMPONENT CHAIN ==========
	"craft_structural_component": {
		"name": "Structural Component",
		"description": "Precision-machined universal assembly from base metals. Required for advanced fabrication.",
		"input": {"Fe": 10, "Cu": 5, "Si": 5, "C": 3, "Li": 2},
		"output": {"StructuralComponent": 1},
		"duration": 8.0,
		# v134: 40 -> 35. The m029a3->m029b mission stretch expected 40 THEN 45
		# (AdvCircuit) back-to-back — a dead grind zone with no new content between.
		# 35 staggers the two gates; AdvCircuit stays 45 (the economy-wide gate).
		"level_req": 35,
		"xp": 80,
		"research_req": "metallurgy_advanced"
	},
	"craft_nano_substrate": {
		"name": "Nano-Substrate",
		"description": "Molecular-scale lattice from structural components and lightweight metals. Capital-grade fabrication.",
		"input": {"StructuralComponent": 5, "Al": 3, "Mg": 2, "Ni": 1},
		"output": {"NanoSubstrate": 1},
		"duration": 15.0,
		"level_req": 55,
		"xp": 200,
		"research_req": "automation"
	},
	# ========== v57.1: SECTOR ZETA RECIPES ==========
	"synthesize_bioweapon": {
		"name": "Bio-Agent Synthesis",
		# v80.4 Fix: MutatedTissue has no source. Replaced with BiohazardSample
		"description": "Synthesize pathogen samples into biological weapon coating.",
		"input": {"BiohazardSample": 15, "PathogenCore": 2},
		"output": {"BioWeaponCoating": 3},
		"duration": 30.0,
		"level_req": 70,
		"xp": 1200,
		"research_req": "zone_9_access",
		"category": "endgame"
	},
	"craft_ai_core": {
		"name": "AI Logic Core",
		"description": "Synthesize a high-bandwidth AI processing core.",
		"input": {"Chip": 25, "AdvCircuit": 5, "NavData": 2},
		"output": {"AICore": 1},
		"duration": 20.0,
		"level_req": 50,
		"xp": 150,
		"research_req": "automation"
	},
	"craft_ai_processor": {
		"name": "Sentient AI Processor",
		"description": "Quantum-entangled processing substrate for sentient AI.",
		# v80.1: Moved QuantumCore back to level 60
		"input": {"AICore": 5, "AdvCircuit": 20, "QuantumCore": 1},
		"output": {"AIProcessor": 1},
		"duration": 60.0,
		"level_req": 65,
		"xp": 500,
		"research_req": "void_navigation"
	},
	"craft_regenerative_plating": {
		"name": "Regenerative Hull Plating",
		# v80.4 Fix: MutatedTissue has no source. Replaced with BiohazardSample
		"description": "Self-healing armor using bio-hazard compounds.",
		"input": {"BiohazardSample": 20, "IrPlate": 3, "PathogenCore": 1},
		"output": {"RegenPlating": 2},
		"duration": 40.0,
		"level_req": 72,
		"xp": 1500,
		"research_req": "zone_9_access",
		"category": "endgame"
	},
	"purify_biohazard": {
		"name": "Pathogen Purification",
		"description": "Extract valuable compounds from hazardous samples.",
		"input": {"BiohazardSample": 20},
		"output": {"PurifiedCompound": 5},
		"output_table": [["PathogenCore", 0.2, 1, 1]],
		"duration": 20.0,
		"level_req": 65,
		"xp": 800,
		"research_req": "zone_9_access",
		"category": "endgame"
	},
	# ========== AUDIT v20.0: DEAD RESOURCE ACTIVATION ==========
	# T2 Fix: PirateManifest
	"decode_manifest": {
		"name": "Decode Encrypted Data",
		# v80.4 Fix: PirateManifest has no source. Reworked to use NavData
		"description": "Cross-reference navigation data to reveal hidden coordinates and bounty.",
		"input": {"NavData": 3},
		"output": {},
		"credits_output": 12500,
		"duration": 15.0,
		"level_req": 15,
		"xp": 30,
		"category": "salvage"
	},
	# T5 Fix: ColonySalvage
	"process_colony_salvage": {
		"name": "Process Colony Salvage",
		"description": "Extract advanced components from colonial wreckage.",
		"input": {"ColonySalvage": 10, "Circuit": 5},
		"output": {"AdvCircuit": 3},
		"duration": 30.0,
		"level_req": 40,
		"xp": 150,
		"research_req": "deep_space_nav",
		"category": "salvage"
	},
	# ── v129: Reclamation lane — the continuous captain→engineer flow. Combat's
	# SalvagedAlloy / DamagedCircuitry drops (Z1-Z2 authored per-enemy; Z3+ via the
	# centralized roll in combat_manager) convert into core industrial goods at
	# per-craft rates the raw chains can't match — so an hour of combat always banks
	# crafting feedstock. Level-gated only: the combat-exclusive supply IS the gate.
	"reclaim_alloy": {
		"name": "Reclaim Salvaged Alloy",
		"description": "Re-smelt battlefield alloy scrap into structural steel.",
		"input": {"SalvagedAlloy": 3},
		"output": {"Steel": 6},
		"duration": 4.0,
		"level_req": 8,
		"xp": 25,
		"category": "salvage"
	},
	"reclaim_circuitry": {
		"name": "Reclaim Circuitry",
		"description": "Strip and re-trace damaged boards into working circuits.",
		"input": {"DamagedCircuitry": 3},
		"output": {"Circuit": 2},
		"duration": 6.0,
		"level_req": 10,
		"xp": 30,
		"category": "salvage"
	},
	"reclaim_superalloy": {
		"name": "Reforge Superalloy",
		"description": "Fold alloy scrap with nickel into superalloy stock.",
		"input": {"SalvagedAlloy": 6, "Ni": 2},
		"output": {"Superalloy": 1},
		"duration": 8.0,
		"level_req": 22,
		"xp": 50,
		"category": "salvage"
	},
	"reclaim_advanced": {
		"name": "Rebuild Advanced Circuitry",
		"description": "Cannibalize salvaged boards into an advanced circuit — combat's shortcut past the semiconductor chain.",
		"input": {"DamagedCircuitry": 6, "Circuit": 2},
		"output": {"AdvCircuit": 1},
		"duration": 12.0,
		"level_req": 30,
		"xp": 70,
		"category": "salvage"
	},
	# v130: Boost Card — infrastructure OVERCLOCK chip (Satisfactory power-shard
	# analog). Installed on a building type in the Infrastructure page: each card
	# makes ONE unit of that building run at x2 (yield AND input drains). Mid/late
	# sink pulling the Reclamation lane (AdvCircuit/Superalloy) + combat exotics.
	"fabricate_boost_card": {
		"name": "Fabricate Boost Card",
		"description": "Quantum-clocked control card. Install on a building in Infrastructure to overclock one unit to 200%.",
		"input": {"AdvCircuit": 5, "Superalloy": 10, "QuantumCore": 1},
		"output": {"BoostCard": 1},
		"duration": 30.0,
		"level_req": 45,
		"xp": 250,
		"category": "components"
	},
	# v129: CoolantCell consumer (was the last sell-only combat drop) — a Z4-farm
	# shortcut to the Cryo-Shield Matrix vs the full N-250 industrial recipe.
	"recharge_coolant_cell": {
		"name": "Recharge Coolant Cell",
		"description": "Recharge a salvaged Glacier-Belt coolant cell into a Cryo-Shield Matrix. Restores 35% Shield.",
		"input": {"CoolantCell": 2, "N": 20},
		"output": {"NitroCoolant": 1},
		"duration": 8.0,
		"level_req": 20,
		"xp": 40,
		"category": "consumables_shield"
	},
	# T6 Fix: RadIsotope
	"process_rad_isotope": {
		"name": "Refine Radioactive Isotopes",
		"description": "Process unstable isotopes into concentrated nuclear fuel.",
		"input": {"RadIsotope": 5, "H": 20, "Steel": 10},
		"output": {"NuclearFuel": 2},
		"duration": 45.0,
		"level_req": 55,
		"xp": 200,
		"research_req": "radiation_shielding",
		"category": "endgame"
	},
	# T7 Fix: AncientTech
	"decode_ancient_tech": {
		"name": "Quantum Core Synthesis",
		# v80.4 Fix: AncientTech has no source. Reworked to use void materials
		"description": "Compress void artifacts into quantum-entangled processing cores.",
		"input": {"VoidArtifact": 10, "VoidCrystal": 3, "AdvCircuit": 5},
		"output": {"QuantumCore": 2},
		"duration": 90.0,
		"level_req": 70,
		"xp": 500,
		"research_req": "exotic_matter_analysis",
		"category": "endgame"
	},
	# ========== AUDIT v20.0 EXTENSION: ALL ENEMIES UNIQUE DROPS ==========
	# T2: claim_jumper -> StolenCargo
	# v80.4 Fix: StolenCargo and SwarmFragment have no source — both recipes removed
	# fence_stolen_cargo: StolenCargo not dropped by any enemy
	# assemble_drone_core: SwarmFragment not dropped by any enemy
	# T4: cryo_drone -> CryoCell
	"craft_cryo_coolant": {
		"name": "Cryogenic Coolant",
		# v80.4 Fix: CryoCell has no source. Reworked to use He+N (cryogenic materials)
		"description": "Compress helium and nitrogen into supercooled fluid.",
		"input": {"He": 15, "N": 10, "Water": 5},
		"output": {"NitroCoolant": 1},
		"duration": 10.0,
		"level_req": 20,
		"xp": 30,
		# v131: was orphan category "processing" (no tab -> invisible). NitroCoolant
		# is a shield consumable, so it lives with the other shield kits.
		"category": "consumables_shield"
	},
	# T5: defense_turret -> TurretCore
	"craft_turret_targeting": {
		"name": "Targeting Array Fabrication",
		# v80.4 Fix: TurretCore has no source. Reworked to use AdvCircuit+Steel
		"description": "Assemble a precision targeting computer from advanced circuits.",
		"input": {"AdvCircuit": 3, "Steel": 20, "Circuit": 10},
		"output": {"TargetingChip": 1},
		"duration": 20.0,
		"level_req": 45,
		"xp": 100,
		"research_req": "deep_space_nav",
		"category": "salvage"
	},
	# T8: energy_wraith -> AntimatterParticle

	# v131: ZONE TROPHIES removed (6 craft_trophy_* recipes cut). Their inputs
	# (MiteChitin/PirateSalvage/MartianRelics/CryoEssence/XenoFragment) all keep
	# other consumers: signature alloys, decode recipes, research costs.

	# ── Tier 1 Combat-Materials (Phase 1) ──────────────────────────────
	# Mandatory consumer: the intended path is farming Z1-2 Heavy/Tech
	# enemies for the inputs. Below it, two deliberately punitive fallback
	# recipes guarantee no progression deadlock (anti-deadlock Law 3).
	"craft_reinforced_plating": {
		"name": "Reinforced Plating",
		"description": "Forge salvaged combat alloy and scavenged circuitry into a Tier-1 reinforced hull plate — the cornerstone of early ship-frame upgrades.",
		"input": {"SalvagedAlloy": 4, "DamagedCircuitry": 2, "Steel": 10},
		"output": {"ReinforcedPlating": 1},
		"duration": 12.0,
		"level_req": 8,
		"xp": 60,
		"category": "components"
	},
	"reclaim_salvaged_alloy": {
		"name": "Improvised Alloy (Fallback)",
		"description": "Crudely re-smelt bulk Steel into a Salvaged Alloy substitute. Wildly inefficient (8:1) — farming Heavy enemies is far better — but it guarantees you can never hard-lock.",
		"input": {"Steel": 8},
		"output": {"SalvagedAlloy": 1},
		"duration": 15.0,
		"level_req": 8,
		"xp": 10,
		"category": "components"
	},
	"reclaim_damaged_circuitry": {
		"name": "Stripped Circuitry (Fallback)",
		"description": "Cannibalise finished Circuits into a Damaged Circuitry substitute. Lossy (6:1) — Tech enemies drop it far faster — but this is the deadlock safety net.",
		"input": {"Circuit": 6},
		"output": {"DamagedCircuitry": 1},
		"duration": 15.0,
		"level_req": 8,
		"xp": 10,
		"category": "components"
	},
}


func _init():
	super._init("Engineering")

# --- P1 Mastery helpers (mirror of gathering_manager — see comments there) ---
func _mastery_xp_needed_for_level(target: int) -> float:
	if target <= 0 or target > MASTERY_LEVEL_CAP:
		return 0.0
	return float(25 + target * 5)

func gain_mastery_xp(recipe_id: String, amount: float = MASTERY_XP_PER_COMPLETION) -> void:
	if recipe_id == "" or amount <= 0.0:
		return
	# v107: First-encounter intro — see gathering_manager.gain_mastery_xp for
	# rationale. Shared flag so it only fires once across both managers.
	if not GameState.game_settings.get("mastery_intro_seen", false):
		GameState.game_settings["mastery_intro_seen"] = true
		UITheme.show_notification(
			"✦ MASTERY UNLOCKED — Keep using actions for permanent speed bonuses. Hover the mastery bar for the milestone schedule.",
			Color(1.0, 0.84, 0.45)
		)
	var prev_level: int = get_mastery_level(recipe_id)
	mastery[recipe_id] = float(mastery.get(recipe_id, 0.0)) + amount
	var new_level: int = get_mastery_level(recipe_id)
	if new_level > prev_level:
		_notify_mastery_milestones(recipe_id, prev_level, new_level)

func get_mastery_xp(recipe_id: String) -> float:
	return float(mastery.get(recipe_id, 0.0))

func get_mastery_level(recipe_id: String) -> int:
	var xp: float = get_mastery_xp(recipe_id)
	var level: int = 0
	var threshold: float = 0.0
	while level < MASTERY_LEVEL_CAP:
		var needed: float = _mastery_xp_needed_for_level(level + 1)
		if xp < threshold + needed:
			break
		threshold += needed
		level += 1
	return level

func get_mastery_progress(recipe_id: String) -> Dictionary:
	var xp: float = get_mastery_xp(recipe_id)
	var level: int = get_mastery_level(recipe_id)
	if level >= MASTERY_LEVEL_CAP:
		return {"in_level": xp, "needed": 0.0, "at_cap": true}
	var threshold: float = 0.0
	for n in range(1, level + 1):
		threshold += _mastery_xp_needed_for_level(n)
	var next_req: float = _mastery_xp_needed_for_level(level + 1)
	return {"in_level": xp - threshold, "needed": next_req, "at_cap": false}

func get_mastery_duration_mult(recipe_id: String) -> float:
	# v109: table-driven (was flat 5%/milestone). Same big-step Lv 50 jump
	# the gathering skill uses; see MASTERY_DURATION_BONUS_TABLE above.
	var level: int = get_mastery_level(recipe_id)
	var milestones_passed: int = 0
	for m in MASTERY_MILESTONES:
		if level >= m:
			milestones_passed += 1
	var idx: int = clamp(milestones_passed, 0, MASTERY_DURATION_BONUS_TABLE.size() - 1)
	var reduction: float = MASTERY_DURATION_BONUS_TABLE[idx]
	return 1.0 - reduction

func is_mastery_alt_unlocked(recipe_id: String) -> bool:
	return get_mastery_level(recipe_id) >= 50

# Infra↔Mastery link: first recipe whose output produces `symbol`. Lets the
# infrastructure manager attribute a producing building to the Mastery of the
# recipe that crafts the same material (insertion-order = canonical recipe).
func get_recipe_id_for_output(symbol: String) -> String:
	for rid in recipes:
		var out = recipes[rid].get("output", {})
		if out is Dictionary and out.has(symbol):
			return rid
	return ""

# P1.3 Alt-recipe framework — returns the configured alt-recipe id for this
# recipe IF mastery is unlocked AND the recipe has an `alt_recipe_id` field.
# Content (per-recipe alt-recipes) is backfilled separately; until a recipe
# defines `alt_recipe_id`, this returns "" and the toggle never surfaces.
# The plumbing being live means content additions are pure data, no code.
func get_alt_recipe_id_for(recipe_id: String) -> String:
	if not is_mastery_alt_unlocked(recipe_id):
		return ""
	return recipes.get(recipe_id, {}).get("alt_recipe_id", "")

func _notify_mastery_milestones(recipe_id: String, prev_level: int, new_level: int) -> void:
	# v110: uniform format — colour cue on the card communicates Lv 50 leap
	# and Lv 100 cap; toast text stays neutral.
	var recipe_name: String = recipes.get(recipe_id, {}).get("name", recipe_id)
	for m in MASTERY_MILESTONES:
		if prev_level < m and new_level >= m:
			var idx: int = MASTERY_MILESTONES.find(m) + 1
			var pct: int = int(round(MASTERY_DURATION_BONUS_TABLE[idx] * 100.0))
			var msg: String = "%s — Mastery %d · −%d%% Duration" % [recipe_name, m, pct]
			UITheme.show_notification(msg, Color(1.0, 0.84, 0.45))

func get_recipe_speed_multiplier(recipe_id: String) -> float:
	var multiplier = 1.0
	
	var upgrades_db = {
		"centrifuge_dirt": [
			{"id": "fast_centrifuges", "bonus": 0.25},
			{"id": "maglev_bearings", "bonus": 0.50},
			{"id": "quantum_separators", "bonus": 0.75}
		],
		"electrolysis": [
			{"id": "catalytic_electrodes", "bonus": 0.25},
			{"id": "ion_exchange", "bonus": 0.50},
			{"id": "resonance_splitters", "bonus": 0.75}
		],
		"charcoal_burning": [ {"id": "pyrolysis_control", "bonus": 0.25}],
		"smelt_steel_basic": [ {"id": "blast_furnace", "bonus": 0.25}],
		"smelt_steel_oxygen": [ {"id": "blast_furnace", "bonus": 0.25}],
		"press_graphite": [ {"id": "hydraulic_press", "bonus": 0.25}]
	}
	
	# Global Speed Bonus (Nano-Fabrication)
	if GameState.research_manager:
		multiplier += GameState.research_manager.get_efficiency_bonus("processing_speed")
	
	# Forensic 3: Infrastructure Buffs
	if GameState.infrastructure_manager:
		# Molecular Fabricator (20% Speed Increase)
		if GameState.infrastructure_manager.get_building_count("fabricator") > 0:
			multiplier += 0.20
		
		# Platinum Catalyst Chamber (Global Processing Speed +25%)
		if GameState.infrastructure_manager.get_building_count("catalyst_chamber") > 0:
			multiplier += 0.25
			
		# Silver Catalyst Bay (Global Processing Speed +15%)
		if GameState.infrastructure_manager.get_building_count("silver_catalyst_bay") > 0:
			multiplier += 0.15
	
	# Audit v8.0 P1-25: Industrial Logistics Hub Bonus (+10% Speed)
	if GameState.research_manager:
		multiplier += GameState.research_manager.get_efficiency_bonus("industrial_logistics")
	
	# Audit v7.0 P1-21: Engineering Skill Bonus (+1% Speed per Level)
	multiplier += (get_level() * 0.01)
	
	# v74.0: Refinery Link (Module Affix)
	if GameState.shipyard_manager:
		multiplier += GameState.shipyard_manager.affix_bonuses.get("refinery_link", 0.0)
	
	# Audit v4.0: Milestone Level 10 (+10% Speed)
	if is_milestone_unlocked(10):
		multiplier *= 1.10
	
	# Audit v12.0: Milestone Level 25 (-10% Duration = 1.11x speed effectively)
	if is_milestone_unlocked(25):
		multiplier *= 1.11

	# v107: Warp Mastery Tree — E2 Recipe Efficiency (-10% duration → +11.1% speed)
	if GameState.warp_manager:
		multiplier *= GameState.warp_manager.get_tree_processing_speed_bonus()

	# P1 Mastery: per-recipe duration reduction folded into the speed
	# multiplier so existing "effective_duration = base / multiplier" math holds.
	var dur_mult: float = get_mastery_duration_mult(recipe_id)
	if dur_mult > 0.0:
		multiplier /= dur_mult

	return multiplier

func start_action(action_id: String):
	if action_id in recipes:
		var recipe = recipes[action_id]
		
		# Levels
		if get_level() < recipe.get("level_req", 1):
			print("Level too low.")
			return
		
		# Research
		var res_req = recipe.get("research_req")
		if res_req and not GameState.research_manager.is_tech_unlocked(res_req):
			print("Research required: ", res_req)
			return
		
		# Ingredients
		var c_cost = recipe.get("credits_cost", 0)
		if not has_ingredients(recipe["input"], c_cost):
			print("Missing ingredients/credits.")
			return
			
		current_recipe = recipe
		current_recipe_id = action_id
		action_progress = 0.0
		is_active = true

func stop_action():
	is_active = false
	current_recipe = {}
	current_recipe_id = ""
	action_progress = 0.0

func reset(decay_factor: float = 1.0) -> void:
	super.reset(decay_factor)
	stop_action()
	# P1 Mastery is true meta-progression — persists across warp (decay_factor<1.0)
	# and clears only on hard reset (decay_factor==1.0).
	if decay_factor >= 1.0:
		mastery = {}
	print("Processing Reset.")

func process_tick(delta_time: float):
	if not is_active or current_recipe.is_empty():
		return
		
	action_progress += delta_time
	
	var speed_mult = get_recipe_speed_multiplier(current_recipe_id)
	var effective_duration = current_recipe["duration"] / speed_mult
	
	if action_progress >= effective_duration:
		complete_process()

func complete_process():
	# 1. Check ingredients again
	var c_cost = current_recipe.get("credits_cost", 0)
	if not has_ingredients(current_recipe["input"], c_cost):
		stop_action()
		return
		
	# 2. Consume (ENG_3 reduces each input by 1, floored at 1)
	for item in current_recipe["input"]:
		var qty = effective_input_qty(current_recipe["input"][item])
		GameState.resources.remove_element(item, qty)
		
	if "credits_cost" in current_recipe:
		GameState.resources.remove_currency("credits", current_recipe["credits_cost"])
		
	# 3. Output
	if "output" in current_recipe:
		for item in current_recipe["output"]:
			var qty = current_recipe["output"][item]
			
			# Apply Steel Scalability (Oxygen-Blast Furnace)
			if item == "Steel" and GameState.research_manager.is_tech_unlocked("oxygen_blast_furnace"):
				qty *= 5
				
			# Efficiency Research Multiplier
			if GameState.research_manager:
				qty *= GameState.research_manager.get_efficiency_multiplier()
				
			# Audit v12.0: Milestone Level 50 (5% chance for double output)
			if is_milestone_unlocked(50) and randf() < 0.05:
				qty *= 2
				events.append(["loot", {"symbol": item, "amount": qty, "is_critical": true}, current_recipe_id])
			else:
				events.append(["loot", {"symbol": item, "amount": qty}, current_recipe_id])
				
			GameState.resources.add_element(item, qty); GameState.note_production("process", qty); GameState.note_craft_material(item, qty)  # P3.10 / Phase 0
			
	if "output_table" in current_recipe:
		var roll_count = current_recipe.get("roll_count", 1) # Default 1 roll

		var results = {} # Accumulate results: {item: total_qty}
		
		for i in range(roll_count):
			for entry in current_recipe["output_table"]:
				var item = entry[0]
				var chance = entry[1]
				var min_q = entry[2]
				var max_q = entry[3]
				
				if randf() < chance:
					var qty = randi_range(min_q, max_q)
					
					# Efficiency Research Multiplier
					if GameState.research_manager:
						qty *= GameState.research_manager.get_efficiency_multiplier()
						
					results[item] = results.get(item, 0) + qty
		
		# Grant accumulated loot
		for item in results:
			var qty = results[item]
			GameState.resources.add_element(item, qty); GameState.note_production("process", qty); GameState.note_craft_material(item, qty)  # P3.10 / Phase 0
			
			# Special jackpot message for rare items
			if item in ["AncientTech", "W", "Ti", "NavData", "Chip", "Circuit"]:
				events.append(["loot", {"symbol": item, "amount": qty, "is_jackpot": true}, current_recipe_id])
			else:
				events.append(["loot", {"symbol": item, "amount": qty}, current_recipe_id])
					
	# 4. XP
	var xp_reward = current_recipe.get("xp", 0)
	add_xp(xp_reward)
	events.append(["xp", "+%d XP" % xp_reward, current_recipe_id])

	# P1 Mastery: per-recipe XP (one tick per completion).
	gain_mastery_xp(current_recipe_id)

	# v61.0 Fix: Grant credits_output if present
	if "credits_output" in current_recipe:
		var cr_out = current_recipe["credits_output"]
		GameState.resources.add_currency("credits", cr_out)
		events.append(["loot", {"symbol": "credits", "amount": cr_out}, current_recipe_id])
	
	# 5. Loop
	action_progress = 0.0
	
	# Check for next cycle
	if not has_ingredients(current_recipe["input"], c_cost):
		stop_action()

# ENG_3 Efficient Recipe (warp tree): -1 of each input material per craft, floored at 1.
# Single source of truth — used by the consume, the ingredient check, the offline
# count, and the recipe-card UI so they never disagree.
func effective_input_qty(raw_qty: int) -> int:
	var red := 0
	if GameState.warp_manager:
		red = GameState.warp_manager.get_tree_recipe_material_reduction()
	return max(1, raw_qty - red)

func has_ingredients(inputs: Dictionary, credits: int = 0) -> bool:
	for item in inputs:
		var qty = effective_input_qty(inputs[item])
		if GameState.resources.get_element_amount(item) < qty:
			return false
			
	if credits > 0:
		if GameState.resources.get_currency("credits") < credits:
			return false
			
	return true

func calculate_offline(delta: float):
	if not is_active or current_recipe.is_empty():
		return null
		
	var speed_mult = get_recipe_speed_multiplier(current_recipe_id)
	var effective_duration = current_recipe["duration"] / speed_mult

	# v132: fold in the saved partial craft and keep the remainder (mirrors
	# gathering) — the fraction used to be discarded on every resume.
	var total_time: float = action_progress + delta
	var time_actions = int(total_time / effective_duration)
	if time_actions <= 0:
		action_progress = total_time
		return null
	
	var input_reqs = current_recipe.get("input", {})
	var min_by_input = 99999999999.0
	
	var no_inputs = input_reqs.is_empty()
	
	if not no_inputs:
		for item in input_reqs:
			var qty = effective_input_qty(input_reqs[item])
			var avail = GameState.resources.get_element_amount(item)
			var possible = int(avail / qty)
			if possible < min_by_input:
				min_by_input = possible
	else:
		min_by_input = time_actions
	
	# v61.0 Fix: Include credits_cost in offline calculation
	var credits_cost = current_recipe.get("credits_cost", 0)
	if credits_cost > 0:
		var credits_avail = GameState.resources.get_currency("credits")
		var possible_by_credits = int(credits_avail / credits_cost)
		if possible_by_credits < min_by_input:
			min_by_input = possible_by_credits
	
	var actions = min(time_actions, int(min_by_input))
	# v132: remainder semantics — time-limited runs carry the fractional tick
	# forward; input/credit-limited runs stalled at a completion boundary, so the
	# partial resets (matches online, which can't accrue progress without inputs).
	if actions >= time_actions:
		action_progress = fmod(total_time, effective_duration)
	else:
		action_progress = 0.0

	if actions <= 0:
		# v132: was a raw String — the offline report pipeline renders Dictionary
		# blocks (block["category"] etc.), so a recipe that stalled overnight fed a
		# String into offline_report_data and broke the boot modal.
		return {
			"category": "processing",
			"title": "Engineering",
			"action": current_recipe.get("name", current_recipe_id),
			"time_sec": int(delta),
			"actions": 0,
			"xp": 0,
			"gains": {},
			"drains": {},
			"notes": ["Stopped — missing input materials."],
			"status": "standby",
		}
		
	var loot_summary = {}
	var xp_base = current_recipe.get("xp", 0)
	var total_xp = actions * xp_base
	add_xp(total_xp)

	# P1 Mastery: batch-grant offline mastery XP (one per completion).
	# Single call avoids spamming N notifications during a long catch-up.
	gain_mastery_xp(current_recipe_id, float(actions) * MASTERY_XP_PER_COMPLETION)

	# Consume
	# v132: use effective_input_qty (ENG_3 -1/material, floored at 1) — the online
	# consume AND the affordability count above both use it, but this loop took the
	# RAW qty: with ENG_3 owned, offline over-consumed and could overdraw the very
	# stock the count just verified as affordable.
	for item in input_reqs:
		var qty = effective_input_qty(input_reqs[item])
		GameState.resources.remove_element(item, qty * actions)
	
	# v61.0 Fix: Deduct credits_cost for offline processing
	if credits_cost > 0:
		GameState.resources.remove_currency("credits", credits_cost * actions)
		
	# Produce
	if "output" in current_recipe:
		for item in current_recipe["output"]:
			var qty = current_recipe["output"][item]
			
			# Apply Steel Scalability (Oxygen-Blast Furnace).
			# v112: was *= 2 offline vs *= 5 online — offline silently paid 60%
			# less on the same buff. Matched to the online complete_process path.
			if item == "Steel" and GameState.research_manager.is_tech_unlocked("oxygen_blast_furnace"):
				qty *= 5

			# Efficiency Research Multiplier
			if GameState.research_manager:
				qty *= GameState.research_manager.get_efficiency_multiplier()

			var total = qty * actions
			GameState.resources.add_element(item, total); GameState.note_production("process", total); GameState.note_craft_material(item, total)  # P3.10 / Phase 0 (offline fallback)
			loot_summary[item] = loot_summary.get(item, 0) + total
			
	if "output_table" in current_recipe:
		var roll_count = current_recipe.get("roll_count", 1)

		for i in range(actions):
			for j in range(roll_count):
				for entry in current_recipe["output_table"]:
					var item = entry[0]
					var chance = entry[1]
					var min_q = entry[2]
					var max_q = entry[3]
					
					if randf() < chance:
						var qty = randi_range(min_q, max_q)
						
						# Efficiency Research Multiplier
						if GameState.research_manager:
							qty *= GameState.research_manager.get_efficiency_multiplier()
							
						GameState.resources.add_element(item, qty); GameState.note_production("process", qty); GameState.note_craft_material(item, qty)  # P3.10 / Phase 0
						loot_summary[item] = loot_summary.get(item, 0) + qty

	# v61.0 Fix: Award credits_output for offline processing
	var total_credits = 0
	if "credits_output" in current_recipe:
		total_credits = current_recipe["credits_output"] * actions
		GameState.resources.add_currency("credits", total_credits)

	# v112: structured offline block (was a formatted string). Liras fold into
	# `gains` under the "credits" key so the ledger renders them as one row.
	var gains = loot_summary.duplicate()
	if total_credits > 0:
		gains["credits"] = total_credits
	return {
		"category": "processing",
		"title": "Engineering",
		"action": current_recipe.get("name", current_recipe_id),
		"time_sec": int(delta),
		"actions": actions,
		"xp": total_xp,
		"gains": gains,
		"drains": {},
		"notes": [],
		"status": "active",
	}

func get_save_data_manager() -> Dictionary:
	var data = get_save_data()
	data["is_active"] = is_active
	data["current_recipe_id"] = current_recipe_id
	data["action_progress"] = action_progress  # v132: resume the partial craft
	data["mastery"] = mastery  # P1
	return data

func load_save_data_manager(data: Dictionary):
	load_save_data(data)
	if data.is_empty(): return

	is_active = data.get("is_active", false)
	current_recipe_id = data.get("current_recipe_id", "")
	action_progress = float(data.get("action_progress", 0.0))  # v132: pre-v132 saves default 0
	# P1 Mastery — defaults to empty so v1 saves load unchanged.
	var saved_mastery = data.get("mastery", {})
	if saved_mastery is Dictionary:
		mastery = saved_mastery.duplicate()

	if is_active and not current_recipe_id.is_empty():
		if current_recipe_id in recipes:
			current_recipe = recipes[current_recipe_id]
		else:
			is_active = false
			action_progress = 0.0

func get_current_rate() -> Dictionary:
	"""Returns units produced per minute for active recipe"""
	if not is_active or current_recipe_id.is_empty():
		return {}
		
	var recipe = recipes[current_recipe_id]
	var speed_mult = get_recipe_speed_multiplier(current_recipe_id)
	var effective_duration = recipe["duration"] / speed_mult
	var actions_per_min = 60.0 / effective_duration
	
	var rates = {}
	
	# Fixed Outputs
	if "output" in recipe:
		for item in recipe["output"]:
			var rate = recipe["output"][item] * actions_per_min

			# v112: match the actual production paths (complete_process /
			# calculate_offline) — the Oxygen-Blast Furnace x5 Steel scalar was
			# missing here, so the displayed active rate understated Steel 5x.
			if item == "Steel" and GameState.research_manager and GameState.research_manager.is_tech_unlocked("oxygen_blast_furnace"):
				rate *= 5

			# Efficiency Research Multiplier
			if GameState.research_manager:
				rate *= GameState.research_manager.get_efficiency_multiplier()

			rates[item] = rate
			
	# Probability Outputs
	if "output_table" in recipe:
		var roll_count = recipe.get("roll_count", 1)

		for entry in recipe["output_table"]:
			var item = entry[0]
			var chance = entry[1]
			var min_q = entry[2]
			var max_q = entry[3]
			var avg = (min_q + max_q) / 2.0
			
			var rate = avg * chance * roll_count * actions_per_min
			
			# Efficiency Research Multiplier
			if GameState.research_manager:
				rate *= GameState.research_manager.get_efficiency_multiplier()
				
			rates[item] = rates.get(item, 0.0) + rate
			
	return rates
