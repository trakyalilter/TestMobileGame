# Staged damage-type introduction — Zones 1–3

**Player fantasy:** *"I understand my ship."* A new player should finish Zone 1
knowing exactly what their weapon does, having made zero loadout decisions — and
should meet their first real choice only once they have something to choose
between.

**Loop:** core (combat) + onboarding. **Owner-confirmed 2026-08-09.**

---

## The problem

Zone 1 currently teaches the **entire** damage triangle and the 3-preset loadout
system before the player has crafted anything. Two of its three trash enemies
demand weapons a new player does not have:

| Enemy | Damage | resist_k | resist_e | resist_x |
|---|---|---|---|---|
| `z1_lunar_drone` | kinetic | **-0.30** | 0.00 | 0.37 |
| `z1_scrap_collector` | kinetic | 0.00 | 0.37 | **-0.30** |
| `z1_survey_probe` | energy | 0.00 | **-0.30** | 0.37 |

And the tutorial chain makes that explicit — `m017b` sends you to kill the Survey
Probe with a Pulse Laser, `m017d` to kill the Scrap Collector with a
Micro-Missile, ending with *"Kinetic / Energy / Explosive now live in Loadouts
1 / 2 / 3"*. That is three weapon types, three ammo lines and a preset system, in
the first zone.

## The design

One new decision per zone.

| | Zone 1 · Lunar Orbit | Zone 2 · Asteroid Belt | Zone 3 · Mars Debris |
|---|---|---|---|
| **Types live** | kinetic | kinetic + energy | all three |
| **Trash** | 1 | 2 | 3 |
| **Teaches** | the loop | the first choice | the triangle |
| **resist_e / resist_x** | **0.0 / 0.0** | e live, x = 0.0 | all live |
| **Craftable** | kinetic weapon + ammo | + energy | + explosive |
| **Missions** | kinetic only | + energy | + explosive, + presets |

Zone 1's job is **gather → craft → equip**, not combat variety. Combat is the
smallest part of it. If Zone 1 combat starts to feel like the content, the zone
is too long.

## Changes

### Enemies

**Delete outright** (owner call — later zones already carry enough roster):
- `z1_scrap_collector`
- `z1_survey_probe`

Zone 1 becomes `z1_lunar_drone` + `z1_boss_architect`.

**Zone 2 drops to 2 trash.** It currently has three (`z2_pirate_skiff`,
`z2_silicate_golem`, `z2_ore_hauler`). Keep the kinetic-weak skiff and whichever
of the other two is retuned energy-weak; delete the third.

**Zone 3 is already correct** at 3 trash + boss.

### Resistances

Zone 1 enemies and boss: `resist_e = 0.0`, `resist_x = 0.0`. Not "weak" —
**neutral**. Those types do not exist yet, so the player must never see a
resist or weakness message naming one.

Zone 2: `resist_x = 0.0` on the whole roster; kinetic and energy behave normally.

### Nothing is orphaned by the deletions

Checked every material the two doomed enemies drop:

| Material | Still sourced by |
|---|---|
| Fe, Res1, MiteChitin, Cu, **NavData** | `z1_lunar_drone` (survives) |
| SalvagedAlloy, DamagedCircuitry | `z1_boss_architect` (survives) |
| Si | 2 buildings + 1 recipe (never enemy-only) |

**Si is fine — I was wrong to flag it.** `centrifuge_dirt` (Dirt 5 + Water 5 →
Fe 5 + **Si 3**) is level 1 behind `basic_engineering`, i.e. available on the
Engineering page from the first minute. My original note said "Si is not
gatherable", which was literally true and completely useless: I grepped one file
and reported a gap without tracing the chain.

### The tutorial chain — this is the real work

`m017a`–`m017d` currently teach all three types in Zone 1. They must be split
across the zones they now belong to:

| Mission | Now | Becomes |
|---|---|---|
| `m017` kill Lunar Drone (kinetic) | Z1 | **stays Z1** |
| `m017a` craft Pulse Laser | Z1 | **moves to Z2** |
| `m017b` kill Survey Probe (energy) | Z1 | **Z2**, retarget to the energy enemy |
| `m017c` craft Micro-Missile | Z1 | **moves to Z3** |
| `m017d` kill Scrap Collector (explosive) | Z1 | **Z3**, retarget to a Z3 enemy |

