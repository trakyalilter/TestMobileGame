# The Capital Fabrication Chain — endgame factory tier (spec, 2026-07-27)

**Player fantasy:** by Zone 10 your dreadnought is not *built*, it is *manufactured* — a
sprawling orbital complex of thirty-odd specialist plants feeding each other in sequence,
and every one of them still bottoms out in the same dirt excavators and water pumps you
bought in your first hour.

**Loop:** CORE (skilling) primarily — infrastructure is the parallel layer that makes the
single active slot a *choice* rather than a bottleneck. Secondary META (the module cost
curve is what demands the tier). **Subsystem:** `infrastructure_manager` (building_db,
research gates), `research_manager` (5 new techs), `shipyard_manager`
(`COST_ZONE_ANCHOR`, `COST_MIN_DIRECT_DEPTH`), `element_db` (5 new materials).

**Owner brief, verbatim:** *"we start the game small ship and small ship have small weapons
shields etc but at the later of the game ships become enormous intergalactic ships so these
will require toooo many factories to work to sustain them"* — and *"im not only talking
about Fe production i gave it as example."* The target is BREADTH of factory types, not one
deeper iron line.

---

## A. THE GAP, MEASURED

All figures below were re-measured on HEAD `800a82f` with a throwaway probe
(`scripts/sim/eft_verify.gd` + `scenes/eft_verify.tscn`, **deleted after the run**). Where
the probe agrees with the prior audit I say so; where it disagrees I say which walk produced
which number and why.

### A1. Class census of `building_db` — 80 entries

Classification: **DRILL** = yields, `input` absent/empty. **FACTORY** = input-bearing, every
input has a non-combat source. **COMBAT-FED** = input-bearing, at least one input comes only
from enemy loot. **POWER** = `energy_gen` only. **OTHER** = no yield, no generation.

```
DRILL       28
FACTORY     31
COMBAT-FED   6   bioreactor_vat, omega_foundry, primordial_extractor,
                 advanced_ballistics_plant, high_energy_cell_plant, guided_munitions_plant
POWER       11
OTHER        4
```

Reproduced exactly by the independent probe. Two further facts confirmed at runtime, both of
which contradict the standing notes and change the spec:

- **`infrastructure_manager.has_method("_apply_upkeep") == false`.** `_apply_upkeep` and
  `_upkeep_efficiency_for` were removed in v120 (`infrastructure_manager.gd:1119`). **There
  is no Water/Dirt upkeep sink in the shipped build.** CLAUDE.md and the original task brief
  both describe it as live. Section F designs against the code that exists.
- **Zero buildings yield `credits`.** Infrastructure produces no Lira income at all today.

### A2. Per-zone tier-matched refit — buildings the production chain touches

Corrected walk (the `matter_deconstructor` route excluded by a 500:1 input/output ratio
filter; see A5).

| zone | total | FACTORY | DRILL | new factories | new drills |
|---|---|---|---|---|---|
| Z2 | 13 | 7 | 6 | 7 (the whole starter set) | 6 |
| Z3 | 19 | 10 | 9 | 3 | 3 |
| Z4 | 25 | 15 | 10 | 6 | 3 |
| Z5 | 31 | 19 | 12 | 5 | 1 |
| Z6 | 31 | 18 | 13 | **0** | 1 |
| Z7 | 32 | 19 | 13 | **1** (`composite_loom`) | 0 |
| Z8 | 31 | 18 | 13 | **0** | 1 |
| Z9 | 33 | 18 | 15 | **0** | 2 |
| Z10 | 37 | 19 | 18 | **1** (`void_crystallizer`) | 2 |

**The headline: factory count is FLAT from Z5 to Z10 — 19, 18, 19, 18, 18, 19.** Drill count
grows 12 to 18. Across the whole endgame the tree introduces **two** new factories and
**six** new drills. The complex stops growing in TYPE at Zone 5 and only grows in COPIES
after that. That is the exact opposite of the fantasy.

Zero COMBAT-FED buildings appear on any zone's chosen chain, because `OmegaComposite`,
`PrimordialMatrix` and `BioReactorCore` are all cheaper via their serial craft recipes than
via the building. **The three deepest "endgame" buildings are dominated by their own
recipes.**

### A3. Depth census

Depth is over the infrastructure forest: a combat material or a producer with no `input` is
depth 0, otherwise `1 + max(depth of inputs)`, minimised over producers.

```
d0  36   DRILL 28, OTHER 4, POWER 4
d1  15   FACTORY 8, POWER 6, COMBAT-FED 1
d2  13   FACTORY 12, POWER 1
d3   9   FACTORY 6, COMBAT-FED 3
d4   4   FACTORY 4
d5   2   FACTORY 1, COMBAT-FED 1
d6   1   COMBAT-FED 1
```

(Probe note: an infra-only walk that treats non-building materials as depth 0 gives
`d0 36 / d1 18 / d2 14 / d3 7 / d4 3 / d5 2`. The table above counts processing recipes as
producers too — the same convention `COST_MIN_DIRECT_DEPTH` uses, so it is the one the cost
curve reads. Both walks agree on the structural claim below.)

Every producing building at d>=3, and the reason the tier is missing:

| d | class | id | out | in |
|---|---|---|---|---|
| 3 | FACTORY | `chromium_forge` | Cr 1.3 | Al 0.6, Chromite 1.9 |
| 3 | FACTORY | `composite_loom` | CompositeWeave 0.6 | Fiber 6.3, Resin 1.3 |
| 3 | FACTORY | `electronics_assembler` | Circuit 1.3 | Cu 2.5, Resin 1.3, Si 2.5 |
| 3 | FACTORY | `matter_deconstructor` | Circuit 0.5, Superalloy 0.1 | Cu 2500 (degenerate) |
| 3 | FACTORY | `structural_press` | StructuralComponent 1.0 | C 3, Cu 5, Fe 10, Li 2, Si 5 |
| 3 | FACTORY | `chip_fab` | Chip 0.8 | Au 0.8, N 4, Semiconductor 1.6 |
| 3 | COMBAT-FED | 3 x T2 ammo plant | SlugT2 / CellT2 / MissileT2 | ... + RimeplateScrap |
| 4 | FACTORY | `adv_circuit_foundry` | AdvCircuit 1.2 | Au 1.2, Semiconductor 2.4, StructuralComponent 2.4 |
| 4 | FACTORY | `superalloy_forge` | Superalloy 1.0 | Cr 1, Ni 2, Steel 4, Ti 1 |
| 4 | FACTORY | `heavy_ordnance_works` | SlugT3 0.8 | Superalloy 2.1, U 0.8, VoidCrystal 0.04 |
| 4 | FACTORY | `thermobaric_warhead_works` | MissileT3 0.8 | StructuralComponent 0.8, Superalloy 2.1, VoidCrystal 0.04 |
| 5 | FACTORY | `zero_point_cell_synthesizer` | CellT3 0.8 | AdvCircuit 0.8, Superalloy 2.1, VoidCrystal 0.04 |
| 5 | COMBAT-FED | `omega_foundry` | OmegaComposite 0.15 | AdvCircuit 15, NeutroniumPlate 1, OmegaPlating 3 |
| 6 | COMBAT-FED | `primordial_extractor` | PrimordialMatrix 0.1 | Neutronium 6, PrimordialShard 2.5, VoidLattice 1 |

**Root cause, sharper than "the deep ones are combat-fed":** of the six non-combat-fed
buildings at d>=4, **three are ammo plants**. Ammo has zero downstream recipe, module or
building sinks by design — combat consumes it — so it can never be a cost-curve target.
Strip ammo and combat-fed and the entire parallelisable production forest tops out at
**two** buildings: `adv_circuit_foundry` (AdvCircuit) and `superalloy_forge` (Superalloy).

