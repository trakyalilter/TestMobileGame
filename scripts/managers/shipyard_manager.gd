# v71.0: Module Rarity System
enum Rarity {COMMON, UNCOMMON, RARE, LEGENDARY, UNIQUE}

const RARITY_COLORS = {
	Rarity.COMMON: Color(0.7, 0.7, 0.7), # Light Gray
	Rarity.UNCOMMON: Color(0.2, 1.0, 0.2), # Sharp Green
	Rarity.RARE: Color(0.0, 0.6, 1.0), # Vivid Electric Blue
	Rarity.LEGENDARY: Color(1.0, 0.8, 0.0), # Vivid Gold
	Rarity.UNIQUE: Color(1.0, 0.2, 0.8), # Vivid Magenta
}

const RARITY_LABELS = {
	Rarity.COMMON: "",
	Rarity.UNCOMMON: "Uncommon",
	Rarity.RARE: "Rare",
	Rarity.LEGENDARY: "Legendary",
	Rarity.UNIQUE: "Unique",
}

const RARITY_STAT_RANGE = {
	# v115: rarity COMPRESSED so a full tier step (~2.2x) out-scales every rarity
	# below Unique -> Sector N Common > Sector N-1 Legendary by raw stats (kills the
	# "my old Rare drop dominates the next-zone craft" dead-common problem). Rarity
	# is now a within-tier bump + affixes; only UNIQUE still leapfrogs one tier (the
	# jackpot skip-key). The honest penetration wall enforces it in combat.
	Rarity.COMMON: [0.00, 0.00],    # 1.00x fixed - baseline crafted
	Rarity.UNCOMMON: [0.10, 0.20],  # 1.10x-1.20x - within-zone upgrade
	Rarity.RARE: [0.25, 0.45],      # 1.25x-1.45x - within-zone (< next-Common 2.2x)
	Rarity.LEGENDARY: [0.40, 0.55], # v120: 1.40x-1.55x (was 1.55-1.85). Trimmed so a carried
									# N-1 Legendary's base+rarity sits clearly UNDER a clean
	                                # next-tier Common (2.2x) — its affixes/cores are then a
	                                # comfort margin, not a tier-leapfrog. Keeps Common > Leg
	                                # without nerfing the affix system. Still > Rare (3 affixes).
	Rarity.UNIQUE: [1.40, 2.20],    # 2.40x-3.20x - jackpot: leapfrogs ONE tier, then retires
}

# v114 (Zone Tier-Gate): the per-zone signature alloy each Z2-Z10 common module
# requires (injected at craft time by get_effective_module_cost). See docs/ZONE_TIER_GATE.md.
const TIER_ALLOY_BY_ZONE := {
	2: "ChondriteAlloy", 3: "WreckforgedAlloy", 4: "RimeAlloy", 5: "XenoforgedAlloy",
	6: "ColonyAlloy", 7: "GammaAlloy", 8: "PrismaticAlloy", 9: "BioforgedAlloy", 10: "AeonAlloy",
}

# Drop scaling curve per zone (kept controlled and tapering in late game).
const MODULE_ZONE_SCALE_EARLY = 1.34
const MODULE_ZONE_SCALE_LATE = 1.28
const MODULE_ZONE_LATE_START = 7

# Stats that get rarity bonuses (damage, defense, HP, etc.)
# v145: "accuracy" removed — the player-accuracy axis is deleted (see the note in
# combat_manager.do_player_attack). The sensor drop-rate stats that replaced it
# (enemy_drop_mult / module_drop_mult) are deliberately NOT here: they are
# fractions, and rarity-boosting or zone-scaling a farm-rate multiplier compounds
# into a loot firehose exactly like the pre-v109 accuracy drop bonus did.
const BOOSTABLE_STATS = [
	"atk_kinetic", "atk_energy", "atk_explosive", "atk_cryo",  # v109: Cryo 4th type
	"hp", "def", "eva", "crit_chance",
	"max_shield", "shield_regen", "energy_capacity",
	"atk_speed_bonus", "shield_regen_mult", "atk_speed_mult",
	"jamming_strength", "atk_interval"
]

# Zone scaling is applied only to flat/core stats.
const ZONE_SCALABLE_STATS = [
	"atk_kinetic", "atk_energy", "atk_explosive", "atk_cryo",  # v109: Cryo 4th type
	"hp", "def", "eva",
	"max_shield", "shield_regen", "energy_capacity",
	"atk_interval"
]

# v110: Battery-only energy model. Hulls provide ZERO energy. Every consumer
# module (weapon/shield/armor/engine/sensor) draws CONSUMER_LOAD_BY_TIER[zone];
# every battery supplies BATTERY_CAP_BY_TIER[zone]. v112: battery supply gives
# each hull tier ~25% power HEADROOM over a full tier-matched consumer set. It
# used to be exactly 1:1 ("exactly powers"), which left ZERO room — slotting any
# higher-tier drop tripped energy_used>energy_capacity and hard-blocked combat
# ("SHIP UNPOWERED"), so a drop's dopamine became "why can't I use it." 25%
# headroom lets the player slot a few next-tier modules before needing battery
# upgrades; a multi-tier leap still requires investment, so the battery economy
# stays a real (non-punishing) constraint. Both DERIVED by tier (not stored
# per-module) so the whole ~50-module roster stays balanced. Index = tier-1.
# Save-safe: energy is derived, so existing loadouts just gain headroom.
const CONSUMER_LOAD_BY_TIER := [10, 15, 25, 40, 60, 100, 150, 220, 350, 500]
const BATTERY_CAP_BY_TIER   := [40, 80, 100, 200, 240, 460, 800, 1000, 1750, 2250]
const CONSUMER_SLOT_TYPES := ["weapon", "shield", "armor", "engine", "sensor"]

# Energy a module-DEFINITION DRAWS (consumers) — works on the def dict so UI
# that only has m_data (no id) can use it too.
func get_def_energy_load(mdef: Dictionary) -> int:
	if not (mdef.get("slot_type", "") in CONSUMER_SLOT_TYPES):
		return 0
	# Explicit override for modules whose zone doesn't match their intended
	# power tier (e.g. Cryo-Lance: zone 11 but starter prestige weapon).
	if mdef.has("power_tier"):
		var pt: int = clampi(int(mdef["power_tier"]), 1, CONSUMER_LOAD_BY_TIER.size())
		return CONSUMER_LOAD_BY_TIER[pt - 1]
	var z: int = int(mdef.get("zone", mdef.get("zone_difficulty", 1)))
	z = clampi(z, 1, CONSUMER_LOAD_BY_TIER.size())
	return CONSUMER_LOAD_BY_TIER[z - 1]

func get_def_energy_capacity(mdef: Dictionary) -> int:
	if mdef.get("slot_type", "") != "battery":
		return 0
	var z: int = int(mdef.get("zone", mdef.get("zone_difficulty", 1)))
	z = clampi(z, 1, BATTERY_CAP_BY_TIER.size())
	return BATTERY_CAP_BY_TIER[z - 1]

# id-based wrappers (used by recalc / equip / per-id UI).
func get_module_energy_load(mid: String) -> int:
	if not mid in modules:
		return 0
	return get_def_energy_load(modules[mid])

func get_module_energy_capacity(mid: String) -> int:
	if not mid in modules:
		return 0
	return get_def_energy_capacity(modules[mid])

# Mid/Late progression tuning for craftable module item requirements.
const MID_MODULE_ITEM_REQ_MULT = 1.35   # v142c: superseded by MODULE_COST_ZONE_BASE
const LATE_MODULE_ITEM_REQ_MULT = 1.75  # v142c: superseded by MODULE_COST_ZONE_BASE

# v142c MODULE MATERIAL COST CURVE (owner, 2026-07-25): "first zones shouldn't
# cost much to craft gear, but after that the game must increase required
# materials, so the player focuses on gather+craft + farming and supports their
# economy with infrastructure — so these features don't go to waste."
#
# The old two-stage 1.35 / 1.75 was far too shallow to do that. Module STATS step
# 3.75x per zone (TIER_STEP_NEW), so a Z10 module is ~100,000x stronger than a Z1
# one while costing under 2x the materials. Crafting stopped being an economic
# decision around Z3, which is exactly why gather/craft/infra felt optional later.
#
# Now keyed off the module's own zone, not which materials its recipe happens to
# mention (the old _get_module_cost_stage route leaked — a low-zone module using
# one late material was billed as late, and vice versa).
#
#   cost_mult = MODULE_COST_ZONE_BASE ^ (zone - MODULE_COST_FREE_ZONES)
#   Z1-Z2 exempt (onboarding stays frictionless) -> Z3 1.55x, Z6 5.8x, Z10 33x.
#
# Liras cost is deliberately NOT scaled here — that is a separate sink, and
# leaving it out keeps this one variable isolated for sim tuning.
const MODULE_COST_ZONE_BASE := 1.55
const MODULE_COST_FREE_ZONES := 2

const EARLY_MODULE_REQ_TECHS = [
	"kinetics_101", "laser_optics", "power_systems",
	"lightweight_alloys", "basic_electronics",
	# v111.5: eff_scanning_1 removed from early-module gate list (tech was
	# cut — it had no real effect on Data which had no consumer).
	"energy_shields", "combustion"
]

const LATE_MODULE_REQ_TECHS = [
	# v111.7: dropped capital_ship_engineering + void_physics (collapsed bridge
	# techs). Neither was ever a module research_req, so this is inert tidy-up.
	"quantum_dynamics", "xeno_engineering",
	"exotic_matter_analysis", "void_navigation"
]

const MID_MODULE_ITEMS = [
	"Res2", "Res3", "AdvCircuit", "Superalloy", "NavData",
	"ColonyDataCore", "RadIsotope", "ExoticIsotope", "AntimatterParticle"
]

const LATE_MODULE_ITEMS = [
	"VoidArtifact", "VoidCrystal", "VoidEssence", "QuantumCore",
	"ChronoCore", "ExoticMatter", "Neutronium", "AncientTech",
	"AICore", "AIProcessor", "PrimordialShard", "OmegaPlating"
]

# v74.0: Module Affix System (Diablo/PoE Style)
# Categories: tactical, industrial, economy
const AFFIX_DB = {
	# --- TACTICAL (Weapon, Sensor) ---
	"static_burst": {
		"name": "Static Burst", "type": "tactical", "scaling": "percent",
		"range": [3, 8], "limit_to": ["weapon"],
		"desc": "%d%% shock chance on hit to reset enemy attack timer."
	},
	"void_strike": {
		"name": "Void Strike", "type": "tactical", "scaling": "percent",
		"range": [3, 8], "limit_to": ["weapon"],
		"desc": "%d%% chance to bypass Shield and deal Hull damage directly."
	},
	"flat_atk": {
		"name": "Sharpened Edge", "type": "tactical", "scaling": "flat",
		"range": [2, 5], "limit_to": ["weapon"],
		"desc": "+%d Flat Attack damage."
	},
	# v145: "flat_accuracy" (Targeting Computer, +N Flat Accuracy) DELETED — it sold
	# the player a stat that resolved to nothing. Weapons keep flat_atk / static_burst
	# / void_strike / servo_overclock / combat_sight, so the weapon pool is still 8 deep.
	"servo_overclock": {
		"name": "Servo Overclock", "type": "tactical", "scaling": "percent",
		"range": [5, 12], "limit_to": ["weapon"],
		"desc": "+%d%% Attack Speed."
	},

	# --- DEFENSIVE (Armor, Shield) ---
	"flat_hp": {
		"name": "Reinforced Layers", "type": "defensive", "scaling": "flat",
		"range": [5, 15], "limit_to": ["armor"],
		"desc": "+%d Flat Hull Integrity."
	},
	"flat_def": {
		"name": "Damped Plating", "type": "defensive", "scaling": "flat",
		"range": [1, 3], "limit_to": ["armor"],
		"desc": "+%d Flat Defense."
	},
	"flat_shield": {
		"name": "Flux Capacitor", "type": "defensive", "scaling": "flat",
		"range": [10, 30], "limit_to": ["shield"],
		"desc": "+%d Flat Shield Capacity."
	},
	"capacitor_pulse": {
		"name": "Capacitor Pulse", "type": "defensive", "scaling": "percent",
		"range": [2, 5], "limit_to": ["shield", "battery"],
		"desc": "Instantly restore %d%% Max Shield on every enemy kill."
	},
	"nanite_resurgence": {
		"name": "Nanite Resurgence", "type": "defensive", "scaling": "percent",
		"range": [2, 5], "limit_to": ["armor"],
		"desc": "Instantly restore %d%% Max Hull on every enemy kill."
	},

	# --- v127 R3: per-type damage RESISTANCE (Armor, Shield) ---
	# Percent scaling -> stored as a fraction (roll 5-20 -> 0.05-0.20; GA -> 0.40).
	# Aggregated into the ship's resist_k/e/x in recalc_stats, capped 0.75 each.
	"resist_k": {
		"name": "Ablative Plating", "type": "defensive", "scaling": "percent",
		"range": [5, 20], "limit_to": ["armor", "shield"],
		"desc": "+%d%% Kinetic Resistance."
	},
	"resist_e": {
		"name": "Faraday Mesh", "type": "defensive", "scaling": "percent",
		"range": [5, 20], "limit_to": ["armor", "shield"],
		"desc": "+%d%% Energy Resistance."
	},
	"resist_x": {
		"name": "Blast Baffling", "type": "defensive", "scaling": "percent",
		"range": [5, 20], "limit_to": ["armor", "shield"],
		"desc": "+%d%% Explosive Resistance."
	},

	# --- SENSOR (v128): loot-finding identity. Sensor rolls ONLY these three.
	# Wired: enemy_drop_mult -> win_fight loot qty (elements+Liras);
	# module_drop_mult -> get_effective_module_drop_chance;
	# stone_drop_mult -> _roll_hack_stone_drops.
	"enemy_drop_mult": {
		"name": "Prospector Array", "type": "utility", "scaling": "percent",
		"range": [5, 10], "limit_to": ["sensor"],
		"desc": "+%d%% loot quantity from destroyed enemies."
	},
	"module_drop_mult": {
		"name": "Salvage Scanner", "type": "utility", "scaling": "percent",
		"range": [8, 15], "limit_to": ["sensor"],
		"desc": "+%d%% module drop chance."
	},
	"stone_drop_mult": {
		"name": "Cryptographic Decoder", "type": "utility", "scaling": "percent",
		"range": [10, 20], "limit_to": ["sensor"],
		# v141: dead stat before Firmware Hacking — _roll_hack_stone_drops returns
		# EMPTY without that tech, so this affix multiplies zero. Gate it out of the
		# roll pool until the system it scales actually exists for the player.
		"research_req": "firmware_hacking",
		"desc": "+%d%% Hack Card drop chance."
	},
	# v85.1: New Combat Affixes
	"combat_sight": {
		"name": "Combat Sight", "type": "tactical", "scaling": "percent",
		"range": [2, 5], "limit_to": ["weapon"],
		"desc": "+%d%% Critical Strike chance."
	},
	"reflexive_plating": {
		"name": "Reflexive Plating", "type": "defensive", "scaling": "flat",
		"range": [2, 5], "limit_to": ["armor", "engine"],
		"desc": "+%d Flat Evasion."
	},
	"hull_heal_on_hit": {
		"name": "Nanite Syringe", "type": "defensive", "scaling": "linear_tier",
		"range": [1, 3], "limit_to": ["weapon", "armor"],
		"desc": "Restore %d Hull Integrity on every hit."
	},
	"shield_heal_on_hit": {
		"name": "Shield Siphon", "type": "defensive", "scaling": "linear_tier",
		"range": [1, 3], "limit_to": ["weapon", "shield"],
		"desc": "Restore %d Shield Capacity on every hit."
	},
	# v85.3: Refined Sci-Fi Affixes (Inspiration, not Imitation)
	"lucky_hit_chance": {
		"name": "Tactical Breach Chance", "type": "tactical", "scaling": "percent",
		"range": [5, 10], "limit_to": ["weapon"],
		"desc": "+%d%% Tactical Breach Chance."
	},
	"dmg_healthy": {
		"name": "Precision Calibration", "type": "tactical", "scaling": "percent",
		"range": [10, 20], "limit_to": ["weapon"],
		"desc": "+%d%% damage against High Integrity enemies."
	},
	"dmg_injured": {
		"name": "Structural Exploitation", "type": "tactical", "scaling": "percent",
		"range": [15, 30], "limit_to": ["weapon"],
		"desc": "+%d%% damage against Severely Damaged enemies."
	},
	"vuln_on_hit": {
		"name": "Exposing Pulse", "type": "tactical", "scaling": "percent",
		"range": [5, 12], "limit_to": ["weapon"],
		"desc": "%d%% chance to make enemies Exposed."
	},
	"berserk_on_kill": {
		"name": "Overdrive Catalyst", "type": "tactical", "scaling": "percent",
		"range": [8, 15], "limit_to": ["weapon", "engine"],
		"desc": "%d%% chance on kill to enter Overdrive."
	}
}

# v85.3: Sci-Fi Thematic Naming System
const AFFIX_NAMING = {
	"static_burst": {"prefix": "Overloaded", "suffix": "of Discharge"},
	"void_strike": {"prefix": "Phased", "suffix": "of the Void"},
	"flat_atk": {"prefix": "Charged", "suffix": "of Lethality"},
	"servo_overclock": {"prefix": "Overclocked", "suffix": "of Haste"},
	"flat_hp": {"prefix": "Reinforced", "suffix": "of Bulwark"},
	"flat_def": {"prefix": "Hardened", "suffix": "of Bastion"},
	"flat_shield": {"prefix": "Flux", "suffix": "of the Aegis"},
	"capacitor_pulse": {"prefix": "Kinetic", "suffix": "of the Dynamo"},
	"nanite_resurgence": {"prefix": "Repairing", "suffix": "of Nanites"},
	"combat_sight": {"prefix": "Surgical", "suffix": "of the Assassin"},
	"reflexive_plating": {"prefix": "Stealth", "suffix": "of Ghosting"},
	"hull_heal_on_hit": {"prefix": "Siphoning", "suffix": "of the Parasite"},
	"shield_heal_on_hit": {"prefix": "Conductive", "suffix": "of the Siphon"},
	"lucky_hit_chance": {"prefix": "Opportunistic", "suffix": "of Synergy"},
	"dmg_healthy": {"prefix": "Executioner's", "suffix": "of the Hunt"},
	"dmg_injured": {"prefix": "Sadistic", "suffix": "of Ending"},
	"vuln_on_hit": {"prefix": "Shattering", "suffix": "of Weakness"},
	"berserk_on_kill": {"prefix": "Neural", "suffix": "of the Reckless"}
}

# Step 6 (v118 redesign): Matrix-core FACETS. PoE-style type-matching — a core's
# effect depends on the HOST module's slot category (weapon=offense / armor+shield=
# defense / engine+sensor+other=utility). Soft per-core, compounds over long runs.
# Two facets SOFTEN (never break) a gate, both offense-only & capped in combat:
# armor_pen (tier wall) and resist_pierce (resist gate). See docs/MATRIX_CORES.md.
const GEM_FACETS = {
	# CRIMSON (Wrath) — crit chance+damage / damage reduction / ammo efficiency
	# (weapon bundles crit_chance so crit_damage isn't dead at the 5% base crit)
	"CrackedCrimsonCore":  {"weapon": {"crit_chance": 0.02, "crit_damage": 0.06}, "defense": {"damage_reduction": 0.015}, "utility": {"ammo_eff": 0.04}},
	"StableCrimsonCore":   {"weapon": {"crit_chance": 0.04, "crit_damage": 0.15}, "defense": {"damage_reduction": 0.03},  "utility": {"ammo_eff": 0.10}},
	"PristineCrimsonCore": {"weapon": {"crit_chance": 0.08, "crit_damage": 0.30}, "defense": {"damage_reduction": 0.06},  "utility": {"ammo_eff": 0.20}},
	# COBALT (Surge) — attack speed / shield regen / energy efficiency
	"CrackedCobaltCore":   {"weapon": {"attack_speed": 0.02}, "defense": {"shield_regen_mult": 0.06}, "utility": {"energy_eff": 0.02}},
	"StableCobaltCore":    {"weapon": {"attack_speed": 0.05}, "defense": {"shield_regen_mult": 0.15}, "utility": {"energy_eff": 0.05}},
	"PristineCobaltCore":  {"weapon": {"attack_speed": 0.10}, "defense": {"shield_regen_mult": 0.30}, "utility": {"energy_eff": 0.10}},
	# TOPAZ (Focus) — armor penetration (tier-wall softener) / evasion / salvage find.
	# v145: the utility facet was accuracy_flat, which resolved to nothing. It is now
	# module_drop_mult, matching the sensor slot's loot identity (utility hosts are
	# engine/sensor/battery). Read in combat_manager.get_effective_module_drop_chance.
	"CrackedTopazCore":    {"weapon": {"armor_pen": 0.03}, "defense": {"evasion_flat": 2.0},  "utility": {"module_drop_mult": 0.03}},
	"StableTopazCore":     {"weapon": {"armor_pen": 0.07}, "defense": {"evasion_flat": 5.0},  "utility": {"module_drop_mult": 0.06}},
	"PristineTopazCore":   {"weapon": {"armor_pen": 0.12}, "defense": {"evasion_flat": 10.0}, "utility": {"module_drop_mult": 0.12}},
	# AMETHYST (Harmonics) — resist pierce (resist-gate softener) / max hull / restore-on-kill
	"CrackedAmethystCore":  {"weapon": {"resist_pierce": 0.03}, "defense": {"max_hull_mult": 0.02}, "utility": {"restore_on_kill": 0.02}},
	"StableAmethystCore":   {"weapon": {"resist_pierce": 0.06}, "defense": {"max_hull_mult": 0.05}, "utility": {"restore_on_kill": 0.04}},
	"PristineAmethystCore": {"weapon": {"resist_pierce": 0.12}, "defense": {"max_hull_mult": 0.10}, "utility": {"restore_on_kill": 0.08}},
	# v135a: RESONANT tier (CMB_4 warp node) — ~2x Pristine, continuing the doubling.
	# A single Resonant of a color already brushes GEM_FACET_CAPS on its tight facet
	# (ammo_eff/energy_eff/armor_pen/resist_pierce), which is the intended diversity
	# push — one Resonant of a color largely satisfies it, freeing sockets for others.
	"ResonantCrimsonCore":  {"weapon": {"crit_chance": 0.15, "crit_damage": 0.60}, "defense": {"damage_reduction": 0.12}, "utility": {"ammo_eff": 0.35}},
	"ResonantCobaltCore":   {"weapon": {"attack_speed": 0.18}, "defense": {"shield_regen_mult": 0.55}, "utility": {"energy_eff": 0.18}},
	"ResonantTopazCore":    {"weapon": {"armor_pen": 0.18}, "defense": {"evasion_flat": 18.0}, "utility": {"module_drop_mult": 0.20}},
	"ResonantAmethystCore": {"weapon": {"resist_pierce": 0.18}, "defense": {"max_hull_mult": 0.18}, "utility": {"restore_on_kill": 0.15}},
}

# v118: aggregate caps per facet — the most any number of sockets can grant. Sized so
# ~4-5 cores reach the cap (past that, more of the same facet is wasted -> pushes a
# diverse matrix), and so a maxed T10 hull (up to 18 weapon / 27 defense / 33 utility
# sockets) can't stack to absurd or BROKEN values (energy_eff/ammo_eff stay < 1.0).
# v142 tier-gate: a Greater Affix DOUBLED the max roll (dmg_injured landed at
# +60%), which was the last offensive term keeping old maxed gear at parity
# with the next tier. 1.5x keeps GA a real jackpot without clearing the step.
const GA_MULT := 1.5
const GEM_FACET_CAPS := {
	# v142 tier-gate: OFFENSIVE facets trimmed ~2x. With the 3.75x tier step doing
	# most of the work, this is the smaller half of the fix — the 2.2x-step version
	# would have needed a 3-4x gut. Defensive facets + affixes left intact.
	"crit_chance": 0.20, "crit_damage": 0.75, "attack_speed": 0.20,
	"shield_regen_mult": 1.20, "max_hull_mult": 0.40,
	# v145: accuracy_flat cap dropped with the stat. module_drop_mult inherits the
	# Topaz utility slot; 0.60 keeps the "~5 Pristine reach the cap" shape above.
	"evasion_flat": 50.0, "module_drop_mult": 0.60,
	"ammo_eff": 0.40, "energy_eff": 0.30, "restore_on_kill": 0.25,
	"damage_reduction": 0.30, "armor_pen": 0.20, "resist_pierce": 0.30,
}

var affix_bonuses = {
	"static_burst": 0.0,
	"capacitor_pulse": 0.0,
	"void_strike": 0.0,
	"servo_overclock": 0.0,
	"nanite_resurgence": 0.0,
	"enemy_drop_mult": 0.0,
	"module_drop_mult": 0.0,
	"stone_drop_mult": 0.0,
	# v80.1: Flat Scaling Affixes  (v145: flat_accuracy removed with the stat)
	"flat_hp": 0.0,
	"flat_def": 0.0,
	"flat_atk": 0.0,
	"flat_shield": 0.0,
	# v85.1: New Affixes
	"combat_sight": 0.0,
	"reflexive_plating": 0.0,
	"hull_heal_on_hit": 0.0,
	"shield_heal_on_hit": 0.0,
	# v85.2: New D4 Affixes
	"lucky_hit_chance": 0.0,
	"dmg_healthy": 0.0,
	"dmg_injured": 0.0,
	"vuln_on_hit": 0.0,
	"berserk_on_kill": 0.0,
	# v127 R3: per-type damage resistance affixes (armor/shield)
	"resist_k": 0.0,
	"resist_e": 0.0,
	"resist_x": 0.0
}

# v71.1: Alert System for new drops
signal alert_changed(state: bool)
var new_drops_alert: bool = false:
	set(val):
		if new_drops_alert != val:
			new_drops_alert = val
			alert_changed.emit(val)

var active_hull: String = "corvette_hull"
var module_inventory: Dictionary = {}
var unseen_modules: Dictionary = {}
# v111.18 Phase 2: persistent Armory grid positions for the spatial inventory.
# { item_id: {"x": int, "y": int} }. Items without an entry are auto-packed.
var armory_layout: Dictionary = {}
var loadout: Dictionary = {} # {slot_index: module_id}
# v113 (NG+ P2): the dedicated Relic slot — a single Threshold Relic (master key),
# SEPARATE from the hull's weapon/armor grid (never competes for a hull slot).
# Persists across Warp (re-granted in execute_warp); cleared only on hard reset.
var equipped_relic: String = ""
var ammo_loadout: Dictionary = {} # {slot_index: ammo_id}

# v66.0: Consumable Slots
var consumable_hull_slot: String = "" # e.g. "Mesh"
var consumable_shield_slot: String = "" # e.g. "BasicBooster"

# Loadout Presets — 5 saved builds (Melvor-style equipment sets) for quick swap.
# v113 (NG+ P2): bumped 3→5 so multi-phase NG+ bosses can be answered with one
# preset per element (Cryo / Corrosion / …), tap-swapped mid-fight. Old 3-preset
# saves migrate cleanly — the load handler only restores indices present here, so
# 4 & 5 simply start empty.
var loadout_presets: Dictionary = {
	1: {"name": "", "loadout": {}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""},
	2: {"name": "", "loadout": {}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""},
	3: {"name": "", "loadout": {}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""},
	4: {"name": "", "loadout": {}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""},
	5: {"name": "", "loadout": {}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""}
}
# v134g: loadouts are no longer saved manually. The live ship build belongs to ONE
# active slot; every equip/unequip/ammo/consumable edit auto-saves into it, and
# clicking a slot switches the whole ship to that build (an empty slot = empty
# ship, ready to build fresh). active_preset_idx is the slot being edited;
# _suppress_preset_autosave gates the auto-save while a slot is being applied.
var active_preset_idx: int = 1
var _suppress_preset_autosave: bool = false

