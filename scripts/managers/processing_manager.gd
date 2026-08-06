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
		# v134h: Ag byproduct made DETERMINISTIC (was 0.4). Silver is a MANDATORY input to
		# the m029b Advanced Circuit mission (2 Ag x5 = 10 Ag) yet had NO other source — a
		# 40% RNG byproduct as the sole path to a required beat was too fragile. 1 Ag/smelt.
		# v141c: promoted from output_table to a STATED output. It was already a
		# guaranteed 1.0-chance roll, so nothing about the drop rate changes — but
		# output_table entries don't render on the recipe card, so the recipe read as
		# "3 Zinc Ore -> 2 Zinc" while silently also paying the Silver the m029b chain
		# depends on. A mandatory material must be visible on the card that makes it.
		"output": {"Zn": 2, "Ag": 1},
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
		"output": {"Ni": 2,"Co": 1},
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
	# v146 dedupe: "smelt_steel_oxygen" REMOVED. It was smelt_steel_basic scaled x2
	# (same Fe:C:O ratio, same 5.0s duration, same "smelting" research) with a +2 Mn
	# tax bolted on and a L40 gate — a strictly-parallel second Steel recipe, not a
	# tier step. Steel keeps two GENUINELY different supply paths: smelt_steel_basic
	# (raw ore chain) and reclaim_alloy (combat SalvagedAlloy). Mn is NOT orphaned —
	# craft_mg_ion_battery + shipyard still consume it.
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
		"input": {"Fe": 8,},
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
		# v135b: gate on Field Theory (its thematic tech, which its "unlocks": ["Ion
		# Field"] already advertised) instead of generic basic_electronics — revives
		# the formerly-dead field_theory node into a real gate.
		"research_req": "field_theory",
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
	# ═══════════════════════════════════════════════════════════════════════════
	# v150 AMMO BANDS — every ammo recipe is now the SAME SHAPE:
	#     [automatable bulk] + [channel payload] + [band catalyst x1]  ->  20 rounds
	# Band catalysts (see ElementDB.AMMO_BAND_MIN_ZONE for the full rationale):
	#     T1 none (tutorial rung stays free + fully automated)
	#     T2  RimeplateScrap  (Z4-only drop)
	#     T3  VoidCrystal     (earliest Z7)
	#     T4  PrimordialShard (earliest Z10)
	# ONE catalyst per 20 rounds is the invariant the ammo BUILDINGS mirror
	# (input = yield / 20). Do not raise it to 2 without redoing the Z4 supply
	# math: hull tier 4 = 3 weapon slots = 90 rounds/min = 4.5 crafts/min against
	# ~4.5 RimeplateScrap/kill x 2-7 kills/min. At 1 the catalyst is a KEY; at 2
	# it inverts against a bad spawn streak and becomes a grind tax.
	# ═══════════════════════════════════════════════════════════════════════════
	"craft_slug_t1": {
		"name": "Ferrite Rounds",
		"description": "Mass produce iron slugs.",
		# v150 MEASURED DEVIATION from the band spec. The spec asked for a 2nd
		# "channel payload" ingredient here ({Fe 2, C 1} / {Si 2, Cu 1}), but the
		# measured level chain forbids it: C comes from charcoal_burning (lvl 2,
		# and Wood gathers at lvl 4) and Cu from smelt_copper (lvl 5, Malachite
		# gathers at lvl 7). SlugT1 is lvl 1 and CellT1 is lvl 2 — the very first
		# ammo a player crafts. Adding those payloads would make the starter
		# kinetic/energy rounds UNCRAFTABLE on a fresh save, which is the exact
		# inverted-gate bug this pass exists to kill (see craft_missile_t2's old
		# lvl-25 recipe demanding a lvl-45 TargetingChip). T1 kinetic/energy stay
		# one bulk ingredient; symmetry is enforced from T2 up, where every
		# ingredient's own level_req is below its ammo recipe's.
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
		"description": "Heavy kinetic penetrators, seated in salvaged Cryofield rimeplate.",
		"input": {"Steel": 2, "W": 1, "RimeplateScrap": 1},
		"output": {"SlugT2": 20},
		"duration": 10.0,
		"level_req": 24, # v126: 32->24 — closes the W idle gap (Tungsten gathers at lvl 20; this is its first real sink)
		"xp": 40,
		"research_req": "processing_tungsten"
	},
	"craft_slug_t1s": {
		"name": "Steel Slugs",
		"description": "Heavy steel slugs, cast for weight rather than speed.",
		"input": {"Steel": 1},
		"output": {"SlugT1S": 20},
		"duration": 10.0,
		"level_req": 24,
		"xp": 20
	},
	"craft_cell_t2": {
		"name": "Plasma Cell",
		"description": "Bottle superheated gas in a rimeplate-lined containment shell.",
		# v150: level 34 -> 26. It was a 10-level outlier against its siblings
		# (slug 24 / missile 25), which is why energy players felt out of step
		# exactly at the Z4 band boundary.
		"input": {"Steel": 2, "Resin": 1, "RimeplateScrap": 1},
		"output": {"CellT2": 20},
		"duration": 10.0,
		"level_req": 26,
		"xp": 40, # Increased from 20
		# v135b: gate on Laser Optics (its thematic tech, already advertised by that
		# node's "unlocks": ["Plasma Cell (T2 Energy Ammo)"]). Was level-only (34) with
		# no research gate; laser_optics is cheap/early (300cr) so a lvl-34 player has
		# it — revives the formerly-dead node without moving Plasma Cell's real tier.
		"research_req": "laser_optics",
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
		# ── v142d ALLOY LADDER RULE (owner, 2026-07-25) ───────────────────────
		# Recipes must be CUMULATIVE: nothing gathered in an earlier zone gets left
		# behind there. Like Satisfactory still needing iron and copper at the end,
		# Z1 resources must feed mid-game and mid-game must feed late-game, so the
		# player keeps every extraction chain (and its infrastructure) alive.
		#
		# Each rung therefore has THREE parts:
		#   1. the PREVIOUS rung        -> depth (no reaching to the floor in bulk)
		#   2. an early automatable good -> cumulative; keeps Fe/Cu/Si/C/O relevant
		#                                   forever and is what infra parallelises
		#   3. the zone's OWN combat drop -> generous is fine
		#
		# THE COMBAT CONSTRAINT IS BACKWARD-LOOKING, NOT ABSOLUTE (owner refinement).
		# A zone-N gear/hull/research MAY demand plenty of zone N's OWN enemy drops —
		# the player is farming that zone right now, so it costs them nothing extra.
		# What must stay small is the reach BACK into EARLIER zones' combat drops,
		# because returning to Z2 to grind while you live in Z8 is serial and cannot
		# be automated. Automatable goods (gathered/processed) are unconstrained in
		# either direction — infrastructure parallelises them, and demanding them
		# forever is exactly how Fe/Cu/Si stay relevant.
		#
		# THE PREVIOUS-RUNG COEFFICIENT MUST BE 1, NEVER 2. Chaining each rung to the
		# last makes zone N transitively depend on Z1 for free (that is the whole
		# point), but the coefficient compounds down the chain. At x2 the combat cost
		# is c(n) = 2*c(n-1) + 1 = 2^(n-1) - 1: rung Z3 costs 3 combat drops, Z5 15,
		# Z8 127, and a single Z10 AeonAlloy 511 — times 5-8 alloys per module, about
		# 4,000 serial kills for one gun. At x1 the leak is LINEAR in the number of
		# rungs: with an own-zone coefficient of k the backward cost is
		# c(n) = k*(n-2) + 1, so the shipped k=3 gives 25 units of backward combat
		# drop at Z10, spread ~3 per prior zone. (An earlier version of this comment
		# claimed 9, which only holds if k=1 — do NOT size the remaining rungs
		# against that figure.) 25 spread over eight zones is the "modest amount"
		# the rule asks for; what matters is that it is linear, not geometric.
		# VOLUME SCALING IS NOT THIS RECIPE'S JOB — it belongs to the banded module
		# cost curve in shipyard_manager (compose_module_costs), which scales the
		# AUTOMATABLE side. Never buy late-game cost by nesting the chain more steeply.
		#
		# ── v156 RE-POINT: own-zone combat coefficient k 6 -> 2 on rungs Z3-Z10,
		# automatable carrier DOUBLED on the same rungs. Measured, the k=6 ladder
		# billed 40 units of BACKWARD combat loot per AeonAlloy, and 34,385 across a
		# tier-matched Z10 refit — hours of serial grinding in zones the player had
		# already left, which is the one thing the rule above forbids. The
		# previous-rung coefficient is UNTOUCHED at 1 (it is inviolable; see the
		# compounding note above) and no output quantity moved — the fix is
		# re-pointing volume from combat onto the automatable carrier, exactly as the
		# rule prescribes. c(n) = c(n-1) + 2 now: c(10) = 17, of which 15 backward.
		# The gate the k=6 term used to provide is not lost: it moved to the MODULE,
		# where compose_module_costs bills each zone's own signature drop on a hard
		# 1.26^(z-2) ramp. Own-zone drops cost the player nothing extra (they are
		# farming that zone right now) and they never propagate backward.
		#
		# Part 3 is capped low ON PURPOSE. Gathering and processing can be turned
		# into a parallel machine with infrastructure; COMBAT CANNOT — you fight one
		# enemy at a time. So a later zone must never demand bulk combat-only drops
		# from Z1/Z2/Z3. (A fleet system could parallelise combat later; deliberately
		# NOT built yet — improve what exists first.)
		#
		# Rung Z2. Was PirateSalvage 3 + Circuit 2 — 3 combat drops per alloy, and
		# the combat-only material was the BULK ingredient. Inverted: Circuit (the
		# automatable Cu/Si/Sn chain) carries the volume, salvage is the garnish.
		"input": {"Circuit": 3, "PirateSalvage": 1}, "output": {"ChondriteAlloy": 1},
		"duration": 12.0, "level_req": 15, "xp": 25, "research_req": "zone_2_access", "category": "alloys"
	},
	"refine_wreckforged_alloy": {
		"name": "Wreckforged Alloy",
		"description": "Reforge Martian war-debris into structural plate.",
		# v142d ALLOY LADDER, rung Z3 — see the three-part rule on refine_chondrite_alloy.
		#   depth: ChondriteAlloy 1 | cumulative: Steel 6 | own-zone combat: MartianRelics 3
		# Coefficient is 1, not 2 — see the compounding note on the Z2 rung. Steel
		# carries the automatable volume. MartianRelics is Z3's OWN drop so it is
		# free to be generous (3); the only thing held to 1 is the BACKWARD leak,
		# i.e. the single PirateSalvage that arrives through ChondriteAlloy.
		# Steel is deliberately RESTORED here. An earlier pass removed it to force
		# depth, but that was the wrong read: dropping the automatable early good
		# left MartianRelics 3 + ChondriteAlloy 2, which transitively cost NINE
		# combat drops per alloy — unautomatable serial grind. Reaching back to Fe
		# is not the problem; reaching back in BULK with no depth is. Steel keeps the
		# Fe/C/O chain and its buildings load-bearing all the way up.
		#   dirt/water -> Fe -> Steel ─┐
		#                 Cu/Si/Sn -> Circuit -> ChondriteAlloy ─┴-> WreckforgedAlloy
		"input": {"ChondriteAlloy": 1, "Steel": 12, "MartianRelics": 2}, "output": {"WreckforgedAlloy": 1},
		"duration": 13.0, "level_req": 25, "xp": 35, "research_req": "zone_3_access", "category": "alloys"
	},
	"refine_rime_alloy": {
		"name": "Rime Alloy",
		"description": "Quench frost-fused hull scrap in liquid nitrogen against a wreckforged core — the Glacier Belt's cold-rated stock.",
		# v142d ALLOY LADDER, rung Z4 — see the three-part rule on refine_chondrite_alloy.
		#   depth: WreckforgedAlloy 1 | automatable: N 10 | own-zone combat: RimeplateScrap 6
		# The old co-input was CryoEssence, which distill_cryo_essence makes from
		# PrimordialShard — a ZONE 10 material, at processing level 60, for a level-35
		# Zone-4 recipe. That was a backward-reach inversion so severe it ran the wrong
		# way down the ladder. N (nitrogen, from the gas line) is automatable and keeps
		# the H/O chain load-bearing; RimeplateScrap is Z4's OWN drop so 6 is fine.
		"input": {"WreckforgedAlloy": 1, "N": 20, "RimeplateScrap": 2}, "output": {"RimeAlloy": 1},
		"duration": 14.0, "level_req": 35, "xp": 50, "research_req": "zone_4_access", "category": "alloys"
	},
	"refine_xenoforged_alloy": {
		"name": "Xenoforged Alloy",
		"description": "Reverse-engineer xenon fragments into an exotic structural alloy.",
		# v142d ALLOY LADDER, rung Z5 — see the three-part rule on refine_chondrite_alloy.
		#   depth: RimeAlloy 1 | automatable: Superalloy 4 | own-zone combat: XenoFragment 6
		# Superalloy, not AdvCircuit, deliberately. Both are automatable, but
		# smelt_superalloy is level_req 18 against craft_adv_circuit's 40, and
		# AdvCircuit is already the band's bottleneck (it walled the bot at
		# zone_5_access). Superalloy also pulls a DIFFERENT raw chain into permanent
		# relevance — Fe/Al/Co/Ni/Cr/Ti — which is exactly what the cumulative rule
		# wants: more early resources staying alive, not the same one squeezed harder.
		"input": {"RimeAlloy": 1, "Superalloy": 8, "XenoFragment": 2}, "output": {"XenoforgedAlloy": 1},
		"duration": 15.0, "level_req": 45, "xp": 70, "research_req": "zone_5_access", "category": "alloys"
	},
	"refine_colony_alloy": {
		"name": "Colony-Forged Alloy",
		"description": "Recast colony reactor-salvage around a xenoforged core into heavy mining-grade plate.",
		# v142d ALLOY LADDER, rung Z6 — see the three-part rule on refine_chondrite_alloy.
		#   depth: XenoforgedAlloy 1 | automatable: StructuralComponent 5 | own-zone combat: ColonySalvage 6
		# Was ColonySalvage 3 + Superalloy 2: no depth (it did not touch the Z5 rung at
		# all, so the ladder simply RESTARTED at Z6) and it re-used Superalloy, the
		# carrier the Z5 rung already owns.
		# Coefficient on the previous rung is 1, NEVER 2 — at 2 the backward cost is
		# geometric, at 1 it stays linear. Transitive combat drops per alloy:
		#   c(6) = c(5) + 6 = 16 + 6 = 22, of which 16 are BACKWARD (Z2-Z5) and arrive
		#   through the single XenoforgedAlloy. Own-zone drops never count backward.
		# StructuralComponent (recipe level 35 + structural_press building) is the
		# carrier because it is a chain NO earlier rung uses: it is the only bulk
		# consumer of Li (Spodumene -> Lithium Extractor / Brine Well / Refinery) and
		# reloads Fe/Cu/Si/C alongside it. Per-zone carriers so far:
		#   Z2 Circuit | Z3 Steel | Z4 N | Z5 Superalloy | Z6 StructuralComponent
		"input": {"XenoforgedAlloy": 1, "StructuralComponent": 10, "ColonySalvage": 2}, "output": {"ColonyAlloy": 1},
		"duration": 15.0, "level_req": 55, "xp": 95, "research_req": "zone_6_access", "category": "alloys"
	},
	"refine_gamma_alloy": {
		"name": "Gamma Alloy",
		"description": "Stabilize charged exotic isotopes in a colony-forged matrix, tempering the lattice against hard radiation.",
		# v142d ALLOY LADDER, rung Z7 — see the three-part rule on refine_chondrite_alloy.
		#   depth: ColonyAlloy 1 | automatable: AdvCircuit 4 | own-zone combat: ExoticIsotope 6
		# Was ExoticIsotope 3 + VoidCrystal 2: no depth, and VoidCrystal is COMBAT-only
		# at this point in the ladder (void_crystallizer needs void_navigation, several
		# techs later), so the "automatable" slot was really a second combat tax.
		#   c(7) = c(6) + 6 = 28, of which 22 are BACKWARD (Z2-Z6) via the one ColonyAlloy.
		# AdvCircuit (recipe level 40 + adv_circuit_foundry building) is the carrier:
		# it wakes Germanite->Germanium, Au (Dirt/Water electrolysis) and Ag, none of
		# which any earlier rung touches. It is only viable HERE and not at Z5 — the
		# note on refine_xenoforged_alloy rejected AdvCircuit at level 45 because the
		# recipe gates at 40 and that band could not reach it; this rung gates at 65.
		#   Z2 Circuit | Z3 Steel | Z4 N | Z5 Superalloy | Z6 StructuralComponent | Z7 AdvCircuit
		"input": {"ColonyAlloy": 1, "AdvCircuit": 8, "ExoticIsotope": 2}, "output": {"GammaAlloy": 1},
		"duration": 16.0, "level_req": 65, "xp": 120, "research_req": "zone_7_access", "category": "alloys"
	},
	"refine_prismatic_alloy": {
		"name": "Prismatic Alloy",
		"description": "Suspend antimatter particles in a graphite lattice grown onto a gamma-tempered core, refracting the containment field into solid form.",
		# v142d ALLOY LADDER, rung Z8 — see the three-part rule on refine_chondrite_alloy.
		#   depth: GammaAlloy 1 | automatable: Graphite 20 | own-zone combat: AntimatterParticle 6
		# Was AntimatterParticle 3 + VoidCrystal 2 — the SAME shape as the Z7 rung
		# (signature raw x3 + VoidCrystal x2), so Z7 and Z8 were not a ladder at all,
		# just two parallel recipes reading from adjacent loot tables.
		#   c(8) = c(7) + 6 = 34, of which 28 are BACKWARD (Z2-Z7) via the one GammaAlloy.
		# Graphite (recipe level 25 + auto_press building) is the carrier. It is 5 C
		# each, so 20 Graphite is 100 Carbon per alloy — the first demand large enough
		# to keep the Wood -> smelt_carbon -> Carbon Generator / Industrial Kiln line
		# load-bearing into the endgame. Steel's C 2 never justified that chain on its
		# own. Crystalline carbon is also the honest read of "prismatic lattice".
		#   Z2 Circuit | Z3 Steel | Z4 N | Z5 Superalloy | Z6 StructuralComponent
		#   Z7 AdvCircuit | Z8 Graphite
		"input": {"GammaAlloy": 1, "Graphite": 40, "AntimatterParticle": 2}, "output": {"PrismaticAlloy": 1},
		"duration": 16.0, "level_req": 72, "xp": 150, "research_req": "zone_8_access", "category": "alloys"
	},
	"refine_bioforged_alloy": {
		"name": "Bioforged Alloy",
		"description": "Culture biohazard residue across a prismatic substrate inside a tungsten containment lattice, growing plate that knits its own fractures shut.",
		# v142d ALLOY LADDER, rung Z9 — see the three-part rule on refine_chondrite_alloy.
		#   depth: PrismaticAlloy 1 | automatable: W 25 | own-zone combat: BiohazardSample 6
		# Was BiohazardSample 3 + RegenPlating 1, and RegenPlating is itself
		# BiohazardSample 20 + IrPlate 3 + PathogenCore 1 for 2 — so the real bill was
		# ~13 BiohazardSample + 0.5 PathogenCore (a 5-10% RARE drop) per alloy, i.e.
		# both slots were Zone-9 combat and the rung had no depth and nothing
		# automatable. It was the worst offender of the five for the combat asymmetry.
		#   c(9) = c(8) + 6 = 40, of which 34 are BACKWARD (Z2-Z8) via the one PrismaticAlloy.
		# W (gathered from level 20 + heavy_tungsten_drill at 2.0/5s) is the carrier:
		# an EARLY, fully automatable good whose only sinks until now were ammo, so the
		# Tungsten Vein line stops being a dead-end the moment the player leaves it.
		#   Z2 Circuit | Z3 Steel | Z4 N | Z5 Superalloy | Z6 StructuralComponent
		#   Z7 AdvCircuit | Z8 Graphite | Z9 W
		"input": {"PrismaticAlloy": 1, "W": 50, "BiohazardSample": 2}, "output": {"BioforgedAlloy": 1},
		"duration": 17.0, "level_req": 80, "xp": 190, "research_req": "zone_9_access", "category": "alloys"
	},
	"refine_aeon_alloy": {
		"name": "Aeon Alloy",
		"description": "Seed aeon residuum into a bioforged matrix and seal it with iridium — the one metal old enough to hold the pour. Primordial-grade stock.",
		# v142d ALLOY LADDER, rung Z10 — see the three-part rule on refine_chondrite_alloy.
		#   depth: BioforgedAlloy 1 | automatable: Ir 10 | own-zone combat: AeonResiduum 6
		# Was AeonResiduum 3 + VoidEssence 2: no depth, and BOTH slots were Zone-10
		# materials, so the capstone alloy asked nothing of the nine zones beneath it —
		# the exact opposite of the cumulative rule.
		#   c(10) = c(9) + 6 = 46, of which 40 are BACKWARD (Z2-Z9) via the one
		#   BioforgedAlloy. LINEAR, not geometric: with the previous rung pinned at
		#   coefficient 1 the whole ladder is c(n) = c(n-1) + k(n), and k = 6 for
		#   Z6-Z10 gives c(n) = 6n - 14 from n=5 up. In the c(n) = k*(n-2)+1 form that
		#   is an effective uniform k of 5.625 at n=10 — compare coefficient 2, which
		#   would have made this alloy cost 2^9-1 = 511 backward drops.
		# Ir (gathered via mine_iridium + iridium_drill at 0.4/10s) is the carrier and
		# the last unclaimed extraction chain. It is not as early as W or C, but it is
		# long-established by this point — the zone_8 gate already bills Ir 80 — and
		# iridium is the honest "primordial" metal (the meteoric marker layer).
		#   Z2 Circuit | Z3 Steel | Z4 N | Z5 Superalloy | Z6 StructuralComponent
		#   Z7 AdvCircuit | Z8 Graphite | Z9 W | Z10 Ir
		"input": {"BioforgedAlloy": 1, "Ir": 20, "AeonResiduum": 2}, "output": {"AeonAlloy": 1},
		"duration": 18.0, "level_req": 88, "xp": 240, "research_req": "zone_10_access", "category": "alloys"
	},
	# v146 dedupe: "nitrogen_coolant" (Cryo-Shield Matrix) REMOVED. It was the
	# dominated raw-element NitroCoolant recipe — L32 + basic_engineering + 15s for
	# Circuit 5 / AlMgAlloy 10 / N 250 / Li 5, versus craft_cryo_coolant's L20,
	# research-free, 10s, He 15 / N 10 / Water 5. Same output, worse on every axis.
	# NitroCoolant keeps ONE raw path (craft_cryo_coolant, He is gatherable) plus the
	# salvage path (recharge_coolant_cell, Z4 CoolantCell drop). AlMgAlloy is NOT
	# orphaned — craft_missile_t3 still consumes it.

	# v146 dedupe: "refine_diamond_lens" REMOVED. Second Res3 producer, and the
	# strictly dominant one: 2 Res3 / 30s with NO research gate against
	# upgrade_exotic_artifact's 1 Res3 / 60s behind sector_alpha_decryption. Keeping
	# the artifact recipe instead of the lens is deliberate — upgrade_exotic_artifact
	# is the ONLY recipe sink for Res2 and one of only two for XenoFragment, so
	# cutting it would have stranded two heavily-dropped combat materials and left
	# sector_alpha_decryption without a payoff. Diamond is NOT orphaned —
	# crystallize_primordial_matrix, infrastructure and shipyard still consume it.
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
		"description": "Armor-shredding heavy rounds, machined around a Gamma-Sector void crystal.",
		# v150: the SlugT2 20 / CellT2 20 NESTING is gone. Nesting is correct for
		# the ALLOY ladder (chondrite -> wreckforged -> rime -> xenoforged is a
		# deliberate depth chain); it is wrong for ammo, where an ammo PLANT has
		# to mirror the recipe one-for-one and a nested tier made T3 kinetic/energy
		# cost 21 crafts while T3 explosive cost 1.
		"input": {"Superalloy": 2, "U": 1, "VoidCrystal": 1},
		"output": {"SlugT3": 20},
		"duration": 15.0,
		"level_req": 55, # Increased from 8
		"xp": 120, # Increased from 50
		"research_req": "ballistics_optimization"
	},
	"craft_slug_t4": {
		"name": "Hyper-Velocity Slug",
		"description": "Nano-lattice sabot for railguns, keyed to a primordial shard. Extreme kinetic impact.",
		# v150: out 50 -> 20. SlugT4 was the ONE ammo in the game that did not
		# output 20, which broke the 1-catalyst-per-20-rounds invariant every
		# ammo plant's input rate is derived from.
		"input": {"NanoSubstrate": 2, "IrWAlloy": 2, "PrimordialShard": 1},
		"output": {"SlugT4": 20},
		"duration": 20.0,
		"level_req": 65,
		"xp": 180,
		"research_req": "ballistics_optimization"
	},
	"craft_cell_t3": {
		"name": "Vaporizer Cell",
		"description": "Matter-disintegrating energy, lensed through a Gamma-Sector void crystal.",
		"input": {"Superalloy": 2, "AdvCircuit": 1, "VoidCrystal": 1},
		"output": {"CellT3": 20},
		"duration": 15.0,
		"level_req": 56, # v150: 58 -> 56, in line with slug 55 / missile 55
		"xp": 120, # Increased from 50
		"research_req": "energy_metrics"
	},
	"craft_cell_t4": {
		"name": "Heavy Plasma Cell",
		"description": "Unstable fusion plasma bottled by a primordial shard. Extreme damage.",
		"input": {"NanoSubstrate": 2, "SuperconductingMagnet": 2, "PrimordialShard": 1},
		"output": {"CellT4": 20},
		"duration": 20.0,
		"level_req": 65,
		"xp": 180,
		"research_req": "energy_metrics"
	},
	"craft_missile_t1": {
		"name": "HE Missile",
		"description": "Standard high-explosive ordnance.",
		# v150: {Fe 5, C 2} -> {Fe 1, C 1}. Explosive paid 7 raw units per 20
		# rounds where kinetic/energy paid 1 — the same "explosive players pay a
		# tax" asymmetry v144 fixed on the building side, still live on the
		# recipe side. C (charcoal_burning, lvl 2) is comfortably below this
		# recipe's lvl 5, so the channel payload is legal here even though it is
		# not at lvl 1. Spec asked for Resin; measured craft_polymer is lvl 10,
		# ABOVE this recipe — that would be an inverted gate, so C it is.
		"input": {"Fe": 1, "C": 1},
		"output": {"MissileT1": 20},
		"duration": 5.0,
		"level_req": 5,
		"xp": 20,
		# v129: research gate removed — T1 ammo is part of the starter combat kit
		# (the damage-triangle tutorial needs missiles pre-research). combustion
		# still gates Fiber/Germanium/Mg + the kiln buildings.
	},
	# v141c: ReactiveCore had NO source anywhere in the game (item-economy audit),
	# which made z6_battery — cost {credits 75000, ReactiveCore 2, AdvCircuit 20} —
	# permanently uncraftable. Under battery-only energy (v110) that is not cosmetic:
	# BATTERY_CAP_BY_TIER jumps 180 (t5) -> 350 (t6), so a Sector Beta player was
	# stuck on half the designed grid until Z7. Sourced the same way z5_battery's
	# QuantumCore is (recipe + a zone rare_loot drop), using Sector Beta's own
	# signature materials so it reads as native Z6 tech.
	"craft_reactive_core": {
		"name": "Reactive Core Assembly",
		"description": "Layer colony salvage plating over a superalloy shell until the lattice answers back. Sector Beta's power core.",
		"input": {"ColonySalvage": 6, "Superalloy": 4, "AdvCircuit": 3},
		"output": {"ReactiveCore": 2},
		"duration": 45.0,
		"level_req": 55,
		"xp": 300,
		"research_req": "zone_6_access",
		"category": "components"
	},
	# v141c: craft_turret_core REMOVED. TurretCore was a true dead end — the recipe
	# cost 1281 raw units (~8 gather-min + 23 craft-min per unit) and NOTHING in the
	# game consumed it: no tech cost_items, no module, no building, no mission. It
	# was registered in research_manager.NON_SCALING_ITEMS as though it were a
	# research token, but no tech ever listed it. (History: v80.4 fixed it as a
	# DEADLOCK by giving it a source; the consumer was never wired, which turned it
	# into the mirror-image bug.) Cut rather than invented a sink — a 25s recipe
	# feeding a phantom is worse than no recipe. The element entry, icon and colour
	# stay in element_db/elements.json so existing saves holding stacks still render.
	"craft_missile_t2": {
		"name": "Seeker Missile",
		"description": "Guided missile with logic circuits, wrapped in salvaged Cryofield rimeplate.",
		# v150: SIX ingredients (19 raw units) -> three. The worst offender in the
		# game: this recipe was level_req 25 but demanded TargetingChip, whose own
		# recipe (craft_turret_targeting) is level_req 45 — a T2 missile needed a
		# lvl-45 component. Kinetic paid 2 units for the same rung.
		"input": {"Steel": 2, "Circuit": 1, "RimeplateScrap": 1},
		"output": {"MissileT2": 20},
		"duration": 10.0,
		"level_req": 25,
		"xp": 50,
		"research_req": "advanced_rocketry"
	},
	"craft_missile_t3": {
		"name": "Heavy Missile",
		"description": "High-yield thermobaric ordnance around a Gamma-Sector void crystal.",
		# v150: SIX ingredients (39 raw units) -> three, same shape as its siblings.
		"input": {"Superalloy": 2, "StructuralComponent": 1, "VoidCrystal": 1},
		"output": {"MissileT3": 20},
		"duration": 15.0,
		"level_req": 55, # v150: 48 -> 55, in line with slug 55 / cell 56
		"xp": 100,
		"research_req": "advanced_rocketry"
	},
	"craft_missile_t4": {
		"name": "Photon Torpedo",
		"description": "Primordial-shard capital buster.",
		# v150: ExoticMatter removed. It is the prestige currency's twin identity
		# and its earliest_zone is 7 — using it at T4 collapsed T3/T4 onto the
		# same band material.
		"input": {"NanoSubstrate": 2, "OsCore": 2, "PrimordialShard": 1},
		"output": {"MissileT4": 20},
		"duration": 20.0,
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
		# v136 fix: was L30, but its consumers craft_mg_ion_battery (L14) and
		# craft_ion_field (L18) were then silently un-craftable until L30. Lowered
		# to L12 (below all AlWire consumers; Al + Resin are available by then).
		"level_req": 12,
		"xp": 35,
		"research_req": "basic_electronics"
	},
	# v146 dedupe: "assemble_circuit_standard" REMOVED. Same Cu/Si/Sn stream as
	# craft_circuit with 1 Resin added, same 6.0s duration, strictly better yield —
	# a fossil of the v18.0 "industrial path (no combat required)" split, which the
	# v80.3 DroneCore fix already resolved by making craft_circuit itself
	# combat-free. Circuit keeps craft_circuit (raw, L6, research-free — the
	# tutorial points at it from main.gd) and reclaim_circuitry (combat
	# DamagedCircuitry). Resin is NOT orphaned — craft_aluminum_wire, craft_cell_t2,
	# craft_hydraulics, craft_sealant and infrastructure still consume it.
	# NOTE: research node basic_electronics listed this recipe as its ONLY payload;
	# it is repointed to a craft_circuit speed bonus in research_manager.gd so it
	# does not become a dead node.

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
	# v146 dedupe: "extract_germanium" REMOVED. It only ever existed as the v80.4
	# workaround for "Germanit has no source" — that premise is dead: gathering
	# action mine_germanit (Mining L35, research-free) sources the ore now, so the
	# Si+Cu synthetic path is a redundant second Germanium recipe. No gate
	# regression: refine_germanite is L35 + adv_materials and Germanium's only
	# consumer (craft_semiconductor) is L38 + adv_materials, so the surviving path
	# unlocks strictly earlier than the demand for it. Removing refine_germanite
	# instead was not an option — it is the only recipe consumer of Germanit ore.
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
	# v146 dedupe: "gold_leaching" REMOVED. Same Dirt+Water launder as refine_gold
	# with H added, and strictly dominant (2.5 Au/craft vs 2, on half the Dirt and
	# a third of the Water per unit) — exactly the "dominated converter" pair
	# docs/SANITY_CHECKLIST.md flagged. Au keeps refine_gold (L20) plus combat drops.
	# The industrial_electrolysis research node does NOT go dead: its stated payload
	# is the Industrial Electrolysis Plant building, not this recipe.
	"craft_adv_circuit": {
		"name": "Advanced Circuitry",
		"description": "High-performance integrated circuit. Silver traces and tin solder for low-loss interconnects.",
		# v139c band surgery: StructuralComponent 2->1, Ag 2->1 — same five input
		# streams (the electronics-chain teach), ~40% lighter raw-gather load per
		# unit. The m029b/m030 band is ACTIVE-time bound at 1h/day (see
		# docs/design/ZONE_PACING_CURVE.md).
		"input": {"Semiconductor": 1, "Au": 1, "StructuralComponent": 1, "Ag": 1, "Sn": 1},
		"output": {"AdvCircuit": 1},
		"duration": 15.0,
		# v135: 45 -> 40. The player-bot matrix showed EVERY archetype parked on
		# m029b (5x AdvCircuit) for its p50 ~40h / p90 ~166h — the whole
		# mid-funnel's single bottleneck was this level gate, not materials.
		# 40 aligns with Chip's gate (one "electronics band"); the research gate
		# (automation) still applies.
		"level_req": 40,
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
	# v146 dedupe: "electrolysis_nickel_catalyst" REMOVED. Second Water -> H+O recipe,
	# and doubly redundant: its parent research catalytic_electrodes ALREADY pays out
	# as a +25% action_speed buff on `electrolysis` itself (see upgrades_db below), so
	# the node kept a payload without the duplicate recipe. H and O keep electrolysis
	# (L2) as the single split, plus the infrastructure hydro plant.
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
		"description": "Crystallize void essence around an advanced-circuit scaffold into a load-bearing lattice.",
		"input": {"VoidEssence": 8, "VoidCrystal": 6, "AdvCircuit": 24},
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
		"description": "Bind a primordial shard into a neutronium-cased void lattice to form a stable matrix.",
		"input": {"PrimordialShard": 5, "Neutronium": 12, "VoidLattice": 2},
		"output": {"PrimordialMatrix": 1},
		"duration": 90.0,
		"level_req": 95,
		"xp": 6000,
		"research_req": "primordial_engineering",
		"category": "endgame"
	},
	# ========== v160: CAPITAL FABRICATION CHAIN — escape hatches ==========
	# ENDGAME_FACTORY_TIER.md Section I DEFECT-1 fix: the module cost curve's
	# serial fallback (_cost_serial_rate) is built ONLY from these recipes and
	# gather actions, so a chain material WITHOUT a recipe is priced as
	# unreachable-serial and hard-walls a player who cannot afford the plant.
	# Every rung therefore keeps a slow, expensive hand path. Rates are set far
	# under the plant (SinteredCarbide 0.8/min vs 9.6 neutral from one press;
	# DreadnoughtFrame 0.1/min vs 0.6 from one yard) so the factory is always
	# clearly better — acceleration, never access. Inputs are >= the plant's
	# per-unit ratios for the same reason. level_req sits under
	# COST_ZONE_PROC_LEVEL of the first zone that anchors the material
	# (SC Z7/65, PL Z8/75, FB Z9/85, CS+DF Z10/95), so nothing is unbuildable
	# when its zone unlocks.
	# v163 CARBON LATTICE LINE. Diamond had NO production path at all — it dropped
	# from z8_boss_warden and nowhere else, which also made z9_battery's "Diamond 2"
	# a backward-combat-debt line (a Z9 module demanding a Z8 boss drop). Pressing
	# carbon into diamond fixes both: Diamond gains a parallel source, and the
	# Wood -> C economy is pulled back under endgame load TRANSITIVELY, so no late
	# recipe ever names Wood directly.
	"craft_synthetic_diamond": {
		"name": "Synthetic Diamond",
		"description": "Crush carbon under press-forge pressure until the lattice locks. The Diamond Press runs this without you.",
		"input": {"C": 216, "Graphite": 8},
		"output": {"Diamond": 1},
		"duration": 45.0,
		"level_req": 58,
		"xp": 520,
		"research_req": "molecular_compression",
		"category": "endgame"
	},
	"craft_diamond_wafer": {
		"name": "Diamond Wafer",
		"description": "Slice and lap a synthetic stone into a substrate. The Wafer Lapping Line runs this without you.",
		"input": {"Diamond": 4, "SinteredCarbide": 2},
		"output": {"DiamondWafer": 1},
		"duration": 90.0,
		"level_req": 68,
		"xp": 900,
		"research_req": "refractory_metallurgy",
		"category": "endgame"
	},
	"craft_superior_circuit": {
		"name": "Superior Circuit",
		"description": "Print logic onto a diamond substrate. The Diamond Lithography Hall runs this without you.",
		"input": {"DiamondWafer": 6, "AdvCircuit": 12, "PrecisionLattice": 2, "Au": 6},
		"output": {"SuperiorCircuit": 1},
		"duration": 180.0,
		"level_req": 78,
		"xp": 2200,
		"research_req": "precision_fabrication",
		"category": "endgame"
	},
	"craft_sintered_carbide": {
		"name": "Sintered Carbide",
		"description": "Hot-press graphite and tungsten around a cobalt binder. The Carbide Sintering Press runs this without you.",
		"input": {"Graphite": 18, "W": 12, "Co": 6},
		"output": {"SinteredCarbide": 1},
		"duration": 75.0,
		"level_req": 62,
		"xp": 800,
		"research_req": "refractory_metallurgy",
		"category": "endgame"
	},
	"craft_precision_lattice": {
		"name": "Precision Lattice",
		"description": "Machine sintered carbide and stainless steel into a micron-tolerance truss. The Precision Lattice Mill runs this without you.",
		"input": {"SinteredCarbide": 18, "StainlessSteel": 18, "Mg": 6},
		"output": {"PrecisionLattice": 1},
		"duration": 120.0,
		"level_req": 72,
		"xp": 1600,
		"research_req": "precision_fabrication",
		"category": "endgame"
	},
	"craft_fabrication_bus": {
		"name": "Fabrication Bus",
		"description": "Assemble a self-routing power-and-tooling spine on a precision lattice. The Bus Assembly Hall runs this without you.",
		"input": {"PrecisionLattice": 18, "AdvCircuit": 12, "Chip": 12, "DiamondWafer": 14},
		"output": {"FabricationBus": 1},
		"duration": 240.0,
		"level_req": 80,
		"xp": 2600,
		"research_req": "precision_fabrication",
		"category": "endgame"
	},
	"craft_capital_spar": {
		"name": "Capital Spar",
		"description": "Lace a fabrication bus through galvanized keel plate and composite weave. The Capital Spar Works runs this without you.",
		"input": {"FabricationBus": 6, "GalvanizedSteel": 54, "CompositeWeave": 12},
		"output": {"CapitalSpar": 1},
		"duration": 300.0,
		"level_req": 88,
		"xp": 4200,
		"research_req": "dreadnought_yards",
		"category": "endgame"
	},
	"craft_dreadnought_frame": {
		"name": "Dreadnought Frame",
		"description": "Join spars, neutronium plate and precision lattice into one hull skeleton section. The Dreadnought Frame Yard runs this without you.",
		"input": {"CapitalSpar": 18, "NeutroniumPlate": 12, "PrecisionLattice": 42},
		"output": {"DreadnoughtFrame": 1},
		"duration": 600.0,
		"level_req": 92,
		"xp": 8000,
		"research_req": "dreadnought_yards",
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
	# shortcut to the Cryo-Shield Matrix.
	# v146 dedupe: the "full N-250 industrial recipe" this used to be compared
	# against (nitrogen_coolant) is gone; the raw-element counterpart is now
	# craft_cryo_coolant. This stays — CoolantCell is combat-drop supply, a
	# genuinely different input source, not a second way to spend the same inputs.
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
		"input": {"VoidArtifact": 2, "VoidCrystal": 6, "AdvCircuit": 12, "Superalloy": 15},
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
		# v146 dedupe: sole raw-element NitroCoolant path now that nitrogen_coolant
		# is gone, so the card carries the shield-restore line it used to own.
		# No percentage quoted on purpose — element_db heal_pct is 0.25 while the
		# legacy recipe cards still say "35%" (stale since the v106 recalibration).
		"description": "Compress helium and nitrogen into supercooled fluid. Restores Shield integrity.",
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
		"input": {"Circuit": 1},
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

func gain_mastery_xp(recipe_id: String, amount: float = MASTERY_XP_PER_COMPLETION + int(get_level()/10)) -> void:
	if recipe_id == "" or amount <= 0.0:
		return
	# v107: First-encounter intro — see gathering_manager.gain_mastery_xp for
	# rationale. Shared flag so it only fires once across both managers.
	if not GameState.game_settings.get("mastery_intro_seen", false):
		GameState.game_settings["mastery_intro_seen"] = true
		UITheme.show_notification(
			tr("MASTERY UNLOCKED — Keep using actions for permanent speed bonuses. Hover the mastery bar for the milestone schedule."),
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
			var msg: String = tr("%s — Mastery %d · −%d%% Duration") % [recipe_name, m, pct]
			UITheme.show_notification(msg, Color(1.0, 0.84, 0.45))

# v141c: ENGINEERING SKILL LEVEL PAYS A FLAT +1 PER 10 LEVELS on a recipe's
# PRIMARY output — the mirror of gathering_manager.get_skill_yield_flat (owner
# call). Before this, Engineering levels paid nothing at all except recipe
# unlocks and a 5%-double at milestone 50.
#
# Applies to EVERY fixed output, not just the headline one (owner call): a recipe
# like Mineral Washing produces Iron AND Silicon in one cycle, and rewarding only
# the first key made the second product visibly inert as the skill climbed.
# Chance-rolled byproducts (output_table) still get nothing — those are lottery
# rolls with min/max ranges, not the recipe's stated product.
#
# KNOWN TRADE-OFF, accepted deliberately: processing is a CONVERTER, not a
# source, so a flat moves the input:output ratio rather than just inflating a
# faucet. It lands hardest on singleton recipes — Copper Smelting (2 Malachite +
# 1 C -> 1 Cu) becomes 2 Malachite -> 11 Cu at Lv100, and Res3 likewise. If that
# ratio inversion ever bites, the lever is YIELD_FLAT_PER_LEVELS or per-recipe
# opt-out, not the raw drop tables. scripts/sim/item_economy_audit.gd measures it.
const YIELD_FLAT_PER_LEVELS := 10

# Skill milestone 50: chance for a cycle to yield double. Online rolls it per
# craft; offline applies it as an expected value over the window (see
# calculate_offline). One constant so the two paths can never disagree again.
const MILESTONE_50_DOUBLE_CHANCE := 0.05


func get_skill_yield_flat() -> int:
	return int(get_level() / YIELD_FLAT_PER_LEVELS)


# The bonus units a cycle of `base_qty` actually receives. Scaled to the output's
# own size and capped at +100%, so levelling roughly DOUBLES a recipe over the
# full climb instead of compounding away the tier structure.
#
# For a standard 10-unit output this is exactly "+1 per 10 levels" — the design
# intent — and it stays proportional for bulk (20-unit) and singleton (1-unit)
# recipes rather than dwarfing the small ones.
func get_skill_yield_bonus(base_qty: float) -> int:
	if base_qty <= 0.0:
		return 0
	# FLAT +1 per 10 levels, UNCAPPED (owner call). At Engineering 100 every recipe
	# reads "+10" — including the 1-unit ones. The promise the skill makes has to be
	# visible on the number, or the last 50 levels read as wasted time.
	#
	# Known cost, accepted deliberately: the bonus applies per CYCLE, so it
	# multiplies at every tier of a crafting tree. Measured L1->L100 with no cap
	# (item_economy_audit section 7): AdvCircuit 89x cheaper, AICore 472x,
	# AIProcessor 2066x. The counterweight is depth-scaled INPUT requirements, not
	# a cap on the reward — see docs/HANDOFF.md. Do not re-add a cap here without
	# re-reading that measurement first.
	return get_skill_yield_flat()


func get_primary_output(recipe: Dictionary) -> String:
	for k in recipe.get("output", {}):
		return String(k)
	return ""


# SINGLE SOURCE OF TRUTH for "what one craft cycle awards for `item`". The card,
# the online award, the offline award and the per-minute rate all call this, so
# they cannot drift (the v140 gathering lesson: three surfaces recomputing the
# same number independently is how a bonus goes live but invisible).
# Returns float — the research efficiency multiplier has always produced
# fractional awards here and truncating now would silently change payouts.
func get_display_output(recipe_id: String, item: String) -> float:
	var recipe: Dictionary = recipes.get(recipe_id, {})
	if recipe.is_empty():
		return 0.0
	var qty := float((recipe.get("output", {}) as Dictionary).get(item, 0))
	# Steel Scalability (Oxygen-Blast Furnace)
	if item == "Steel" and GameState.research_manager and GameState.research_manager.is_tech_unlocked("oxygen_blast_furnace"):
		qty *= 5.0
	if GameState.research_manager:
		qty *= GameState.research_manager.get_efficiency_multiplier()
	# v141c skill bonus — after the multipliers, on every fixed output, scaled to
	# the output's own size and capped at +100% (see get_skill_yield_bonus).
	#
	# Why not a raw flat: it is applied per CYCLE, so it compounds multiplicatively
	# down a crafting tree. Uncapped, a 1-output recipe became 11 at Lv100 = 11x
	# fewer cycles, and three stacked tiers (AdvCircuit -> AICore -> AIProcessor)
	# measured 2065x cheaper end-to-end (item_economy_audit section 7) — the deeper
	# the item, the cheaper it got, inverting the tier structure. Bounded at +100%
	# the worst case is 2^depth, and the reward still grows every 10 levels instead
	# of maxing out at Lv10 the way a hard min(flat, base) cap did.
	qty += float(get_skill_yield_bonus(qty))
	return qty


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
		# v146 dedupe: smelt_steel_oxygen entry dropped with the recipe.
		# v146 dedupe: basic_electronics repointed off the deleted
		# assemble_circuit_standard onto craft_circuit so the node keeps a payload.
		"craft_circuit": [ {"id": "basic_electronics", "bonus": 0.25}],
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
	
	# v161: Refinery Link (v74.0) REMOVED — added affix_bonuses["refinery_link"] to
	# recipe speed, but no AFFIX_DB entry granted that key, so it added a permanent
	# 0.0. Verified by roll proof in affix_gem_sanity.tscn.
	
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
			# v141c: Steel scalar + research efficiency + the skill flat all live in
			# get_display_output, so the recipe card renders the identical number.
			var qty = get_display_output(current_recipe_id, item)

			# Audit v12.0: Milestone Level 50 (5% chance for double output)
			# v141c: mirrored offline as an EXPECTED VALUE — see calculate_offline.
			if is_milestone_unlocked(50) and randf() < MILESTONE_50_DOUBLE_CHANCE:
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
	gain_mastery_xp(current_recipe_id,  MASTERY_XP_PER_COMPLETION + int(get_level()/10))

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
			# v141c: same single source as online (v112 fixed a 5x-vs-2x Steel
			# mismatch here by hand; routing both through get_display_output means
			# that class of online/offline drift can't recur).
			var qty = get_display_output(current_recipe_id, item)

			# v141c: the milestone-50 double-output roll was ONLINE ONLY — an
			# offline window silently paid ~5% less than the same time played
			# (bonus_audit caught it: online 33.0 vs offline 30.0 at Lv100).
			# Closed-form offline can't roll per craft, so apply the expected
			# value, the same way chance-based drops are handled here.
			if is_milestone_unlocked(50):
				qty *= (1.0 + MILESTONE_50_DOUBLE_CHANCE)

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
			# v141c: project the number actually awarded. This used to re-derive the
			# per-cycle qty from the raw dict and patch multipliers in by hand (v112
			# added the missing Steel x5 that way); it would have missed the skill
			# flat identically. Same fix as gathering_manager.get_current_rate.
			rates[item] = get_display_output(current_recipe_id, item) * actions_per_min
			
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
