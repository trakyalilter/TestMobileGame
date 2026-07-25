# Zone combat baseline — post-3.75x rebase (v142)

Ungated baseline for every transition, measured with:
`z3_funnel.tscn -- --zone=N`

Read: config 9 (Common N) MUST farm all four with no deaths (owner idle rule).
Where it does not, the ZONE is mis-calibrated — gate only after that is fixed.

## Zone 2
```
config                     e1             e2             e3             e4            
1 Rare  N-1     no cores   16*            8*             6D             4             
5 Legend N-1    T1 cores   17*            9*             7*             4             
6 Legend N-1    T2 cores   19*            10*            8*             5*            
7 Legend N-1    T3 cores   23*            12*            8*             5*            
8 Unique N-1    no cores   122*           73*            12*            41*           
9 Common N      no cores   17*            10*            7*             5*            
* = farms (>=5 kills, survived) | D = DIED | [!] = forced sockets (Rare has none in game)
```

## Zone 3
```
config                     e1             e2             e3             e4            
1 Rare  N-1     no cores   8*             5*             2              2             
5 Legend N-1    T1 cores   9*             5*             4              2             
6 Legend N-1    T2 cores   10*            6*             5*             2             
7 Legend N-1    T3 cores   13*            7*             6*             2             
8 Unique N-1    no cores   22*            14*            9*             6*            
9 Common N      no cores   17*            11*            9*             5*            
* = farms (>=5 kills, survived) | D = DIED | [!] = forced sockets (Rare has none in game)
```

## Zone 4
```
config                     e1             e2             e3             e4            
1 Rare  N-1     no cores   2D             2D             2              3D            
5 Legend N-1    T1 cores   4              3              2              4             
6 Legend N-1    T2 cores   5*             2              3              1D            
7 Legend N-1    T3 cores   6*             4              3              5*            
8 Unique N-1    no cores   12*            9*             6*             10*           
9 Common N      no cores   5*             3              2              4             
* = farms (>=5 kills, survived) | D = DIED | [!] = forced sockets (Rare has none in game)
```

## Zone 5
```
config                     e1             e2             e3             e4            
1 Rare  N-1     no cores   1D             1D             2              0D            
5 Legend N-1    T1 cores   4D             3D             3              1D            
6 Legend N-1    T2 cores   7*             0D             3              2D            
7 Legend N-1    T3 cores   8*             6D             4              5D            
8 Unique N-1    no cores   19*            16*            9*             17*           
9 Common N      no cores   9*             6*             4              8D            
* = farms (>=5 kills, survived) | D = DIED | [!] = forced sockets (Rare has none in game)
```

## Zone 6
```
config                     e1             e2             e3             e4            
1 Rare  N-1     no cores   5*             3D             2              4D            
5 Legend N-1    T1 cores   5*             6D             2              5D            
6 Legend N-1    T2 cores   8*             7*             3              7*            
7 Legend N-1    T3 cores   7*             7*             3              7*            
8 Unique N-1    no cores   17*            15*            7*             16*           
9 Common N      no cores   6*             5*             2              5*            
* = farms (>=5 kills, survived) | D = DIED | [!] = forced sockets (Rare has none in game)
```

## Zone 7
```
config                     e1             e2             e3             e4            
1 Rare  N-1     no cores   0D             0D             0D             1             
5 Legend N-1    T1 cores   0D             1D             0D             1             
6 Legend N-1    T2 cores   1D             3D             1D             2             
7 Legend N-1    T3 cores   1D             4              2D             2             
8 Unique N-1    no cores   12*            6*             8*             4             
9 Common N      no cores   6D             3              4              2             
* = farms (>=5 kills, survived) | D = DIED | [!] = forced sockets (Rare has none in game)
```

## Zone 8
```
config                     e1             e2             e3             e4            
1 Rare  N-1     no cores   3D             7*             2D             3             
5 Legend N-1    T1 cores   3D             9*             7D             4             
6 Legend N-1    T2 cores   11*            12*            10*            5*            
7 Legend N-1    T3 cores   12*            11*            9D             5*            
8 Unique N-1    no cores   27*            28*            24*            12*           
9 Common N      no cores   8*             8*             7*             3             
* = farms (>=5 kills, survived) | D = DIED | [!] = forced sockets (Rare has none in game)
```

## Zone 9
```
config                     e1             e2             e3             e4            
1 Rare  N-1     no cores   0D             2D             1D             2             
5 Legend N-1    T1 cores   2D             5*             1D             2D            
6 Legend N-1    T2 cores   1D             1D             4D             2             
7 Legend N-1    T3 cores   7D             6*             5D             3             
8 Unique N-1    no cores   12*            10*            10*            4             
9 Common N      no cores   6*             5*             5*             2             
* = farms (>=5 kills, survived) | D = DIED | [!] = forced sockets (Rare has none in game)
```

