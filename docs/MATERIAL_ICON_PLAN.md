# Material Icon Rollout — Batch Plan

_Status: planning. Source of truth for the material-icon art + wiring effort._

## Player fantasy (one sentence)

Every material has a recognizable face, so reading a recipe, a gather yield, or
your inventory is an instant visual scan instead of a wall of text — lowering the
cognitive load of the core skilling loop and the crafting meta loop.

## Why this matters (loop framing)

- **Core (skilling) loop:** gather/process cards list inputs & yields. Icons make
  "what does this action give me / cost me" parseable at a glance.
- **Meta loop:** processing recipes, building costs, and the Armory all read
  materials by id. Icons turn dense cost lists into scannable rows.
- Materials are real periodic elements + ores + processed goods — a coherent icon
  set reinforces the established space-salvage identity.

## Scope

198 real materials in the registry (`scripts/core/element_db.gd` ELEMENT_NAMES +
`assets/elements.json`). Build target after exclusions: **~180 icons**.

| Category    | Count | Notes |
|-------------|------:|-------|
| element     | 31 | real periodic symbols (Fe, Si, Au…) |
| component   | 62 | circuits, batteries, plating, matrix cores, zone cores, catalysts |
| other       | 22 | exotics, trophies, artifacts, fuels |
| processed   | 21 | alloys (Steel, Superalloy, zone-signature alloys) |
| raw         | 18 | Dirt/Water/Wood + combat-salvage raws |
| ammo        | 17 | slugs / cells / missiles ×4 tiers (+legacy) |
| consumable  | 11 | hull heals + shield heals |
| ore         | 11 | Bauxite, Cassiterite, Malachite… |
| currency    |  2 | `credits` (has `lira.svg`) + `ExoticMatter` |

**Excluded (do not build until wired into the economy):** Bronze, Rh, S,
SyntheticCrystal, ReactiveCore, AncientTech, AIMatrix, ColonyDataCore,
MutatedTissue, PirateManifest, StolenCargo, SwarmFragment, CryoCell, nanite_swarm,
QuarantineClearance, TitanClearance. (`LaserSight` is a ship module, not a material.)

## Icon design system

One **monochrome white** silhouette per material, **runtime-tinted** via
`TextureRect.modulate` to a per-material signature color (or per-category default).
This matches the existing `assets/icons/modules/*` + `lira.svg` pattern, keeps
~180 icons feasible, and lets one art file carry a material's color identity
(Cu → copper, Au → gold, Water → blue) without re-authoring.

**Hard constraints (GL Compatibility / ThorVG):**
- 64×64 viewBox, pure flat `<path>/<circle>/<line>`, solid fill/stroke.
- **No `<filter>`, `feGaussianBlur`, blur, glow, drop-shadow** — they drop or
  misrasterize. (The `assets/shields/*.svg` use filters — never copy those.)
- Author the body in white `#ffffff` so `modulate` tinting works; bold strokes (≥1.8
  on a 64 box); generous padding; legible at 32–40px; `STRETCH_KEEP_ASPECT_CENTERED`.
- **Internal detail = `#303030` shapes over the white body.** `modulate` multiplies, so
  grey becomes a darker shade of the tint = an embossed stamp / facet line. **ThorVG
  renders no `<text>`** — draw letters/symbols as shape strokes, never `<text>`.
- `.import`: `compress/mode=0`, mipmaps off, `svg/scale=1.0` (editor auto-writes).

