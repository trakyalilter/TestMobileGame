# Session Handoff — 2026-07-15

**Branch:** `MissionFlow` · **Remote:** `origin` (`github.com/trakyalilter/horizonidle-godot`)
**To resume on another machine:** `git pull origin MissionFlow`

This is the "where we are right now" snapshot. For the deep, standing context read `CLAUDE.md`;
this file is the fast catch-up on what changed in the last work block and what's next.

---

## LATEST BLOCK (2026-07-15) — cadence redesign shipped (v138/a/b)

**Owner decisions locked (do NOT relitigate):** first warp at the ZONE-3 boss via a
diegetic BLACK HOLE (not a button) · fleet = soft-role only, siege gates CUT
(**decision #30 RESOLVED: NG+ loop boundaries stay plain clear→Warp**) · bosses
killable offline · demo + mobile PARKED.

| Commit | What |
|---|---|
| `5d879f6` | **v138 THE SINGULARITY** — killing any Z3+ boss tears a black hole open on the Sector Chart; entering IT executes the warp (one confirm modal with the full ledger). Recurs every run, persists until used, collapses on warp. Warp page = spend/monitor only (execute button removed, passive rift status line). `warp_first_revealed` now flips at the first rift (game logic, was zone_6 research) — headless bots earn it naturally. Pre-v138 save migration both ways. Probe 15/15. |
| `f625795` | **v138a fleet soft-role SHIPPED** — glut sink + passive accelerator (+25%/ship, cap +100%), everything already existed (manager/page/combat hook); real work was cost re-sizing for the Z3 cadence (frigate ÷5: Water 8K/Dirt 4K/Steel 800/Circuit 150; destroyer ÷2; cruiser ÷1.5 — playtest-tunable). FLEET_SIEGE_GATES.md → v0.2, siege historical. Probe 20/20. |
| `bbe72bb` | **v138b offline boss kills** — calculate_offline credits boss_kills + cores + clear flags + missions (enemy_defeated capped 25/sweep); `_apply_boss_progression(eid)` extracted from win_fight and shared by both paths (no drift). Phase wardens governed by the existing worst-band no-swap model (refuses under-geared, credits smash-through). Park on the Z3 boss overnight → return to a dead boss AND a Singularity. Probe 13/13. |
| `365b573`+`b732871` | Player-bot fidelity: 4 gear/economy-decision bugs fixed + zone-pacing telemetry. **Mid-game pacing numbers before these are bot-noise; re-measure under the new cadence.** |
| `b5b10a1`/`a312613`/`bcf102d` | Warp Tree Phase 3b COMPLETE — ENG_5 overclock, CMB_3 aux slot, CMB_4 Resonant matrix tier. Zero stubs left except ENG_6 (parked on an owner design call: auto-feed vs manual Core). |

**Design consequence:** the prestige ladder now starts in week one (~3 shards at the
Z3 kill). Loop-2 tuning assumptions (modeled warp states in ng_tune) should be
re-checked against the new cadence before trusting them.

---

## Sync state

- **5 commits pushed this session** (HEAD → `5c8b832`, or `HANDOFF` commit on top):

  | Commit | What |
  |---|---|
  | `f6efd3d` | Balance pass + game-breaker audit (economy, prestige, combat, softlocks) |
  | `1fce48d` | NG+ Loop 1: Corrosion frontier **Z13–Z15** (data + wiring + warp-aware tune) |
  | `d0fa797` | NG+ step 3: map-mod reward system (backend) |
  | `e92507c` | NG+ #36: Z12 Rift Warden warp-aware re-tune (28M/375K → **45M/320K**) |
  | `5c8b832` | NG+ step 3: map-mod selection picker (combat_page UI) |

- **Untracked, deliberately NOT committed:** `steam/new_screenshots/` — Steam store marketing PNGs
  (Jun 30). Binary marketing assets, unrelated to dev. Commit separately if you want them synced.

---

## What shipped this session

### NG+ Loop 1 — Corrosion frontier (Z12–Z15) — COMPLETE, warp-aware tuned
- Multi-phase boss engine live (`phases` + `phase_cut`; non-matching exotic element phase-cut ×0.15).
- Zones `the_verdigris`(13) / `the_dissolution`(14) / `the_caustic_core`(15) + 15 enemies.
- **Final tuned base stats** (effective after ENEMY_COMP warp catch-up in parens):
  - Z12 Rift Warden **45M / 320K**, 2-phase [cryo, corrosion] — probe 6/9 @ ~8.8 min
  - Z13 Verdigris Warden **65M / 300K**, 2-phase [corrosion, cryo] — 9/9 @ 10.2 min
  - Z14 Dissolution Tyrant **68M / 230K**, 3-phase [cryo, corrosion, cryo] — 7/9 @ 10.7 min
  - Z15 Caustic Sovereign **95M / 190K**, 3-phase [corrosion, cryo, corrosion] — 8/9 @ 10.7 min
- Note: base ATK **decreases** per sector (300→230→190K) — correct, because the warp catch-up
  multiplies it more each sector. All no-swap gates hold 0/9. Tuned to *modeled* warp state
  (shards 30/44/58/72, CMB tree nodes) — **real playtest should refine.**
- Clear→Warp→unlock cadence: boss-kill `z{N}_cleared` flag table (combat_manager) →
  `z{N+1}_unlocked` reveal table (warp_manager.execute_warp). Mirrors the proven Z11→Z12 pattern.

### Map-mod system (NG+ step 3) — backend COMPLETE + verified, UI first pass
- `combat_manager.MAP_MODS` (4 mods: hardened_hulls, early_enrage, exotic_dampening, swarm),
  opt-in, cap 3, compounding loot multiplier folded into **all 4 loot surfaces**
  (materials / modules / credits / hack cards). Never-expiring (premium — no FOMO).
- UI picker in `combat_page` (`_build_map_mod_picker`), pre-fight only, gated `z11_unlocked`.
  **Placement/styling (offsets -252/56/-8) is a first pass — refine in-app** (headless can't see render).

### Game-breaker audit — fixed
- Warp infinite-loop (credits snapshot moved AFTER starter grant → no runaway shards).
- Offline over-grant (flat-10s/kill → modeled TTK) + offline reload double-dip (save after offline calc).
- Offline combat now drops hack cards too (online/offline parity).
- Hack-card low-zone farm → frontier-relative taper `clamp(1-0.30*(gap-2), 0.10, 1)`.
- Mitigation-stack unkillable farm → incoming-damage floor `MIN_INCOMING_FRAC = 0.10`.
- Module sell price → scale by `module.zone`, not flat rarity.
- 3 invisible/softlocking research nodes surfaced in `research_page.graphs` allowlist
  (firmware_hacking, neutronium_synthesis, primordial_engineering).
- Economy sell-printers closed: `decode_manifest` credits_output 12500→250; `base_value` model shift
  (materials = crafting inputs, flattened to 1; 20 progression tokens kept at 0).
- `shipwright_2` now requires Advanced Circuit (was Circuit Board); `firmware_hacking` cost right-sized.

---

## Design conclusions locked this session (do NOT relitigate)

- **Exotic damage types share ONE channel.** Cryo / corrosion / plasma all ride the `atk_cryo`
  field + an `exotic_element` tag string — they are NOT separate damage stats. **Never add a
  damage-stat field per new type** (it re-introduces slot pressure + multiplies combat math).
  A new exotic = new tag + new resist key + phase entry, same channel.
- **Loadout = preset-swap, NOT slot-per-type.** Hull weapon slots are type-agnostic; player carries
  **5 loadout presets** (bumped 3→5 in v113 for exactly this). Adding an exotic = one weapon module
  + dedicate one preset. **No new hull slot per damage type, ever.** Preset math: fits through Loop 2
  comfortably, Loop 3 tightly (wall is a 5-phase/5-exotic boss, far off).
- **ENEMY_COMP warp catch-up** (`spawn_enemy`): effective stat = base × (1 + (combat_mult−1)×COMP).
  → NG+ enemy **base atk must decrease per sector** to keep effective atk survivable.
- Tune Z11+/NG+ bosses with **`scripts/sim/ng_tune.gd`** (warp-aware), never z12_tune or boss_gearcheck.

---

## Next up

1. ~~#30 DECISION~~ **RESOLVED 2026-07-15: plain clear+Warp boundaries; siege gates CUT**
   (fleet ships as soft-role only — see LATEST BLOCK above).
2. **#28 Loop 2 — Plasma frontier Z16–Z19:** new plasma exotic (weapon `plasma_lance` guaranteed on
   Z16 first clear + material + `plasma_armaments` research); phase escalation to 3-phase all-three-exotic
   juggle at Z18/Z19; boundary = plain clear+Warp. Warp-aware scaling, low base atk, floats.
   **Re-check ng_tune's modeled warp states against the new Z3-first-warp cadence first.**
   - **New UI task this loop (from the loadout-slots analysis):** *swap legibility*, not slots.
     Name the current phase's element in the combat readout ("PHASE: CORROSION") + let players name
     presets by element (the preset `name` field already exists, unused). This is the real Loop-2 UI work.
3. ~~Pacing re-measure~~ **DONE + v138c compression pass applied** (measured, 3-seed follower):
   Zone 3 entry 11.9d → **9.5d**, destroyer 7.9d → **7.2d**, first Singularity now at the EDGE
   of the 14-day bot horizon (~12.5d when an offline Warmaster kill lands; just past otherwise) —
   plausibly week-one for a real (non-pessimistic-bot) player. Levers used: Z2+Z3 regular module
   drop chance 0.10→0.20 (gear-check unchanged), destroyer plating 10→5. NOTE: m029b AdvCircuit
   5→3 was tried and REVERTED — shipwright_2 effectively spends ~5 (deliberate pairing, see
   mission comment). Remaining binding gate if playtest wants more: the m030fa-f2 Z3-gear band.
4. **#37 map-mod UI polish** (in-app visual pass) · **#29 BigNumber adoption** before Loop 3
   (`docs/BIGNUMBER_PLAN.md`) · ENG_6 Resonant Foundry awaits an owner call (auto-feed vs manual Core).

---

## Verification tooling (scripts/sim/)

`ng_tune.gd` (warp-aware boss tune — **use this for Z11+**), `z12_tune.gd` (no-warp floor only),
`ng_loop_check.gd` (zone/phase/flag wiring), `map_mod_check.gd`, `research_costcheck.gd`,
`hackfarm_check.gd`, `warploop_check.gd`, `module_sell_check.gd`.
Run: `Godot_v4.5.1-stable_win64_console.exe --headless --path . res://scenes/<probe>.tscn`.

## Standing constraints (still in force)
Internal `"credits"` key never renamed (Liras = display only) · commit/push only when asked ·
batteries destructible in real game (sim-only protection OK) · no save reset (migrate) ·
premium paid, zero F2P-isms/FOMO · prestige cadence long.