The *"Loadouts 1 / 2 / 3 = Kinetic / Energy / Explosive"* lesson moves to **Zone
3**, because that is the first moment all three exist and a preset is worth
having. Teaching it in Zone 1 teaches a system with one input.

### Gating

- Energy weapon + ammo recipes → behind Zone 2 research
- Explosive weapon + ammo recipes → behind Zone 3 research
- Zone 1 loot tables must not roll energy or explosive modules
- Zone 1 boss must be **kinetic-solvable**, no resist wall

### Boss ramp

Bosses ramp on the same schedule as their zones, rather than spiking ahead:

- **Z1 boss** — plain kinetic. No mechanic, no resist.
- **Z2 boss** — first boss that *resists* something. Teaches "bring the right tool."
- **Z3 boss** — first that wants a mixed loadout, solvable pre-fight.

## Failure modes

**"Zone 1 is boring."** One enemy, one weapon, no choice. It survives only
because Zone 1's content is the gather/craft loop — combat is a garnish. Guard:
if Z1 combat time-to-boss grows past a few minutes, cut it further rather than
adding a second enemy.

**"The triangle never gets taught."** With no resists in Z1, the lesson lands
entirely in Z2. Guard: Z2's energy enemy must *visibly* resist kinetic, and the
combat log must say so — the first RESISTED message is the lesson.

**"A dead weapon type in the player's hands."** If explosive recipes unlock at
Z3 but no Z3 enemy is explosive-weak, the new type is a dominated choice on
arrival. Guard: `zone_gate_check` and the resist table — every newly unlocked
type needs a same-zone enemy that is weak to it.

**Save compatibility.** Deleting enemy ids breaks saves that reference them
(`current_enemy_id`, `boss_kills`, mission targets). Needs a migration that
clears any dangling reference, and a `combat_manager.reset()` path check.

## Guards

- `zone_gate_check` — unchanged rules still apply from Z3 onward.
- `boss_gearcheck` — Z1/Z2 rows must stay OK with a kinetic-only / kinetic+energy
  kit respectively; today they assume all three types are available.
- `mission_routing_check` — will catch the retargeted `m017b`/`m017d`.
- **New check needed:** assert no Zone 1 or Zone 2 enemy carries a non-zero
  resist for a type that is not yet unlocked, and that no Zone 1 loot table can
  roll an energy or explosive module.


---

## Shipped 2026-08-09

| Change | Detail |
|---|---|
| Enemies deleted | `z1_scrap_collector`, `z1_survey_probe`, `z2_ore_hauler` |
| Zone 1 | 1 trash + boss, `resist_e`/`resist_x` = 0, boss now weak to **kinetic** |
| Zone 2 | 2 trash + boss, `resist_x` = 0, boss weak to **energy** |
| Zone 3 | unchanged — full triangle |
| Drop pools | Z1 rolls kinetic only; Z2 drops missile modules |
| Gating | `z1_energy`→`zone_2_access`, `z1_missile`/`z2_missile`→`zone_3_access`, `CellT1`→Z2, `MissileT1`→Z3 |
| Tutorial | `m017`→`m018` direct; energy leg behind `m027`; explosive leg behind `m030e` |
| Retargets | `m017b` → Silicate Golem (Z2), `m017d` → Scavenger Mech (Z3) |

### Two things the implementation turned up

**Deleting `z2_ore_hauler` silently removed Zone 2's tier gate.**
`enemy_is_front_salvage` was a flat `idx < 2` — with only two trash left, *both*
counted as front salvage and nothing in the zone walled an under-geared player.
Fixed by deriving the cutoff from the roster: everything except the **last** trash
is front salvage. That is identical to `idx < 2` on a three-trash zone and
correct on a two-trash one, so no other zone moved.

**A save parked mid-fight against a deleted enemy would have ghosted.**
`load_save_data` handed `spawn_enemy()` whatever id the save held — a retired id
leaves `in_combat` true with no enemy, which never ticks and blocks repairs. It
now ejects cleanly with a log line.

### Guard

`scenes/type_unlock_check.tscn` — asserts no zone resists or drops a type it has
not unlocked, that weapons and their ammo gate on the same zone, and that no
mission targets a retired enemy. Verified by reinstating Zone 1's explosive
resist and explosive drop: reports both, by name.
