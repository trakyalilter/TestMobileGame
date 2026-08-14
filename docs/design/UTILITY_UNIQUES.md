# P5 — Utility Uniques (engine · sensor · battery)

> **The slot you never thought about becomes the reason your build works.**

You have opened the Ship Designer a hundred times and never once made a decision
in the engine bay. It holds the one engine you own, it grants a number you have
never felt, and you close the panel. Then the Sovereign Prism drops a Phase
Drive, and suddenly the question is not "which gun" — it is whether you are
flying a ship that *cannot be hit*, a ship that *always finds the part you need*,
or a ship that *turns spare power into damage*.

---

## Which loop, which subsystems

**Meta loop** (loadout/build), feeding core (combat) and prestige (a utility
unique is exactly the thing you spend a Salvage Vault slot on).

Touches `shipyard_manager` (27 module defs), `combat_manager` (boss `rare_loot`
rows + two new resolution hooks), and nothing else. No new currency, no new
system, no UI work — these render through the existing module card.

---

## The problem, measured

Every zone from 2 to 10 ships six uniques: weapon, kinetic, energy, missile,
armor, shield. **Engine, sensor and battery have no unique tier at any zone** —
`unique_engine`, `unique_sensor` and `unique_battery` appear zero times in the
codebase.

That is not an oversight of coverage, it is a symptom. Those three slots have
nothing worth making unique, because each is a single scalar:

| slot | its entire contribution | ladder Z1 → Z10 |
|---|---|---|
| engine | `eva` | 4 → 15 |
| sensor | `enemy_drop_mult` + `module_drop_mult` | 0.20/0.40 → 0.35/0.65 |
| battery | `energy_capacity` | 30 → 60369 |

**The engine slot is worth ~2.8% dodge, and has been at every tier for the whole
game.** The dodge formula (`combat_manager.gd:3406`) is

```
dodge = eva / (eva + 150 × (1 + enemy_accuracy/100)),  capped 0.75
```

At Z5 that is `9 / (9 + 315)` = **2.8%**. At Z10, `15 / (15 + 525)` = **2.8%**.
The ladder rises exactly as fast as boss accuracy, so nine tiers of engine
upgrades move the number not at all. Stack every other evasion source in the game
— Topaz gems (+10–18) and the Colossus set (+12) — and Z10 still only reaches
~7%. Evasion is live (v145 deliberately kept it when it deleted `accuracy`), but
nothing in the game supplies enough of it to matter.

So P5 is not "add 27 more stat sticks". A unique battery with a bigger number is
a **dominated pickup** the moment your power fits, and a unique engine with a
bigger `eva` is dominated on arrival. The spec's own word is build-**altering**:
these three slots must grant *mechanics*, not magnitudes.

---

## Mechanic — one axis per slot, and the unique is the only source

### ENGINE — Phase Drive: evasion becomes a real defensive layer

The unique engine is the **only** item in the game that supplies enough `eva` to
move the dodge formula. It changes the defensive question from "how much damage
do I absorb" to "how much do I simply not take", which is a genuinely different
build — it beats big slow hits (charge_nuke, volatile) and loses to sustained
chip damage (corrosive_field), so it is a counter-pick, not an upgrade.

No new code: `eva` is aggregated and capped already (`MAX_EVASION`, and the 0.75
dodge cap).

`eva` sized for ~20% dodge against its own zone's boss — `0.25 × 150 × (1 + acc/100)`:

| zone | boss acc | unique `eva` | dodge vs own boss |
|---|---|---|---|
| Z2 | 45 | 54 | 20% |
| Z3 | 65 | 62 | 20% |
| Z4 | 85 | 69 | 20% |
| Z5 | 110 | 79 | 20% |
| Z6 | 140 | 90 | 20% |
| Z7 | 170 | 101 | 20% |
| Z8 | 200 | 113 | 20% |
| Z9 | 230 | 124 | 20% |
| Z10 | 250 | 131 | 20% |

Flat 20% is deliberate: it keeps the item relevant at its own tier without
letting a carried-forward Z10 drive trivialise Z2 (where 131 eva reads ~38%, good
but not the 75% cap).

### SENSOR — Predictive Array: a pity timer on module drops

Every **N** kills without a Rare+ module, the next module drop is guaranteed
Rare+. The counter resets on any Rare+ from any source.