That is why `COST_ZONE_ANCHOR` names AdvCircuit at **Z6, Z7, Z8, Z9 and Z10** and why
`COST_MIN_DIRECT_DEPTH` is capped at 3 with the comment *"there is no parallelisable d5 at
all"*. The five-zone AdvCircuit monoculture is a symptom, not a choice.

### A4. What is serial that should not be

151 of 212 solved materials (71%) have **no** infrastructure producer. Ranked by peak units
demanded across the Z2-Z10 refits, and the resulting foreground minutes locked in the single
active slot per full tier-matched refit:

| zone | serial minutes | biggest lines |
|---|---|---|
| Z5 | 192 (3.2 h) | |
| Z6 | 281 (4.7 h) | |
| Z7 | **1,214 (20.2 h)** | Fiber 9,786 u = 816 min |
| Z8 | 874 (14.6 h) | Al 9,159 u = 229 min; QuantumCore 167; Resin 125 |
| Z9 | 1,181 (19.7 h) | Al 15,462 u = 387 min; QuantumCore 303; Resin 158 |
| Z10 | **1,574 (26.2 h)** | Al 27,397 u = 685 min; VoidLattice 264; NeutroniumPlate 244 |

**The endgame's real cost curve is ~26 hours of the single active slot at Z10, and the two
biggest lines are Aluminium and Resin** — shallow, boring d2 materials with no factory. They
are the cheapest possible things to parallelise.

The same hole starves the one new endgame factory the tree does have: `composite_loom`
consumes **Fiber 75.6/min** and Resin 15.6/min, both hand-crafted at 12/min. **One loom at
100% throttle needs seven players' worth of Fiber.** It is shipped, gated, and unrunnable.

### A5. The instrument caveat

`scripts/sim/bom.gd` is algorithmically correct (Knuth's Dijkstra generalisation over an
AND-OR hypergraph) and its stated limitation — infra conversion priced at 0 foreground
minutes, so 53 of 212 materials price at exactly 0.0 — is accurate. **It has a second defect
it does not state, and it is load-bearing:** because conversion is free, a building with an
absurd ratio is strictly optimal on the fg axis. `matter_deconstructor` (Cu 2500 ->
Circuit 0.5 + Superalloy 0.1 = 25,000 Cu per Superalloy) therefore wins Superalloy's
derivation over `superalloy_forge`, which (a) reports Malachite at 2,975,084,480 for a Z10
refit against a true 3,036,038 — a **980x** overstatement — and (b) deletes
`superalloy_forge`, `chromium_forge` and `nickel_refinery` from every zone's chain, which is
why the naive census undercounts factories by 4-6 per zone.

**Quote bom.gd's depth and chain STRUCTURE. Never quote its TRANSITIVE ROOTS or fg HOURS.**
Recommended fix, out of scope here: add a 500:1 ratio guard, or add root mass as a declared
second axis, and note in the header that `matter_deconstructor` is a DISPOSAL SINK (surplus
Cu -> anything), not a production route.

### A6. The missing rungs, named

1. **No d2 chemical rung.** Fiber, Resin, Al, Mg — the four highest-volume serial lines in
   the game, none with a building.
2. **No d3 refractory/plate rung.** GalvanizedSteel, StainlessSteel, IrPlate, Seal,
   SuperconductingMagnet — all serial, 0-2 sinks each.
3. **No parallelisable d5 at all.** Every d5 material is a serial craft or a combat-fed
   building.
4. **Nothing in infrastructure consumes** Chip, CompositeWeave, IrPlate, Graphite,
   StainlessSteel, Cr, Zn, Co, Sn, Mg or NanoSubstrate. The mid tier is a dead end.
5. **No Lira-yielding building.** (Addressed by the already-planned warp node E5, not by
   this tier — see F.)

---

## B. THE TIER — 14 new buildings, 5 new materials

Fourteen input-bearing FACTORIES. **Zero new drills** — the drill census is already the
problem, not the solution. Five new materials; nine *existing* serial materials get a
parallel producer instead of minting new ones (re-pointing beats inventing).

### Intended factory-type climb

| zone | today | with tier | new types pulled onto the chain |
|---|---|---|---|
| Z5 | 19 | **21** | polymer_reactor, alumina_line |
| Z6 | 18 | **22** | + magnesia_calciner, nano_substrate_lab |
| Z7 | 19 | **25** | + carbon_fiber_spinner, carbide_sintering_press, passivation_furnace |
| Z8 | 18 | **27** | + lattice_mill, galvanising_line |
| Z9 | 18 | **30** | + bus_assembly_hall, neutronium_press, void_lattice_loom |
| Z10 | 19 | **34** | + capital_spar_works, frame_yard |

Drills stay at ~18. Factory:drill ratio goes from 19:18 to 34:18 at Z10. **That is the
fantasy expressed as a number.**

### Rate-setting rule used throughout

Every stack saturates: `_dr_units` is linear to KNEE 10 then a saturating tail of 10, so an
industry building type delivers at most **~20x its neutral rate** (times mastery +20%, times
`_eng_scale` up to 2.0 for the ten ids in `INFRA_ENG_SCALED_BUILDINGS`). **None of the 14 is
added to `INFRA_ENG_SCALED_BUILDINGS`** — see failure mode 5. Every rate below was checked
so that one rung's demand fits inside the 20x ceiling of the rung beneath it. The one place
it does not (Pentlandite) is called out in F.

Every rate is also set at **0.9x to 1.5x the serial recipe's rate**, so a single building
never beats the active slot; twenty do. That is the payoff for a tens-of-millions-of-Liras
parallel investment, and it is the existing tree's own convention (`silicon_furnace` 12/min
vs the serial line).

---

### LAYER 1 — CHEMICAL BASE (d2). Research `industrial_chemistry`, tier 3.

Fixes A4 outright. These four are cheap, early, and unblock `composite_loom`.

```gdscript
"polymer_reactor": {
    "name": "Polymer Reactor",
    "description": "+1.5 Resin (-1.5 C, -3 H, -1.5 O)",
    "cost": {"credits": 350000, "Steel": 900, "Circuit": 90},
    "energy_gen": 0.0,
    "energy_cons": 400.0,
    "yield": {"Resin": 1.5},
    "input": {"C": 1.5, "H": 3.0, "O": 1.5},
    "interval": 5.0,
    "research_req": "industrial_chemistry",
    "category": "industry"
},
"carbon_fiber_spinner": {
    "name": "Carbon Fiber Spinner",
    "description": "+3 Fiber (-9 C)",
    "cost": {"credits": 300000, "Steel": 800, "Circuit": 80},
    "energy_gen": 0.0,
    "energy_cons": 350.0,
    "yield": {"Fiber": 3.0},
    "input": {"C": 9.0},
    "interval": 5.0,
    "research_req": "industrial_chemistry",
    "category": "industry"
},
"alumina_line": {
    "name": "Alumina Reduction Line",
    "description": "+3 Al (-4.5 Bauxite, -3 O)",
    "cost": {"credits": 400000, "Steel": 1000, "Circuit": 120},
    "energy_gen": 0.0,
    "energy_cons": 500.0,
    "yield": {"Al": 3.0},
    "input": {"Bauxite": 4.5, "O": 3.0},
    "interval": 5.0,
    "research_req": "industrial_chemistry",
    "category": "industry"
},
"magnesia_calciner": {
    "name": "Magnesia Calciner",
    "description": "+1.5 Mg (-6 Dolomite, -1.5 C)",
    "cost": {"credits": 550000, "Steel": 1400, "AdvCircuit": 40},
    "energy_gen": 0.0,
    "energy_cons": 700.0,
    "yield": {"Mg": 1.5},
    "input": {"Dolomite": 6.0, "C": 1.5},
    "interval": 5.0,
    "research_req": "industrial_chemistry",
    "category": "industry"
},
```

Rates: Resin 18/min (serial 12), Fiber 36/min (serial 12), Al 36/min (serial 40 — the
building is *slower* than the recipe and that is fine, it stacks), Mg 18/min (serial 10).

