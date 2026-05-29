extends Skill

signal activity_occurred

# v111.5: scan-loop vars stripped. `is_active` + `current_action` kept (read
# externally by game_state / global_header / offline_boot_modal) but pinned
# at falsey values — research has no foreground action anymore.
var current_action: String = ""
var is_active: bool = false

# v56.0: Progression Pacing Extension - 2.5x credit costs for 30-40h playtime
const COST_MULTIPLIER = 1.0 # Applied manually now
# v56.1: 2x material requirements for progression extension.
# NOTE: this is a SECOND, flat layer applied at can_unlock()/unlock_tech() time,
# ON TOP OF the per-stage multiplier baked into tech_tree by
# _scale_mid_late_research_item_costs(). Effective item cost is therefore:
#     raw_authored_qty  ×  stage_mult  ×  MATERIAL_MULTIPLIER
# The stage constants below are set to HALF their headline value so they
# compound with this ×2 to the intended effective curve. Do NOT add a third
# multiply anywhere — keep these two layers the only sources of truth.
const MATERIAL_MULTIPLIER = 2.0

# v104: Tier-scaled material sink. The economy problem was a glut: continuous
# raw/refined production vs. one-time gate costs calibrated to ~hour-1 income.
# Fix = steepen the (already-existing but near-flat) per-stage cost curve so
# later research consumes a meaningful slice of a multi-day stockpile.
# Headline effective curve (raw × these × MATERIAL_MULTIPLIER):
#   stage 0 (early/tutorial) : ×1  effective  (UNCHANGED — onboarding contract)
#   stage 1 (mid)            : ×5  effective  (2.5 × 2.0)
#   stage 2 (late)           : ×15 effective  (7.5 × 2.0)
#   stage 3 (endgame, new)   : ×40 effective  (20  × 2.0)
const MID_RESEARCH_ITEM_REQ_MULT = 2.5
const LATE_RESEARCH_ITEM_REQ_MULT = 7.5
const ENDGAME_RESEARCH_ITEM_REQ_MULT = 20.0
const MID_RESEARCH_COST_GATE = 15000
const LATE_RESEARCH_COST_GATE = 150000
const ENDGAME_RESEARCH_COST_GATE = 1000000

const MID_RESEARCH_ITEMS = [
	"Res2", "Res3", "AdvCircuit", "NavData", "ColonyDataCore",
	"RadIsotope", "ExoticIsotope", "Superalloy", "AntimatterParticle"
]

const LATE_RESEARCH_ITEMS = [
	"VoidArtifact", "VoidCrystal", "QuantumCore", "AncientTech"
]

const ENDGAME_RESEARCH_ITEMS = [
	"VoidEssence", "ChronoCore", "ExoticMatter", "Neutronium",
	"AICore", "AIProcessor", "PrimordialShard", "OmegaPlating"
]

# v104: Drop-gated / one-off tokens are NEVER tier-scaled. Scaling these adds
# pure grind with zero glut benefit (they don't accumulate in bulk). The glut
# is raw/refined mats (Fe, Steel, Circuit, AdvCircuit, Ti, Superalloy, ...) —
# only those should grow with tier. Zone boss cores match the "*_Core" suffix
# (Z1_Core..Z10_Core) and are excluded by pattern.
const NON_SCALING_ITEMS = [
	"NavData", "SalvageData", "VoidArtifact", "ColonyDataCore",
	"QuarantineClearance", "BiohazardSample", "TurretCore",
	"AncientTech", "ExoticMatter"
]

var unlocked_techs = []
var repeatable_techs = {} # {id: level}
var _research_item_costs_scaled := false

signal tech_unlocked(tech_id)

func _on_research_completed(active_tech_id):
	activity_occurred.emit()

