# Horizon Idle — measured balance reference

Every number here was read from source or measured in-engine on 2026-08-08 at
commit `de4bf80`. Where a value is a *measured effective* number rather than an
authored constant, it says so — those two diverge a lot in this codebase and
confusing them produces wrong rulings.

Re-measure before trusting anything here after a tuning commit.

## Contents

- [Boss HP ladder](#boss-hp-ladder)
- [Gear-check rule and results](#gear-check-rule-and-results)
- [Rarity multiplier curve](#rarity-multiplier-curve)
- [Damage types and breach factors](#damage-types-and-breach-factors)
- [Exotic weapons](#exotic-weapons)
- [Player resistances](#player-resistances)
- [Crafting depth floor](#crafting-depth-floor)
- [Prestige / warp](#prestige--warp)
- [Skill XP](#skill-xp)

## Boss HP ladder

**Measured effective HP** as `boss_gearcheck` fights it. `_apply_enemy_tier_rebase()`
runs once in `combat_manager._init()` and multiplies every authored stat by
`tier_rebase(zone)` — about ×121.5 at Zone 10 — so the numbers in the `enemy_db`
literal are PRE-rebase and are not what ships. Always quote the post-rebase value
and say which one you mean.

| Zone | Boss | Effective HP | Weak type |
|---|---|---|---|
| 5 | z5_boss_harbinger | 582 K | energy |
| 6 | z6_boss_colossus | 3.73 M | kinetic |
| 7 | z7_boss_sovereign | 14.2 M | explosive |
| 8 | z8_boss_warden | 58.0 M | energy |
| 9 | z9_boss_patient_zero | 296 M | kinetic |
| 10 | z10_boss_leviathan | 975 M | explosive |   <!-- ATK raised ×1.20 on 2026-08-08, see docs/RULINGS -->
| 11 | z11_boss_threshold_warden | 4.14 B | (cryo gate) |
| 12 | z12_boss_rift_warden | 15.9 B | (phase) |
| 13 | z13_boss_verdigris_warden | 39.1 B | (phase) |
| 14 | z14_boss_dissolution_tyrant | 69.7 B | (phase) |
| 15 | z15_boss_caustic_sovereign | 166 B | (phase) |

Zone-to-zone step is roughly ×4–5 through Z10, then ×4.2 into Z11 and ×2.4–3.8
across the NG+ loop.

`warp_hardened` enemies (Z11) are **exempt from zone-steepening** by design —
their base stats are the intended effective stats, so the gate stays predictable
to tune.

## Gear-check rule and results

`scripts/sim/boss_gearcheck.gd`. Rule: **Common and Uncommon must LOSE; Rare and
above (or the Zone N-1 Unique set) must WIN.** Each cell is 9 trials. `MAXT` is
1500 s — a fight that runs past 25 minutes scores as a loss.

Loadout under test: every weapon slot filled with the weak-type Z-N weapon,
Z-N armor and shield, power deliberately over-provisioned so rarity is the only
variable, tier-appropriate ammo and repair kits stocked, researches tier ≤ N
unlocked.

State at `de4bf80` — 10 of 15 honor the rule:

| Zone | Common | Uncommon | Rare | Legendary | N-1 Unique | Verdict |
|---|---|---|---|---|---|---|
| 5 | 0/9 | 0/9 | 8/9 W132s | 9/9 W102s | 9/9 W91s | OK |
| 6 | 0/9 | 0/9 | 8/9 W200s | 9/9 W185s | 0/9 | OK |
| 7 | 0/9 | 0/9 | 9/9 W144s | 9/9 W123s | 0/9 | OK |
| 8 | 0/9 | 0/9 | 9/9 W173s | 9/9 W130s | 9/9 W96s | OK |
| 9 | 0/9 | 0/9 | 7/9 W177s | 9/9 W148s | 0/9 | OK |
| 10 | 0/9 L39% | **9/9 W262s** | 9/9 W169s | 9/9 W151s | 0/9 L98% | **VIOLATES** |
| 11 | 0/9 | 0/9 | 0/9 L71% | 2/9 W349s | 8/9 W139s | OK |
| 12 | 0/9 | 0/9 | 0/9 L100% | **0/9 L95%** | n/a | **VIOLATES** |
| 13 | 0/9 | 0/9 | 0/9 L93% | **0/9 L60%** | n/a | **VIOLATES** |
| 14 | 0/9 | 0/9 | 0/9 L100% | **0/9 L100%** | n/a | **VIOLATES** |
| 15 | 0/9 | 0/9 | 0/9 L100% | **0/9 L100%** | n/a | **VIOLATES** |

`L<n>%` is boss HP remaining at loss. Healthy on-tier kills land 100–200 s.

## Rarity multiplier curve

`shipyard_manager.gd` `RARITY_MULT` — the pair is a random range added to 1.0.

| Rarity | Range | Effective |
|---|---|---|
| Common | [0.00, 0.00] | ×1.00 fixed |
| Uncommon | [0.10, 0.20] | ×1.10 – ×1.20 |
| Rare | [0.25, 0.45] | ×1.25 – ×1.45 |
| Legendary | [0.40, 0.55] | ×1.40 – ×1.55 |
| Unique | [1.40, 2.20] | ×2.40 – ×3.20 |

A clean next-tier **Common is ×2.2** relative to the previous tier. The curve is
deliberately set so a carried N-1 Legendary sits *under* a next-tier Common —
affixes and cores are then a comfort margin, not a tier leapfrog. Unique
deliberately leapfrogs exactly one tier, then retires.

Affix counts: Rare 2, Legendary 3.

## Damage types and breach factors

Conventional triangle: **kinetic / energy / explosive** (`resist_k/e/x`). The
old channel-routing system — kinetic-hits-hull, energy-hits-shield,
missile-penetrates-armor — was **removed**; do not reintroduce per-channel
routing or per-channel damage multipliers on the player path.

Exotic channel: **cryo / corrosion**, both carried on the single `atk_cryo`
stat and distinguished by the weapon's `exotic_element`. Exotic is NOT a member
of the triangle — resist_k/e/x do not apply to it.

`_get_breach_factors(is_player_attacker, weapon_exotic)` in `combat_manager.gd`:

- **Z11 `warp_hardened`** — K/E/X × **0.02** flat; cryo ×1.0 only if the
  weapon's exotic type is `cryo`. Binary gate, deliberately not a stat race.
- **Multi-phase NG+ bosses (Z12–Z15)** — HP splits into N equal bands from the
  `phases` list; in each band only that element deals full damage, everything
  else is cut to `phase_cut` = **0.15**. The cryo channel is full only when the
  attacking weapon's exotic type matches the current band.
- Everything else returns all-1.0.

Because the gate is evaluated **per weapon**, a phase boss is solvable by
pre-fight loadout: bring one weapon of each phase element. Mid-fight preset
swapping is the second valid path, not the required one.

Enemy `dmg_type` values in use: `kinetic`, `energy`, `explosive`, `corrosion`.
Corrosion has no player resist stat of its own and rides the kinetic mitigation
channel — deliberate as of v174, and both corrosion bosses were tuned with it
applying.

Resist amplification: authored resistances are amplified toward an 80% wall so
the wrong type is roughly a 5× TTK penalty; weaknesses keep their authored
value. `MIN_INCOMING_FRAC` = 0.10 floors incoming hull damage so no defensive
stack becomes unkillable.

Floating-label tags: `KIN` / `NRG` / `EXP` / `CRY` / `COR`.

## Exotic weapons

| Module | Stat | Interval | Notes |
|---|---|---|---|
| `cryo_lance` | `atk_cryo` 10 000 | 2.0 s | first-Warp unlock, self-charging, no ammo |
| `corrosion_blaster` | `atk_cryo` 12 000, `exotic_element: "corrosion"` | 2.0 s | same channel, different phase key |

Both are **deliberately exempt from the v155 channel flatten** — they are the
tuning axis of the Z11 Threshold Warden and the Z12 Rift Warden, and their
pipeline (armour divisor 0.5, hull coefficient 1.0) already is the flattened one.

There is **no exotic tier above these two.** Any Loop-1 content whose HP assumes
stronger exotic weapons is a design gap, not a tuning problem.

## Player resistances

Per-type, aggregated in `recalc_stats`, each **capped at 0.75** (you always eat
at least 25%).

Baseline per-slot floor from crafted gear:

| Slot | resist_k | resist_e | resist_x |
|---|---|---|---|
| armor | +0.08 | +0.02 | +0.06 |
| shield | +0.03 | +0.08 | +0.03 |

Plus module `resist_*` baselines and affix rolls. A typical one-armor
one-shield loadout sits near **0.11 kinetic**.

## Crafting depth floor

`COST_MIN_DIRECT_DEPTH = {3:1, 4:1, 5:2, 6:2, 7:3, 8:4, 9:5, 10:6}`

The minimum crafting depth of any DIRECT ingredient in a zone-N recipe. Depth 0
is a gathered raw or a zero-input drill (Dirt, Fe, Wood, Neutronium); depth n is
processed from depth n-1 inputs.

The owner's cumulative rule behind it: **early resources matter late only as
sub-items of sub-items, never as direct ingredients.** No raw Fe or Dirt in a Z8
recipe. Zone 1 and 2 are exempt.

## Prestige / warp

- `progress_score = lifetime_credits + buildings × 1000`
- Threshold: **500 000** (the 1-shard anchor)
- `shards = floor(log2(progress_score / 500000)) + 1`, zero below threshold
- Warp keeps **30% XP** (`reset(0.7)`), which is roughly a 12-level drop on the
  RS curve at mid levels
- **Research RESETS on warp** as of v140 — economy spines were buffed to
  compensate. Blueprint-cached buildings keep producing; you cannot build more
  or re-equip modules until re-researched. (CLAUDE.md may still say research
  persists — it is stale on this point.)
- Warp Mastery Tree: 2 branches, 10 nodes, 36 shards to max, purchases persist
- Global multipliers scale with shards, × `2^warp_tier` (a tier every 5 warps)
- Z11+ unlock flags and `cryo_unlocked` persist across warp; only hard reset
  clears them (see `combat_manager.get_progression_flags()`)

## Skill XP

- RuneScape curve, table generated to level 120, **cap 100**
- Milestones at **10 / 25 / 50 / 75 / 100**
- Per-milestone mastery: −5% action duration, total capped at −25%; alt-recipe
  unlock at 50; gold-card cosmetic at 100
- `unlocked_milestones` is derived from xp, never saved — `rebuild_level_silently()`
  rebuilds both it and the level from scratch