### LAYER 2 — REFRACTORY (d3/d4). Research `refractory_metallurgy`, tier 4.

Gives `zinc_smelter` (2 sinks), `cobalt_refinery` (2 sinks) and `tungsten_drill` a job for
the first time, and mints the tier's first new material.

```gdscript
"galvanising_line": {
    "name": "Galvanising Line",
    "description": "+2 Galvanized Steel (-2 Steel, -1 Zn)",
    "cost": {"credits": 3500000, "Steel": 4000, "AdvCircuit": 150, "Zn": 400},
    "energy_gen": 0.0,
    "energy_cons": 4000.0,
    "yield": {"GalvanizedSteel": 2.0},
    "input": {"Steel": 2.0, "Zn": 1.0},
    "interval": 5.0,
    "research_req": "refractory_metallurgy",
    "category": "industry"
},
"passivation_furnace": {
    "name": "Passivation Furnace",
    "description": "+2.5 Stainless Steel (-1.25 Cr, -3.1 Fe, -0.6 Ni)",
    "cost": {"credits": 4200000, "Steel": 5000, "Superalloy": 200, "AdvCircuit": 180},
    "energy_gen": 0.0,
    "energy_cons": 5000.0,
    "yield": {"StainlessSteel": 2.5},
    "input": {"Cr": 1.25, "Fe": 3.1, "Ni": 0.6},
    "interval": 5.0,
    "research_req": "refractory_metallurgy",
    "category": "industry"
},
"carbide_sintering_press": {
    "name": "Carbide Sintering Press",
    "description": "+0.8 Sintered Carbide (-2.4 Graphite, -1.2 W, -0.4 Co)",
    "cost": {"credits": 6000000, "Steel": 6000, "Superalloy": 300, "W": 500},
    "energy_gen": 0.0,
    "energy_cons": 8000.0,
    "yield": {"SinteredCarbide": 0.8},
    "input": {"Graphite": 2.4, "W": 1.2, "Co": 0.4},
    "interval": 5.0,
    "research_req": "refractory_metallurgy",
    "category": "industry"
},
"nano_substrate_lab": {
    "name": "Nano-Substrate Lab",
    "description": "+0.6 Nano-Substrate (-1.8 Al, -1.2 Mg, -0.6 Ni, -3 Structural Component)",
    "cost": {"credits": 3500000, "Steel": 4500, "Superalloy": 250, "AdvCircuit": 200},
    "energy_gen": 0.0,
    "energy_cons": 6000.0,
    "yield": {"NanoSubstrate": 0.6},
    "input": {"Al": 1.8, "Mg": 1.2, "Ni": 0.6, "StructuralComponent": 3.0},
    "interval": 5.0,
    "research_req": "refractory_metallurgy",
    "category": "industry"
},
```

`nano_substrate_lab` is the single highest-value entry in the tier: **NanoSubstrate is
already a `COST_ZONE_ANCHOR` at Z6, Z8 and Z9 with 23 downstream sinks and has no producer**,
so the curve prices it serial at 4/min today. The lab runs it at 7.2/min and pulls
`structural_press` (Fe 120, Cu 60, Si 60, C 36, Li 24 per minute) onto the endgame chain —
five early materials, transitively, from one Zone-9 anchor.

### LAYER 3 — PRECISION (d5/d6). Research `precision_fabrication`, tier 6, parent `zone_6_access`.

The first clean parallelisable d5 and d6 in the game.

```gdscript
"lattice_mill": {
    "name": "Precision Lattice Mill",
    "description": "+0.4 Precision Lattice (-1.2 Sintered Carbide, -1.6 Stainless Steel, -0.5 Mg)",
    "cost": {"credits": 18000000, "Steel": 9000, "Superalloy": 600, "AdvCircuit": 400, "SinteredCarbide": 200},
    "energy_gen": 0.0,
    "energy_cons": 30000.0,
    "yield": {"PrecisionLattice": 0.4},
    "input": {"SinteredCarbide": 1.2, "StainlessSteel": 1.6, "Mg": 0.5},
    "interval": 5.0,
    "research_req": "precision_fabrication",
    "category": "industry"
},
"bus_assembly_hall": {
    "name": "Fabrication Bus Assembly Hall",
    "description": "+0.2 Fabrication Bus (-0.6 Precision Lattice, -0.5 Adv Circuit, -0.8 Chip)",
    "cost": {"credits": 55000000, "Superalloy": 2500, "AdvCircuit": 900, "PrecisionLattice": 300},
    "energy_gen": 0.0,
    "energy_cons": 120000.0,
    "yield": {"FabricationBus": 0.2},
    "input": {"PrecisionLattice": 0.6, "AdvCircuit": 0.5, "Chip": 0.8},
    "interval": 10.0,
    "research_req": "precision_fabrication",
    "category": "industry"
},
```

### LAYER 4 — CAPITAL (d4-d8). Research `capital_fabrication` (tier 8) and `dreadnought_yards` (tier 9).

```gdscript
"neutronium_press": {
    "name": "Neutronium Press",
    "description": "+0.5 Neutronium Plate (-2 Neutronium, -1 Os, -2.5 Superalloy)",
    "cost": {"credits": 40000000, "Superalloy": 2000, "AdvCircuit": 600, "Neutronium": 80},
    "energy_gen": 0.0,
    "energy_cons": 90000.0,
    "yield": {"NeutroniumPlate": 0.5},
    "input": {"Neutronium": 2.0, "Os": 1.0, "Superalloy": 2.5},
    "interval": 10.0,
    "research_req": "capital_fabrication",
    "category": "industry"
},
"void_lattice_loom": {
    "name": "Void Lattice Loom",
    "description": "+0.3 Void Lattice (-7.2 Adv Circuit, -1.8 Void Crystal, -2.4 Void Essence)",
    "cost": {"credits": 90000000, "Superalloy": 3000, "AdvCircuit": 1200, "VoidCrystal": 200, "QuantumCore": 40},
    "energy_gen": 0.0,
    "energy_cons": 160000.0,
    "yield": {"VoidLattice": 0.3},
    "input": {"AdvCircuit": 7.2, "VoidCrystal": 1.8, "VoidEssence": 2.4},
    "interval": 10.0,
    "research_req": "capital_fabrication",
    "category": "industry"
},
"capital_spar_works": {
    "name": "Capital Spar Works",
    "description": "+0.2 Capital Spar (-0.25 Fabrication Bus, -2 Galvanized Steel, -0.8 Composite Weave)",
    "cost": {"credits": 160000000, "Superalloy": 5000, "AdvCircuit": 2000, "PrecisionLattice": 400, "FabricationBus": 150},
    "energy_gen": 0.0,
    "energy_cons": 300000.0,
    "yield": {"CapitalSpar": 0.2},
    "input": {"FabricationBus": 0.25, "GalvanizedSteel": 2.0, "CompositeWeave": 0.8},
    "interval": 10.0,
    "research_req": "dreadnought_yards",
    "category": "industry"
},
"frame_yard": {
    "name": "Dreadnought Frame Yard",
    "description": "+0.1 Dreadnought Frame (-0.4 Capital Spar, -0.3 Neutronium Plate, -1 Precision Lattice)",
    "cost": {"credits": 350000000, "Superalloy": 9000, "AdvCircuit": 4000, "CapitalSpar": 60, "NeutroniumPlate": 200, "Z9_Core": 4},
    "energy_gen": 0.0,
    "energy_cons": 600000.0,
    "yield": {"DreadnoughtFrame": 0.1},
    "input": {"CapitalSpar": 0.4, "NeutroniumPlate": 0.3, "PrecisionLattice": 1.0},
    "interval": 10.0,
    "research_req": "dreadnought_yards",
    "category": "industry"
},
```

### The 5 new materials

`element_db` needs a name, a tint, and a `CATEGORIES` membership for each; `assets/elements.json`
needs an entry. Suggested:

| symbol | display | category | elements.json tier | tint |
|---|---|---|---|---|
| `SinteredCarbide` | Sintered Carbide | components | 3 | `Color(0.42, 0.40, 0.38)` |
| `PrecisionLattice` | Precision Lattice | components | 4 | `Color(0.72, 0.78, 0.86)` |
| `FabricationBus` | Fabrication Bus | endgame | 5 | `Color(0.85, 0.72, 0.35)` |
| `CapitalSpar` | Capital Spar | endgame | 6 | `Color(0.62, 0.68, 0.80)` |
| `DreadnoughtFrame` | Dreadnought Frame | endgame | 7 | `Color(0.90, 0.86, 0.72)` |

Nine EXISTING materials gain a parallel producer and need no new data at all: Resin, Fiber,
Al, Mg, GalvanizedSteel, StainlessSteel, NanoSubstrate, NeutroniumPlate, VoidLattice.

### The reference Z10 complex — what one Dreadnought Frame Yard actually costs to run

Every ratio below is derived from the entries above and checked against each rung's 20x DR
ceiling. **This is the number the fantasy is made of.**

| building | copies | drives |
|---|---|---|
| `frame_yard` | 1 | 0.6 DreadnoughtFrame/min |
| `capital_spar_works` | 2 | 2.4 CapitalSpar/min |
| `bus_assembly_hall` | 3 | 3.6 FabricationBus/min |
| `lattice_mill` | 4 | 19.2 PrecisionLattice/min |
| `carbide_sintering_press` | 5 | 48 SinteredCarbide/min |
| `passivation_furnace` | 2 | 60 StainlessSteel/min |
| `magnesia_calciner` | 2 | 36 Mg/min |
| `galvanising_line` | 1 | 24 GalvanizedSteel/min |
| `neutronium_press` | 1 | 3 NeutroniumPlate/min |
| `composite_loom` | 2 | 14.4 CompositeWeave/min |
| `carbon_fiber_spinner` | 3 | 108 Fiber/min |
| `polymer_reactor` | 2 | 36 Resin/min |
| `alumina_line` | 1 | 36 Al/min |
| `auto_press` | 15 | 144 Graphite/min (ceiling 192) |
| `industrial_kiln` | 14 | 1,008 C/min (ceiling 1,440) |
| `cobalt_refinery` | 2 | 36 Co/min |
| `tungsten_drill` | 5 | 60 W/min |
| plus the existing Fe/Si/Cu/Steel/Superalloy/AdvCircuit/Chip spine | ~25 | |

**~60 industry copies across ~30 distinct factory types, plus ~80 drill copies, to run ONE
frame yard at 0.6 frames per minute.** Scaling to three yards (the realistic Z10 refit rate)
multiplies the whole thing by ~3 against DR ceilings that mostly hold. That is "toooo many
factories", measured.

---

## C. HOW THE COST CURVE COMES TO DEMAND THE TIER

No special case. The curve already anchors each zone on a deep material with a parallel
producer; there simply are none above d4. The tier supplies them, and the two existing
constants move.

### C1. New material depths

| material | producer | depth | why |
|---|---|---|---|
| SinteredCarbide | `carbide_sintering_press` | **d3** | Graphite d2, W d0, Co d2 |
| PrecisionLattice | `lattice_mill` | **d5** | SinteredCarbide d3, StainlessSteel d4, Mg d2 |
| FabricationBus | `bus_assembly_hall` | **d6** | PrecisionLattice d5, AdvCircuit d4, Chip d3 |
| CapitalSpar | `capital_spar_works` | **d7** | FabricationBus d6, GalvanizedSteel d3, CompositeWeave d3 |
| DreadnoughtFrame | `frame_yard` | **d8** | CapitalSpar d7, NeutroniumPlate d4, PrecisionLattice d5 |

**The parallelisable ceiling goes from d4 to d8.** DreadnoughtFrame is deeper than
`primordial_extractor`'s d6 and, unlike it, is not combat-fed.

### C2. `COST_ZONE_ANCHOR` — proposed

```gdscript
const COST_ZONE_ANCHOR := {
    3: ["Steel"],
    4: ["Circuit", "StructuralComponent", "Steel"],
    5: ["Superalloy", "StructuralComponent", "Chip", "Graphite"],
    6: ["AdvCircuit", "NanoSubstrate"],                                  # now building-backed
    7: ["AdvCircuit", "CompositeWeave", "SinteredCarbide"],              # IrPlate -> SinteredCarbide
    8: ["StainlessSteel", "NanoSubstrate", "TargetingChip", "PrecisionLattice"],
    9: ["PrecisionLattice", "FabricationBus", "NeutroniumPlate"],
   10: ["DreadnoughtFrame", "CapitalSpar", "VoidLattice", "PtCatalyst"],
}
```

**AdvCircuit stops being the anchor at Z8/Z9/Z10** — the five-zone monoculture ends. It is
still bought, harder than before, transitively: `bus_assembly_hall` spends AdvCircuit 2.5 per
FabricationBus, so 12.5 AdvCircuit per DreadnoughtFrame.

### C3. `COST_MIN_DIRECT_DEPTH` — the cap can finally rise

```gdscript
const COST_MIN_DIRECT_DEPTH := {
    3: 1, 4: 1, 5: 2, 6: 2, 7: 3, 8: 4, 9: 5, 10: 6,
}
```

The current comment says the floor is capped at 3 because *"the clean, non-combat-fed,
building-produced tree tops out at AdvCircuit (d4)"* and a floor of 4 *"severs the Steel
line"*. Both hold today and both stop holding once this tier ships: at Z8 there are four
clean parallelisable d4s (AdvCircuit, StainlessSteel, NanoSubstrate, NeutroniumPlate); at Z9
two clean d5s (PrecisionLattice, VoidLattice); at Z10 three clean d6/d7/d8s. **Raising the
floor is the acceptance test for the whole tier** — if it cannot be raised, the tier did not
land.

### C4. Transitive early-root effect

Per **one DreadnoughtFrame**, expanded through the entries above:

```
1 DreadnoughtFrame
  <- 4 CapitalSpar          <- 5 FabricationBus, 40 GalvanizedSteel, 16 CompositeWeave
  <- 3 NeutroniumPlate      <- 15 Superalloy, 6 Neutronium, 3 Os
  <- 10 PrecisionLattice    (+ 15 more via the buses)  = 25 PrecisionLattice
```

Rolling the transitive Fe demand up:

| path | Fe |
|---|---|
| AdvCircuit 12.5 -> StructuralComponent 25 -> Fe 10 each | 250 |
| StainlessSteel 100 -> Fe 1.24 each | 124 |
| GalvanizedSteel 40 -> Steel 40 -> Fe 1:1 | 40 |
| Superalloy 15 -> Steel 60 -> Fe 1:1 | 60 |
| **total, before the Chip and Circuit branches** | **~474 Fe per frame** |

A 100-frame Z10 module bill therefore drags **~47,400 Fe** through the chain without Fe, C,
Si, Cu or Steel ever appearing as a named line. Compare today's measured Z10 refit at 14,920
transitive Steel: **roughly a 3x increase in early-root demand, obtained by forbidding the
shallow line, not by naming it.** That is the owner's cumulative rule made mechanical.

### C5. Float-ceiling effect — the tier makes this BETTER, not worse

Today's Z10 module bill names **133,162 AdvCircuit**. Re-anchored on DreadnoughtFrame, the
same module budget buys on the order of **100-200 frames**: unit counts at the top of the
bill drop by ~3 orders of magnitude while transitive early demand rises. Peak per-line unit
counts stay well under 1e5, and no total approaches the 2^53 (~9.0e15) ceiling. The standing
recommendation (schedule BigNumber adoption before NG+ Loop 3) is unchanged; this tier does
not accelerate it.

---

