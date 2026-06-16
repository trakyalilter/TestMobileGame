# Fleet & Siege Gates — design doc v0.1

**Status:** Spec locked, P1 in scaffolding.
**Player fantasy:** *Your factories outgrow a single hull — so each warp you forge the surplus into a growing battle-fleet that fights beside you, and eventually sieges the planetary gates barring the deep sectors.*

**Loop served:** **Prestige** (warp gains a new reward axis) + **Meta** (fleet roster).
**Subsystems touched** (`docs/audit/SUBSYSTEM_MATRIX.md`): `combat_manager`, `shipyard_manager`, `warp_manager`, `infrastructure_manager` (glut source) + new `fleet_manager`.

**Why it exists:** infrastructure + gathering over-produce basic materials forever (validated glut: Water 215k, Dirt 108k, …). The fleet is the *mandatory milestone sink* — you spend the surplus to build an armada, and the armada is what advances you. It closes the engineer→captain loop: the engineer half's overflow becomes the captain half's force.

---

## Locked decisions

- Anchored to the **warp loop**; reveals **post-first-warp**, alongside Z11.
- **Warp sets the capacity ceiling; glut basics build ships to fill it.**
- Fleet ships **reuse shipyard hulls/loadouts** (build investment scales ship *and* fleet; keeps the build screen central; minimal new systems).
- **Soft role:** joins zone combat as an accelerator (not survival-mandatory).
- **Hard role:** sieges the sector gates past Z11 (chip-down, never binary).
- **Fork A:** new sectors past Z11 stay ship-combat with fleet support; sieges gate the *boundaries*.

---

## The warp math (anti-treadmill)

**Implemented model (v112 — reconciled to code).** The earlier draft of this
section described a per-warp enemy buff (×1.20/warp) that the code never
implemented. The real model:

- **Enemies do NOT scale per warp.** They scale per **zone** only — the static
  zone-steepening curve in `combat_manager` (`_zhp` / `_zatk`, zones 3→10) runs
  HP ×1.7→3.45 and ATK ×1.7→3.1. That curve is identical on every run.
- **Player power rises every warp** via two stacked levers in
  `warp_manager.get_combat_multiplier()`:

  | lever | effect |
  |---|---|
  | Shards (cumulative; earned each warp ≈ `log2(run_progress/500k)+1`) | **+3% combat / shard** |
  | Warp tier (**locked backbone**, do not restructure) | **×2 every 5 warps** = `2^floor(total_warps/5)` |

**Result — net stronger by construction.** Enemies are fixed per zone while the
player's multiplier strictly increases every warp (more shards, plus a ×2 at
each 5-warp tier). Gear and levels reset, but shards + research + 30% XP + the
Warp Mastery Tree persist, so run N+1 reaches any given zone *faster* than run
N. There is no per-warp enemy buff to cancel — the treadmill the old table
feared cannot occur in the current zone roster.

> Note: `get_external_progression_combat_mult()` (a 6×-clamped "enemy
> progression compensation") is currently **uncalled / dead** — enemies are not
> scaled up to match player level/research/warp, which further favors the player
> each warp. If a future build wires it in, it must be re-tuned against this
> table. (Tracked in SANITY_CHECKLIST "Multiplier clamps actually bind".)

**Future (NG+ / siege — not yet built).** The ×1.20/loop enemy buff is the
*forward target* for post-Z11 loop content (Z12+ sectors, siege gates), where
each NG+ loop re-hardens enemies and the fleet + multipliers must out-scale it.
At that point the fleet is the surplus on top (never the decaying marginal slot
holding the line):

| per NG+ loop (future spec) | value |
|---|---|
| Enemy combat power | ×1.20 |
| Combat multiplier growth (ship + every fleet ship) | target ≥ ×1.30 → **+8%/loop floor** |
| Fleet capacity | +1 slot (bonus + the siege tool) |

---

## Capacity — warp is the ceiling, glut is the fill

`capacity = 1 + warps_completed` → **W1=2, W2=3, W3=4, W5=6, W10=11** (an optional warp-mastery node can bump it later).

- Each ship = hull + (later) a saved loadout. Build cost = **glut basics**, e.g. a Fleet Frigate ≈ `40k Water + 20k Dirt + 5k Steel + 2k Circuit + 1 hull` — tuned to soak ~30–60 min of infra output at that depth.
- **Fleet ship ≈ 0.25× the main ship's power** → a full cap-4 fleet ≈ +100% effective power *max*, and the main ship stays the single biggest piece.
- Double gate: warp caps the count (anti-spam / prestige-paced); glut fills it (the sink).

---

## Soft role — joins zone combat

Fleet adds volleys to the existing auto-battle (no new combat instance, no extra input, visible contribution line). **Not survival-mandatory** — multipliers keep normal zones beatable; the fleet accelerates. Prevents the under-built-fleet hard-stuck.

## Hard role — siege gates (Fork A)

- Sectors past Z11 (Z12–16, Z17–21, …) are normal ship-combat with fleet support.
- Between sectors: a **planetary defense gate**, resolved as a **chip-down bar** — each siege wave deals damage = fleet power; a bigger fleet (more warps) chips faster. *Never binary* — partial progress persists.
- Sample first gate: **500k defense HP**; a W3 fleet breaks it in a few waves. Light ship attrition on failed waves (ongoing sink), never total loss.

---

## Failure modes → prevention

1. **Warp feels like running in place** → multipliers tuned above the enemy bump; fleet is surplus; UI sells "net stronger".
2. **Fleet drowns the ship** → fleet uses your loadouts + 0.25× per-ship cap; ship stays biggest.
3. **Hard wall at a gate** → chip-down (always progress) + gentle first siege (teach before test) + fleet not required in normal zones.
4. **Re-glut** → fleet eats glut basics, returns credits / modules / sector access — never bulk materials.
5. **Capacity-decay** (marginal slot stops mattering) → multipliers carry the offset, not the slot.
6. **Gate-type fatigue** → sieges only at sector boundaries; distinct from zone bosses and the warp/Threshold gate.

---

## Persistence

The fleet is **prestige meta-progression** — the roster **persists across warp** (it's the thing that grows *with* warps) and clears only on **hard reset**. Capacity is derived live from warp count, never stored.

---

## Phased build

- **P1 — Sink + roster** *(in progress):* `fleet_manager` + Fleet page, warp-gated capacity, build ships from glut. **No combat yet.** Validate it drains inventory. Reveals post-first-warp.
- **P2 — Soft role:** fleet joins zone combat + the net-positive warp math. Validate warp *feels* stronger.
- **P3 — Hard role:** siege gates past Z11 (chip-down) + the first gate. Validate the wall isn't a wall.
- **P4 — Idle polish:** offline siege resolution, auto-build-to-cap, fleet upgrades, warp-mastery capacity node.

## Deferred
Fork B (fleet-command endgame), persistent planet colonies / 4X, per-ship micro-management.