func _autosave_active_preset() -> void:
	if _suppress_preset_autosave:
		return
	if active_preset_idx >= 1 and active_preset_idx in loadout_presets:
		save_loadout_preset(active_preset_idx)

# v72.3: Research Requirements for non-module equipment (Ammo, Consumables)
const ELEMENT_RESEARCH_REQS = {
	# v129: SlugT1/MissileT1 equip gates removed — the T1 starter combat kit
	# (weapon + battery + shield + all three T1 ammo types) is research-free so the
	# tutorial stops bouncing the player to Research. T2+ gates unchanged.
	"SlugT2": "ballistics_optimization",
	# v105b: was "high_energy_munitions" — a tech that doesn't exist in tech_tree.
	# Players could craft SlugT3/T4 via ballistics_optimization but never equip
	# them (can_equip_module check failed against unknown tech). Aligned to the
	# same tech that gates the crafting recipes.
	"SlugT3": "ballistics_optimization",
	"SlugT4": "ballistics_optimization",
	"CellT2": "laser_optics",
	"CellT3": "cryogenic_systems",
	"CellT4": "cryogenic_systems",
	"MissileT2": "advanced_rocketry",
	"MissileT3": "advanced_rocketry",
	"MissileT4": "capital_ship_armament",
	"EmergencyPatch": "basic_engineering", # Early game
	"Mesh": "adv_materials",
	"Seal": "adv_materials",
	"BasicBooster": "basic_engineering", # v129: was energy_shields — starter shield kit matches EmergencyPatch's gate
	"IonField": "field_theory",
	"NitroCoolant": "cryogenic_systems",
	"ZeroPoint": "quantum_dynamics"
}
var custom_modules: Dictionary = {} # Feature v66.0: Random Rare Drops
var _module_item_costs_scaled := false

# Calculated Stats
var max_hp = 100
var current_hp = 100
var active_shield = 0
var max_shield = 0
var shield_regen = 0
var hp_regen = 0 # v80.1: Added for Trinity set bonuses
var attack_kinetic = 0
var attack_energy = 0
var attack_explosive = 0 # Phase 9
# v127: player per-type damage RESISTANCE (0.0-0.75). Summed from equipped
# modules (baseline on armor/shield defs + rollable affix) in recalc_stats,
# capped at 0.75 each, then applied to incoming enemy damage of the matching
# type. Defaults 0 -> combat is mathematically unchanged until modules grant it.
var resist_k = 0.0
var resist_e = 0.0
var resist_x = 0.0
var attack = 0 # Combined
var defense = 0
var evasion = 0
# v145: `var accuracy` is GONE. It aggregated base 100 + sensor stats + the
# flat_accuracy affix + the Topaz accuracy_flat facet + the Overseer set bonus,
# and its single consumer was a hit roll that could never miss. `evasion` above
# is the OTHER axis (player dodge vs enemy accuracy) and is live — do not
# confuse the two if this ever gets revisited.
var crit_chance = 0.05 # 5% base
var energy_used = 0
var energy_capacity = 0  # v110: ship's own energy field, decoupled from resources.max_energy (infra grid)
var attack_speed_bonus = 0.0
var shield_regen_bonus = 0.0
var jamming_strength = 0.0 # New: EW Enemy Slow % (0.0 to 1.0)


signal hull_constructed(hull_id)
signal module_crafted(module_id)
signal inventory_updated() # New signal for UI refresh
signal hack_stone_applied(stone_id)  # v128: a Hack Card was successfully applied (mission arc)