## D. CHAIN DIAGRAMS TO RAW ROOTS

Quantities are per one unit of output, resolved through the building entries in B.
`[drill]` marks a zero-input extractor — the bottom of every chain.

### Layer 1

```
Resin 1  <- C 1.0, H 2.0, O 1.0
             C  <- industrial_kiln <- Wood 0.217          <- bio_harvester [drill]
             H  <- hydro_plant     <- Water 0.5           <- industrial_pump [drill]
             O  <- hydro_plant     <- Water 0.5           <- industrial_pump [drill]

Fiber 1  <- C 3.0 <- Wood 0.65                            <- bio_harvester [drill]

Al 1     <- Bauxite 1.5                                   <- bauxite_miner [drill]
            O 1.0 <- Water 0.5                            <- industrial_pump [drill]

Mg 1     <- Dolomite 4.0                                  <- dolomite_quarry [drill]
            C 1.0 <- Wood 0.217                           <- bio_harvester [drill]
```

### Layer 2

```
GalvanizedSteel 1 <- Steel 1.0 <- auto_smelter <- Fe 1.0, C 0.52, O 1.0
                                   Fe <- industrial_centrifuge <- Dirt 1.66, Water 1.66  [drills]
                     Zn 0.5    <- zinc_smelter <- ZincOre 1.52, C 0.52
                                   ZincOre <- zinc_mine [drill]

StainlessSteel 1  <- Cr 0.5   <- chromium_forge <- Chromite 0.73 [drill], Al 0.28 (Layer 1)
                     Fe 1.24  <- industrial_centrifuge <- Dirt 2.06, Water 2.06  [drills]
                     Ni 0.24  <- nickel_refinery <- Pentlandite 0.40 [drill], C 0.13

SinteredCarbide 1 <- Graphite 3.0 <- auto_press <- C 15.75 <- Wood 3.41  [bio_harvester]
                     W 1.5        <- tungsten_drill [drill]
                     Co 0.5       <- cobalt_refinery <- Pentlandite 0.83 [drill], C 0.27

NanoSubstrate 1   <- Al 3.0   (Layer 1 -> Bauxite 4.5, Water 1.5)
                     Mg 2.0   (Layer 1 -> Dolomite 8.0, Wood 0.43)
                     Ni 1.0   <- Pentlandite 1.67 [drill]
                     StructuralComponent 5.0 <- structural_press
                                   <- Fe 50, Cu 25, Si 25, C 15, Li 10
                                      Fe <- Dirt 83, Water 83     [drills]
                                      Cu <- Malachite 50          [deep_crust_drill]
                                      Si <- Quartz 50             [quartz_excavator]
                                      Li <- Spodumene 20          [brine_extractor]
```

**Every Layer-2 chain reaches Dirt, Water, Wood, or a raw ore through at least two
intermediate factories. Nothing raw is named at the top.**

### Layer 3

```
PrecisionLattice 1
  <- SinteredCarbide 3.0  -> Graphite 9.0 -> C 47 -> Wood 10.2          [bio_harvester]
                          -> W 4.5                                       [tungsten_drill]
                          -> Co 1.5 -> Pentlandite 2.5                   [nickel_mine]
  <- StainlessSteel 4.0   -> Cr 2.0 -> Chromite 2.9                      [chromite_excavator]
                          -> Fe 4.96 -> Dirt 8.2, Water 8.2              [drills]
                          -> Ni 0.96 -> Pentlandite 1.6                  [nickel_mine]
  <- Mg 1.25              -> Dolomite 5.0                                [dolomite_quarry]

FabricationBus 1
  <- PrecisionLattice 3.0  (as above, x3)
  <- AdvCircuit 2.5        -> Semiconductor 5.0 -> Si 10, Germanium 5 -> Quartz 20, Germanit 25
                           -> Au 2.5            -> Dirt 67, Water 67     [au_refinery]
                           -> StructuralComponent 5.0 -> Fe 50, Cu 25, Si 25, C 15, Li 10
  <- Chip 4.0              -> Semiconductor 8.0, Au 4.0, N 20            [orbital_siphon]
```

### Layer 4

```
CapitalSpar 1
  <- FabricationBus 1.25   (as above)
  <- GalvanizedSteel 10.0  -> Steel 10 -> Fe 10 -> Dirt 16.6, Water 16.6
                           -> Zn 5.0   -> ZincOre 7.6
  <- CompositeWeave 4.0    -> Fiber 42  -> C 126 -> Wood 27.3
                           -> Resin 8.7 -> C 8.7, H 17.4, O 8.7

DreadnoughtFrame 1
  <- CapitalSpar 4.0       (as above, x4)
  <- NeutroniumPlate 3.0   -> Neutronium 6                               [neutronium_condenser]
                           -> Os 3                                       [osmium_condenser]
                           -> Superalloy 15 -> Steel 60, Ni 30, Cr 15, Ti 15
                                                Steel -> Fe 60 -> Dirt 100, Water 100
                                                Ti    -> Dolomite 30
  <- PrecisionLattice 10.0 (as above, x10)
```

**Root totals per DreadnoughtFrame** (transitive, approximate, drills only):
Dirt ~1,850 · Water ~1,900 · Wood ~700 · Bauxite ~68 · Dolomite ~155 · Chromite ~90 ·
Pentlandite ~110 · Malachite ~180 · Quartz ~230 · ZincOre ~300 · W ~68 · Neutronium 6 · Os 3.

Thirteen distinct raw roots, none of them named anywhere in the Z10 module bill. **A Zone-1
excavator is still on the critical path for a Zone-10 dreadnought frame.**

---

## E. RESEARCH AND PACING

Five new techs. Tiers 6-10 currently contain **exactly one tech each** (the `zone_N_access`
gate), so a general research shelf at those tiers has to be authored alongside them — that
is expected and is the correct place for it.

| tech | tier | parent | Lira cost | cost_items | unlocks | affordable at |
|---|---|---|---|---|---|---|
| `industrial_chemistry` | 3 | `industrial_electrolysis` | 250,000 | Resin 200, Fiber 200, Circuit 80 | polymer_reactor, carbon_fiber_spinner, alumina_line, magnesia_calciner | Z4 (3.7 h of Z4 income) |
| `refractory_metallurgy` | 4 | `superalloy_engineering` | 1,800,000 | W 300, Co 150, Graphite 250, Zn 300 | galvanising_line, passivation_furnace, carbide_sintering_press, nano_substrate_lab | Z6 (2.9 h) |
| `precision_fabrication` | 6 | `zone_6_access` | 12,000,000 | Z6_Core 3, NanoSubstrate 60, StainlessSteel 200, SinteredCarbide 150 | lattice_mill, bus_assembly_hall | Z8 (2.1 h) |
| `capital_fabrication` | 8 | `zone_8_access` | 60,000,000 | Z8_Core 3, PrecisionLattice 120, VoidCrystal 60, Neutronium 40 | neutronium_press, void_lattice_loom | Z9 (3.3 h) |
| `dreadnought_yards` | 9 | `zone_9_access` | 220,000,000 | Z9_Core 4, FabricationBus 40, CapitalSpar 0*, NeutroniumPlate 150, Superalloy 3000 | capital_spar_works, frame_yard | Z10 (2.0 h) |

\* `CapitalSpar` deliberately absent from its own gate's `cost_items` — the material does not
exist until the tech is bought.

### The "nothing unbuildable when its zone unlocks" check

This project has shipped that bug repeatedly (7 of 10 hulls; AdvCircuit needing skill 40 at a
zone landing the player at 35). Every entry checked against research tier, input availability
and `COST_ZONE_PROC_LEVEL` (Z5 45 / Z6 55 / Z7 65 / Z8 75 / Z9 85 / Z10 95):