var tech_tree = {
	"basic_engineering": {
		"name": "Basic Engineering",
		"tier": 1,
		"category": "processing",
		"cost": 125,
		"type": "technology",
		"parent": null,
		"effects": [],
		# v111.6 audit: "Lithium Refining" → "Refine Lithium" (real recipe id).
		"unlocks": ["Mineral Washing", "Refine Lithium"],
		"flavor": "",
	},
	# v111.6 audit batch G — applied_physics' unlocks were three downstream
	# research-tech names (energy_shields, eff_scanning_1 [deleted!],
	# core_overclocking), not items. Tree's parent/req_tech edges already
	# show downstream techs — dropped from the prose.
	"applied_physics": {
		"name": "Applied Physics",
		"tier": 1,
		"category": "meta",
		"cost": 625,
		"type": "technology",
		"parent": "basic_engineering",
		"effects": [],
		"unlocks": [],
		"flavor": "Gates the Energy Fields and Reactor Overclocking branches.",
	},
	"materials_science": {
		"name": "Materials Science",
		"tier": 1,
		"category": "meta",
		"cost": 625,
		"type": "technology",
		"parent": "basic_engineering",
		"effects": [],
		"unlocks": [],
		"flavor": "Gates the Advanced Technologies branch.",
	},
	"industrial_logistics": {
		"name": "Industrial Logistics",
		"tier": 1,
		"category": "meta",
		"cost": 625,
		"type": "technology",
		"parent": "basic_engineering",
		"effects": [],
		"unlocks": [],
		"flavor": "Gates the Advanced Technologies branch.",
	},
	"fluid_dynamics": {
		"name": "Fluid Dynamics",
		"tier": 1,
		"category": "processing",
		"cost": 125,
		"type": "technology",
		"parent": "applied_physics",
		"effects": [],
		# v111.6 audit:
		#   • "Water Reclamation" — phantom (no recipe/building by that name)
		#   • "Electrolysis" → "Water Electrolysis" (real recipe display name)
		#   • "High-Flow Pumps" — that's a downstream research tech name,
		#     not an item. Tree edge already shows it.
		"unlocks": ["Water Electrolysis"],
		"flavor": "",
	},
	# v110: schema refactor pilot — combustion / smelting / shipwright_1 are
	# the first three converted to the structured format. UI now builds the
	# tooltip from `effects` / `unlocks` / `flavor` + auto-derived REQUIRES;
	# no more hand-typed bullets.
	"combustion": {
		"name": "Organic Combustion",
		"tier": 1,
		"category": "processing",
		"cost": 125,
		"type": "technology",
		"parent": "materials_science",
		# v111.6 audit: dropped 3 dead/wrong-layer claims —
		#   • "Fly Ash Separation"  — phantom (no such recipe / building anywhere)
		#   • "Laser Cutters"       — that's a downstream research tech, not an
		#                              item; the tree edge already shows it
		#   • "Carbon Hull Lattice" — same (hull_hardening tech name)
		"effects": [],
		"unlocks": [
			"Charcoal Kiln",
			"HE Missile",
			"Micro-Missile Launcher",
		],
		"flavor": "",
	},
	"smelting": {
		"name": "Efficient Smelting",
		# v61.0 Fix: Bronze Alloy doesn't exist, corrected to Galvanized Steel
		"tier": 2,
		"category": "processing",
		"cost": 3750,  # Audit v41.0: Reduced from 3000 to smooth progression
		"cost_items": {"Res1": 10, "Circuit": 5},
		"type": "technology",
		"parent": "combustion",
		"effects": [],
		# v111.6 audit: "Steel Foundry" → "Basic Steel Smelting" (real recipe).
		"unlocks": ["Basic Steel Smelting", "Galvanized Steel"],
		"flavor": "",
	},
	"shipwright_1": {
		"name": "Shipwright I",
		"tier": 2,
		"category": "ships",
		"cost": 50000,
		"cost_items": {"Steel":20,"Res1": 20,"Circuit": 10},
		"type": "technology",
		"parent": "power_systems",
		"req_tech": "smelting",
		"effects": [],
		"unlocks": ["Industrial Frigate"],
		"flavor": "",
	},

	"shipwright_2": {
		"name": "Shipwright II",
		"tier": 3,
		"category": "ships",
		"cost": 1000000,
		"cost_items": {"Res2": 25},
		"type": "technology",
		"parent": "shipwright_1",
		"effects": [],
		# v111.6 audit: hull's real display name in shipyard is "Destroyer"
		# (was "Destroyer Class"). Drop the " Class" suffix so smart-linker
		# can hyperlink it to the hull popup.
		"unlocks": ["Destroyer"],
		"flavor": "",
	},
	"adv_materials": {
		"name": "Advanced Materials",
		"tier": 2,
		"category": "processing",
		"cost": 5000,
		"cost_items": {"Res2": 5},
		"type": "technology",
		"parent": "smelting",
		"effects": [],
		"unlocks": ["Graphite Press"],
		"flavor": "Gates the Factory Automation and Hydraulic Press branches.",
	},
	"energy_shields": {
		"name": "Energy Fields",
		"tier": 2,
		"category": "combat",
		"cost": 1250,
		"type": "technology",
		# v111.5: re-parented from `eff_scanning_1` (Sensor Calibration) to
		# `applied_physics`. Sensor Calibration was deleted as a dead tech —
		# it boosted a Data currency that had no consumer and a scan loop no
		# UI ever started.
		"parent": "applied_physics",
		"effects": [],
		"unlocks": [],
		"flavor": "Gates Shield Harmonics and Magnetic Funnels research.",
	},
	"field_theory": {
		"name": "Field Theory",
		# v105: restored after wrong-flag deletion — actually gates the IonField
		# defensive consumable via shipyard CONSUMABLE_REQ_TECH map.
		"tier": 2,
		"category": "combat",
		"cost": 37500,
		"cost_items": {"Res2": 15},
		"type": "technology",
		"parent": "energy_shields",
		"effects": [],
		"unlocks": ["Ion Field"],
		"flavor": "Defensive consumable for evasion windows.",
	},
	# v111.5: eff_scanning_1 (Sensor Calibration) deleted. The tech boosted
	# Data per Scan, but Data had no consumer in the game and the scan loop
	# (start_scan / complete_action / scan_sector) was never started by any
	# UI. Triple-dead feature — removed cleanly. energy_shields re-parented
	# to applied_physics so the tree stays connected.

	"automation": {
		"name": "Factory Automation",
		"tier": 2,
		"category": "processing",
		"cost": 12500,
		"cost_items": {"Res2": 25, "Circuit": 20},
		"type": "technology",
		"parent": "adv_materials",
		"effects": [],
		"unlocks": ["Advanced Circuit"],
		"flavor": "Gates Advanced Rocketry research.",
	},
	"advanced_rocketry": {
		"name": "Advanced Rocketry",
		"tier": 3,
		"category": "combat",
		"cost": 37500,
		"cost_items": {"Steel": 100, "Circuit": 50},
		"type": "technology",
		"parent": "automation",
		"effects": [],
		"unlocks": ["Seeker Missile"],
		"flavor": "",
	},
	"sector_alpha_decryption": {
		"name": "Sector Scanning (Alpha)",
		"tier": 5,
		"category": "zone",
		"cost": 50000,
		"cost_items": {"NavData": 15, "Res1": 50},
		"type": "technology",
		"parent": "zone_5_access",
		"effects": [],
		"unlocks": ["Sector Alpha (scan)"],
		"flavor": "",
	},
	"advanced_batteries": {
		"name": "Advanced Battery Tech",
		"tier": 2,
		"category": "processing",
		"cost": 7500,
		"cost_items": {"Co": 25, "Mg": 25, "Li": 25},
		"type": "technology",
		"parent": "adv_materials",
		"effects": [],
		# v111.6 audit:
		#   • "Cobalt-Lithium Battery" → "Lithium-Cobalt Battery" (word order)
		#   • "Magnesium-Ion Cell"     → "Magnesium-Ion Battery"
		"unlocks": ["Lithium-Cobalt Battery", "Magnesium-Ion Battery"],
		"flavor": "",
	},
	"xeno_archaeology": {
		"name": "Xeno-Archaeology",
		"tier": 3,
		"category": "meta",
		"cost": 5000,
		"cost_items": {"VoidArtifact": 1, "NavData": 5},
		"type": "technology",
		"parent": "sector_alpha_decryption",
		"effects": [],
		"unlocks": ["Analyze Void Artifact"],
		"flavor": "",
	},
	"warp_drive": {
		"name": "Warp Drive Theory",
		"tier": 3,
		"category": "meta",
		"cost": 12500,
		"cost_items": {"NavData": 50, "Ti": 200, "Res3": 10},
		"type": "technology",
		"parent": "shipwright_2",
		"effects": [],
		"unlocks": ["Meson Oscillator"],
		"flavor": "Required for Deep Space Navigation research.",
	},
	# --- v56.1: CONTENT GATES (Intermediate milestones) ---

	# ═══════════════════════════════════════════════════════════════
	# v80.1: Zone Access Research Gates — Instant, material-gated
	# Cost formula: credits = floor(30000 × 2.5^(N-2)), boss cores = floor(1 + (N-1)/2)
	# ═══════════════════════════════════════════════════════════════
	"zone_2_access": {
		"name": "Asteroid Belt Authorization",
		"tier": 2,
		"category": "zone",
		"cost": 30000,
		"cost_items": {"Z1_Core": 1, "Fe": 40, "Cu": 20},
		"type": "technology",
		"parent": null,
		"req_tech": "shipwright_1",
		"effects": [],
		# v111.6 audit: "Asteroid Belt zone" → "Asteroid Belt" to match the
		# combat zone's display name and let the smart-linker hyperlink it.
		"unlocks": ["Asteroid Belt", "Zone 2 modules fabrication"],
		"flavor": "",
	},
	# v102: Zone gates re-tuned into an escalating industrial-supply curve.
	# Volumes from z4+ are impractical to hand-gather under the single-active-
	# task rule, so extraction + background processing (Infrastructure) becomes
	# the de-facto supply line. Boss cores stay as the combat gate. First-pass
	# numbers — MATERIAL_MULTIPLIER scales further; tune via playtest.
	"zone_3_access": {
		"name": "Mars Debris Clearance",
		"tier": 3,
		"category": "zone",
		"cost": 75000,
		"cost_items": {"Z2_Core": 1, "Steel": 200, "Circuit": 60},
		"type": "technology",
		"parent": "zone_2_access",
		"effects": [],
		"unlocks": ["Mars Debris Field", "Zone 3 modules fabrication"],
		"flavor": "Bulk refined materials — start automating.",
	},
	"zone_4_access": {
		"name": "Cryofield Expedition",
		"tier": 4,
		"category": "zone",
		"cost": 187500,
		"cost_items": {"Z3_Core": 2, "Steel": 600, "Ti": 350, "Circuit": 200},
		"type": "technology",
		"parent": "zone_3_access",
		"effects": [],
		# v111.6 audit: hull entries renamed to drop " hull" suffix so they
		# match shipyard_manager's actual hull display names. Smart-linker
		# can now hyperlink each one to the hull info-card popup.
		"unlocks": ["Cryofield zone", "Zone 4 modules", "Heavy Cruiser"],
		"flavor": "Hand-supply is impractical here — build extraction.",
	},
	"zone_5_access": {
		"name": "Sector Alpha Decryption",
		"tier": 5,
		"category": "zone",
		"cost": 468750,
		"cost_items": {"Z4_Core": 2, "Steel": 1500, "AdvCircuit": 250, "Superalloy": 80},
		"type": "technology",
		"parent": "zone_4_access",
		"effects": [],
		"unlocks": ["Sector Alpha", "Zone 5 modules", "Battlecruiser"],
		"flavor": "Sustained automated output required.",
	},
	"zone_6_access": {
		"name": "Deep Space Navigation",
		"tier": 6,
		"category": "zone",
		"cost": 1171875,
		"cost_items": {"Z5_Core": 3, "Ti": 2000, "AdvCircuit": 600, "Superalloy": 300},
		"type": "technology",
		"parent": "zone_5_access",
		"effects": [],
		"unlocks": ["Sector Beta", "Zone 6 modules", "Capital Ship"],
		"flavor": "Mature industrial base required.",
	},
	"zone_7_access": {
		"name": "Radiation Shielding",
		"tier": 7,
		"category": "zone",
		"cost": 2929687,
		"cost_items": {"Z6_Core": 3, "AdvCircuit": 1500, "Superalloy": 900, "W": 200},
		"type": "technology",
		"parent": "zone_6_access",
		"effects": [],
		"unlocks": ["Sector Gamma", "Zone 7 modules", "Carrier"],
		"flavor": "Heavy automation + Tungsten extraction.",
	},
	"zone_8_access": {
		"name": "Exotic Matter Analysis",
		"tier": 8,
		"category": "zone",
		"cost": 7324218,
		"cost_items": {"Z7_Core": 4, "AdvCircuit": 3000, "Superalloy": 2200, "Ir": 60},
		"type": "technology",
		"parent": "zone_7_access",
		"effects": [],
		"unlocks": ["Sector Delta", "Zone 8 modules", "Dreadnought"],
		"flavor": "Full-scale industrial economy.",
	},
	"zone_9_access": {
		"name": "Quarantine Protocols",
		"tier": 9,
		"category": "zone",
		"cost": 18310546,
		"cost_items": {"Z8_Core": 4, "AdvCircuit": 6000, "Superalloy": 5000, "Os": 40},
		"type": "technology",
		"parent": "zone_8_access",
		"effects": [],
		"unlocks": ["Sector Zeta", "Zone 9 modules", "Titan"],
		"flavor": "Deep automated supply chains.",
	},
	"zone_10_access": {
		"name": "Void Navigation",
		"tier": 10,
		"category": "zone",
		"cost": 45776367,
		"cost_items": {"Z9_Core": 5, "AdvCircuit": 15000, "Superalloy": 12000, "ChronoCore": 10},
		"type": "technology",
		"parent": "zone_9_access",
		"effects": [],
		"unlocks": ["Sector Epsilon", "Zone 10 modules", "Leviathan"],
		"flavor": "End-game industrial empire.",
	},
	# --- NEW EARLY GAME GATES ---
	"kinetics_101": {
		"name": "Kinetic Weapons Theory",
		"tier": 1,
		"category": "combat",
		"cost": 50,
		"type": "technology",
		"parent": null,
		"req_tech": "applied_physics",
		# v111.6 audit:
		#   • "Basic Slug Factory" → real building is "Basic Kinetic Foundry"
		#     (building_db key: basic_kinetic_foundry). Renamed.
		#   • "Lunar Trophy" → phantom (no recipe / item by that name). Removed.
		"effects": [],
		"unlocks": ["Basic Kinetic Foundry"],
		"flavor": "",
	},
	"power_systems": {
		"name": "Power Systems",
		"tier": 1,
		"category": "infrastructure",
		"cost": 300,
		"type": "technology",
		"parent": "kinetics_101",
		"req_tech": "applied_physics",
		"effects": [],
		"unlocks": ["Basic Cell Factory", "Basic Battery"],
		"flavor": "",
	},
	"laser_optics": {
		"name": "Laser Optics",
		# v105b: restored after wrong-flag deletion — actually gates Plasma Cell
		# (CellT2 energy ammo) via shipyard ELEMENT_RESEARCH_REQS map.
		"tier": 1,
		"category": "combat",
		"cost": 300,
		"cost_items": {"Res1": 5},
		"type": "technology",
		"parent": "power_systems",
		"req_tech": "fluid_dynamics",
		"effects": [],
		"unlocks": ["Plasma Cell (T2 Energy Ammo)"],
		"flavor": "",
	},
	"lightweight_alloys": {
		"name": "Lightweight Alloys",
		"tier": 1,
		"category": "processing",
		"cost": 200,
		"cost_items": {"Res1": 3},
		"type": "technology",
		"parent": "materials_science",
		"effects": [],
		# v111.6 audit: "Aluminum Smelting" — phantom (no recipe). Removed.
		"unlocks": ["Aluminum-Magnesium Alloy"],
		"flavor": "",
	},
	"basic_electronics": {
		"name": "Basic Electronics",
		"tier": 1,
		"category": "processing",
		"cost": 800,
		"cost_items": {"Cu": 20, "Si": 20},
		"type": "technology",
		"parent": "industrial_logistics",
		"effects": [],
		"unlocks": ["Standard Circuit Assembly"],
		"flavor": "",
	},
	# --- GATHERING UPGRADES ---
	"diamond_drills": {
		"name": "Diamond Tipped Drills",
		"tier": 1,
		"category": "gathering",
		"cost": 200,
		"cost_items": {"Res1": 2},
		"type": "technology",
		"parent": null,
		"req_tech": "industrial_logistics",
		# v110 schema audit: legacy description said "+25%" but the actual
		# mechanic in gathering_manager.get_action_speed_multiplier returns
		# +50% (upgrades_db: bonus 0.50). Tooltip now reads the truth.
		"effects": [
			{"type": "action_speed", "id": "gather_dirt", "bonus": 0.50, "stacks": true,
				"stack_chain": ["Ultrasonic Drills", "Plasma Bore"]},
		],
		"unlocks": [],
		"flavor": "",
	},
	"high_flow_pumps": {
		"name": "High-Flow Pumps",
		"tier": 1,
		"category": "gathering",
		"cost": 250,
		"cost_items": {"Res1": 2},
		"type": "technology",
		"parent": null,
		"req_tech": "fluid_dynamics",
		"effects": [
			{"type": "action_speed", "id": "collect_water", "bonus": 0.50, "stacks": true,
				"stack_chain": ["Superfluid Intake", "Hydro-Vortex Arrays"]},
		],
		"unlocks": [],
		"flavor": "",
	},
	"laser_cutters": {
		"name": "Laser Cutters",
		"tier": 1,
		"category": "gathering",
		"cost": 300,
		"cost_items": {"Res1": 2},
		"type": "technology",
		"parent": null,
		"req_tech": "combustion",
		"effects": [
			{"type": "action_speed", "id": "gather_wood", "bonus": 0.50, "stacks": true,
				"stack_chain": ["Mono-Filament Wire", "Molecular Disassembler"]},
		],
		"unlocks": [],
		"flavor": "",
	},
	"magnetic_funnels": {
		"name": "Magnetic Funnels",
		"tier": 1,
		"category": "gathering",
		"cost": 2000,
		"type": "technology",
		"parent": "energy_shields",
		# Solo-tier upgrade — no sibling chain, so no stack_chain field.
		"effects": [
			{"type": "action_speed", "id": "harvest_nebula", "bonus": 0.25, "stacks": false},
		],
		"unlocks": [],
		"flavor": "",
	},
	# Gathering Tier 2 (+50%) & Tier 3 (+75%)
	"ultrasonic_drills": {
		"name": "Ultrasonic Drills",
		"tier": 2,
		"category": "gathering",
		"cost": 1000,
		"cost_items": {"Res1": 250},
		"type": "technology",
		"parent": "diamond_drills",
		"effects": [
			{"type": "action_speed", "id": "gather_dirt", "bonus": 0.50, "stacks": true,
				"stack_chain": ["Diamond Tipped Drills", "Plasma Bore"]},
		],
		"unlocks": [],
		"flavor": "",
	},
	"plasma_bore": {
		"name": "Plasma Bore",
		"tier": 3,
		"category": "gathering",
		"cost": 5000,
		"cost_items": {"Res2": 20},
		"type": "technology",
		"parent": "ultrasonic_drills",
		"effects": [
			{"type": "action_speed", "id": "gather_dirt", "bonus": 0.75, "stacks": true,
				"stack_chain": ["Diamond Tipped Drills", "Ultrasonic Drills"]},
		],
		"unlocks": [],
		"flavor": "",
	},
	"superfluid_intake": {
		"name": "Superfluid Intake",
		"tier": 2,
		"category": "gathering",
		"cost": 1500,
		"cost_items": {"Res2": 15},
		"type": "technology",
		"parent": "high_flow_pumps",
		"effects": [
			{"type": "action_speed", "id": "collect_water", "bonus": 0.50, "stacks": true,
				"stack_chain": ["High-Flow Pumps", "Hydro-Vortex Arrays"]},
		],
		"unlocks": [],
		"flavor": "",
	},
	"hydro_vortex": {
		"name": "Hydro-Vortex Arrays",
		"tier": 3,
		"category": "gathering",
		"cost": 7500,
		"cost_items": {"Res3": 5, "AdvCircuit": 10},
		"type": "technology",
		"parent": "superfluid_intake",
		"effects": [
			{"type": "action_speed", "id": "collect_water", "bonus": 0.75, "stacks": true,
				"stack_chain": ["High-Flow Pumps", "Superfluid Intake"]},
		],
		"unlocks": [],
		"flavor": "",
	},
	"mono_filament": {
		"name": "Mono-Filament Wire",
		"tier": 2,
		"category": "gathering",
		"cost": 2000,
		"cost_items": {"Res2": 15},
		"type": "technology",
		"parent": "laser_cutters",
		"effects": [
			{"type": "action_speed", "id": "gather_wood", "bonus": 0.50, "stacks": true,
				"stack_chain": ["Laser Cutters", "Molecular Disassembler"]},
		],
		"unlocks": [],
		"flavor": "",
	},
	"molecular_disassembler": {
		"name": "Molecular Disassembler",
		"tier": 3,
		"category": "gathering",
		"cost": 10000,
		"cost_items": {"Res3": 10, "AdvCircuit": 15},
		"type": "technology",
		"parent": "mono_filament",
		"effects": [
			{"type": "action_speed", "id": "gather_wood", "bonus": 0.75, "stacks": true,
				"stack_chain": ["Laser Cutters", "Mono-Filament Wire"]},
		],
		"unlocks": [],
		"flavor": "",
	},
	# --- PROCESSING UPGRADES ---
	"fast_centrifuges": {
		"name": "High-RPM Centrifuges",
		"tier": 1,
		"category": "processing",
		"cost": 200,
		"type": "technology",
		"parent": "industrial_logistics",
		"effects": [
			{"type": "action_speed", "id": "centrifuge_dirt", "bonus": 0.25, "stacks": true,
				"stack_chain": ["Mag-Lev Bearings", "Quantum Separators"]},
		],
		"unlocks": [],
		"flavor": "",
	},
	"catalytic_electrodes": {
		"name": "Catalytic Electrodes",
		"tier": 1,
		"category": "processing",
		"cost": 300,
		"type": "technology",
		"parent": "fluid_dynamics",
		"effects": [
			{"type": "action_speed", "id": "electrolysis", "bonus": 0.25, "stacks": true,
				"stack_chain": ["Ion-Exchange Membranes", "Resonance Splitters"]},
		],
		"unlocks": [],
		"flavor": "",
	},
	"pyrolysis_control": {
		"name": "Pyrolysis Control",
		"tier": 1,
		"category": "processing",
		"cost": 400,
		"cost_items": {"Res1": 5},
		"type": "technology",
		"parent": "combustion",
		# Solo tier — only Charcoal Kiln has one buff in the chain.
		"effects": [
			{"type": "action_speed", "id": "charcoal_burning", "bonus": 0.25, "stacks": false},
		],
		"unlocks": [],
		"flavor": "",
	},
	"blast_furnace": {
		"name": "Blast Furnace",
		"tier": 1,
		"category": "processing",
		"cost": 800,
		"cost_items": {"Res1": 10},
		"type": "technology",
		"parent": "smelting",
		# v110 schema audit: legacy description only mentioned "Steel Foundry"
		# but upgrades_db gives the buff to BOTH smelt_steel_basic AND
		# smelt_steel_oxygen. Tooltip now shows the truth.
		"effects": [
			{"type": "action_speed", "id": "smelt_steel_basic", "bonus": 0.25, "stacks": false},
			{"type": "action_speed", "id": "smelt_steel_oxygen", "bonus": 0.25, "stacks": false},
		],
		"unlocks": [],
		"flavor": "",
	},
	"hydraulic_press": {
		"name": "Hydraulic Press",
		"tier": 1,
		"category": "processing",
		"cost": 1500,
		"cost_items": {"Res1": 10},
		"type": "technology",
		"parent": "adv_materials",
		"effects": [
			{"type": "action_speed", "id": "press_graphite", "bonus": 0.25, "stacks": false},
		],
		"unlocks": [],
		"flavor": "",
	},
	# Processing Tier 2 (+50%) & Tier 3 (+75%)
	"maglev_bearings": {
		"name": "Mag-Lev Bearings",
		"tier": 2,
		"category": "processing",
		"cost": 1000,
		"cost_items": {"Res2": 15},
		"type": "technology",
		"parent": "fast_centrifuges",
		"effects": [
			{"type": "action_speed", "id": "centrifuge_dirt", "bonus": 0.50, "stacks": true,
				"stack_chain": ["High-RPM Centrifuges", "Quantum Separators"]},
		],
		"unlocks": [],
		"flavor": "",
	},
	"quantum_separators": {
		"name": "Quantum Separators",
		"tier": 3,
		"category": "processing",
		"cost": 5000,
		"cost_items": {"Res3": 10, "AdvCircuit": 10},
		"type": "technology",
		"parent": "maglev_bearings",
		"effects": [
			{"type": "action_speed", "id": "centrifuge_dirt", "bonus": 0.75, "stacks": true,
				"stack_chain": ["High-RPM Centrifuges", "Mag-Lev Bearings"]},
		],
		"unlocks": [],
		"flavor": "",
	},
	"advanced_mineralogy": {
		"name": "Advanced Mineralogy",
		"tier": 2,
		"category": "processing",
		"cost": 5000,
		"cost_items": {"Si": 100, "Fe": 100},
		"type": "technology",
		"parent": "fast_centrifuges",
		"effects": [
			{"type": "chance_drop", "id": "Ti", "context": "Dirt centrifuging"},
		],
		"unlocks": [],
		"flavor": "Industrial Centrifuges learn to spot trace titanium.",
	},
	"ion_exchange": {
		"name": "Ion-Exchange Membranes",
		"tier": 2,
		"category": "processing",
		"cost": 1500,
		"cost_items": {"Res2": 15},
		"type": "technology",
		"parent": "catalytic_electrodes",
		"effects": [
			{"type": "action_speed", "id": "electrolysis", "bonus": 0.50, "stacks": true,
				"stack_chain": ["Catalytic Electrodes", "Resonance Splitters"]},
		],
		"unlocks": [],
		"flavor": "",
	},
	"resonance_splitters": {
		"name": "Resonance Splitters",
		"tier": 3,
		"category": "processing",
		"cost": 7500,
		"cost_items": {"Res3": 10, "AdvCircuit": 10},
		"type": "technology",
		"parent": "ion_exchange",
		"effects": [
			{"type": "action_speed", "id": "electrolysis", "bonus": 0.75, "stacks": true,
				"stack_chain": ["Catalytic Electrodes", "Ion-Exchange Membranes"]},
		],
		"unlocks": [],
		"flavor": "",
	},
	# --- MILITARY UPGRADES ---
	"processing_tungsten": {
		"name": "Processing Tungsten",
		"tier": 2,
		"category": "combat",
		"cost": 1000,
		"cost_items": {"Res1": 10},
		"type": "technology",
		"parent": "smelting",
		"effects": [],
		"unlocks": ["Tungsten Sabot Rounds (T2)"],
		"flavor": "",
	},
	"ballistics_optimization": {
		"name": "Ballistics Optimization",
		# v105b: was claiming Tungsten Sabot (gated by processing_tungsten — not here).
		# Real consumers: SlugT3 + SlugT4 crafting recipes.
		"tier": 2,
		"category": "combat",
		"cost": 1500,
		"cost_items": {"Res2": 15},
		"type": "technology",
		"parent": "processing_tungsten",
		"effects": [],
		"unlocks": ["Depleted Uranium Rounds (T3 Ammo)", "Hyper-Velocity Slug (T4 Ammo)"],
		"flavor": "",
	},
	"energy_metrics": {
		"name": "Energy Metrics",
		"tier": 2,
		"category": "infrastructure",
		"cost": 5000,
		"cost_items": {"Res2": 20, "AdvCircuit": 10},
		"type": "technology",
		"parent": "fluid_dynamics",
		"effects": [],
		"unlocks": [
			"Hydrogen Reactor",
			"Vaporizer Cell (T3 Ammo)",
			"Orbital Gas Siphon",
			"Uranium Isotope Centrifuge",
		],
		"flavor": "",
	},
	"cryogenic_systems": {
		"name": "Cryogenic Systems",
		"tier": 3,
		"category": "processing",
		"cost": 25000,
		"cost_items": {"He": 50, "Ti": 30},
		"type": "technology",
		"parent": "energy_metrics",
		"effects": [],
		"unlocks": ["Helium Coolant Cell"],
		"flavor": "",
	},
	# --- LOGISTICS UPGRADES ---
	"automated_logistics": {
		"name": "Automated Logistics",
		"tier": 2,
		"category": "infrastructure",
		"cost": 3000,
		"cost_items": {"Cu": 25, "Fe":50, "Res1": 25},
		"type": "technology",
		"parent": "industrial_logistics",
		"effects": [],
		# v111.6 audit: drift fix — building's real display name in
		# infrastructure_manager is "Drone Recovery Bay", not "Drone Bay".
		# Now matches → smart-linker can hyperlink it in tooltips.
		"unlocks": ["Drone Recovery Bay"],
		"flavor": "",
	},
	"molecular_printing": {
		"name": "Molecular Printing",
		"tier": 3,
		"category": "infrastructure",
		"cost": 5000,
		"cost_items": {"Circuit": 50, "Fiber": 20},
		"type": "technology",
		"parent": "shipwright_2",
		"effects": [],
		# v111.6 audit: drift fix — building is "Molecular Fabricator", not
		# "Fabricator". Bonus parenthetical "(+20% crafting)" dropped — if
		# that's an actual mechanic, it should be a structured effect, not
		# inline prose. Flagging for later balance check.
		"unlocks": ["Molecular Fabricator"],
		"flavor": "",
	},
	# --- END-GAME AUTOMATION (NEW) ---
	"automated_smelting": {
		"name": "Automated Smelting",
		"tier": 2,
		"category": "infrastructure",
		"cost": 2500,
		"cost_items": {"Ti": 20},
		"type": "technology",
		"parent": "blast_furnace",
		"effects": [],
		# v111.6 audit: drift fix — "Automated Smelter" is the building's
		# real display name.
		"unlocks": ["Automated Smelter"],
		"flavor": "",
	},
	"oxygen_blast_furnace": {
		"name": "Oxygen-Blast Furnaces",
		"tier": 2,
		"category": "processing",
		"cost": 5000,
		"cost_items": {"Steel": 100, "O": 200},
		"type": "technology",
		"parent": "blast_furnace",
		# Special yield buff — quantified in flavor for now. If more yield-
		# multiplier effects show up later, add a structured "yield_buff" type.
		"effects": [],
		"unlocks": [],
		"flavor": "Steel yield: 1 → 5 per Foundry cycle.",
	},
	"industrial_electrolysis": {
		"name": "Industrial Electrolysis",
		"tier": 2,
		"category": "infrastructure",
		"cost": 2500,
		"cost_items": {"Si": 50},
		"type": "technology",
		"parent": "catalytic_electrodes",
		"effects": [],
		# v111.6 audit: drift fix — building is "Industrial Electrolysis
		# Plant" (id: hydro_plant); "Hydro-Plant" was the internal-ID
		# leaking into player-facing text.
		"unlocks": ["Industrial Electrolysis Plant"],
		"flavor": "",
	},
	"molecular_compression": {
		"name": "Molecular Compression",
		"tier": 2,
		"category": "infrastructure",
		"cost": 3000,
		"cost_items": {"Fe": 100},
		"type": "technology",
		"parent": "hydraulic_press",
		"effects": [],
		# v111.6 audit: drift fix — building is "Automated Carbon Press"
		# (id: auto_press); "Auto-Press" was again the internal id leaking.
		"unlocks": ["Automated Carbon Press"],
		"flavor": "",
	},
	"mass_production_tactics": {
		"name": "Mass Production Tactics",
		"tier": 2,
		"category": "infrastructure",
		"cost": 5000,
		"cost_items": {"Circuit": 20, "Steel": 20},
		"type": "technology",
		"parent": "automated_logistics",
		# v111.6 audit: "Munitions Factory" — phantom. The string `munitions_factory`
		# is in infrastructure_manager.gd line 29 (INFRA_ENG_SCALED_BUILDINGS) as
		# if it were a building id, but no entry exists in building_db. Either
		# planned and never built, or renamed to heavy_ordnance_works.
		# Tech currently grants nothing — flagged for design follow-up.
		"effects": [],
		"unlocks": [],
		"flavor": "Industrial tactics — buildings TBD.",
	},
	"xeno_engineering": {
		"name": "Xeno-Engineering",
		"tier": 3,
		"category": "processing",
		"cost": 10000,
		"cost_items": {"SalvageData": 10, "Circuit": 50},
		"type": "technology",
		"parent": "automated_logistics",
		# v111.6 audit: BOTH unlocks were phantoms — "Alien Flora Cultivation"
		# and "Analyzing Xeno-Materials" have no matching recipe / building /
		# action anywhere. Tech currently has no real effect — vestigial.
		# Flagging for design follow-up (cut or build the missing content).
		"effects": [],
		"unlocks": [],
		"flavor": "Xeno-research path — content TBD.",
	},
	# --- END-GAME SHIPS (NEW) ---
	"capital_ship_engineering": {
		"name": "Capital Ship Doctrine",
		"tier": 4,
		"category": "ships",
		"cost": 500000,
		"cost_items": {"VoidArtifact": 20,"NavData": 75, "Res3":75}, # Audit v20.0: Added ColonyDataCore (Overseer Drop)
		"type": "technology",
		"parent": "shipwright_2",
		"effects": [],
		"unlocks": [],
		"flavor": "Gate for Capital Ship Armament. Battlecruiser hull + capital modules unlock via Zone Access tech.",
	},
	"capital_ship_armament": {
		"name": "Capital Ship Armament",
		"tier": 4,
		"category": "combat",
		"cost": 1000000,
		"cost_items": {"VoidArtifact": 10, "Superalloy": 50, "AdvCircuit": 50},
		"type": "technology",
		"parent": "capital_ship_engineering",
		# v111.6 audit: "Munitions Factory tier" → phantom (neither a building
		# id nor a recognizable concept). Building dict has no `munitions_factory`
		# entry — it's listed in INFRA_ENG_SCALED_BUILDINGS but never defined.
		"effects": [],
		"unlocks": ["Photon Torpedo (T4 Ammo)"],
		"flavor": "",
	},
	"quantum_dynamics": {
		"name": "Quantum Dynamics",
		# v105: restored after wrong-flag deletion — actually gates Fusion Core
		# and Antimatter Generator (Infrastructure) plus the Zero-Point Module
		# defensive consumable via shipyard CONSUMABLE_REQ_TECH map. Original
		# "Dreadnought Class" claim was phantom (Dreadnought is zone-gated).
		"tier": 4,
		"category": "infrastructure",
		"cost": 5000000,
		"cost_items": {"QuantumCore": 20, "VoidArtifact": 50, "ColonyDataCore": 50, "RadIsotope": 1000, "Res3": 500, "ExoticIsotope": 20},
		"type": "technology",
		"parent": "capital_ship_engineering",
		"effects": [],
		"unlocks": ["Fusion Core", "Antimatter Generator", "Zero-Point Module"],
		"flavor": "",
	},
	# New Zone Unlocks
	"deep_space_nav": {
		"name": "Deep Space Navigation",
		"tier": 3,
		"category": "zone",
		"cost": 100000,
		"cost_items": {"NavData": 25, "Ti": 150, "Res3": 10},
		"type": "technology",
		"parent": null,
		"req_tech": "warp_drive",
		"effects": [],
		# v111.6 audit: dropped 2 wrong-layer entries —
		#   • "Precious Metal Refining" — that's the precious_metal_refining
		#     tech, not an item. Tree edge (req_tech link) already shows it.
		#   • "Colony AI Integration" — same (colony_automation tech).
		"unlocks": ["Sector Beta (Mining Colony)"],
		"flavor": "",
	},
	"radiation_shielding": {
		"name": "Radiation Shielding Theory",
		"tier": 4,
		"category": "zone",
		"cost": 250000,
		"cost_items": {"Co": 50, "Al": 100, "Superalloy": 25, "AdvCircuit": 15},
		"type": "technology",
		"parent": "deep_space_nav",
		"effects": [],
		"unlocks": ["Sector Gamma (Radioactive)"],
		"flavor": "Gates Exotic Matter Analysis research.",
	},
	"exotic_matter_analysis": {
		"name": "Exotic Matter Analysis",
		"tier": 4,
		"category": "zone",
		"cost": 1000000,
		"cost_items": {"Pt": 20, "RadIsotope": 50, "QuantumCore": 3},
		"type": "technology",
		"parent": "radiation_shielding",
		"effects": [],
		"unlocks": ["Sector Delta (Crystalline)"],
		"flavor": "",
	},
	# --- EFFICIENCY BRANCH (MULTIPLIED YIELDS) ---
	"efficiency_1": {
		"name": "Efficiency I",
		"tier": 3,
		"category": "meta",
		"cost": 250000,
		"cost_items": {"Circuit": 250, "Steel": 500,"Res1": 1000, "Res2": 100},
		"type": "technology",
		"parent": "industrial_logistics",
		"effects": [
			{"type": "yield_multiplier", "factor": 2.0, "what": "Output (Gathering & Processing)"},
		],
		"unlocks": [],
		"flavor": "",
	},
	"efficiency_2": {
		"name": "Efficiency II",
		"tier": 3,
		"category": "meta",
		"cost": 1000000,
		"cost_items": {"AdvCircuit": 100, "Ti": 1000, "Res3": 50},
		"type": "technology",
		"parent": "efficiency_1",
		"effects": [
			{"type": "yield_multiplier", "factor": 4.0, "what": "Output (Gathering & Processing)"},
		],
		"unlocks": [],
		"flavor": "",
	},
	"efficiency_3": {
		"name": "Efficiency III",
		"tier": 4,
		"category": "meta",
		"cost": 5000000,
		"cost_items": {"QuantumCore": 10, "U": 500, "Pt": 250},
		"type": "technology",
		"parent": "efficiency_2",
		"effects": [
			{"type": "yield_multiplier", "factor": 8.0, "what": "Output (Gathering & Processing)"},
		],
		"unlocks": [],
		"flavor": "",
	},
	"efficiency_4": {
		"name": "Efficiency IV",
		"tier": 4,
		"category": "meta",
		"cost": 25000000,
		"cost_items": {"ExoticMatter": 5, "Os": 100, "VoidCrystal": 50},
		"type": "technology",
		"parent": "efficiency_3",
		"effects": [
			{"type": "yield_multiplier", "factor": 16.0, "what": "Output (Gathering & Processing)"},
		],
		"unlocks": [],
		"flavor": "",
	},
	"efficiency_5": {
		"name": "Efficiency V",
		"tier": 4,
		"category": "meta",
		"cost": 100000000,
		"cost_items": {"ExoticIsotope": 25, "Neutronium": 5, "QuantumCore": 50},
		"type": "technology",
		"parent": "efficiency_4",
		"effects": [
			{"type": "yield_multiplier", "factor": 32.0, "what": "Output (Gathering & Processing)"},
		],
		"unlocks": [],
		"flavor": "",
	},
	# Mid-Game Technology
	"metallurgy_advanced": {
		"name": "Advanced Metallurgy",
		"tier": 2,
		"category": "processing",
		"cost": 5000,
		"cost_items": {"Ni": 100},
		"type": "technology",
		"parent": "smelting",
		"effects": [],
		"unlocks": ["Stainless Steel Alloy"],
		"flavor": "",
	},

	"superalloy_engineering": {
		"name": "Superalloy Engineering",
		"tier": 3,
		"category": "processing",
		"cost": 100000,
		"cost_items": {"Co": 100, "Ni": 100, "Cr": 50, "Ti": 100},
		"type": "technology",
		"parent": "metallurgy_advanced",
		"effects": [],
		"unlocks": ["Superalloy"],
		"flavor": "",
	},
	# Late-Game Rare Metal Technologies
	"precious_metal_refining": {
		"name": "Precious Metal Refining",
		"tier": 3,
		"category": "processing",
		"cost": 15000, # Audit v64.1: Adjusted from 1500 to match Res2 tier
		"cost_items": {"Ti": 200, "Res2": 25},
		"type": "technology",
		"parent": null,
		"req_tech": "deep_space_nav",
		"effects": [],
		# v111.6 audit: "Palladium Refining" — phantom (no such recipe). The
		# Pd recipes that exist are crafting (Palladium Fuel Cell), not
		# refining. Dropped.
		"unlocks": ["Platinum Extraction", "Precious Metal Dredge"],
		"flavor": "",
	},
	"industrial_catalysis": {
		"name": "Industrial Catalysis",
		# v105b: was advertising +25% "All" but code paid 0.15 and only into
		# processing_speed. Aligned: 0.25 in code (see get_efficiency_bonus),
		# and description scoped to Crafting since gathering/research are
		# untouched. Also gates 4 catalyst recipes/buildings.
		"tier": 4,
		"category": "processing",
		"cost": 1000000,
		"cost_items": {"Pt": 200, "Si": 200, "AdvCircuit": 20},
		"type": "technology",
		"parent": "precious_metal_refining",
		"effects": [
			{"type": "bonus_yield", "bonus": 0.25, "what": "Crafting Speed"},
		],
		# v111.6 audit: "Platinum Catalyst Bay" → "Platinum Catalyst Chamber"
		# (building's actual display name; "Bay" was id-derived).
		"unlocks": [
			"Platinum Catalyst Matrix",
			"Silver Catalyst",
			"Platinum Catalyst Chamber",
			"Silver Catalyst Bay",
		],
		"flavor": "",
	},
	"fuel_cell_tech": {
		"name": "Fuel Cell Technology",
		"tier": 3,
		"category": "processing",
		"cost": 250000,
		"cost_items": {"Pd": 30, "H": 500, "Circuit": 30},
		"type": "technology",
		"parent": "precious_metal_refining",
		# v111.6 audit: "Hydrogen Fuel Cell" — phantom (no such recipe; the
		# only fuel-cell recipe is "Palladium Fuel Cell" already gated by
		# precious_metal_refining). This tech currently has no unlock and
		# no effect — likely vestigial. Flagging for design follow-up.
		"effects": [],
		"unlocks": [],
		"flavor": "Hydrogen-fuel research path — implementation TBD.",
	},
	"iridium_metallurgy": {
		"name": "Iridium Metallurgy",
		"tier": 3,
		"category": "processing",
		"cost": 40000,
		"cost_items": {"Pt": 50, "Res3": 10},
		"type": "technology",
		"parent": "superalloy_engineering",
		"effects": [],
		# v111.6 audit: "Iridium Extraction" → "Mine Iridium Crystals" (real
		# gathering action display name).
		"unlocks": ["Mine Iridium Crystals", "Iridium Armor Plating"],
		"flavor": "",
	},
	"exotic_metallurgy": {
		"name": "Exotic Metallurgy",
		"tier": 4,
		"category": "processing",
		"cost": 2000000,
		"cost_items": {"Ir": 100, "Res3": 50},
		"type": "technology",
		"parent": "iridium_metallurgy",
		"effects": [],
		# v111.6 audit:
		#   • "Osmium Harvesting" → "Condense Osmium Vapor" (real gathering action)
		#   • "Osmium Armor Plating" — phantom (no such recipe; only Osmium
		#     Reactor Core and Osmium Condenser exist for Os). Removed.
		"unlocks": ["Condense Osmium Vapor"],
		"flavor": "",
	},
	# --- NEW LATE-GAME TECH (Expansion) ---
	"colony_automation": {
		"name": "Colony AI Integration",
		"tier": 3,
		# v111.6 audit: "Colonial Auto-Extractor" was a phantom (no building
		# or recipe by that name). The +5 gathering-yield bonus is the real
		# (and only) effect of this tech — player notices it instantly on
		# next gather drop. Re-categorised from "infrastructure" → "meta"
		# since it now grants a passive bonus, not a building unlock.
		"category": "meta",
		"cost": 50000,
		"cost_items": {"ColonyDataCore": 1, "ColonySalvage": 100, "AdvCircuit": 50},
		"type": "technology",
		"parent": null,
		"req_tech": "deep_space_nav",
		"effects": [
			{"type": "flat_bonus", "amount": 5.0, "what": "Base Gathering Yield"},
		],
		"unlocks": [],
		"flavor": "",
	},
	"void_physics": {
		"name": "Extreme Void Physics",
		"tier": 4,
		"category": "meta",
		"cost": 5000000,
		"cost_items": {"VoidCrystal": 20, "QuantumCore": 10, "AntimatterParticle": 5},
		"type": "technology",
		"parent": "exotic_matter_analysis",
		"effects": [],
		"unlocks": [],
		"flavor": "Gates Void Navigation research.",
	},
	# ENDGAME - Sector Epsilon unlock
	"void_navigation": {
		"name": "Void Navigation",
		"tier": 4,
		"category": "zone",
		"cost": 50000000,
		"cost_items": {"QuantumCore": 30, "VoidCrystal": 50, "ExoticMatter": 20, "AncientTech": 5, "QuarantineClearance": 1, "BiohazardSample": 20},  # v58.0: Added clearance req
		"type": "technology",
		"parent": "void_physics",
		"effects": [],
		# v111.6 audit: dropped "Void Weaponry/Shielding Optimization" — those
		# are downstream research techs (void_weaponry_1 / void_shielding_1),
		# not items. Tree's req_tech edges already show they unlock next.
		"unlocks": [
			"Sector Epsilon — The Void",
			"Void Rift Anchor",
			"Chrono-Siphon",
		],
		"flavor": "",
	},
	# ENDGAME SINKS - Iteration 7
	"void_weaponry_1": {
		"name": "Void Weaponry Optimization",
		# v105c: rebalanced 100M → 25M and materials halved to match 20% → 5%
		# bonus nerf. Still above ENDGAME_RESEARCH_COST_GATE so stage-3 scaling
		# (×20 × ×2 MATERIAL_MULTIPLIER = ×40 effective) still applies.
		"tier": 4,
		"category": "combat",
		"cost": 25000000,
		"cost_items": {"VoidEssence": 25, "ChronoCore": 10, "PrimordialShard": 3, "BiohazardSample": 5, "BioWeaponCoating": 5},
		"type": "technology",
		"parent": null,
		"req_tech": "void_navigation",
		"effects": [
			{"type": "bonus_yield", "bonus": 0.05, "what": "Total Ship Damage"},
		],
		"unlocks": [],
		"flavor": "",
	},
	"void_shielding_1": {
		"name": "Void Shielding Optimization",
		# v105c: rebalanced 100M → 25M and materials halved to match 20% → 5%
		# bonus nerf. Stage-3 scaling still applies.
		"tier": 4,
		"category": "combat",
		"cost": 25000000,
		"cost_items": {"OmegaPlating": 25, "VoidEssence": 10, "PrimordialShard": 3, "Os": 12, "BiohazardSample": 5, "RegenPlating": 4},
		"type": "technology",
		"parent": null,
		"req_tech": "void_navigation",
		"effects": [
			{"type": "bonus_yield", "bonus": 0.05, "what": "Total Ship Shields"},
		],
		"unlocks": [],
		"flavor": "",
	},
	"perfect_automation": {
		"name": "Omni-Fabrication",
		"tier": 4,
		"category": "processing",
		"cost": 10000000,
		"cost_items": {"AICore": 5, "AncientTech": 5, "AdvCircuit": 200, "AIProcessor": 5},
		"type": "technology",
		"parent": "colony_automation",
		"effects": [
			{"type": "bonus_yield", "bonus": 0.30, "what": "Global Processing & Research Speed"},
		],
		"unlocks": [],
		"flavor": "",
	},
	# --- EFFICIENCY & STAT EXPANSION (Phase 7) ---
	"combat_heuristics": {
		"name": "Combat Heuristics",
		"tier": 1,
		"category": "combat",
		"cost": 1500,
		"cost_items": {"Res1": 10},
		"type": "technology",
		"parent": "industrial_logistics",
		"effects": [
			{"type": "bonus_yield", "bonus": 0.20, "what": "Combat XP gain"},
		],
		"unlocks": [],
		"flavor": "",
	},
	"shield_harmonics": {
		"name": "Shield Harmonics",
		"tier": 2,
		"category": "combat",
		"cost": 2000,
		"cost_items": {"Res1": 10},
		"type": "technology",
		"parent": "energy_shields",
		"effects": [
			{"type": "bonus_yield", "bonus": 0.20, "what": "Shield Regeneration speed"},
		],
		"unlocks": [],
		"flavor": "",
	},
	"hull_hardening": {
		"name": "Carbon Hull Lattice",
		"tier": 2,
		"category": "combat",
		"cost": 1200,
		"cost_items": {"Res1": 5, "MiteChitin": 50},
		"type": "technology",
		"parent": "shield_harmonics",
		"req_tech": "combustion",
		"effects": [
			{"type": "bonus_yield", "bonus": 0.15, "what": "Ship Max HP"},
		],
		"unlocks": [],
		"flavor": "",
	},
	"core_overclocking": {
		"name": "Reactor Overclocking",
		"tier": 2,
		"category": "combat",
		"cost": 4000,
		"cost_items": {"Res2": 10},
		"type": "technology",
		"parent": "applied_physics",
		"effects": [
			{"type": "bonus_yield", "bonus": 0.10, "what": "Combat Attack Speed"},
		],
		"unlocks": [],
		"flavor": "",
	},
	"deep_core_optics": {
		"name": "Deep Core Optics",
		"tier": 1,
		"category": "gathering",
		"cost": 800,
		"cost_items": {"Res1": 5},
		"type": "technology",
		"parent": "laser_cutters",
		"effects": [
			{"type": "flat_bonus", "amount": 1.0, "what": "Base Yield (all Gathering)"},
		],
		"unlocks": [],
		"flavor": "",
	},
	"nano_fabrication": {
		"name": "Nano-Fabrication",
		"tier": 2,
		"category": "processing",
		"cost": 5000,
		"cost_items": {"Res2": 10},
		"type": "technology",
		"parent": "automation",
		"effects": [
			{"type": "bonus_yield", "bonus": -0.15, "what": "Processing duration"},
		],
		"unlocks": [],
		"flavor": "",
	},
	"industrial_automation": {
		"name": "Industrial Automation",
		"tier": 2,
		"category": "infrastructure",
		"cost": 15000,
		"cost_items": {"Circuit": 50, "Steel": 200},
		"type": "technology",
		"parent": "automated_smelting",
		"effects": [],
		"unlocks": ["Electronics Assembler"],
		"flavor": "",
	},
	"molecular_recycling": {
		"name": "Molecular Recycling",
		"tier": 3,
		"category": "infrastructure",
		"cost": 50000,
		"cost_items": {"Res2": 50, "AdvCircuit": 25},
		"type": "technology",
		"parent": "industrial_automation",
		"effects": [],
		"unlocks": ["Matter De-constructor"],
		"flavor": "",
	},
	"cryogenic_storage": {
		"name": "Cryogenic Storage",
		"tier": 3,
		"category": "infrastructure",
		"cost": 30000,
		"cost_items": {"Ti": 100, "Si": 200},
		"type": "technology",
		"parent": "cryogenic_systems",
		"effects": [],
		"unlocks": ["Cryo-Storage Array"],
		"flavor": "",
	},
	# v66.0: Auto-Repair Techs
	"auto_repair_20": {
		"name": "Emergency Auto-Repair I",
		"tier": 2,
		"category": "combat",
		"cost": 5000,
		"cost_items": {"Res1": 10, "MiteChitin": 25, "Mesh": 5},
		"type": "technology",
		"parent": "hull_hardening",
		"effects": [
			{"type": "threshold", "at_pct": 0.20, "what": "hull/shield integrity"},
		],
		"unlocks": [],
		"flavor": "Auto-fires equipped hull/shield consumables on trigger.",
	},
	"auto_repair_40": {
		"name": "Emergency Auto-Repair II",
		"tier": 3,
		"category": "combat",
		"cost": 15000,
		"cost_items": {"Res2": 5, "Seal": 10, "Mesh": 10},
		"type": "technology",
		"parent": "auto_repair_20",
		"effects": [
			{"type": "threshold", "at_pct": 0.40, "what": "hull/shield integrity"},
		],
		"unlocks": [],
		"flavor": "",
	},
	"auto_repair_60": {
		"name": "Emergency Auto-Repair III",
		"tier": 3,
		"category": "combat",
		"cost": 50000,
		"cost_items": {"Res2": 5, "AdvCircuit": 15},
		"type": "technology",
		"parent": "auto_repair_40",
		"effects": [
			{"type": "threshold", "at_pct": 0.60, "what": "hull/shield integrity"},
		],
		"unlocks": [],
		"flavor": "",
	},
	"auto_repair_80": {
		"name": "Emergency Auto-Repair IV",
		"tier": 4,
		"category": "combat",
		"cost": 200000,
		"cost_items": {"Res3": 3},
		"type": "technology",
		"parent": "auto_repair_60",
		"effects": [
			{"type": "threshold", "at_pct": 0.80, "what": "hull/shield integrity"},
		],
		"unlocks": [],
		"flavor": "",
	},
}

