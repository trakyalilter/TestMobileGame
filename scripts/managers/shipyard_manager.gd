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
#
# v156: SUPERSEDED by the banded curve below (compose_module_costs). The two
# constants are kept because the sim probes in scripts/sim/ reference them by
# name; nothing in the live cost path reads them any more.
const MODULE_COST_ZONE_BASE := 1.55
const MODULE_COST_FREE_ZONES := 2

# ═══════════════════════════════════════════════════════════════════════════
# v156 BANDED MODULE COST CURVE (owner, 2026-07-27)
#
# THE COMPLAINT: "z5 armor still wants steel of 100 — 100 steel is a few minutes
# crafting job." And: "later in the game ships become enormous intergalactic
# ships, so these will require toooo many factories to work to sustain them."
#
# THE MEASURED DIAGNOSIS (scripts/sim/nc_audit.gd on HEAD):
#   * One blunt exponential (1.55^(zone-2)) multiplied whatever the recipe
#     happened to mention. It landed on Steel/Ti — which infrastructure makes in
#     PARALLEL while the player does something else — and pinned the per-zone
#     signature alloy at a FLAT 5/6/8 from Z2 to Z10.
#   * The result was inverted AND non-monotone. Foundation cost measured in
#     building-minutes per module: armor 0.4, 0.6, 2.5, 7.6, 17.1, 28.9,
#     25.0 (DOWN at Z7), 1860 (x74 at Z8), 8120, 17455. z6_shield had ZERO.
#   * A tier-matched refit needed 0.02 buildings at Z1 and 1504 at Z10 — the
#     first is decorative, the second is unreachable (the diminishing-returns
#     tail caps a building type at knee+tail = 20 effective units).
#   * Serial processing, not infrastructure, was the real hidden wall:
#     the Z8 refit billed 87 HOURS of un-parallelisable recipe time.
#
# THE MODEL: a module cost is priced in TIME ON A PRODUCTION LINE, not in units.
# Each material's neutral reference rate (qty/interval*60 for a building,
# out/duration*60 for a recipe) converts a time budget into a quantity, so a
# cheap bulk metal and an expensive endgame condensate cost the same factory
# effort per line. Three bands, three different curves:
#
#   BAND 1 FOUNDATION — everything automatable AND AFFORDABLE AT THAT ZONE.
#     Budgeted in BUILDING-MINUTES, split across the module's infra-produced
#     materials plus that zone's ANCHORS (below) in proportion to INFRA DEPTH.
#     Parallelisable, so this is where volume lives — but v157 cut its Z10
#     budget to 0.55x because at v156 it was 70% of the felt cost of a refit
#     while the un-parallelisable bands were 30%. Steel belongs here.
#   BAND 1b SERIAL — materials no building produces (pure processing/gathering).
#     Budgeted in RECIPE-MINUTES on a much shallower curve, because this time
#     competes 1:1 with combat for the single active task.
#   BAND 2a ZONE SIGNATURE ALLOY — the TIER_ALLOY_BY_ZONE rung. Deliberately a
#     MILD ramp: one AeonAlloy costs 136 s of chained, un-parallelisable
#     processing (nine rungs at coefficient 1 — inviolable, see
#     processing_manager). Ramping it hard is a pure time tax, not pressure.
#   BAND 2b OWN-ZONE COMBAT SIGNATURE — the zone's own signature drop. THIS is
#     where band 2 ramps hard, because own-zone combat is what the player is
#     already doing, and (unlike an earlier zone's drop) it never propagates
#     backward. Rule: a zone-N recipe may demand plenty of zone N's own drops;
#     reaching BACK into a cleared zone's combat-only loot is now ZERO, not
#     small (v157/D4). Budgeted in KILLS against the measured per-kill drop
#     rate, so the same budget means the same grind whichever material it hits.
#   BAND 3 CREDITS — left at the authored ladder (measured: 55 M for a Z10 refit
#     against 5-50 B lifetime credits — not a binding sink), but LEVELLED across
#     the three weapon channels, which had a 1.25x explosive premium buying 0%
#     extra damage after the v155 channel flattening.
#
# THE COSTS ARE BAKED INTO modules[id]["cost"] by compose_module_costs(), not
# injected at read time. Four call sites read the raw dict (info_card.gd:171,
# atlas_page.gd:429, resources.gd:382, get_sell_price) and the old read-time
# alloy injection made all four under-report every Z2-Z10 weapon/armor/shield
# and list the nine signature alloys as having zero consumers. Baking is the
# single central fix. The composer is non-reentrant BY CONSTRUCTION: it composes
# from an authored snapshot, so calling it twice yields the identical dict.
# ═══════════════════════════════════════════════════════════════════════════
const COST_CURVE_MIN_ZONE := 1
const COST_CURVE_MAX_ZONE := 10
const COST_FOUNDATION_FREE_ZONES := 2      # Z1-Z2 keep their authored foundation

# Band 1 — building-minutes per module at Z3, geometric per zone after that.
# Sized so a tier-matched refit needs ~1.4 buildings/line at Z3 rising to ~100
# spread over 8+ distinct lines at Z10 (measured in nc_audit section [D]).
#
# v157 (D3): 24.0/1.65 measured band 1 at 69.6% of the felt cost of a Z10 refit
# against 10.3% for own-zone combat — the exponential was landing almost
# entirely on the one axis infrastructure parallelises. 15.0/1.63 puts the Z10
# band-1 budget at 0.55x its v156 value (806 -> 444 building-minutes for a
# weight-1.0 slot) while leaving Z3 near where it was after the onboarding ramp.
const COST_BMIN_Z3 := 20.5
const COST_BMIN_STEP := 1.63

# v157 (D2): the guided Z3 chain (m030fa/fb/f1) is MANDATORY before the
# Warmaster, and Z1-Z2 are authored-untouched at ~0.6 building-minutes. Going
# straight to the full band-1 budget at Z3 measured a x51 cliff in the armor
# line. This is an explicit onboarding ramp on the band-1 budget only — it does
# NOT raise Z1/Z2 and it is gone by Z5.
const COST_BMIN_RAMP := {3: 0.455, 4: 0.78, 7: 2.4, 8: 3.0, 9: 5.5}
# v161: Z7-Z9 lifted. The factory tier ADDED anchors at those zones, and band 1
# splits one budget across them -- so every pre-existing anchor (AdvCircuit above
# all, the Au->Dirt/Water and Wood->C engine) got a thinner slice and transitive
# early-root tonnage FELL at Z7-Z9 versus the pre-tier state, which inverts the
# owner rule that early materials must matter MORE late, not less. More anchors
# needs a bigger budget, not a thinner split. Z10 needed no lift: its own new
# anchors are deep enough to pull tonnage on their own.

# v157 (D1): band 1 is split across the module's automatable materials weighted
# by INFRA DEPTH — the length of the shortest input chain from the material back
# to a zero-input root. A zero-input drill (uranium_centrifuge, tungsten_drill,
# osmium_condenser, void_anchor) is depth 0: one click, no upstream factory, it
# pulls nothing forward. At v156 those drills carried 74.8% of the Z10 refit's
# building-equivalents, so the endgame bill got SHALLOWER as it grew. Weighting
# the split by (1 + 0.9 * depth) makes the deep chains — AdvCircuit at depth 4
# reaches back through Semiconductor / StructuralComponent to Fe, Si, C, Cu, Li
# — carry the volume, which serves the cumulative rule at the same time.
const COST_DEPTH_WEIGHT := 0.9

# Band 1b — serial recipe-minutes per module. Much shallower: this is the
# single-active-task clock, and HEAD's 87-hour Z8 refit is what happens without
# a leash on it.
const COST_SMIN_Z3 := 2.5
const COST_SMIN_STEP := 1.12

# Per-slot share of the zone budget. Combat gear carries the cost; utility slots
# are deliberately lighter so a refit is not six identical bills.
const COST_SLOT_WEIGHT := {
	"armor": 1.30, "shield": 1.10, "weapon": 1.00,
	"engine": 0.50, "battery": 0.50, "sensor": 0.50,
}

# Band 2a — signature alloy. Base == the shipped flat values, so Z2 is unchanged.
const COST_ALLOY_BASE := {"armor": 8, "shield": 6, "weapon": 5}
const COST_ALLOY_STEP := 1.05

# Band 2b — the zone's own signature combat drop. Every Z2-Z10 module pays it.
const COST_ZONE_DROP := {
	2: "PirateSalvage", 3: "MartianRelics", 4: "RimeplateScrap", 5: "XenoFragment",
	6: "ColonySalvage", 7: "ExoticIsotope", 8: "AntimatterParticle",
	9: "BiohazardSample", 10: "AeonResiduum",
}

# v157 (D3): band 2b is now budgeted in KILLS, not units. The v156 split divided
# a unit budget equally across the module's own-zone drops with no reference to
# how often each one drops — z8_armor asked for Diamond 13 (0.73/kill = 18
# kills) AND AntimatterParticle 13 (8.4/kill = 2 kills). Same number, nine times
# the grind. A kill budget means the same thing whichever material it lands on.
#
# Each own-zone material gets the SAME kill budget rather than a share of one,
# because own-zone drops all fall off the same enemies simultaneously: one kill
# advances every line at once, so adding a material adds breadth at no time
# cost. The module's real combat price is therefore K kills, not n x K.
#
# Base is the Z2 kill budget per module; 1.42 per zone. Measured: this leaves Z3
# at 23 min of kills for a full destroyer refit (v156: 24) and takes Z10 from
# 264 min to ~511 min, moving own-zone combat from 10.3% to ~25% of felt refit
# time. It is deliberately NOT pushed to parity with band 1 — combat cannot be
# parallelised, so every minute here is exclusive active time, and 8.5 h for a
# full 26-slot Z10 refit is already the ceiling the dwell time can absorb.
const COST_OWNC_KILLS := {
	"armor": 1.6, "shield": 1.4, "weapon": 1.2, "engine": 0.8, "battery": 0.8, "sensor": 0.8,
}
const COST_OWNC_STEP := 1.42

# v157 (D4): an EARLIER zone's combat-only drop can never appear at all. The
# v156 clamp at 6 units still LEFT the line in place (z9_battery kept Diamond 2,
# and Diamond drops only in Zone 8 — a titan hull's five battery slots billed
# ~308 backward Zone-8 kills). Backward combat lines are now dropped outright
# and their weight is carried by the zone's own drop, which is added
# unconditionally below.
const COST_BACK_COMBAT_DROP := true

# Band 1c COMPOSITE — a material a building yields but whose production chain is
# transitively fed by an ENEMY DROP. Measured: primordial_extractor burns 1.5
# Diamond + 2.5 PrimordialShard per 0.1 PrimordialMatrix, and QuantumCore is
# 5 VoidArtifact each. Those lines LOOK parallelisable and are not — you cannot
# kill fast enough to feed fourteen of them, and pricing them by building-minutes
# is what let HEAD bill 1,335 PrimordialMatrix and 34,385 units of backward
# combat loot for a Z10 refit. Priced like the signature alloy instead: a fixed,
# mildly-ramping per-slot quantity, never a bulk term.
# Step and base are held down by MEASUREMENT, not taste: composites are made by
# slow recipes (StructuralLattice 2/min, PrimordialMatrix 0.67/min), so their
# count converts straight into single-active-task minutes. At base 12 / step 1.25
# the Z8 refit measured 13.1 h of serial time; these values put it at ~4 h.
const COST_COMPOSITE_BASE := {
	"armor": 8, "shield": 7, "weapon": 6, "engine": 4, "battery": 4, "sensor": 4,
}
const COST_COMPOSITE_STEP := 1.18

# Band 1 breadth anchor: the automatable materials EVERY module of a zone must
# buy, so each zone forces production lines the previous zone did not.
#
# v157 (D1): the v156 anchors were Z7 Os, Z9 W, Z10 U — osmium_condenser,
# tungsten_drill and uranium_centrifuge all have NO input key. Anchoring the
# endgame on zero-input drills made the Z9/Z10 bill 75% depth-0: it grew without
# ever branching. Re-pointed onto existing DEEP materials only, chosen so each
# zone opens buildings the previous one did not AND the late zones reload an
# earlier zone's line at a much larger scale (the cumulative rule):
#
#   Z3  Steel               d2  auto_smelter <- Fe, C, O
#   Z4  Circuit             d3  electronics_assembler <- Si, Cu, Resin
#   Z5  Superalloy          d3  superalloy_forge <- Steel, Ni, Cr, Ti
#   Z6  AdvCircuit          d4  adv_circuit_foundry <- Semiconductor, Au, StructuralComponent
#   Z7  Semiconductor + Graphite      d3 / d2   (new: germanium chain, auto_press)
#   Z8  StructuralComponent + Steel   d3 / d2   (new: structural_press; reloads Z3)
#   Z9  Chip + Superalloy             d3 / d3   (new: chip_fab, au_refinery; reloads Z5)
#   Z10 AdvCircuit + StructuralComponent d4/d3  (reloads Z6 and Z8 at endgame scale)
#
# Nothing new was invented: every one of these already had a building and an
# under-used consumer list. Re-pointing beats inventing, and element_db is
# untouched.
# v158 (E1): re-pointed again so EVERY anchor clears its zone's minimum direct
# depth (COST_MIN_DIRECT_DEPTH below) and each zone opens buildings the previous
# ones did not. Depths are the measured rule depth, not an assertion:
#
#   Z3  Steel                            d2   auto_smelter
#   Z4  Circuit + StructuralComponent    d3   electronics_assembler, structural_press
#   Z5  Superalloy + Chip                d3   superalloy_forge, chip_fab, Ni/Cr/Ti lines
#   Z6  AdvCircuit + NanoSubstrate       d4   adv_circuit_foundry, bauxite/dolomite
#   Z7  AdvCircuit + IrPlate + CompositeWeave  d4/d3/d3   iridium_drill, composite_loom
#   Z8  AdvCircuit + TargetingChip + PtCatalyst d4/d5/d5  platinum_drill; RELOADS Steel+Circuit
#   Z9  AdvCircuit + NeutroniumPlate + NanoSubstrate d4/d4/d4 neutronium_condenser,
#                                        osmium_condenser; RELOADS Superalloy -> Steel
#   Z10 AdvCircuit + VoidLattice + TargetingChip + NeutroniumPlate
#                                        d4/d5/d5/d4  void_anchor, void_crystallizer
#
# TargetingChip (AdvCircuit 3 + Steel 20 + Circuit 10) and NeutroniumPlate
# (Superalloy 5 -> Steel 20) are the cumulative rule made mechanical: the Z3 Steel
# line and the Z4 Circuit line are reloaded at endgame scale WITHOUT either
# material ever being named directly in a Z8-Z10 recipe.
# v160 (ENDGAME_FACTORY_TIER): the Capital Fabrication Chain ends the five-zone
# AdvCircuit monoculture. Z7-Z10 re-anchor onto the new d3-d8 spine, every rung
# building-produced (carbide_sintering_press / lattice_mill / bus_assembly_hall /
# capital_spar_works / frame_yard) AND recipe-backed (Section I Defect-1: each
# new material keeps a slow escape-hatch recipe, so the serial fallback at the
# elif below is live for all of them — acceleration, never access).
#   Z7  AdvCircuit + CompositeWeave + SinteredCarbide   d4/d3/d3  (IrPlate -> SinteredCarbide)
#   Z8  StainlessSteel + NanoSubstrate + TargetingChip + PrecisionLattice  d4/d4/d5/d5
#   Z9  PrecisionLattice + FabricationBus + VoidLattice  d5/d6/d6
#   Z10 DreadnoughtFrame + CapitalSpar + VoidLattice  d8/d7/d6
# NeutroniumPlate (d4) left the Z9/Z10 anchor rows because the floors below rose
# past it; it is still bought transitively (frame_yard NeutroniumPlate 3/frame)
# and via the Superalloy -> NeutroniumPlate -> DreadnoughtFrame lift chain.
# PtCatalyst (d5, serial) likewise left Z10: the anchor loop floor-checks every
# anchor, so a d5 entry under a floor of 6 would be dead text, not a line.
const COST_ZONE_ANCHOR := {
	3: ["Steel"],
	4: ["Circuit", "StructuralComponent", "Steel"],
	5: ["Superalloy", "StructuralComponent", "Chip", "Graphite"],
	6: ["AdvCircuit", "NanoSubstrate"],
	7: ["AdvCircuit", "CompositeWeave", "SinteredCarbide"],
	8: ["AdvCircuit", "StainlessSteel", "NanoSubstrate", "TargetingChip", "PrecisionLattice", "DiamondWafer"],
	9: ["AdvCircuit", "TargetingChip", "PrecisionLattice", "FabricationBus", "VoidLattice", "SuperiorCircuit"],
	10: ["AdvCircuit", "NeutroniumPlate", "DreadnoughtFrame", "CapitalSpar", "VoidLattice", "SuperiorCircuit"],
}