| building | Lira cost | first zone where cost <= 6h income | all inputs have a producer by then? |
|---|---|---|---|
| `polymer_reactor` | 350,000 | Z4 (405,000) | C kiln t1, H/O hydro_plant t2 — yes |
| `carbon_fiber_spinner` | 300,000 | Z4 | C kiln t1 — yes |
| `alumina_line` | 400,000 | Z4 (405,000, tight) | bauxite_mine t2, O hydro_plant t2 — yes |
| `magnesia_calciner` | 550,000 | Z5 (2,115,000) | dolomite_quarry t2, kiln t1 — yes |
| `galvanising_line` | 3,500,000 | Z6 (3,778,393) | auto_smelter t2, zinc_smelter t2 — yes |
| `passivation_furnace` | 4,200,000 | Z7 (6,750,000) | chromium_forge t3, centrifuge t2, nickel_refinery t3 — yes |
| `carbide_sintering_press` | 6,000,000 | Z7 (6,750,000) | auto_press t2, tungsten_drill t2, cobalt_refinery t3 — yes |
| `nano_substrate_lab` | 3,500,000 | Z6 (3,778,393) | alumina_line + magnesia_calciner (t3), nickel_refinery t3, structural_press t2 — yes |
| `lattice_mill` | 18,000,000 | Z8 (33,750,000) | Layer 2 all live by Z7 — yes |
| `bus_assembly_hall` | 55,000,000 | Z9 (108,000,000) | lattice_mill Z8, adv_circuit_foundry t2, chip_fab t2 — yes |
| `neutronium_press` | 40,000,000 | Z9 | neutronium_condenser (t5, 30M) + osmium_condenser (t4, 5M) — yes at Z9 |
| `void_lattice_loom` | 90,000,000 | Z9 (108,000,000, tight) | void_anchor + void_crystallizer (t4 `void_navigation`, 50M — reachable Z9) — yes |
| `capital_spar_works` | 160,000,000 | Z10 (675,000,000) | bus_assembly_hall Z9, galvanising_line Z6, composite_loom t2 — yes |
| `frame_yard` | 350,000,000 | Z10 | capital_spar_works Z10, neutronium_press Z9, lattice_mill Z8 — yes |

**No new processing recipes and no new `level_req` gates**, so nothing can collide with
`COST_ZONE_PROC_LEVEL`. Every parallelised material keeps its existing serial recipe at its
existing level, so a player who has not bought a building is exactly as capable as today.

### Count-scaling budget

Per additional copy, credits scale `1.15^n` to n<10, then `x1.24^(n-10)` to 25, then
`x1.32^(n-25)` (x0.8 with warp node ENG_4). The 20th copy is ~4.0x base. Stacking
`carbide_sintering_press` to 20 therefore costs roughly `6,000,000 x sum(...)` ~= **260M L**,
against a Z10 budget of 675M/6h. Stacking `frame_yard` to 5 costs ~2.3B — about 20 hours of
pure Z10 combat income, or a handful once bounties, quests and module sales are counted.
**The tier is a Lira sink of the same order as the module bill. That is intended.**

---

## F. UPKEEP AND ENERGY

### F1. Upkeep — do not reintroduce it

**Correction of record:** the Water/Dirt upkeep sink described in CLAUDE.md does not exist.
`_apply_upkeep` and `_upkeep_efficiency_for` were deleted in v120 and
`has_method("_apply_upkeep")` returns false at runtime. Any design that assumes "20-40
factories loads the existing upkeep sink" is designing against deleted code.

**Recommendation: leave it deleted.** With 14 input-bearing buildings the chain already has a
continuous running cost, and it is a *better* one than a flat tax — it scales with depth. The
reference complex in B draws, purely as inputs and purely to run one frame yard:

```
Dirt   ~1,110/min      (industrial_centrifuge + au_refinery feed)
Water  ~1,140/min
Wood     ~420/min      (14 industrial_kilns)
Dolomite ~144/min      Bauxite ~54/min      ZincOre ~36/min
```

Against `auto_excavator` 120 Dirt/min and `industrial_pump` 120 Water/min, that is **~10
excavators and ~10 pumps running flat out just to keep one frame yard fed.** A flat upkeep
tax on top would be a second, weaker copy of the same pressure, and it would punish BREADTH —
the exact behaviour this tier exists to reward. Input consumption is the honest limiter.

### F2. Energy — sized as a visible second-order tax, deliberately not the limiter

The grid is currently a non-event: one of every building in the game draws 1,197,820 kW and
generates 21,330,325 kW. **A single `fusion_reactor` (4,000,000 kW, 25M L, zero input) covers
3.3x the entire consumption of the shipped game.**

Total draw of the reference Z10 complex (Section B), including the drills and generators it
implies:

| group | draw |
|---|---|
| `frame_yard` 1 | 600,000 |
| `capital_spar_works` 2 | 600,000 |
| `bus_assembly_hall` 3 | 360,000 |
| `void_lattice_loom` 6 | 960,000 |
| `lattice_mill` 4 | 120,000 |
| `neutronium_press` 1 | 90,000 |
| `neutronium_condenser` 3 + `osmium_condenser` 4 | 600,000 |
| `void_anchor` + `void_crystallizer` ~4 | 340,000 |
| Layer 2 (5 press + 2 furnace + 1 line + 3 lab) | ~76,000 |
| Layer 1 (~8 copies) | ~3,600 |
| existing spine + drills | ~400,000 |
| **TOTAL** | **~4,150,000 kW** |

**Two Fusion Cores (50M L) run it at 100% throttle; three at 200% overclock.** Against a Z10
6h budget of 675M L that is affordable but not free, and it is the first time in the game
that the endgame power tree (`orbital_solar_relay`, `fusion_reactor`,
`antimatter_generator`) is a purchase decision rather than decoration.

**This is a deliberate choice: INPUT SCARCITY is the limiter, energy is the tax.** The
alternative — pushing `energy_cons` into the 200,000-2,000,000 band per factory so 20-30 of
them force an antimatter build-out — was rejected because it converts a chain-building game
into a generator-buying game and makes E4 Building Overclock (throttle to 200%, output
linear, input quadratic, **energy also doubled**) a power problem rather than a materials
problem. At the numbers above, E4 stays what it should be: a decision about whether you can
feed the quadratic input cost.

### F3. One measured upstream deficit

`nickel_mine` yields Pentlandite 0.3/5s = 3.6/min neutral, halved to **1.8/min effective** by
`INFRA_ORE_EXTRACTION_MULT`. The reference complex draws ~58 Pentlandite/min (Co for the
carbide presses plus Ni for the passivation furnaces), which is **~32 nickel_mines**. It is
inside the primitive-extractor DR asymptote (knee 30 + tail 30) but it is the tier's thinnest
rung by a factor of three. **Recommend raising `nickel_mine` yield to 0.8/5s (9.6/min neutral,
4.8 effective) as part of step 2**, or removing it from `INFRA_ORE_EXTRACTORS`. Flagging it
here rather than discovering it after the tier ships.

---

## G. FAILURE MODES

### 1. The tier becomes a click-to-win wall the player cannot afford

*How it feels bad:* the Z8 module bill re-anchors on PrecisionLattice, the player cannot
afford an 18M `lattice_mill`, and Zone 8 becomes a hard stop instead of a grind.

*Prevention, three independent mechanisms:*
- **Every parallelised material keeps its serial recipe.** All nine of Resin, Fiber, Al, Mg,
  GalvanizedSteel, StainlessSteel, NanoSubstrate, NeutroniumPlate, VoidLattice remain
  craftable at their existing levels. A player with no buildings is exactly as capable as
  today — the tier is *acceleration*, never *access*.
- The five NEW materials are only ever named in **module** costs, and the module cost curve
  already re-points anything whose parallel source is unaffordable onto a serial band via
  `_cost_infra_rate_at` and `COST_AFFORD_HOURS = 6.0`. Unaffordable buildings degrade the
  bill's *pricing*, they do not brick it.
- The tier **opens cheap**: the first four buildings total 1.6M L and are affordable at Z4.
  The player meets the pattern early and long before it is expensive.