var repeatable_tech_db = {
	"production_focus": {
		"name": "Recursive Optimization (Industry)",
		"description": "Infinite scaling: +5% Global Processing Speed per level.",
		"base_cost": 100000,
		"base_items": {"VoidArtifact": 5, "AdvCircuit": 50, "Bauxite": 100, "Quartz": 100, "PtOre": 25},
		"bonus_type": "processing_speed",
		"bonus_value": 0.05
	},
	"combat_focus": {
		"name": "Recursive Calibration (Combat)",
		"description": "Infinite scaling: +5% Total Ship Damage per level.",
		"base_cost": 100000,
		"base_items": {"VoidArtifact": 5, "QuantumCore": 5, "Malachite": 100},
		"bonus_type": "combat_damage",
		"bonus_value": 0.05
	},
	"gathering_focus": {
		"name": "Recursive Logistics (Gathering)",
		"description": "Infinite scaling: +5% Global Gathering Yield per level.",
		"base_cost": 100000,
		# v103e: DroneCore unsourced -> swapped to MiteChitin (obtainable:
		# zone-1 combat loot + salvage) so this recursion stays levelable.
		"base_items": {"VoidArtifact": 5, "MiteChitin": 50, "Spodumene": 100},
		"bonus_type": "gathering_yield_mult",
		"bonus_value": 0.05
	},
	# v109: three new lanes paired to the offense/output trio above —
	# defense, background production, and income velocity. VoidArtifact stays
	# the shared combat gate (engineer/captain integration); secondary mats
	# differ per lane to keep demand-breadth across production chains.
	"defense_focus": {
		"name": "Recursive Hardening (Defense)",
		"description": "Infinite scaling: +5% Max Hull HP per level.",
		"base_cost": 100000,
		"base_items": {"VoidArtifact": 5, "Steel": 100, "Superalloy": 20},
		"bonus_type": "hull_hp_mult",
		"bonus_value": 0.05
	},
	"infrastructure_focus": {
		"name": "Recursive Networking (Infrastructure)",
		"description": "Infinite scaling: +5% Global Building Yield per level.",
		"base_cost": 100000,
		"base_items": {"VoidArtifact": 5, "AdvCircuit": 30, "Cu": 100},
		"bonus_type": "building_yield_mult",
		"bonus_value": 0.05
	},
	"wealth_focus": {
		"name": "Recursive Acquisition (Wealth)",
		"description": "Infinite scaling: +5% Lira rewards from combat, quests & bounties per level.",
		"base_cost": 100000,
		"base_items": {"VoidArtifact": 5, "PirateSalvage": 30, "Au": 5},
		"bonus_type": "credit_reward_mult",
		"bonus_value": 0.05
	}
}