# ═══════════════════════════════════════════════════════════════════════════
# v158 MIN-DIRECT-DEPTH RULE (owner, 2026-07-27)
#
# THE RULING, verbatim: "first resources must matter late means it has to be a
# sub item of a sub item kinda thing. dont use directly dirt iron at zone 8 craft
# recipe for example."
#
# So an early material must matter TRANSITIVELY — pulled in through the chain —
# and must NOT appear as a DIRECT line in a late recipe. The measured violation
# on v157: z8_armor named Steel 2,244, z9_armor Steel 2,518, z10_armor Steel
# 4,188 and z10_kinetic Steel 3,222. Steel is a Zone-3-tier material at rule
# depth 2.
#
# THE RULE: a zone-N module may only NAME a foundation material whose rule depth
# is at least COST_MIN_DIRECT_DEPTH[N]. Anything shallower is re-pointed onto a
# deeper item that consumes it (COST_DEPTH_LIFT), so the early material is still
# bought — through the chain, in larger quantity, dragging its whole subtree.
#
# THE RULE ONLY GOVERNS BANDS 1 AND 1b (the bulk automatable / serial lines).
# It cannot govern the other bands and must not:
#   band 2a  the zone SIGNATURE alloy is the zone's own tier material;
#   band 2b  the zone's OWN combat drop is by definition not an early material;
#   band 1c  combat-fed composites are already priced as fixed gate quantities.
#
# WHY IT MAKES RULE 1 STRONGER RATHER THAN WEAKER. Band 1 is budgeted in
# BUILDING-MINUTES, and the budget does not change. Deep items run at a similar
# per-building rate to shallow ones but each unit carries an order of magnitude
# more early material, so the same factory-time budget buys far MORE transitive
# early demand. Measured, early-root units per building-minute:
#     Steel        30/min x  1 Fe/unit  =   30 Fe per building-minute
#     Superalloy   12/min x  4 Steel    =   48 Steel   (-> 48 Fe)
#     StructuralComponent 12/min x 10 Fe = 120 Fe
#     AdvCircuit 14.4/min x 20 Fe/unit  =  288 Fe per building-minute
# Forbidding the shallow line and spending the same minutes deeper is a ~10x
# increase in transitive Fe, not a decrease.
#
# THE LADDER, DERIVED FROM WHAT ACTUALLY EXISTS AT EACH DEPTH (census in
# scripts/sim/dr_audit.gd section [1]/[1b]):
#   d1  Fe Si C Ti Au Li O H Germanium VoidCrystal Al          (13 materials)
#   d2  Steel Cu Ni Co Zn Sn Semiconductor Graphite Cr Resin Fiber Mg (12)
#   d3  Circuit Superalloy StructuralComponent Chip CompositeWeave IrPlate
#       GalvanizedSteel Hydraulics Seal StainlessSteel SuperconductingMagnet (~14)
#   d4  AdvCircuit NanoSubstrate NeutroniumPlate  (+ combat-fed AICore/ReactiveCore)
#   d5  TargetingChip PtCatalyst VoidLattice      (+ combat-fed OmegaComposite,
#                                                    StructuralLattice, OsCore)
# THE FLOOR IS CAPPED AT 3, AND THAT CAP IS A MEASUREMENT, NOT A PREFERENCE.
#   * The CLEAN, non-combat-fed, BUILDING-produced tree tops out at AdvCircuit
#     (d4). omega_foundry, primordial_extractor and bioreactor_vat are all
#     combat-fed, so there is no parallelisable d5 at all. A floor of 5 would
#     empty band 1 and dump the whole budget onto serial recipes — the 87-hour
#     Zone-8 refit v157 had to fix.
#   * A floor of 4 was BUILT AND MEASURED first, and it severs the Steel line.
#     AdvCircuit is the only clean d4 building material and adv_circuit_foundry
#     takes Semiconductor / Au / StructuralComponent — no Steel. Every d>=4 item
#     that DOES consume Steel (TargetingChip, NeutroniumPlate) is a serial
#     recipe, and the serial band is deliberately tiny. Measured transitive Steel
#     per full Zone-10 refit: authored HEAD 14,920 -> floor 4: 4,748 (-68%,
#     auto_smelter goes idle at the endgame) -> floor 3: 77,168 (+417%).
#     Superalloy (d3, superalloy_forge <- Steel 4 at 12/min = 48 Steel per
#     building-minute) is the only thing that keeps the Zone-3 smelter line
#     load-bearing at Zone 10, and it is legal only at floor 3.
# So the floor rises 1 -> 2 -> 3 and stops. The ladder keeps CLIMBING past that
# through the per-zone ANCHORS, which are d4/d5 from Zone 6 up: measured MEAN
# direct depth per zone is 2.0 (Z3) 2.6 (Z4) 2.9 (Z5) 3.7 (Z6) 3.3 (Z7) 4.1 (Z8)
# 4.1 (Z9) 4.3 (Z10). Nothing raw is ever named late: Fe, Si, C, Ti, Cu, Au and
# every zero-input drill (Mn, Os, Ir, W, U, Neutronium, VoidEssence) are illegal
# as DIRECT lines from Zone 5 on, and Steel from Zone 7 on.
#
# v160 (ENDGAME_FACTORY_TIER): BOTH premises of the cap-at-3 measurement are now
# false, so the floor finally rises at Z8-Z10 — that rise is the acceptance test
# for the whole Capital Fabrication Chain:
#   * "the clean building-produced tree tops out at AdvCircuit (d4)" — no longer:
#     lattice_mill (PrecisionLattice d5), bus_assembly_hall (FabricationBus d6),
#     capital_spar_works (CapitalSpar d7) and frame_yard (DreadnoughtFrame d8)
#     are all non-combat-fed industry buildings with escape-hatch recipes.
#   * "a floor of 4 severs the Steel line" — no longer: the lift chain now runs
#     Steel -> Superalloy -> NeutroniumPlate -> DreadnoughtFrame, and the frame
#     physically consumes Steel through GalvanizedSteel (24/frame via the spar
#     line) and Superalloy (via neutronium_press). Measured transitive roots per
#     Z10 refit RISE versus the floor-3 state (see the v160 measurement sweep).
const COST_MIN_DIRECT_DEPTH := {
	3: 1, 4: 1, 5: 2, 6: 2, 7: 3, 8: 4, 9: 5, 10: 6,
}

# Expected processing level at each zone, taken from the SHIPPED alloy ladder
# (refine_wreckforged_alloy lvl 25 at Z3, refine_rime_alloy 35 at Z4,
# refine_xenoforged_alloy 45 at Z5, ...). Used only to decide whether a lift
# target is craftable when the player arrives — rule 4, nothing may be
# unbuildable when its zone unlocks.
const COST_ZONE_PROC_LEVEL := {
	1: 5, 2: 15, 3: 25, 4: 35, 5: 45, 6: 55, 7: 65, 8: 75, 9: 85, 10: 95,
}

# Shallow material -> ordered preference of DEEPER items that consume it. The
# lift is recursive: if the first candidate is itself below the floor, the search
# continues through that candidate's own lift list, so Fe -> Steel -> Superalloy
# -> NeutroniumPlate all fall out of one table.
#
# Every pair here was checked against the live recipe/building input lists, so
# the deep item genuinely buys the shallow one:
#   Steel      -> superalloy_forge Steel 4 | galvanize_steel Steel 2
#                 | craft_turret_targeting Steel 20
#   Fe         -> auto_smelter Fe 2.5 | structural_press Fe 10 | craft_stainless_steel Fe 5
#   Si         -> semiconductor_furnace Si 3 | structural_press Si 5 | craft_platinum_catalyst Si 50
#   Cu         -> electronics_assembler Cu 2.5 | structural_press Cu 5 | craft_magnet Cu 10
#   C          -> auto_press C 4.2 | auto_smelter C 1.3 | structural_press C 3
#   Superalloy -> refine_neutronium_plate Superalloy 5
#   Circuit    -> craft_turret_targeting Circuit 10
#   Os         -> refine_neutronium_plate Os 2
#   VoidCrystal-> weave_void_lattice VoidCrystal 6
# An empty list means "no deeper consumer exists in the game" — the line is then
# DROPPED rather than kept shallow, and its budget flows to the zone's anchors.
const COST_DEPTH_LIFT := {
	"Dirt": ["Fe", "C"],
	"Water": ["Fe", "O"],
	"Wood": ["C"],
	"Fe": ["Steel", "StructuralComponent", "StainlessSteel", "AdvCircuit"],
	"Si": ["Semiconductor", "Chip", "StructuralComponent", "AdvCircuit", "PtCatalyst"],
	"C": ["Graphite", "Steel", "StructuralComponent", "AdvCircuit"],
	"Cu": ["Circuit", "StructuralComponent", "SuperconductingMagnet", "AdvCircuit"],
	"Ti": ["Superalloy", "IrPlate", "NeutroniumPlate"],
	"Au": ["Chip", "AdvCircuit"],
	"Li": ["StructuralComponent", "AdvCircuit"],
	"O": ["Steel", "Resin"],
	"H": ["Resin", "Circuit"],
	"N": ["Chip", "AdvCircuit"],
	"Al": ["Cr", "StainlessSteel", "NanoSubstrate"],
	"Mg": ["NanoSubstrate"],
	"Ag": ["AdvCircuit"],
	"Sn": ["AdvCircuit", "SuperconductingMagnet"],
	"Zn": ["GalvanizedSteel"],
	"Cr": ["Superalloy", "StainlessSteel", "NeutroniumPlate"],
	"Ni": ["Superalloy", "StainlessSteel", "NanoSubstrate"],
	"Co": ["Superalloy"],
	"Resin": ["Circuit", "Seal", "CompositeWeave"],
	"Fiber": ["CompositeWeave"],
	"Quartz": ["Si"],
	"Malachite": ["Cu"],
	"Steel": ["Superalloy", "GalvanizedSteel", "Hydraulics", "TargetingChip", "NeutroniumPlate"],
	"Semiconductor": ["Chip", "AdvCircuit"],
	"Graphite": ["IrPlate"],
	"Circuit": ["TargetingChip"],
	"Superalloy": ["NeutroniumPlate", "TargetingChip"],
	"StructuralComponent": ["AdvCircuit", "NanoSubstrate"],
	"Ir": ["IrPlate"],
	"W": ["IrWAlloy"],
	"Os": ["NeutroniumPlate", "OsCore"],
	"Neutronium": ["NeutroniumPlate"],
	"VoidCrystal": ["VoidLattice"],
	"VoidEssence": ["VoidCrystal", "VoidLattice"],
	"Pt": ["PtCatalyst"],
	"PtOre": ["Pt"],
	"Germanium": ["Semiconductor"],
	"StainlessSteel": ["NanoSubstrate", "PrecisionLattice"],
	"GalvanizedSteel": ["AdvCircuit", "CapitalSpar"],
	"Hydraulics": ["AdvCircuit"],
	"IrPlate": ["AdvCircuit"],
	"CompositeWeave": ["AdvCircuit", "CapitalSpar"],
	"Chip": ["AdvCircuit"],
	"SuperconductingMagnet": ["AdvCircuit"],
	"Seal": ["AdvCircuit"],
	# v160 (ENDGAME_FACTORY_TIER): the Capital Fabrication Chain extends the lift
	# ladder past d4, so the raised Z8-Z10 floors have somewhere to send the old
	# lines instead of dropping them. Every pair checked against the live
	# building/recipe input lists:
	#   AdvCircuit      -> bus_assembly_hall AdvCircuit 0.25 | craft_fabrication_bus 2
	#   NeutroniumPlate -> frame_yard NeutroniumPlate 0.3 | craft_dreadnought_frame 2
	#   SinteredCarbide -> lattice_mill SinteredCarbide 1 | craft_precision_lattice 3
	#   PrecisionLattice-> bus_assembly_hall 0.5 + frame_yard 0.6 | recipes 3 / 7
	#   FabricationBus  -> capital_spar_works FabricationBus 0.25 | craft_capital_spar 1
	#   CapitalSpar     -> frame_yard CapitalSpar 0.4 | craft_dreadnought_frame 3
	#   StainlessSteel / GalvanizedSteel / CompositeWeave extended above the same way.
	"AdvCircuit": ["FabricationBus"],
	"NeutroniumPlate": ["DreadnoughtFrame"],
	"SinteredCarbide": ["PrecisionLattice"],
	"PrecisionLattice": ["FabricationBus", "DreadnoughtFrame"],
	"FabricationBus": ["CapitalSpar"],
	"CapitalSpar": ["DreadnoughtFrame"],
}

# v158 (E2): ONBOARDING RAMP on bands 2a / 2b / 1c at Z3-Z4. COST_BMIN_RAMP
# already leashed band 1 there; the measured pre-Warmaster bundle was still
# 3.86 h of TRANSITIVELY EXPANDED active time against a 1.5 h target, and 72% of
# it was band 2a (43 WreckforgedAlloy at 2.81 min each, because one alloy carries
# a ChondriteAlloy plus 2 MartianRelics) and band 1c (16 ReinforcedPlating at
# 2.83 min each, because craft_reinforced_plating carries 4 SalvagedAlloy +
# 2 DamagedCircuitry). Neither cost is visible in the recipe's own duration —
# that is the exact mistake the v157 probe made when it reported 1.01 h.
const COST_SMIN_RAMP := {3: 0.75, 4: 1.0}
const COST_ONBOARD_RAMP := {3: 0.16, 4: 0.70}