*Acceptance test:* run the cost composer with all 14 buildings priced at 10x and confirm no
zone's bill becomes unbuildable — only slower.

### 2. Buildings that are strictly dominated, so nobody builds them

*How it feels bad:* `alumina_line` runs Al at 36/min while `smelt_bauxite` runs it at 40/min
serial. A player does the arithmetic once, concludes the building is worse, and never touches
Layer 1.

*Prevention:*
- **The comparison is wrong and the UI must not invite it.** The recipe is capped at 1x
  because it occupies the single active slot; the building stacks to ~20x effective and runs
  while you fight. The building `description` strings state the per-interval rate, and the
  infrastructure page already shows the adjusted stacked rate.
- **No two entries produce the same material.** Every one of the 14 is the sole parallel
  producer of its output.
- **Every new material has at least two sinks by construction:** SinteredCarbide -> lattice_mill
  + Z7 anchor; PrecisionLattice -> bus_assembly_hall + frame_yard + Z8/Z9 anchors;
  FabricationBus -> capital_spar_works + Z9 anchor; CapitalSpar -> frame_yard + Z10 anchor;
  DreadnoughtFrame -> Z10 anchor. Nothing is a dead end — the failure the mid tier already has.
- The three lateral parallelisations exist specifically to give three *existing* dead-end
  buildings a job: `zinc_smelter` (2 sinks) -> galvanising_line; `cobalt_refinery` (2 sinks)
  -> carbide_sintering_press; `tungsten_drill` -> carbide_sintering_press.

*Acceptance test:* re-run the per-zone chain census; assert all 14 appear on at least one
zone's chosen chain. Any building that does not appear is dominated and must be repriced.

### 3. A chain so deep the player cannot see why they are producing something

*How it feels bad:* d8 is four rungs deeper than anything in the game today. A player looks at
a Magnesia Calciner and has no idea it is there because a Zone-10 weapon needs a frame.

*Prevention:*
- **The tier arrives one rung at a time across five research techs spanning five zones.** The
  player never meets more than four new buildings at once, and each layer's outputs are
  consumed by the layer immediately above it, which they already own.
- **Every `description` names the immediate consumer, not just the yield.** The strings in
  section B are the placeholder form; ship them as e.g. "+0.8 Sintered Carbide -- feeds the
  Precision Lattice Mill".
- **The demand is visible before the supply.** SinteredCarbide appears in a Zone-7 module cost
  breakdown in the shipyard before `carbide_sintering_press` is affordable, so the player meets
  the material as a *problem* first and the building as its *answer*.
- Group all 14 under one named line in the infrastructure UI ("Capital Fabrication Chain") so
  the topology is legible as a unit.

### 4. Inventory slot pressure

*How it feels bad:* inventory is 28 base slots plus paid upgrades and slot pressure is an
intentional sink. Five new materials is +18% on the base allocation, arriving exactly when the
player is also holding nine zone alloys and four boss cores.

*Prevention:*
- **Five is the floor, not a preference.** A d3-to-d8 spine needs five rungs; the other nine
  materials in the tier are existing ones being re-pointed, not minted. A naive version of this
  spec would have minted fourteen.
- **The tier NET REDUCES peak slot pressure at the endgame.** Today a Zone-7 refit requires the
  player to accumulate **9,786 Fiber in one slot** because it is hand-crafted in one long batch.
  With `carbon_fiber_spinner` feeding `composite_loom`, standing Fiber stock is ~2 minutes of
  throughput (~72 units) because production and consumption are continuous and simultaneous.
  The same holds for Al (27,397-unit peak), Resin and Mg. **Trading four enormous batch stacks
  for five small continuous ones is a slot win, not a loss.**
- Put SinteredCarbide and PrecisionLattice in `CATEGORIES["components"]` and the three capital
  materials in `CATEGORIES["endgame"]` so the existing inventory filters group them.
- If measurement shows real pressure: grant **+2 storage slots** as an `effects` entry on
  `precision_fabrication` and again on `dreadnought_yards`. Cheaper than repricing the tier.

### 5. Infrastructure obsoletes active processing

*How it feels bad:* nine serial recipes get a parallel producer at once. If the buildings are
generous, the processing skill stops being a reason to sit at the screen and the core loop
hollows out.

*Prevention:*
- **None of the 14 is added to `INFRA_ENG_SCALED_BUILDINGS`** — engineering multiplier stays
  1.0, so they never reach the 2.0x that `adv_circuit_foundry` and friends do.
- **Industry DR stays 10/10** (asymptote ~20 effective). None of the 14 goes into
  `PRIMITIVE_EXTRACTORS`.
- **Every rate is set at 0.9x-1.5x its serial recipe** (Resin 18 vs 12, Fiber 36 vs 12, Al 36
  vs **40**, Mg 18 vs 10, GalvanizedSteel 24 vs 30, StainlessSteel 30 vs 30, NanoSubstrate 7.2
  vs 4, NeutroniumPlate 3 vs 1.875, VoidLattice 1.8 vs 1.71). One building never beats the
  active slot. Twenty do, and they cost tens of millions of Liras.
- The materials the tier does NOT parallelise are the ones processing should keep: the nine
  zone alloys, PtCatalyst, Pt, IrPlate, TargetingChip, AICore. **The serial residue after the
  tier is ~5.8 h at Z10** (from 26.2 h), of which 306 min is the alloy ladder — processing
  keeps a real, chunky, identity-bearing job.

### 6. The parallelised material starves at the drill

Covered in F3: `nickel_mine` at 1.8/min effective is the tier's thinnest rung. Mechanism:
measure Pentlandite draw at step 2 and raise `nickel_mine` yield to 0.8/5s before Layer 3
ships, not after.

---

## H. SEQUENCED BUILD PLAN

Every step ends with a **full headless boot** (`--headless --quit-after 18`, grep
`SCRIPT ERROR|not declared|Nonexistent function|Cannot infer`) — the `--check-only` path is
syntax-only and has let real errors through in this project before. Every step also ends with
a **census re-run**: distinct FACTORY types per zone chain, and the serial-minutes-per-refit
table from A4.

### Step 1 — Layer 1 (4 chemical buildings) + `industrial_chemistry`

Smallest, cheapest, highest measured value. No new materials, no cost-curve changes.

**Measure:** serial minutes per refit. Expect **Z7 1,214 -> ~400 min** (Fiber 816 min removed)
and **Z10 1,574 -> ~890 min** (Al 685, Resin 34). Confirm `composite_loom` is runnable: three
spinners feed one loom at 108 vs 75.6 Fiber/min. If Z7 does not roughly halve, the walk is
wrong before anything else is built.

### Step 2 — Layer 2 (4 buildings) + `refractory_metallurgy` + the `nickel_mine` fix

Adds the first new material (SinteredCarbide) and the highest-leverage single entry
(`nano_substrate_lab`).

**Measure:** factory-type census at Z6/Z7 — expect **18 -> 22** and **19 -> 25**. Downstream
sink counts for `zinc_smelter` and `cobalt_refinery` — expect 2 -> 3+. Pentlandite draw at the
reference complex; verify the `nickel_mine` bump holds it under 15 copies.

### Step 3 — Layer 3 (2 buildings) + `precision_fabrication`

The first clean parallelisable d5 and d6.

**Measure:** re-run the depth census — assert PrecisionLattice resolves d5 and FabricationBus
d6 with no combat-fed inputs. Then **raise `COST_MIN_DIRECT_DEPTH[8]` from 3 to 4** and re-run
the cost composer. Acceptance: no zone's bill becomes unbuildable, and the mean direct depth
at Z8 rises from the measured 4.1 without the Steel line going idle (transitive Steel per Z10
refit must stay above 14,920 — the floor-4 experiment that severed it measured 4,748).