var hulls: Dictionary = {
	# v80.1: 10 formula-driven hulls — HP = floor(80 × 2.2^(N-1)), Slots = 6 + 2N
	"corvette_hull": {
		"name": "Corvette",
		"stats": {"hp": 120, "energy_capacity": 25},
		"cost": {"credits": 0},
		"slots": ["weapon", "weapon", "shield", "armor", "engine", "battery", "battery", "sensor"], # 8
		"visual": "res://assets/ships/1.png",
		"tier": 1
	},
	"frigate_hull": {
		"name": "Industrial Frigate",
		"stats": {"hp": 200, "energy_capacity": 75},
		# v126: Reinforced Plating gets its intended "early ship-frame upgrade" sink.
		# SalvagedAlloy/DamagedCircuitry drop only in Z1-2; the frigate (tier 2) is built
		# in that same era, so the reclaimed loop terminates here instead of piling up
		# dead. Anti-deadlock: lvl-8 fallback recipes mint both from Steel/Circuit.
		# v139c band surgery: 4 -> 3 plating (m026b measured 0.7h active on the
		# 1h/day pacing curve — the frigate beat targets ~0.5h).
		"cost": {"credits": 30000, "Steel": 50, "ReinforcedPlating": 3},
		"slots": ["weapon", "weapon", "shield", "shield","armor", "armor", "engine", "battery", "battery", "sensor"], # 10
		"research_req": "shipwright_1",
		"visual": "res://assets/ships/2.png",
		"tier": 2
	},
	"destroyer_hull": {
		"name": "Destroyer",
		"stats": {"hp": 387, "energy_capacity": 120},
		# v126: continues the Reinforced Plating sink into the tier-3 hull (still Z1-2 era).
		# v138c: ReinforcedPlating 10 -> 5 — at 4 SalvagedAlloy + 2 DamagedCircuitry +
		# 10 Steel per plate (thin Z1-2-only drops), the 10-plate bill was a ~2.5-day
		# offline-accrual gate blocking the new Z3 first-warp cadence.
		# v139c band surgery: 5 -> 3 (m030c was the single fattest pre-warp mission
		# at 1.55h active; the plating chain is salvage-bound, not skill-bound).
		"cost": {"credits": 90000, "Steel": 100, "Circuit": 20, "ReinforcedPlating": 3},
		"slots": ["weapon", "weapon", "weapon", "shield", "shield", "armor", "armor", "engine", "battery", "battery", "battery", "sensor"], # 12
		"research_req": "shipwright_2",
		"visual": "res://assets/ships/3.png",
		"tier": 3
	},
	"cruiser_hull": {
		"name": "Heavy Cruiser",
		"stats": {"hp": 852, "energy_capacity": 260},
		# v142d: AdvCircuit 50 made this hull effectively UNBUILDABLE when it unlocks —
		# craft_adv_circuit is level_req 40 but zone_4_access lands the player near
		# L35, so the primary recipe is still locked. It was the sim bot's hard wall
		# in every run. Reshaped onto the Z3 alloy + automatable stock.
		# NOTE: hull costs bypass every scaling layer (construct_hull reads this dict
		# raw — no MODULE_COST_ZONE_BASE, no TIER_ALLOY_BY_ZONE, no research mult),
		# so these are FINAL values, not authored-then-multiplied ones.
		"cost": {"credits": 270000, "WreckforgedAlloy": 15, "Steel": 250, "Ti": 120},
		"slots": ["weapon", "weapon", "weapon", "shield", "shield", "shield", "armor", "armor", "engine", "battery", "battery", "battery", "sensor", "sensor"], # 14
		"research_req": "zone_4_access",
		"visual": "res://assets/ships/4.png",
		"tier": 4
	},
	"battlecruiser_hull": {
		"name": "Battlecruiser",
		"stats": {"hp": 1874, "energy_capacity": 570},
		# v142d: QuantumCore 25 removed — craft_quantum_core is level_req 70 and needs
		# VoidCrystal, a ZONE 7 material, for a TIER 5 hull. Same unbuildable-on-unlock
		# shape as cruiser_hull's AdvCircuit, one zone further and worse. Tier-N hull
		# now keys on the zone-(N-1) alloy, matching cruiser_hull. Hull costs bypass
		# all scaling layers, so these are final values.
		"cost": {"credits": 810000, "RimeAlloy": 15, "Superalloy": 300, "Ti": 200},
		"slots": ["weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "armor", "armor", "engine", "battery", "battery", "battery", "battery", "sensor", "sensor"], # 16
		"research_req": "zone_5_access",
		"visual": "res://assets/ships/5.png",
		"tier": 5
	},
	"capital_hull": {
		"name": "Capital Ship",
		"stats": {"hp": 4124, "energy_capacity": 1255},
		"cost": {"credits": 2430000, "AdvCircuit": 1000, "VoidArtifact": 50},
		"slots": ["weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "armor", "armor", "armor", "engine", "engine", "battery", "battery", "battery", "battery", "sensor", "sensor"], # 18
		"research_req": "zone_6_access",
		"visual": "res://assets/ships/5.png",
		"tier": 6
	},
	"carrier_hull": {
		"name": "Carrier",
		"stats": {"hp": 9073, "energy_capacity": 2760},
		"cost": {"credits": 7290000, "ExoticMatter": 100},
		"slots": ["weapon", "weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "shield", "armor", "armor", "armor", "engine", "engine", "battery", "battery", "battery", "battery", "sensor", "sensor"], # 20
		"research_req": "zone_7_access",
		"visual": "res://assets/ships/5.png",
		"tier": 7
	},
	"dreadnought_hull": {
		"name": "Dreadnought",
		"stats": {"hp": 19960, "energy_capacity": 6075},
		"cost": {"credits": 21870000, "ExoticMatter": 200},
		"slots": ["weapon", "weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "shield", "armor", "armor", "armor", "engine", "engine", "battery", "battery", "battery", "battery", "battery", "sensor", "sensor", "sensor"], # 22
		"research_req": "zone_8_access",
		"visual": "res://assets/ships/5.png",
		"tier": 8
	},
	"titan_hull": {
		"name": "Titan",
		"stats": {"hp": 43913, "energy_capacity": 13365},
		"cost": {"credits": 65610000, "Neutronium": 500},
		"slots": ["weapon", "weapon", "weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "shield", "armor", "armor", "armor", "armor", "engine", "engine", "battery", "battery", "battery", "battery", "battery", "sensor", "sensor", "sensor"], # 24
		"research_req": "zone_9_access",
		"visual": "res://assets/ships/5.png",
		"tier": 9
	},
	"leviathan_hull": {
		"name": "Leviathan",
		"stats": {"hp": 96609, "energy_capacity": 29400},
		"cost": {"credits": 196830000, "PrimordialShard": 1000},
		"slots": ["weapon", "weapon", "weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "shield", "shield", "armor", "armor", "armor", "armor", "engine", "engine", "battery", "battery", "battery", "battery", "battery", "battery", "sensor", "sensor", "sensor"], # 26
		"research_req": "zone_10_access",
		"visual": "res://assets/ships/5.png",
		"tier": 10
	}
}

func get_ship_name() -> String:
	if active_hull in hulls:
		return hulls[active_hull].get("name", "Unknown Ship")
	return "No Ship"

var modules: Dictionary = {
	# ═══════════════════════════════════════════════════════════════
	# v80.1: Formula-Driven Modules — 10 Zones × 5 Types = 50 Base
	# Kinetic ATK = floor(8 × 2.2^(N-1))
	# Energy ATK  = floor(10 × 2.2^(N-1))
	# Missile ATK = floor(18 × 2.2^(N-1)), interval 4.0s
	# Shield HP   = floor(40 × 2.2^(N-1)), regen = floor(HP × 0.05)
	# Armor DEF   = floor(5 × 2.2^(N-1)), HP bonus = floor(20 × 2.2^(N-1))
	# ═══════════════════════════════════════════════════════════════

	# ── CRYO WEAPON TIER — the 4th damage type, unlocked by the first Warp. ──
	# Exotic-Matter self-charging (no ammo). The only damage that bites
	# Warp-Hardened (Z11+) hulls. v113: NO free starter weapon — ALL
	# Cryo weapons are CRAFTED via Shipyard craft_module (research: cryo_armaments)
	# during the post-warp re-climb. Z11 drops rarity-rolled cryo_lance upgrades.
	# All Cryo weapons use power_tier to decouple draw from zone 11.
	# v113: the free Cryo Shard Pistol was CUT — Warping no longer hands out a
	# (useless ~Z1-power) weapon. v113: collapsed to ONE craftable Cryo weapon, the
	# Cryo Lance below (RARE entry, Cryo Catalyst + research) — Z11 drops it
	# rarity-rolled and the boss a guaranteed one; a LEGENDARY roll (with affixes)
	# is the real Warden-killer, same craft-then-farm loop as every zone.
	"cryo_lance": {
		"name": "Cryo Lance",
		"slot_type": "weapon",
		"rarity": Rarity.RARE,
		# ~Z10 power level. Endgame Cryo craft — the weapon that makes Z11
		# beatable. 3× equipped → ~19 min Threshold Warden kill (first clear).
		# Z11 drops rarity-rolled copies that can exceed this base via affixes.
		# v137 (NG+ P5 tune): atk_cryo 4000→10000. The Z11 Threshold Warden AND
		# the Z12 Rift Warden were both tuned against "Cryo-Lance 10K atk_cryo"
		# (see z11_boss_threshold_warden comment) — the module shipped at 4000,
		# 2.5× under spec, making Z11 secretly harder than its ~19-min design and
		# Z12 phase-1 an unwinnable slog. Restoring 10K repairs both.
		"stats": {"atk_cryo": 10000, "atk_interval": 2.0},
		"cost": {"credits": 2000000, "ExoticMatter": 15, "CryoCatalyst": 12, "Superalloy": 50, "FocusingCrystal": 20},
		"desc": "Exotic-Condensate cryo lance. Self-charging, no ammo. The only thing that breaches Warp-Hardened hulls - farm The Threshold for legendary-grade rolls.",
		"zone": 11,
		"power_tier": 8,
		"cryo": true,
		"research_req": "cryo_armaments"
	},

	# ── CORROSION WEAPON (NG+ WT2 / Z12) — the 2nd exotic element. ──
	# v113 (NG+ P3): same exotic channel as Cryo (atk_cryo, self-charging/no-ammo),
	# but stats.exotic_element = "corrosion" tags it so the multi-phase gate credits
	# it ONLY against Corrosion phases. A Cryo loadout does ×0.15 on the Rift
	# Warden's Corrosion phase → you swap to a Corrosion preset. Guaranteed drop
	# from the Rift Warden's first clear; craftable thereafter (corrosion_armaments).
	# NOTE: UI still tints it Cryo-ice until per-element weapon coloring ships (P3b).
	"corrosion_blaster": {
		"name": "Corrosion Blaster",
		"slot_type": "weapon",
		"rarity": Rarity.LEGENDARY,
		"stats": {"atk_cryo": 12000, "atk_interval": 2.0, "exotic_element": "corrosion"},
		"cost": {"credits": 8000000, "ExoticMatter": 30, "CryoCatalyst": 20, "Superalloy": 120, "ChronoCore": 8, "VoidCrystal": 15, "FocusingCrystal": 40},
		"desc": "Acid-plasma projector. Etches through Corrosion-hardened hulls where cryogenic fire just glazes the surface.",
		"zone": 12,
		"power_tier": 8,
		"research_req": "corrosion_armaments"
	},

	# ── THRESHOLD RELIC (NG+ master key) — the Rift Warden's drop. ──
	# v113 (NG+ P2): dedicated Relic slot (slot_type "relic", NOT a hull slot).
	# While equipped IN its keyed zone, incoming damage is slashed to ~8% so the
	# gate boss becomes survivable → idle-farmable (the "active clear once, then
	# farm" payoff). Empty cost = not craftable; only the boss drops it. Persists
	# across Warp. relic_reduction is P5-tunable.
	"rift_relic": {
		"name": "Threshold Relic — Rift",
		"slot_type": "relic",
		"rarity": Rarity.LEGENDARY,
		"unique": true,
		"stats": {},
		"relic_zone": "the_rift",
		"relic_reduction": 0.92,
		"relic_for": "z12_boss_rift_warden",
		"cost": {},
		"desc": "A master key wrenched from the Rift Warden's core. Equipped, the Rift's corrosive fury barely scratches your hull — clear the gate once, then farm it at will.",
		"zone": 12
	},

	# ── ZONE 1: Lunar Orbit ──
	"z1_kinetic": {
		"name": "Mass Driver Mk.I",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 8, "energy_load": 5, "atk_interval": 2.0},
		"cost": {"credits": 2000, "Fe": 30},
		"desc": "Magnetic projectile cannon. Reliable hull damage.",
		"zone": 1
	},
	"z1_energy": {
		"name": "Pulse Laser Mk.I",
		"slot_type": "weapon",
		"stats": {"atk_energy": 10, "energy_load": 8, "atk_interval": 2.0},
		"cost": {"credits": 2000, "Si": 30},
		"desc": "Fast-firing energy beam. Strong vs shields.",
		"zone": 1
	},
	"z1_missile": {
		"name": "Micro-Missile Launcher",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 18, "energy_load": 10, "atk_interval": 4.0},
		"cost": {"credits": 2500, "Fe": 20, "Cu": 10},
		"desc": "Explosive payload. High armor penetration.",
		"zone": 1
	},
	"z1_shield": {
		"name": "Basic Shield",
		"slot_type": "shield",
		"stats": {"max_shield": 40, "shield_regen": 2},
		"cost": {"credits": 1500, "Si": 20},
		"desc": "Entry-level energy barrier.",
		"zone": 1
	},
	"z1_armor": {
		"name": "Iron Plate",
		"slot_type": "armor",
		"stats": {"def": 5, "hp": 20},
		"cost": {"credits": 1500, "Fe": 25},
		"desc": "Basic hull plating. Reduces incoming damage.",
		"zone": 1
	},

	# ── ZONE 2: Asteroid Belt ──
	"z2_kinetic": {
		"name": "Gauss Rifle",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 18, "energy_load": 10, "atk_interval": 2.0},
		"cost": {"credits": 4400, "Fe": 60, "Cu": 20},
		"desc": "Electromagnetic accelerator. Armor-piercing.",
		"zone": 2, "research_req": "zone_2_access"
	},
	"z2_energy": {
		"name": "Plasma Cutter",
		"slot_type": "weapon",
		"stats": {"atk_energy": 22, "energy_load": 15, "atk_interval": 2.0},
		"cost": {"credits": 4400, "Si": 60, "Cu": 20},
		"desc": "Focused plasma stream. Melts shields.",
		"zone": 2, "research_req": "zone_2_access"
	},
	"z2_missile": {
		"name": "Concussion Missile",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 40, "energy_load": 18, "atk_interval": 4.0},
		"cost": {"credits": 5500, "Fe": 40, "C": 30, "Hydraulics": 2},
		"desc": "Blast warhead. Devastating hull damage.",
		"zone": 2, "research_req": "zone_2_access"
	},
	"z2_shield": {
		"name": "Deflector Shield",
		"slot_type": "shield",
		"stats": {"max_shield": 88, "shield_regen": 4},
		"cost": {"credits": 3300, "Cu": 40, "Si": 20},
		"desc": "Improved barrier with regen coils.",
		"zone": 2, "research_req": "zone_2_access"
	},
	"z2_armor": {
		"name": "Carbon Fiber Plate",
		"slot_type": "armor",
		"stats": {"def": 11, "hp": 44},
		# v139c band surgery: m029 (craft ONE of these) measured 1.36h active —
		# the plating+kiln chain overshot the Z2-armor teach. 3 -> 2 plating, C 30 -> 20.
		"cost": {"credits": 3300, "C": 20, "Fe": 20, "ReinforcedPlating": 2},
		"desc": "Lightweight composite armor.",
		"zone": 2, "research_req": "zone_2_access"
	},

	# ── ZONE 3: Mars Debris ──
	"z3_kinetic": {
		"name": "Autocannon",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 39, "energy_load": 18, "atk_interval": 2.0},
		"cost": {"credits": 9680, "Steel": 40, "Ti": 15},
		"desc": "Rapid-fire ballistic weapon.",
		"zone": 3, "research_req": "zone_3_access"
	},
	"z3_energy": {
		"name": "Cryo Beam",
		"slot_type": "weapon",
		"stats": {"atk_energy": 48, "energy_load": 25, "atk_interval": 2.0},
		"cost": {"credits": 9680, "Si": 100, "Ti": 15},
		"desc": "Helium-cooled beam. Extreme shield damage.",
		"zone": 3, "research_req": "zone_3_access"
	},
	"z3_missile": {
		"name": "Heavy Torpedo",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 87, "energy_load": 30, "atk_interval": 4.0},
		"cost": {"credits": 12100, "Steel": 60, "C": 40, "Hydraulics": 3},
		"desc": "Armor-busting ordnance.",
		"zone": 3, "research_req": "zone_3_access"
	},
	"z3_shield": {
		"name": "Hardened Shield",
		"slot_type": "shield",
		"stats": {"max_shield": 194, "shield_regen": 9},
		"cost": {"credits": 7260, "Ti": 25, "Circuit": 10},
		"desc": "Military-grade energy barrier.",
		"zone": 3, "research_req": "zone_3_access"
	},
	"z3_armor": {
		"name": "Composite Plate",
		"slot_type": "armor",
		"stats": {"def": 24, "hp": 97},
		"cost": {"credits": 7260, "Steel": 30, "Ti": 10, "ReinforcedPlating": 5},
		"desc": "Layered ceramic-metal composite.",
		"zone": 3, "research_req": "zone_3_access"
	},

	# ── ZONE 4: Cryofield ──
	"z4_kinetic": {
		"name": "Railgun Mk.II",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 86, "energy_load": 30, "atk_interval": 2.0},
		"cost": {"credits": 21296, "Steel": 80, "AdvCircuit": 9},
		"desc": "High-velocity slug launcher.",
		"zone": 4, "research_req": "zone_4_access"
	},
	"z4_energy": {
		"name": "Ion Lance",
		"slot_type": "weapon",
		"stats": {"atk_energy": 106, "energy_load": 40, "atk_interval": 2.0},
		"cost": {"credits": 21296, "Ti": 60, "AdvCircuit": 9, "FocusingCrystal": 2},
		"desc": "Concentrated ion stream.",
		"zone": 4, "research_req": "zone_4_access"
	},
	"z4_missile": {
		"name": "Cluster Warhead",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 192, "energy_load": 45, "atk_interval": 4.0},
		"cost": {"credits": 26620, "Steel": 100, "Chip": 18, "Hydraulics": 5},
		"desc": "Splits into sub-munitions on impact.",
		"zone": 4, "research_req": "zone_4_access"
	},
	"z4_shield": {
		"name": "Cryo Shield",
		"slot_type": "shield",
		"stats": {"max_shield": 426, "shield_regen": 21},
		"cost": {"credits": 15972, "Ti": 40, "AdvCircuit": 14},
		"desc": "Supercooled barrier matrix.",
		"zone": 4, "research_req": "zone_4_access"
	},
	"z4_armor": {
		"name": "Stainless Armor",
		"slot_type": "armor",
		"stats": {"def": 53, "hp": 213},
		"cost": {"credits": 15972, "Steel": 60, "Ti": 20, "GalvanizedSteel": 10, "ReinforcedPlating": 8},
		"desc": "Corrosion-resistant alloy plating.",
		"zone": 4, "research_req": "zone_4_access"
	},

	# ── ZONE 5: Xenon Territory ──
	"z5_kinetic": {
		"name": "Gauss Cannon",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 189, "energy_load": 50, "atk_interval": 2.0},
		"cost": {"credits": 46851, "Superalloy": 20, "QuantumCore": 2},
		"desc": "Capital-grade magnetic accelerator.",
		"zone": 5, "research_req": "zone_5_access"
	},
	"z5_energy": {
		"name": "Particle Beam",
		"slot_type": "weapon",
		"stats": {"atk_energy": 234, "energy_load": 60, "atk_interval": 2.0},
		"cost": {"credits": 46851, "Ti": 100, "QuantumCore": 2, "Au": 10, "FocusingCrystal": 3},
		"desc": "Accelerated particles strip shields instantly.",
		"zone": 5, "research_req": "zone_5_access"
	},
	"z5_missile": {
		"name": "Seeker Torpedo",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 422, "energy_load": 70, "atk_interval": 4.0},
		"cost": {"credits": 58564, "Superalloy": 30, "Chip": 20},
		"desc": "AI-guided ordnance. Never misses.",
		"zone": 5, "research_req": "zone_5_access"
	},
	"z5_shield": {
		"name": "Xenon Barrier",
		"slot_type": "shield",
		"stats": {"max_shield": 937, "shield_regen": 46},
		"cost": {"credits": 35138, "VoidArtifact": 5, "AdvCircuit": 20, "StainlessSteel": 8},
		"desc": "Reverse-engineered alien shielding.",
		"zone": 5, "research_req": "zone_5_access"
	},
	"z5_armor": {
		"name": "Superalloy Plate",
		"slot_type": "armor",
		"stats": {"def": 117, "hp": 469},
		"cost": {"credits": 35138, "Superalloy": 15, "Steel": 100, "StainlessSteel": 8},
		"desc": "Dense metamaterial hull plating.",
		"zone": 5, "research_req": "zone_5_access"
	},

	# ── ZONE 6: Sector Beta ──
	"z6_kinetic": {
		"name": "Siege Cannon",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 416, "energy_load": 80, "atk_interval": 2.0},
		"cost": {"credits": 103072, "Superalloy": 50, "AdvCircuit": 30},
		"desc": "Colony-siege grade ballistic weapon.",
		"zone": 6, "research_req": "zone_6_access"
	},
	"z6_energy": {
		"name": "Plasma Lancer",
		"slot_type": "weapon",
		"stats": {"atk_energy": 514, "energy_load": 90, "atk_interval": 2.0},
		"cost": {"credits": 103072, "QuantumCore": 5, "AdvCircuit": 30, "FocusingCrystal": 5},
		"desc": "Sustained plasma discharge.",
		"zone": 6, "research_req": "zone_6_access"
	},
	"z6_missile": {
		"name": "Antimatter Warhead",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 928, "energy_load": 100, "atk_interval": 4.0},
		"cost": {"credits": 128840, "Superalloy": 60, "QuantumCore": 5},
		"desc": "Annihilation-class ordnance.",
		"zone": 6, "research_req": "zone_6_access"
	},
	"z6_shield": {
		"name": "Reactive Barrier",
		"slot_type": "shield",
		"stats": {"max_shield": 2062, "shield_regen": 103},
		"cost": {"credits": 77304, "VoidArtifact": 15, "QuantumCore": 5},
		"desc": "Adapts to incoming damage patterns.",
		"zone": 6, "research_req": "zone_6_access"
	},
	"z6_armor": {
		"name": "Iridium Armor",
		"slot_type": "armor",
		"stats": {"def": 257, "hp": 1031},
		"cost": {"credits": 77304, "Ir": 10, "Superalloy": 40},
		"desc": "Ultra-dense rare earth plating.",
		"zone": 6, "research_req": "zone_6_access"
	},

	# ── ZONE 7: Sector Gamma ──
	"z7_kinetic": {
		"name": "Neutron Slugger",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 916, "energy_load": 120, "atk_interval": 2.0},
		"cost": {"credits": 226758, "ExoticMatter": 10, "Ir": 10, "IrWAlloy": 5, "AdvCircuit": 40},
		"desc": "Fires neutron-dense projectiles.",
		"zone": 7, "research_req": "zone_7_access"
	},
	"z7_energy": {
		"name": "Void Beam",
		"slot_type": "weapon",
		"stats": {"atk_energy": 1131, "energy_load": 140, "atk_interval": 2.0},
		"cost": {"credits": 226758, "ExoticMatter": 10, "VoidCrystal": 5, "AdvCircuit": 40, "FocusingCrystal": 8},
		"desc": "Drains energy from realspace.",
		"zone": 7, "research_req": "zone_7_access"
	},
	"z7_missile": {
		"name": "Singularity Bomb",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 2042, "energy_load": 160, "atk_interval": 4.0},
		"cost": {"credits": 283448, "ExoticMatter": 15, "QuantumCore": 10, "Chip": 55},
		"desc": "Creates micro-singularity on impact.",
		"zone": 7, "research_req": "zone_7_access"
	},
	"z7_shield": {
		"name": "Exotic Shield Matrix",
		"slot_type": "shield",
		"stats": {"max_shield": 4536, "shield_regen": 226},
		"cost": {"credits": 170069, "ExoticMatter": 8, "VoidCrystal": 5, "AdvCircuit": 35},
		"desc": "Exotic matter barrier. Near-impervious.",
		"zone": 7, "research_req": "zone_7_access"
	},
	"z7_armor": {
		"name": "Osmium Core Plate",
		"slot_type": "armor",
		"stats": {"def": 565, "hp": 2268},
		"cost": {"credits": 170069, "Os": 5, "ExoticMatter": 5},
		"desc": "Densest material known to science.",
		"zone": 7, "research_req": "zone_7_access"
	},

	# ── ZONE 8: Sector Delta ──
	"z8_kinetic": {
		"name": "Prismatic Railgun",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 2015, "energy_load": 180, "atk_interval": 2.0},
		"cost": {"credits": 498868, "VoidCrystal": 10, "StructuralLattice": 2, "NeutroniumPlate": 2, "Steel": 4500},
		"desc": "Crystal-focused kinetic lance.",
		"zone": 8, "research_req": "zone_8_access"
	},
	"z8_energy": {
		"name": "Prism Annihilator",
		"slot_type": "weapon",
		"stats": {"atk_energy": 2489, "energy_load": 200, "atk_interval": 2.0},
		"cost": {"credits": 498868, "VoidCrystal": 10, "ExoticMatter": 10, "StructuralLattice": 2, "Ti": 3500, "FocusingCrystal": 12},
		"desc": "Refracted energy cascade.",
		"zone": 8, "research_req": "zone_8_access"
	},
	"z8_missile": {
		"name": "Quantum Torpedo",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 4493, "energy_load": 240, "atk_interval": 4.0},
		"cost": {"credits": 623585, "QuantumCore": 20, "StructuralLattice": 3, "NeutroniumPlate": 3, "Steel": 5500},
		"desc": "Exists in superposition until detonation.",
		"zone": 8, "research_req": "zone_8_access"
	},
	"z8_shield": {
		"name": "Prismatic Barrier",
		"slot_type": "shield",
		"stats": {"max_shield": 9980, "shield_regen": 499},
		"cost": {"credits": 374151, "VoidCrystal": 8, "ExoticMatter": 10, "StructuralLattice": 1, "Ti": 3000},
		"desc": "Crystal lattice energy barrier.",
		"zone": 8, "research_req": "zone_8_access"
	},
	"z8_armor": {
		"name": "Diamond Core Plate",
		"slot_type": "armor",
		"stats": {"def": 1244, "hp": 4990},
		"cost": {"credits": 374151, "Diamond": 5, "VoidCrystal": 5, "StructuralLattice": 2, "NeutroniumPlate": 2, "Steel": 4000},
		"desc": "Carbon-lattice super-structure.",
		"zone": 8, "research_req": "zone_8_access"
	},

	# ── ZONE 9: Sector Zeta ──
	"z9_kinetic": {
		"name": "Pathogen Cannon",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 4432, "energy_load": 260, "atk_interval": 2.0},
		"cost": {"credits": 1097510, "BiohazardSample": 20, "BioReactorCore": 3, "Neutronium": 180, "Steel": 9000},
		"desc": "Bio-corrosive projectiles.",
		"zone": 9, "research_req": "zone_9_access"
	},
	"z9_energy": {
		"name": "Zero-Point Beam",
		"slot_type": "weapon",
		"stats": {"atk_energy": 5476, "energy_load": 300, "atk_interval": 2.0},
		"cost": {"credits": 1097510, "ChronoCore": 2, "BioReactorCore": 3, "Neutronium": 180, "Ti": 8000, "FocusingCrystal": 18},
		"desc": "Extracts energy from vacuum fluctuations.",
		"zone": 9, "research_req": "zone_9_access"
	},
	"z9_missile": {
		"name": "Biohazard Warhead",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 9885, "energy_load": 350, "atk_interval": 4.0},
		"cost": {"credits": 1371888, "BiohazardSample": 30, "BioReactorCore": 4, "Neutronium": 200, "Steel": 11000},
		"desc": "Viral payload. Corrodes all matter.",
		"zone": 9, "research_req": "zone_9_access"
	},
	"z9_shield": {
		"name": "Quarantine Barrier",
		"slot_type": "shield",
		"stats": {"max_shield": 21956, "shield_regen": 1097},
		"cost": {"credits": 823132, "PathogenCore": 5, "BioReactorCore": 2, "Neutronium": 150, "Ti": 7000},
		"desc": "Containment-grade barrier field.",
		"zone": 9, "research_req": "zone_9_access"
	},
	"z9_armor": {
		"name": "Neutronium Plate",
		"slot_type": "armor",
		"stats": {"def": 2737, "hp": 10978},
		"cost": {"credits": 823132, "Os": 5, "NeutroniumPlate": 4, "Neutronium": 180, "Steel": 9000},
		"desc": "Neutron-star density alloy.",
		"zone": 9, "research_req": "zone_9_access"
	},

	# ── ZONE 10: Sector Epsilon ──
	"z10_kinetic": {
		"name": "Omega Cannon",
		"slot_type": "weapon",
		"stats": {"atk_kinetic": 9751, "energy_load": 400, "atk_interval": 2.0},
		"cost": {"credits": 2414522, "PrimordialShard": 5, "PrimordialMatrix": 3, "OmegaComposite": 2, "Neutronium": 200, "Steel": 13000},
		"desc": "Final evolution of kinetic warfare.",
		"zone": 10, "research_req": "zone_10_access"
	},
	"z10_energy": {
		"name": "Chrono Disruptor",
		"slot_type": "weapon",
		"stats": {"atk_energy": 12047, "energy_load": 450, "atk_interval": 2.0},
		"cost": {"credits": 2414522, "ChronoCore": 5, "PrimordialMatrix": 3, "OmegaComposite": 2, "Neutronium": 200, "Ti": 11000, "FocusingCrystal": 25},
		"desc": "Tears through spacetime itself.",
		"zone": 10, "research_req": "zone_10_access"
	},
	"z10_missile": {
		"name": "Void Annihilator",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 21747, "energy_load": 500, "atk_interval": 4.0},
		"cost": {"credits": 3018153, "PrimordialShard": 8, "PrimordialMatrix": 4, "OmegaComposite": 3, "Neutronium": 220, "Steel": 15000},
		"desc": "Erases matter from existence.",
		"zone": 10, "research_req": "zone_10_access"
	},
	"z10_shield": {
		"name": "Void Aegis",
		"slot_type": "shield",
		"stats": {"max_shield": 48304, "shield_regen": 2415},
		"cost": {"credits": 1810891, "VoidEssence": 10, "PrimordialMatrix": 2, "OmegaComposite": 2, "Neutronium": 170, "Ti": 9000},
		"desc": "Reality-bending shield barrier.",
		"zone": 10, "research_req": "zone_10_access"
	},
	"z10_armor": {
		"name": "Primordial Bulkhead",
		"slot_type": "armor",
		"stats": {"def": 6022, "hp": 24152},
		"cost": {"credits": 1810891, "PrimordialShard": 3, "PrimordialMatrix": 3, "OmegaComposite": 2, "Neutronium": 200, "Steel": 13000},
		"desc": "Forged from primordial matter.",
		"zone": 10, "research_req": "zone_10_access"
	},

	# ── ENGINE SYSTEMS (10 Zones) ──
	"z1_engine": {
		"name": "Basic Thruster", "slot_type": "engine", "stats": {"eva": 4},
		"cost": {"credits": 1200, "Fe": 15}, "zone": 1
	},
	"z2_engine": {
		"name": "Plasma Drive", "slot_type": "engine", "stats": {"eva": 5},
		"cost": {"credits": 2800, "Cu": 30, "Si": 15}, "zone": 2, "research_req": "zone_2_access"
	},
	"z3_engine": {
		"name": "Ion Engine", "slot_type": "engine", "stats": {"eva": 6},
		"cost": {"credits": 6500, "Steel": 25, "Ti": 10, "Hydraulics": 2}, "zone": 3, "research_req": "zone_3_access"
	},
	"z4_engine": {
		"name": "Cryo-Pulse Drive", "slot_type": "engine", "stats": {"eva": 7},
		"cost": {"credits": 15000, "Ti": 50, "AdvCircuit": 5, "Hydraulics": 3}, "zone": 4, "research_req": "zone_4_access"
	},
	"z5_engine": {
		"name": "Superalloy Engine", "slot_type": "engine", "stats": {"eva": 9},
		"cost": {"credits": 35000, "Superalloy": 15, "Chip": 10, "Hydraulics": 5}, "zone": 5, "research_req": "zone_5_access"
	},
	"z6_engine": {
		"name": "Antimatter Engine", "slot_type": "engine", "stats": {"eva": 10},
		"cost": {"credits": 80000, "Superalloy": 40, "QuantumCore": 2, "Hydraulics": 8}, "zone": 6, "research_req": "zone_6_access"
	},
	"z7_engine": {
		"name": "Void Engine", "slot_type": "engine", "stats": {"eva": 11},
		"cost": {"credits": 180000, "ExoticMatter": 5, "Ir": 5}, "zone": 7, "research_req": "zone_7_access"
	},
	"z8_engine": {
		"name": "Quantum Drive", "slot_type": "engine", "stats": {"eva": 12},
		"cost": {"credits": 420000, "VoidCrystal": 10, "Os": 5}, "zone": 8, "research_req": "zone_8_access"
	},
	"z9_engine": {
		"name": "Temporal Drive", "slot_type": "engine", "stats": {"eva": 13},
		"cost": {"credits": 950000, "Neutronium": 5, "ChronoCore": 2}, "zone": 9, "research_req": "zone_9_access"
	},
	"z10_engine": {
		"name": "Leviathan Engine", "slot_type": "engine", "stats": {"eva": 15},
		"cost": {"credits": 2200000, "PrimordialShard": 2, "OmegaPlating": 5}, "zone": 10, "research_req": "zone_10_access"
	},

	# ── POWER SYSTEMS (10 Zones) ──
	"z1_battery": {
		"name": "Basic Battery", "slot_type": "battery", "stats": {"energy_capacity": 50},
		"cost": {"credits": 1000,"Fe":10}, "zone": 1
	},
	"z2_battery": {
		"name": "Improved Battery", "slot_type": "battery", "stats": {"energy_capacity": 110},
		"cost": {"credits": 2500, "Cu": 25, "Si": 10}, "zone": 2, "research_req": "zone_2_access"
	},
	"z3_battery": {
		"name": "Co-Li Battery", "slot_type": "battery", "stats": {"energy_capacity": 242},
		"cost": {"credits": 6000, "CoBattery": 3, "Mn": 8}, "zone": 3, "research_req": "zone_3_access"
	},
	"z4_battery": {
		"name": "Mg-Ion Cell", "slot_type": "battery", "stats": {"energy_capacity": 532},
		"cost": {"credits": 14000, "Mg": 30, "AdvCircuit": 5}, "zone": 4, "research_req": "zone_4_access"
	},
	"z5_battery": {
		"name": "Quantum Cell", "slot_type": "battery", "stats": {"energy_capacity": 1171},
		"cost": {"credits": 32000, "QuantumCore": 1, "Si": 100}, "zone": 5, "research_req": "zone_5_access"
	},
	"z6_battery": {
		"name": "Reactive Core", "slot_type": "battery", "stats": {"energy_capacity": 2577},
		"cost": {"credits": 75000, "ReactiveCore": 2, "AdvCircuit": 20}, "zone": 6, "research_req": "zone_6_access"
	},
	"z7_battery": {
		"name": "Exotic Matrix", "slot_type": "battery", "stats": {"energy_capacity": 5669},
		"cost": {"credits": 170000, "ExoticMatter": 5, "VoidCrystal": 5}, "zone": 7, "research_req": "zone_7_access"
	},
	"z8_battery": {
		"name": "Void Battery", "slot_type": "battery", "stats": {"energy_capacity": 12473},
		"cost": {"credits": 400000, "VoidCrystal": 15, "Os": 5}, "zone": 8, "research_req": "zone_8_access"
	},
	"z9_battery": {
		"name": "Neutronium Core", "slot_type": "battery", "stats": {"energy_capacity": 27440},
		"cost": {"credits": 900000, "Neutronium": 10, "Diamond": 2}, "zone": 9, "research_req": "zone_9_access"
	},
	"z10_battery": {
		"name": "Omega Battery", "slot_type": "battery", "stats": {"energy_capacity": 60369},
		"cost": {"credits": 2100000, "PrimordialShard": 5, "OmegaPlating": 5}, "zone": 10, "research_req": "zone_10_access"
	},

	# ── SENSOR SUITES (10 Zones) ──
	# v145 SENSOR IDENTITY. These 10 modules used to carry {"accuracy": 30..120} and
	# NOTHING else. With the accuracy axis deleted the slot would have become dead
	# weight that still draws CONSUMER_LOAD_BY_TIER off the battery budget, so the
	# stat is replaced rather than removed.
	#
	# WHAT THEY DO NOW: sensors are the FARM-RATE slot. Both stats already exist and
	# are already read by live combat code — AFFIX_DB assigned this slot its loot
	# identity back in v128, so this is the base-stat half of an identity the game
	# had already declared, not a new system.
	#   enemy_drop_mult  -> combat_manager.win_fight, scales ALL enemy loot quantity
	#                       (elements AND Liras).
	#   module_drop_mult -> combat_manager.get_effective_module_drop_chance.
	#
	# WHY NOT DAMAGE: the combat curve was just recalibrated (ZONE_BASELINE_v142.md).
	# Any atk/crit/interval stat here is flat power creep on top of it and would force
	# a re-sweep. Loot rate is orthogonal to time-to-kill — the z3_funnel numbers are
	# untouched by design, which is the whole point of picking this axis.
	#
	# THE DECISION IT CREATES: sensor slots are typed, so this is not sensor-vs-weapon.
	# It is a POWER-BUDGET decision. Batteries carry only ~25% headroom over a full
	# tier-matched consumer set, so at any battery tier the player chooses between
	# running tier-matched sensors and having the headroom to slot the next-tier
	# weapon/shield they just looted. Downshifting to a cheaper sensor tier is a real
	# middle option (a z5 sensor draws 60 energy vs a z10's 500). That is the Melvor
	# "gathering gear or combat gear" call, in this game's power-grid vocabulary.
	#
	# CURVE: linear, not the 1.34x/zone the damage stats use — these are percentages
	# and compound with affixes, gems and the Overseer's Command set. Per module:
	#   enemy_drop_mult  = 0.08 + 0.03*(tier-1)   ->  +8% .. +35%
	#   module_drop_mult = 0.20 + 0.05*(tier-1)   -> +20% .. +65%
	# Sensor slot counts are 1 (hull T1-T4), 2 (T5-T8), 3 (T9-T10), so a maxed
	# tier-matched endgame ship reaches +105% loot qty / +195% module find from the
	# base stats — roughly "double your farm rate for three slots and 1500 energy".
	# Deliberately NOT in BOOSTABLE_STATS/ZONE_SCALABLE_STATS, so a Unique-rarity
	# drop of the same sensor carries the same base rate plus its affixes only.
	"z1_sensor": {
		"name": "Lidar Array", "slot_type": "sensor",
		"stats": {"enemy_drop_mult": 0.08, "module_drop_mult": 0.20},
		"cost": {"credits": 1500, "Si": 20}, "zone": 1
	},
	"z2_sensor": {
		"name": "Optical Scanner", "slot_type": "sensor",
		"stats": {"enemy_drop_mult": 0.11, "module_drop_mult": 0.25},
		"cost": {"credits": 3500, "Si": 40, "Cu": 20, "AlWire": 2}, "zone": 2, "research_req": "zone_2_access"
	},
	"z3_sensor": {
		"name": "Deep Space Radar", "slot_type": "sensor",
		"stats": {"enemy_drop_mult": 0.14, "module_drop_mult": 0.30},
		"cost": {"credits": 8000, "Circuit": 15, "Ti": 10, "AlWire": 3}, "zone": 3, "research_req": "zone_3_access"
	},
	"z4_sensor": {
		"name": "Phased Array", "slot_type": "sensor",
		"stats": {"enemy_drop_mult": 0.17, "module_drop_mult": 0.35},
		"cost": {"credits": 18000, "AdvCircuit": 10, "Ti": 30, "Au": 5, "FocusingCrystal": 2}, "zone": 4, "research_req": "zone_4_access"
	},
	"z5_sensor": {
		"name": "AI Targeting", "slot_type": "sensor",
		"stats": {"enemy_drop_mult": 0.20, "module_drop_mult": 0.40},
		"cost": {"credits": 42000, "AICore": 1, "Chip": 15, "FocusingCrystal": 3}, "zone": 5, "research_req": "zone_5_access"
	},
	"z6_sensor": {
		"name": "Quantum Scanner", "slot_type": "sensor",
		"stats": {"enemy_drop_mult": 0.23, "module_drop_mult": 0.45},
		"cost": {"credits": 95000, "QuantumCore": 3, "AdvCircuit": 25, "FocusingCrystal": 5}, "zone": 6, "research_req": "zone_6_access"
	},
	"z7_sensor": {
		"name": "Exotic Lens", "slot_type": "sensor",
		"stats": {"enemy_drop_mult": 0.26, "module_drop_mult": 0.50},
		"cost": {"credits": 210000, "ExoticMatter": 5, "VoidCrystal": 5}, "zone": 7, "research_req": "zone_7_access"
	},
	"z8_sensor": {
		"name": "Omni-Scanner", "slot_type": "sensor",
		"stats": {"enemy_drop_mult": 0.29, "module_drop_mult": 0.55},
		"cost": {"credits": 480000, "VoidArtifact": 10, "Os": 5}, "zone": 8, "research_req": "zone_8_access"
	},
	"z9_sensor": {
		"name": "Temporal Tracker", "slot_type": "sensor",
		"stats": {"enemy_drop_mult": 0.32, "module_drop_mult": 0.60},
		"cost": {"credits": 1100000, "ChronoCore": 3, "Neutronium": 5}, "zone": 9, "research_req": "zone_9_access"
	},
	"z10_sensor": {
		"name": "Oracle Array", "slot_type": "sensor",
		"stats": {"enemy_drop_mult": 0.35, "module_drop_mult": 0.65},
		"cost": {"credits": 2500000, "PrimordialShard": 5, "OmegaPlating": 5}, "zone": 10, "research_req": "zone_10_access"
	},

	# ── MATRIX CORES (Sockets) ──
	"matrix_synthesis": {
		"name": "Matrix Synthesis", "slot_type": "gem", "stats": {},
		"cost": {"credits": 20000, "NavData": 10, "Res1": 25},
		"desc": "Synthesize a random Cracked Matrix Core.", "zone": 2, "research_req": "zone_2_access"
	},
	"cracked_crimson_core": {
		"name": "Fuse Stable Crimson", "slot_type": "gem_synth", "stats": {},
		"cost": {"credits": 50000, "CrackedCrimsonCore": 3},
		"desc": "Fuses 3 Cracked Crimson cores into 1 Stable version.", "zone": 3
	},
	"stable_crimson_core": {
		"name": "Fuse Pristine Crimson", "slot_type": "gem_synth", "stats": {},
		"cost": {"credits": 250000, "StableCrimsonCore": 3},
		"desc": "Fuses 3 Stable Crimson cores into 1 Pristine version.", "zone": 5
	},
	"cracked_cobalt_core": {
		"name": "Fuse Stable Cobalt", "slot_type": "gem_synth", "stats": {},
		"cost": {"credits": 50000, "CrackedCobaltCore": 3},
		"desc": "Fuses 3 Cracked Cobalt cores into 1 Stable version.", "zone": 3
	},
	"stable_cobalt_core": {
		"name": "Fuse Pristine Cobalt", "slot_type": "gem_synth", "stats": {},
		"cost": {"credits": 250000, "StableCobaltCore": 3},
		"desc": "Fuses 3 Stable Cobalt cores into 1 Pristine version.", "zone": 5
	},
	"cracked_topaz_core": {
		"name": "Fuse Stable Topaz", "slot_type": "gem_synth", "stats": {},
		"cost": {"credits": 50000, "CrackedTopazCore": 3},
		"desc": "Fuses 3 Cracked Topaz cores into 1 Stable version.", "zone": 3
	},
	"stable_topaz_core": {
		"name": "Fuse Pristine Topaz", "slot_type": "gem_synth", "stats": {},
		"cost": {"credits": 250000, "StableTopazCore": 3},
		"desc": "Fuses 3 Stable Topaz cores into 1 Pristine version.", "zone": 5
	},
	"cracked_amethyst_core": {
		"name": "Fuse Stable Amethyst", "slot_type": "gem_synth", "stats": {},
		"cost": {"credits": 50000, "CrackedAmethystCore": 3},
		"desc": "Fuses 3 Cracked Amethyst cores into 1 Stable version.", "zone": 3
	},
	"stable_amethyst_core": {
		"name": "Fuse Pristine Amethyst", "slot_type": "gem_synth", "stats": {},
		"cost": {"credits": 250000, "StableAmethystCore": 3},
		"desc": "Fuses 3 Stable Amethyst cores into 1 Pristine version.", "zone": 5
	},
	# v135a: RESONANT fuse recipes (3 Pristine -> 1 Resonant). Gated on the CMB_4
	# warp node via warp_req (id names the INPUT tier per the offset-by-one convention).
	"pristine_crimson_core": {
		"name": "Fuse Resonant Crimson", "slot_type": "gem_synth", "stats": {},
		"cost": {"credits": 1250000, "PristineCrimsonCore": 3},
		"desc": "Fuses 3 Pristine Crimson cores into 1 Resonant version.", "zone": 6, "warp_req": "CMB_4"
	},
	"pristine_cobalt_core": {
		"name": "Fuse Resonant Cobalt", "slot_type": "gem_synth", "stats": {},
		"cost": {"credits": 1250000, "PristineCobaltCore": 3},
		"desc": "Fuses 3 Pristine Cobalt cores into 1 Resonant version.", "zone": 6, "warp_req": "CMB_4"
	},
	"pristine_topaz_core": {
		"name": "Fuse Resonant Topaz", "slot_type": "gem_synth", "stats": {},
		"cost": {"credits": 1250000, "PristineTopazCore": 3},
		"desc": "Fuses 3 Pristine Topaz cores into 1 Resonant version.", "zone": 6, "warp_req": "CMB_4"
	},
	"pristine_amethyst_core": {
		"name": "Fuse Resonant Amethyst", "slot_type": "gem_synth", "stats": {},
		"cost": {"credits": 1250000, "PristineAmethystCore": 3},
		"desc": "Fuses 3 Pristine Amethyst cores into 1 Resonant version.", "zone": 6, "warp_req": "CMB_4"
	},

	# ═══════════════════════════════════════════════════════════════
	# v80.1: Unique Trinity Set Modules — 2.8x base stats per zone
	# 3 per zone boss (Weapon, Armor, Shield) = 30 total
	# All have: rarity=UNIQUE, 4 affixes, 3 matrix sockets
	# ═══════════════════════════════════════════════════════════════

	# v146: the Z1 "Architect's Regalia" pieces (z1_unique_weapon/_kinetic/_missile/
	# _armor/_shield) were DELETED — see the note on combat_manager.TRINITY_SET_BONUSES.
	# Zone 1 is the tutorial; the set's free +25% attack speed skipped Zone 2 entirely.
	# Existing owners are migrated in _migrate_remove_architects_regalia().

	# ── Z2: Monolith's Bedrock (+10% DEF, Reflect 5% dmg) ──
	"z2_unique_weapon": {
		"name": "Monolith's Shatter", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_kinetic": 28, "energy_load": 18, "atk_interval": 2.0},
		"cost": {}, "desc": "Crystalline projectile launcher.", "zone": 2,
		"set_id": "monoliths_bedrock", "is_unique": true
	},
	"z2_unique_energy": {
		"name": "Monolith's Lance", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_energy": 28, "energy_load": 18, "atk_interval": 2.0},
		"cost": {}, "desc": "Unique energy-channel armament.", "zone": 2,
		"set_id": "monoliths_bedrock", "is_unique": true
	},
	"z2_unique_missile": {
		"name": "Monolith's Salvo", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 56, "energy_load": 18, "atk_interval": 4.0},
		"cost": {}, "desc": "Unique missile-channel armament.", "zone": 2,
		"set_id": "monoliths_bedrock", "is_unique": true
	},
	"z2_unique_armor": {
		"name": "Monolith's Shell", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 17, "hp": 70},
		"cost": {}, "desc": "Silicate-hardened hull plating.", "zone": 2,
		"set_id": "monoliths_bedrock", "is_unique": true
	},
	"z2_unique_shield": {
		"name": "Monolith's Barrier", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 140, "shield_regen": 6},
		"cost": {}, "desc": "Stone-resonance energy barrier.", "zone": 2,
		"set_id": "monoliths_bedrock", "is_unique": true
	},

	# v86.0: Hazard Zone Counter Equipment
	"faraday_hull": {
		"name": "Faraday Hull", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 20, "hp": 80},
		"cost": {}, "desc": "EMP-shielded armor plating with integrated electromagnetic dampeners. Grants immunity to weapon jamming in the EMP Nexus.", "zone": 2,
		"is_unique": true, "special": "emp_immunity"
	},

	# ── Z3: Warmaster's Arsenal (+12% Crit Chance, +8% ATK) ──
	"z3_unique_weapon": {
		"name": "Warmaster's Railgun", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_kinetic": 62, "energy_load": 30, "atk_interval": 2.0},
		"cost": {}, "desc": "Mars-forged magnetic accelerator.", "zone": 3,
		"set_id": "warmasters_arsenal", "is_unique": true
	},
	"z3_unique_energy": {
		"name": "Warmaster's Lance", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_energy": 62, "energy_load": 30, "atk_interval": 2.0},
		"cost": {}, "desc": "Unique energy-channel armament.", "zone": 3,
		"set_id": "warmasters_arsenal", "is_unique": true
	},
	"z3_unique_missile": {
		"name": "Warmaster's Salvo", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 124, "energy_load": 30, "atk_interval": 4.0},
		"cost": {}, "desc": "Unique missile-channel armament.", "zone": 3,
		"set_id": "warmasters_arsenal", "is_unique": true
	},
	"z3_unique_armor": {
		"name": "Warmaster's Bulkhead", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 38, "hp": 155},
		"cost": {}, "desc": "Battle-scarred Martian alloy.", "zone": 3,
		"set_id": "warmasters_arsenal", "is_unique": true
	},
	"z3_unique_shield": {
		"name": "Warmaster's Aegis", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 310, "shield_regen": 14},
		"cost": {}, "desc": "Command-grade barrier matrix.", "zone": 3,
		"set_id": "warmasters_arsenal", "is_unique": true
	},

	# ── Z4: Overseer's Command (+10% Shield Regen, +50 Accuracy) ──
	"z4_unique_weapon": {
		"name": "Overseer's Lance", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_energy": 169, "energy_load": 50, "atk_interval": 2.0},
		"cost": {}, "desc": "Cryo-focused targeting lance.", "zone": 4,
		"set_id": "overseers_command", "is_unique": true
	},
	"z4_unique_kinetic": {
		"name": "Overseer's Driver", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_kinetic": 169, "energy_load": 50, "atk_interval": 2.0},
		"cost": {}, "desc": "Unique kinetic-channel armament.", "zone": 4,
		"set_id": "overseers_command", "is_unique": true
	},
	"z4_unique_missile": {
		"name": "Overseer's Salvo", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 338, "energy_load": 50, "atk_interval": 4.0},
		"cost": {}, "desc": "Unique missile-channel armament.", "zone": 4,
		"set_id": "overseers_command", "is_unique": true
	},
	"z4_unique_armor": {
		"name": "Overseer's Carapace", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 84, "hp": 340},
		"cost": {}, "desc": "Ice-tempered composite armor.", "zone": 4,
		"set_id": "overseers_command", "is_unique": true
	},
	"z4_unique_shield": {
		"name": "Overseer's Dome", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 681, "shield_regen": 33},
		"cost": {}, "desc": "Cryo-stabilized barrier dome.", "zone": 4,
		"set_id": "overseers_command", "is_unique": true
	},

	# ── Z5: Harbinger's Wrath (+15% Missile DMG, -10% Enemy DEF) ──
	"z5_unique_weapon": {
		"name": "Harbinger's Fury", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 675, "energy_load": 90, "atk_interval": 4.0},
		"cost": {}, "desc": "Xenon doomsday missile platform.", "zone": 5,
		"set_id": "harbingers_wrath", "is_unique": true
	},
	"z5_unique_kinetic": {
		"name": "Harbinger's Driver", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_kinetic": 338, "energy_load": 90, "atk_interval": 2.0},
		"cost": {}, "desc": "Unique kinetic-channel armament.", "zone": 5,
		"set_id": "harbingers_wrath", "is_unique": true
	},
	"z5_unique_energy": {
		"name": "Harbinger's Lance", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_energy": 338, "energy_load": 90, "atk_interval": 2.0},
		"cost": {}, "desc": "Unique energy-channel armament.", "zone": 5,
		"set_id": "harbingers_wrath", "is_unique": true
	},
	"z5_unique_armor": {
		"name": "Harbinger's Bastion", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 187, "hp": 750},
		"cost": {}, "desc": "Alien-alloy hull reinforcement.", "zone": 5,
		"set_id": "harbingers_wrath", "is_unique": true
	},
	"z5_unique_shield": {
		"name": "Harbinger's Veil", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 1499, "shield_regen": 73},
		"cost": {}, "desc": "Xenon phase-shift barrier.", "zone": 5,
		"set_id": "harbingers_wrath", "is_unique": true
	},

	# ── Z6: Colossus Dominion (+12% All DMG, +5% Evasion) ──
	"z6_unique_weapon": {
		"name": "Colossus Cannon", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_kinetic": 665, "energy_load": 120, "atk_interval": 2.0},
		"cost": {}, "desc": "Colony-siege superweapon.", "zone": 6,
		"set_id": "colossus_dominion", "is_unique": true
	},
	"z6_unique_energy": {
		"name": "Colossus Cannon Lance", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_energy": 665, "energy_load": 120, "atk_interval": 2.0},
		"cost": {}, "desc": "Unique energy-channel armament.", "zone": 6,
		"set_id": "colossus_dominion", "is_unique": true
	},
	"z6_unique_missile": {
		"name": "Colossus Cannon Salvo", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 1330, "energy_load": 120, "atk_interval": 4.0},
		"cost": {}, "desc": "Unique missile-channel armament.", "zone": 6,
		"set_id": "colossus_dominion", "is_unique": true
	},
	"z6_unique_armor": {
		"name": "Colossus Bulwark", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 411, "hp": 1649},
		"cost": {}, "desc": "Gamma-hardened ultra-plating.", "zone": 6,
		"set_id": "colossus_dominion", "is_unique": true
	},
	"z6_unique_shield": {
		"name": "Colossus Aegis", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 3299, "shield_regen": 164},
		"cost": {}, "desc": "Radiation-dampening barrier.", "zone": 6,
		"set_id": "colossus_dominion", "is_unique": true
	},

	# ── Z7: Sovereign's Prism (+300 DEF, +10% Energy DMG) ──
	"z7_unique_weapon": {
		"name": "Sovereign's Ray", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_energy": 1809, "energy_load": 180, "atk_interval": 2.0},
		"cost": {}, "desc": "Prismatic energy cascade.", "zone": 7,
		"set_id": "sovereigns_prism", "is_unique": true
	},
	"z7_unique_kinetic": {
		"name": "Sovereign's Driver", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_kinetic": 1809, "energy_load": 180, "atk_interval": 2.0},
		"cost": {}, "desc": "Unique kinetic-channel armament.", "zone": 7,
		"set_id": "sovereigns_prism", "is_unique": true
	},
	"z7_unique_missile": {
		"name": "Sovereign's Salvo", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 3618, "energy_load": 180, "atk_interval": 4.0},
		"cost": {}, "desc": "Unique missile-channel armament.", "zone": 7,
		"set_id": "sovereigns_prism", "is_unique": true
	},
	"z7_unique_armor": {
		"name": "Sovereign's Mantle", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 904, "hp": 3628},
		"cost": {}, "desc": "Exotic-matter woven hull.", "zone": 7,
		"set_id": "sovereigns_prism", "is_unique": true
	},
	"z7_unique_shield": {
		"name": "Sovereign's Corona", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 7257, "shield_regen": 361},
		"cost": {}, "desc": "Reality-bending shield aura.", "zone": 7,
		"set_id": "sovereigns_prism", "is_unique": true
	},

	# ── Z8: Warden's Quarantine (+20% Shield HP, +8% Crit) ──
	"z8_unique_weapon": {
		"name": "Warden's Scalpel", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_energy": 3982, "energy_load": 280, "atk_interval": 2.0},
		"cost": {}, "desc": "Crystal-focused annihilation beam.", "zone": 8,
		"set_id": "wardens_quarantine", "is_unique": true
	},
	"z8_unique_kinetic": {
		"name": "Warden's Driver", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_kinetic": 3982, "energy_load": 280, "atk_interval": 2.0},
		"cost": {}, "desc": "Unique kinetic-channel armament.", "zone": 8,
		"set_id": "wardens_quarantine", "is_unique": true
	},
	"z8_unique_missile": {
		"name": "Warden's Salvo", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 7964, "energy_load": 280, "atk_interval": 4.0},
		"cost": {}, "desc": "Unique missile-channel armament.", "zone": 8,
		"set_id": "wardens_quarantine", "is_unique": true
	},
	"z8_unique_armor": {
		"name": "Warden's Containment", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 1990, "hp": 7984},
		"cost": {}, "desc": "Diamond-lattice containment hull.", "zone": 8,
		"set_id": "wardens_quarantine", "is_unique": true
	},
	"z8_unique_shield": {
		"name": "Warden's Lockdown", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 15968, "shield_regen": 798},
		"cost": {}, "desc": "Prismatic containment barrier.", "zone": 8,
		"set_id": "wardens_quarantine", "is_unique": true
	},

	# ── Z9: Titan's Legacy (+15% All DMG, +500 DEF) ──
	"z9_unique_weapon": {
		"name": "Titan's Wrath", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_kinetic": 7091, "energy_load": 400, "atk_interval": 2.0},
		"cost": {}, "desc": "Neutronium-core mass driver.", "zone": 9,
		"set_id": "titans_legacy", "is_unique": true
	},
	"z9_unique_energy": {
		"name": "Titan's Lance", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_energy": 7091, "energy_load": 400, "atk_interval": 2.0},
		"cost": {}, "desc": "Unique energy-channel armament.", "zone": 9,
		"set_id": "titans_legacy", "is_unique": true
	},
	"z9_unique_missile": {
		"name": "Titan's Salvo", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 14182, "energy_load": 400, "atk_interval": 4.0},
		"cost": {}, "desc": "Unique missile-channel armament.", "zone": 9,
		"set_id": "titans_legacy", "is_unique": true
	},
	"z9_unique_armor": {
		"name": "Titan's Aegis", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 4379, "hp": 17564},
		"cost": {}, "desc": "Neutron-star density plating.", "zone": 9,
		"set_id": "titans_legacy", "is_unique": true
	},
	"z9_unique_shield": {
		"name": "Titan's Bulwark", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 35129, "shield_regen": 1755},
		"cost": {}, "desc": "Containment-grade mega-barrier.", "zone": 9,
		"set_id": "titans_legacy", "is_unique": true
	},

	# ── Z10: Leviathan's Crown (+20% All DMG, +1000 HP Regen/tick) ──
	"z10_unique_weapon": {
		"name": "Leviathan's Maw", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 34795, "energy_load": 600, "atk_interval": 4.0},
		"cost": {}, "desc": "Reality-ending void warhead.", "zone": 10,
		"set_id": "leviathans_crown", "is_unique": true
	},
	"z10_unique_kinetic": {
		"name": "Leviathan's Driver", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_kinetic": 17398, "energy_load": 600, "atk_interval": 2.0},
		"cost": {}, "desc": "Unique kinetic-channel armament.", "zone": 10,
		"set_id": "leviathans_crown", "is_unique": true
	},
	"z10_unique_energy": {
		"name": "Leviathan's Lance", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_energy": 17398, "energy_load": 600, "atk_interval": 2.0},
		"cost": {}, "desc": "Unique energy-channel armament.", "zone": 10,
		"set_id": "leviathans_crown", "is_unique": true
	},
	"z10_unique_armor": {
		"name": "Leviathan's Hide", "slot_type": "armor", "rarity": 4,
		"stats": {"def": 9635, "hp": 38643},
		"cost": {}, "desc": "Primordial matter hull.", "zone": 10,
		"set_id": "leviathans_crown", "is_unique": true
	},
	"z10_unique_shield": {
		"name": "Leviathan's Dominion", "slot_type": "shield", "rarity": 4,
		"stats": {"max_shield": 77286, "shield_regen": 3864},
		"cost": {}, "desc": "Void-sovereign barrier field.", "zone": 10,
		"set_id": "leviathans_crown", "is_unique": true
	}
}