func _init():
	super._init("Astrophysics")
	_scale_mid_late_research_item_costs()

func _scale_mid_late_research_item_costs() -> void:
	if _research_item_costs_scaled:
		return
	_research_item_costs_scaled = true
	
	for tech_id in tech_tree:
		var node = tech_tree[tech_id]
		if not node.has("cost_items"):
			continue
		var stage = _get_research_cost_stage(node)
		if stage <= 0:
			continue

		var mult = _stage_item_multiplier(stage)
		var cost_items: Dictionary = node["cost_items"]
		for item in cost_items:
			var qty = int(cost_items[item])
			if qty <= 0:
				continue
			if not _is_scalable_cost_item(item):
				continue
			cost_items[item] = _scale_research_item_requirement(qty, mult)
		
		node["cost_items"] = cost_items
		tech_tree[tech_id] = node
	
	for rid in repeatable_tech_db:
		var r_data = repeatable_tech_db[rid]
		if not r_data.has("base_items"):
			continue
		
		var stage = _get_repeatable_cost_stage(r_data)
		if stage <= 0:
			continue

		var mult = _stage_item_multiplier(stage)
		var base_items: Dictionary = r_data["base_items"]
		for item in base_items:
			var qty = int(base_items[item])
			if qty <= 0:
				continue
			if not _is_scalable_cost_item(item):
				continue
			base_items[item] = _scale_research_item_requirement(qty, mult)
		
		r_data["base_items"] = base_items
		repeatable_tech_db[rid] = r_data