### Step 4 — Layer 4 (4 buildings) + `capital_fabrication` + `dreadnought_yards` + anchor swap

The whole point. Ship the buildings, then the two constant changes in C2 and C3 together.

**Measure, in order:**
1. Factory-type census at Z10: **19 -> 34**. Drills unchanged at 18.
2. Depth census: DreadnoughtFrame at **d8**, non-combat-fed.
3. `COST_MIN_DIRECT_DEPTH` to `{... 8: 4, 9: 5, 10: 6}`; re-compose every zone bill.
4. Transitive Fe per Z10 refit: today ~14,920 transitive Steel; target **>= 40,000 Fe**.
5. Peak per-line unit count in any zone bill: must stay **under 1e5** (today's Z10 names
   133,162 AdvCircuit; the re-anchored bill should name 100-200 DreadnoughtFrame).
6. New serial minutes at Z10: target **<= 6 h** (from 26.2 h).

### Step 5 — Energy and grid pass

Build the reference complex in a probe, sum `energy_cons`, and assert two `fusion_reactor`
cover it at 100% throttle and three at 200%. If the ratio drifts past 4 reactors, cut Layer 4
`energy_cons` rather than adding generators — the tier must not become a power-plant game.

### Step 6 — Materials, UI and slots

`element_db` names, tints, `CATEGORIES` membership, `assets/elements.json` entries, the five
material icons (they degrade to text if absent, so this is not blocking). Group the 14 under
one named line in the infrastructure page. Re-check inventory slot pressure against the base
28 and add the +2/+2 research grants if measurement shows it.

### Not in this tier

- **E5 Reclamation Foundry** (the first Lira-yielding building, warp node, ~1 Lira per 100
  surplus units) remains a separate already-planned item. It is the natural overflow valve for
  this tier's surplus intermediates and should land immediately after step 4. Suggested numbers
  consistent with the above: `yield {"credits": 3000}`, `input {"Dirt": 50, "Water": 50,
  "Wood": 25}`, `interval 10.0` = 18,000 L/min = ~1.08M L/h, which is **~1% of Z10 combat
  income per copy** — a background trickle that pays, not a replacement for combat.
- **The `bom.gd` ratio guard** (A5). Fix it before anyone sizes another tier with it.
- **BigNumber adoption.** Unchanged by this tier; still recommended before NG+ Loop 3.

---

## I. VERIFICATION RESULT — NOT READY TO IMPLEMENT

Three independent adversarial agents re-measured this spec against the live game on
HEAD `800a82f`. **All three refuted it.** The structure and the fantasy survive; three
numeric/mechanical defects block implementation. Fix these before writing any code.

### What survived verification

- Entry shape is genuinely paste-ready. The shipped 80 entries use
  `{name, description, cost, energy_gen, energy_cons, category, input, interval,
  research_req, yield}`; the 14 new entries use only those keys, correct types, no id
  collisions.
- **All five depth claims measured EXACTLY right** via `_cost_rdepth_of`:
  SinteredCarbide d3, PrecisionLattice d5, FabricationBus d6, CapitalSpar d7,
  DreadnoughtFrame d8. No existing material's depth regresses.
- Zone-income table matches the engine to the Lira (Z4 405,000 … Z10 675,000,000).
- Zero non-ASCII in any new name or description. `"credits"` never renamed. `Z9_Core` in
  a building cost has precedent (`auto_excavator` takes `Z1_Core 2`). No combat or module
  stat change required.

### DEFECT 1 — the tier turns the module bill from ACCELERATION into hard ACCESS

Section G/1 claims "the tier is acceleration, never access" and cites two safety
mechanisms. **Both are inert for the five new materials — the ones that anchor Z7-Z10.**

- The serial fallback cannot fire. `_cost_serial_rate` (shipyard_manager.gd:2406-2421) is
  built only from `processing_manager.recipes` and `gathering_manager.actions`. Section E
  ships "no new processing recipes", so all five measure `serial_rate = 0.000` — against
  the nine re-pointed controls at 12.0 / 12.0 / 40.0 / 10.0 / 30.0 / 30.0 / 4.0 / 1.875 /
  1.714. The `elif _cost_serial_rate.get(anchor) > 0.0` branch at shipyard_manager.gd:3177
  is unreachable for every new material.
- The anchor sticks regardless. `_cost_infra_rate_at` (shipyard_manager.gd:2516-2522) gates
  purely on the building's own `cost.credits` versus `_cost_afford_at(z)`. It never asks
  whether the player OWNS the building, nor whether its inputs are affordable. Every new
  plant clears its zone budget, so `DreadnoughtFrame` and `CapitalSpar` get NAMED on every
  Z10 module bill with no alternative path.

Contrast the shipped state: of the four live Z10 anchors, VoidLattice / PtCatalyst /
NeutroniumPlate have `infra_rate_at10 = 0.00` and serial rates 1.71 / 3.00 / 1.88, and
AdvCircuit has both. Every current anchor has an escape hatch. None of the new ones do.

**FIX:** give each new material a processing recipe (slow and expensive, but present), or
make `_cost_infra_rate_at` ownership-aware. Prefer the recipe — it is the general fix and
it restores the acceleration-not-access property by construction.

### DEFECT 2 — demand breaches hard diminishing-returns asymptotes

`_dr_units` (infrastructure_manager.gd:1147) is asymptotic: effective units approach
`KNEE + TAIL` as count approaches infinity. Industry = 20, primitive extractors = 60. This
is a ceiling no number of copies passes.

At **one** frame yard (0.6 frames/min — the spec's own reference complex):

| material | need/min | type ceiling | over |
|---|---|---|---|
| C | 2,210 | 1,440 | x1.53 |
| Graphite | 243 | 192 | x1.27 |
| Pentlandite | 182 | 108 | x1.69 |
| Chromite | 123 | 72 | x1.71 |

At **three** frame yards — which Section B calls "the realistic Z10 refit rate against DR
ceilings that mostly hold" — there are seven breaches, four at 3.8x-5.1x. "Mostly hold" is
false.

Worse, two are unfixable by scale:
- **Graphite**: type ceiling 192/min, plus `press_graphite` at 10/min = 202 against 243
  needed. The reference complex cannot run ONE frame yard at 100% throttle even with the
  single active slot dedicated to it full time.
- **Chromite**: `chromite_excavator` yields 0.2/5s = 2.4/min, halved by
  `INFRA_ORE_EXTRACTION_MULT` to 1.2/min, x60 asymptote = **72/min forever**, against 123
  needed.

**FIX:** size the tier's throughput against measured DR ceilings rather than nominal rates,
and either raise the ceiling for the affected extractors or re-point the chain off Chromite
and Graphite. Any resize must re-check the whole chain — these interact.

### DEFECT 3 — research gates priced against numbers the engine multiplies by 15-40x

`research_manager.gd:1749` `_init()` calls `_scale_mid_late_research_item_costs()`, applying
LATE x7.5 / ENDGAME x20 to every `cost_item` of any tech NOT in category `"zone"` (line
1761 exempts zone gates only). `_effective_item_requirement` (line 1883) then applies
`MATERIAL_MULTIPLIER` x2 again at `can_unlock` / `unlock_tech`. Section E's table is
authored quantities, so every gate is understated 15-40x. Measured:
`industrial_chemistry` Resin 200 -> **3,000**, Fiber 200 -> **3,000**, Circuit 80 -> **1,200**.

**FIX:** author the research costs through `_effective_item_requirement` and quote effective
numbers, or exempt the new techs the way zone gates are exempted. Decide which deliberately.

### Correction of record

An earlier draft of this document, and the brief that produced it, both assumed a
continuous building upkeep sink. **`_apply_upkeep` does not exist** — it was removed in
v120 (infrastructure_manager.gd:1119). Section F's upkeep reasoning is void, and upkeep
cannot be relied on as the limiter on a 60-copy complex. If a drain on large complexes is
wanted, it has to be designed, not assumed.