# ─────────────────────────────────────────────────────────────────────────────
# v142 TIER-STEP REBASE (owner rule, 2026-07-25): the zone tier-gate.
#
#   "a maxed Zone-N set must NOT farm Zone N+1 e3/e4; a clean Common Zone N+1
#    set MUST" — an ORDERING on player power, so it lives or dies on:
#
#        tier step  >  rarity x affixes x matrix cores
#
# Measured (gear_power_audit, corrected): the gear ceiling stacks to 1.30-1.97x
# ABOVE a clean next-tier Common, i.e. old maxed gear out-damaged the tier meant
# to replace it — the gate ran BACKWARDS. Authored module stats stepped 2.2x per
# zone, which the Legendary roll (1.55x) plus affixes plus Resonant cores clears
# comfortably. Rather than gut itemization to fit under 2.2x (owner call), the
# STEP is raised so the ceiling fits under it with real margin.
#
# Applied as ONE scale factor over the authored literals (kept as-is so the
# hand-tuned per-zone shape survives). Enemy stats take the SAME factor in
# combat_manager, so in-zone difficulty is unchanged — only the CROSS-zone gear
# gap widens, which is the whole point.
#
# MIGRATION: custom module instances already stored in a save carry stats baked
# at the old scale and will read weak. Balance-iteration prototype — New Game
# for a clean read.
const TIER_STEP_OLD := 2.2
const TIER_STEP_NEW := 3.75
const REBASE_STATS := ["atk_kinetic", "atk_energy", "atk_explosive", "atk_cryo",
	"def", "max_shield", "hp_bonus", "hp", "shield_regen"]

static func tier_rebase(z: int) -> float:
	return pow(TIER_STEP_NEW / TIER_STEP_OLD, maxf(0.0, float(z) - 1.0))

func _apply_tier_rebase() -> void:
	# Modules: scale combat stats by their own zone/power_tier. energy_load is
	# EXCLUDED — the battery budget lives in its own CONSUMER/BATTERY tables and
	# must stay in lockstep with them (v110 battery-only energy).
	for mid in modules:
		var m: Dictionary = modules[mid]
		var z: int = int(m.get("zone", m.get("power_tier", 0)))
		if z <= 1:
			continue
		var f: float = tier_rebase(z)
		var st: Dictionary = m.get("stats", {})
		for k in REBASE_STATS:
			if st.has(k) and typeof(st[k]) in [TYPE_INT, TYPE_FLOAT]:
				st[k] = int(round(float(st[k]) * f)) if typeof(st[k]) == TYPE_INT else float(st[k]) * f
	# Hulls: the chassis HP pool steps with the gear it carries, or the hull
	# becomes the dominant (unscaled) EHP term and flattens the gate.
	for hid in hulls:
		var h: Dictionary = hulls[hid]
		var t: int = int(h.get("tier", 0))
		if t <= 1:
			continue
		var hf: float = tier_rebase(t)
		var hs: Dictionary = h.get("stats", {})
		if hs.has("hp"):
			hs["hp"] = int(round(float(hs["hp"]) * hf))

func _init():
	_apply_tier_rebase()
	_scale_mid_late_module_item_costs()
	recalc_stats()
	_migrate_module_entries_from_resources()

func _scale_mid_late_module_item_costs() -> void:
	if _module_item_costs_scaled:
		return
	_module_item_costs_scaled = true
	
	for module_id in modules:
		var m_data = modules[module_id]
		if m_data.get("is_custom", false):
			continue
		var slot_type = str(m_data.get("slot_type", ""))
		if slot_type == "gem" or slot_type == "gem_synth":
			continue
		if not m_data.has("cost"):
			continue
		
		# v142c: zone-keyed curve (see MODULE_COST_ZONE_BASE). Replaces the
		# material-list-keyed _get_module_cost_stage, which is now unused.
		var z: int = int(m_data.get("zone", m_data.get("power_tier", 0)))
		if z <= MODULE_COST_FREE_ZONES:
			continue

		var mult: float = pow(MODULE_COST_ZONE_BASE, float(z - MODULE_COST_FREE_ZONES))
		var cost_dict: Dictionary = m_data["cost"]
		for res in cost_dict:
			if res == "credits":
				continue
			var qty = int(cost_dict[res])
			if qty <= 0:
				continue
			cost_dict[res] = _scale_item_requirement(qty, mult)
		
		m_data["cost"] = cost_dict
		modules[module_id] = m_data

func _get_module_cost_stage(m_data: Dictionary) -> int:
	var req = str(m_data.get("research_req", ""))
	var cost: Dictionary = m_data.get("cost", {})
	
	for res in cost:
		if res in LATE_MODULE_ITEMS:
			return 2
	if req in LATE_MODULE_REQ_TECHS:
		return 2
	
	for res in cost:
		if res in MID_MODULE_ITEMS:
			return 1
	if req == "":
		return 0
	if req in EARLY_MODULE_REQ_TECHS:
		return 0
	return 1

func _scale_item_requirement(base_qty: int, multiplier: float) -> int:
	var scaled = int(ceil(float(base_qty) * multiplier))
	if scaled <= base_qty:
		return base_qty + 1
	return scaled

func _migrate_atk_interval_caps() -> void:
	# Retroactive migration: older saves contain weapon drops where atk_interval
	# was rolled below the new -40% reduction floor (formula coefficient lowered
	# from 0.4 → 0.15). Clamp those values to base × 0.6 so cross-tier outliers
	# get rebalanced. Damage stats are untouched.
	var clamped := 0
	for mid in custom_modules.keys():
		var m: Dictionary = custom_modules[mid]
		var stats: Dictionary = m.get("stats", {})
		if not stats.has("atk_interval"):
			continue
		var base_id: String = m.get("base_module", "")
		if base_id == "" or not base_id in modules:
			continue
		var base_interval: float = float(modules[base_id].get("stats", {}).get("atk_interval", 0.0))
		if base_interval <= 0.0:
			continue
		var floor_val: float = base_interval * 0.6
		var cur: float = float(stats["atk_interval"])
		if cur < floor_val:
			var new_val := snappedf(floor_val, 0.01)
			stats["atk_interval"] = new_val
			# The modules dict is a live mirror that contains custom_modules — keep them in sync.
			if mid in modules:
				modules[mid]["stats"]["atk_interval"] = new_val
			clamped += 1
	if clamped > 0:
		print("[Migration] Clamped atk_interval on %d existing custom module(s) to new -40%% floor." % clamped)

func _migrate_module_entries_from_resources() -> void:
	if not GameState or not GameState.resources:
		return
	
	var moved_any = false
	var symbols_to_remove: Array = []
	for symbol in GameState.resources.elements.keys():
		if symbol in modules:
			var qty = int(GameState.resources.elements.get(symbol, 0))
			if qty > 0:
				module_inventory[symbol] = module_inventory.get(symbol, 0) + qty
				symbols_to_remove.append(symbol)
				moved_any = true
	
	for symbol in symbols_to_remove:
		var qty_left = GameState.resources.get_element_amount(symbol)
		if qty_left > 0:
			GameState.resources.remove_element(symbol, qty_left)
	
	if moved_any:
		new_drops_alert = true
		inventory_updated.emit()

## v109: Grant a fixed module straight into inventory (no cost, no rarity roll).
## Used by the first-Warp Cryo grant and Z11+ Cryo drops.
func grant_module(mid: String, qty: int = 1) -> void:
	if not mid in modules:
		return
	module_inventory[mid] = module_inventory.get(mid, 0) + qty
	unseen_modules[mid] = true
	new_drops_alert = true
	inventory_updated.emit()

func construct_hull(hull_id: String) -> bool:
	if not hull_id in hulls: return false
	
	var hull_data = hulls[hull_id]
	if hull_data.get("research_req"):
		if not GameState.research_manager.is_tech_unlocked(hull_data["research_req"]):
			return false
	
	# Check Costs
	for res in hull_data["cost"]:
		var qty = hull_data["cost"][res]
		if res == "credits":
			if GameState.resources.get_currency("credits") < qty: return false
		else:
			if GameState.resources.get_element_amount(res) < qty: return false
			
	# Consume
	for res in hull_data["cost"]:
		var qty = hull_data["cost"][res]
		if res == "credits":
			GameState.resources.remove_currency("credits", qty)
		else:
			GameState.resources.remove_element(res, qty)
			
	# Snapshot the current loadout (in slot order) so it can be carried over
	# to the new hull. unequip_all() returns these to module_inventory.
	var _carry: Array = []
	var _old_idxs: Array = loadout.keys()
	_old_idxs.sort()
	for _i in _old_idxs:
		if loadout[_i]:
			_carry.append(loadout[_i])

	# Unequip All
	unequip_all()

	active_hull = hull_id
	loadout = {}
	# v135a: iterate EFFECTIVE slots so the CMB_3 aux slot is pre-allocated on the
	# new hull — a base-size loop would strip the aux entry on every hull switch.
	for i in range(get_effective_slots().size()):
		loadout[i] = null

	# Auto-transfer: re-equip each previous module into the first matching
	# free slot on the new hull. equip_module() enforces type / energy /
	# uniqueness, so anything that no longer fits simply stays in inventory
	# (never lost) instead of forcing a full manual re-equip.
	#
	# Batteries FIRST: capacity is battery-derived (hulls supply 0) and the
	# step-wise equip checks power per module — placing a consumer before any
	# battery tests it against 0 capacity, which rejects it (and used to spam
	# the power warning once per consumer), silently dropping modules that
	# actually fit. Equip silently: internal migration, the ship-status
	# indicator reports the final power state once.
	var _carry_ordered: Array = []
	for _mid in _carry:
		if _mid in modules and modules[_mid].get("slot_type", "") == "battery":
			_carry_ordered.append(_mid)
	for _mid in _carry:
		if not (_mid in modules and modules[_mid].get("slot_type", "") == "battery"):
			_carry_ordered.append(_mid)
	for _mid in _carry_ordered:
		if not _mid in modules:
			continue
		var _mtype = modules[_mid].get("slot_type", "")
		var _placed := false
		for _s in range(hull_data["slots"].size()):
			if loadout.get(_s) == null and hull_data["slots"][_s] == _mtype:
				if module_inventory.get(_mid, 0) > 0 and equip_module(_s, _mid, true):
					_placed = true
					break
		# v135a: last-resort landing in the CMB_3 aux slot (accepts any type) so a
		# carried module isn't stranded in inventory when its base slots are full.
		if not _placed:
			var _aux := get_aux_slot_index()
			if _aux >= 0 and loadout.get(_aux) == null and module_inventory.get(_mid, 0) > 0:
				equip_module(_aux, _mid, true)

	# v136: the live re-equip above migrated the ACTIVE build slot (equip_module keeps it
	# in sync via _autosave_active_preset). Carry the OTHER saved build slots over too —
	# remap each onto the new hull's slot layout so they don't load stripped. See
	# _migrate_presets_to_current_hull.
	_migrate_presets_to_current_hull()

	# Recalculate to get new max_hp
	recalc_stats()
	current_hp = max_hp # Explicitly force full health for the new hull
	
	hull_constructed.emit(hull_id) # Audit v11.0: Signal for missions
	return true

# v136: after a hull switch, re-map every SAVED build slot (loadout preset) onto the NEW
# hull's slot layout. construct_hull already migrates the ACTIVE build via the live
# re-equip, but the other presets are stored as raw {slot_index: module} maps — and slot
# TYPES reorder across hulls (corvette slot 3 = armor, frigate slot 3 = shield). Loading a
# stale preset on the new hull would land its armor/engine/battery/sensor on wrong-typed
# slots, silently skip them, and bring the ship up stripped — the "presets emptied
# themselves" bug. The active slot is skipped (kept in sync by equip_module's autosave);
# empty slots have nothing to carry.
func _migrate_presets_to_current_hull() -> void:
	for _pidx in loadout_presets.keys():
		if _pidx == active_preset_idx:
			continue
		if _preset_has_no_modules(loadout_presets[_pidx]):
			continue
		loadout_presets[_pidx] = _remap_preset_to_current_hull(loadout_presets[_pidx])

# Rebuild one preset's loadout/ammo onto the CURRENT hull, matching each module to the
# first free slot of its TYPE (batteries first, then aux last-resort — mirrors
# construct_hull's live transfer). Remapping by type (not by old index) also self-heals a
# preset already stale from an earlier upgrade. Pure data op: never touches inventory or
# live equips. A module whose type no longer has a free slot is dropped from the preset —
# it stays owned in inventory, exactly as the live transfer leaves modules that don't fit.
func _remap_preset_to_current_hull(preset: Dictionary) -> Dictionary:
	var hull_slots: Array = get_effective_slots()
	var aux_idx: int = get_aux_slot_index()
	var old_load: Dictionary = preset.get("loadout", {})

	# Source modules, batteries first then ascending old slot — capacity before consumers,
	# same order construct_hull uses so a preset maps to the slots the active build would.
	var batteries: Array = []
	var others: Array = []
	for s in old_load.keys():
		var mid = old_load[s]
		if mid == null or mid == "" or not (mid in modules):
			continue
		if modules[mid].get("slot_type", "") == "battery":
			batteries.append(s)
		else:
			others.append(s)
	batteries.sort()
	others.sort()
	var src_slots: Array = batteries.duplicate()
	src_slots.append_array(others)

	# Fresh loadout with a null in every slot of the new hull.
	var new_load: Dictionary = {}
	for i in range(hull_slots.size()):
		new_load[i] = null

	var slot_remap: Dictionary = {}   # old slot -> new slot, so ammo can follow its weapon
	for old_slot in src_slots:
		var mid = old_load[old_slot]
		var mtype: String = modules[mid].get("slot_type", "")
		var placed := false
		for ns in range(hull_slots.size()):
			if new_load[ns] == null and str(hull_slots[ns]) == mtype:
				new_load[ns] = mid
				slot_remap[old_slot] = ns
				placed = true
				break
		if not placed and aux_idx >= 0 and new_load.get(aux_idx) == null:
			new_load[aux_idx] = mid
			slot_remap[old_slot] = aux_idx

	# Ammo follows each weapon to its new slot index.
	var old_ammo: Dictionary = preset.get("ammo_loadout", {})
	var new_ammo: Dictionary = {}
	for old_slot in old_ammo.keys():
		if old_slot in slot_remap:
			new_ammo[slot_remap[old_slot]] = old_ammo[old_slot]

	return {
		"name": preset.get("name", ""),
		"loadout": new_load,
		"ammo_loadout": new_ammo,
		"consumable_hull": preset.get("consumable_hull", ""),
		"consumable_shield": preset.get("consumable_shield", ""),
	}

func unequip_all():
	for idx in loadout:
		var mid = loadout[idx]
		if mid:
			module_inventory[mid] = module_inventory.get(mid, 0) + 1
	loadout = {}

func craft_module(module_id: String) -> bool:
	if not module_id in modules: return false
	
	var mod_data = modules[module_id]
	if mod_data.get("is_custom", false):
		print("Craft Fail: Dropped modules cannot be crafted.")
		return false
	if mod_data.get("research_req"):
		if not GameState.research_manager.is_tech_unlocked(mod_data["research_req"]):
			return false
	# v135a: warp-node gate (e.g. CMB_4 unlocks the Resonant fuse recipes). MUST run
	# before cost consumption below, else a blocked craft silently eats the inputs.
	if mod_data.get("warp_req"):
		if not (GameState.warp_manager and GameState.warp_manager.is_node_purchased(mod_data["warp_req"])):
			return false

	# v114: effective cost includes the zone tier-gate alloy when the gate is on.
	var craft_cost = get_effective_module_cost(mod_data)
	# Check Cost
	for res in craft_cost:
		var qty = craft_cost[res]
		if res == "credits":
			if GameState.resources.get_currency("credits") < qty: return false
		else:
			if GameState.resources.get_element_amount(res) < qty: return false

	# Consume
	for res in craft_cost:
		var qty = craft_cost[res]
		if res == "credits":
			GameState.resources.remove_currency("credits", qty)
		else:
			GameState.resources.remove_element(res, qty)
			
	# === Matrix Core Crafting Logic ===
	if module_id == "matrix_synthesis":
		# Roll random core
		var roll = randi() % 4
		var gem_id = ""
		match roll:
			0: gem_id = "CrackedCrimsonCore"
			1: gem_id = "CrackedCobaltCore"
			2: gem_id = "CrackedTopazCore"
			3: gem_id = "CrackedAmethystCore"
			_: gem_id = "CrackedCrimsonCore"
			
		GameState.resources.add_element(gem_id, 1)
		UITheme.show_notification(tr("Synthesized: %s") % ElementDB.get_display_name(gem_id), Color(0.8, 0.3, 0.8))
		inventory_updated.emit()
		return true
		
	elif mod_data.get("slot_type") == "gem_synth":
		# It's an upgrade recipe, map ID to output gem
		var out_gem = ""
		match module_id:
			"cracked_crimson_core": out_gem = "StableCrimsonCore"
			"stable_crimson_core": out_gem = "PristineCrimsonCore"
			"cracked_cobalt_core": out_gem = "StableCobaltCore"
			"stable_cobalt_core": out_gem = "PristineCobaltCore"
			"cracked_topaz_core": out_gem = "StableTopazCore"
			"stable_topaz_core": out_gem = "PristineTopazCore"
			"cracked_amethyst_core": out_gem = "StableAmethystCore"
			"stable_amethyst_core": out_gem = "PristineAmethystCore"
			# v135a: Resonant tier (CMB_4) — Pristine input -> Resonant output.
			"pristine_crimson_core": out_gem = "ResonantCrimsonCore"
			"pristine_cobalt_core": out_gem = "ResonantCobaltCore"
			"pristine_topaz_core": out_gem = "ResonantTopazCore"
			"pristine_amethyst_core": out_gem = "ResonantAmethystCore"

		if out_gem != "":
			GameState.resources.add_element(out_gem, 1)
			UITheme.show_notification(tr("Fused: %s") % ElementDB.get_display_name(out_gem), Color(0.8, 0.3, 0.8))
			inventory_updated.emit()
			return true
			
	# Normal Module Crafting
	module_inventory[module_id] = module_inventory.get(module_id, 0) + 1
	module_crafted.emit(module_id)
	inventory_updated.emit() # Fix: Signal for UI update
	return true