**Archetypes (a material's family decides its silhouette; tint/overlay disambiguates):**

| Family | Archetype | Within-family variation |
|--------|-----------|------------------------|
| Raw (Dirt/Water/Wood/scrap/organic) | literal object (mound, droplet, log, bent plate, carapace) | unique per item |
| Ore | rough rock chunk w/ crystal inclusions | tint per ore |
| Element — metal | ingot bar **stamped with UPPERCASE symbol** (`#303030`) | symbol stamp + spread signature tint (warm/cool, light/dark) |
| Element — gas (H/He/N/O) | flask w/ bubbles | tint |
| Element — nonmetal/metalloid (Si/C/B/Ge/S/U) | crystal shard / pellet | tint |
| Processed / alloy | banded / poured double-bar | zone glyph for signature alloys |
| Component — circuit/chip | circuit board / chip | tier pips |
| Component — battery/cell | battery cell | tier pips |
| Component — structural | plate / gear / coil | — |
| Component — catalyst | reaction flask | tint |
| Matrix core (12) | faceted gem (reuse `MatrixCoreIcon`) | color family × tier cut |
| Zone boss core (10) | core orb | zone numeral |
| Ammo — kinetic/energy/explosive | sabot / cartridge / missile | tier pips |
| Consumable — hull/shield | patch-cross / shield-bolt | — |
| Exotic / fuel | swirling orb / fuel cell | tint |
| Trophy (10) | medal/trophy | zone glyph |

A small `MATERIAL_TINT` map holds per-element signature colors (Fe steel-gray,
Cu copper, Au gold, Al silver, Water blue, Li rose-silver, U green…); everything
else falls back to its category color (already defined in `UITheme`).

## Batch 0 — Foundation (code, no art) — DO FIRST

Without this, no icon can appear. Enables incremental adoption.

1. `ElementDB.get_material_icon(id) -> Texture2D` — static, class-level cache,
   `ResourceLoader.exists()` guard, **negative-caches misses** (absent icons don't
   re-stat every inventory rebuild). Mirror `module_card._get_module_icon()`.
2. `ElementDB.MATERIAL_TINT` map + `get_material_tint(id)` (per-material →
   per-category fallback).
3. `element_card.tscn`/`.gd`: add a `TextureRect` (≈40px, KEEP_ASPECT_CENTERED) at
   top of the VBox; populate in `setup()`. **Fallback:** if icon null, keep the
   exact current text card (zero regression).
4. Inline icons in `gathering_action_widget.gd` yield rows + `processing_recipe_widget.gd`
   input/output rows (per-row TextureRect or BBCode `[img]`).
5. Larger icon in `info_card.gd` hover tooltip.
6. Create `res://assets/icons/materials/`.
7. Fold the 4 critic-found materials (`S`, `SalvagedAlloy`, `DamagedCircuitry`,
   `ReinforcedPlating`) into any icon/tint coverage checks.

## Batch sequence (ordered by player exposure × visual coherence)

Each batch ≈ one coherent art pass (10–16 icons) and is shippable on its own
(partial coverage is fine — text fallback covers the rest).

| # | Theme | ~Count | Why this order |
|--:|-------|------:|----------------|
| 1 | First-session heroes | 9 | 100% of players see these constantly; also the recipe backbone (Steel 18×, Circuit 14×, C 13×, Fe 10×). |
| 2 | Early ores + light metals + gases | 14 | first ore→metal chains; establishes ore/ingot/flask archetypes. |
| 3 | Early components, data & salvage chain | 14 | first-zone combat drops + crafting glue (AdvCircuit 13×). |
| 4 | Ammunition | 13 | 3 archetypes × 4 tiers — one tidy pass; combat-facing. |
| 5 | Consumables | 11 | actively managed in combat; 2 archetypes. |
| 6 | Mid-game metals & alloys | 16 | Zones 2–6 / skills 15–45 industrial layer. |
| 7 | Power & catalysts | 11 | batteries + reactor/catalyst components. |
| 8 | Matrix cores | 12 | combat loot; reuse `MatrixCoreIcon` gem design (fast). |
| 9 | Zone signature raws + alloys | 16 | Zone-Tier-Gate refining chain. |
| 10 | Rare / exotic metals | 12 | late mining (Ir, Os, U, Pd, Pt, W) + their plating/alloys. |
| 11 | Exotics & prestige | 12 | ExoticMatter, Void/Quantum/Antimatter chain. |
| 12 | Zone boss cores | 10 | Z1–Z10, socket gear; orb + numeral. |
| 13 | Trophies | 10 | held passives, rarely shown — low priority. |
| 14 | Bio/AI & endgame components | 13 | Sector Zeta line + capital-grade fab. |
| 15 | Endgame passives & remainder | ~9 | TemporalModule, PrimordialArmor, artifacts, fuels. |

## Production method (per batch)

Run one icon-generation **workflow** per batch (same shape used for the app/nav
icons this session):

1. Lock the batch's archetype spec (silhouette, stroke weights, padding).
2. Fan out: one agent generates each material's SVG (white, 64 viewBox, ThorVG-safe).
3. Art-director pass: render at 32/40px, reject anything that muddies or collides
   with a sibling; iterate.
4. Write `.svg` files to `res://assets/icons/materials/<id>.svg` (id-keyed, exact
   case). Godot auto-imports.
5. Spot-check in a headless boot that the cards pick them up.

## Failure modes & mitigations

- **200 same-y icons → worse than text.** Mitigated by archetype + per-material
  tint + small overlays (tier pips, zone numerals), and by skipping dead defs.
- **Color-blind ambiguity** (two ores differing only by tint). Keep silhouette
  inclusions/overlays distinct, not tint-only, within a family.
- **Soft at small size.** Bold strokes ≥2.4/64; bump `svg/scale` to 2.0 only if
  needed, uniformly.
- **id ≠ display name.** Always name files by id (Cassiterite, not "TinOre"); the
  orphaned `assets/raws/*.png` are named by display name and are why none are wired.

## Appendix — full id → batch assignment

- **B1:** Dirt, Water, Wood, Fe, Si, C, Cu, Steel, Circuit
- **B2:** Bauxite, Cassiterite, Spodumene, Malachite, Quartz, Dolomite, ZincOre, Al, Sn, Li, Mg, Zn, H, O
- **B3:** AdvCircuit, Chip, Semiconductor, Resin, Fiber, AlWire, SparePart, Res1, SalvageData, NavData, MiteChitin, SalvagedAlloy, DamagedCircuitry, ReinforcedPlating
- **B4:** SlugT1, SlugT1S, SlugT2, SlugT3, SlugT4, CellT1, CellT2, CellT3, CellT4, MissileT1, MissileT2, MissileT3, MissileT4 _(legacy kinetic_shell/energy_cell/missile optional)_
- **B5:** Mesh, Seal, EmergencyPatch, ChitinPatch, AdvMaintenanceKit, CapacitorShard, BasicBooster, IonField, NitroCoolant, ZeroPoint _(nanite_swarm only if sourced)_
- **B6:** Ti, Ni, Cr, Co, Mn, Au, Ag, Graphite, Superalloy, StainlessSteel, GalvanizedSteel, AlMgAlloy, Diamond, StructuralComponent, NanoSubstrate, Hydraulics, Pentlandite, Chromite
- **B7:** BatteryT1, BatteryT2, BatteryT3, CoBattery, MgBattery, PdFuelCell, VoidBattery, CoolantCell, AgCatalyst, PtCatalyst, NuclearFuel
- **B8:** Cracked/Stable/Pristine × Crimson/Cobalt/Topaz/Amethyst Core (12)
- **B9:** PirateSalvage, MartianRelics, CryoEssence, RimeplateScrap, XenoFragment, ColonySalvage, AeonResiduum, ChondriteAlloy, WreckforgedAlloy, RimeAlloy, XenoforgedAlloy, ColonyAlloy, GammaAlloy, PrismaticAlloy, BioforgedAlloy, AeonAlloy
- **B10:** Ir, Os, U, Pd, Germanium, Pt, PtOre, Germanit, W, IrPlate, OsCore, IrWAlloy, RadIsotope
- **B11:** ExoticMatter, VoidCrystal, VoidEssence, QuantumCore, Neutronium, ChronoCore, AntimatterParticle, AntimatterFuel, PrimordialShard, ExoticIsotope, CryoCatalyst, Food
- **B12:** Z1_Core … Z10_Core
- **B13:** Trophy_Lunar, Trophy_Belt, Trophy_Mars, Trophy_Titan, Trophy_Alpha, Trophy_Beta, Trophy_Gamma, Trophy_Delta, Trophy_Zeta, Trophy_Epsilon
- **B14:** BiohazardSample, PathogenCore, AICore, AIProcessor, RegenPlating, BioWeaponCoating, OmegaPlating, PurifiedCompound, TurretCore, TargetingChip, SuperconductingMagnet, AncientComponent, VoidArtifact
- **B15:** TemporalModule, PrimordialArmor, OmegaAccelerator, Res2, Res3, emp_generator_blueprint, FertileSoil, CompositeWeave, PurifiedCompound
