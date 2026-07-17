# Zone Pacing Curve — the standing spec (owner-locked 2026-07-17)

**Design target player: 1 hour/day.** Zone-to-zone transition time follows a geometric
curve — early zones flow inside a session, late zones are multi-day commitments. The unit
drifts from hours to days on purpose (owner's framing: "z1→z2 0.5h, z2→z3 1h, …
z9→z10 a few days").

| Transition | Target (calendar @1h/day) | Cumulative | Beat it lands |
|---|---|---|---|
| Z1→Z2 | 0.5h — same session | day 1 | onboarding flow |
| Z2→Z3 | ~1h active | day 2 | **first warp day 2–4 (D7-safe)** |
| Z3→Z4 | ~1 day | day 3–4 | post-warp momentum |
| Z4→Z5 | ~1.5 days | ~day 5–6 | week 1 ends at Z5 |
| Z5→Z6 | ~2 days | week 2 | |
| Z6→Z7 | ~2.5 days | week 2 | |
| Z7→Z8 | ~3 days | week 3 | |
| Z8→Z9 | ~3.5 days | week 3–4 | |
| Z9→Z10 | ~4 days | Z10 boss ≈ week 4 | endgame gate |

Rules:
- **Transitions only ever lengthen** down the ladder (monotone). A later transition
  measuring SHORTER than an earlier one is a bug in either the curve or the measure.
- **Measured in the [FUN] instrumentation** (`player_bot` — zone novelty events in
  active-time domain + calendar days). Any pacing claim cites a run, not vibes.
- Warp multipliers are part of the budget: later transitions assume the player warps on
  cadence. If a transition only fits the curve WITH warping, that is working as intended
  (prestige is the engine).
- Bigger budgets compress the calendar naturally (2h/day ≈ half the days). The curve is
  the FLOOR experience; never tune such that 1h/day misses a beat window.

## v139c band surgery (first application of the curve)

Measured (fun_20260717 matrix): Z2→Z3 ran 10+ ACTIVE hours / 12+ calendar days — 10× over
target; no follower warped in 14 days. Applied:
1. `m029b` Craft AdvCircuit **5 → 2** (full teach chain intact, 3 fewer deep-chain crafts).
2. `zone_3_access` items **Steel 200→120, Circuit 60→25** (effective bill ~45% down).
3. `zone_4_access` items **Steel 600→300, Ti 350→150, Circuit 200→80** (~55% down;
   Z3→Z4 target is ~1 day, measured 48h active).
4. `m030d` text now routes players to the **zone bounty board** — hunt contracts pay a
   guaranteed Rare-floor module on claim: the deterministic bridge over the uncommon+
   drop-RNG gear check (was 55h of farming).
5. Bot fidelity: `player_like` policy now works the zone board while gear-farming
   (accept matching hunt + claim completed contracts) — as a real player would.

Acceptance for the re-run: no m030d/overdue walls in the band, first rift ≤ ~5 active
hours, Z2→Z3 novelty gap ≈ 1–2.5h, band deserts < 2h. Z4+ transitions get measured after
this lands and stretched TO the curve where too fast/slow.

## Measured results (2026-07-17, follower seed 11, 5 iterations)

| Milestone | Pre-surgery | Post (all fixes) |
|---|---|---|
| Destroyer hull | act 8.3h | **act 5.0h** |
| zone_3_access | act 11.4–12.5h | **act 8.8h** |
| First rift (Z3 boss) | act 16.0h / day 14 | **act 13.7h / day 12** |

Landed along the way (each verified by re-run):
- m030d bounty-bridge works (55h gear-RNG wall → ~3.3h of board-driven farming).
- **DO-NOT-TRIM lesson:** m029b's 5 AdvCircuit crafts are load-bearing (stock+chain
  warm-up for Shipwright II) — a 2-craft variant re-opened the historical m030 wall.
- **Bills ARE the XP curve:** trimming early material bills starves processing/gathering
  levels that gate later recipes — check level gates when cutting costs.
- AdvCircuit chain lightened ~40% (Ge: Si 10→6/Cu 5→3; craft: SC 2→1, Ag 2→1) — the
  6-stream chain can't amortize offline in a single-active-task game; active cost is real.
- Two BOT bugs fixed that inflated all prior pacing data: slot-pressure sells vendored
  chase-chain intermediates (advc frozen 90h while credits rose 1.9M at ~1/unit), and
  nested telemetry dirs were silently unwritable.

**Remaining gap vs curve (rift target ~3–5h active): the two designed boss gear-checks.**
Monolith ≈ 3.3h + Warmaster (incl. Z3 craft chain m030fa/fb/f1) ≈ 4.5h. This is now an
OWNER DECISION, not a trim: (a) soften the Uncommon+ bars (weakens the gear-check teach),
(b) richer early bounty pity (e.g. first zone-board claim per window guarantees the
boss-WEAK-TYPE module), or (c) accept rift ≈ day 3–4 at 1h/day (still inside week one)
and keep the checks as-is. Note: the bot's overdue-wall detector fires on 48h SIM time —
at 1h/day a healthy 3-active-hour mission spans 3 days and false-positives; detector
should move to active-time basis.
