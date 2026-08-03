# Horizon Idle — Material & Crafting Economy Audit (2026-08-02)

Independent re-derivation of the demand graph from HEAD data tables: `elements.json` (182
symbols), `gathering_manager.actions` (21), `processing_manager.recipes` (118),
`infrastructure_manager.building_db` (94), `research_manager.tech_tree` (105, 94 with
`cost_items`), `shipyard_manager.hulls/modules` (10 / 151 authored), `combat_manager`
enemy_db/zones (68 / 15). Cross-checked against `docs/design/ENDGAME_FACTORY_TIER.md`
(2026-07-27) and the shipped v157/v158 code. 266 distinct material symbols are referenced
somewhere in the economy.

**Method note:** static parse of authored data + manual accounting for code-granted sources
(boss cores via `boss_core`, hack stones via `_roll_hack_stone_drops`, salvage via
`_roll_salvage_drops`, SparePart via recycling) and code-side sinks (ammo burn, consumable
use, `compose_module_costs` procedural bills, `install_boost_card`). Everything below
survived that correction pass; the raw first-pass lists (85 "dead ends") are not quoted
because most were false positives from exactly those channels.

---

## 1. State of the factory tier — SHIPPED, and the three verify defects are fixed

The spec's Section I verdict ("NOT READY — three defects") is stale relative to HEAD:

| Defect | Spec problem | Shipped fix (verified in code) |
|---|---|---|
| D1 access-not-acceleration | new anchors had no serial fallback | Hand recipes exist for all five new materials (`craft_precision_lattice` L72, `craft_fabrication_bus`, `craft_capital_spar`, `craft_dreadnought_frame` L92 600s, etc.) — `_cost_serial_rate` can fire |
| D2 DR-ceiling breaches | frame yard demand 1.3–1.7× over asymptotes | Layer 3/4 rates cut ~6× vs spec: `lattice_mill` 0.4→0.067, `bus_assembly_hall` 0.2→0.033, `capital_spar_works` 0.2→0.033, `frame_yard` 0.1→0.017 per interval |
| D3 research ×15–40 | authored gates multiplied by engine | `cost_items` re-authored at effective/15 and effective/40 with effective numbers quoted in comments (`industrial_chemistry` Resin 13 → 195 effective, etc.) |

`COST_ZONE_ANCHOR` re-anchored per C2 (AdvCircuit no longer the sole Z7–Z10 anchor;
DreadnoughtFrame/CapitalSpar/PrecisionLattice/FabricationBus/NeutroniumPlate live) and
`COST_MIN_DIRECT_DEPTH = {3:1,4:1,5:2,6:2,7:3,8:4,9:5,10:6}` — the spec's own acceptance
test ("if the floor cannot rise, the tier did not land") passes. The supply side of this
economy is in the best shape it has ever been.

## 2. Demand-hub census (authored sinks only; compose adds more on top)

| material | total sink refs | breakdown | recurring? |
|---|---|---|---|
| Steel | 98 | recipes 15 · bcost 50 · fuel 4 · research 9 · hulls 3 · modules 17 | yes |
| AdvCircuit | 86 | recipes 15 · bcost 33 · fuel 3 · research 18 · hulls 3 · modules 14 | yes |
| Superalloy | 60 | recipes 11 · bcost 24 · fuel 4 · research 7 · hulls 4 · modules 10 | yes |
| Ti | 60 | recipes 3 · bcost 25 · fuel 1 · research 10 · hulls 3 · modules 18 | yes |
| Circuit | 52 | recipes 12 · bcost 26 · research 11 · hull 1 · modules 2 | no fuel sink |
| Si / QuantumCore / Fe / C / VoidCrystal | 24–38 each | broad | yes |

61 materials carry a recurring building-fuel sink; 111 are consumed by recipes; 45 have
*only* one-time sinks (research/build/craft). On top of authored data,
`compose_module_costs` (v157/v158) systematically injects the zone signature alloy
(`TIER_ALLOY_BY_ZONE`, ChondriteAlloy→AeonAlloy) into every weapon/armor/shield module of
its zone, and the zone signature drop (`COST_ZONE_DROP`) kill-budgeted into own-zone
modules. This is why AeonAlloy and DreadnoughtFrame look sink-less in authored data but are
not — **any future dead-end lint must be compose-aware.**

## 3. Confirmed structural findings