func _get_research_cost_stage(node: Dictionary) -> int:
	var cost_items: Dictionary = node.get("cost_items", {})
	var credit_cost = int(node.get("cost", 0))

	for item in cost_items:
		if item in ENDGAME_RESEARCH_ITEMS:
			return 3
	if credit_cost >= ENDGAME_RESEARCH_COST_GATE:
		return 3

	for item in cost_items:
		if item in LATE_RESEARCH_ITEMS:
			return 2
	if credit_cost >= LATE_RESEARCH_COST_GATE:
		return 2

	for item in cost_items:
		if item in MID_RESEARCH_ITEMS:
			return 1
	if credit_cost >= MID_RESEARCH_COST_GATE:
		return 1
	return 0

func _get_repeatable_cost_stage(r_data: Dictionary) -> int:
	var base_items: Dictionary = r_data.get("base_items", {})
	var base_cost = int(r_data.get("base_cost", 0))

	for item in base_items:
		if item in ENDGAME_RESEARCH_ITEMS:
			return 3
	if base_cost >= ENDGAME_RESEARCH_COST_GATE:
		return 3

	for item in base_items:
		if item in LATE_RESEARCH_ITEMS:
			return 2
	if base_cost >= LATE_RESEARCH_COST_GATE:
		return 2

	for item in base_items:
		if item in MID_RESEARCH_ITEMS:
			return 1
	if base_cost >= MID_RESEARCH_COST_GATE:
		return 1
	return 0

