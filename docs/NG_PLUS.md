# NG+ — Recursion Depth (endgame past Z11) — design doc v0.1

**Status:** Spec LOCKED. **Shipped & sim-verified** (`scripts/sim/phase_gate_spike.gd`): **P1** (multi-phase engine — HP→phase bands, per-element gate, telegraph; Z11 byte-identical), **P2-core** (in-fight loadout-preset swap + typed-exotic gating), and the **first P3 tier — Z12 "The Rift" / Corrosion**: `corrosion_blaster` weapon (`exotic_element: corrosion`), Rift Warden 2-phase boss (Cryo→Corrosion), Z12 zone + 4 trash, `corrosion_armaments` research, and the **clear-gate unlock wiring** (clear Z11 boss → flag → next Warp reveals Z12; hard-reset clears it). BigNumber is **harden-and-defer, NOT blocking** the planned ladder (`docs/BIGNUMBER_PLAN.md`).

**Remaining:** P2 — Threshold Relic slot + master-key drop + cross-warp persist + the combat-page swap UI button (UI not headless-verifiable). P3 — `corrosion_plating` resist module + acid-DoT enemy attack (the defensive axis) + per-element weapon UI coloring; then WT3–5 (Thermal/Radiation/Graviton) as content drops. P4 — Fleet siege gates. P5 — sim-tune the HP/cut/scaling curves.
**Player fantasy:** *Each Warp you breach a deeper hostile frontier — master a new exotic element, beat its multi-phase Warden in a hands-on gauntlet, then claim the key that turns that wall into your farm.*

**Loop served:** **Prestige** (the D30+ warp tail) + **Combat** (the gates) + **Meta** (per-element resist/weapon crafting).
**Subsystems touched** (`docs/audit/SUBSYSTEM_MATRIX.md`): `combat_manager` (zones, multi-phase bosses, hardened/resist), `shipyard_manager` (relic slot, loadout presets, resist modules, element weapons), `warp_manager` (gating), `fleet_manager` (siege gates), `research_manager` + `processing_manager` (element craftables). Precursor: a BigNumber number type.

**Why it exists:** the warp loop is already a *soft* NG+ (reset + ×2^tier mults + faster re-climb), but post-Z11 there is no content — D30 caps at "warp and re-run the same 11 zones." NG+ gives the prestige arc an authored, escalating frontier: a new zone + element per tier, gated by a hands-on boss, rewarded with permanent power.

---

## Pacing — the frontier extends, the re-climb compresses

Clear-gated, NOT warp-count-gated: **clear the current frontier boss → Warp → the next zone + its content unlock.** The player paces NG+ by conquering the edge; the re-climb shrinks every warp while the frontier is where the hours go.

| | Time to clear Z10 | Frontier adds |
|---|---|---|
| Climb 0 (no warp) | ~20h | — |
| After Warp 1 (+ fleet) | ~15h | **Z11: +8–10h** |
| After Warp 2 | ~8–10h | Z12: +8–10h |
| … | compresses toward a floor | each new zone ≈ +8–10h |

Enemy scaling per NG+ tier (×over the Z1–10 baseline), **to be sim-tuned** with the existing TTK/parity harness, never hand-tuned:

| Tier | ~Enemy HP/ATK × | aligns with |
|---|---|---|
| WT1 (Z11) | ×2.5 | first warp |
| WT2 (Z12) | ×6 | ~warp 2–4 |
| WT3 (Z13) | ×15 | warp-tier ×4 era |
| WT4 (Z14) | ×40 | warp-tier ×8 |
| WT5 (Z15) | ×100 | warp-tier ×16 |

---

## The element ladder — one new element per tier

Each NG+ tier is a **content drop built around a new element** (the Melvor poison↔poison-resistance model in space dress). A tier ships: a themed **zone**, a new **enemy attack element** (you gear **resistance** to survive — a new *defensive* build axis the game currently lacks), a new **resistance module type**, new **element weapons + craftables**, and new enemy resists (offensive puzzle).

| Tier | Zone | Element | Enemy threat | You counter with |
|---|---|---|---|---|
| WT1 | Z11 "The Threshold" | **Cryo** | warp-hardened (offense gate, ×0.02) | Cryo weapons (the free first-Warp reward) — *built* |
| WT2 | Z12 | **Corrosion** | acid DoT — shreds DEF over the fight | Corrosion Plating (resist) + advantaged dmg |
| WT3 | Z13 | **Thermal** | burst + heat ramp | Thermal Shielding |
| WT4 | Z14 | **Radiation** | stacking DoT, partly ignores shields | Rad Shielding |
| WT5 | Z15 | **Graviton** | slows fire rate / disables | Inertial Dampener |

Counters are **gear axes you craft** (resist modules + element weapons), not key-hunts — so progression is build-optimization, not "find the mandatory key." **Z11/Cryo is the one binary gate** (the must-warp teaching moment); every element after it is graded resistance.

---

## The gate — cumulative multi-phase boss

The Z(10+N) boss has **N cumulative phases**, each hardened against all-but-one element (Cryo → +Corrosion → +Thermal → …). A phase is an HP threshold (`boss_hp / N` each); at the threshold the boss swaps which element breaches it.

