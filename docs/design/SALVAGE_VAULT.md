# Salvage Vault — carrying gear through the Warp

> **The reset takes your empire. It doesn't take your rifle.**

You warp, and everything goes: the buildings, the research, the Liras, the
fleet. The Vault is the one exception you get to choose. Three modules — the
gun you finally got the right roll on, the plate that carried you through the
Glacier Belt — survive the collapse and are sitting in the hangar when you come
out the other side. Every warp after that, you get to bring one more.

---

## Which loop, which subsystems

**Prestige loop.** This is the "each run is faster" promise made concrete for
the one part of the game that currently ignores it.

Touches `warp_manager` (snapshot + restore + capacity), `shipyard_manager`
(`reset()` currently wipes the fleet; save shape gains the vault), and the warp
confirmation UI in `warp_page`. No new manager, no new currency.

---

## The problem this solves

`shipyard_manager.reset()` — called from `execute_warp()` at
`warp_manager.gd:202` — does this:

```gdscript
module_inventory = {}
loadout = {}
custom_modules = {}
```

Every module you own, gone, every warp. `warp_manager`'s own comment says it
plainly: *"The fleet does NOT survive, and never did."*

That would be fine if re-acquiring gear were quick. It is not. Measured this
session (v175):

| what | measurement |
|---|---|
| Rare weak-type weapon drop rate | `drop_chance × 11.5% rarity × ~1-of-7 pool weight` ≈ **0.2%/kill** |
| kills per weak-type Rare | **~470** |
| gear-detour time on a single boss beat | **1.3–4.6h** (player_bot telemetry, seeds 4/11/27) |
| m030f2 / m030i dwell | **30–100h**, identical across baseline and post-fix runs |

So the single most time-expensive activity in the mid-game resets to zero on
every warp. The stated design cadence is **a few warps before mid/endgame**, in
the AdVenture Capitalist angel-investor shape — reset often, each run faster.
Multiplying a 470-kill hunt by the number of warps is the opposite of that. The
carry-overs that do exist (30% XP retention, Warp Mastery Tree, permanent sector
unlocks, REC_1 blueprint cache) all skip the fleet entirely.

This is a **design gap, not a balance problem.** No drop-rate number fixes it:
raise the rate enough to survive being re-farmed N times and the first run
becomes trivial. The missing system is a carry-over.

---

## Mechanic

At the warp confirmation, before the world resets, the player picks up to **K**
modules from inventory + loadout. Those survive; everything else is wiped as
today. Carried modules land in `module_inventory` post-reset, **unequipped**.

**K is automatic and permanent — it is not a purchase.** The angel-investor feel
is that every reset makes you permanently stronger without having to spend
anything to collect it.

| warp # | K |
|---|---|
| 1 | 3 |
| 2 | 4 |
| 3 | 5 |
| 4 | 6 |
| 5 | 7 |
| 6+ | 8 (cap) |

`K = clampi(2 + total_warps, 3, 8)`, evaluated after `total_warps += 1` at
`warp_manager.gd:148`.

Starting values, chosen to be tunable rather than right: 3 is enough for a
weapon, a plate and a shield — one coherent core, not a build. 8 caps below the
6-weapon Battlecruiser loadout, so a maxed vault still cannot field a complete
end-tier ship on run 2.

### The interesting decision is TIER, not slot

The obvious worry is that the choice is fake because weapons always win. In
practice the live decision is **how far ahead to bet**, because of the research
gate below: a Zone-6 Legendary is dead weight for hours until you re-research
Zone 6, while a Zone-3 gun is usable almost immediately and carries the opening.
Carry high and the run starts slow and ends strong; carry mid and it starts
fast. That is a real allocation call every warp, and it gets richer as K grows.

I considered restricting the vault to at most 2 weapons to force slot diversity
and **declined it**: the weapon hunt is precisely the grind this exists to cut,
so taxing it re-imposes the problem the feature is for.

---

## The power-creep guard already exists

Carried gear cannot skip progression, because equipping already enforces
research and that survives untouched:

- `can_equip_module()` (`shipyard_manager.gd:6189`) rejects a module whose
  `research_req` is not unlocked.
