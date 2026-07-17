# Session Handoff — 2026-07-17

---

## LATEST BLOCK (2026-07-17 late) — Boss Overhaul SHIPPED (v139d)

**Trait engine + rollout Z1–Z11** (7 data-driven traits, taught one per zone, combos at
Z9/Z10, soft tutorial flavors at Z1/Z2) + **the Rare gate, owner-corrected twice**:
- Hard ×0.25 sub-Rare multiplier: tried, REJECTED ("do not break the math").
- God-roll allowance: REJECTED ("i ain't said god rolled uncommon should overcome").
- **Final mechanism: Uncommon affixes 1→0** (v101 revert in generate_module_drop) —
  rarity stat ranges were already disjoint (U caps ×1.20, R floors ×1.25); the single
  affix was the only bridge. Tiers separate in the ITEM numbers; combat math pure.
  Save-compat: old affixed Uncommons keep baked stats, new drops roll affixless.
- **Commit matrix (bgc_commit.txt, TRIALS=9):** Uncommon 0/9 at EVERY boss (deep losses
  L75–99%), Rare 6–9/9 at Z2–Z10 with TTK 3.0–6.7min in envelope. gearcheck rule now
  fractional: C AND U ≤10%, Rare-or-better ≥60%.
- Pre-fight card + atlas show trait chips + NEEDS RARE GEAR; bot boss bar = Rare;
  m030d speaks the rule. Lethality lesson on record: kits make survival near-infinite,
  so boss-side pressure = spikes/enrage/volatile, never HP stretch.
- REMAINING: Z11+ warp-aware pass (ng_tune) vs the 5–10min envelope; funnel [FUN]
  re-measure (rift timing under Rare gate + board farming, projected day 4–6 @1h/day);
  watch Z3/Z9 Rare cells (wobble 45–60%, L columns 9/9 so progression never blocks).

---

## (earlier same day) — Fun-audit instrumentation + measured verdict (v139c)

**Owner directive: "before Loop 2, check the game generally — is it fun, will players be
bored, do we need new systems."** Built boredom-proxy instrumentation into player_bot
(all ACTIVE-time domain, offline-immune): [FUN][DENSITY] debounced context switches/h,
[FUN][MIX] daily gather/process/combat share, [FUN][STREAK] resumable same-target sits,
[FUN][DESERT] active spans with zero novelty events, [FUN][WARPCURVE] v138 cadence
re-measure. Run: 5×14-day runs (follower s11/22/33, efficient, overnighter) →
`sim_out/players/fun_20260717_082835/`.

**MEASURED FINDINGS (the load-bearing ones):**
1. **v138's "first warp in week one" FAILS for casual budgets.** Follower (1h/day): best
   seed opens the rift on DAY 14 (active-hour 16), NO warp executes in 14 days, 2 of 3
   seeds never open it. Overnighter (0.3h/day + heavy offline): walled at m026/m029, never
   near Z3. Only ≥2h/day players see a week-one warp. Loop-2's modeled warp states are
   moot until this is addressed.
2. **The m029–m030 band (Z2→Z3) is simultaneously the WALL, the DESERT, and the density
   collapse.** Deserts 2.2–8.7 ACTIVE hours anchored after `hull:destroyer` through the
   AdvCircuit chain; walls: m030d "farming rare/uncommon explosive gear for Monolith"
   (55h active!), m030g/m026 `blk=item need=Circuit` (research item costs), overnighter
   m026 at 72h. Context-switch density flatlines to 0/h from ~d7 in every run.
3. **The captain fantasy starves mid-funnel:** d3–d7 MIX runs ~30/60/0–10 g/p/c —
   processing-dominated days with near-zero combat while the circuit chain grinds.
4. **Follower runs log ZERO `building:` novelty events** — the mission chain never forces
   infrastructure in that band, so a mission-follower can silently skip an entire pillar
   (efficient archetype builds auto_excavator d8 on its own initiative).

**P3 per-boss mechanics (owner-approved, "wisely"):** design table shipped at
`docs/design/P3_BOSS_MECHANICS.md` — 3 new data-driven traits (Shield Pulse / Reactive
Armor / Volley) + existing Enrage, taught Z3→Z10 one-per-zone then combined, all
pre-fight-solvable, invariants: Uncommon still clears mandatory bosses, TTK ≤ +20%,
offline prices traits conservatively. IMPLEMENT AFTER the m029–m030 band surgery (the
Z3 enrage number interacts with the same band).