func equip_module(slot_idx: int, module_id: String, silent: bool = false) -> bool:
	# Used by Designer UI. silent=true for internal bulk re-equip (hull switch,
	# preset load): suppresses per-step power/research toasts — the final
	# recalc + ship-status indicator reports the real power state once.
	if not active_hull in hulls:
		print("Equip Fail: Active hull not found or invalid.")
		return false
	var hull_data = hulls[active_hull]
	
	# v135a: effective slots include the CMB_3 aux slot (index == base slot count).
	var eff_slots := get_effective_slots()
	if slot_idx >= eff_slots.size():
		print("Equip Fail: Slot index out of bounds.")
		return false
	var req_type = eff_slots[slot_idx]
	
	if not module_id in modules:
		print("Equip Fail: Module ID not found.")
		return false
	
	# v71.5: Enforce Research Prerequisites
	var status = can_equip_module(module_id)
	if not status["can_equip"]:
		print("Equip Fail: ", status["reason"])
		if not silent:
			UITheme.show_notification(tr(str(status["reason"])), Color.RED)
		return false
		
	var mod_data = modules[module_id]
	# v135a: the CMB_3 aux slot (req_type "aux") accepts any standard module type,
	# but NOT socket gems or consumables — those have their own equip paths.
	if req_type == "aux":
		if mod_data["slot_type"] in ["gem", "consumable"]:
			print("Equip Fail: Aux slot rejects ", mod_data["slot_type"])
			return false
	elif mod_data["slot_type"] != req_type:
		print("Equip Fail: Slot Type Mismatch. Req: ", req_type, " Got: ", mod_data["slot_type"])
		return false
		
	# v64.0 Fix: Enforce Uniqueness
	if mod_data.get("unique", false):
		for slot in loadout:
			if slot != slot_idx and loadout[slot] == module_id:
				print("Equip Fail: Module is unique and already equipped.")
				return false
	
	if module_inventory.get(module_id, 0) <= 0:
		print("Equip Fail: No inventory.")
		return false
	
	# v110: Battery-only energy guard. Capacity + load are DERIVED by tier
	# (helpers); hulls contribute 0. Compute the loadout's load/capacity both
	# BEFORE and AFTER this hypothetical equip, then block over-capacity — with
	# an anti-softlock exception: always allow an equip that improves the net
	# power margin, so an overloaded ship can always be repaired step by step.
	# v119: Engineering skill no longer scales energy capacity (removed from
	# recalc_stats too — keep this guard consistent). applied_physics research stays.
	var rm = GameState.research_manager
	var phys_mult = 1.0
	if rm:
		phys_mult = 1.0 + rm.get_efficiency_bonus("basic_engineering")
	var cap_mult = phys_mult

	var old_load := 0.0
	var old_cap := 0.0
	var new_load := 0.0
	var new_cap := 0.0
	for s_idx in loadout:
		var mid = loadout[s_idx]
		if mid and mid in modules:
			old_load += get_module_energy_load(mid)
			old_cap += get_module_energy_capacity(mid) * cap_mult
			if s_idx != slot_idx:  # this slot is being replaced by the equip
				new_load += get_module_energy_load(mid)
				new_cap += get_module_energy_capacity(mid) * cap_mult
	# Add the incoming module to the prospective state.
	new_load += get_module_energy_load(module_id)
	new_cap += get_module_energy_capacity(module_id) * cap_mult

	if new_load > new_cap:
		var old_margin = old_cap - old_load
		var new_margin = new_cap - new_load
		# Allow only if this equip improves the margin (anti-softlock).
		if new_margin <= old_margin + 0.1:
			if not silent:
				UITheme.show_notification(tr("Power %d / %d — equip more (or higher-tier) Battery modules first.") % [int(round(new_load)), int(round(new_cap))], Color(1.0, 0.45, 0.35))
			return false

	# Unequip existing
	var existing = loadout.get(slot_idx)
	if existing:
		module_inventory[existing] = module_inventory.get(existing, 0) + 1
		
	module_inventory[module_id] = module_inventory.get(module_id, 0) - 1  # v132: default 1 was a latent dupe trap (stock guard above makes 0 correct)
	if module_inventory[module_id] <= 0:
		module_inventory.erase(module_id)
		
	loadout[slot_idx] = module_id
	
	recalc_stats()
	inventory_updated.emit() # Fix: Signal for UI update
	
	# v80.2 Fix: Clear incompatible ammo when swapping weapons
	if mod_data["slot_type"] == "weapon":
		var ammo_id = ammo_loadout.get(slot_idx, "")
		if ammo_id != "":
			var m_stats = mod_data.get("stats", {})
			var w_type = "kinetic"
			if m_stats.get("atk_energy", 0) > 0: w_type = "energy"
			elif m_stats.get("atk_explosive", 0) > 0: w_type = "explosive"
			
			if not is_ammo_compatible(w_type, ammo_id):
				ammo_loadout.erase(slot_idx) # Clear it so auto-equip can run
	
	# Auto-Equip Ammo if slot is empty (QoL Fix)
	if mod_data["slot_type"] == "weapon" and not ammo_loadout.get(slot_idx):
		var stats = mod_data.get("stats", {})
		if stats.get("atk_kinetic", 0) > 0:
			ammo_loadout[slot_idx] = "SlugT1"
		elif stats.get("atk_energy", 0) > 0:
			ammo_loadout[slot_idx] = "CellT1"
		# v65.0 Fix: Auto-equip for Explosive weapons mismatch
		elif stats.get("atk_explosive", 0) > 0:
			# v134: MissileT1 is the real recipe output (craft_missile_t1). "missile" was
			# a phantom key the player could never craft, so the launcher auto-loaded ammo
			# it had zero of and fired empty. Set it unconditionally like kinetic/energy.
			ammo_loadout[slot_idx] = "MissileT1"
	_autosave_active_preset()   # v134g: persist the edit to the active build slot
	return true

func unequip_slot(slot_idx: int):
	var existing = loadout.get(slot_idx)
	if existing:
		module_inventory[existing] = module_inventory.get(existing, 0) + 1
		loadout.erase(slot_idx)
		# Fix Medium: Clear ammo slot on unequip
		ammo_loadout.erase(slot_idx)
		recalc_stats()
		inventory_updated.emit() # Fix: Signal for UI update
		_autosave_active_preset()   # v134g: persist the edit to the active build slot

func handle_module_defeat():
	# v125: ONLINE defeat is non-destructive. Every equipped module floors to 50%
	# durability (never lower, never destroyed) — the old 1/6 instant-destroy +
	# 10-50% roll is gone (premium: no sudden loss of earned gear). At <=50% a
	# module is "destroyable", but that loss only ever happens during OFFLINE
	# combat (opt-in + consented — see apply_offline_durability_risk).
	var changed := false
	for slot_idx in loadout:
		var mid = loadout[slot_idx]
		if not mid or mid == "": continue

		# Base modules must become a custom instance so durability can be tracked.
		if not mid.begins_with("custom_"):
			var base_data = modules.get(mid)
			if base_data:
				var custom_id = "custom_%s_%d_%d" % [mid, Time.get_ticks_msec() + slot_idx, _drop_seq]
				_drop_seq += 1
				var custom_module = base_data.duplicate(true)
				custom_module["is_custom"] = true
				custom_module["base_module"] = mid
				custom_module["durability"] = 100

				modules[custom_id] = custom_module
				custom_modules[custom_id] = custom_module
				loadout[slot_idx] = custom_id
				mid = custom_id

		# Guard: a loadout slot can reference a module id that's no longer in
		# `modules` (custom-instance id collision under rapid losses). Skip the
		# stale ref instead of crashing on modules[mid].
		if not (mid in modules):
			continue
		var m = modules[mid]
		var current_dur = int(m.get("durability", 100))
		if current_dur > 50:
			m["durability"] = 50
			changed = true

	if changed:
		log_msg("DEFEAT: equipped modules worn down to 50% durability — repair with Spare Parts.")
		recalc_stats()
		# The base→custom conversion above rewrote loadout slot ids (base id →
		# custom-instance id) so durability can be tracked. Re-sync the ACTIVE build
		# slot to the new ids: otherwise the preset keeps the stale BASE ids, and the
		# next time it's applied (build-slot switch or relog) equip_module fails on
		# them ("No inventory" — the base copy is now a custom instance the player owns
		# instead), so the slot loads EMPTY even though the gear is still owned. That
		# is the "loadout N emptied itself after a loss" data-loss bug.
		_autosave_active_preset()


# v135b: SIM-ONLY hook (default false → real game UNAFFECTED; modules incl.
# batteries stay destructible, player re-crafts them). The player-bot sets this so
# its ship never loses BATTERIES to offline combat — not for balance, but because
# offline destruction lands BETWEEN a fight's prep and its combat-ready assert
# (batteries die in the offline gap → next fight reads SHIP UNPOWERED → false
# CANT_FIRE violation). Protecting batteries in-sim keeps the funnel measuring the
# real economy without that timing artifact.
var sim_protect_batteries := false

func apply_offline_durability_risk(delta: float) -> Array:
	# v125: OFFLINE combat runs unattended, so it carries the real loss risk the
	# player consents to when enabling it. Only modules ALREADY worn to <=50%
	# durability ("destroyable") can be lost — pristine/>50% gear is always safe.
	# Per-module destruction chance scales with hours away, capped. Repairing worn
	# modules before logging off carries ZERO risk. Returns destroyed display names
	# so the offline report can surface exactly what was lost (never silent).
	var destroyed: Array = []
	var hours: float = delta / 3600.0
	var p: float = clampf(0.05 * hours, 0.0, 0.35)   # ~5%/hr, capped 35% per worn module
	if p <= 0.0:
		return destroyed
	var slots_to_clear: Array = []
	for slot_idx in loadout:
		var mid = loadout[slot_idx]
		if not mid or mid == "": continue
		if not (mid in modules): continue
		if sim_protect_batteries and String(modules[mid].get("slot_type", "")) == "battery":
			continue   # sim-only: see sim_protect_batteries note above
		var dur: int = int(modules[mid].get("durability", 100))
		if dur <= 50 and randf() < p:
			destroyed.append(str(modules[mid].get("name", mid)))
			slots_to_clear.append(slot_idx)
	for slot_idx in slots_to_clear:
		var mid = loadout.get(slot_idx)
		if mid:
			if str(mid).begins_with("custom_"):
				custom_modules.erase(mid)
				modules.erase(mid)
			loadout[slot_idx] = null
	if not slots_to_clear.is_empty():
		recalc_stats()
		inventory_updated.emit()   # was dead code AFTER the return below — the armory
								   # never refreshed after offline module destruction
	return destroyed

func log_msg(msg: String):
	if GameState.combat_manager:
		GameState.combat_manager.log_msg(msg)
	else:
		print(msg)

func set_slot_ammo(slot_idx: int, ammo_id: String) -> bool:
	if ammo_id != "":
		# v80.2 Fix: Enforce ammo-to-weapon compatibility
		var mid = loadout.get(slot_idx)
		if mid and mid in modules:
			var m_stats = modules[mid].get("stats", {})
			var w_type = "kinetic"
			if m_stats.get("atk_energy", 0) > 0: w_type = "energy"
			elif m_stats.get("atk_explosive", 0) > 0: w_type = "explosive"
			
			if not is_ammo_compatible(w_type, ammo_id):
				print("Ammo Fail: Type Mismatch. Weapon: %s, Ammo: %s" % [w_type, ammo_id])
				UITheme.show_notification(tr("Incompatible Ammo Type"), Color.RED)
				return false
				
	ammo_loadout[slot_idx] = ammo_id
	_autosave_active_preset()   # v134g: persist the edit to the active build slot
	return true

# Step 6: Gem Socket Support
func insert_gem(module_id: String, socket_idx: int, gem_id: String) -> bool:
	if GameState.resources.get_element_amount(gem_id) <= 0: return false
	
	var mod = modules.get(module_id)
	if not mod or not mod.has("sockets"): return false
	if socket_idx < 0 or socket_idx >= mod["sockets"].size(): return false
	if mod["sockets"][socket_idx] != null: return false # Already filled
	
	GameState.resources.remove_element(gem_id, 1)
	mod["sockets"][socket_idx] = gem_id
	recalc_stats()
	inventory_updated.emit()
	return true

func remove_gem(module_id: String, socket_idx: int) -> bool:
	# Removed inventory check to allow removal from equipped modules
	var mod = modules.get(module_id)
	if not mod or not mod.has("sockets"): return false
	if socket_idx < 0 or socket_idx >= mod["sockets"].size(): return false
	
	var gem = mod["sockets"][socket_idx]
	if not gem: return false
	
	GameState.resources.add_element(gem, 1)
	mod["sockets"][socket_idx] = null
	recalc_stats()
	inventory_updated.emit()
	return true

# v118: aggregated matrix-core facet bonuses (the 12 new keys), keyed by host slot
# category. Recomputed each recalc_stats; consumed by combat (Phase 2).
var gem_bonuses: Dictionary = {}

# Map a module's slot_type to its gem facet category: weapons -> offense, armor/
# shield -> defense, everything else (engine/sensor/battery/...) -> utility.
func _gem_slot_category(slot_type: String) -> String:
	if slot_type == "weapon":
		return "weapon"
	if slot_type == "armor" or slot_type == "shield":
		return "defense"
	return "utility"

# v118: matrix-core facet text helpers (designer socket UI + gem inspect card).
const GEM_STAT_LABELS := {
	"crit_damage": "Crit Damage", "attack_speed": "Attack Speed",
	"armor_pen": "Armor Penetration", "resist_pierce": "Resist Pierce",
	"damage_reduction": "Damage Reduction", "shield_regen_mult": "Shield Regen",
	"evasion_flat": "Evasion", "max_hull_mult": "Max Hull",
	"ammo_eff": "Ammo Efficiency", "energy_eff": "Energy Efficiency",
	"module_drop_mult": "Module Find", "restore_on_kill": "Restore on Kill",
}

func format_gem_stat(key: String, val) -> String:
	var label: String = GEM_STAT_LABELS.get(key, key.replace("_", " ").capitalize())
	if key.ends_with("_flat"):
		return "+%d %s" % [int(val), label]
	return "+%d%% %s" % [int(round(float(val) * 100.0)), label]

# The bonus a gem actually provides in a given host slot type (its slot-matched facet).
func get_gem_facet_text(gem_id: String, slot_type: String) -> String:
	if not GEM_FACETS.has(gem_id):
		return ""
	var facet: Dictionary = GEM_FACETS[gem_id].get(_gem_slot_category(slot_type), {})
	var parts: Array = []
	for k in facet:
		parts.append(format_gem_stat(String(k), facet[k]))
	return ", ".join(parts)

# v135a: CMB_3 "Auxiliary Slot" warp node grants ONE extra module slot that
# accepts ANY module type. Rather than hard-code an index (base slot counts differ
# per hull, corvette 8 → dreadnought 26), expose an EFFECTIVE-slots accessor: the
# hull's fixed slots plus one "aux" sentinel when CMB_3 is owned. Every slot-length
# / slot-type read routes through this so the aux slot stays consistent across
# equip, hull-switch, save/load, reset, and the designer UI.
func get_effective_slots() -> Array:
	if not active_hull in hulls:
		return []
	var s: Array = hulls[active_hull]["slots"].duplicate()
	# warp_manager may be null during autoload-init ordering — treat as not-owned.
	if GameState.warp_manager and GameState.warp_manager.is_node_purchased("CMB_3"):
		s.append("aux")
	return s

# Loadout index of the aux slot on the CURRENT hull (== base slot count), or -1
# when CMB_3 is not owned / no valid hull. Derived, never persisted — it moves with
# the hull's base slot count, which is correct because hull-switch re-seats slots.
func get_aux_slot_index() -> int:
	if not active_hull in hulls:
		return -1
	if GameState.warp_manager and GameState.warp_manager.is_node_purchased("CMB_3"):
		return hulls[active_hull]["slots"].size()
	return -1

func recalc_stats():
	# Capture the pre-recalc damage fraction. Loadout / research / hull /
	# trophy changes all re-run this outside combat; without this the final
	# clamp would fake-damage a full ship when max_hp grows and permanently
	# erode HP on any transient max_hp dip.
	var _prev_max_hp: float = float(max_hp)
	var _hp_ratio: float = 1.0
	if _prev_max_hp > 0.0:
		_hp_ratio = clampf(float(current_hp) / _prev_max_hp, 0.0, 1.0)
	var hp = 0
	var shield = 0.0
	var s_reg = 0.0
	var atk_k = 0
	var atk_e = 0
	var atk_x = 0
	var defe = 0
	var eva = 0.0
	var crit = 0.05
	# v145: base-module sensor loot stats. Accumulated here and folded into
	# affix_bonuses below (that dict is the single thing combat reads), so a
	# CRAFTED sensor and a sensor AFFIX contribute through one code path.
	var drop_enemy = 0.0
	var drop_module = 0.0
	var e_cap = 0.0
	var h_reg = 0.0
	var e_load = 0.0
	var atk_speed_bon = 0.0
	var s_reg_bon = 0.0
	var jam_str = 0.0
	var rk = 0.0  # v127: aggregate per-type resistances (baseline + affix)
	var re = 0.0
	var rx = 0.0

	if active_hull in hulls:
		var h = hulls[active_hull]["stats"]
		hp += h.get("hp", 0)
		shield += h.get("max_shield", 0)
		# v119: hull base attack removed — combat damage comes entirely from equipped
		# weapon modules, so the hull `atk` no longer feeds the aggregate (it was never
		# read in combat and only inflated the displayed attack stat).
		defe += h.get("def", 0)
		eva += h.get("eva", 0)
		# v110: hulls provide ZERO energy — all capacity comes from batteries.
		# (hull energy_capacity stat is now vestigial / display-only.)
		# e_cap += h.get("energy_capacity", 0)
		
	# v119: Engineering (Processing) skill no longer buffs ship stats — combat is
	# loadout/hull/warp/research-driven, matching the balance model the sims assume
	# (they run an Engineering-level-1 player). Engineering stays a crafting skill.
	
	for mid in loadout.values():
		if mid:
			if not mid in modules:
				continue
				
			var m = modules[mid]["stats"]
			hp += m.get("hp", 0)
			shield += m.get("max_shield", 0)
			s_reg += m.get("shield_regen", 0)
			hp_regen += m.get("hp_regen", 0) # v80.1: Native HP Regen support
			atk_k += m.get("atk_kinetic", 0)
			atk_e += m.get("atk_energy", 0)
			atk_x += m.get("atk_explosive", 0)
			defe += m.get("def", 0)
			eva += m.get("eva", 0) # v65.3 Fix: Flat stat
			crit += m.get("crit_chance", 0.0)
			drop_enemy += m.get("enemy_drop_mult", 0.0)    # v145: sensor identity
			drop_module += m.get("module_drop_mult", 0.0)
			# v110: derive energy supply (batteries) + draw (consumers) by tier.
			e_cap += get_module_energy_capacity(mid)
			e_load += get_module_energy_load(mid)
			atk_speed_bon += m.get("atk_speed_mult", 0.0)
			atk_speed_bon += m.get("atk_speed_bonus", 0.0)
			s_reg_bon += m.get("shield_regen_mult", 0.0)
			s_reg_bon += m.get("shield_regen_bonus", 0.0)
			jam_str += m.get("jamming_strength", 0.0)
			rk += m.get("resist_k", 0.0)  # v127: baseline resist from module def
			re += m.get("resist_e", 0.0)
			rx += m.get("resist_x", 0.0)
			# v127 R2: per-slot baseline resist (generalist floor from CRAFTED gear).
			# Armor = physical plate (kinetic/explosive lean); Shield = energy barrier.
			var _st := str(modules[mid].get("slot_type", ""))
			if _st == "armor":
				rk += 0.08
				re += 0.02
				rx += 0.06
			elif _st == "shield":
				rk += 0.03
				re += 0.08
				rx += 0.03

	# Reset Affix Bonuses
	for key in affix_bonuses:
		affix_bonuses[key] = 0.0
		
	# Aggregate Affixes from Custom Modules
	for mid in loadout.values():
		if mid and mid in custom_modules:
			var affixes = custom_modules[mid].get("affixes", {})
			for affix_id in affixes:
				if affix_id in affix_bonuses:
					affix_bonuses[affix_id] += affixes[affix_id]

	# v145: fold the CRAFTED sensor line's base loot stats into the same two keys
	# the sensor AFFIXES use, so combat_manager has exactly one thing to read.
	# Must come AFTER the reset+affix loop above or it would be wiped.
	affix_bonuses["enemy_drop_mult"] += drop_enemy
	affix_bonuses["module_drop_mult"] += drop_module

	# v80.1: Apply Flat Affix Bonuses to base values BEFORE multipliers
	hp += affix_bonuses.get("flat_hp", 0.0)
	shield += affix_bonuses.get("flat_shield", 0.0)
	defe += affix_bonuses.get("flat_def", 0.0)
	atk_k += affix_bonuses.get("flat_atk", 0.0)
	
	# v85.1: Add New Affix types to global stats
	crit += affix_bonuses.get("combat_sight", 0.0)
	eva += affix_bonuses.get("reflexive_plating", 0.0)
	# v127: per-type resist AFFIXES stack on the module-def baseline.
	rk += affix_bonuses.get("resist_k", 0.0)
	re += affix_bonuses.get("resist_e", 0.0)
	rx += affix_bonuses.get("resist_x", 0.0)
	
	# v85.2: Accumulate D4 stats (Combat manager will handle the logic, but we track the totals)
	# Note: These are mostly procs/thresholds, but we track totals for tooltip display logic if needed.
	# Actually, CombatManager will check sm.affix_bonuses directly.

	var rm = GameState.research_manager
	var hp_mult = 1.0
	if rm:
		hp_mult += rm.get_efficiency_bonus("max_hp_mult")
		hp_mult += rm.get_efficiency_bonus("materials_science")
	
	max_hp = int(hp * hp_mult)
	if max_hp <= 0: max_hp = 10
	
	max_shield = shield
	shield_regen = s_reg
	attack_kinetic = atk_k
	attack_energy = atk_e
	attack_explosive = atk_x
	
	attack = attack_kinetic + attack_energy + attack_explosive
	defense = defe
	evasion = eva
	hp_regen = h_reg
	# v127: commit per-type resistances, each capped at 0.75 (you always eat >=25%).
	resist_k = clampf(rk, 0.0, 0.75)
	resist_e = clampf(re, 0.0, 0.75)
	resist_x = clampf(rx, 0.0, 0.75)
	crit_chance = crit
	energy_used = e_load
	attack_speed_bonus = atk_speed_bon
	# v131: trophies removed — get_trophy_buff("ship_speed") is now the Temporal
	# Module capstone only.
	if GameState.bounty_manager:
		attack_speed_bonus += (GameState.bounty_manager.get_trophy_buff("ship_speed") - 1.0)

	# v112: Primordial Armor capstone — "best-in-slot defense" = +30% hull HP.
	# Self-contained presence check.
	if GameState.resources and GameState.resources.get_element_amount("PrimordialArmor") > 0:
		max_hp = int(max_hp * 1.30)
		if max_hp <= 0: max_hp = 10

	shield_regen_bonus = s_reg_bon
	jamming_strength = jam_str
	
	# Step 6 (v118): Matrix-core facet accumulation. Each socketed gem contributes
	# the facet matching its HOST module's slot category (weapon/defense/utility).
	gem_bonuses = {}
	for mid in loadout.values():
		if mid and mid in modules and modules[mid].has("sockets"):
			var host_cat: String = _gem_slot_category(modules[mid].get("slot_type", ""))
			for gem in modules[mid]["sockets"]:
				if gem and gem in GEM_FACETS:
					var facet: Dictionary = GEM_FACETS[gem].get(host_cat, {})
					for k in facet:
						gem_bonuses[k] = gem_bonuses.get(k, 0.0) + facet[k]
						
	# v118: clamp each facet to its aggregate cap (bounds the max-stack — a maxed T10
	# hull can't push any facet past its GEM_FACET_CAPS ceiling).
	for _gk in gem_bonuses:
		if GEM_FACET_CAPS.has(_gk):
			gem_bonuses[_gk] = minf(float(gem_bonuses[_gk]), float(GEM_FACET_CAPS[_gk]))
	# v118 Phase 2: apply the STAT-aggregate facets here; the rest (crit_chance,
	# crit_damage, armor_pen, resist_pierce, damage_reduction, ammo_eff,
	# restore_on_kill, module_drop_mult) are consumed live in combat_manager.
	crit_chance += gem_bonuses.get("crit_chance", 0.0)
	evasion += int(round(gem_bonuses.get("evasion_flat", 0.0)))
	shield_regen = int(round(float(shield_regen) * (1.0 + gem_bonuses.get("shield_regen_mult", 0.0))))
	max_hp = int(round(float(max_hp) * (1.0 + gem_bonuses.get("max_hull_mult", 0.0))))
	energy_used = int(round(float(energy_used) * (1.0 - gem_bonuses.get("energy_eff", 0.0))))
	attack_speed_bonus += gem_bonuses.get("attack_speed", 0.0)

	# v107: Warp Mastery Tree — C1 Hull Reinforcement (+10% Hull HP, all hulls)
	if GameState.warp_manager:
		max_hp = int(float(max_hp) * GameState.warp_manager.get_tree_hull_bonus())
	# v109: Recursion — Recursive Hardening (infinite +5%/level Hull HP).
	# Multiplicative on top of the warp tree's flat +10%; both compound.
	if GameState.research_manager:
		max_hp = int(float(max_hp) * (1.0 + GameState.research_manager.get_efficiency_bonus("hull_hp_mult")))
	attack = attack_kinetic + attack_energy + attack_explosive

	# v105b: void_shielding_1 +5% Total Ship Shields. Endgame sink that
	# had no consumer despite a 100M-credit unlock cost.
	# Nerfed 20% → 5% (v105c): 20% stacked too hard on shield gem mults.
	if rm and rm.is_tech_unlocked("void_shielding_1"):
		max_shield *= 1.05
	# v118: evasion / energy / etc. gem bonuses now apply in combat (Phase 2).
	
	# Audit v8.0 P1-25: Applied Physics Hub Bonus (+10% Energy Capacity)
	if rm:
		e_cap *= (1.0 + rm.get_efficiency_bonus("basic_engineering"))

	# v110 Phase 1: ship energy capacity now lives on its own field. All ship
	# combat/equip/UI reads use sm.energy_capacity. resources.max_energy is
	# still mirrored (below) for the infrastructure grid, which currently
	# borrows it as a storage ceiling — that coupling is separated in Phase 2
	# when hull energy is removed (so removing it can't shrink the infra grid).
	energy_capacity = e_cap
	# v112: Void Battery capstone — "ultimate power storage" = +40% ship energy
	# capacity (stacks on the v112 battery headroom; lets the player slot more).
	if GameState.resources and GameState.resources.get_element_amount("VoidBattery") > 0:
		energy_capacity = int(energy_capacity * 1.40)
	# v110: ship no longer writes resources.max_energy — that field is now the
	# infrastructure grid's buffer ceiling (set by infrastructure_manager).
	# Ship energy lives entirely on energy_capacity / energy_used.

	# Was the ship full before this recalc? Then keep it full when max_hp
	# grows (fixes "100/132 though I never fought"). Otherwise keep the
	# absolute HP, only clamped to the new max — damage persists until you
	# pay Repair, and recalcs never silently bleed HP out of combat.
	if _hp_ratio >= 0.999:
		current_hp = max_hp
	else:
		current_hp = int(clampf(float(current_hp), 1.0, float(max_hp)))
	
	