### 3.1 HIGH — the matrix-core subsystem has no faucet

`CrackedCrimsonCore / CrackedCobaltCore / CrackedTopazCore / CrackedAmethystCore` (and
therefore all 12 fusable tiers above them) have **zero sources anywhere in the codebase**:
not in any enemy `loot`/`rare_loot`, not in `_roll_hack_stone_drops`, not in
`_roll_salvage_drops`, not in mission/bounty/quest rewards, not in module drop generation
(sockets spawn empty; `_destroy_equipped_module` only *returns* already-socketed cores).
Repo-wide grep: the only writers are the 12 `gem_synth` fuse recipes — which consume them.

Stranded on this missing faucet: the socket system on every module, 16 core items + tints +
categories, 12 fuse recipes, the `GEM_FACET_CAPS`/`gem_bonuses` combat plumbing (live and
tested), the armory "matrix_cores" category, and the **CMB_4 warp node whose entire payoff
is the Resonant fuse tier**. `ui-mockups/card-soul-comps.html` (fresh, Jul 31) suggests a
faucet design is in flight — this audit's finding is that *nothing currently ships*.

### 3.2 HIGH — demand is refit-shaped; the complex idles between refits

One-time sinks dominate: 94/105 techs, 94 building costs, hull ladder, and the per-zone
module bill (the big one) are each paid once. Standing flow demand today is: generator
fuel, T1–T3 ammo plants, combat consumables, and supply orders. After a zone's refit is
bought, a 30-type/60-copy complex has nowhere to push output — and with `base_value`
flattened to 1 and the sell path being removed (owner call recorded in
`sim/design_audit.gd`), surplus is not even convertible to Liras. 28 inventory slots cap
accumulation. The player's rational move is throttling down the most impressive thing they
built. In Satisfactory the building itself is the toy so idle factories are fine; in an
idle game the factory's *output stream* is the progress bar.

