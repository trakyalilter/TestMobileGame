extends Skill

var is_active: bool = false
var current_recipe: Dictionary = {}
var current_recipe_id: String = ""
var action_progress: float = 0.0

var events: Array = []

var recipes: Dictionary = {
	"sift_dirt_dry": {
		"name": "Dry Sifting",
		"description": "Manually sift through dirt for metallic fragments. No water required.",
		"input": {"Dirt": 10},
		# Low efficiency but early access
		"output": {"Fe": 3},
		"output_table": [["Si", 0.2, 1, 1]],
		"duration": 5.0,
		"level_req": 1,
		"xp": 3,
		"research_req": "basic_engineering",
		"category": "basics"
	},
	"charcoal_burning": {
		"name": "Charcoal Kiln",
		"description": "Burn Wood to produce Carbon. The backbone of metallurgy.",
		"input": {"Wood": 5},
		"output": {"C": 16},
		"duration": 4.0,
		"level_req": 3,
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
		"research_req": "fluid_dynamics",
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
		"description": "Foundry smelting of Iron and Carbon into Steel.",
		"input": {"Fe": 5, "C": 2},
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
		"description": "Extract Zinc from ore via carbon reduction.",
		"input": {"ZincOre": 3, "C": 1},
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
		"level_req": 20,
		"xp": 25,
		"research_req": "smelting"
	},
	"refine_pentlandite": {
		"name": "Nickel Extraction",
		"description": "Process Pentlandite for Nickel (Ni).",
		"input": {"Pentlandite": 3, "C": 1},
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
		"level_req": 32, # Increased from 4
		"xp": 40, # Increased from 20
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
		"research_req": "fluid_dynamics"
	},
	"nitrogen_coolant": {
		"name": "Cryo-Shield Matrix",
		"description": "Supercools shield generators for rapid integrity restoration. Restores 35% Shield.",
		"input": {"Circuit": 5, "AlMgAlloy": 10, "N": 250, "Li": 5},
		"output": {"NitroCoolant": 1},
		"duration": 15.0,
		"level_req": 32,
		"xp": 60,
		"research_req": "fluid_dynamics",
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
		"research_req": "combustion"
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
		"description": "Guided missile with logic circuits.",
		"input": {"Steel": 2, "Circuit": 1, "TargetingChip": 1, "StructuralComponent": 3, "PirateSalvage": 2},
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
		"name": "Basic Circuitry",
		# v80.3 Fix: DroneCore requires SwarmFragment which no enemy drops — deadlock
		"description": "Combine conductive copper traces with silicon wafers.",
		"input": {"Cu": 3, "Si": 4},
		"output": {"Circuit": 2},
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
		"input": {"Cu": 2, "Si": 3, "Resin": 1},
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
		"description": "Extract Lithium from Spodumene crystals.",
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
		"input": {"Dirt": 100, "Water": 100},
		"output": {"Au": 1},
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
		"input": {"Semiconductor": 2, "Au": 1, "N": 5},
		"output": {"Chip": 1},
		"duration": 20.0,
		"level_req": 40,
		"xp": 60,
		"research_req": "adv_materials"
	},
	"craft_battery_t1": {
		"name": "Assemble Basic Battery",
		"description": "Basic energy storage for ships.",
		"input": {"Li": 5, "Fe": 2},
		"output": {"BatteryT1": 1},
		"duration": 10.0,
		"level_req": 6,
		"xp": 60, # Increased from 50
		"research_req": "power_systems"
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
	# ========== v86.0: UNIVERSAL COMPONENT CHAIN ==========
	"craft_structural_component": {
		"name": "Structural Component",
		"description": "Precision-machined universal assembly from base metals. Required for advanced fabrication.",
		"input": {"Fe": 10, "Cu": 5, "Si": 5, "C": 3, "Li": 2},
		"output": {"StructuralComponent": 1},
		"duration": 8.0,
		"level_req": 40,
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
		"category": "processing"
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

	# ========== ZONE TROPHIES (Permanent Buffs) ==========
	# Consumes zone-themed combat loot that was previously dead-end inventory.
	# Each trophy grants a permanent passive bonus (see bounty_manager.get_trophy_buff).
	# Multiple copies do NOT stack — one is enough.
	"craft_trophy_lunar": {
		"name": "Lunar Conquest Trophy",
		"description": "Forge a trophy from Mite Chitin shards. Grants +25% Gathering XP permanently.",
		"input": {"MiteChitin": 50, "Cu": 20, "Circuit": 10},
		"output": {"Trophy_Lunar": 1},
		"duration": 30.0,
		"level_req": 10,
		"xp": 80,
		"research_req": "kinetics_101",
		"category": "trophies"
	},
	"craft_trophy_belt": {
		"name": "Asteroid Belt Trophy",
		"description": "Reforge Pirate Salvage into a Belt Trophy. Grants +20% Mining Yield permanently.",
		"input": {"PirateSalvage": 50, "Steel": 30, "Cu": 20},
		"output": {"Trophy_Belt": 1},
		"duration": 45.0,
		"level_req": 20,
		"xp": 150,
		"research_req": "zone_2_access",
		"category": "trophies"
	},
	"craft_trophy_mars": {
		"name": "Martian Relic Trophy",
		"description": "Restore Martian Relics into a memorial trophy. Grants +25% Processing XP permanently.",
		"input": {"MartianRelics": 40, "Steel": 40, "AdvCircuit": 5},
		"output": {"Trophy_Mars": 1},
		"duration": 60.0,
		"level_req": 30,
		"xp": 250,
		"research_req": "zone_3_access",
		"category": "trophies"
	},
	"craft_trophy_titan": {
		"name": "Titan Cryofield Trophy",
		"description": "Condense Cryo Essence into a Titan Trophy. Grants +10% Ship Speed permanently.",
		"input": {"CryoEssence": 30, "Ti": 50, "Superalloy": 5},
		"output": {"Trophy_Titan": 1},
		"duration": 75.0,
		"level_req": 40,
		"xp": 400,
		"research_req": "zone_4_access",
		"category": "trophies"
	},
	"craft_trophy_alpha": {
		"name": "Sector Alpha Trophy",
		"description": "Bind Xeno Fragments into an Alpha Trophy. Grants +15% Research Speed permanently.",
		"input": {"XenoFragment": 25, "Superalloy": 5, "AdvCircuit": 10},
		"output": {"Trophy_Alpha": 1},
		"duration": 90.0,
		"level_req": 50,
		"xp": 600,
		"research_req": "zone_5_access",
		"category": "trophies"
	},
	"craft_trophy_delta": {
		"name": "Delta Sector Trophy",
		"description": "Compress Neutronium into a Delta Trophy. Grants +15% Kinetic Damage permanently.",
		"input": {"Neutronium": 20, "Superalloy": 10, "ExoticMatter": 5},
		"output": {"Trophy_Delta": 1},
		"duration": 120.0,
		"level_req": 70,
		"xp": 1200,
		"research_req": "zone_8_access",
		"category": "trophies"
	},
}


func _init():
	super._init("Engineering")

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
		
	# 2. Consume
	for item in current_recipe["input"]:
		var qty = current_recipe["input"][item]
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
				
			GameState.resources.add_element(item, qty)
			
	if "output_table" in current_recipe:
		var roll_count = current_recipe.get("roll_count", 1) # Default 1 roll
		
		# Apply Scrap Recycling Bonus
		if current_recipe_id == "recycle_scrap":
			roll_count += int(GameState.research_manager.get_efficiency_bonus("scrap_rolls"))
			
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
			GameState.resources.add_element(item, qty)
			
			# Special jackpot message for rare items
			if item in ["AncientTech", "W", "Ti", "NavData", "Chip", "Circuit"]:
				events.append(["loot", {"symbol": item, "amount": qty, "is_jackpot": true}, current_recipe_id])
			else:
				events.append(["loot", {"symbol": item, "amount": qty}, current_recipe_id])
					
	# 4. XP
	var xp_reward = current_recipe.get("xp", 0)
	if GameState.bounty_manager:
		xp_reward = int(xp_reward * GameState.bounty_manager.get_trophy_buff("processing_xp"))
		
	add_xp(xp_reward)
	events.append(["xp", "+%d XP" % xp_reward, current_recipe_id])
	
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

func has_ingredients(inputs: Dictionary, credits: int = 0) -> bool:
	for item in inputs:
		var qty = inputs[item]
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
	
	var time_actions = int(delta / effective_duration)
	if time_actions <= 0: return null
	
	var input_reqs = current_recipe.get("input", {})
	var min_by_input = 99999999999.0
	
	var no_inputs = input_reqs.is_empty()
	
	if not no_inputs:
		for item in input_reqs:
			var qty = input_reqs[item]
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
	
	if actions <= 0:
		return "Engineering (%s):\nStopped (Missing Resources)." % current_recipe['name']
		
	var loot_summary = {}
	var xp_base = current_recipe.get("xp", 0)
	var total_xp = actions * xp_base
	if GameState.bounty_manager:
		total_xp = int(total_xp * GameState.bounty_manager.get_trophy_buff("processing_xp"))
		
	add_xp(total_xp)
	
	# Consume
	for item in input_reqs:
		var qty = input_reqs[item]
		GameState.resources.remove_element(item, qty * actions)
	
	# v61.0 Fix: Deduct credits_cost for offline processing
	if credits_cost > 0:
		GameState.resources.remove_currency("credits", credits_cost * actions)
		
	# Produce
	if "output" in current_recipe:
		for item in current_recipe["output"]:
			var qty = current_recipe["output"][item]
			
			# Apply Steel Scalability (Oxygen-Blast Furnace)
			if item == "Steel" and GameState.research_manager.is_tech_unlocked("oxygen_blast_furnace"):
				qty *= 2
				
			# Efficiency Research Multiplier
			if GameState.research_manager:
				qty *= GameState.research_manager.get_efficiency_multiplier()
				
			var total = qty * actions
			GameState.resources.add_element(item, total)
			loot_summary[item] = loot_summary.get(item, 0) + total
			
	if "output_table" in current_recipe:
		var roll_count = current_recipe.get("roll_count", 1)
		
		# Apply Scrap Recycling Bonus
		if current_recipe_id == "recycle_scrap":
			roll_count += int(GameState.research_manager.get_efficiency_bonus("scrap_rolls"))
			
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
							
						GameState.resources.add_element(item, qty)
						loot_summary[item] = loot_summary.get(item, 0) + qty

	# v61.0 Fix: Award credits_output for offline processing
	var total_credits = 0
	if "credits_output" in current_recipe:
		total_credits = current_recipe["credits_output"] * actions
		GameState.resources.add_currency("credits", total_credits)

	var report = "Engineering (%s):\n" % current_recipe['name']
	report += "Time Adjusted: %dm\n" % int(delta / 60)
	report += "Actions Completed: %d\n" % actions
	report += "XP Gained: %d\n" % total_xp
	if total_credits > 0:
		report += "Liras Earned: %d\n" % total_credits
	report += "Produced:\n"
	
	for item in loot_summary:
		report += " + %s: %d\n" % [item, loot_summary[item]]
		
	return report

func get_save_data_manager() -> Dictionary:
	var data = get_save_data()
	data["is_active"] = is_active
	data["current_recipe_id"] = current_recipe_id
	return data

func load_save_data_manager(data: Dictionary):
	load_save_data(data)
	if data.is_empty(): return
	
	is_active = data.get("is_active", false)
	current_recipe_id = data.get("current_recipe_id", "")
	
	if is_active and not current_recipe_id.is_empty():
		if current_recipe_id in recipes:
			current_recipe = recipes[current_recipe_id]
		else:
			is_active = false

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
			
			# Efficiency Research Multiplier
			if GameState.research_manager:
				rate *= GameState.research_manager.get_efficiency_multiplier()
				
			rates[item] = rate
			
	# Probability Outputs
	if "output_table" in recipe:
		var roll_count = recipe.get("roll_count", 1)
		if current_recipe_id == "recycle_scrap":
			roll_count += int(GameState.research_manager.get_efficiency_bonus("scrap_rolls"))
			
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