# v157 (D2) — AFFORDABILITY-AWARE PRICING. The composer used to price every
# material a building CAN make at that building's neutral rate, whether or not
# the player could own the building yet. Measured consequence: Ti at Z3 was
# priced at titanium_refinery's 18/min, but titanium_refinery costs 850,000
# Liras and a player at Z2 clear has 4,071 on hand — the only real Ti path is
# refine_titanium at 7.5/min, SERIAL, sharing the single active slot with
# gathering and combat. That mispricing alone put 1,389 Ti (~185 min of
# processing) on a MANDATORY pre-Warmaster mission.
#
# A building counts as a parallel source for zone z only if its Lira cost is at
# most COST_AFFORD_HOURS of that zone's own measured combat income. Zone income
# is derived at boot from the zone's loot tables, so it re-tunes itself when
# loot moves. Kill rate is held flat at 60/h: the measured values across Z3-Z10
# (49.5 / 77.1 / 58.6 / 57.3) are all within 30% of it, and making the cost
# curve depend on a per-zone kill-rate table would couple it to combat tuning.
# If no affordable building exists, the material falls back to its serial
# recipe/gather rate and is priced in band 1b instead — which is the honest
# answer: at that point in the game it IS serial.
# 6.0 measured: at that window Ti is still SERIAL at Z3 by a factor of 16
# (titanium_refinery 850,000 vs a 54,000 budget — the D2 fix holds with room),
# while every zone's own anchor building is buyable in that zone. Combat is only
# part of a player's income (bounties, quests, module sales, infra Liras), so a
# building costing a few hours of pure combat income is one they will own
# several of during a normal dwell.
const COST_AFFORD_HOURS := 6.0
const COST_KILLS_PER_HOUR := 60.0

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
# v156: the authored cost snapshot the banded curve composes FROM. The old
# _scale_mid_late_module_item_costs mutated modules[id].cost in place behind a
# bool nothing ever reset — one extra call away from silently compounding every
# mid/late recipe by 3.7x. Composing from a snapshot makes a second call a no-op
# by construction rather than by flag discipline.
var _authored_module_costs: Dictionary = {}

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
		# v142d: VoidArtifact 50 removed — VoidArtifact is a ZONE 5 combat drop (z5
		# regulars 1-5, z5 boss 10-25, z6_ore_guardian at 10%) with no gatherable or
		# infrastructure source, so a TIER 6 hull demanded bulk BACKWARD combat farming,
		# which cannot be parallelised. Same defect class as cruiser_hull's AdvCircuit
		# and battlecruiser_hull's QuantumCore. AdvCircuit 1000 also triple-booked
		# against the zone_6 gate. Tier-N hull now keys on the zone-(N-1) alloy plus
		# automatable stock, matching cruiser/battlecruiser. Hull costs bypass all
		# scaling layers (construct_hull reads this dict raw), so these are FINAL.
		"cost": {"credits": 2430000, "XenoforgedAlloy": 12, "Superalloy": 500, "Ti": 350},
		"slots": ["weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "armor", "armor", "armor", "engine", "engine", "battery", "battery", "battery", "battery", "sensor", "sensor"], # 18
		"research_req": "zone_6_access",
		"visual": "res://assets/ships/5.png",
		"tier": 6
	},
	"carrier_hull": {
		"name": "Carrier",
		"stats": {"hp": 9073, "energy_capacity": 2760},
		# v142d: ExoticMatter 100 was the ENTIRE material bill and ExoticMatter is a
		# combat-only drop (Z7/Z8 regulars ~2/kill; the only recipe source,
		# transmute_void_essence, is level 75 behind exotic_matter_analysis and so is
		# locked when this hull unlocks). ~50 serial Zone-7 kills, unautomatable, zero
		# depth. Now zone-(N-1) alloy + automatable stock, matching every tier below.
		"cost": {"credits": 7290000, "ColonyAlloy": 10, "AdvCircuit": 350, "Superalloy": 700},
		"slots": ["weapon", "weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "shield", "armor", "armor", "armor", "engine", "engine", "battery", "battery", "battery", "battery", "sensor", "sensor"], # 20
		"research_req": "zone_7_access",
		"visual": "res://assets/ships/5.png",
		"tier": 7
	},
	"dreadnought_hull": {
		"name": "Dreadnought",
		"stats": {"hp": 19960, "energy_capacity": 6075},
		# v142d: ExoticMatter 200 — same defect as carrier_hull, doubled. Combat-only
		# bulk (~100 serial kills) with no depth and nothing automatable. Replaced with
		# the zone-(N-1) alloy plus the Z8 rung's own carrier, so building the hull and
		# building the alloy pull on one supply line rather than two.
		# GammaAlloy, NOT PrismaticAlloy: a tier-N hull keys on the zone-(N-1) rung
		# (cruiser->Wreckforged, battlecruiser->Rime). PrismaticAlloy's research_req is
		# zone_8_access, the same tech that unlocks this hull, so keying on it would
		# give the player zero head start and re-create the unbuildable-on-unlock shape.
		"cost": {"credits": 21870000, "GammaAlloy": 8, "AdvCircuit": 800, "Graphite": 400},
		"slots": ["weapon", "weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "shield", "armor", "armor", "armor", "engine", "engine", "battery", "battery", "battery", "battery", "battery", "sensor", "sensor", "sensor"], # 22
		"research_req": "zone_8_access",
		"visual": "res://assets/ships/5.png",
		"tier": 8
	},
	"titan_hull": {
		"name": "Titan",
		"stats": {"hp": 43913, "energy_capacity": 13365},
		# v142d: Neutronium 500 was effectively UNBUILDABLE ON UNLOCK. Neutronium drops
		# from two of Zone 9's four regulars at 1-3 (~0.6/kill) — ~830 serial kills in
		# the zone this hull is meant to help you enter. The only other source,
		# neutronium_condenser, costs 30M credits + VoidCrystal 40 + QuantumCore 20
		# behind neutronium_synthesis and yields 0.4/10s, so it is not available either.
		# Keys on PrismaticAlloy (zone_8_access), one tech ahead of this hull.
		"cost": {"credits": 65610000, "PrismaticAlloy": 6, "AdvCircuit": 1500, "W": 800},
		"slots": ["weapon", "weapon", "weapon", "weapon", "weapon", "weapon", "shield", "shield", "shield", "shield", "armor", "armor", "armor", "armor", "engine", "engine", "battery", "battery", "battery", "battery", "battery", "sensor", "sensor", "sensor"], # 24
		"research_req": "zone_9_access",
		"visual": "res://assets/ships/5.png",
		"tier": 9
	},
	"leviathan_hull": {
		"name": "Leviathan",
		"stats": {"hp": 96609, "energy_capacity": 29400},
		# v142d: PrimordialShard 1000 was the single worst hull cost in the game.
		# PrimordialShard has NO gatherable and NO infrastructure source — every unit is
		# a Zone-10 combat drop (~1.4/kill across the rotation), so this was ~700 serial
		# kills of the zone the hull exists to help you fight, and primordial_extractor
		# CONSUMES shards rather than producing them. Keys on BioforgedAlloy
		# (zone_9_access) + the Z10 rung's own carrier.
		"cost": {"credits": 196830000, "BioforgedAlloy": 5, "Superalloy": 3000, "Ir": 150},
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
	# Shield HP   = floor(40 × 2.2^(N-1)), regen = floor(HP × 0.05)
	# Armor DEF   = floor(5 × 2.2^(N-1)), HP bonus = floor(20 × 2.2^(N-1))
	#
	# v155 WEAPON BASE-ATK FLATTEN (owner rule: "REMOVE the a-type-hits-hull /
	# a-type-hits-shield / a-type-penetrates-armor system; the damage-type
	# TRIANGLE is the only difference"). The three channels used to run SEPARATE
	# ladders — kinetic floor(8×2.2^(N-1)), energy floor(10×…), missile
	# floor(18×…) at interval 4.0 (halved to 9/… at 2.0 in v149) — i.e. a fixed
	# 1.000 : 1.235 : 1.115 raw-attack advantage to energy and explosive at EVERY
	# zone. That ladder existed to pay kinetic back for being mechanically worse
	# in the OLD pipeline (per-channel shield weight, armour divisor and hull
	# coefficient). v154 flattened that pipeline (combat_manager
	# CHANNEL_ARMOR_DIV / CHANNEL_HULL_COEF, player shield weights 1/1/1), so the
	# ladder became pure unearned advantage — and it is exactly what broke the
	# weak leg of the triangle in the 12 kinetic-weak cells:
	#     weak kinetic   1.000 × 1.30 = 1.300
	#     natural energy 1.235 × 1.00 = 1.235      <- a 5% margin, inside noise
	#
	# ONE LADDER NOW: all three channels share the zone's MISSILE value.
	#   zone  1     2     3      4    5     6     7      8       9        10
	#   all   9    20   43.5    96   211   464  1021  2246.5  4942.5  10873.5
	#
	# WHY THE MISSILE VALUE. It is the geometric mean of the three old channels
	# to within 0.20-0.42% at every single zone (X / geomean = 1.0042, 1.0034,
	# 1.0042, 1.0029, 1.0027, 1.0027, 1.0020, 1.0022, 1.0024, 1.0024 for Z1..Z10),
	# so aggregate player DPS is preserved and the existing per-zone enemy
	# calibration is disturbed as little as any single target can manage — while
	# being an ALREADY-AUTHORED integer ladder rather than a newly invented one,
	# which leaves one of the three channels bit-identical to HEAD. Kinetic gains
	# ~11.5%, energy loses ~9.7%, explosive does not move.
	#
	# The UNIQUE (trinity-set) weapons were already flat per zone; v155 only
	# repaired two v149 half-value rounding residues (z5_unique_weapon 337.5→338,
	# z10_unique_weapon 17397.5→17398) so they are flat to the last digit.
	#
	# NOT FLATTENED, deliberately: cryo_lance / corrosion_blaster. They are the
	# EXOTIC channel, not members of the K/E/X resist triangle — no zone has a
	# cryo resist row outside the Z11+ gate, there is no per-zone cryo ladder to
	# level against, and both numbers are the tuning axis of the Z11 Threshold
	# Warden and the Z12 Rift Warden. Their pipeline (armour divisor 0.5, hull
	# coefficient 1.0) already IS the flattened one.
	#
	# The per-channel energy_load literals below (5/8/10 … 400/450/500) are DEAD:
	# draw is derived from CONSUMER_LOAD_BY_TIER by zone/power_tier
	# (get_def_energy_load), and every UI surface skips the stat explicitly. They
	# are left alone rather than edited so the diff stays confined to live values.
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
		"stats": {"atk_cryo": 20000, "atk_interval": 2.0},
		# v174 (owner ruling: Z11 must clear on Rare gear AT that zone). Every other
		# sector's boss is answered by that sector's own weapon tier; Z11's was the
		# entry-level prestige unlock, and at 10K it left the zone's own Rare row at
		# 0/9 while a CARRIED Zone-10 Unique cleared 9/9 — the gate was passing on
		# borrowed gear. Buffing defence 1.8x moved Rare 0/9 -> 2/9 and a 25% HP cut
		# moved it back to 0/9, i.e. the rarity roll (x1.25-1.45 on Rare) was swamping
		# both. Doubling the weapon halves TTK instead of nudging the survival cliff,
		# so even the worst Rare roll clears with room. Z11 and Z12 bosses were both
		# retuned in this same pass, so nothing is still calibrated against 10K.
		# v156: authored at the FINAL CHARGED values (previously {15,12,50,20}
		# multiplied at boot by 1.55^9 = 51.6). The Z11 Threshold gate is tuned
		# against these numbers, so they opt out of the zone cost curve via
		# cost_authored — the curve would have read CryoCatalyst (a Z10 drop) as
		# BACKWARD debt at zone 11 and clamped 620 down to 6, collapsing the gate.
		# Baking them also fixes the Atlas / material-uses under-report.
		"cost_authored": true,
		"cost": {"credits": 2000000, "ExoticMatter": 775, "CryoCatalyst": 620, "Superalloy": 2582, "FocusingCrystal": 1033},
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
		# v156: authored at the FINAL CHARGED values (previously {30,20,120,8,15,40}
		# multiplied at boot by 1.55^10 = 80.1). Same reasoning as cryo_lance — the
		# Z12 Rift gate is tuned against these; cost_authored keeps them off the
		# zone curve.
		"cost_authored": true,
		"cost": {"credits": 8000000, "ExoticMatter": 2402, "CryoCatalyst": 1601, "Superalloy": 9606, "ChronoCore": 641, "VoidCrystal": 1201, "FocusingCrystal": 3202},
		"desc": "Acid-plasma projector. Etches through Corrosion-hardened hulls where cryogenic fire just glazes the surface.",
		"zone": 12,
		"power_tier": 8,
		"research_req": "corrosion_armaments"
	},

	# ── SECTOR 11 KIT (v174, owner ruling) ────────────────────────────────────
	# Z11 was the one zone with no gear set of its own: the Threshold gave you the
	# Cryo-Lance and nothing to wear, so defence fell back to z10 and the zone's own
	# Rare and Legendary rows both read 0/9. It only "passed" through the Zone-10
	# Unique clause — a x2.4-3.2 rarity roll on a carried weapon papering over a
	# missing tier — and that cell swung 4/9 to 8/9 across runs, so the verdict was
	# a coin flip. Owner ruling: Z11 must pass on Rare or better AT THAT ZONE.
	# Values interpolate the z10 -> z12 line, which is where a Z11 tier belongs.
	"z11_armor": {
		"name": "Threshold Bulwark",
		"slot_type": "armor",
		"stats": {"def": 24000, "hp": 96000, "resist_k": 0.09, "resist_e": 0.09, "resist_x": 0.09},
		"cost_authored": true,
		"cost": {"credits": 9000000, "ExoticMatter": 1800, "CryoEssence": 1400, "OmegaPlating": 1100, "Neutronium": 5000},
		"desc": "Sector 11 plating. Warp-tempered against the Threshold's cold.",
		"zone": 11,
		"power_tier": 9,
		"research_req": "cryo_armaments"
	},
	"z11_shield": {
		"name": "Threshold Barrier",
		"slot_type": "shield",
		"stats": {"max_shield": 192000, "shield_regen": 1870, "resist_e": 0.09},
		"cost_authored": true,
		"cost": {"credits": 8000000, "ExoticMatter": 1600, "CryoEssence": 1300, "OmegaPlating": 950, "Ti": 14000},
		"desc": "Sector 11 deflector envelope. Holds against warp-hardened fire.",
		"zone": 11,
		"power_tier": 9,
		"research_req": "cryo_armaments"
	},

	# ══ NG+ DEFENSIVE LADDER (v174) ═══════════════════════════════════════════
	# The weapon ladder above fixed offence and immediately exposed this: NG+ had
	# no armour or shield of its own either, so the player's defence stayed pinned
	# at z10_armor/z10_shield while these bosses' attack climbed four sectors past
	# it. Measured survival on z10 defence was 13s / 7s / 8s / 5s against kills
	# that need 267-345s — a 20-45x gap, and Z15 landed single hits larger than a
	# fully-geared 36M hull pool.
	#
	# Sized against measured survival, not a formula (the weapon ladder's authored
	# values were 3-5x off precisely because they were solved on paper — module
	# stats get scaled by zone on top of whatever is written here). Explicit
	# per-type resists are included because NG+ attack values are large enough that
	# flat mitigation matters more than raw pool, and because corrosion rides the
	# kinetic channel, so resist_k covers the Verdigris and Caustic bosses too.

	"z12_armor": {
		"name": "Rift Bulwark",
		"slot_type": "armor",
		"stats": {"def": 22820, "hp": 91530, "resist_k": 0.05, "resist_e": 0.05, "resist_x": 0.05},
		"cost_authored": true,
		"cost": {"credits": 25000000, "ExoticMatter": 3400, "OmegaPlating": 2600, "VoidLattice": 1400, "Neutronium": 9000},
		"desc": "Sector 12 plating. Layered against the frontier's acid and cold alike.",
		"zone": 12,
		"power_tier": 9,
		"research_req": "rift_armaments"
	},
	"z12_shield": {
		"name": "Rift Barrier",
		"slot_type": "shield",
		"stats": {"max_shield": 183065, "shield_regen": 1407, "resist_e": 0.05},
		"cost_authored": true,
		"cost": {"credits": 22500000, "ExoticMatter": 3400, "OmegaPlating": 2600, "VoidLattice": 1400, "Neutronium": 9000},
		"desc": "Sector 12 deflector envelope. Regenerates fast enough to matter between phase swings.",
		"zone": 12,
		"power_tier": 9,
		"research_req": "rift_armaments"
	},
	"z13_armor": {
		"name": "Verdigris Bulwark",
		"slot_type": "armor",
		"stats": {"def": 16049, "hp": 64365, "resist_k": 0.06, "resist_e": 0.06, "resist_x": 0.06},
		"cost_authored": true,
		"cost": {"credits": 55000000, "ExoticMatter": 6100, "OmegaPlating": 4700, "VoidLattice": 2500, "ChronoCore": 800, "Neutronium": 16000},
		"desc": "Sector 13 plating. Layered against the frontier's acid and cold alike.",
		"zone": 13,
		"power_tier": 9,
		"research_req": "verdigris_armaments"
	},
	"z13_shield": {
		"name": "Verdigris Barrier",
		"slot_type": "shield",
		"stats": {"max_shield": 128730, "shield_regen": 990, "resist_e": 0.06},
		"cost_authored": true,
		"cost": {"credits": 49500000, "ExoticMatter": 6100, "OmegaPlating": 4700, "VoidLattice": 2500, "ChronoCore": 800, "Neutronium": 16000},
		"desc": "Sector 13 deflector envelope. Regenerates fast enough to matter between phase swings.",
		"zone": 13,
		"power_tier": 9,
		"research_req": "verdigris_armaments"
	},
	"z14_armor": {
		"name": "Dissolution Bulwark",
		"slot_type": "armor",
		"stats": {"def": 25834, "hp": 103612, "resist_k": 0.07, "resist_e": 0.07, "resist_x": 0.07},
		"cost_authored": true,
		"cost": {"credits": 120000000, "ExoticMatter": 11000, "OmegaPlating": 8400, "VoidLattice": 4500, "ChronoCore": 1500, "Neutronium": 29000},
		"desc": "Sector 14 plating. Layered against the frontier's acid and cold alike.",
		"zone": 14,
		"power_tier": 9,
		"research_req": "dissolution_armaments"
	},
	"z14_shield": {
		"name": "Dissolution Barrier",
		"slot_type": "shield",
		"stats": {"max_shield": 207224, "shield_regen": 1594, "resist_e": 0.07},
		"cost_authored": true,
		"cost": {"credits": 108000000, "ExoticMatter": 11000, "OmegaPlating": 8400, "VoidLattice": 4500, "ChronoCore": 1500, "Neutronium": 29000},
		"desc": "Sector 14 deflector envelope. Regenerates fast enough to matter between phase swings.",
		"zone": 14,
		"power_tier": 9,
		"research_req": "dissolution_armaments"
	},
	"z15_armor": {
		"name": "Caustic Bulwark",
		"slot_type": "armor",
		"stats": {"def": 24660, "hp": 98902, "resist_k": 0.08, "resist_e": 0.08, "resist_x": 0.08},
		"cost_authored": true,
		"cost": {"credits": 260000000, "ExoticMatter": 19500, "OmegaPlating": 15000, "VoidLattice": 8000, "ChronoCore": 2700, "VoidEssence": 1600, "Neutronium": 52000},
		"desc": "Sector 15 plating. Layered against the frontier's acid and cold alike.",
		"zone": 15,
		"power_tier": 9,
		"research_req": "caustic_armaments"
	},
	"z15_shield": {
		"name": "Caustic Barrier",
		"slot_type": "shield",
		"stats": {"max_shield": 197804, "shield_regen": 1522, "resist_e": 0.08},
		"cost_authored": true,
		"cost": {"credits": 234000000, "ExoticMatter": 19500, "OmegaPlating": 15000, "VoidLattice": 8000, "ChronoCore": 2700, "VoidEssence": 1600, "Neutronium": 52000},
		"desc": "Sector 15 deflector envelope. Regenerates fast enough to matter between phase swings.",
		"zone": 15,
		"power_tier": 9,
		"research_req": "caustic_armaments"
	},

	# ══ NG+ EXOTIC WEAPON LADDER (v174) ═══════════════════════════════════════
	# The conventional channel gets a fresh weapon every zone — 30 modules across
	# 10 zones. The exotic channel shipped TWO for five zones (Cryo Lance 10K at
	# Z11, Corrosion Blaster 12K at Z12), so from Z12 on the player's exotic power
	# was frozen at tier 11 while boss HP climbed to 40x Z11 — and on a phase boss
	# the exotic channel is the ONLY damage that counts. Measured: all four NG+
	# bosses lost 0/9 at every rarity with the correct mixed battery; Z15 was a
	# seven-hour fight. See docs/RULINGS_2026-08-08.md.
	#
	# Values solve HP / 400s at the measured 0.575 phase-mix throughput (half your
	# barrels sit at phase_cut 0.15 in any band). The resulting per-zone step
	# averages x2.2 — the same ratio as the conventional ladder — which is the
	# evidence that the HP curve was right and only these were missing.
	#
	# Gating mirrors conventional zones: zone N's weapon is researched off zone N's
	# UNLOCK flag, i.e. earned from clearing N-1 and warping. You never need zone
	# N's boss to drop the weapon that beats zone N. power_tier stays 8 like the
	# older exotics — power is deliberately not a second gate here.

	"z12_cryo_lance": {
		"name": "Rift Lance",
		"slot_type": "weapon",
		"rarity": Rarity.LEGENDARY,
		"stats": {"atk_cryo": 60000, "atk_interval": 2.0},
		"cost_authored": true,
		"cost": {"credits": 20000000, "ExoticMatter": 4000, "CryoEssence": 2400, "OmegaPlating": 1600, "VoidLattice": 1200},
		"desc": "Sector 12 cryogenic armament. Breaches the Rift's cryo band; glances off corrosion phases, so pair it with an Etcher.",
		"zone": 12,
		"power_tier": 8,
		"research_req": "rift_armaments"
	},
	"z12_corrosion_blaster": {
		"name": "Rift Etcher",
		"slot_type": "weapon",
		"rarity": Rarity.LEGENDARY,
		"stats": {"atk_cryo": 72000, "atk_interval": 2.0, "exotic_element": "corrosion"},
		"cost_authored": true,
		"cost": {"credits": 24000000, "ExoticMatter": 4800, "CryoEssence": 2880, "OmegaPlating": 1920, "VoidLattice": 1440},
		"desc": "Sector 12 acid-plasma projector. Breaches the Rift's corrosion band; glances off cryo phases, so pair it with a Lance.",
		"zone": 12,
		"power_tier": 8,
		"research_req": "rift_armaments"
	},
	"z13_cryo_lance": {
		"name": "Verdigris Lance",
		"slot_type": "weapon",
		"rarity": Rarity.LEGENDARY,
		"stats": {"atk_cryo": 70000, "atk_interval": 2.0},
		"cost_authored": true,
		"cost": {"credits": 45000000, "ExoticMatter": 7200, "CryoEssence": 4300, "OmegaPlating": 2900, "VoidLattice": 2200, "ChronoCore": 900},
		"desc": "Sector 13 cryogenic armament. Breaches the Reach's cryo band; glances off corrosion phases, so pair it with an Etcher.",
		"zone": 13,
		"power_tier": 8,
		"research_req": "verdigris_armaments"
	},
	"z13_corrosion_blaster": {
		"name": "Verdigris Etcher",
		"slot_type": "weapon",
		"rarity": Rarity.LEGENDARY,
		"stats": {"atk_cryo": 84000, "atk_interval": 2.0, "exotic_element": "corrosion"},
		"cost_authored": true,
		"cost": {"credits": 54000000, "ExoticMatter": 8640, "CryoEssence": 5160, "OmegaPlating": 3480, "VoidLattice": 2640, "ChronoCore": 1080},
		"desc": "Sector 13 acid-plasma projector. Breaches the Reach's corrosion band; glances off cryo phases, so pair it with a Lance.",
		"zone": 13,
		"power_tier": 8,
		"research_req": "verdigris_armaments"
	},
	"z14_cryo_lance": {
		"name": "Dissolution Lance",
		"slot_type": "weapon",
		"rarity": Rarity.LEGENDARY,
		"stats": {"atk_cryo": 81000, "atk_interval": 2.0},
		"cost_authored": true,
		"cost": {"credits": 100000000, "ExoticMatter": 13000, "CryoEssence": 7800, "OmegaPlating": 5200, "VoidLattice": 3900, "ChronoCore": 1600},
		"desc": "Sector 14 cryogenic armament. Breaches the Tyrant's two cryo bands; glances off corrosion phases, so pair it with an Etcher.",
		"zone": 14,
		"power_tier": 8,
		"research_req": "dissolution_armaments"
	},
	"z14_corrosion_blaster": {
		"name": "Dissolution Etcher",
		"slot_type": "weapon",
		"rarity": Rarity.LEGENDARY,
		"stats": {"atk_cryo": 97000, "atk_interval": 2.0, "exotic_element": "corrosion"},
		"cost_authored": true,
		"cost": {"credits": 120000000, "ExoticMatter": 15600, "CryoEssence": 9360, "OmegaPlating": 6240, "VoidLattice": 4680, "ChronoCore": 1920},
		"desc": "Sector 14 acid-plasma projector. Breaches the Tyrant's corrosion band; glances off cryo phases, so pair it with a Lance.",
		"zone": 14,
		"power_tier": 8,
		"research_req": "dissolution_armaments"
	},
	"z15_cryo_lance": {
		"name": "Caustic Lance",
		"slot_type": "weapon",
		"rarity": Rarity.LEGENDARY,
		"stats": {"atk_cryo": 122000, "atk_interval": 2.0},
		"cost_authored": true,
		"cost": {"credits": 220000000, "ExoticMatter": 23000, "CryoEssence": 14000, "OmegaPlating": 9400, "VoidLattice": 7000, "ChronoCore": 2900, "VoidEssence": 1800},
		"desc": "Sector 15 cryogenic armament. Breaches the Sovereign's cryo band; glances off corrosion phases, so pair it with an Etcher.",
		"zone": 15,
		"power_tier": 8,
		"research_req": "caustic_armaments"
	},
	"z15_corrosion_blaster": {
		"name": "Caustic Etcher",
		"slot_type": "weapon",
		"rarity": Rarity.LEGENDARY,
		"stats": {"atk_cryo": 146000, "atk_interval": 2.0, "exotic_element": "corrosion"},
		"cost_authored": true,
		"cost": {"credits": 264000000, "ExoticMatter": 27600, "CryoEssence": 16800, "OmegaPlating": 11280, "VoidLattice": 8400, "ChronoCore": 3480, "VoidEssence": 2160},
		"desc": "Sector 15 acid-plasma projector. Breaches the Sovereign's two corrosion bands; glances off cryo phases, so pair it with a Lance.",
		"zone": 15,
		"power_tier": 8,
		"research_req": "caustic_armaments"
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
		"stats": {"atk_kinetic": 9, "energy_load": 5, "atk_interval": 2.0},
		"cost": {"credits": 2000, "Fe": 30},
		"desc": "Magnetic rail cannon. Crude, rugged, and cheap to keep loaded.",
		"zone": 1
	},
	"z1_energy": {
		"name": "Pulse Laser Mk.I",
		"slot_type": "weapon",
		"stats": {"atk_energy": 9, "energy_load": 8, "atk_interval": 2.0},
		"cost": {"credits": 2000, "Si": 30},
		"desc": "Fast-cycling beam emitter. Focus crystals in, coherent light out.",
		"zone": 1
	},
	# v156 CHANNEL CREDIT PARITY: every explosive weapon's Lira cost was EXACTLY
	# 1.25x its kinetic counterpart at every zone (2500/2000 ... 3018153/2414522).
	# That premium used to buy explosive ~11.5% more attack; v155 flattened all
	# three channels onto one base atk, so it bought +0% damage and made kinetic
	# strictly the cheapest channel. Levelled DOWN to the kinetic ladder — kinetic
	# and energy stay bit-identical, credits are not a binding sink (a Z10 refit
	# bills 55 M against 5-50 B lifetime credits), and raising the other two
	# instead would also have inflated their get_sell_price (25% of the credit
	# cost). Material parity is handled by the cost composer: the foundation and
	# serial budgets are per-SLOT, so all three weapon channels buy the same
	# number of production-line minutes with different flavour materials.
	"z1_missile": {
		"name": "Micro-Missile Launcher",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 9, "energy_load": 10, "atk_interval": 2.0},
		"cost": {"credits": 2000, "Fe": 20, "Cu": 10},
		"desc": "Rack-fed micro-warheads. Loud, messy, and quick to reload.",
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
		"stats": {"atk_kinetic": 20, "energy_load": 10, "atk_interval": 2.0},
		"cost": {"credits": 4400, "Fe": 60, "Cu": 20},
		"desc": "Electromagnetic accelerator. Throws ferrite at hypersonic muzzle speed.",
		"zone": 2, "research_req": "zone_2_access"
	},
	"z2_energy": {
		"name": "Plasma Cutter",
		"slot_type": "weapon",
		"stats": {"atk_energy": 20, "energy_load": 15, "atk_interval": 2.0},
		"cost": {"credits": 4400, "Si": 60, "Cu": 20},
		"desc": "Focused plasma stream, repurposed from a shipbreaker's cutting torch.",
		"zone": 2, "research_req": "zone_2_access"
	},
	"z2_missile": {
		"name": "Concussion Missile",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 20, "energy_load": 18, "atk_interval": 2.0},
		"cost": {"credits": 4400, "Fe": 40, "C": 30, "Hydraulics": 2},
		"desc": "Concussive warhead tuned for maximum overpressure.",
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
		"stats": {"atk_kinetic": 43.5, "energy_load": 18, "atk_interval": 2.0},
		"cost": {"credits": 9680, "Steel": 40, "Ti": 15},
		"desc": "Rapid-fire ballistic weapon.",
		"zone": 3, "research_req": "zone_3_access"
	},
	"z3_energy": {
		"name": "Cryo Beam",
		"slot_type": "weapon",
		"stats": {"atk_energy": 43.5, "energy_load": 25, "atk_interval": 2.0},
		"cost": {"credits": 9680, "Si": 100, "Ti": 15},
		"desc": "Helium-cooled emitter. Holds a firing line far longer than it should.",
		"zone": 3, "research_req": "zone_3_access"
	},
	"z3_missile": {
		"name": "Heavy Torpedo",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 43.5, "energy_load": 30, "atk_interval": 2.0},
		"cost": {"credits": 9680, "Steel": 60, "C": 40, "Hydraulics": 3},
		"desc": "Slow, heavy ordnance. One tube, one very large warhead.",
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
		"stats": {"atk_kinetic": 96, "energy_load": 30, "atk_interval": 2.0},
		"cost": {"credits": 21296, "Steel": 80, "AdvCircuit": 9},
		"desc": "High-velocity slug launcher.",
		"zone": 4, "research_req": "zone_4_access"
	},
	"z4_energy": {
		"name": "Ion Lance",
		"slot_type": "weapon",
		"stats": {"atk_energy": 96, "energy_load": 40, "atk_interval": 2.0},
		"cost": {"credits": 21296, "Ti": 60, "AdvCircuit": 9, "FocusingCrystal": 2},
		"desc": "Concentrated ion stream.",
		"zone": 4, "research_req": "zone_4_access"
	},
	"z4_missile": {
		"name": "Cluster Warhead",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 96, "energy_load": 45, "atk_interval": 2.0},
		"cost": {"credits": 21296, "Steel": 100, "Chip": 18, "Hydraulics": 5},
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
		"stats": {"atk_kinetic": 211, "energy_load": 50, "atk_interval": 2.0},
		"cost": {"credits": 46851, "Superalloy": 20, "QuantumCore": 2},
		"desc": "Capital-grade magnetic accelerator.",
		"zone": 5, "research_req": "zone_5_access"
	},
	"z5_energy": {
		"name": "Particle Beam",
		"slot_type": "weapon",
		"stats": {"atk_energy": 211, "energy_load": 60, "atk_interval": 2.0},
		"cost": {"credits": 46851, "Ti": 100, "QuantumCore": 2, "Au": 10, "FocusingCrystal": 3},
		"desc": "Relativistic particle stream drawn straight off the reactor line.",
		"zone": 5, "research_req": "zone_5_access"
	},
	"z5_missile": {
		"name": "Seeker Torpedo",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 211, "energy_load": 70, "atk_interval": 2.0},
		# v150: TargetingChip added. Pulling it out of craft_missile_t2 (where it
		# was an inverted gate — a lvl-25 recipe demanding a lvl-45 component) left
		# it with ZERO consumers anywhere in the game, i.e. the exact dead-end that
		# got craft_turret_core cut in v141c. The Seeker Torpedo is its native home:
		# same guidance fantasy, and craft_turret_targeting's lvl 45 sits on-curve
		# for a Zone 5 purchase. A module cost is a CHOICE, never a gate — an
		# unaffordable module is simply not bought.
		"cost": {"credits": 46851, "Superalloy": 30, "Chip": 20, "TargetingChip": 5},
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
		"stats": {"atk_kinetic": 464, "energy_load": 80, "atk_interval": 2.0},
		"cost": {"credits": 103072, "Superalloy": 50, "AdvCircuit": 30},
		"desc": "Colony-siege grade ballistic weapon.",
		"zone": 6, "research_req": "zone_6_access"
	},
	"z6_energy": {
		"name": "Plasma Lancer",
		"slot_type": "weapon",
		"stats": {"atk_energy": 464, "energy_load": 90, "atk_interval": 2.0},
		"cost": {"credits": 103072, "QuantumCore": 5, "AdvCircuit": 30, "FocusingCrystal": 5},
		"desc": "Sustained plasma discharge.",
		"zone": 6, "research_req": "zone_6_access"
	},
	"z6_missile": {
		"name": "Antimatter Warhead",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 464, "energy_load": 100, "atk_interval": 2.0},
		"cost": {"credits": 103072, "Superalloy": 60, "QuantumCore": 5},
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
		"stats": {"atk_kinetic": 1021, "energy_load": 120, "atk_interval": 2.0},
		"cost": {"credits": 226758, "ExoticMatter": 10, "Ir": 10, "IrWAlloy": 5, "AdvCircuit": 40},
		"desc": "Fires neutron-dense projectiles.",
		"zone": 7, "research_req": "zone_7_access"
	},
	"z7_energy": {
		"name": "Void Beam",
		"slot_type": "weapon",
		"stats": {"atk_energy": 1021, "energy_load": 140, "atk_interval": 2.0},
		"cost": {"credits": 226758, "ExoticMatter": 10, "VoidCrystal": 5, "AdvCircuit": 40, "FocusingCrystal": 8},
		"desc": "Drains energy from realspace.",
		"zone": 7, "research_req": "zone_7_access"
	},
	"z7_missile": {
		"name": "Singularity Bomb",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 1021, "energy_load": 160, "atk_interval": 2.0},
		"cost": {"credits": 226758, "ExoticMatter": 15, "QuantumCore": 10, "Chip": 55},
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
		"stats": {"atk_kinetic": 2246.5, "energy_load": 180, "atk_interval": 2.0},
		"cost": {"credits": 498868, "VoidCrystal": 10, "StructuralLattice": 2, "NeutroniumPlate": 2, "Steel": 4500},
		"desc": "Crystal-focused kinetic lance.",
		"zone": 8, "research_req": "zone_8_access"
	},
	"z8_energy": {
		"name": "Prism Annihilator",
		"slot_type": "weapon",
		"stats": {"atk_energy": 2246.5, "energy_load": 200, "atk_interval": 2.0},
		"cost": {"credits": 498868, "VoidCrystal": 10, "ExoticMatter": 10, "StructuralLattice": 2, "Ti": 3500, "FocusingCrystal": 12},
		"desc": "Refracted energy cascade.",
		"zone": 8, "research_req": "zone_8_access"
	},
	"z8_missile": {
		"name": "Quantum Torpedo",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 2246.5, "energy_load": 240, "atk_interval": 2.0},
		"cost": {"credits": 498868, "QuantumCore": 20, "StructuralLattice": 3, "NeutroniumPlate": 3, "Steel": 5500},
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
		"stats": {"atk_kinetic": 4942.5, "energy_load": 260, "atk_interval": 2.0},
		"cost": {"credits": 1097510, "BiohazardSample": 20, "BioReactorCore": 3, "Neutronium": 180, "Steel": 9000},
		"desc": "Bio-corrosive projectiles.",
		"zone": 9, "research_req": "zone_9_access"
	},
	"z9_energy": {
		"name": "Zero-Point Beam",
		"slot_type": "weapon",
		"stats": {"atk_energy": 4942.5, "energy_load": 300, "atk_interval": 2.0},
		"cost": {"credits": 1097510, "ChronoCore": 2, "BioReactorCore": 3, "Neutronium": 180, "Ti": 8000, "FocusingCrystal": 18},
		"desc": "Extracts energy from vacuum fluctuations.",
		"zone": 9, "research_req": "zone_9_access"
	},
	"z9_missile": {
		"name": "Biohazard Warhead",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 4942.5, "energy_load": 350, "atk_interval": 2.0},
		"cost": {"credits": 1097510, "BiohazardSample": 30, "BioReactorCore": 4, "Neutronium": 200, "Steel": 11000},
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
		"stats": {"atk_kinetic": 10873.5, "energy_load": 400, "atk_interval": 2.0},
		"cost": {"credits": 2414522, "PrimordialShard": 5, "PrimordialMatrix": 3, "OmegaComposite": 2, "Neutronium": 200, "Steel": 13000},
		"desc": "Final evolution of kinetic warfare.",
		"zone": 10, "research_req": "zone_10_access"
	},
	"z10_energy": {
		"name": "Chrono Disruptor",
		"slot_type": "weapon",
		"stats": {"atk_energy": 10873.5, "energy_load": 450, "atk_interval": 2.0},
		"cost": {"credits": 2414522, "ChronoCore": 5, "PrimordialMatrix": 3, "OmegaComposite": 2, "Neutronium": 200, "Ti": 11000, "FocusingCrystal": 25},
		"desc": "Tears through spacetime itself.",
		"zone": 10, "research_req": "zone_10_access"
	},
	"z10_missile": {
		"name": "Void Annihilator",
		"slot_type": "weapon",
		"stats": {"atk_explosive": 10873.5, "energy_load": 500, "atk_interval": 2.0},
		"cost": {"credits": 2414522, "PrimordialShard": 8, "PrimordialMatrix": 4, "OmegaComposite": 3, "Neutronium": 220, "Steel": 15000},
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
		# v156: VoidArtifact -> VoidCrystal. VoidArtifact only drops in Z5/Z6, so a
		# Zone 8 module asking for it was BACKWARD combat debt — serial grind in a
		# zone the player has left, the one thing the cost rules forbid. VoidCrystal
		# is the Z7/Z8 equivalent and is infra-produced (void_crystallizer), so it
		# lands in the parallel foundation band instead.
		"cost": {"credits": 480000, "VoidCrystal": 10, "Os": 5}, "zone": 8, "research_req": "zone_8_access"
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
	"z2_unique_kinetic": {
		"name": "Monolith's Driver", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_kinetic": 28, "energy_load": 18, "atk_interval": 2.0},
		"cost": {}, "desc": "Unique kinetic-channel armament.", "zone": 2,
		"set_id": "monoliths_bedrock", "is_unique": true
	},
	"z2_unique_missile": {
		"name": "Monolith's Salvo", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 28, "energy_load": 18, "atk_interval": 2.0},
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
	"z3_unique_kinetic": {
		"name": "Warmaster's Driver", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_kinetic": 62, "energy_load": 30, "atk_interval": 2.0},
		"cost": {}, "desc": "Unique kinetic-channel armament.", "zone": 3,
		"set_id": "warmasters_arsenal", "is_unique": true
	},
	"z3_unique_missile": {
		"name": "Warmaster's Salvo", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 62, "energy_load": 30, "atk_interval": 2.0},
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
	"z4_unique_energy": {
		"name": "Overseer's Beam", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_energy": 169, "energy_load": 50, "atk_interval": 2.0},
		"cost": {}, "desc": "Unique energy-channel armament.", "zone": 4,
		"set_id": "overseers_command", "is_unique": true
	},
	"z4_unique_missile": {
		"name": "Overseer's Salvo", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 169, "energy_load": 50, "atk_interval": 2.0},
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

	# ── Z5: Harbinger's Wrath (+30% All DMG, -20% Enemy DEF) ──
	# v155: was "+15% Missile DMG" in this header and missile_dmg_pct 30 in the
	# const — stale on both counts. The set bonus is now channel-agnostic; see the
	# TRINITY_SET_BONUSES note in combat_manager.gd.
	"z5_unique_weapon": {
		"name": "Harbinger's Fury", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 338, "energy_load": 90, "atk_interval": 2.0},
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
	"z5_unique_missile": {
		"name": "Harbinger's Salvo", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 338, "energy_load": 90, "atk_interval": 2.0},
		"cost": {}, "desc": "Unique missile-channel armament.", "zone": 5,
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
	"z6_unique_kinetic": {
		"name": "Colossus Cannon Driver", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_kinetic": 665, "energy_load": 120, "atk_interval": 2.0},
		"cost": {}, "desc": "Unique kinetic-channel armament.", "zone": 6,
		"set_id": "colossus_dominion", "is_unique": true
	},
	"z6_unique_missile": {
		"name": "Colossus Cannon Salvo", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 665, "energy_load": 120, "atk_interval": 2.0},
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

	# ── Z7: Sovereign's Prism (+800 DEF, +22% All DMG) ──
	# v155: was "+10% Energy DMG" here and energy_dmg_pct 22 in the const — stale on
	# both counts. Now channel-agnostic; see combat_manager.gd TRINITY_SET_BONUSES.
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
	"z7_unique_energy": {
		"name": "Sovereign's Lance", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_energy": 1809, "energy_load": 180, "atk_interval": 2.0},
		"cost": {}, "desc": "Unique energy-channel armament.", "zone": 7,
		"set_id": "sovereigns_prism", "is_unique": true
	},
	"z7_unique_missile": {
		"name": "Sovereign's Salvo", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 1809, "energy_load": 180, "atk_interval": 2.0},
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
	"z8_unique_energy": {
		"name": "Warden's Lance", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_energy": 3982, "energy_load": 280, "atk_interval": 2.0},
		"cost": {}, "desc": "Unique energy-channel armament.", "zone": 8,
		"set_id": "wardens_quarantine", "is_unique": true
	},
	"z8_unique_missile": {
		"name": "Warden's Salvo", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 3982, "energy_load": 280, "atk_interval": 2.0},
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
	"z9_unique_kinetic": {
		"name": "Titan's Driver", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_kinetic": 7091, "energy_load": 400, "atk_interval": 2.0},
		"cost": {}, "desc": "Unique kinetic-channel armament.", "zone": 9,
		"set_id": "titans_legacy", "is_unique": true
	},
	"z9_unique_missile": {
		"name": "Titan's Salvo", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 7091, "energy_load": 400, "atk_interval": 2.0},
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
		"stats": {"atk_explosive": 17398, "energy_load": 600, "atk_interval": 2.0},
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
	"z10_unique_missile": {
		"name": "Leviathan's Salvo", "slot_type": "weapon", "rarity": 4,
		"stats": {"atk_explosive": 17398, "energy_load": 600, "atk_interval": 2.0},
		"cost": {}, "desc": "Unique missile-channel armament.", "zone": 10,
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
	recalc_stats()
	_migrate_module_entries_from_resources()
	# NOTE: compose_module_costs() is NOT called here. It needs
	# infrastructure/processing/gathering/combat to classify each material, and
	# GameState builds those managers after this one. GameState._ready() calls it
	# once every manager exists, before load_game().

# ── v156 BANDED COST CURVE — material classification ───────────────────────
# Costs are priced in time on a production line, so the composer needs to know,
# for every material, whether a BUILDING makes it (parallel), a RECIPE or a
# GATHER action makes it (serial), or only an enemy drops it (combat) — and for
# combat, which zones. All of it is derived from the live databases at boot, so
# the curve re-tunes itself when a building or recipe is added.
var _cost_infra_rate := {}     # sym -> units/min for ONE building, neutral reference
var _cost_serial_rate := {}    # sym -> units/min of the best single recipe / action
var _cost_combat_zones := {}   # sym -> [zone, ...] it can drop in
var _cost_index_built := false
# v157: sym -> [[credits_cost, units_per_min], ...] for every building that
# yields it, so the curve can ask "at zone z, which of these can the player
# actually own?" instead of always taking the best one (D2).
var _cost_infra_offers := {}
var _cost_zone_income := {}    # zone difficulty -> Liras/hour from that zone's regulars
var _cost_drop_rate := {}      # sym -> {zone: expected units per kill} (D3 weighting)
var _cost_depth := {}          # sym -> infra depth, shortest chain to a zero-input root
var _cost_depth_visiting := {}

func _build_cost_index() -> void:
	if _cost_index_built:
		return
	_cost_index_built = true
	var im = GameState.infrastructure_manager
	var pm = GameState.processing_manager
	var gm = GameState.gathering_manager
	var cm = GameState.combat_manager
	if im:
		for bid in im.building_db:
			var d: Dictionary = im.building_db[bid]
			var iv: float = maxf(0.001, float(d.get("interval", 1.0)))
			var bcr: float = float((d.get("cost", {}) as Dictionary).get("credits", 0))
			for sym in d.get("yield", {}):
				var s := String(sym)
				var r: float = float(d["yield"][sym]) / iv * 60.0
				_cost_infra_rate[s] = maxf(float(_cost_infra_rate.get(s, 0.0)), r)
				if not _cost_infra_offers.has(s):
					_cost_infra_offers[s] = []
				(_cost_infra_offers[s] as Array).append([bcr, r])
	if pm:
		for rid in pm.recipes:
			var rec: Dictionary = pm.recipes[rid]
			var du: float = maxf(0.001, float(rec.get("duration", 1.0)))
			for sym in rec.get("output", {}):
				var s2 := String(sym)
				var r2: float = float(rec["output"][sym]) / du * 60.0
				_cost_serial_rate[s2] = maxf(float(_cost_serial_rate.get(s2, 0.0)), r2)
	if gm:
		for aid in gm.actions:
			var a: Dictionary = gm.actions[aid]
			var du2: float = maxf(0.001, float(a.get("duration", 3.0)))
			for row in a.get("loot_table", []):
				var s3 := String(row[0])
				var avg: float = (float(row[2]) + float(row[3])) * 0.5 * float(row[1])
				_cost_serial_rate[s3] = maxf(float(_cost_serial_rate.get(s3, 0.0)), avg / du2 * 60.0)
	if cm:
		for zid in cm.zones:
			var z: Dictionary = cm.zones[zid]
			var zd: int = int(z.get("difficulty", 0))
			var elist: Array = (z.get("enemies", []) as Array).duplicate()
			if z.has("boss"):
				elist.append(z["boss"])
			for eid in elist:
				var e: Dictionary = cm.enemy_db.get(String(eid), {})
				for tbl in ["loot", "rare_loot"]:
					for row in e.get(tbl, []):
						var s4 := String(row[0])
						if not _cost_combat_zones.has(s4):
							_cost_combat_zones[s4] = []
						if not (zd in _cost_combat_zones[s4]):
							(_cost_combat_zones[s4] as Array).append(zd)
			# v157: expected units per kill and Liras per hour, from the REGULAR
			# roster only. The boss id lives INSIDE zones[..].enemies (there is no
			# separate "boss" key on Z1-Z10), and its loot is an order of
			# magnitude richer, so leaving it in would price a farm rate off a
			# once-per-clear event.
			var regs: Array = []
			for eid3 in (z.get("enemies", []) as Array):
				if String(eid3).find("_boss_") == -1:
					regs.append(eid3)
			if regs.is_empty():
				continue
			var per_kill := {}
			for eid2 in regs:
				var e2: Dictionary = cm.enemy_db.get(String(eid2), {})
				for row2 in e2.get("loot", []):
					var sa := String(row2[0])
					per_kill[sa] = float(per_kill.get(sa, 0.0)) \
						+ (float(row2[1]) + float(row2[2])) * 0.5
				for row3 in e2.get("rare_loot", []):
					var sb := String(row3[0])
					per_kill[sb] = float(per_kill.get(sb, 0.0)) \
						+ float(row3[1]) * (float(row3[2]) + float(row3[3])) * 0.5
			for sc in per_kill:
				var avg2: float = float(per_kill[sc]) / float(regs.size())
				var sk := String(sc)
				if not _cost_drop_rate.has(sk):
					_cost_drop_rate[sk] = {}
				(_cost_drop_rate[sk] as Dictionary)[zd] = maxf(
					float((_cost_drop_rate[sk] as Dictionary).get(zd, 0.0)), avg2)
			var inc: float = float(per_kill.get("credits", 0.0)) / float(regs.size()) \
				* COST_KILLS_PER_HOUR
			_cost_zone_income[zd] = maxf(float(_cost_zone_income.get(zd, 0.0)), inc)
		_cost_fill_income_gaps()

# Zone 6's four regulars drop no Liras at all (measured — a pre-existing gap in
# combat_manager's loot tables, not something the cost curve should fix). A zone
# with no measured income would inherit the previous zone's budget and could
# strand its own anchor, so log-interpolate any gap between the nearest measured
# zones on either side. Purely a smoothing pass over the measurement.
func _cost_fill_income_gaps() -> void:
	var zs: Array = _cost_zone_income.keys()
	zs.sort()
	if zs.is_empty():
		return
	var lo: int = int(zs[0])
	var hi: int = int(zs[zs.size() - 1])
	for z in range(lo, hi + 1):
		if float(_cost_zone_income.get(z, 0.0)) > 0.0:
			continue
		var pz := -1
		var nz := -1
		for a in range(z - 1, lo - 1, -1):
			if float(_cost_zone_income.get(a, 0.0)) > 0.0:
				pz = a
				break
		for b in range(z + 1, hi + 1):
			if float(_cost_zone_income.get(b, 0.0)) > 0.0:
				nz = b
				break
		if pz >= 0 and nz >= 0:
			var t := float(z - pz) / float(nz - pz)
			_cost_zone_income[z] = float(_cost_zone_income[pz]) \
				* pow(float(_cost_zone_income[nz]) / float(_cost_zone_income[pz]), t)
		elif pz >= 0:
			_cost_zone_income[z] = float(_cost_zone_income[pz])

# v157 (D2): the Lira budget a zone-z player can put into ONE building.
# Monotone by construction — a later zone can never be poorer than an earlier
# one, so a material never loses its parallel source as the player advances.
func _cost_afford_at(z: int) -> float:
	var best := 0.0
	for zz in _cost_zone_income:
		if int(zz) <= z:
			best = maxf(best, float(_cost_zone_income[zz]))
	return best * COST_AFFORD_HOURS

# v157 (D2): the neutral rate of the best building for `sym` that a zone-z
# player can actually own. 0.0 means "no parallel source yet at this zone".
func _cost_infra_rate_at(sym: String, z: int) -> float:
	var budget := _cost_afford_at(z)
	var best := 0.0
	for off in _cost_infra_offers.get(sym, []):
		if float(off[0]) <= budget:
			best = maxf(best, float(off[1]))
	return best

# v157 (D1): shortest input chain from `sym` back to a zero-input root, over the
# infrastructure forest. min-over-producers, so a design can never be flattered
# by a deep path the player would not take. A combat drop, a material with no
# building, and a building with no input key are all depth 0.
func _cost_depth_of(sym: String) -> int:
	if _cost_depth.has(sym):
		return int(_cost_depth[sym])
	if _cost_depth_visiting.has(sym):
		return 0
	if float(_cost_infra_rate.get(sym, 0.0)) <= 0.0:
		_cost_depth[sym] = 0
		return 0
	var im = GameState.infrastructure_manager
	if im == null:
		return 0
	_cost_depth_visiting[sym] = true
	var best := -1
	for bid in im.building_db:
		var d: Dictionary = im.building_db[bid]
		if not (d.get("yield", {}) as Dictionary).has(sym):
			continue
		var inp: Dictionary = d.get("input", {})
		if inp.is_empty():
			best = 0
			break
		var mx := 0
		for isym in inp:
			mx = maxi(mx, _cost_depth_of(String(isym)))
		if best < 0 or (1 + mx) < best:
			best = 1 + mx
	_cost_depth_visiting.erase(sym)
	if best < 0:
		best = 0
	_cost_depth[sym] = best
	return best

# ── v158: RULE DEPTH + MIN-DIRECT-DEPTH LIFT ───────────────────────────────
# Rule depth is the depth metric the min-direct-depth rule is measured against.
# It is the SAME shape as _cost_depth_of — min over producers of 1 + max over
# that producer's inputs, 0 for a producer with no inputs and 0 for a material
# with no producer — but taken over the union of BUILDINGS AND RECIPES.
#
# The union matters in both directions:
#   * _cost_depth_of alone scores every processing-only material 0, so
#     StainlessSteel (Fe 5 + Cr 2 + Ni 1) and TargetingChip (AdvCircuit 3 +
#     Steel 20 + Circuit 10) would have been banned from every late zone
#     alongside the zero-input drills they are nothing like.
#   * the recipe metric alone can be FLATTENED by a combat shortcut —
#     process_colony_salvage turns a Zone-6 drop straight into AdvCircuit, which
#     would score AdvCircuit 1 and make the endgame's deepest building item
#     illegal at Z8. So the result is floored at _cost_depth_of, which only ever
#     sees the infrastructure forest.
# min-over-producers is kept on purpose inside each metric: the rule must not be
# satisfiable by a deep path nobody takes.
var _cost_rdepth := {}
var _cost_rdepth_vis := {}

func _cost_rdepth_of(sym: String) -> int:
	if _cost_rdepth.has(sym):
		return int(_cost_rdepth[sym])
	if _cost_rdepth_vis.has(sym):
		return 0
	_cost_rdepth_vis[sym] = true
	var im = GameState.infrastructure_manager
	var pm = GameState.processing_manager
	var best := -1
	if im:
		for bid in im.building_db:
			var d: Dictionary = im.building_db[bid]
			if not (d.get("yield", {}) as Dictionary).has(sym):
				continue
			var inp: Dictionary = d.get("input", {})
			if inp.is_empty():
				best = 0
				break
			var mx := 0
			for i in inp:
				mx = maxi(mx, _cost_rdepth_of(String(i)))
			if best < 0 or (1 + mx) < best:
				best = 1 + mx
	if best != 0 and pm:
		for rid in pm.recipes:
			var r: Dictionary = pm.recipes[rid]
			if not (r.get("output", {}) as Dictionary).has(sym):
				continue
			var inp2: Dictionary = r.get("input", {})
			if inp2.is_empty():
				best = 0
				break
			var mx2 := 0
			for i2 in inp2:
				mx2 = maxi(mx2, _cost_rdepth_of(String(i2)))
			if best < 0 or (1 + mx2) < best:
				best = 1 + mx2
	_cost_rdepth_vis.erase(sym)
	if best < 0:
		best = 0
	best = maxi(best, _cost_depth_of(sym))
	_cost_rdepth[sym] = best
	return best

# Cheapest processing level_req among the recipes that make `sym`; -1 when no
# recipe makes it. Built lazily off pm.recipes so it re-tunes with the data.
var _cost_serial_level := {}

func _cost_min_level_of(sym: String) -> int:
	if _cost_serial_level.has(sym):
		return int(_cost_serial_level[sym])
	var pm = GameState.processing_manager
	var best := -1
	if pm:
		for rid in pm.recipes:
			var r: Dictionary = pm.recipes[rid]
			if not (r.get("output", {}) as Dictionary).has(sym):
				continue
			var lv: int = int(r.get("level_req", 1))
			if best < 0 or lv < best:
				best = lv
	_cost_serial_level[sym] = best
	return best

# The zone a research tech becomes reachable at. zone_N_access is exact; every
# other tech is placed at its TIER, which is the same axis — zone_N_access itself
# sits at tier N in research_manager, so tier is the game's own statement of
# "how far in is this".
func _cost_tech_zone(tech: String) -> int:
	if tech == "":
		return 0
	if tech.begins_with("zone_") and tech.ends_with("_access"):
		return int(tech.substr(5, tech.length() - 12))
	var rm = GameState.research_manager
	if rm == null:
		return 0
	var t: Dictionary = (rm.tech_tree as Dictionary).get(tech, {})
	return int(t.get("tier", 0))

# Rule 4, enforced instead of assumed: NOTHING MAY BE UNBUILDABLE WHEN ITS ZONE
# UNLOCKS. A material is reachable at zone z when the player can own a building
# for it at that zone (the affordability model band 1 already prices with),
# gather it, kill for it in a zone already open, or CRAFT it — and "craft it" is
# recursive: the recipe's research tier and level_req must be within the zone AND
# every input must itself be reachable.
#
# The recursion is the load-bearing part. Without it the first run of this pass
# lifted Si at Zone 3 onto PtCatalyst (craft_platinum_catalyst is level 25, so it
# looked legal) whose Pt line needs a 2,000,000-Lira platinum_drill — 158 minutes
# of impossible work billed to a MANDATORY tutorial-chain module. With it,
# Superalloy is correctly unreachable at Z3 (Ni/Cr/Co are 800-900 K buildings
# with no recipe at all) and reachable from Z5.
var _cost_reach_cache := {}
func _cost_reachable_at(sym: String, z: int, depth: int = 0) -> bool:
	var key := sym + "@" + str(z)
	if _cost_reach_cache.has(key):
		return bool(_cost_reach_cache[key])
	# 14, not 8: the alloy ladder alone is nine rungs deep (AeonAlloy back to
	# ChondriteAlloy), and a cap of 8 declared the Zone-10 signature alloy
	# unreachable purely by running out of recursion budget.
	if depth > 14:
		return false
	if _cost_infra_rate_at(sym, z) > 0.0:
		_cost_reach_cache[key] = true
		return true
	var gm = GameState.gathering_manager
	if gm:
		for aid in gm.actions:
			for row in (gm.actions[aid] as Dictionary).get("loot_table", []):
				if String(row[0]) == sym:
					_cost_reach_cache[key] = true
					return true
	for zz in _cost_combat_zones.get(sym, []):
		if int(zz) <= z:
			_cost_reach_cache[key] = true
			return true
	_cost_reach_cache[key] = false      # cycle guard: unreachable until proven
	var pm = GameState.processing_manager
	var ok := false
	if pm:
		for rid in pm.recipes:
			var r: Dictionary = pm.recipes[rid]
			if not (r.get("output", {}) as Dictionary).has(sym):
				continue
			if int(r.get("level_req", 1)) > int(COST_ZONE_PROC_LEVEL.get(z, 99)):
				continue
			if _cost_tech_zone(String(r.get("research_req", ""))) > z:
				continue
			var all_in := true
			for i in r.get("input", {}):
				if not _cost_reachable_at(String(i), z, depth + 1):
					all_in = false
					break
			if all_in:
				ok = true
				break
	_cost_reach_cache[key] = ok
	return ok

# The deep item that replaces `sym` at zone z, or "" when the game contains no
# deeper consumer the player can actually reach there. Recursive through
# COST_DEPTH_LIFT so one table covers Fe -> Steel -> Superalloy -> NeutroniumPlate.
#
# Candidates are taken SHALLOWEST-FIRST among those that clear the floor, and
# anything more than COST_LIFT_OVERSHOOT above the floor is refused: the ruling
# is "one tier deeper than you were naming", not "jump to the endgame item".
const COST_LIFT_OVERSHOOT := 1

func _cost_lift(sym: String, z: int, floor_d: int, depth: int = 0) -> String:
	if _cost_rdepth_of(sym) >= floor_d and _cost_reachable_at(sym, z):
		return sym
	if depth > 6:
		return ""
	var best := ""
	var best_d := 99
	for cand in COST_DEPTH_LIFT.get(sym, []):
		var c := String(cand)
		if c == sym:
			continue
		var cd := _cost_rdepth_of(c)
		if cd < floor_d or cd > floor_d + COST_LIFT_OVERSHOOT:
			continue
		if not _cost_reachable_at(c, z):
			continue
		if cd < best_d:
			best_d = cd
			best = c
	if best != "":
		return best
	for cand2 in COST_DEPTH_LIFT.get(sym, []):
		var c2 := String(cand2)
		if c2 == sym:
			continue
		var deeper := _cost_lift(c2, z, floor_d, depth + 1)
		if deeper != "":
			return deeper
	return ""

# ── v158 (E3): TRANSITIVE MINUTES PER UNIT ─────────────────────────────────
# The single biggest measured error in v157 was pricing a material at its OWN
# recipe's duration and ignoring the input chain: WreckforgedAlloy was billed at
# 13 s although refine_wreckforged_alloy also needs a ChondriteAlloy, 12 Steel
# and 2 MartianRelics. That is how a 3.9-hour pre-Warmaster bundle got reported
# as 1.01 h.
#
# _cost_mpu is a fixed point over the SINGLE FOREGROUND SLOT:
#   gather                    -> 1 / (units per minute)
#   recipe                    -> duration/out + SUM in qty/out * mpu(in)
#   AFFORDABLE building at z  -> SUM in qty/out * mpu(in)   (the conversion runs
#                                in parallel with the active task, so it costs no
#                                foreground minutes; its INPUTS still do)
#   combat drop in a zone <= z -> (1 / drop per kill) / kills-per-hour * 60
# The serial band (1b) is priced against this instead of against the material's
# nominal recipe rate, so a serial budget of N minutes buys N minutes of REAL
# work however deep the material sits. Without it the budget was fictional:
# ReinforcedPlating was billed at its 12 s duration and actually costs 2.83 min
# because craft_reinforced_plating carries 4 SalvagedAlloy + 2 DamagedCircuitry.
const COST_MPU_INF := 1.0e18
var _cost_mpu_by_zone := {}

func _cost_build_mpu(z: int) -> Dictionary:
	if _cost_mpu_by_zone.has(z):
		return _cost_mpu_by_zone[z]
	var im = GameState.infrastructure_manager
	var pm = GameState.processing_manager
	var gm = GameState.gathering_manager
	var m := {}
	var syms := {}
	if pm:
		for rid in pm.recipes:
			for a in (pm.recipes[rid] as Dictionary).get("output", {}):
				syms[String(a)] = true
			for b in (pm.recipes[rid] as Dictionary).get("input", {}):
				syms[String(b)] = true
	if im:
		for bid in im.building_db:
			for c in (im.building_db[bid] as Dictionary).get("yield", {}):
				syms[String(c)] = true
			for d in (im.building_db[bid] as Dictionary).get("input", {}):
				syms[String(d)] = true
	for s in _cost_drop_rate:
		syms[String(s)] = true
	for s2 in syms:
		m[String(s2)] = COST_MPU_INF
	if gm:
		for aid in gm.actions:
			var act: Dictionary = gm.actions[aid]
			var du: float = maxf(0.001, float(act.get("duration", 3.0)))
			for row2 in act.get("loot_table", []):
				var sg := String(row2[0])
				var avg: float = (float(row2[2]) + float(row2[3])) * 0.5 * float(row2[1])
				if avg <= 0.0:
					continue
				m[sg] = minf(float(m.get(sg, COST_MPU_INF)), 1.0 / (avg / du * 60.0))
	for sk in _cost_drop_rate:
		var sks := String(sk)
		for zz2 in (_cost_drop_rate[sk] as Dictionary):
			if int(zz2) > z:
				continue
			var dpk: float = float((_cost_drop_rate[sk] as Dictionary)[zz2])
			if dpk > 0.0:
				m[sks] = minf(float(m.get(sks, COST_MPU_INF)),
					(1.0 / dpk) / COST_KILLS_PER_HOUR * 60.0)
	var budget := _cost_afford_at(z)
	for _it in range(40):
		var changed := false
		if pm:
			for rid2 in pm.recipes:
				var r2: Dictionary = pm.recipes[rid2]
				for so in r2.get("output", {}):
					var sos := String(so)
					var o: float = maxf(0.0001, float(r2["output"][so]))
					var cr: float = float(r2.get("duration", 1.0)) / 60.0 / o
					var okr := true
					for i2 in r2.get("input", {}):
						var iv: float = float(m.get(String(i2), COST_MPU_INF))
						if iv >= COST_MPU_INF:
							okr = false
							break
						cr += float(r2["input"][i2]) / o * iv
					if okr and cr < float(m.get(sos, COST_MPU_INF)) - 1e-9:
						m[sos] = cr
						changed = true
		if im:
			for bid2 in im.building_db:
				var bd: Dictionary = im.building_db[bid2]
				if float((bd.get("cost", {}) as Dictionary).get("credits", 0)) > budget:
					continue
				for sy in bd.get("yield", {}):
					var sys2 := String(sy)
					var o2: float = maxf(0.0001, float(bd["yield"][sy]))
					var cb2 := 0.0
					var okb := true
					for i3 in bd.get("input", {}):
						var iv2: float = float(m.get(String(i3), COST_MPU_INF))
						if iv2 >= COST_MPU_INF:
							okb = false
							break
						cb2 += float(bd["input"][i3]) / o2 * iv2
					if okb and cb2 < float(m.get(sys2, COST_MPU_INF)) - 1e-9:
						m[sys2] = cb2
						changed = true
		if not changed:
			break
	_cost_mpu_by_zone[z] = m
	return m

func _cost_mpu(sym: String, z: int) -> float:
	var m := _cost_build_mpu(z)
	var v: float = float(m.get(sym, COST_MPU_INF))
	if v >= COST_MPU_INF or v <= 0.0:
		# no expanded path the model can see: fall back to the nominal rate
		# rather than pricing the line at infinity (which would zero it).
		return 1.0 / maxf(_cost_rate_at(sym, z), 0.0001)
	return v

# v157 (D3): expected units of `sym` per kill in zone `z`, averaged over that
# zone's regular roster. 0.0 if it does not drop there.
func _cost_drop_per_kill(sym: String, z: int) -> float:
	return float((_cost_drop_rate.get(sym, {}) as Dictionary).get(z, 0.0))

# INFRA (a building yields it) > SERIAL (a recipe or gather action makes it) >
# COMBAT (only an enemy drops it). Steel is both smelted and building-made, and
# it is INFRA — the parallel source is the one that decides the band.
func _cost_class(sym: String) -> String:
	if float(_cost_infra_rate.get(sym, 0.0)) > 0.0:
		return "INFRA"
	if float(_cost_serial_rate.get(sym, 0.0)) > 0.0:
		return "SERIAL"
	if _cost_combat_zones.has(sym):
		return "COMBAT"
	return "UNKNOWN"

# v157 (D2): the same decision, but asked at a zone. A material whose only
# building the player cannot buy yet is SERIAL at that zone, not INFRA — which
# is what the player experiences. Falls back to INFRA when there is no serial
# path at all (U, Neutronium, VoidCrystal), because "you must save for the
# building" is then the true answer.
func _cost_class_at(sym: String, z: int) -> String:
	var combat_only: bool = _cost_combat_zones.has(sym) \
		and float(_cost_infra_rate.get(sym, 0.0)) <= 0.0 \
		and float(_cost_serial_rate.get(sym, 0.0)) <= 0.0
	if combat_only:
		return "COMBAT"
	if _cost_infra_rate_at(sym, z) > 0.0:
		return "INFRA"
	if float(_cost_serial_rate.get(sym, 0.0)) > 0.0:
		return "SERIAL"
	if float(_cost_infra_rate.get(sym, 0.0)) > 0.0:
		return "INFRA"
	if _cost_combat_zones.has(sym):
		return "COMBAT"
	return "UNKNOWN"

# The rate the curve should charge at: the affordable building if there is one,
# otherwise the serial recipe.
func _cost_rate_at(sym: String, z: int) -> float:
	var r := _cost_infra_rate_at(sym, z)
	if r > 0.0:
		return r
	var s := float(_cost_serial_rate.get(sym, 0.0))
	if s > 0.0:
		return s
	return maxf(float(_cost_infra_rate.get(sym, 0.0)), 0.0001)

# Is every production path for `sym` fed, somewhere upstream, by an enemy drop?
# Combat is the one thing infrastructure cannot parallelise (one enemy at a
# time — the fleet system is deliberately not activated), so a material whose
# CHEAPEST path still touches a drop cannot be treated as bulk-automatable no
# matter how many buildings the player owns. Takes the min over every building
# and every recipe that makes it, so one clean path is enough to stay foundation.
var _cost_combat_fed_cache := {}
func _cost_is_combat_fed(sym: String, depth: int = 0) -> bool:
	if _cost_combat_fed_cache.has(sym):
		return bool(_cost_combat_fed_cache[sym])
	if depth > 10:
		return false
	if _cost_class(sym) == "COMBAT":
		return true
	_cost_combat_fed_cache[sym] = true          # cycle guard: assume fed until proven clean
	var im = GameState.infrastructure_manager
	var pm = GameState.processing_manager
	var clean := false
	var any_path := false
	if im:
		for bid in im.building_db:
			var d: Dictionary = im.building_db[bid]
			if not (d.get("yield", {}) as Dictionary).has(sym):
				continue
			any_path = true
			var fed := false
			for isym in d.get("input", {}):
				if _cost_is_combat_fed(String(isym), depth + 1):
					fed = true
					break
			if not fed:
				clean = true
				break
	if not clean and pm:
		for rid in pm.recipes:
			var r: Dictionary = pm.recipes[rid]
			if not (r.get("output", {}) as Dictionary).has(sym):
				continue
			any_path = true
			var fed2 := false
			for isym2 in r.get("input", {}):
				if _cost_is_combat_fed(String(isym2), depth + 1):
					fed2 = true
					break
			if not fed2:
				clean = true
				break
	# A material with no producer at all (a raw gathered resource) is clean.
	var res: bool = (not clean) and any_path
	_cost_combat_fed_cache[sym] = res
	return res

# Does `sym` drop in the module's OWN zone or later? Own-zone combat is free to
# be generous; anything that only drops behind the player is backward debt.
func _cost_drop_is_own_zone(sym: String, z: int) -> bool:
	for zz in _cost_combat_zones.get(sym, []):
		if int(zz) >= z:
			return true
	return false

func _cost_skip(m_data: Dictionary) -> bool:
	# The shipped skip set, reproduced exactly: custom, matrix cores, no cost.
	if m_data.get("is_custom", false):
		return true
	var st := String(m_data.get("slot_type", ""))
	if st == "gem" or st == "gem_synth" or st == "relic":
		return true
	if not m_data.has("cost"):
		return true
	# The 46 Unique boss templates carry cost == {} as the documented
	# "uncraftable" sentinel. Writing costs into them would list 46 phantom
	# consumers in the Atlas and the material-uses panel.
	if m_data.get("unique", false):
		return true
	if (m_data.get("cost", {}) as Dictionary).is_empty():
		return true
	# The Z11 Cryo Lance and Z12 Corrosion Blaster are the NG+ gates and are
	# tuned against the Threshold / Rift Wardens. Their dicts are authored at
	# their final charged values and opt out of the zone curve — they are NOT
	# skipped for carrying a `rarity`, which is the trap that would have
	# collapsed Superalloy 2582 -> 50 on the Z11 gate.
	if m_data.get("cost_authored", false):
		return true
	var z: int = int(m_data.get("zone", 0))
	if z < COST_CURVE_MIN_ZONE or z > COST_CURVE_MAX_ZONE:
		return true
	return false

func compose_module_costs() -> void:
	_build_cost_index()
	for module_id in modules:
		var m_data: Dictionary = modules[module_id]
		if not _authored_module_costs.has(module_id):
			if not m_data.has("cost"):
				continue
			_authored_module_costs[module_id] = (m_data["cost"] as Dictionary).duplicate(true)
		if _cost_skip(m_data):
			continue
		m_data["cost"] = _compose_one_cost(String(module_id), m_data)
		modules[module_id] = m_data

func _compose_one_cost(module_id: String, m_data: Dictionary) -> Dictionary:
	var authored: Dictionary = _authored_module_costs[module_id]
	var z: int = int(m_data.get("zone", 0))
	var st := String(m_data.get("slot_type", ""))
	var w: float = float(COST_SLOT_WEIGHT.get(st, 1.0))
	var out := {}
	if authored.has("credits"):
		out["credits"] = int(authored["credits"])

	var infra_mats: Array = []
	var serial_mats: Array = []
	var composite_mats: Array = []
	var own_combat: Array = []
	var back_combat: Array = []
	for sym in authored:
		var s := String(sym)
		if s == "credits":
			continue
		# v157 (D2): classified AT THIS ZONE. A material whose only building the
		# player cannot afford yet is serial here, and gets the serial curve.
		var cls := _cost_class_at(s, z)
		if cls == "COMBAT":
			if _cost_drop_is_own_zone(s, z): own_combat.append(s)
			else: back_combat.append(s)
		elif cls == "UNKNOWN":
			out[s] = int(authored[sym])         # no known source: leave it alone
		elif _cost_is_combat_fed(s):
			composite_mats.append(s)            # looks automatable, is not
		elif cls == "INFRA":
			infra_mats.append(s)
		else:
			serial_mats.append(s)

	# v158 (E2): onboarding ramp on the three non-parallel bands at Z3-Z4.
	var oramp: float = float(COST_ONBOARD_RAMP.get(z, 1.0))

	# ── BAND 2a: the zone signature alloy (weapon / armor / shield only) ──
	var alloy := String(TIER_ALLOY_BY_ZONE.get(z, ""))
	if alloy != "" and (st == "weapon" or st == "armor" or st == "shield") and not m_data.has("rarity"):
		var ab: float = float(COST_ALLOY_BASE.get(st, 5))
		out[alloy] = maxi(1, int(round(ab * pow(COST_ALLOY_STEP, float(z - 2)) * oramp)))
		infra_mats.erase(alloy)
		serial_mats.erase(alloy)
		composite_mats.erase(alloy)

	# ── BAND 1c: combat-fed composites — gate-priced, never bulk ──
	if z > COST_FOUNDATION_FREE_ZONES and not composite_mats.is_empty():
		var cb: float = float(COST_COMPOSITE_BASE.get(st, 5)) * pow(COST_COMPOSITE_STEP, float(z - 2)) * oramp
		var cper: int = maxi(1, int(round(cb / float(composite_mats.size()))))
		for sc in composite_mats:
			out[String(sc)] = cper

	# ── BAND 2b: own-zone combat signature, the hard ramp ──
	# v157 (D3): budgeted in KILLS. Every own-zone material gets the SAME kill
	# budget (drops fall off the same enemies at the same time, so the module's
	# real price is K kills however many materials it lists), and the unit count
	# is that budget times the material's MEASURED expected drop per kill.
	var drop := String(COST_ZONE_DROP.get(z, ""))
	if drop != "" and not (drop in own_combat):
		own_combat.append(drop)
	if not own_combat.is_empty():
		var kills: float = float(COST_OWNC_KILLS.get(st, 0.8)) * pow(COST_OWNC_STEP, float(z - 2)) * oramp
		for s3 in own_combat:
			var s3s := String(s3)
			var dpk := _cost_drop_per_kill(s3s, z)
			if dpk <= 0.0:
				# drops in a LATER zone only (a forward-reaching authored line):
				# price it off the earliest zone it actually drops in.
				for zz in _cost_combat_zones.get(s3s, []):
					if int(zz) >= z:
						dpk = maxf(dpk, _cost_drop_per_kill(s3s, int(zz)))
			var qf: float = kills * maxf(dpk, 0.0)
			if qf < 0.5 and s3s != drop:
				# Too rare for even ONE unit to fit the kill budget (Diamond is
				# 0.03/kill off Zone 8's regulars, so a single unit is 31 kills —
				# 2.4x the whole module's budget). Flooring it at 1 is exactly
				# the drop-rate-blind pricing D3 flagged, so this line is not a
				# bulk requirement for this module at all. The zone's signature
				# drop is never removed.
				continue
			out[s3s] = maxi(1, int(round(qf)))
	# v157 (D4): backward combat is DROPPED, not clamped. The v156 clamp still
	# left the line on the recipe; z9_battery kept Diamond 2 (Zone 8 only) and a
	# five-battery titan hull billed ~308 backward Zone-8 kills for it.
	if not COST_BACK_COMBAT_DROP:
		for s4 in back_combat:
			out[String(s4)] = int(authored[s4])

	# ── BAND 1 / 1b: foundation. Z1-Z2 keep their authored quantities. ──
	if z <= COST_FOUNDATION_FREE_ZONES:
		for s5 in infra_mats:
			out[String(s5)] = int(authored[s5])
		for s6 in serial_mats:
			out[String(s6)] = int(authored[s6])
		for s6c in composite_mats:
			out[String(s6c)] = int(authored[s6c])
		return out

	# ── v158: MIN-DIRECT-DEPTH LIFT (bands 1 and 1b only) ──
	# Every foundation line shallower than this zone's floor is re-pointed onto a
	# deeper item that consumes it. The budget is untouched: the same
	# building-minutes are simply not allowed to be spent shallow. A material with
	# no deeper consumer anywhere in the game is DROPPED rather than kept shallow,
	# and its share flows to the survivors and the zone's anchors.
	var floor_d: int = int(COST_MIN_DIRECT_DEPTH.get(z, 0))
	if floor_d > 0:
		var pool: Array = []
		for si in infra_mats:
			pool.append(String(si))
		for ss2 in serial_mats:
			pool.append(String(ss2))
		infra_mats = []
		serial_mats = []
		for sp in pool:
			var sps := String(sp)
			var tgt := _cost_lift(sps, z, floor_d)
			if tgt == "":
				out.erase(sps)
				continue
			if (tgt in infra_mats) or (tgt in serial_mats) or (tgt in composite_mats):
				out.erase(sps)
				continue
			if tgt != sps:
				out.erase(sps)
			if _cost_is_combat_fed(tgt):
				# The only deep expression is combat-fed, so it is a band-1c gate
				# quantity, never a bulk line. Do not silently turn a parallel
				# budget into an un-parallelisable grind.
				continue
			if _cost_class_at(tgt, z) == "INFRA":
				infra_mats.append(tgt)
			else:
				serial_mats.append(tgt)

	# v157 (D1): anchors are a LIST per zone and must be affordable at this zone,
	# otherwise the module would be billed at a rate no player can run.
	for a in COST_ZONE_ANCHOR.get(z, []):
		var anchor := String(a)
		if anchor == "" or (anchor in infra_mats) or (anchor in serial_mats):
			continue
		# v158: an anchor is a DIRECT line like any other, so it obeys the floor.
		# Belt and braces — the table above is authored to clear it already.
		if _cost_rdepth_of(anchor) < floor_d:
			continue
		# v158: rule 4 again — an anchor is charged to EVERY module of the zone,
		# so an unreachable one would make the whole zone uncraftable on unlock.
		if not _cost_reachable_at(anchor, z):
			continue
		if _cost_infra_rate_at(anchor, z) > 0.0:
			infra_mats.append(anchor)
		elif not (anchor in serial_mats) and float(_cost_serial_rate.get(anchor, 0.0)) > 0.0:
			serial_mats.append(anchor)

	var ramp: float = float(COST_BMIN_RAMP.get(z, 1.0))
	var bmin: float = COST_BMIN_Z3 * pow(COST_BMIN_STEP, float(z - 3)) * w * ramp
	# v158 (E2): the onboarding ramp applies to the SERIAL band too. It is the
	# same argument — Z1-Z2 are authored-untouched at ~0.6 building-minutes and
	# the mandatory Z3 chain must not be a cliff — and the serial band is the one
	# that costs exclusive foreground time.
	var smin: float = COST_SMIN_Z3 * pow(COST_SMIN_STEP, float(z - 3)) * w * float(COST_SMIN_RAMP.get(z, 1.0))
	# A weapon channel with no serial component must not be cheaper than one that
	# has a FocusingCrystal line for the same damage — fold the unspent budget
	# back into the parallel band rather than dropping it.
	if serial_mats.is_empty():
		bmin += smin
		smin = 0.0
	if infra_mats.is_empty():
		smin += bmin
		bmin = 0.0
	if not infra_mats.is_empty():
		# v157 (D1): split the building-minute budget by INFRA DEPTH, not evenly.
		# A zero-input drill gets weight 1; a depth-4 chain like AdvCircuit gets
		# 4.6, so the volume lands on the materials that actually pull a factory
		# tree behind them and keep the early lines running into the endgame.
		var wsum := 0.0
		var dw := {}
		for sd in infra_mats:
			var sds := String(sd)
			# v158 (E4): PARALLELISM DISCOUNT. Band 1 exists because its materials
			# run in the background; the budget is building-minutes precisely
			# because those minutes are not foreground minutes. But some
			# "automatable" materials still drag a serial sub-chain: at Zone 3 one
			# Circuit costs 0.309 foreground minutes even though its own building
			# is affordable, because electronics_assembler needs Resin and nothing
			# makes Resin but a recipe. Measured, that one line was 40 of the 108
			# minutes on the mandatory pre-Warmaster bundle while Steel — same
			# band, deeper root content — was 16.
			# residue = how many foreground minutes one building-minute of this
			# line actually costs. 1.0 means genuinely parallel (Steel: 0.0122
			# min/unit x 30 units/min = 0.37, clamped to 1). Circuit measures 4.8,
			# so it gets 1/4.8 of the share its depth alone would have won.
			var residue: float = maxf(1.0, _cost_mpu(sds, z) * _cost_rate_at(sds, z))
			var ww: float = (1.0 + COST_DEPTH_WEIGHT * float(_cost_depth_of(sds))) / residue
			dw[sds] = ww
			wsum += ww
		for s7 in infra_mats:
			var s7s := String(s7)
			var each_b: float = bmin * float(dw[s7s]) / maxf(wsum, 0.0001)
			out[s7s] = maxi(1, int(round(each_b * _cost_rate_at(s7s, z))))
	if not serial_mats.is_empty():
		var each_s: float = smin / float(serial_mats.size())
		for s8 in serial_mats:
			var s8s := String(s8)
			# v158 (E3): TRANSITIVE. Was `each_s * rate`, i.e. the material's own
			# recipe throughput with its input chain ignored — the same error the
			# v157 probe made when it reported a 3.9 h bundle as 1.01 h.
			out[s8s] = maxi(1, int(round(each_s / _cost_mpu(s8s, z))))
	return out

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

# v149 UNIFORM CADENCE MIGRATION. Every authored weapon atk_interval is now
# CombatManager.DEFAULT_ATTACK_INTERVAL (2.0). The 19 explosive/missile modules
# moved 4.0 -> 2.0 with their atk_explosive halved, so their DPS is unchanged.
#
# Saved custom drops rolled off the OLD 4.0 base keep a stored interval in
# [2.40, 4.00] (the roll range is [base x0.6, base]), which does not overlap the
# new missile range [1.20, 2.00] — so ">= the new base + epsilon" is an exact,
# unambiguous test for a pre-v149 missile roll. Those items are rescaled by
# k = new_base / old_base on BOTH the interval and every damage channel, which
# preserves their DPS *and* their rarity roll exactly: the migrated item is
# bit-identical to the fresh drop that same roll would produce today.
#
# Without this the old drops keep a 2.4-4.0s cadence forever — DPS-correct but in
# violation of the owner's one-cadence rule, and with every per-SHOT mechanic
# (ammo burn, heal_on_hit, vuln uptime) stuck at half rate versus a fresh drop.
const _V149_OLD_WEAPON_BASES := [2.0, 4.0]
const _V149_DMG_KEYS := ["atk_kinetic", "atk_energy", "atk_explosive", "atk_cryo"]

func _migrate_uniform_atk_interval() -> void:
	var moved := 0
	for mid in custom_modules.keys():
		var m: Dictionary = custom_modules[mid]
		var stats: Dictionary = m.get("stats", {})
		if not stats.has("atk_interval"):
			continue
		var base_id: String = m.get("base_module", "")
		if base_id == "" or not base_id in modules:
			continue
		var new_base: float = float(modules[base_id].get("stats", {}).get("atk_interval", 0.0))
		if new_base <= 0.0:
			continue
		var cur: float = float(stats["atk_interval"])
		# Anything at or under the current base was rolled off it — nothing to do.
		if cur <= new_base + 0.0001:
			continue
		# Infer the pre-v149 base: the smallest authored base that could have
		# produced this stored roll (roll range is [old_base x 0.6, old_base]).
		var old_base: float = 0.0
		for b in _V149_OLD_WEAPON_BASES:
			var bf: float = float(b)
			if cur <= bf + 0.0001 and cur >= bf * 0.6 - 0.0001:
				old_base = bf
				break
		if old_base <= 0.0 or is_equal_approx(old_base, new_base):
			continue
		var k: float = new_base / old_base
		var new_iv := snappedf(cur * k, 0.01)
		# Compute FIRST, assign second. `modules[mid]` is usually the very same
		# Dictionary object as `custom_modules[mid]`, so a read-modify-write applied
		# to both mirrors would scale the damage twice (measured: x0.25 instead of
		# x0.5, i.e. a silent 50% DPS loss on every migrated drop). Assignment of a
		# precomputed value is idempotent whether the two are aliases or copies.
		var new_dmg := {}
		for dk in _V149_DMG_KEYS:
			if stats.has(dk):
				new_dmg[dk] = snappedf(float(stats[dk]) * k, 0.01)
		stats["atk_interval"] = new_iv
		for dk in new_dmg:
			stats[dk] = new_dmg[dk]
		# The modules dict is a live mirror that contains custom_modules — keep them in sync.
		if mid in modules:
			var mm: Dictionary = modules[mid].get("stats", {})
			mm["atk_interval"] = new_iv
			for dk2 in new_dmg:
				if mm.has(dk2):
					mm[dk2] = new_dmg[dk2]
		moved += 1
	if moved > 0:
		print("[Migration] Rebased %d saved weapon drop(s) onto the uniform base cadence (DPS and rarity roll preserved)." % moved)


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
		var channel := ""
		if stats.get("atk_kinetic", 0) > 0:
			channel = "kinetic"
		elif stats.get("atk_energy", 0) > 0:
			channel = "energy"
		# v65.0 Fix: Auto-equip for Explosive weapons mismatch
		elif stats.get("atk_explosive", 0) > 0:
			# v134: MissileT1 is the real recipe output (craft_missile_t1). "missile" was
			# a phantom key the player could never craft, so the launcher auto-loaded ammo
			# it had zero of and fired empty. Set it unconditionally like kinetic/energy.
			channel = "explosive"
		if channel != "":
			ammo_loadout[slot_idx] = _auto_ammo_for_module(mod_data, channel)
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

# v147: the TWO-STRIKE durability rule, stated by the owner:
#   strike 1 — a defeat wears every equipped module down to 50% durability.
#              Nothing is ever destroyed on this strike. Pristine gear is SAFE.
#   strike 2 — a defeat taken while a module is ALREADY at <=50% durability can
#              destroy it.
# v125 implemented only strike 1 and wrote the second half off as "offline-only",
# which was a misreading: losing online then cost time + Spare Parts but never
# gear, so bringing the wrong loadout had almost no consequence.
#
# Sizing the chance against the pre-v125 precedent (1/6 instant-destroy per
# defeat): we keep the SAME 1/6 number, but re-shaped so it can only ever cost
# ONE module per defeat.
#   - The old 1/6 rolled independently on EVERY equipped module, on the FIRST
#     defeat, with no warning and no way to opt out — a bad fight could wipe
#     several slots at once.
#   - The new 1/6 is a SINGLE roll per defeat; on a hit, exactly one of the worn
#     modules is destroyed, chosen at random. It only fires on strike 2+, after
#     the player has seen "DUR 50%" and an orange Repair button on the slot.
# So the headline number is unchanged (the punishment keeps its teeth) while the
# variance that made the old system feel arbitrary is gone. Expected cost of
# ignoring the warning: ~1 module per 6 losses, never a full-ship wipe from one
# bad engage — which matters in an idle game where a stray fight can chain.
# v146 owner spec: FLAT 50%, no rarity weighting, rolled INDEPENDENTLY for every
# equipped module already at <=50 durability when a fight is lost. No cap — a full
# worn loadout can go in one defeat. With 8 worn slots that averages ~4 lost and
# leaves only a ~0.4% chance of losing nothing, so the 50% durability mark has to
# read as a real warning: see the DUR/Repair surfacing note in handle_module_defeat.
const MODULE_DESTROY_CHANCE: float = 0.5

# Slots holding a module that is ALREADY worn to <=50% durability, i.e. the
# strike-2 pool. Evaluated BEFORE this defeat's wear is applied, so a module that
# only just dropped to 50 this fight is never in it.
func _worn_equipped_slots() -> Array:
	var out: Array = []
	for slot_idx in loadout:
		var mid = loadout[slot_idx]
		if not mid or String(mid) == "": continue
		if not (mid in modules): continue
		# Only custom instances carry per-item durability; base defs are shared
		# templates and must never be erased from `modules`.
		if not String(mid).begins_with("custom_"): continue
		if sim_protect_batteries and String(modules[mid].get("slot_type", "")) == "battery":
			continue   # sim-only: see sim_protect_batteries note
		if int(modules[mid].get("durability", 100)) <= 50:
			out.append(slot_idx)
	return out

# Full teardown of ONE destroyed equipped module instance. Reuses the v146
# _migrate_remove_architects_regalia approach (sockets refunded exactly like
# remove_gem, then the id purged from every container that can reference it)
# rather than growing a second, divergent deletion path.
# Returns the display name for the notification, or "" if nothing was removed.
func _destroy_equipped_module(slot_idx: int) -> String:
	var mid = loadout.get(slot_idx)
	if mid == null or String(mid) == "":
		return ""
	var m_id: String = String(mid)
	var def_d: Dictionary = {}
	if custom_modules.has(m_id) and custom_modules[m_id] is Dictionary:
		def_d = custom_modules[m_id]
	elif modules.has(m_id) and modules[m_id] is Dictionary:
		def_d = modules[m_id]
	var disp: String = String(def_d.get("name", m_id))

	# Matrix cores go back to the element pool — same as remove_gem. Silently
	# eating a socketed Resonant core would be worse than losing the module.
	var socks = def_d.get("sockets", [])
	if socks is Array:
		for gi in range(socks.size()):
			var g = socks[gi]
			if g != null and String(g) != "":
				if GameState.resources:
					GameState.resources.add_element(String(g), 1)
			socks[gi] = null

	# The live ship: slot + its ammo binding.
	loadout[slot_idx] = null
	ammo_loadout.erase(slot_idx)
	ammo_loadout.erase(str(slot_idx))
	if equipped_relic == m_id:
		equipped_relic = ""

	# Every container that can still name it. A custom instance is unique (one
	# copy, currently equipped), so these are all defensive except the layout /
	# unseen bookkeeping.
	module_inventory.erase(m_id)
	custom_modules.erase(m_id)
	modules.erase(m_id)
	unseen_modules.erase(m_id)
	armory_layout.erase(m_id)

	# Build presets keep their slot, minus the destroyed module (v146 pattern).
	for p_key in loadout_presets.keys():
		var p = loadout_presets[p_key]
		if not (p is Dictionary):
			continue
		var p_load = p.get("loadout", {})
		if not (p_load is Dictionary):
			continue
		var p_ammo = p.get("ammo_loadout", {})
		for s_key in p_load.keys():
			var pm = p_load[s_key]
			if pm != null and String(pm) == m_id:
				p_load[s_key] = null
				if p_ammo is Dictionary:
					p_ammo.erase(s_key)
	return disp

# One short factual line naming what was lost — never a silent deletion.
# Routed through the SAME notification path combat losses already use
# (UITheme.show_notification) plus the combat log; no second system.
func _announce_module_destroyed(disp: String) -> void:
	if disp == "":
		return
	UITheme.show_notification(tr("MODULE DESTROYED: %s") % disp.to_upper(), UITheme.COLORS["negative"])
	log_msg("DESTROYED: %s was at 50%% durability and did not survive the defeat." % disp)

func handle_module_defeat():
	# See MODULE_DESTROY_CHANCE above for the two-strike rule.
	var changed := false
	# Strike-2 pool, sampled BEFORE this defeat's wear is applied.
	var worn_slots: Array = _worn_equipped_slots()
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

	# STRIKE 2 (owner spec, verbatim): "you can lose all your loadout or none, we
	# roll the dice for EACH gear that has <=50% durability in the fight lost
	# loadout" — so this is an INDEPENDENT roll per worn module, not one roll that
	# picks a single victim, and there is deliberately NO cap. A full worn loadout
	# can be wiped by one defeat. Modules floored to 50 by THIS defeat are still
	# exempt: strike 1 is always safe, which is what makes the 50% mark a warning
	# the player is given a chance to act on rather than an ambush.
	var destroyed_names: Array = []
	for slot_idx in worn_slots:
		if randf() < MODULE_DESTROY_CHANCE:
			var nm: String = _destroy_equipped_module(slot_idx)
			if nm != "":
				destroyed_names.append(nm)
				changed = true
	var destroyed_name: String = ", ".join(destroyed_names)

	if changed:
		if worn_slots.is_empty():
			log_msg("DEFEAT: equipped modules worn down to 50% durability — repair with Spare Parts.")
		else:
			log_msg("DEFEAT: worn modules (50% durability) are at risk of destruction — repair with Spare Parts.")
		_announce_module_destroyed(destroyed_name)
		recalc_stats()
		inventory_updated.emit()
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
	# OFFLINE combat is opt-in + consented, and it runs unattended, so it keeps a
	# destruction risk on modules ALREADY worn to <=50% durability. Pristine/>50%
	# gear is always safe; repairing before logging off carries ZERO risk. Returns
	# destroyed display names so the offline report names the loss (never silent).
	#
	# v147 parity with the online two-strike rule: offline combat is winnability-
	# gated (_offline_winnable), so it never produces a DEFEAT — it can't legitimately
	# punish harder than losing a real fight does. It was doing exactly that: a
	# 5%/hr, 35%-capped roll on EVERY worn module meant an 8-hour night could delete
	# ~3 modules with no fight lost at all, which now that strike 2 exists online
	# would be a straight double-punish. Reshaped to match the online rule exactly:
	# ONE roll per return, at most ONE module destroyed, at the same
	# MODULE_DESTROY_CHANCE — ramped in over the first hour away so a short absence
	# is proportionally safer and a quick alt-tab is ~free. It also now runs the
	# SAME full teardown (sockets refunded, presets scrubbed); the old inline path
	# silently ate socketed matrix cores and left dead ids in the presets/armory.
	var destroyed: Array = []
	var hours: float = delta / 3600.0
	var p: float = MODULE_DESTROY_CHANCE * clampf(hours, 0.0, 1.0)
	if p <= 0.0:
		return destroyed
	var worn_slots: Array = _worn_equipped_slots()
	if worn_slots.is_empty():
		return destroyed
	if randf() >= p:
		return destroyed
	var victim = worn_slots[randi() % worn_slots.size()]
	var disp: String = _destroy_equipped_module(victim)
	if disp == "":
		return destroyed
	destroyed.append(disp)
	recalc_stats()
	inventory_updated.emit()   # was dead code AFTER the return below — the armory
							   # never refreshed after offline module destruction
	_autosave_active_preset()
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
	# v155: `atk_k += affix_bonuses["flat_atk"]` REMOVED. VERIFIED before removal:
	# atk_k lands only in attack_kinetic, and attack_kinetic is read by exactly
	# three places — mission_manager's (sum > 0) liveness test, atlas_page's DPS
	# readout, and the `attack` display total. The COMBAT path never touches it:
	# _rebuild_player_weapon_states builds dmg_k/dmg_e/dmg_x straight off each
	# module's own atk_kinetic/atk_energy/atk_explosive stat. So the line moved no
	# damage — it only made the ship sheet's KINETIC number larger, on any build,
	# including a pure energy or missile one.
	# That was a per-channel display lie with no mechanical backing, so it goes.
	# SEPARATE, LARGER FINDING, deliberately NOT fixed here: the flat_atk affix
	# ("Sharpened Edge" / "of Lethality", range 2-5, weapons only) is COMBAT-DEAD
	# in its entirety — same class as the flat_accuracy affix v145 deleted. Wiring
	# it into weapon_states would move every measured TTK in the game, so it needs
	# its own pass with a full invariant re-measure; deleting it needs an affix
	# migration for rolled items. Flagged, not silently patched.

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
	_migrate_uniform_atk_interval()
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
		# v161: this claimed to pay "for this rarity/zone" but used the flat
		# rarity table, so after the tier weighting landed it refunded 1/20th of
		# the real recycle value at Z10. Price it off the same tier weight.
		if copies > 0:
			copies_total += copies
			var comp_w: float = float(RECYCLE_TIER_WEIGHT.get(clampi(int(zone), 1, 10), 1.0))
			var parts: int = maxi(1, int(round(float(RARITY_SPARE_PARTS.get(rarity, 1)) * comp_w))) * copies
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
	# v150b: the runtime ammo fallback is a pure cache over live stock, but a warp
	# or new game changes both the stock and the slot layout — drop it so nothing
	# resolves against a pre-reset ship.
	_ammo_fallback_cache.clear()
	_ammo_fallback_at.clear()
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

# v150 BAND-AWARE AUTO-EQUIP. equip_module used to hardcode SlugT1/CellT1/
# MissileT1 regardless of the weapon, which is measurably where the "T1 rounds in
# an endgame railgun" default came from — a Z10 kinetic module auto-loaded T1 and
# ran at 1.00x forever while the whole T2-T4 ladder sat unused (AMMO_TIER_MULT
# tops out at 1.35x). This picks the weapon's designed band instead.
#
# CRITICAL — it only ever selects ammo the player ACTUALLY HOLDS, then steps DOWN
# to T1 as the final fallback. Selecting an unheld band id would hand the player a
# weapon with an empty stack, and combat_manager's `_warn_no_ammo(); return` means
# such a weapon deals ZERO damage and the fight never ends. That is a softlock,
# not a difficulty spike. Never "improve" this into an unconditional band write
# without the ammo_loadout save migration described in CLAUDE.md.
func _auto_ammo_for_module(mod_data: Dictionary, channel: String) -> String:
	var zone: int = int(mod_data.get("zone", 1))
	var band: String = ElementDB.get_ammo_band_for_zone(zone)
	# Walk down from the weapon's own band to T1, taking the best one in stock.
	var start: int = AMMO_DESCENT.find(band)
	if start < 0:
		start = AMMO_DESCENT.size() - 1
	# Pass 1: best band the player can actually FEED a weapon with. A stock of 1
	# is not a supply, it is a single shot — binding to it used to leave the gun
	# dry one tick later. AUTO_AMMO_MIN_STOCK is the sane floor.
	for i in range(start, AMMO_DESCENT.size()):
		var candidate: String = ElementDB.get_band_ammo_id(channel, AMMO_DESCENT[i])
		if candidate != "" and GameState.resources.get_element_amount(candidate) >= AUTO_AMMO_MIN_STOCK:
			return candidate
	# Pass 2: nothing meets the floor — take the best tier with ANY stock rather
	# than binding to a rung the player holds nothing of. The runtime fallback in
	# resolve_ammo_for_slot() catches the moment it runs out either way.
	for i in range(start, AMMO_DESCENT.size()):
		var candidate2: String = ElementDB.get_band_ammo_id(channel, AMMO_DESCENT[i])
		if candidate2 != "" and GameState.resources.get_element_amount(candidate2) > 0:
			return candidate2
	# Nothing in stock anywhere: fall back to the T1 rung, which is research-free,
	# craftable from Zone-0 materials and fully automated from tier 1 buildings.
	return ElementDB.get_band_ammo_id(channel, "T1")

# ─────────────────────────────────────────────────────────────────────────────
# v150b RUNTIME AMMO FALLBACK — the fix for the zero-damage stall.
#
# _auto_ammo_for_module only runs at EQUIP time, so whatever it picked stayed
# bound forever. The instant that stack hit zero the weapon was bound to an empty
# id, and combat_manager's `_warn_no_ammo(); return` means such a weapon deals
# ZERO damage — at every band zone Z4-Z10 the fight then never ends. An equip-time
# stock floor alone only makes that rarer; it cannot make it impossible, because
# any finite stack empties eventually.
#
# So the descent has to happen in the FIRING path: when the bound ammo is dry the
# weapon drops to the next rung down that still has stock, all the way to T1
# (research-free, Zone-0 craftable, automated from tier-1 buildings), and only a
# player holding literally nothing on that channel is reported genuinely dry.
#
# COST: the hot path is ONE dictionary read + ONE stock read. Only when the bound
# ammo is empty do we walk the 5-rung ladder, and that result is cached per
# preference id, re-validated by stock every shot and re-resolved at most once per
# AMMO_FALLBACK_REFRESH_MS (so newly crafted higher-tier rounds get picked back
# up). The inventory is never scanned.
#
# The player's ammo_loadout preference is NEVER rewritten — the substitution is a
# runtime read-through. Craft more of the preferred tier and the very next shot
# goes back to it on its own.
const AMMO_DESCENT := ["T4", "T3", "T2", "T1S", "T1"]
const AUTO_AMMO_MIN_STOCK := 30
const AMMO_FALLBACK_REFRESH_MS := 10000

var _ammo_fallback_cache: Dictionary = {}   # resolve key -> substituted ammo id
var _ammo_fallback_at: Dictionary = {}      # resolve key -> ticks_msec of resolve

## The ammo this weapon slot will ACTUALLY fire right now. Returns "" only when
## the player holds no compatible ammo at any tier (the genuinely-dry report).
func resolve_ammo_for_slot(slot_idx: int, weapon_type: String) -> String:
	var pref: String = String(ammo_loadout.get(slot_idx, ""))
	if pref != "" and not is_ammo_compatible(weapon_type, pref):
		pref = ""   # incompatible binding is treated as no binding, as before
	# HOT PATH: the bound ammo is in stock. Two lookups, no walk, no allocation.
	if pref != "" and GameState.resources.get_element_amount(pref) > 0:
		return pref
	var key: String = pref
	if key == "":
		key = "@" + weapon_type
	var cached: String = String(_ammo_fallback_cache.get(key, ""))
	if cached != "":
		var age: int = Time.get_ticks_msec() - int(_ammo_fallback_at.get(key, 0))
		if age < AMMO_FALLBACK_REFRESH_MS and GameState.resources.get_element_amount(cached) > 0:
			return cached
	var resolved: String = _descend_ammo(pref, weapon_type)
	_ammo_fallback_cache[key] = resolved
	_ammo_fallback_at[key] = Time.get_ticks_msec()
	return resolved

## Walk strictly DOWN the tier ladder from the preferred rung and take the first
## one the player holds. With no preference (empty/legacy binding) start at the
## top, so an unbound weapon fires the best ammo its owner has instead of nothing.
func _descend_ammo(pref: String, weapon_type: String) -> String:
	var channel: String = ""
	if pref != "":
		channel = ElementDB.get_ammo_channel(pref)
	if channel == "":
		# weapon_type and ammo channel share the same vocabulary for the three
		# ammo-fed types; "cryo" is self-charging and never reaches this path.
		if weapon_type == "kinetic" or weapon_type == "energy" or weapon_type == "explosive":
			channel = weapon_type
	if channel == "":
		return ""
	var start: int = 0
	if pref != "":
		var idx: int = AMMO_DESCENT.find(ElementDB.get_ammo_tier(pref))
		if idx >= 0:
			start = idx + 1   # strictly below the preference — it is already dry
	for i in range(start, AMMO_DESCENT.size()):
		var candidate: String = ElementDB.get_band_ammo_id(channel, AMMO_DESCENT[i])
		if candidate != "" and GameState.resources.get_element_amount(candidate) > 0:
			return candidate
	return ""   # genuinely dry on this channel at every tier

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

# v156: PASSTHROUGH. This used to inject the zone signature alloy at READ time,
# which meant the four call sites that read m_data["cost"] directly
# (info_card.gd:171 — live, it spawns on hover from research_detail_modal —
# atlas_page.gd:429, resources.gd:382 and get_sell_price) charged one thing and
# displayed another: modules["z5_armor"]["cost"] carried NO XenoforgedAlloy while
# the game billed 8, so the Atlas under-reported every Z2-Z10 weapon, armor and
# shield by its signature alloy and reported all nine alloys as having zero
# consumers. compose_module_costs() now bakes the charged cost into the authored
# dict, so every reader sees the same numbers and none of them needs the
# tier_gate_enabled flag (which stays exactly as it is — flipping it for
# pre-v114 saves would wall zones those players already cleared).
# Kept as a function because ~20 call sites use it and it is the honest name for
# "the cost you will actually be charged".
func get_effective_module_cost(m_data: Dictionary) -> Dictionary:
	return (m_data.get("cost", {}) as Dictionary).duplicate()

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

# v161: Spare-Part yield and repair cost were BOTH flat across zones, so the
# recycle loop read as broken past the early game:
#   crafted gear carries no "rarity" key -> every crafted module, Z1 Iron Plate
#   through the ~450k-credit Z10 Primordial Bulkhead, recycled for exactly 1 part;
#   and a Z1 Legendary paid the same 25 as a Z10 Legendary. Sell price already
#   scaled by zone (get_sell_price); parts never did.
# Both the faucet (demolish) and the sink (repair) now take the same tier weight,
# so the faucet:sink ratio inside a tier is UNCHANGED (a Legendary still costs ~10
# Legendary recycles to fully repair) while the numbers grow with the rest of the
# game — and, deliberately, scrapping a pile of low-tier junk no longer funds
# frontier repairs at parity. ~1.26^(zone-1), rounded to readable steps.
# The curve is deliberately SOFT (Z10 = x8, not the x20 a 1.45^ ramp gives).
# Inside a tier the exponent cancels — faucet and sink both carry it, so
# kills-to-fund-a-repair is identical at every base — the exponent only prices
# CROSS-tier conversion, i.e. what a hoard of old junk buys toward frontier
# maintenance. Measured at x20 that was 832 Z1 Legendaries per Z10 repair,
# which retires old gear as a resource entirely; x8 puts it at ~333, steep
# enough that farming current content is clearly better without making a
# stockpile worthless.
const RECYCLE_TIER_WEIGHT := {
	1: 1.0, 2: 1.3, 3: 1.6, 4: 2.0, 5: 2.5,
	6: 3.2, 7: 4.0, 8: 5.0, 9: 6.5, 10: 8.0,
}

func get_module_tier_weight(module_id: String) -> float:
	var m = modules.get(module_id, {})
	var z: int = int(m.get("zone", 0))
	# Custom drops carry their own zone; fall back to the base module's when a
	# roll didn't copy it (older saves).
	if z <= 0 and m.has("base_module"):
		z = int(modules.get(str(m["base_module"]), {}).get("zone", 0))
	if z <= 0:
		z = 1
	return float(RECYCLE_TIER_WEIGHT.get(clampi(z, 1, 10), 1.0))

func get_demolish_parts(module_id: String) -> int:
	var m = modules.get(module_id, {})
	var rarity = m.get("rarity", Rarity.COMMON)
	var base: int = RARITY_SPARE_PARTS.get(rarity, 1)
	return maxi(1, int(round(float(base) * get_module_tier_weight(module_id))))

# Spare-Part cost to restore a module to 100%. Shared by the equipped-slot and
# armory repair paths so both charge identically (UI used to compute this
# inline, which is how the armory path drifted out of existence entirely).
func get_repair_parts_cost(module_id: String) -> int:
	var m = modules.get(module_id, {})
	var cur_dur: int = int(m.get("durability", 100))
	if cur_dur >= 100:
		return 0
	var chunks: int = ceili((100 - cur_dur) / 10.0)
	var base: int = RARITY_SPARE_PARTS.get(get_module_rarity(module_id), 1)
	return maxi(1, int(round(float(base * chunks) * get_module_tier_weight(module_id))))

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
	var mid = loadout.get(slot_idx)
	if not mid:
		return false
	return repair_module_by_id(str(mid), cost_parts)

# v161: repair by module id, so ARMORY (stored) modules are repairable too. The
# hammer tool only ever reached equipped slots — designer_slot_widget owned the
# whole repair path — which left worn gear sitting in storage permanently broken
# and forced a pointless equip/unequip dance to service it.
func repair_module_by_id(module_id: String, cost_parts: int) -> bool:
	if module_id == "" or not module_id.begins_with("custom_"):
		return false
	if not modules.has(module_id):
		return false
	if GameState.resources.get_element_amount("SparePart") < cost_parts:
		return false

	GameState.resources.remove_element("SparePart", cost_parts)

	modules[module_id]["durability"] = 100
	if module_id in custom_modules:
		custom_modules[module_id]["durability"] = 100

	recalc_stats()
	inventory_updated.emit()
	return true