**Next up (proposed):** m029–m030 band surgery (AdvCircuit chain length, m030d gear-RNG
gate, Circuit research item costs, early-income sanity vs the v139 repricing, offline
chain-advance for heavy-offline profiles) → re-run this matrix → P3 build → then Loop 2.

---

# (previous) Session Handoff — 2026-07-16

**Branch:** `MissionFlow` · **Remote:** `origin` (`github.com/trakyalilter/horizonidle-godot`)
**To resume on another machine:** `git pull origin MissionFlow`

This is the "where we are right now" snapshot. For the deep, standing context read `CLAUDE.md`;
this file is the fast catch-up on what changed in the last work block and what's next.

---

## LATEST BLOCK (2026-07-16) — Bounty/Quest split (v139)

**Owner decisions locked:** bounty board split **zone-by-zone as tabs** (unlocked zones only;
paid refresh targets the ACTIVE tab) · **NO fleet dispatch** — fleet stays a passive post-first-warp
combat helper (already shipped in v138, verified) · **quest/bounty role split: bounties own COMBAT,
quests own SKILLING** · NG+ T11–15 tiers included.

- **Bounty (`bounty_manager` + `bounty_page`):** per-zone 4-card boards — 2 hunts + 1 boss
  bounty (qty 1–2, offline-completable by v138b design) + 1 elite duel. **v139b owner rule:
  contracts target ONLY the module-hunters — e3/e4 (last two trash; weapons-pool + defense-pool
  carriers) + boss; e1/e2 (material-farm lane) never get contracts.** The 2 hunts are
  deterministic (one per hunter → every board offers a weapon-farm AND a defense-farm target);
  elites roll hunters only, never bosses. Programmatic zone-tab strip (defaults to frontier).
  Natural 8h refresh regenerates ALL boards + clears reroll heat (ticks offline); paid refresh
  is per-zone at `diff×5000×2^uses`. DELIVERY contracts removed from generation (legacy actives
  still claim/refund). Hunt payout `xp×qty×10.0×diff^1.6`.
  Drop-rule NOTE (verified, no change needed): module drops are already gated by
  `enemy_is_front_salvage` → `drops_modules` (v114/v120) — Z2–Z10 e1/e2 = materials only,
  Z1 AND Z11+ exempt (everyone drops). The e1/e2 `module_drop_chance` data values are INERT
  (flag zeroes them at roll time) — don't be misled by them like this session was.
- **Quest (`quest_manager`):** hunt ("Sweep") quests REMOVED (legacy ones on old saves still
  track/claim via the kept hook). NEW **Supply Orders** — hand in CRAFTED goods (Steel/Circuit/
  AdvCircuit/Superalloy, T2–T15), tracked like stockpiles but **consumed at claim** (stock
  re-verified at claim; un-completes if spent). Gather table moved quest-side + REPRICED (old
  static column paid printer sums — T6 "own 3K Steel"=1M; now a small trickle, T1 2K → T15 42M).
  Reroll gains the same escalating heat (×2/use, cools 1 step per claim).
- **Save migration:** old flat bounty `available` pool discarded (ephemeral RNG), ACTIVE
  contracts incl. pre-v139 deliveries preserved + claimable. No save version bump needed
  (defensive loaders both sides). Quest boards carry legacy hunts until claimed.
- **Texts:** m027b mission + bounty/quest coach marks rewritten (old text claimed bounties were
  "background income" — false without dispatch — and referenced delivery/timers that no longer exist).
- **Verified:** `scripts/sim/bounty_check.gd` (scene `bounty_check.tscn`) — composition/zone-lock/
  elite-no-boss, escalation+natural-reset, lazy-seed, migration, supply consume+stock-guard,
  reroll heat: **ALL PASS**. Full headless boot clean. Reward ladder printed per tier (T1 1–2K …
  T11 200–650M pre-mults — in family with direct combat drops at era).
- **UI polish pending (in-app):** tab strip styling/placement is a first programmatic pass
  (like the map-mod picker) — eyeball both in a real render.
- **NEW STANDING RULE — no emojis in player-facing text** (owner, 2026-07-16). Game-wide sweep
  removed ~60 pictographs (sidebar prefixes, contract/log/mastery/modal icons → plain labels).
  Kept: functional typography only (→ arrows, ▲▼▸ indicators, ✕ close, ◆◇ pips, ◈ shard symbol).
  Codified in CLAUDE.md gotchas. Gotcha: star_map strips the hazard prefix for map labels —
  now `.replace("HAZARD: ", "")` (3 sites), keep in sync if the prefix wording changes.

---

## PREVIOUS BLOCK (2026-07-15) — cadence redesign shipped (v138/a/b)

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