## Zone 10
```
config                     e1             e2             e3             e4            
1 Rare  N-1     no cores   3              0D             3D             2             
5 Legend N-1    T1 cores   4              2D             4D             2             
6 Legend N-1    T2 cores   7*             5D             5*             3             
7 Legend N-1    T3 cores   7*             5D             5*             3             
8 Unique N-1    no cores   13*            10*            9*             6*            
9 Common N      no cores   4              3              3              2             
* = farms (>=5 kills, survived) | D = DIED | [!] = forced sockets (Rare has none in game)
```

---

## Diagnosis (2026-07-25)

Config 9 (Common N, the INTENDED answer for zone N) per zone:

| Zone | e1 | e2 | e3 | e4 | verdict |
|---|---|---|---|---|---|
| 2 | 17* | 10* | 7* | 5* | OK (tuned) |
| 3 | 17* | 11* | 9* | 5* | OK (tuned) |
| 4 | 5* | 3 | 2 | 4 | only e1 |
| 5 | 9* | 6* | 4 | 8D | dies on e4 |
| 6 | 6* | 5* | 2 | 5* | e3 fails |
| 7 | 6D | 3 | 4 | 2 | DIES on e1 |
| 8 | 8* | 8* | 7* | 3 | e4 fails |
| 9 | 6* | 5* | 5* | 2 | e4 fails |
| 10 | 4 | 3 | 3 | 2 | nothing farms |

**Clean break at Zone 4** — exactly where hand-tuning stopped. This is ONE
systematic mis-calibration, not seven independent ones: after the 3.75x tier
rebase the authored Z4+ enemy stats are sized against a gear assumption that no
longer holds. Z2/Z3 land 5-17 kills; Z4-Z10 land 2-8 on the same 5-kill bar.

### Prescription (do in this order)

1. **Re-calibrate BASE stats Z4-Z10 first — do NOT gate yet.** Target: config 9
   farms all four (>=5 kills, no deaths). Starting point: enemy `hp` x0.65-0.70
   across e1-e4, plus `atk` x0.75 on the deaths (Z5 e4, Z7 e1). Re-run
   `-- --zone=N` after each zone; expect 1-2 passes each once the curve is right.
2. **Then apply the two-axis gate** (proven on Z2/Z3): e3 gets `sustain` pulse
   (MIN-DPS gate — old gear stalls, never dies: idle-rule safe), e4 gets
   `charge_nuke` (EHP gate, telegraphed). Ramp pulse ~9%->20% and nuke ~2.0x->2.9x
   from Z2 to Z10.
3. **Re-verify** `boss_gearcheck` + `boss_threshold` + the 3-seed funnel.

### Hard-won notes

- A blanket scripted trait pass over Z4-Z10 was tried and REVERTED: it made all
  seven worse because the base calibration underneath was already broken. The
  PATTERN transfers between zones; the NUMBERS do not.
- Z1->Z2 has a tighter tuning window than Z2->Z3 (smaller hull tier-1->2 EHP
  gap), so it oscillates - too hard kills the tier-matched Common, too soft lets
  everything farm. Expect the same narrowness at any small hull step.
- Tune with the REAL consumable model: `auto_repair_20` is tier 2 (reachable at
  Z2->Z3) and fires at 20% HP. Modelling 80% flatters every kit and hides deaths.

---

# RESOLVED (2026-07-25) — steps 1/2/3 applied

## Root cause: the player's power ladder is LUMPY, the enemy's was authored SMOOTH

Hull weapon slots only grow every OTHER tier — 2,2,3,3,4,4,5,5,6,6
(`shipyard_manager.hulls`). Z2->Z3 buys a 3rd weapon slot; Z3->Z4 buys nothing.
So tier-matched Common gear gains no weapon DPS across half the steps, while the
trash ladder stepped smoothly every zone. The break at Zone 4 was that deficit
opening, and it never closed again. The 3.75x rebase preserved the mismatch and
magnified it in absolute terms.

This also explains the residual leaks (below): the leak zones are EXACTLY the
no-slot-gain transitions.

## Step 1 — base calibration (solved, not guessed)

`scenes/zone_calib.tscn` secant-searches enemy EHP until Common-N lands back on
the accepted Z2/Z3 kill curve. Result is one table, not 28 scattered edits:

```gdscript
# combat_manager.gd
const ZONE_TRASH_EHP_CALIB := {4: 0.41, 5: 0.69, 6: 0.48, 7: 0.38, 8: 0.58, 9: 0.48, 10: 0.31}
```