# v111.18 Phase 2: persistent Armory grid placement, as (page, x, y). A coord
# of -1 means "no saved position" (auto-pack). Stored as a plain {p,x,y} dict
# for JSON safety. Old saves (pre-pagination) stored just {x,y} → page 0.
func get_armory_pos(item_id: String) -> Vector3i:
	var p = armory_layout.get(item_id)
	if typeof(p) != TYPE_DICTIONARY:
		return Vector3i(-1, -1, -1)
	return Vector3i(int(p.get("p", 0)), int(p.get("x", -1)), int(p.get("y", -1)))

func set_armory_pos(item_id: String, page: int, gx: int, gy: int) -> void:
	armory_layout[item_id] = {"p": page, "x": gx, "y": gy}

func clear_armory_pos(item_id: String) -> void:
	armory_layout.erase(item_id)

func get_save_data_manager() -> Dictionary:
	var data = {}
	data["active_hull"] = active_hull
	data["loadout"] = loadout
	data["inventory"] = module_inventory
	data["unseen_modules"] = unseen_modules
	data["hp"] = current_hp
	data["ammo_loadout"] = ammo_loadout
	data["consumable_hull_slot"] = consumable_hull_slot
	data["consumable_shield_slot"] = consumable_shield_slot
	data["custom_modules"] = custom_modules
	data["loadout_presets"] = loadout_presets
	data["armory_layout"] = armory_layout
	data["equipped_relic"] = equipped_relic  # v113 (NG+ P2)
	data["drop_seq"] = _drop_seq  # v134e: persist the custom-id counter (see load)
	data["active_preset_idx"] = active_preset_idx  # v134g: the live build slot
	return data

func load_save_data_manager(data: Dictionary):
	if data.is_empty(): return
	
	active_hull = data.get("active_hull", "corvette_hull")
	var saved_load = data.get("loadout", {})
	
	if data.has("consumable_hull_slot"): consumable_hull_slot = data["consumable_hull_slot"]
	if data.has("consumable_shield_slot"): consumable_shield_slot = data["consumable_shield_slot"]
	
	custom_modules = data.get("custom_modules", {})
	# v134e: custom module ids are "custom_<base>_<ticks_msec>_<drop_seq>". ticks_msec
	# resets to ~0 each launch, so the whole cross-session uniqueness rested on
	# _drop_seq — which was NEVER persisted (reset to 0 every boot). Two sessions'
	# first drops at the same ms-since-boot would collide and silently OVERWRITE a
	# rolled module in `modules`. Persist the counter (now globally monotonic); old
	# saves seed it past their existing custom-module count so new ids can't collide
	# with already-stored ones.
	_drop_seq = int(data.get("drop_seq", custom_modules.size() + 1))
	for cm_id in custom_modules:
		# v118: heat removed — migrate the legacy "heat_sync_focus" affix key
		# (re-skinned to Servo Overclock) on existing rolled gear.
		var _afx = custom_modules[cm_id].get("affixes", null)
		if _afx is Dictionary and _afx.has("heat_sync_focus"):
			_afx["servo_overclock"] = _afx["heat_sync_focus"]
			_afx.erase("heat_sync_focus")
		# v145 MIGRATION: the accuracy axis was deleted and the crafted sensor line
		# re-statted to enemy_drop_mult / module_drop_mult. A ROLLED sensor stores its
		# own stat dict in the save, so without this a legacy dropped sensor would load
		# carrying only a dead "accuracy" key — a genuinely blank module in a slot that
		# still draws power. Re-seed it from its base def (drop rates are not
		# rarity-boosted, so the base value IS the correct value) and strip the dead key.
		# Legacy weapons also carried a "flat_accuracy" affix; strip it so no tooltip
		# or roll-range renderer has to look up an id AFFIX_DB no longer defines.
		var _cst = custom_modules[cm_id].get("stats", null)
		if _cst is Dictionary and _cst.has("accuracy"):
			_cst.erase("accuracy")
			var _base_id: String = str(custom_modules[cm_id].get("base_module", ""))
			var _bst: Dictionary = modules.get(_base_id, {}).get("stats", {})
			for _k in ["enemy_drop_mult", "module_drop_mult"]:
				if _bst.has(_k):
					_cst[_k] = _bst[_k]
		if _afx is Dictionary and _afx.has("flat_accuracy"):
			_afx.erase("flat_accuracy")
		modules[cm_id] = custom_modules[cm_id]
	
	# Convert JSON string keys back to int if needed or handle direct
	loadout = {}
	if active_hull in hulls:
		# v135a: EFFECTIVE slot count so a saved CMB_3 aux-slot module (index == base
		# slot count) is restored, not silently truncated on every relog.
		var slot_count = get_effective_slots().size()
		for i in range(slot_count):
			var val = saved_load.get(str(i)) # JSON keys are strings
			if not val: val = saved_load.get(i) # Try int key
			loadout[i] = val

	module_inventory = data.get("inventory", {})
	# v135a: return any saved loadout entry BEYOND the effective slot count to
	# inventory — e.g. an aux-slot module saved while CMB_3 was owned, then loaded
	# after a hard reset cleared the node (or before warp_manager finished init).
	# Runs AFTER module_inventory is loaded above so the += isn't overwritten.
	if active_hull in hulls:
		var _eff_count: int = get_effective_slots().size()
		for _k in saved_load.keys():
			var _idx := int(_k)
			if _idx >= _eff_count:
				var _amid = saved_load[_k]
				if _amid != null and _amid != "" and _amid in modules:
					module_inventory[_amid] = module_inventory.get(_amid, 0) + 1
	unseen_modules = data.get("unseen_modules", {})
	# Migration: old saves have no armory_layout → {} (everything auto-packs).
	armory_layout = data.get("armory_layout", {})
	equipped_relic = data.get("equipped_relic", "")  # v113 (NG+ P2)
	# v146 MIGRATION: must run BEFORE the v113 scrub below, which would silently drop a
	# base-id Architect piece with no compensation. Takes `data` because the loadout
	# presets are restored further down and still need scrubbing.
	_migrate_remove_architects_regalia(data)
	# v113: scrub any equipped/owned module whose def no longer exists (e.g. the
	# removed free Cryo Shard Pistol) so a stale id can't dangle into recalc/UI.
	for _s in loadout.keys():
		var _mid = loadout[_s]
		if _mid != null and _mid != "" and not (_mid in modules):
			loadout[_s] = null
	for _mid in module_inventory.keys():
		if not (_mid in modules):
			module_inventory.erase(_mid)
	_migrate_module_entries_from_resources()
	_migrate_atk_interval_caps()

	# Convert JSON string keys for ammo_loadout back to int
	var saved_ammo = data.get("ammo_loadout", {})
	ammo_loadout = {}
	for key in saved_ammo:
		ammo_loadout[int(key)] = saved_ammo[key]
	recalc_stats()
	_repower_if_unpowered()  # v110: re-power pre-battery loadouts under the battery-only model
	current_hp = data.get("hp", max_hp)

	# Restore loadout presets (JSON string keys → int)
	var saved_presets = data.get("loadout_presets", {})
	for raw_idx in saved_presets:
		var p_idx = int(raw_idx)
		if not p_idx in loadout_presets: continue
		var p = saved_presets[raw_idx]
		var preset = loadout_presets[p_idx]
		preset["name"] = p.get("name", "")
		preset["consumable_hull"] = p.get("consumable_hull", "")
		preset["consumable_shield"] = p.get("consumable_shield", "")
		preset["loadout"] = {}
		for k in p.get("loadout", {}):
			preset["loadout"][int(k)] = p["loadout"][k]
		preset["ammo_loadout"] = {}
		for k in p.get("ammo_loadout", {}):
			preset["ammo_loadout"][int(k)] = p["ammo_loadout"][k]

	# v134g: restore the active build slot. A pre-v134g save has no such field —
	# its live loadout wasn't tied to any slot, so migrate it INTO slot 1 (the
	# default active) so switching slots preserves the player's current build.
	active_preset_idx = int(data.get("active_preset_idx", 1))
	if active_preset_idx < 1 or not active_preset_idx in loadout_presets:
		active_preset_idx = 1
	if not data.has("active_preset_idx"):
		var _was := _suppress_preset_autosave
		_suppress_preset_autosave = true
		save_loadout_preset(active_preset_idx)   # sync live build → active slot
		_suppress_preset_autosave = _was

	# v136: heal build slots saved before the hull-remap fix. A player who upgraded hulls
	# pre-v136 has non-active presets still keyed to an OLD hull's slot layout; realign
	# them to the current hull so they load fully instead of stripped. Idempotent
	# (type-driven) — presets already valid for this hull are reproduced unchanged.
	_migrate_presets_to_current_hull()

# ═══════════════════════════════════════════════════════════════
# v146 MIGRATION — "Architect's Regalia" (Z1 unique set) deleted
# ═══════════════════════════════════════════════════════════════
# The five Z1 pieces were removed outright: the tutorial zone must not hand out a
# 3-piece +25% attack-speed set (99be329 pulled them off the boss table; the defs and
# the set bonus are now gone too). They were rarity-4 DROPS, so a live save can hold
# one as a base id, as a rolled "custom_z1_unique_*" instance, EQUIPPED in a loadout
# slot, stored in a build preset, and SOCKETED with matrix cores. Deleting the defs
# without this would leave a dangling id in every one of those places.
#
# Handling reuses the paths this repo already has, rather than inventing one:
#   - socketed gems go back to the element pool exactly as remove_gem() returns them;
#   - each owned copy pays what demolish_module() pays for a destroyed module of that
#     rarity and zone (rarity-scaled Spare Parts + the Zone-1 salvage item), which is
#     this game's compensation for gear that ceases to exist. Modules have had no Lira
#     sell value since v140, so Spare Parts + salvage IS the fair payout.
const REMOVED_ARCHITECT_MODULES := [
	"z1_unique_weapon", "z1_unique_kinetic", "z1_unique_missile",
	"z1_unique_armor", "z1_unique_shield",
]

# True for a deleted base id AND for any rolled instance whose base_module is one.
func _is_removed_architect_module(mid: String) -> bool:
	if mid in REMOVED_ARCHITECT_MODULES:
		return true
	var d = custom_modules.get(mid, modules.get(mid, {}))
	if d is Dictionary:
		return String(d.get("base_module", "")) in REMOVED_ARCHITECT_MODULES
	return false

# Takes the raw shipyard save dict: the loadout presets and the ammo map are restored
# further down in load_save_data_manager, so they are scrubbed at the source.
func _migrate_remove_architects_regalia(data: Dictionary) -> void:
	var dead: Dictionary = {}   # id -> true

	for mid in custom_modules.keys():
		if _is_removed_architect_module(String(mid)):
			dead[String(mid)] = true
	for mid in module_inventory.keys():
		if _is_removed_architect_module(String(mid)):
			dead[String(mid)] = true
	for s in loadout.keys():
		var lm = loadout[s]
		if lm != null and String(lm) != "" and _is_removed_architect_module(String(lm)):
			dead[String(lm)] = true

	var saved_load = data.get("loadout", {})
	var saved_ammo = data.get("ammo_loadout", {})
	var saved_presets = data.get("loadout_presets", {})

	# Slots BEYOND the current hull's effective slot count (e.g. a CMB_3 aux slot saved
	# then loaded without the node) never reach `loadout` — catch them at the source.
	if saved_load is Dictionary:
		for k in saved_load.keys():
			if loadout.has(int(k)):
				continue
			var sm_id = saved_load[k]
			if sm_id != null and String(sm_id) != "" and _is_removed_architect_module(String(sm_id)):
				dead[String(sm_id)] = true

	if saved_presets is Dictionary:
		for p_key in saved_presets.keys():
			var p = saved_presets[p_key]
			if not (p is Dictionary):
				continue
			var p_load = p.get("loadout", {})
			if not (p_load is Dictionary):
				continue
			for s_key in p_load.keys():
				var pm = p_load[s_key]
				if pm != null and String(pm) != "" and _is_removed_architect_module(String(pm)):
					dead[String(pm)] = true

	if dead.is_empty():
		return

	var parts_total: int = 0
	var salvage_total: int = 0
	var gems_total: int = 0
	var copies_total: int = 0

	for mid in dead.keys():
		var m_id: String = String(mid)
		var def_d: Dictionary = {}
		if custom_modules.has(m_id) and custom_modules[m_id] is Dictionary:
			def_d = custom_modules[m_id]
		elif modules.has(m_id) and modules[m_id] is Dictionary:
			def_d = modules[m_id]
		# A base id whose def is already gone still has its known rarity/zone.
		var rarity: int = int(def_d.get("rarity", Rarity.UNIQUE))
		var zone: int = int(def_d.get("zone", 1))

		# Owned copies = stacked in inventory + every slot it currently occupies
		# (equipping moves the copy OUT of module_inventory — see unequip_slot).
		var copies: int = int(module_inventory.get(m_id, 0))
		for s in loadout.keys():
			if loadout[s] != null and String(loadout[s]) == m_id:
				loadout[s] = null
				if saved_ammo is Dictionary:
					saved_ammo.erase(str(s))
					saved_ammo.erase(int(s))
				copies += 1
		if saved_load is Dictionary:
			for k in saved_load.keys():
				if loadout.has(int(k)):
					continue
				if saved_load[k] != null and String(saved_load[k]) == m_id:
					saved_load[k] = null
					copies += 1

		# Matrix cores go back to the element pool (same as remove_gem).
		var socks = def_d.get("sockets", [])
		if socks is Array:
			for gi in range(socks.size()):
				var g = socks[gi]
				if g != null and String(g) != "":
					if GameState.resources:
						GameState.resources.add_element(String(g), 1)
					gems_total += 1
				socks[gi] = null

		# Compensation, per demolish_module's payout for this rarity/zone.
		if copies > 0:
			copies_total += copies
			var parts: int = int(RARITY_SPARE_PARTS.get(rarity, 1)) * copies
			if GameState.resources and parts > 0:
				GameState.resources.add_element("SparePart", parts)
			parts_total += parts
			if rarity > Rarity.COMMON:
				var salvage_item: String = "MiteChitin" if zone == 1 else ""
				var salv: int = (rarity - Rarity.COMMON) * copies
				if salvage_item != "" and GameState.resources:
					GameState.resources.add_element(salvage_item, salv)
					salvage_total += salv

		module_inventory.erase(m_id)
		custom_modules.erase(m_id)
		modules.erase(m_id)
		unseen_modules.erase(m_id)
		armory_layout.erase(m_id)

	# Build presets keep their slot, minus the deleted module.
	if saved_presets is Dictionary:
		for p_key in saved_presets.keys():
			var p = saved_presets[p_key]
			if not (p is Dictionary):
				continue
			var p_load = p.get("loadout", {})
			if not (p_load is Dictionary):
				continue
			var p_ammo = p.get("ammo_loadout", {})
			for s_key in p_load.keys():
				var pm = p_load[s_key]
				if pm != null and String(pm) != "" and dead.has(String(pm)):
					p_load[s_key] = null
					if p_ammo is Dictionary:
						p_ammo.erase(s_key)

	print("v146 migration: removed %d Architect's Regalia module(s), %d copies -> %d Spare Parts, %d salvage, %d matrix core(s) returned." % [dead.size(), copies_total, parts_total, salvage_total, gems_total])

# Manual Repair System
func get_full_repair_cost(hull_id: String) -> int:
	var costs = {
		"corvette_hull": 1000,
		"frigate_hull": 5000,
		"destroyer_hull": 25000,
		"battlecruiser_hull": 100000,
		"dreadnought_hull": 500000
	}
	return costs.get(hull_id, 1000)

func get_repair_cost() -> int:
	if current_hp >= max_hp:
		return 0
	
	var full_cost = get_full_repair_cost(active_hull)
	var missing_hp = max_hp - current_hp
	var damage_ratio = float(missing_hp) / float(max_hp)
	
	var cost = max(10, int(full_cost * damage_ratio))
	return cost

func can_repair() -> bool:
	# Audit v68.0: Prevent repairs during active combat
	if GameState.combat_manager and GameState.combat_manager.in_combat:
		return false
		
	var has_damage = current_hp < max_hp
	var can_afford = GameState.resources.get_currency("credits") >= get_repair_cost()
	return has_damage and can_afford

func repair_hull() -> bool:
	# v124: hull repair CONSUMES the equipped hull repair kit (no Liras). Out of
	# combat consumables have no cooldown, so this tops up to full by spending
	# kits one at a time. No kit/stock -> can't repair; craft an Emergency Patch
	# (20 Fe, lvl 1, no research — the always-available anti-softlock floor).
	if GameState.combat_manager and GameState.combat_manager.in_combat:
		return false
	if current_hp >= max_hp:
		return false
	var kit = consumable_hull_slot
	if kit == "" or GameState.resources.get_element_amount(kit) < 1:
		print("[Repair] No hull repair kit equipped/stocked.")
		return false
	var cm = GameState.combat_manager
	var guard := 0
	while current_hp < max_hp and GameState.resources.get_element_amount(kit) >= 1 and guard < 200:
		cm.use_manual_consumable("hull")
		guard += 1
	return true
	
func reset(decay_factor: float = 1.0) -> void:
	active_hull = "corvette_hull"
	module_inventory = {}
	unseen_modules = {}
	loadout = {}
	ammo_loadout = {}
	custom_modules = {}
	# v134g: new game / warp wipes the ship, so wipe the build slots too and start
	# on slot 1 — otherwise a slot would still point at pre-reset (now non-existent)
	# modules. The fresh starter build is synced into slot 1 at the end.
	consumable_hull_slot = ""
	consumable_shield_slot = ""
	for _pi in loadout_presets:
		loadout_presets[_pi] = {"name": "", "loadout": {}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""}
	active_preset_idx = 1
	if active_hull in hulls:
		# v135a: effective slots so the CMB_3 aux slot stays allocated post-warp
		# (loadout persists across warp; CMB_3 persists in warp_manager).
		for i in range(get_effective_slots().size()):
			loadout[i] = null
	# v134g: power-first onboarding. A NEW GAME (decay_factor >= 1.0) now starts
	# UNPOWERED — the tutorial (m005b/m005c) teaches the player to craft + equip
	# batteries BEFORE the engine, so the battery-only power model is legible from
	# the first loadout action. A WARP (decay_factor < 1.0) still auto-equips the
	# starter batteries — an experienced prestige player must not be forced to
	# re-craft power every single run.
	if decay_factor < 1.0:
		_grant_and_equip_starter_batteries()
	# v134g: capture the fresh build as slot 1 so switching slots preserves it (any
	# batteries were placed directly, not via equip_module, so no auto-save fired).
	save_loadout_preset(active_preset_idx)
	recalc_stats()
	# New game / warp: the ship starts at FULL integrity. recalc_stats() alone
	# preserves the pre-reset HP fraction (right for in-game equips, wrong here) —
	# so a stale damaged current_hp (e.g. 13 carried from a loaded save) would ride
	# into the fresh corvette and read as a near-empty hull. Force full.
	current_hp = max_hp

# v110: seed the active hull's battery slots with tier-1 batteries.
func _grant_and_equip_starter_batteries() -> void:
	if not ("z1_battery" in modules) or not (active_hull in hulls):
		return
	module_inventory["z1_battery"] = 2
	var slots: Array = hulls[active_hull].get("slots", [])
	var placed := 0
	for i in range(slots.size()):
		if placed >= 2:
			break
		if slots[i] == "battery":
			loadout[i] = "z1_battery"
			module_inventory["z1_battery"] -= 1
			placed += 1

# Highest-capacity battery the player currently owns (for the v110 re-power
# migration below); "" if none.
func _best_owned_battery() -> String:
	var best := ""
	var best_cap := 0
	for mid in module_inventory:
		if int(module_inventory.get(mid, 0)) <= 0: continue
		if modules.get(mid, {}).get("slot_type", "") != "battery": continue
		var cap := get_module_energy_capacity(mid)
		if cap > best_cap:
			best_cap = cap
			best = mid
	return best

# v110 migration: pre-battery saves (the hull used to supply energy) load with
# consumers but no batteries → "SHIP UNPOWERED". Fill empty battery slots (best
# owned battery, else a granted z1) until the grid is positive, so a migrated
# ship is never stranded.
func _repower_if_unpowered() -> void:
	if active_hull not in hulls: return
	if energy_used <= energy_capacity: return
	var slots: Array = hulls[active_hull].get("slots", [])
	for i in range(slots.size()):
		if energy_used <= energy_capacity: return
		if slots[i] != "battery" or loadout.get(i) != null: continue
		var bat := _best_owned_battery()
		if bat == "":
			if not ("z1_battery" in modules): return
			module_inventory["z1_battery"] = int(module_inventory.get("z1_battery", 0)) + 1
			bat = "z1_battery"
		loadout[i] = bat
		if int(module_inventory.get(bat, 0)) > 0:
			module_inventory[bat] -= 1
		recalc_stats()

# v66.0: Consumable Management
func equip_consumable(slot_type: String, item_id: String):
	print("Equipping consumable: %s -> %s" % [slot_type, item_id])
	# slot_type: "hull" or "shield"
	var data = ElementDB.get_consumable_data(item_id)
	if data.is_empty():
		print("Invalid consumable data for %s" % item_id)
		return # Invalid item
	
	if data.get("type") != slot_type:
		print("Type mismatch: %s != %s" % [data.get("type"), slot_type])
		return # Mismatch
		
	if slot_type == "hull":
		consumable_hull_slot = item_id
	elif slot_type == "shield":
		consumable_shield_slot = item_id
	# Without this, mission sync (equip_consumables) and the UI never
	# re-evaluate on equip — the Combat Triage step would sit at 0%.
	inventory_updated.emit()
	_autosave_active_preset()   # v134g: persist the edit to the active build slot

func unequip_consumable(slot_type: String):
	if slot_type == "hull":
		consumable_hull_slot = ""
	elif slot_type == "shield":
		consumable_shield_slot = ""
	inventory_updated.emit()
	_autosave_active_preset()   # v134g: persist the edit to the active build slot

func get_consumable(slot_type: String) -> String:
	if slot_type == "hull": return consumable_hull_slot
	if slot_type == "shield": return consumable_shield_slot
	return ""

func get_module_zone_multiplier(zone_difficulty: int) -> float:
	var diff = max(1, zone_difficulty)
	var early_steps = min(diff - 1, MODULE_ZONE_LATE_START - 1)
	var late_steps = max(0, diff - MODULE_ZONE_LATE_START)
	return pow(MODULE_ZONE_SCALE_EARLY, early_steps) * pow(MODULE_ZONE_SCALE_LATE, late_steps)

# v80.1: Calculate scaled range for an affix based on zone difficulty
func get_affix_scaled_range(affix_id: String, zone_difficulty: int) -> Array:
	if affix_id not in AFFIX_DB: return [0.0, 0.0]
	var cfg = AFFIX_DB[affix_id]
	var r_min = cfg["range"][0]
	var r_max = cfg["range"][1]
	
	if cfg.get("scaling") == "flat":
		var scaled_min = floor(float(r_min) * pow(1.8, max(0, zone_difficulty - 1)))
		var scaled_max = floor(float(r_max) * pow(1.8, max(0, zone_difficulty - 1)))
		return [scaled_min, scaled_max]
	elif cfg.get("scaling") == "linear_tier":
		# v85.1: Base * Zone
		return [float(r_min) * zone_difficulty, float(r_max) * zone_difficulty]
	else:
		# Percent affixes [3, 10] -> [0.03, 0.10]
		return [float(r_min) / 100.0, float(r_max) / 100.0]

func is_ammo_compatible(weapon_type: String, ammo_id: String) -> bool:
	if ammo_id == "": return true
	if weapon_type == "kinetic":
		return ammo_id.begins_with("Slug") or ammo_id == "kinetic_shell" or "Slug" in ammo_id
	elif weapon_type == "energy":
		return ammo_id.begins_with("Cell") or ammo_id == "energy_cell" or "Cell" in ammo_id
	elif weapon_type == "explosive":
		return "Missile" in ammo_id or "Torpedo" in ammo_id or ammo_id == "missile"
	return false

# v115: monotonic counter so custom-module ids are unique even when many roll in
# the same millisecond. Time.get_ticks_msec() alone collides under batch/offline
# loot -- the second roll overwrote the first in `modules` (silent loss; could even
# swap a Legendary's entry for a Unique, corrupting which module you actually hold).
var _drop_seq: int = 0

# v127 H1: shared affix helpers — the single source of truth that both
# generate_module_drop AND the Hack Stone crafting system call, so affix pooling,
# rolling, Greater-Affix chance and naming can never drift between drops and crafts.

# Legal affix pool for a slot_type, minus any ids to exclude (e.g. already present).
func _legal_affix_pool(slot_type: String, exclude: Array = []) -> Array:
	var pool := []
	for a_id in AFFIX_DB:
		if a_id in exclude:
			continue
		var cfg = AFFIX_DB[a_id]
		if not _affix_research_ok(cfg):
			continue
		if not cfg.has("limit_to") or slot_type in cfg["limit_to"]:
			pool.append(a_id)
	# Fallback: generic industrial/economy fill for slots no affix restricts to.
	if pool.is_empty():
		for a_id in AFFIX_DB:
			if a_id in exclude:
				continue
			if not _affix_research_ok(AFFIX_DB[a_id]):
				continue
			if AFFIX_DB[a_id]["type"] in ["industrial", "economy"]:
				pool.append(a_id)
	return pool

# v141: an affix may declare "research_req" — it must not ROLL until the system it
# scales exists for the player (a "+18% Hack Card drop chance" sensor is a dead stat
# before Firmware Hacking, since hack-stone drops return empty without that tech).
# Gates rolling only: gear that already carries the affix keeps it, and it starts
# working the moment the tech lands.
func _affix_research_ok(cfg: Dictionary) -> bool:
	var req := str(cfg.get("research_req", ""))
	if req == "":
		return true
	var rm = GameState.research_manager
	return rm != null and rm.is_tech_unlocked(req)

# Roll ONE affix's final value at a zone difficulty. 15% Greater-Affix chance
# (2x max roll). Percent -> fraction; flat -> floor(base * 1.8^(zone-1)); linear_tier
# -> base * zone. Returns {"value": float, "is_greater": bool}.
func _roll_affix_value(affix_id: String, zone_difficulty: int, ga_chance: float = 0.15) -> Dictionary:
	var cfg = AFFIX_DB[affix_id]
	var is_greater := randf() < ga_chance
	var raw_val = 0.0
	if is_greater:
		raw_val = cfg["range"][1] * GA_MULT
	else:
		raw_val = randi_range(cfg["range"][0], cfg["range"][1])
	var final_val := 0.0
	if cfg.get("scaling") == "flat":
		# v128: cap the exponential flat term at AFFIX_ZONE_CAP so stored floats stay exact.
		final_val = floor(float(raw_val) * pow(1.8, int(min(zone_difficulty, AFFIX_ZONE_CAP)) - 1))
	elif cfg.get("scaling") == "linear_tier":
		final_val = float(raw_val) * zone_difficulty
	else:
		final_val = float(raw_val) / 100.0
	return {"value": final_val, "is_greater": is_greater}

# Recompose a module's dynamic display name from its base name + ordered affix ids.
func _compose_module_name(base_name: String, affix_ids: Array) -> String:
	if affix_ids.is_empty():
		return base_name
	var prefix = AFFIX_NAMING.get(affix_ids[0], {}).get("prefix", "")
	var suffix = AFFIX_NAMING.get(affix_ids[-1], {}).get("suffix", "")
	var nm := base_name
	if prefix != "":
		nm = prefix + " " + nm
	if suffix != "" and affix_ids.size() > 1:
		nm = nm + " " + suffix
	return nm