- For dropped instances it *also* checks the base module's requirement
  (`shipyard_manager.gd:6192`) — and `generate_module_drop` copies
  `research_req` onto every `custom_*` instance (`shipyard_manager.gd:5661`).
- Warp resets research (v140 owner call), and `warp_manager.gd:196` already
  states the consequence: *"post-warp you must re-research before re-equipping."*

So a vaulted Zone-6 gun sits in the hangar until Zone 6 research is back — by
which point the player is at Zone 6 anyway. **The vault removes the re-farming,
not the progression.** No new gating system is needed, and none should be added.

---

## Architecture — mirror REC_1

`execute_warp()` already does this exact shape for buildings: snapshot a subset
before the wipe, restore it after (`warp_manager.gd:159-181`). The Vault is the
fleet's REC_1 and should read like it.

1. **Before** `GameState.shipyard_manager.reset(decay)` (`warp_manager.gd:202`),
   snapshot the chosen ids together with their `custom_modules` entries — a
   dropped module is only meaningful alongside its rolled stats and affixes.
2. Let `reset()` wipe as it does today. **Do not special-case `reset()`** — it is
   also the new-game path, and a new game must keep starting with nothing.
3. **After** the reset, restore into `module_inventory` + `custom_modules`.
   Leave `loadout` empty; the player re-equips as research returns, which is
   also what makes the tier bet legible.

Ordering is load-bearing in both directions, exactly as the bounty settlement
note at `warp_manager.gd:214` warns: snapshot before the wipe or there is
nothing to read, restore after or the wipe eats it.

---

## Failure modes

**"Run 2 has no gear loop at all."** Partly intended — that is the angel-reset
reward, and the frontier is where engagement should move. Bounded by the cap (8
of a 16-slot Battlecruiser) and by the research gate delaying high-tier picks.
Watch for the early zones becoming *fully* inert; the cap is the first number to
cut if so.

**Choice paralysis at the warp button.** Picking 3 of ~40 modules under a
one-way door is stressful. Mitigation: pre-select the highest-tier equipped
module per slot type as the default, so confirming without thinking is a
reasonable outcome. And there is no FOMO — it happens every warp, not once.

**Regret / one-way door.** The warp confirm must show exactly what is being
carried and what is being lost, and be cancellable up to the confirm.

**Save bloat.** Carried `custom_modules` persist across runs, so a long-lived
save accumulates rolled instances. Capped at 8 — negligible.

**Hard reset must clear it.** `hard_reset` and warp reset are different paths and
the matrix already logs hard reset missing prestige state. The vault must be
cleared on hard reset or a "new game" starts with an endgame rifle.

---

## Save + migration

Vault contents live in `warp_manager`'s save shape (it owns prestige state and
already survives warp). Bump `save_game` version and add a `migrate_save` arm
seeding an empty vault for existing saves. An existing save must load with an
empty vault and full capacity for its `total_warps`.

---

## Guard

New probe `scenes/vault_carry_check.tscn`, asserting against the real
`execute_warp()` (not a reimplementation of it):

1. Vaulted ids exist in `module_inventory` after a warp; non-vaulted ids do not.
2. A carried instance keeps its rolled stats and affixes — restoring the id
   without its `custom_modules` entry silently downgrades it to base stats.
3. A carried module above current research **cannot** be equipped, and can once
   that tech is re-unlocked. This is the power-creep guard; it needs a test that
   has been seen to fail.
4. `K` matches the table at `total_warps` 1..7.
5. `hard_reset()` empties the vault.
6. Selecting more than `K` is rejected.

Must assert `GameState.sim_mode` before running — it exercises warp and reset,
and `hard_reset()` deletes the real save.

---

## Declined

- **Tree node for capacity.** The Warp Mastery Tree is locked at 10 nodes / 36
  shards with 6 mechanic nodes already unbuilt. Automatic capacity keeps the
  angel-reset feel (you get it for existing, not for shopping) and stays out of
  a locked spec. A tree node as a *later multiplier* remains open.
- **Carrying the loadout equipped.** Free power on a fresh corvette, and it
  hides the research gate that makes the tier bet interesting.
- **Carrying blueprints/recipes instead of items.** That is research carry-over
  by another name, which v140 deliberately removed.
- **Raising drop rates instead.** Does not survive being re-farmed N times
  without trivialising run 1. Tuning cannot reach this target.
