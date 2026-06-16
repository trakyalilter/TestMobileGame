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

The danger: if the fleet merely *cancels* the per-warp enemy buff, the player treads water and resents warping. Fix — the **multipliers already beat the enemy buff; the fleet is surplus on top** (never rely on the decaying marginal slot to hold the line).

| per warp | value |
|---|---|
| Enemy combat power | ×1.20 |
| Combat shard-multiplier growth (ship + every fleet ship) | ×1.30 → **+8%/warp floor** |
| Fleet capacity | +1 slot (bonus + the siege tool) |

**Result:** every warp = net stronger (multipliers) + a bigger fleet (new toy) + progress toward the next siege.

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