- **Per-phase cut ≈ ×0.15** for off-element weapons (soft — off-element still chips ~15%, so it's "lead with the right element + a spread," not "solo each phase"). **Z11 stays the lone ×0.02 binary.**
- **Telegraphed:** UI calls each phase ("⚠ PHASE 2 — CORROSION-HARDENED").
- Phase count can **exceed weapon-slot capacity** (a Dreadnought holds ~5–6 weapons). That ceiling is broken by the active swap (below) — which is *why* the gate is active.

### Active first clear → master key → idle farm (the idle-safe trick)

1. **First clear is ACTIVE.** Because phases outnumber slots, the player **swaps loadout presets mid-fight** to match the current phase. Skill = phase recognition + preset swap. **Free, unlimited retries; no penalty.**
   - **Swap mechanic = loadout PRESETS, tap-to-swap, instant, free anytime.** (Uses the existing `save_loadout_preset`.) Mobile-safe — tap preset 1/2/3, never drag-re-equip under pressure. The challenge is recognition/timing, not fiddling.
2. **Boss drops a master key — the "Threshold Relic."** Grants resistance to **all** of that boss's damage types regardless of loadout. Goes in a **dedicated Relic slot** (one at a time, never competes with weapon/armor slots). **Persists across Warp** (cleared only on hard reset, like `cryo_unlocked` / the fleet).
3. **With the Relic equipped, the boss becomes idle-farmable** → farm it for the special materials that gear you for the *next* tier's boss. (This is the chase-drop source: boss → Relic + next-tier farm mats.)

This bounds the active requirement to a single climactic fight per tier (Monster-Hunter "first hunt is the skill-gate, then farm the parts"); the bulk of play stays idle. NG+ is explicitly the **"active push" layer over the idle base.**

---

## Siege gate — the Fleet hard role (one per tier)

Between clearing a frontier boss and the next zone unlocking sits a **planetary-defense siege gate**, resolved as a **chip-down HP bar**: each siege wave deals damage = current fleet power; a bigger fleet (more warps → more capacity → more glut spent) chips faster. **Never binary** — partial progress persists; failed waves cost light ship attrition (an ongoing glut sink). This is where the Fleet (built from material surplus, `+25%`/ship soft-role combat already wired) finally *gates* progression.

Starting gate HP: WT1 **500K**, WT2 **5M**, WT3 **50M**, WT4 **500M**, WT5 **5B**.

---

## Failure modes → prevention

1. **Active gate filters the pure-idle player** → free unlimited retries, fully telegraphed phases, generous post-Relic idle farm so the active spike is brief. NG+ is *named* as the active-push endgame; the idle base game (Z1–10 + warp farm) never requires it.
2. **Mobile fumbling mid-fight** → preset **tap**-swap only, never drag-re-equip.
3. **Gate-type fatigue** ("you need the specific key") → counters are *gear axes you craft* (resist modules + element weapons), not mandatory new keys; Z11 is the only binary gate.
4. **Number overflow** → BigNumber is a hard precursor (WT5 enemy HP ~2.2B, `lifetime_credits` into the trillions over the multi-day arc → crosses 2^53 within a few tiers).
5. **Bosses feel same-y** → cumulative phases + a new element + a new zone skin per tier keep each gate distinct.
6. **Master key trivializes the boss** → intended; the Relic *is* the farm-enabler reward. Resist modules are climb tools for that tier, not lasting investments.

---

## Locked decisions

- Clear-gated frontier pacing (clear boss → Warp → next zone). Re-climb compresses; frontier adds ~8–10h/zone.
- One element per NG+ tier (themed zone + enemy element + resist module + element weapon + craftables). Resistance is a new defensive build axis.
- **Cumulative multi-phase bosses**; per-phase soft cut ≈ ×0.15; **Z11/Cryo is the lone ×0.02 binary gate**.
- **First clear is active** via loadout-PRESET tap-swap (a scoped, knowing exception to the auto-battler "no in-fight inputs" rule, justified because it's one-time per tier and the Relic restores idle play). Free retries.
- **Master key = "Threshold Relic"**: all-resist to its boss, dedicated **Relic slot** (one at a time), **persists across Warp**, enables idle farm.
- **One siege gate (Fleet chip-down) per tier.**
- **BigNumber is a hard precursor** — no NG+ content ships numbers past 2^53 until it lands.

---

## Dependencies & phased build

- **P0 — BigNumber adoption** *(precursor — RESOLVED as harden-and-defer, see `docs/BIGNUMBER_PLAN.md`):* Phase-1 hardening (the `is_finite` format guard) is done; the full mantissa/exponent rewrite is deferred behind a **1e15 live-value tripwire**, because the planned 6-tier ladder (WT5 enemy HP ~2.2B) stays comfortably under 2^53. **No longer blocks NG+ at the planned scale** — revisit only if a tier's live values would cross the tripwire.
- **P1 — NG+ framework:** World-Tier/element data; clear-gated zone reveal on (frontier-clear + warp); cumulative multi-phase boss (per-phase hardened element + ×0.15 soft cut); phase telegraph UI.
- **P2 — Active-gate kit:** in-fight loadout-preset tap-swap; the **Relic slot**; master-key drop / equip / cross-warp persistence; the "boss now idle-farmable" state.
- **P3 — Element content (per tier, content cadence):** resist module + element weapon + craftables + themed zone + enemies. One element = one drop.
- **P4 — Siege gates:** Fleet chip-down wall, one per tier.
- **P5 — Tuning:** sim the gate difficulty, enemy-scaling curve, and pacing against the v106 TTK band.

## Open / deferred
- **Swap timing rule:** free anytime (recommended — skill = recognition) vs phase-transition-only vs short cooldown.
- **Resist-Cryo reversal tier:** should a late tier resist *Cryo* to pull players off the crutch? (Build depth vs undercutting the Cryo reward.)
- **Enemy-scaling curve:** the ×2.5→×100 table is a starting point; sim-tune.
- **BigNumber scope:** full mantissa/exponent vs a pragmatic float64 + display-formatting that only *delays* the ceiling (cheaper, finite). Decide before writing the BigNumber plan.