# v71.0: Generate a rarity-boosted module drop from a base module ID
func generate_module_drop(base_module_id: String, rarity: int = Rarity.UNCOMMON, zone_difficulty: int = 1) -> String:
	if base_module_id not in modules:
		print("generate_module_drop: Unknown base module '%s'" % base_module_id)
		return ""
	
	# Common modules are fixed drops; no custom roll is created.
	if rarity == Rarity.COMMON:
		module_inventory[base_module_id] = module_inventory.get(base_module_id, 0) + 1
		new_drops_alert = true
		inventory_updated.emit()
		return base_module_id
	
	var base = modules[base_module_id]
	var custom_id = "custom_%s_%d_%d" % [base_module_id, Time.get_ticks_msec(), _drop_seq]
	_drop_seq += 1
	var zone_mult = get_module_zone_multiplier(zone_difficulty)
	
	# Apply stat bonuses based on rarity tier
	var stat_range = RARITY_STAT_RANGE.get(rarity, [0.0, 0.0])
	var custom_stats = {}
	for stat_key in base.get("stats", {}):
		var base_val = base["stats"][stat_key]
		if stat_key in BOOSTABLE_STATS:
			var scaled_base = base_val
			
			var bonus = randf_range(stat_range[0], stat_range[1])
			var boosted = scaled_base
			
			if stat_key == "atk_interval":
				# Reciprocal scaling: faster fire rate at higher rarity.
				# Coefficient lowered from 0.4 → 0.15 so a max-roll Unique caps near
				# -40% reduction (was -67%). Damage scaling is unchanged; this only
				# affects fire rate, preventing compound DPS outliers that let a
				# T2 Unique trivialize T3+ content.
				var speed_bonus = bonus * 0.15
				boosted = scaled_base / (1.0 + speed_bonus)
				# Hard floor: interval can never drop below 60% of base (-40% cap).
				boosted = max(boosted, scaled_base * 0.6)
				# Absolute floor: never under 0.25s (4Hz fire rate cap) for very fast bases.
				boosted = max(boosted, 0.25)
			else:
				boosted = scaled_base * (1.0 + bonus)
			
			if scaled_base is float or stat_key == "atk_interval":
				custom_stats[stat_key] = snappedf(boosted, 0.01)
			else:
				if float(scaled_base) < 50.0:
					custom_stats[stat_key] = snappedf(boosted, 0.1)
				else:
					custom_stats[stat_key] = int(round(boosted))
		else:
			# Non-boostable stats (energy_load, etc.) stay at base
			custom_stats[stat_key] = base_val
	
	# v74.0: Affix Generation
	var custom_affixes = {}
	var slot_type = base.get("slot_type", "utility")
	
	# v76.5: Filter affix pool by slot_type.
	# v141: was a byte-identical inline copy of _legal_affix_pool (same limit_to
	# filter + same industrial/economy fallback), so a pool rule added there silently
	# missed drops. Routed through the shared helper — which also applies the
	# research gate, keeping dead affixes (Hack Card drop chance pre-Firmware
	# Hacking) out of the roll.
	var affix_pool = _legal_affix_pool(slot_type)

	var num_affixes = 0
	# v139d Rare gate (owner rule): Uncommon affixes 1 -> 0 (reverts v101).
	# The rarity STAT ranges are already disjoint (Uncommon caps x1.20, Rare
	# floors x1.25) — the single v101 affix was the ONLY bridge letting a
	# god-rolled Uncommon reach boss-viable power. Removing it separates the
	# tiers in the ITEM NUMBERS themselves (no combat multiplier hacks): boss
	# gearcheck U-wins are affix-driven leaks, and this closes them at the
	# source. Tier identity: Common = crafted baseline, Uncommon = stat bump,
	# RARE = where affixes (builds) begin, Legendary/Unique = more + greater.
	if rarity == Rarity.RARE: num_affixes = 2      # v101: Was 1
	elif rarity == Rarity.LEGENDARY: num_affixes = 3 # v101: Was 2
	elif rarity == Rarity.UNIQUE: num_affixes = 4  # v101: Was 3
	
	num_affixes = min(num_affixes, affix_pool.size())
	
	# v85.3: Dynamic Naming & GA Initialization
	var final_name = base.get("name", "Unknown")
	var greater_affixes = []
	
	if num_affixes > 0:
		affix_pool.shuffle()
		for i in range(num_affixes):
			var affix_id = affix_pool[i]
			var cfg = AFFIX_DB[affix_id]
			
			# v101: Greater Affix Logic (15% chance, was 10%)
			var is_greater = randf() < 0.15
			var raw_val = 0.0
			
			if is_greater:
				# v101: GA pinned to 2.0x max roll (was 1.5x)
				raw_val = cfg["range"][1] * GA_MULT
				greater_affixes.append(affix_id)
			else:
				raw_val = randi_range(cfg["range"][0], cfg["range"][1])
				
			var final_val = 0.0
			
			if cfg.get("scaling") == "flat":
				# v80.1: floor(Base * 1.8^(Zone - 1))
				final_val = floor(float(raw_val) * pow(1.8, zone_difficulty - 1))
			elif cfg.get("scaling") == "linear_tier":
				# v85.1: Base * Zone (e.g. 3 * Zone 5 = 15)
				final_val = float(raw_val) * zone_difficulty
			else: # percent
				# v80.1: range [3, 10] becomes [0.03, 0.10]
				final_val = float(raw_val) / 100.0
				
			custom_affixes[affix_id] = final_val
	
		# v85.3: Apply Dynamic Naming if affixes exist
		var affix_ids = custom_affixes.keys()
		var first_affix = affix_ids[0]
		var last_affix = affix_ids[-1]
		
		var prefix = AFFIX_NAMING.get(first_affix, {}).get("prefix", "")
		var suffix = AFFIX_NAMING.get(last_affix, {}).get("suffix", "")
		
		if prefix != "":
			final_name = prefix + " " + final_name
		if suffix != "" and affix_ids.size() > 1:
			final_name = final_name + " " + suffix
			
	var rarity_label = RARITY_LABELS.get(rarity, "")
	var suffix_label = " (%s)" % rarity_label if rarity_label != "" else ""
	
	# Socket Generation (Step 6)
	var sockets = []
	if base.get("rarity") == Rarity.LEGENDARY or rarity == Rarity.LEGENDARY or rarity == Rarity.UNIQUE:
		var socket_count = 3 if rarity == Rarity.UNIQUE else (randi() % 3 + 1) # 1 to 3 sockets for Legendary, 3 for Unique
		for _i in range(socket_count): sockets.append(null)
	elif rarity == Rarity.RARE:
		if randf() < 0.3: # 30% chance for a socket on Rare
			sockets.append(null)
			
	var custom_module = {
		"name": "%s%s" % [final_name, suffix_label],
		"slot_type": base.get("slot_type", "weapon"),
		"stats": custom_stats,
		"cost": {},
		"desc": base.get("desc", ""),
		"is_custom": true,
		"is_unique": base.get("is_unique", false),
		"set_id": base.get("set_id", ""),
		"research_req": base.get("research_req", ""),
		"rarity": rarity,
		"base_module": base_module_id,
		"zone_difficulty": max(1, zone_difficulty),
		# v115 FIX: carry the base module's TIER onto the drop so the tier-gate
		# (get_module_tier / module_tier_penetration) reads it. Without this, rolled
		# drops had no zone/power_tier -> get_module_tier()=0 -> every drop (even a
		# tier-matched Legendary, and the Unique skip-key) was treated as tier 0 and
		# could NEVER pierce a hardened enemy.
		"zone": int(base.get("zone", max(1, zone_difficulty))),
		"power_tier": int(base.get("power_tier", base.get("zone", max(1, zone_difficulty)))),
		"affixes": custom_affixes,
		"greater_affixes": greater_affixes, # v85.2: Track GA affixes
		"sockets": sockets,
		"durability": 100
	}
	
	# Legendary: add extra flavor
	if rarity == Rarity.LEGENDARY:
		custom_module["desc"] = custom_module["desc"] + " (Legendary variant)"
	
	modules[custom_id] = custom_module
	custom_modules[custom_id] = custom_module
	
	module_inventory[custom_id] = module_inventory.get(custom_id, 0) + 1
	unseen_modules[custom_id] = true
	new_drops_alert = true
	inventory_updated.emit()
	return custom_id

# Backward compat wrapper
func generate_custom_weapon(base_weapon_id: String) -> String:
	return generate_module_drop(base_weapon_id, Rarity.RARE)

# v71.0: Get rarity of any module (with name-based fallback for legacy items)
# v135a: distinct unique-set pieces OWNED (equipped + inventory) per set_id, capped
# at 3 (weapon/armor/shield). Feeds the neutral Collection panel — pure state, no
# weakness/zone hints. Counts DISTINCT slot-types so duplicates never read >3/3.
func get_owned_set_counts() -> Dictionary:
	var by_set := {}   # set_id -> {slot_type: true}
	for slot in loadout:
		var m = loadout[slot]
		if m != null and String(m) != "":
			_tally_set_piece(by_set, String(m))
	for mid in module_inventory:
		if int(module_inventory.get(mid, 0)) > 0:
			_tally_set_piece(by_set, String(mid))
	var out := {}
	for sid in by_set:
		out[sid] = int((by_set[sid] as Dictionary).size())
	return out

func _tally_set_piece(by_set: Dictionary, mid: String) -> void:
	if mid == "" or mid == equipped_relic:
		return
	var mdata: Dictionary = modules.get(mid, {})
	var sid := String(mdata.get("set_id", ""))
	# Fallback: affixed/custom drops may carry set_id only on the base module.
	if sid == "" and mdata.get("is_custom", false) and mdata.has("base_module"):
		sid = String(modules.get(mdata["base_module"], {}).get("set_id", ""))
	if sid == "":
		return
	var st := String(mdata.get("slot_type", ""))
	if st == "":
		return
	var d: Dictionary = by_set.get(sid, {})
	d[st] = true
	by_set[sid] = d

func get_module_rarity(module_id: String) -> int:
	var m = modules.get(module_id, {})
	if m.has("rarity"):
		return m["rarity"]
	
	# Fallback: parse from name for modules created before rarity system
	var name_str = m.get("name", "")
	if "(Legendary)" in name_str: return Rarity.LEGENDARY
	if "(Rare)" in name_str: return Rarity.RARE
	if "(Uncommon)" in name_str: return Rarity.UNCOMMON
	return Rarity.COMMON

func get_module_durability(module_id: String) -> int:
	var m = modules.get(module_id, {})
	return int(m.get("durability", 100))

# ══ v127 H2: Hack Stone crafting engine ═══════════════════════════════════
# Rare consumables dragged onto a module in the Ship Designer to modify its affixes
# (currency-as-crafting ported from PoE2 — see docs/design/HACK_STONES.md). All
# rolling routes through the H1 helpers so crafts and drops share ONE affix path.
const HACK_STONE_IDS := ["SpliceChip", "FirmwareInjector", "RootKey", "AnchorBolt", "CorruptionWorm", "RefitBay", "SignalCalibrator"]
# v127: player-facing effect blurb per stone (single source of truth for the
# tooltip / arm-confirm UI). Keep in sync with apply_hack_stone below.
const HACK_STONE_DESC := {
	"SpliceChip": "Awaken a Common module → Uncommon, rolling 1 random affix.",
	"FirmwareInjector": "Forge a Common module straight to Rare with 2 fresh affixes.",
	"RootKey": "Rarity +1 tier — keeps every existing affix, rolls 1 new one.",
	"AnchorBolt": "Lock an affix from rerolls (up to 2 on Legendary; re-apply to release).",
	"CorruptionWorm": "Remove 1 RANDOM unlocked affix, roll a new one (25% Greater-Affix — the gamble).",
	"RefitBay": "Remove 1 CHOSEN unlocked affix, roll a new one in its place (deterministic).",
	"SignalCalibrator": "Re-roll the VALUES of every unanchored affix — identities & count kept.",
}
const HACK_STONE_LIRA_COST := {
	Rarity.UNCOMMON: 500, Rarity.RARE: 3000, Rarity.LEGENDARY: 20000, Rarity.UNIQUE: 100000,
}
# v128: affix magnitude scales 1.8^(zone-1); cap the exponent so deep-zone / NG+ crafts
# keep affix floats exactly integer-representable (< 2^23) instead of silently drifting.
const AFFIX_ZONE_CAP := 15

# v128 P0: craft cost re-couples to the module's ZONE, not rarity alone. A Z12 base rolls
# Z12-magnitude affixes, so it must cost Z12 Liras — closes the cheap-deep-base arbitrage
# (a flat-3000 Rare craft on a Z12 base was ~200x underpriced vs the power it produced).
func _hack_lira_cost(rarity: int, zone_difficulty: int = 3) -> int:
	var base: int = int(HACK_STONE_LIRA_COST.get(rarity, 500))
	var z: int = int(min(max(zone_difficulty, 1), AFFIX_ZONE_CAP))
	return int(base * pow(1.8, max(0, z - 3)))

# v128 Q2: normalized anchor set — legacy single `anchored_affix` (string) + new
# `anchored_affixes` (array). Reading both keeps pre-v128 saves valid with no migration.
func _anchored_array(m: Dictionary) -> Array:
	var out := []
	var legacy: String = str(m.get("anchored_affix", ""))
	if legacy != "":
		out.append(legacy)
	for a in m.get("anchored_affixes", []):
		var s: String = str(a)
		if s != "" and not (s in out):
			out.append(s)
	return out

# Legendary+ modules can hold 2 locks (protect a 2-affix core before Calibrator-fishing
# the third); lower rarities 1.
func _max_anchors(m: Dictionary) -> int:
	return 2 if int(m.get("rarity", Rarity.COMMON)) >= Rarity.LEGENDARY else 1

# Rebuild a custom module's display name from base + affixes + rarity label
# (mirrors generate_module_drop's naming so crafted names read like dropped ones).
func _rebuild_custom_name(m: Dictionary) -> String:
	var base_id: String = str(m.get("base_module", ""))
	var base_name: String = str((modules.get(base_id, {}) as Dictionary).get("name", m.get("name", "Module")))
	var nm: String = _compose_module_name(base_name, m.get("affixes", {}).keys())
	var rl: String = str(RARITY_LABELS.get(int(m.get("rarity", 0)), ""))
	if rl != "":
		nm = "%s (%s)" % [nm, rl]
	return nm

# Public entry: apply a Hack Stone to a module. `module_id` is a base COMMON id
# (Splice/Injector) or a custom_ instance id (all others). `arg` = chosen affix for
# Anchor Bolt. Returns {"ok": bool, "msg": String, "result_id": String}. Stone + Liras
# are consumed ONLY on success (each stone fn does its own consume).
# v127: dry-run acceptance check for the hold-and-click insert flow — mirrors the
# per-stone validation below WITHOUT consuming or applying anything. {ok, msg}.
func can_apply_hack_stone(stone_id: String, module_id: String) -> Dictionary:
	if GameState.resources.get_element_amount(stone_id) < 1:
		return {"ok": false, "msg": "No %s in stock." % ElementDB.get_display_name(stone_id)}
	if module_id == "" or not modules.has(module_id):
		return {"ok": false, "msg": "Invalid module."}
	var m: Dictionary = modules[module_id]
	match stone_id:
		"SpliceChip", "FirmwareInjector":
			if module_id.begins_with("custom_"):
				return {"ok": false, "msg": "Already awakened — use another stone."}
			if int(module_inventory.get(module_id, 0)) < 1:
				return {"ok": false, "msg": "Keep that component in inventory (not equipped) to Splice it."}
			var tr: int = Rarity.UNCOMMON if stone_id == "SpliceChip" else Rarity.RARE
			var tr_z: int = int(m.get("zone", m.get("zone_difficulty", 1)))
			if GameState.resources.get_currency("credits") < _hack_lira_cost(tr, tr_z):
				return {"ok": false, "msg": "Need %d Liras." % _hack_lira_cost(tr, tr_z)}
			return {"ok": true, "msg": ""}
		"RootKey":
			if not module_id.begins_with("custom_"):
				return {"ok": false, "msg": "Awaken it first with a Splice Chip."}
			var rar: int = int(m.get("rarity", Rarity.COMMON))
			if rar >= Rarity.LEGENDARY:
				return {"ok": false, "msg": "Root Key caps at Legendary."}
			var rk_z: int = int(m.get("zone_difficulty", 1))
			if GameState.resources.get_currency("credits") < _hack_lira_cost(rar + 1, rk_z):
				return {"ok": false, "msg": "Need %d Liras." % _hack_lira_cost(rar + 1, rk_z)}
			var rk_af: Dictionary = m.get("affixes", {})
			if _legal_affix_pool(str(m.get("slot_type", "")), rk_af.keys()).is_empty():
				return {"ok": false, "msg": "No new affix type fits this slot."}
			return {"ok": true, "msg": ""}
		"CorruptionWorm", "RefitBay":
			if not module_id.begins_with("custom_"):
				return {"ok": false, "msg": "Awaken it first with a Splice Chip."}
			if int(m.get("rarity", Rarity.COMMON)) < Rarity.RARE:
				return {"ok": false, "msg": "Needs Rare or higher."}
			var cw_anch: Array = _anchored_array(m)
			var cw_removable: bool = false
			for a in m.get("affixes", {}).keys():
				if not (str(a) in cw_anch):
					cw_removable = true
					break
			if not cw_removable:
				return {"ok": false, "msg": "No unlocked affix to reroll."}
			var cw_cost: int = _hack_lira_cost(int(m.get("rarity", Rarity.RARE)), int(m.get("zone_difficulty", 1)))
			if stone_id == "RefitBay":
				cw_cost = int(cw_cost * 1.67)   # control is the premium over the random Worm
			if GameState.resources.get_currency("credits") < cw_cost:
				return {"ok": false, "msg": "Need %d Liras." % cw_cost}
			return {"ok": true, "msg": ""}
		"SignalCalibrator":
			if not module_id.begins_with("custom_"):
				return {"ok": false, "msg": "Awaken it first with a Splice Chip."}
			if int(m.get("rarity", Rarity.COMMON)) < Rarity.RARE:
				return {"ok": false, "msg": "Needs Rare or higher."}
			var sc_anch: Array = _anchored_array(m)
			var sc_rollable: bool = false
			for a in m.get("affixes", {}).keys():
				if not (str(a) in sc_anch):
					sc_rollable = true
					break
			if not sc_rollable:
				return {"ok": false, "msg": "No unanchored affix to re-roll."}
			var sc_cost: int = _hack_lira_cost(int(m.get("rarity", Rarity.RARE)), int(m.get("zone_difficulty", 1)))
			if GameState.resources.get_currency("credits") < sc_cost:
				return {"ok": false, "msg": "Need %d Liras." % sc_cost}
			return {"ok": true, "msg": ""}
		"AnchorBolt":
			if not module_id.begins_with("custom_"):
				return {"ok": false, "msg": "Awaken it first with a Splice Chip."}
			var ab_af: Dictionary = m.get("affixes", {})
			if ab_af.is_empty():
				return {"ok": false, "msg": "No affix to anchor."}
			return {"ok": true, "msg": ""}
	return {"ok": false, "msg": "Unknown stone: %s" % stone_id}

func apply_hack_stone(stone_id: String, module_id: String, arg: String = "") -> Dictionary:
	if GameState.resources.get_element_amount(stone_id) < 1:
		return {"ok": false, "msg": "No %s in stock." % ElementDB.get_display_name(stone_id), "result_id": ""}
	if module_id == "" or not modules.has(module_id):
		return {"ok": false, "msg": "Invalid module.", "result_id": ""}
	var r: Dictionary = {"ok": false, "msg": "Unknown stone: %s" % stone_id, "result_id": ""}
	match stone_id:
		"SpliceChip": r = _stone_materialize(module_id, Rarity.UNCOMMON, stone_id)
		"FirmwareInjector": r = _stone_materialize(module_id, Rarity.RARE, stone_id)
		"RootKey": r = _stone_rootkey(module_id, stone_id)
		"CorruptionWorm": r = _stone_worm(module_id, stone_id, "")     # random target, 25% GA gamble
		"RefitBay": r = _stone_worm(module_id, stone_id, arg)          # chosen target, 15% GA, +67% cost
		"SignalCalibrator": r = _stone_calibrate(module_id, stone_id)
		"AnchorBolt": r = _stone_anchor(module_id, arg, stone_id)
	if bool(r.get("ok", false)):
		hack_stone_applied.emit(stone_id)   # v128: drives the goal_hack_3 mission
	return r

# Splice Chip (UNCOMMON) / Firmware Injector (RARE): awaken a fixed-stat COMMON into
# a rollable custom instance. Reuses generate_module_drop (mints custom + affixes +
# rarity stat boost), then consumes 1 of the base common.
func _stone_materialize(base_id: String, target_rarity: int, stone_id: String) -> Dictionary:
	if base_id.begins_with("custom_"):
		return {"ok": false, "msg": "Already awakened — use another stone.", "result_id": ""}
	if int(module_inventory.get(base_id, 0)) < 1:
		return {"ok": false, "msg": "Keep that component in inventory (not equipped) to Splice it.", "result_id": ""}
	var base: Dictionary = modules[base_id]
	var zone: int = int(base.get("zone", base.get("zone_difficulty", 1)))
	var cost: int = _hack_lira_cost(target_rarity, zone)
	if GameState.resources.get_currency("credits") < cost:
		return {"ok": false, "msg": "Need %d Liras." % cost, "result_id": ""}
	var new_id: String = generate_module_drop(base_id, target_rarity, zone)
	if new_id == "" or new_id == base_id:
		return {"ok": false, "msg": "Splice failed.", "result_id": ""}
	modules[new_id]["stone_crafted"] = true   # v127: mark so demolish can't profit (anti-pump)
	module_inventory[base_id] = int(module_inventory.get(base_id, 0)) - 1
	if int(module_inventory[base_id]) <= 0:
		module_inventory.erase(base_id)
	GameState.resources.remove_currency("credits", cost)
	GameState.resources.remove_element(stone_id, 1)
	inventory_updated.emit()
	return {"ok": true, "msg": "Awakened -> %s" % str((modules[new_id] as Dictionary).get("name", new_id)), "result_id": new_id}

# v127 review #5: top up sockets so a Root-Keyed Legendary/Unique matches a dropped
# one (dropped Legendary rolls 1-3, Unique 3). Never removes existing sockets.
func _topup_sockets(m: Dictionary, rarity: int) -> void:
	if not m.has("sockets"): m["sockets"] = []
	var target: int = 0
	if rarity == Rarity.UNIQUE: target = 3
	elif rarity == Rarity.LEGENDARY: target = 1
	while m["sockets"].size() < target:
		m["sockets"].append(null)

# Root Key: rarity +1 tier, KEEP all existing affixes + values, roll 1 new legal affix.
func _stone_rootkey(module_id: String, stone_id: String) -> Dictionary:
	if not module_id.begins_with("custom_"):
		return {"ok": false, "msg": "Awaken it first with a Splice Chip.", "result_id": ""}
	var m: Dictionary = modules[module_id]
	var rar: int = int(m.get("rarity", Rarity.COMMON))
	if rar >= Rarity.LEGENDARY:
		return {"ok": false, "msg": "Root Key caps at Legendary. Unique modules drop only from Sector bosses.", "result_id": ""}
	var cost: int = _hack_lira_cost(rar + 1, int(m.get("zone_difficulty", 1)))
	if GameState.resources.get_currency("credits") < cost:
		return {"ok": false, "msg": "Need %d Liras." % cost, "result_id": ""}
	if not m.has("affixes"): m["affixes"] = {}
	var pool: Array = _legal_affix_pool(str(m.get("slot_type", "")), m["affixes"].keys())
	if pool.is_empty():
		return {"ok": false, "msg": "No new affix type fits this slot.", "result_id": ""}
	pool.shuffle()
	var new_affix: String = str(pool[0])
	var roll: Dictionary = _roll_affix_value(new_affix, int(m.get("zone_difficulty", 1)))
	m["affixes"][new_affix] = roll["value"]
	if not m.has("greater_affixes"): m["greater_affixes"] = []
	if bool(roll["is_greater"]):
		m["greater_affixes"].append(new_affix)
	m["rarity"] = rar + 1
	m["stone_crafted"] = true   # v127: mark so demolish can't profit (anti-pump)
	_topup_sockets(m, rar + 1)  # v127 review #5: match dropped-item socket count
	m["name"] = _rebuild_custom_name(m)
	GameState.resources.remove_currency("credits", cost)
	GameState.resources.remove_element(stone_id, 1)
	recalc_stats()
	inventory_updated.emit()
	return {"ok": true, "msg": "Root Key -> %s + new affix." % str(RARITY_LABELS.get(rar + 1, "")), "result_id": module_id}

# Corruption Worm (chosen==""): remove 1 RANDOM unanchored affix, roll 1 new at 25% GA — the
# cheap high-variance gamble. Refit Bay (chosen==affix_id): remove that CHOSEN unanchored affix,
# roll 1 new at 15% GA, +67% cost (control is the premium). Count & rarity unchanged; respects anchors.
func _stone_worm(module_id: String, stone_id: String, chosen: String = "") -> Dictionary:
	if not module_id.begins_with("custom_"):
		return {"ok": false, "msg": "Awaken it first with a Splice Chip.", "result_id": ""}
	var m: Dictionary = modules[module_id]
	if int(m.get("rarity", Rarity.COMMON)) < Rarity.RARE:
		return {"ok": false, "msg": "Needs Rare or higher.", "result_id": ""}
	if not m.has("affixes"): m["affixes"] = {}
	var affixes: Dictionary = m["affixes"]
	var anchored: Array = _anchored_array(m)
	var removable: Array = []
	for a in affixes.keys():
		if not (str(a) in anchored):
			removable.append(str(a))
	if removable.is_empty():
		return {"ok": false, "msg": "No unlocked affix to reroll.", "result_id": ""}
	var is_refit: bool = (stone_id == "RefitBay")
	var drop_affix: String = ""
	if is_refit:
		if chosen == "" or not (chosen in removable):
			return {"ok": false, "msg": "Pick an unlocked affix to refit.", "result_id": ""}
		drop_affix = chosen
	else:
		removable.shuffle()
		drop_affix = str(removable[0])
	var cost: int = _hack_lira_cost(int(m.get("rarity", Rarity.RARE)), int(m.get("zone_difficulty", 1)))
	if is_refit:
		cost = int(cost * 1.67)
	if GameState.resources.get_currency("credits") < cost:
		return {"ok": false, "msg": "Need %d Liras." % cost, "result_id": ""}
	if not m.has("greater_affixes"): m["greater_affixes"] = []
	affixes.erase(drop_affix)
	m["greater_affixes"].erase(drop_affix)
	var pool: Array = _legal_affix_pool(str(m.get("slot_type", "")), affixes.keys())
	if not pool.is_empty():
		pool.shuffle()
		var new_affix: String = str(pool[0])
		# Worm gambles harder (25% GA) than deterministic Refit Bay (15%) — its upside.
		var ga: float = 0.15 if is_refit else 0.25
		var roll: Dictionary = _roll_affix_value(new_affix, int(m.get("zone_difficulty", 1)), ga)
		affixes[new_affix] = roll["value"]
		if bool(roll["is_greater"]):
			m["greater_affixes"].append(new_affix)
	m["stone_crafted"] = true   # v128: anti-pump — reshuffle outputs can't be sold for profit
	m["name"] = _rebuild_custom_name(m)
	GameState.resources.remove_currency("credits", cost)
	GameState.resources.remove_element(stone_id, 1)
	recalc_stats()
	inventory_updated.emit()
	var wlabel: String = "Refit Bay: chosen affix rerolled." if is_refit else "Corruption Worm: 1 affix rerolled."
	return {"ok": true, "msg": wlabel, "result_id": module_id}