func _stage_item_multiplier(stage: int) -> float:
	match stage:
		3: return ENDGAME_RESEARCH_ITEM_REQ_MULT
		2: return LATE_RESEARCH_ITEM_REQ_MULT
		1: return MID_RESEARCH_ITEM_REQ_MULT
		_: return 1.0

func _is_scalable_cost_item(item: String) -> bool:
	# v104: never tier-scale drop-gated tokens or zone boss cores.
	if item in NON_SCALING_ITEMS:
		return false
	if item.ends_with("_Core"):  # Z1_Core .. Z10_Core
		return false
	return true

func _scale_research_item_requirement(base_qty: int, multiplier: float) -> int:
	var scaled = int(ceil(float(base_qty) * multiplier))
	if scaled <= base_qty:
		return base_qty + 1
	return scaled

func can_unlock(tech_id: String) -> bool:
	if not tech_id in tech_tree: return false
	if tech_id in unlocked_techs: return false
	
	var node = tech_tree[tech_id]
	var cost = int(node.get("cost", 0) * COST_MULTIPLIER)  # v56.0
	var parent = node.get("parent")
	var req_tech = node.get("req_tech")
	
	if GameState.resources.get_currency("credits") < cost: return false
	
	if "cost_items" in node:
		for item in node["cost_items"]:
			var qty = int(node["cost_items"][item] * MATERIAL_MULTIPLIER)  # v56.1
			if GameState.resources.get_element_amount(item) < qty: return false
	
	if parent and not parent in unlocked_techs: return false
	if req_tech and not req_tech in unlocked_techs: return false
	
	return true