EHP ONLY (`hp` + `max_shield`). `atk` is deliberately untouched — the solver
found Common-N already SURVIVES every zone at full enemy atk, so this was a pure
DPS deficit. Cutting atk too would have defused the e3/e4 gate before it shipped.
BOSSES EXCLUDED: `boss_gearcheck`/`boss_threshold` already passed, so the boss
ladder is calibrated against real gear and must not move. (Re-verified after: Z2-Z10
bosses all still pass; Rare wins, Uncommon/Common lose.)

Plus 7 per-enemy shape fixes where a zone's intra-zone ordering was wrong (the
roster's e3 slot held the zone's authored tank, etc.).

### The fast-attacker lethality archetype

All three Common-N deaths were sub-2s `atk_interval` enemies — `z7_shard_swarm`
(0.8), `z5_alien_probe` (1.2), `z4_glacial_drone` (1.8). They out-tick the 10s
consumable cooldown, so kit procs can't answer them. **Any new enemy under ~2s
interval needs its `atk` checked against the idle rule.**

## Step 2 — the two-axis e3/e4 gate

e1/e2 stay open to every config (front salvage, materials only). The MODULE-hunter
cells gate: **e3 = `sustain` pulse** (min-DPS gate; under-geared kits stall but
never die, so idle players lose time not a ship), **e4 = `charge_nuke`** (EHP gate,
telegraphed). Consistent mechanic, ramped numbers — the player learns one rule
("e3 regenerates, bring DPS; e4 spikes, bring EHP") and it transfers across zones.

### Three trait-engine gotchas found while wiring this

1. **`sustain` pulse heals `enemy_max_shield * pct` — it is SHIELD-ONLY.** On a
   shieldless enemy it is a silent no-op. `z4_frost_hulk` had no shield, so Z4 e3
   read *identically* pre- and post-gate until this was caught. It was given a
   shield. **Never attach a pulse to a shieldless enemy.**
2. **`charge_nuke.every_n` counts SWINGS, not seconds.** A flat `every_n: 4` made
   `z5_alien_probe` (1.2s) spike every 4.8s while `z9_quarantine_mech` (3.5s)
   spiked every 14s — the fast one killed tier-matched Common outright. `every_n`
   is now tuned per `atk_interval` to land a ~12-14s TIME cadence.
3. **The pulse subtracts a near-CONSTANT number of kills from every config**,
   rather than scaling with their DPS. It lowers the floor more than it
   discriminates: at Z4, `pct 0.14` gated carried Rare (5->2) but also pushed
   Common under the farm bar (7->4). Gate strength must be set against the
   *margin* Common has, not against the config you want to stop.

## Final state — config 9 (Common N) farms all four, every zone

| Zone | e1 | e2 | e3 | e4 |
|---|---|---|---|---|
| 4 | 13* | 9* | 6* | 11* |
| 5 | 12* | 9* | 8* | 12* |
| 6 | 14* | 12* | 7* | 11* |
| 7 | 15* | 10* | 10* | 6* |
| 8 | 12* | 12* | 10* | 6* |
| 9 | 12* | 11* | 11* | 8* |
| 10 | 14* | 11* | 7* | 7* |

(Was: only e1 at Z4; deaths at Z5/Z7; nothing farming at Z10.)

## STILL OPEN — the even-zone leak, and why it is not a trait problem

Carried Rare-(N-1) still farms some e3/e4 at **Z4, Z6, Z8, Z10** — precisely the
no-slot-gain hull transitions. At those steps the measured gap between fresh
Common-N and carried Rare-(N-1) is only ~1.0-1.4x (at Z10 e4 they are *equal*:
7 kills each). **No threshold trait can separate kits that are 1.4x apart while
leaving the winner above the farm bar** — see gotcha 3. Crafting the new zone's
commons is therefore a *dominated choice* at those four transitions.

That is an economy problem (tier step vs. rarity multiplier), not a combat-trait
problem, and it needs an owner decision before more tuning:

- **(a) Accept it** — every other zone forces a gear refresh, the alternating
  ones are a breather. Cheapest; arguably a fine cadence.
- **(b) Widen the tier step** relative to the rarity multiplier so Common-N beats
  Rare-(N-1) everywhere. Touches the whole gear economy.
- **(c) Give hulls a per-tier damage/EHP coefficient** so a tier gain always pays
  even when the slot count does not. Most targeted fix for the actual root cause.

Recommend **(c)** — it fixes the lumpiness at its source instead of papering over
it per zone, and it is one coefficient rather than a re-audit of every module.

## Probe caveat

`z3_funnel` runs TRIALS=3 and carries +/-1-2 kills of noise, with occasional
spurious deaths. Z2 e4 and Z3 e3 read 5*/9* in three separate runs this session
and 4/8D in the final one on **byte-identical** Z2/Z3 code. Do not chase a
single-run regression on an untouched zone — re-run before believing it.