This is the itemization answer to the acquisition problem measured in v175/v176:
a weak-type Rare is ~0.2%/kill, about **470 kills**. Combined with the v176 loot
filter (which the board now honours too), a Predictive Array turns the hunt from
a lottery into a schedule. Idle games live on that conversion — a visible,
bounded worst case is worth more than a better average.

| zone | N (kills to guarantee) |
|---|---|
| Z2–Z4 | 40 |
| Z5–Z7 | 30 |
| Z8–Z10 | 20 |

New code: a kill counter on `combat_manager` and a check in
`_roll_one_module_drop` that floors the rarity roll. Small, and it sits in the
one function all drops already route through.

### BATTERY — Overcharge Cell: unspent power becomes damage

`+1% weapon damage per 5% of battery capacity left unspent`, capped by tier.
**Only pays while every consumer slot is filled** — see the failure mode below.

This gives the v110 battery-only energy model a second dimension. Power stops
being a pass/fail constraint and becomes a dial: over-provision batteries and run
lighter modules for damage, or fill the ship with heavy ordnance and take none.
That is a real allocation decision on a slot that currently has one right answer.

| zone | cap |
|---|---|
| Z2–Z4 | +10% |
| Z5–Z7 | +18% |
| Z8–Z10 | +25% |

New code: one term in `recalc_stats` reading `energy_capacity - energy_used`.

---

## Acquisition

Same as every existing unique: **3% each on the zone boss's `rare_loot`**, three
new rows per boss, Z2–Z10. Z1 stays unique-free (the v146 ruling deleted the Z1
set because a free tutorial-zone unique let players walk past Zone 2).

Module shape matches the existing uniques exactly: `rarity: 4`, `is_unique: true`,
`cost: {}` (never craftable), `zone: N`.

---

## Failure modes

**Overcharge rewards stripping your ship.** Empty slots draw no power, so naive
"unspent capacity" pays you for flying half-equipped — a degenerate loop the
player would find immediately and resent losing. **Prevented by requiring every
consumer slot filled for the bonus to apply at all.** The bonus then measures
genuine over-provisioning (more/better batteries) rather than absence.

**The pity timer trivialises farming.** Mitigated three ways: the floor is Rare,
not Legendary; the counter resets on any Rare+ from any source, so it is a floor
and never a bonus; and it is earned from a 3% boss drop in the zone it applies
to. Watch the interaction with the v176 bounty filter — both push the same
direction, and together they may overshoot. This is the first number to measure.

**Phase Drive makes an unkillable ship.** Capped twice already: `MAX_EVASION` on
aggregation and 0.75 on the dodge roll. Verify `MAX_EVASION` is above the Z10
value (131) or the top of the ladder silently flattens.

**Carried through a Warp, these are strong.** The Salvage Vault (v176) means a
Phase Drive can anchor several runs. The research gate still applies — a Z10
unique cannot be equipped until Zone 10 is re-researched — so it accelerates the
late run, not the early one. Intended, but worth watching once both ship.

**Set-bonus inflation.** Declined below.

---

## Guard

`utility_unique_check`, asserting against the real code paths:

1. all 27 modules exist with `rarity: 4`, `is_unique: true`, empty `cost`
2. every Z2–Z10 boss `rare_loot` carries its three rows at 3%
3. Phase Drive dodge measured through the real formula lands 18–22% vs its own
   zone's boss, and `MAX_EVASION` does not clip the Z10 value
4. Predictive Array: N+1 kills with no Rare+ yields a Rare+ (drive the real
   `_roll_one_module_drop`, not a copy), and the counter resets on a natural Rare+
5. Overcharge pays 0 with any consumer slot empty, and pays the capped value at
   full over-provision
6. no utility unique carries a `set_id` (see below)

---

## Declined

- **Giving them the zone `set_id`.** Thematically obvious and quietly harmful:
  every trinity set triggers at 3 pieces, so adding three more collectible pieces
  to each pool makes every existing set bonus easier to complete. That is a
  power-creep change to nine tuned set bonuses disguised as a content addition.
  These stay standalone.
- **A unique battery that just holds more.** Dominated the moment your power
  fits — the exact non-decision this feature exists to remove.
- **Raising the base engine `eva` ladder instead.** Tempting, since the slot is
  near-dead. But that buffs every ship for free and re-tunes nine zones of
  incoming damage. The unique is the bounded version of the same idea; if it
  measures well, promoting some of it to the base ladder is a separate ruling
  with its own measurement.
- **A fourth axis (hull/consumable uniques).** Those slots already have identity.