# Signal Calibrator: re-roll the VALUES of every UNANCHORED affix (same ids, new magnitudes,
# fresh independent 15% GA each). Identities & count untouched — no brick. Respects anchors.
func _stone_calibrate(module_id: String, stone_id: String) -> Dictionary:
	if not module_id.begins_with("custom_"):
		return {"ok": false, "msg": "Awaken it first with a Splice Chip.", "result_id": ""}
	var m: Dictionary = modules[module_id]
	if int(m.get("rarity", Rarity.COMMON)) < Rarity.RARE:
		return {"ok": false, "msg": "Needs Rare or higher.", "result_id": ""}
	if not m.has("affixes"): m["affixes"] = {}
	var affixes: Dictionary = m["affixes"]
	var anchored: Array = _anchored_array(m)
	var targets: Array = []
	for a in affixes.keys():
		if not (str(a) in anchored):
			targets.append(str(a))
	if targets.is_empty():
		return {"ok": false, "msg": "No unanchored affix to re-roll.", "result_id": ""}
	var cost: int = _hack_lira_cost(int(m.get("rarity", Rarity.RARE)), int(m.get("zone_difficulty", 1)))
	if GameState.resources.get_currency("credits") < cost:
		return {"ok": false, "msg": "Need %d Liras." % cost, "result_id": ""}
	if not m.has("greater_affixes"): m["greater_affixes"] = []
	var z: int = int(m.get("zone_difficulty", 1))
	for aid in targets:
		var roll: Dictionary = _roll_affix_value(str(aid), z)   # same id, fresh value + independent 15% GA
		affixes[aid] = roll["value"]
		m["greater_affixes"].erase(aid)
		if bool(roll["is_greater"]):
			m["greater_affixes"].append(aid)
	m["stone_crafted"] = true
	m["name"] = _rebuild_custom_name(m)
	GameState.resources.remove_currency("credits", cost)
	GameState.resources.remove_element(stone_id, 1)
	recalc_stats()
	inventory_updated.emit()
	return {"ok": true, "msg": "Signal Calibrator: %d affix value(s) re-rolled." % targets.size(), "result_id": module_id}

# Anchor Bolt: lock a chosen affix from Worm/Refit/Calibrator. Legendary+ holds 2 locks.
# Re-applying to an anchored affix RELEASES it (free); locking consumes 1 card.
func _stone_anchor(module_id: String, arg: String, stone_id: String) -> Dictionary:
	if not module_id.begins_with("custom_"):
		return {"ok": false, "msg": "Awaken it first with a Splice Chip.", "result_id": ""}
	var m: Dictionary = modules[module_id]
	var affixes: Dictionary = m.get("affixes", {})
	if affixes.is_empty():
		return {"ok": false, "msg": "No affix to anchor.", "result_id": ""}
	var target: String = arg if affixes.has(arg) else str(affixes.keys()[0])
	var arr: Array = _anchored_array(m)
	var tname: String = str((AFFIX_DB.get(target, {}) as Dictionary).get("name", target))
	if target in arr:
		arr.erase(target)
		m["anchored_affixes"] = arr
		m.erase("anchored_affix")           # fold legacy field into the array model
		inventory_updated.emit()
		return {"ok": true, "msg": "Released: %s unlocked." % tname, "result_id": module_id}
	if arr.size() >= _max_anchors(m):
		return {"ok": false, "msg": "Max %d anchor(s) — release one, or Root Key to Legendary." % _max_anchors(m), "result_id": ""}
	arr.append(target)
	m["anchored_affixes"] = arr
	m.erase("anchored_affix")
	GameState.resources.remove_element(stone_id, 1)   # consume only on LOCK, not release
	inventory_updated.emit()
	return {"ok": true, "msg": "Anchored: %s locked." % tname, "result_id": module_id}

# ── v114: Zone Tier-Gate helpers (see docs/ZONE_TIER_GATE.md) ──
# A module's effective tier = power_tier when set (exotic weapons like cryo_lance,
# whose `zone` is the unlock zone, not the power band), else its `zone`.
func get_module_tier(module_id: String) -> int:
	var m = modules.get(module_id, {})
	return int(m.get("power_tier", m.get("zone", 0)))

# v115: HONEST tier wall. A module's penetration vs a tier_hardened: z enemy is a
# GRADUATED curve on the tier deficit -- readable as a penetration-vs-armor mismatch
# (the cards show the numbers), not an arbitrary binary flag, and tunable hard<->soft
# with ONE knob. Replaces the old all-or-nothing x TIER_FLOOR floor.
#   eff_tier = get_module_tier (+1 if Unique -- superior penetration, the skip-key)
#   deficit  = z - eff_tier
#   deficit <= 0 -> 1.0 (tier-matched or better: full effect)
#   deficit >= 1 -> TIER_PEN_PER_TIER ^ deficit, floored at TIER_PEN_FLOOR
# TIER_PEN_PER_TIER IS the hard<->soft dial: 0.15 = HARD (1 under -> 15%, 2 -> 2.25%);
# 0.35 = medium; 0.55 = soft (1 under -> 55%, brute-forceable). Sim-tune, never hand-wave.
const TIER_PEN_PER_TIER := 0.15
const TIER_PEN_FLOOR := 0.02
func module_tier_penetration(module_id: String, z: int) -> float:
	if z <= 0:
		return 1.0
	var mt := get_module_tier(module_id)
	if get_module_rarity(module_id) == Rarity.UNIQUE:
		mt += 1   # Unique = superior penetration -> the one-zone jackpot skip-key
	var deficit := z - mt
	if deficit <= 0:
		return 1.0
	return max(TIER_PEN_FLOOR, pow(TIER_PEN_PER_TIER, deficit))

# Boolean form kept for UI badges / callers that just need "fully pierces?".
func module_pierces_tier(module_id: String, z: int) -> bool:
	return module_tier_penetration(module_id, z) >= 1.0

# Defensive half of the gate: the fraction of armor / shield retained vs a
# tier_hardened: z enemy. Sub-tier ARMOR/SHIELD modules keep only `floor_f` (~0.02)
# of their stat; piercing ones keep all. Returned as multipliers so combat scales
# the FINAL sm.defense / sm.max_shield (preserving set/matrix/research bonuses
# proportionally) rather than re-deriving them. No armor/shield modules → 1.0
# (nothing to floor; bare hull base is not a gated module).
func get_tier_defense_factors(z: int, floor_f: float) -> Dictionary:
	if z <= 0:
		return {"def": 1.0, "shield": 1.0}
	var arm_full := 0.0
	var arm_keep := 0.0
	var sh_full := 0.0
	var sh_keep := 0.0
	for mid in loadout.values():
		if mid and mid in modules:
			var st = modules[mid].get("slot_type", "")
			# v115: graduated penetration, mirrors the offense wall (floor_f kept for
			# signature compat; the curve carries its own TIER_PEN_FLOOR).
			var f: float = module_tier_penetration(mid, z)
			if st == "armor":
				var d: float = modules[mid]["stats"].get("def", 0)
				arm_full += d
				arm_keep += d * f
			elif st == "shield":
				var s: float = modules[mid]["stats"].get("max_shield", 0)
				sh_full += s
				sh_keep += s * f
	return {
		"def": (arm_keep / arm_full) if arm_full > 0.0 else 1.0,
		"shield": (sh_keep / sh_full) if sh_full > 0.0 else 1.0,
	}

# v114: a module's effective craft cost. Injects the zone signature alloy for Z2-Z10
# common (no-rarity) weapon/armor/shield ONLY when the tier gate is on — so ungated /
# pre-feature saves keep their base costs and never need an alloy they can't craft.
# +5 weapon / +6 shield / +8 armor (Z4 reference; tune). Returns a copy (never mutates
# the module's stored cost). Use this everywhere a common module's cost is read.
func get_effective_module_cost(m_data: Dictionary) -> Dictionary:
	var base: Dictionary = (m_data.get("cost", {}) as Dictionary).duplicate()
	if not bool(GameState.game_settings.get("tier_gate_enabled", false)):
		return base
	var z: int = int(m_data.get("zone", 0))
	var st: String = str(m_data.get("slot_type", ""))
	if z >= 2 and z <= 10 and (st == "weapon" or st == "armor" or st == "shield") and not m_data.has("rarity"):
		var alloy: String = str(TIER_ALLOY_BY_ZONE.get(z, ""))
		if alloy != "":
			var qty: int = 8 if st == "armor" else (6 if st == "shield" else 5)
			base[alloy] = int(base.get(alloy, 0)) + qty
	return base

# v71.5: Check if module can be equipped (Prerequisite check)
# Returns: {"can_equip": bool, "reason": String}
func can_equip_module(module_id: String) -> Dictionary:
	var m = modules.get(module_id, {})
	if not m:
		# Check if it's an ammo or consumable
		var is_ammo = module_id in ElementDB.CATEGORIES.get("ammo", [])
		var is_consumable = module_id in ElementDB.CATEGORIES.get("consumables", [])
		
		if is_ammo or is_consumable:
			var req = ELEMENT_RESEARCH_REQS.get(module_id, "")
			if req != "" and GameState.research_manager and not GameState.research_manager.is_tech_unlocked(req):
				var tech_name = GameState.research_manager.tech_tree.get(req, {"name": req}).get("name", req)
				return {"can_equip": false, "reason": "Requires Research: " + tech_name}
			return {"can_equip": true, "reason": ""}
			
		return {"can_equip": false, "reason": "Module not found"}
	
	var req = m.get("research_req", "")
	
	# If it's a dropped module, check the base module's requirement too
	if m.get("is_custom") and m.has("base_module"):
		var base_id = m["base_module"]
		var base_data = modules.get(base_id, {})
		if base_data.has("research_req"):
			req = base_data["research_req"]
	
	if req != "" and not GameState.research_manager.is_tech_unlocked(req):
		# Get human readable tech name
		var tech_name = GameState.research_manager.tech_tree.get(req, {"name": req}).get("name", req)
		return {"can_equip": false, "reason": "Requires Research: " + tech_name}
		
	return {"can_equip": true, "reason": ""}

# v71.0: Roll rarity tier for a combat drop
func roll_rarity(is_boss: bool = false) -> int:
	var roll = randf()

	# v136 rebalance prototype (was v82.0's flat 4/26/70 trash · 15/35/50 boss,
	# no Common floor, UNIQUE unreachable). Goals: make Rare genuinely rare, and
	# make UNIQUE a boss-only jackpot (roll_rarity previously capped at Legendary
	# so Unique never dropped from any enemy). Measured in rarity_drop_spike.
	if is_boss:
		# Bosses are the reward moment: no junk floor, and the ONLY source of
		# Unique. Unique 3% / Legendary 15% / Rare 30% / Uncommon 52%.
		if roll < 0.03:
			return Rarity.UNIQUE
		elif roll < 0.18:
			return Rarity.LEGENDARY
		elif roll < 0.48:
			return Rarity.RARE
		else:
			return Rarity.UNCOMMON

	# Trash: Common is the ~50% "EMPTY" roll — combat's _roll_one_module_drop
	# skips it, so nothing drops (Common modules never enter inventory; still
	# crafting-only per v82.0). Real modules land only on Uncommon+, which halves
	# effective drop frequency AND makes Rare+ earned. Never Unique.
	# Legendary 3% / Rare 8.5% / Uncommon 38.5% / Common(empty) 50%.
	if roll < 0.03:
		return Rarity.LEGENDARY
	elif roll < 0.115:
		return Rarity.RARE
	elif roll < 0.50:
		return Rarity.UNCOMMON
	else:
		return Rarity.COMMON

# v71.2: Sell module for credits -> v100: Demolish for credits + SpareParts
const RARITY_SELL_PRICES = {
	Rarity.COMMON: 100,
	Rarity.UNCOMMON: 750,
	Rarity.RARE: 5000,
	Rarity.LEGENDARY: 30000,
	Rarity.UNIQUE: 100000,
}

const RARITY_SPARE_PARTS = {
	Rarity.COMMON: 1,
	Rarity.UNCOMMON: 3,
	Rarity.RARE: 8,
	Rarity.LEGENDARY: 25,
	Rarity.UNIQUE: 75,
}

func get_sell_price(module_id: String) -> int:
	var m = modules.get(module_id, {})
	# v127: stone-crafted modules demolish for a token only (see demolish_module) — report 0.
	if m.get("stone_crafted", false):
		return 0
	# Crafted modules: sell for 25% of credit cost
	var cost_credits = m.get("cost", {}).get("credits", 0)
	if cost_credits > 0:
		return max(50, int(cost_credits * 0.25))
	# Dropped modules: rarity price SCALED BY ZONE (v137 #32). Flat rarity pricing let a
	# strong player farm a one-shot low boss for frontier-equivalent Liras + prestige
	# (bosses re-target instantly; ~28k/burst identical at Z1 and Z10). A Z-N module now
	# sells for N/10 of the top-tier value — low-tier modules ARE worth less, and the
	# frontier (Z10, ×1.0) stays full. Kills the farm-down credit/prestige leak.
	var rarity = m.get("rarity", Rarity.COMMON)
	var zone_f: float = maxf(0.1, float(m.get("zone", 1)) / 10.0)
	return int(RARITY_SELL_PRICES.get(rarity, 100) * zone_f)

func get_demolish_parts(module_id: String) -> int:
	var m = modules.get(module_id, {})
	var rarity = m.get("rarity", Rarity.COMMON)
	return RARITY_SPARE_PARTS.get(rarity, 1)

func demolish_module(module_id: String) -> bool:
	if module_id not in module_inventory or module_inventory[module_id] <= 0:
		return false
	# v127 review #1: stone-crafted modules can't be a Lira/SpareParts/salvage faucet.
	# A cheap Common crafted to high rarity would otherwise demolish for MORE than the
	# craft cost AND inflate lifetime_credits -> prestige. Token salvage (1 part) only.
	if modules.get(module_id, {}).get("stone_crafted", false):
		var sp_stone := get_demolish_parts(module_id)   # v140: rarity-scaled (was flat 1); compute BEFORE erase
		module_inventory[module_id] -= 1
		if module_inventory[module_id] <= 0:
			module_inventory.erase(module_id)
			if module_id in custom_modules:
				custom_modules.erase(module_id)
				modules.erase(module_id)
		GameState.resources.add_element("SparePart", sp_stone)
		inventory_updated.emit()
		return true

	var price = get_sell_price(module_id)
	var parts = get_demolish_parts(module_id)
	
	var m = modules.get(module_id, {})
	var rarity = m.get("rarity", Rarity.COMMON)
	var zone = m.get("zone", 1)
	
	module_inventory[module_id] -= 1
	if module_inventory[module_id] <= 0:
		module_inventory.erase(module_id)
		# Clean up custom modules
		if module_id in custom_modules:
			custom_modules.erase(module_id)
			modules.erase(module_id)
	
	# v140: modules no longer sell for Liras — recycle yields Spare Parts only (rarity-scaled).
	GameState.resources.add_element("SparePart", parts)
	
	# v101: Zone-specific salvage return based on rarity and zone tier
	if rarity > Rarity.COMMON:
		var salvage_amt = rarity - Rarity.COMMON # 1 to 4 depending on rarity
		var salvage_item = ""
		if zone == 1: salvage_item = "MiteChitin"
		elif zone == 2: salvage_item = "PirateSalvage"
		elif zone == 3: salvage_item = "MartianRelics"
		elif zone == 4: salvage_item = "CryoEssence"
		elif zone == 5: salvage_item = "XenoFragment"
		
		if salvage_item != "":
			GameState.resources.add_element(salvage_item, salvage_amt)

	inventory_updated.emit()
	return true

# ── Bulk Demolish (QoL: Scrap All Commons / Scrap Junk) ──
# Demolishes every NON-EQUIPPED module at or below max_rarity.
# Returns the count of modules scrapped.
func bulk_demolish_by_rarity(max_rarity: int) -> int:
	var equipped_ids = {}
	for slot in loadout:
		var mid = loadout[slot]
		if mid: equipped_ids[mid] = true
	# Collect candidates first (don't mutate while iterating)
	var candidates: Array = []
	for mid in module_inventory.keys():
		if equipped_ids.has(mid): continue
		if get_module_rarity(mid) > max_rarity: continue
		candidates.append(mid)
	var count = 0
	for mid in candidates:
		var qty = module_inventory.get(mid, 0)
		for i in range(qty):
			if demolish_module(mid):
				count += 1
	return count

func count_demolish_candidates_by_rarity(max_rarity: int) -> int:
	var equipped_ids = {}
	for slot in loadout:
		var mid = loadout[slot]
		if mid: equipped_ids[mid] = true
	var n = 0
	for mid in module_inventory.keys():
		if equipped_ids.has(mid): continue
		if get_module_rarity(mid) > max_rarity: continue
		n += module_inventory.get(mid, 0)
	return n

# ── Loadout Presets (QoL: Save/Load build) ──
# v139c: base module TYPE of any id — a base id maps to itself; a custom instance
# to its base_module (with a string-parse fallback for a stale custom id no longer
# in `modules`). Used to match a churned preset id to an owned equivalent.
func _module_base_id(mid: String) -> String:
	if mid in modules:
		return String(modules[mid].get("base_module", mid))
	if mid.begins_with("custom_"):
		var parts: PackedStringArray = mid.trim_prefix("custom_").split("_")
		while parts.size() > 1 and parts[parts.size() - 1].is_valid_int():
			parts.remove_at(parts.size() - 1)
		return "_".join(parts)
	return mid

# v139c: an OWNED module id equivalent to `mid` (same base type), for preset
# application after the base→custom id churn. Prefers an exact-rarity match, else
# the best-rarity owned instance of that type; "" if none owned.
func _resolve_owned_equivalent(mid: String) -> String:
	var want_base: String = _module_base_id(mid)
	var want_rar: int = int(modules.get(mid, {}).get("rarity", 0))
	var best := ""
	var best_rar := -1
	for owned_id in module_inventory:
		if int(module_inventory[owned_id]) <= 0:
			continue
		if _module_base_id(String(owned_id)) != want_base:
			continue
		var orar: int = int(modules.get(owned_id, {}).get("rarity", 0))
		if orar == want_rar:
			return String(owned_id)
		if orar > best_rar:
			best = String(owned_id)
			best_rar = orar
	return best

func save_loadout_preset(idx: int) -> bool:
	if not idx in loadout_presets: return false
	var preset = loadout_presets[idx]
	# Deep copy of current state
	preset["loadout"] = loadout.duplicate(true)
	preset["ammo_loadout"] = ammo_loadout.duplicate(true)
	preset["consumable_hull"] = consumable_hull_slot
	preset["consumable_shield"] = consumable_shield_slot
	if preset["name"] == "":
		preset["name"] = "Build %d" % idx
	inventory_updated.emit()
	return true

func load_loadout_preset(idx: int, from_combat_swap: bool = false) -> Dictionary:
	# v134g: this is now "SWITCH to build slot idx". Applying a slot must NOT
	# auto-save (its own equips would clobber the slot mid-apply), and it sets the
	# slot as the active edit target. An EMPTY slot is a valid switch — the ship is
	# stripped to an empty hull, ready to build fresh (the auto-save then persists
	# each equip back into this slot).
	# Returns: {"loaded": int, "skipped": int}
	if not idx in loadout_presets: return {"loaded": 0, "skipped": 0}
	# v139e: the live ship IS the combat ship. Switching build slots strips + re-equips
	# it, which desyncs an ACTIVE fight's weapon snapshot — weapons then fire against the
	# new build's ammo map and read empty ("NO AMMO" on a ship that owns ammo). The ONLY
	# sanctioned mid-fight swap is the Combat screen's loadout bar, which routes through
	# swap_loadout_in_combat (from_combat_swap=true) and rebuilds the snapshot. A
	# designer-side switch during combat must NOT reach into the fighting ship.
	# Owner: "separate these."
	if not from_combat_swap and GameState.combat_manager and GameState.combat_manager.in_combat:
		return {"loaded": 0, "skipped": 0, "blocked": true}
	var preset = loadout_presets[idx]
	var was_suppressed := _suppress_preset_autosave
	_suppress_preset_autosave = true

	# v140: switching to an EMPTY build slot INHERITS the current ship instead of
	# stripping to a bare hull — a variant build keeps the shared defense / armor /
	# engine / battery / consumable kit, and the player only swaps the weapons. Was: a
	# mission-follower (LOADOUT 2 = energy, LOADOUT 3 = explosive) left every non-weapon
	# slot empty in builds 2 & 3. Seed the target from the live loadout before the strip.
	if is_loadout_preset_empty(idx):
		preset["loadout"] = loadout.duplicate(true)
		preset["ammo_loadout"] = ammo_loadout.duplicate(true)
		preset["consumable_hull"] = consumable_hull_slot
		preset["consumable_shield"] = consumable_shield_slot

	# Step 1: Return every currently-equipped module to inventory. For an empty
	# slot this IS the whole switch — the player lands on a clean, empty ship.
	var slot_keys = loadout.keys().duplicate()
	for slot in slot_keys:
		if loadout.get(slot):
			unequip_slot(slot)

	# Step 2: Equip preset modules. equip_module handles inventory accounting,
	# slot-type validation, energy capacity, and research gates. Batteries
	# FIRST (establish capacity before consumers, else the per-step power check
	# rejects consumers against 0 capacity) and silently (internal bulk equip —
	# the returned loaded/skipped summary informs the player, not per-step
	# toasts).
	var loaded = 0
	var skipped = 0
	var _slot_order: Array = []
	for raw_slot in preset["loadout"]:
		var _bm = preset["loadout"][raw_slot]
		if _bm != null and _bm != "" and _bm in modules and modules[_bm].get("slot_type", "") == "battery":
			_slot_order.append(raw_slot)
	for raw_slot in preset["loadout"]:
		var _bm = preset["loadout"][raw_slot]
		if not (_bm != null and _bm != "" and _bm in modules and modules[_bm].get("slot_type", "") == "battery"):
			_slot_order.append(raw_slot)
	for raw_slot in _slot_order:
		var slot_idx = int(raw_slot)
		var mid = preset["loadout"][raw_slot]
		if mid == null or mid == "":
			continue
		# v139c: preset ids can churn — an equipped BASE module becomes a custom
		# instance on combat defeat (durability tracking), so a preset that still
		# stores the base id finds it gone (0 owned) and loads that slot EMPTY.
		# d620882 re-synced only the ACTIVE preset; the OTHER build still stored
		# base ids and wiped when the shared modules converted ("build 1 & 2
		# emptied after a defeat"). If the exact id isn't owned, equip an
		# equivalent OWNED module of the same base type so the build survives.
		var use_mid: String = String(mid)
		if int(module_inventory.get(use_mid, 0)) <= 0:
			use_mid = _resolve_owned_equivalent(use_mid)
		if use_mid != "" and equip_module(slot_idx, use_mid, true):
			loaded += 1
		else:
			skipped += 1

	# Step 3: Restore ammo loadout (only for slots that still have weapons equipped).
	for raw_slot in preset["ammo_loadout"]:
		var slot_idx = int(raw_slot)
		if slot_idx in loadout and loadout[slot_idx] != null and loadout[slot_idx] != "":
			ammo_loadout[slot_idx] = preset["ammo_loadout"][raw_slot]

	# Step 4: Restore consumables (only if the player still owns at least one).
	var hull_c = preset.get("consumable_hull", "")
	if hull_c != "" and GameState.resources and GameState.resources.get_element_amount(hull_c) > 0:
		consumable_hull_slot = hull_c
	else:
		consumable_hull_slot = ""

	var shield_c = preset.get("consumable_shield", "")
	if shield_c != "" and GameState.resources and GameState.resources.get_element_amount(shield_c) > 0:
		consumable_shield_slot = shield_c
	else:
		consumable_shield_slot = ""

	# v134g: an empty (or under-powered) slot must NOT strand the player on a dead,
	# unbuildable hull. Re-seat OWNED batteries into empty battery slots so the ship
	# can power the modules they're about to equip (e.g. the engine at the m007b
	# tutorial step). Only uses batteries the player already owns — never grants, so
	# there's no farm. Runs under the autosave-suppress guard, so an "empty" slot
	# stays empty in its saved preset until the first real edit.
	_ensure_powered_from_inventory()
	# v134g: this slot is now the live build; future edits auto-save here.
	active_preset_idx = idx
	_suppress_preset_autosave = was_suppressed
	recalc_stats()
	inventory_updated.emit()
	return {"loaded": loaded, "skipped": skipped}

# v134g: fill empty BATTERY slots from owned batteries (best-capacity first) so a
# switched-to slot is at least powerable. Never grants new batteries.
func _ensure_powered_from_inventory() -> void:
	if not active_hull in hulls:
		return
	var slots: Array = hulls[active_hull].get("slots", [])
	for i in range(slots.size()):
		if str(slots[i]) != "battery":
			continue
		if loadout.get(i):
			continue   # slot already has a battery
		var b := _best_owned_battery()
		if b == "":
			break   # own no more batteries to place
		equip_module(i, b, true)

func _preset_has_no_modules(preset: Dictionary) -> bool:
	# A preset is "empty" if every saved slot is null/empty — not just if the dict has no keys.
	# (Loadout dicts have keys for every slot, often with null values.)
	for k in preset.get("loadout", {}):
		var v = preset["loadout"][k]
		if v != null and v != "":
			return false
	return true

func clear_loadout_preset(idx: int) -> bool:
	if not idx in loadout_presets: return false
	loadout_presets[idx] = {"name": "", "loadout": {}, "ammo_loadout": {}, "consumable_hull": "", "consumable_shield": ""}
	inventory_updated.emit()
	return true

func is_loadout_preset_empty(idx: int) -> bool:
	if not idx in loadout_presets: return true
	return _preset_has_no_modules(loadout_presets[idx])

# ── Threshold Relic slot (NG+ P2 master key) ──
# v113: relics live in a dedicated single slot, separate from the hull grid.
# equip/unequip validate slot_type + ownership; the combat effect is read via
# get_relic_reduction_factor (applied to incoming damage in the keyed zone only).
func equip_relic(relic_id: String) -> bool:
	if not relic_id in modules: return false
	if modules[relic_id].get("slot_type", "") != "relic": return false
	if module_inventory.get(relic_id, 0) <= 0: return false
	equipped_relic = relic_id
	inventory_updated.emit()
	return true

func unequip_relic() -> void:
	if equipped_relic != "":
		equipped_relic = ""
		inventory_updated.emit()

# Incoming-damage multiplier from the equipped relic IN the given zone (1.0 = no
# effect). A relic only bites in its keyed zone, so it can't become a universal
# god-item — it's the farm-enabler for its tier's gate boss, nothing else.
func get_relic_reduction_factor(zone_id: String) -> float:
	if equipped_relic == "" or not equipped_relic in modules:
		return 1.0
	var r = modules[equipped_relic]
	if str(r.get("relic_zone", "")) != zone_id:
		return 1.0
	var red: float = clampf(float(r.get("relic_reduction", 0.0)), 0.0, 0.99)
	return 1.0 - red

func repair_module(slot_idx: int, cost_parts: int) -> bool:
	# v125: repair is Spare-Parts only (no Liras). Spare Parts come from demolishing
	# surplus modules — that's the maintenance sink that keeps worn gear alive.
	if GameState.resources.get_element_amount("SparePart") < cost_parts: return false

	var mid = loadout.get(slot_idx)
	if not mid or not mid.begins_with("custom_"): return false

	GameState.resources.remove_element("SparePart", cost_parts)

	modules[mid]["durability"] = 100
	if mid in custom_modules:
		custom_modules[mid]["durability"] = 100
	
	recalc_stats()
	inventory_updated.emit()
	return true