func unlock_tech(tech_id: String) -> bool:
	if can_unlock(tech_id):
		var node = tech_tree[tech_id]
		
		# Pay
		if node.get("cost", 0) > 0:
			var scaled_cost = int(node["cost"] * COST_MULTIPLIER)  # v56.0
			GameState.resources.remove_currency("credits", scaled_cost)
		
		if "cost_items" in node:
			for item in node["cost_items"]:
				var scaled_qty = int(node["cost_items"][item] * MATERIAL_MULTIPLIER)  # v56.1
				GameState.resources.remove_element(item, scaled_qty)
				
		unlocked_techs.append(tech_id)
		tech_unlocked.emit(tech_id)
		print("Unlocked tech: " + node["name"])
		return true
	return false

func is_tech_unlocked(tech_id):
	if tech_id == null: return true
	return tech_id in unlocked_techs

func get_repeatable_level(tech_id: String) -> int:
	return repeatable_techs.get(tech_id, 0)

func get_repeatable_cost(tech_id: String) -> Dictionary:
	if not tech_id in repeatable_tech_db: return {}
	var data = repeatable_tech_db[tech_id]
	var lvl = get_repeatable_level(tech_id)
	
	var cost_cr = data["base_cost"] * pow(1.3, lvl) * COST_MULTIPLIER  # v56.0
	var costs = {"credits": int(cost_cr)}
	for res in data["base_items"]:
		costs[res] = int(data["base_items"][res] * pow(1.2, lvl))
	return costs