The HANDOFF already names the fix thread ("family→demand engine: supply-order re-sizing →
ammo-plant pass → …"). This audit's numbers say that thread is not polish — it is the
other half of the factory tier.

### 3.3 MEDIUM — supply orders touch 4 goods in 15 tiers

`quest_manager.supply_goods`: T2–T4 Steel/Circuit, then **only AdvCircuit and Superalloy
from T5 through T15**. None of the nine fabrication-tier families (GalvanizedSteel,
StainlessSteel, SinteredCarbide, PrecisionLattice, FabricationBus, NanoSubstrate,
CompositeWeave, NeutroniumPlate, VoidLattice) ever has a buyer on the quest board. The
quest layer predates the factory tier and has not caught up. Note supply orders are also
the **engineer's only meaningful Lira lane** once selling is gone — this table is doing two
jobs and is under-built for both.

### 3.4 MEDIUM — two rate-policy regimes coexist

The tier's convention (locked in its failure-mode 5): building = 0.9–1.5× serial rate, not
in `INFRA_ENG_SCALED_BUILDINGS`, DR 10/10. The pre-tier spine ignores it:

| good | serial (base) | one building (base) | ratio | eng-scaled ×2? |
|---|---|---|---|---|
| AdvCircuit | 0.067/s | `adv_circuit_foundry` 0.24/s | **3.6×** | yes → 7.2× |
| Circuit | 0.17/s | `electronics_assembler` 0.26/s | 1.5× | yes |
| Superalloy | 0.10/s | `superalloy_forge` 0.20/s | 2.0× | yes |
| Steel | 1.0/s | `auto_smelter` 0.5/s | 0.5× | yes |

One AdvCircuit foundry at eng-cap outproduces seven hand-crafters. That is exactly the
"infrastructure obsoletes active processing" hollowing the tier's own spec guards against —
already live in the old spine. Either bless it explicitly ("the old spine is the bulk tier;
processing identity lives in alloys/exotics") or schedule a rate pass. **Do not nerf the
assembler/foundry before re-measuring the m029–m030 band** — the measured Beat-2 desert fix
leans on assembler strength.

### 3.5 LOW — data hygiene

- 84 referenced symbols have **no `elements.json` entry** (`base_value` None) — works via
  fallback, but description/value/tier data is missing for a third of the economy.
- Orphan symbols (no source, no sink, defined): B, Be, Ge (vs the used "Germanium" string
  — likely a legacy duplicate), FertileSoil, SparePart-adjacent leftovers, TurretCore
  (recipe removed v141c, symbol remains), `emp_generator_blueprint`, `energy_cell`,
  `kinetic_shell`, `missile`, Trophy_* (if bounty trophies are granted in code, fine).
- Trinket crafts (`PrimordialArmor`, `VoidBattery`, plus `OmegaAccelerator`,
  `TemporalModule` if wired the same way) are own-1-passive checks — by design, but they
  read as dead stock in a 28-slot inventory after the first craft, and repeat crafts are
  worthless. Consider a "1/1 owned — installed" UI state.
- T4 ammo (`SlugT4/CellT4/MissileT4`) is recipe-only; T1–T3 have plants. Known pending
  (ordnance pass) — flagging for completeness.

### 3.6 For the record — corrected false alarms

Ammo and the 10 combat consumables are consumed in combat code (not dead ends). Boss cores
are granted by `boss_core` keys on kill (not deadlocks). `z*_unique_*`, `cryo_lance`,
`corrosion_blaster`, `faraday_hull` in rare_loot are module grants, not materials.
`AlMgAlloy`'s consumer was removed in the v146 dedupe with a comment claiming
`craft_missile_t3` still consumes it — **it does not** (verified input: Superalloy 2,
StructuralComponent 1, VoidCrystal 1). AlMgAlloy is a real, small dead end: one recipe
produces it, nothing consumes it.

## 4. Lira faucet map (post-sell-removal)

Combat credits loot (dominant, scales ~10× per era) · bounty hunts `xp×qty×10×diff^1.6` ·
supply orders (T2 25K → T15 60M) · stockpile quests (trickle, repriced v139) · mission
rewards · module recycling → SparePart (item, not Lira). `decode_manifest` printer closed
(12,500→250). Zero buildings yield Liras today; E5 Reclamation Foundry (planned,
~18K L/min ≈ 1% of Z10 combat income per copy) will be the first. With selling gone, an
engineer-only session earns essentially nothing except via supply orders — the engineer
half of the fantasy has no income identity yet.

## 5. Ranked recommendations

1. **Ship the demand engine before Loop 2 content** (supply-order re-sizing, per-family
   boards): every producible family gets a standing, never-expiring buyer generated
   against measured production rates — order size ≈ 20–40 min of one saturated line's
   output, reward from the existing per-tier Lira ladder. This converts the factory tier
   from a refit tool into a running economy, and doubles as the engineer's Lira lane.
2. **Decide and ship the matrix-core faucet** (or explicitly park the socket system).
   Cheapest coherent version: zone-tiered rolls in the existing
   `_roll_hack_stone_drops`-style channel — Cracked from Z3+ elites/bosses, Stable Z5+,
   Pristine Z7+ bosses; fuse recipes already handle the rest. Unblocks CMB_4.
3. **E5 Reclamation Foundry + T4 ammo plants** — with selling removed, E5 is no longer a
   nice-to-have: it is the only overflow valve a 28-slot no-sell economy has. Numbers in
   the tier doc (§H "Not in this tier") are consistent and ready.
4. **Rate-policy decision on the old spine** (3.4): bless or align. If blessing, write it
   into CLAUDE.md so future tiers don't inherit the ambiguity by accident.
5. **Hygiene sweep + CI**: elements.json entries for the 84 missing symbols; delete or
   wire the orphans; make `design_audit.gd` compose-aware and add asserts: "every
   CATEGORIES member has ≥1 source" (catches matrix cores today) and "every recipe output
   has ≥1 sink or an explicit trinket/anchor tag" (catches AlMgAlloy).

## 6. Numbers to keep an eye on

- Chain depth now: d1 29 · d2 15 · d3 3 · d4 2 · d5–d9 one each (RimeAlloy→…→AeonAlloy
  alloy ladder + fabrication spine). Depth exists; breadth per depth band is thin above d4
  — fine while the anchor system is the only consumer, revisit if a second consumer class
  (NG+ Foundation Kits?) lands on d5+.
- Fuel burn concentration: `matter_deconstructor` alone is 500 Cu/s per copy (by design, a
  glut-eater — but it will look like a bug in any per-material flow UI; label it).
- Peak per-line bill counts stay <1e5 post-re-anchor (spec C5 verified) — BigNumber can
  still wait for NG+ Loop 3, as planned.