func can_unlock_repeatable(tech_id: String) -> bool:
	if not tech_id in repeatable_tech_db: return false
	var costs = get_repeatable_cost(tech_id)
	
	if GameState.resources.get_currency("credits") < costs["credits"]: return false
	for res in costs:
		if res == "credits": continue
		if GameState.resources.get_element_amount(res) < costs[res]: return false
	return true

func unlock_repeatable_tech(tech_id: String) -> bool:
	if can_unlock_repeatable(tech_id):
		var costs = get_repeatable_cost(tech_id)
		for res in costs:
			if res == "credits":
				GameState.resources.remove_currency("credits", costs[res])
			else:
				GameState.resources.remove_element(res, costs[res])
		
		repeatable_techs[tech_id] = get_repeatable_level(tech_id) + 1
		activity_occurred.emit()
		return true
	return false

func get_efficiency_multiplier() -> float:
	if is_tech_unlocked("efficiency_5"): return 32.0
	if is_tech_unlocked("efficiency_4"): return 16.0
	if is_tech_unlocked("efficiency_3"): return 8.0
	if is_tech_unlocked("efficiency_2"): return 4.0
	if is_tech_unlocked("efficiency_1"): return 2.0
	return 1.0

func get_efficiency_bonus(bonus_type: String) -> float:
	# v105: Refactored to accumulate into a single bonus instead of early-returning
	# from each match arm. Old structure made the repeatable-tech loop at the bottom
	# unreachable for any bonus_type handled in the match — silently killing the
	# Recursive Optimization / Calibration / Logistics endgame sinks. Now the
	# repeatable bonus always applies.
	var bonus := 0.0

	match bonus_type:
		"combat_xp":
			if "combat_heuristics" in unlocked_techs: bonus += 0.20
		"shield_regen":
			if "shield_harmonics" in unlocked_techs: bonus += 0.20
		"max_hp_mult":
			if "hull_hardening" in unlocked_techs: bonus += 0.15
		"attack_speed":
			if "core_overclocking" in unlocked_techs: bonus += 0.10
		"gathering_yield":
			if "deep_core_optics" in unlocked_techs: bonus += 1.0
			if "colony_automation" in unlocked_techs: bonus += 5.0
		"processing_speed":
			if "nano_fabrication" in unlocked_techs: bonus += 0.15
			if "perfect_automation" in unlocked_techs: bonus += 0.30
			# v105/v105b: industrial_catalysis was previously an unreachable
			# hub-style bonus_type with no consumer. Now wired into processing.
			# Bumped 0.15 → 0.25 to match player-facing description.
			if "industrial_catalysis" in unlocked_techs: bonus += 0.25
		"research_speed":
			if "perfect_automation" in unlocked_techs: bonus += 0.30

	# Hub Node Passive Bonuses (Audit v8.0 P1-25)
	if bonus_type == "applied_physics" and is_tech_unlocked("applied_physics"):
		bonus += 0.10 # +10% Energy Capacity
	if bonus_type == "materials_science" and is_tech_unlocked("materials_science"):
		bonus += 0.10 # +10% Max Hull HP
	if bonus_type == "industrial_logistics" and is_tech_unlocked("industrial_logistics"):
		bonus += 0.10 # +10% Global Production Speed

	if bonus_type == "xeno_engineering" and is_tech_unlocked("xeno_engineering"):
		bonus += 0.25 # +25% Rare Loot Chance (Used by Combat/Gathering)

	# Recursive (infinite endgame) bonuses — always summed, for every bonus_type.
	# bonus_value × levels, e.g. production_focus adds 0.05/level to processing_speed.
	for rid in repeatable_techs:
		var lvl = int(repeatable_techs[rid])
		var r_data = repeatable_tech_db.get(rid)
		if r_data and r_data["bonus_type"] == bonus_type:
			bonus += lvl * r_data["bonus_value"]

	return bonus

func get_research_speed_multiplier() -> float:
	# Audit v8.0 P2-20: +1% Research Speed per Level
	return 1.0 + (get_level() * 0.01)

func get_affordable_researches_count() -> int:
	"""Phase 2.1: Checks if tech is available AND player has specific items/credits"""
	var count = 0
	for tid in tech_tree:
		if not is_tech_unlocked(tid) and can_unlock(tid):
			# can_unlock already checks credits and items
			count += 1
	return count

func reset(decay_factor: float = 1.0) -> void:
	super.reset(decay_factor)
	unlocked_techs = []
	stop_action()

# Audit v2.0 P1-6: Soft reset preserves unlocked techs, only clears in-progress
func soft_reset():
	# Keep unlocked_techs intact!
	stop_action()
	# XP is also preserved through soft reset

func get_save_data_manager() -> Dictionary:
	var data = get_save_data()
	data["unlocked_techs"] = unlocked_techs
	data["repeatable_techs"] = repeatable_techs
	return data

func load_save_data_manager(data: Dictionary):
	load_save_data(data)
	# Filter out tech IDs that no longer exist in tech_tree (handles removed nodes
	# in old saves — e.g. salvage_heuristics / scavenger_protocol cut in cleanup).
	var saved_techs = data.get("unlocked_techs", [])
	unlocked_techs = []
	for tid in saved_techs:
		if tid in tech_tree:
			unlocked_techs.append(tid)
	repeatable_techs = data.get("repeatable_techs", {})

# v111.5: Scan-action + Data-currency machinery deleted. The original design
# had Research = Astrophysics-skill-with-idle-scan-action producing a `data`
# currency, but nothing ever started the scan loop in the UI and no system
# consumed Data. Research is now exactly what the player perceives it as:
# instant-click node unlocks.
#
# Kept as no-ops because external callers still hit these signatures:
#   - game_state.gd:121     active_manager.process_tick(delta)
#   - game_state.gd:192     active_manager.stop_action()
#   - game_state.gd:362     research_manager.calculate_offline(delta)
#   - global_header.gd:161  research_manager.is_active   (read)
#   - offline_boot_modal:143  research_manager.is_active / current_action (read)

func stop_action() -> void:
	# No-op — there's no scan loop to stop. Kept so set_active_manager() can
	# still call stop_action() when switching managers without erroring.
	is_active = false
	current_action = ""

func process_tick(_delta: float) -> void:
	pass    # No tick work; research unlocks happen instantly on click.

func calculate_offline(_delta: float):
	return null   # Nothing to accumulate offline; player gets no scan rewards.

func get_auto_consume_threshold() -> float:
	if is_tech_unlocked("auto_repair_80"): return 0.8
	if is_tech_unlocked("auto_repair_60"): return 0.6
	if is_tech_unlocked("auto_repair_40"): return 0.4
	if is_tech_unlocked("auto_repair_20"): return 0.2
	return 0.0
