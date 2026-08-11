# Session Handoff — 2026-08-08

---

## LATEST BLOCK (2026-08-08) — AUDIT, SAVE GUARD, NG+ GEAR LADDER (v174)

28 commits, `b900608..027a7eb`. Started as a full-build audit, turned into closing
what it found.

### Read these first

- **`.claude/skills/rpg-game-design/`** — general RPG design craft, not this game's
  rules. Load it for any balance question. Its procedure (measure → distrust the
  instrument → classify → rule with a number → guard it) is what the rest of this
  block was produced with.
- **`docs/BALANCE_REFERENCE.md`** — measured curves: boss HP by zone, rarity table,
  breach factors, depth floor, prestige formula, XP milestones. Quote from here.
- **`docs/RULINGS_2026-08-08.md`** — the three balance rulings, each with the
  measurement and the wrong turns. More useful than the conclusions.
- **`docs/audit/AUDIT_2026-08-08.md`** — the 48-finding audit this all came from.

### ⚠ A sim harness deleted the developer's save. It is fixed. Do not undo it.

`scripts/sim/*` scenes drive the LIVE `GameState`, and `hard_reset()` ends by
deleting `savegame.json`, `.bak`, `.tmp` AND `.corrupt.json`. Writing
`ngplus_reset_check` destroyed a real playthrough and every backup —
unrecoverable. `boss_gearcheck` alone calls `hard_reset()` ~540 times per run.

`GameState.sim_mode` now auto-detects a launch into any `.tscn` that is not the
project's `main_scene` and gates **both** `save_game()` and that delete loop. It
prints `[SIM] sim_mode ON` at boot. New probes that reset or warp should assert
it before touching state.

### Shipped

**Save / reset integrity**
- `hard_reset()` was missing 6 NG+ flags, so a New Game left Sectors 13–15
  enterable while Z11/Z12 were correctly locked. The list is now derived from
  `combat_manager.get_progression_flags()` (zone unlock flags + clear-flag table +
  relic `_earned` keys), so a Loop 2 sector cannot go missing from it.
- `Skill.rebuild_level_silently()` now rebuilds level AND `unlocked_milestones`
  from scratch. Warping kept milestone bonuses for levels you no longer had; it
  also fixed a second bug where loading a lower save over a live skill never
  lowered the level.

**Combat feedback**
- Exotic damage stopped calling itself kinetic: `CRY`/`COR` tags, cryo WEAK SPOT
  via `resist_cryo`, corrosion enemies labelled `COR`, weapon battery splits the
  two exotics (they share `atk_cryo` and both read as "cryo" before).

**NG+ gear ladder — the big one**
- Z11–Z15 each now have their own **weapon pair** (Lance/Etcher) and **armour +
  shield**, on four new research techs, dropped by their own boss. Before this,
  the exotic channel had two weapons for five sectors and NG+ had no defence at
  all — so a Z15 boss one-shot a fully-geared hull, and Z15 was a seven-hour fight.
- Boss corrections the measurements forced: Z10 ATK ×1.20, Z11 ATK 280K→105K and
  HP 20M→15M, Z12 ATK 256K→205K and HP 45M→40M, Z15 ATK 152K→304K, `cryo_lance`
  10K→20K. Z11 and Z15 were both **inverted** — Z11 hit harder than Z12, and the
  Z15 capstone hit softest of the whole loop.
- **`boss_gearcheck`: 15/15 honour the gear rule at 21 trials, 0 violations.** No
  zone passes on borrowed gear any more.

**Guards repaired** — five of six failing suite scenes were broken probes, not a
broken game: a stale property that hung the scene to timeout, an assertion that
could never pass, two hand-copied lists that drifted from the code they mirrored,
and English literals compared against a Turkish build. Also new:
`ngplus_reset_check`, `milestone_reset_check`, `damage_label_check`,
`orders_i18n_check`.

**Orders rename finished** — the whole 8-section HOW TO PLAY briefing had zero
rows in `strings.csv` and shipped English under Turkish, and still said "Quests".

### Two lessons worth more than the fixes

1. **Nine trials cannot resolve a ~60% win rate.** Z11's rows swung 0/9 → 2/9 →
   6/9 → 3/9 across *identical* settings, and a 1.3× buff appeared to make things
   worse. Several rounds were spent tuning that noise before running `--trials=21`
   showed the true rates. Use 21 near any threshold.
2. **Distrust a bespoke instrument before the game.** A custom DPS probe reported
   5.6 *billion* DPS (it counted the whole health bar when a fight ended), then
   double-counted boss regen, then gave contradictory results between identical
   runs. The only honest measure of time-to-kill was killing the boss and reading
   the clock. The long-standing committed harness was right the whole time.

### Next up

1. **Owner ruling needed — the zone gate.** `zone_gate_check` reports 9 cells where
   maxed zone-N gear can slow-farm zone N+1 trash (~75% slower, but it works). Read
   as intended Melvor-style bootstrap, or should a wall exist? The probe currently
   expects a wall and is red because of it.
2. **Owner ruling — DECISION #30**, the NG+ loop boundary (Fleet Siege Gate vs
   clear+Warp), then **Loop 2 — Plasma frontier Z16–Z19**.
3. **~16 audit minors open.** Best of them: `load_game` only migrates when `ver < 3`
   while saves write version 4 (harmless today, silently skips the next migration);
   hard reset misses three one-time intro flags; Cryo tooltips describe a downside
   that has no mechanical backing.
4. **174 untracked one-shot probe files** in `scripts/sim` and `scenes` — swept for
   references and nothing tracked cites them, but they are not in git history so
   deleting is irreversible. Needs an explicit go-ahead.

### Closed by measurement, not by fixing

- **Wood tonnage gap: refuted.** All d5+ materials carry Wood; Z9/Z10 loadouts
  demand 85K–221K of it. The long-standing concern was wrong.
- **coach_overlay error flood: did not reproduce.** Zero occurrences all session.

---


---

## 2026-08-02 — STATION PROCUREMENT S1 (v162, Demand Engine)

**Spec:** `docs/design/DEMAND_ENGINE.md` · **Audit that motivated it:** `docs/audit/ECONOMY_AUDIT_2026-08-02.md`
(headline findings: demand is refit-shaped; supply orders covered 4 goods in 15 tiers; matrix
cores have NO faucet anywhere — separate decision, still open; sell path removal is TOTAL, owner-confirmed).

**Owner decisions locked this block:** sell removal total (UI gone) · demand engine before
Loop 2 · ENGINEER_SHARE 0.35 (sim arbitrates vs 0.30) · rewards Liras only (three-currency).

### What shipped (S1 — engine + board)

- **`element_db.gd` (+v162 section):** `PROCUREMENT_FAMILY_ORDER` (7 families),
  `PROCUREMENT_FAMILIES` (eligibility = has infra producer; drills/combat-fed/zone-alloys
  excluded, ordnance T1-T3 exception), `PROCUREMENT_UNIT_PRICE` (~40 goods, FIXED per good —
  income scales linearly with capacity), helpers `get_procurement_family` / `get_procurement_unit_price`.
- **`quest_manager.gd` (+v162 engine):** per-family demand pools — cap =
  `PROC_ERA_INCOME_PER_H[frontier] × ENGINEER_SHARE / online_families × 24h`, refill
  continuous via LAZY unix-timestamp settle (`_settle_pools`) so **offline refill is the same
  code path, no tick anywhere**; boards `proc_boards{family:[3 cards]}`, qty = 30 min of NET
  `get_total_resource_rates()` (feeder goods your factories eat are correctly not asked for),
  reward = qty × unit price; `claim_procurement` = pool-gate FIRST (blocks lose nothing) →
  v139c stock re-verify/consume → same warp/recursion payout mults as quests → pool -= BASE
  reward → instant card replacement at current rates. Legacy `supply` actives still claim
  (table + generator kept for that path); **new supply rolls retired** — Standing Orders is
  stockpile-only now. Save keys `proc_boards/proc_pools/proc_pool_ts`, defensive both sides,
  NO version bump (bounty v139 precedent). `reset()` clears all three (warp + hard reset).
- **`quest_page.gd` (rewritten) + `quest_card.gd` (2-line patch):** programmatic tab strip
  (bounty_page pattern) — STANDING ORDERS + 7 family tabs, dimmed dormant tabs with
  build-a-line tooltip, pool meter (bar + "STATION DEMAND: x / y"), reroll/claim-all stay
  legacy-tab-only, procurement cards restyle "infrastructure". Strip HIDDEN until the first
  family is online — day-one UX unchanged. One-time reveal notification
  (`game_settings["procurement_intro_seen"]`).
- **Probe:** `scripts/sim/supply_board_check.gd` + `scenes/supply_board_check.tscn` —
  8 sections: static data (producer/price/no-alloy per good), eligibility, qty/reward shape,
  pool math (born-full + lazy 12h refill ≈ cap/2), claim tri-path, legacy claim, reset regen,
  **ceiling-L/h price ladder print (the tuning table — retune from THIS, not vibes)**.
- **Loc:** 13 rows appended to `localization/strings.csv` (en/tr, TR is first-pass — owner
  should eyeball); reused existing keys `STANDING ORDERS` (MEVCUT SİPARİŞLER) + `ORDNANCE`.

### Verification state — ⚠ NOT DONE YET

- ✅ Isolated parse gate (Godot 4.5.1 Linux `--check-only`, autoload false-positives
  filtered): all 5 scripts 0 errors. One real catch fixed (`:=` inference through autoload).
- ⛔ **FULL HEADLESS BOOT not run** (needs the Windows binary on this machine):
  `Godot_v4.5.1-stable_win64_console.exe --headless --quit-after 18 --path .` then grep
  `SCRIPT ERROR|not declared|Nonexistent function|Cannot infer`.
- ⛔ **Probe not run:**
  `Godot_v4.5.1-stable_win64_console.exe --headless --path . res://scenes/supply_board_check.tscn`
  — expect `[PROC] ALL PASS` + the ladder print.
- ⛔ Funnel gates (before calling S1 done, spec §F): 3-seed follower re-run — engineer income
  share ≈ 35%±5 at saturated states, **first-warp shards stay 15–17**, deserts don't regress.
  `player_like` still has NO procurement policy (add gear-contract-style SCOPED claiming —
  the unscoped version hijacked material farms once, HANDOFF 2026-07-21 on record).

### Next steps (spec §G)

S2 ordnance pass (3 T4 ammo plants + T4 rows join the family) → S3 convoys (2.5×, 8h dock,
cooldown-not-expiry) → S4 **E5 Reclamation Foundry** (with sell gone it is the only valve for
UNDEMANDED surplus — numbers ready in ENDGAME_FACTORY_TIER.md §H) → S5 polish (fanfare, CLAIM
ALL on family tabs, pool meter styling — eyeball the programmatic strip in a real render,
same caveat as the map-mod picker).

### Tuning knobs (all in one place)

`ENGINEER_SHARE` 0.35 · `PROC_ORDER_MINUTES` 30 · `PROC_POOL_HOURS` 24 ·
`PROC_CARDS_PER_FAMILY` 3 · `PROC_ERA_INCOME_PER_H` (Z1-Z3 extrapolated, Z11+ ×2/sector
placeholder — re-anchor when NG+ income is measured) · `PROCUREMENT_UNIT_PRICE` (retune from
the probe's ladder print).

---

# (previous) Session Handoff — 2026-07-21

---

## 2026-07-21 — Boss Systems UI + per-boss traits + BEAT 2 industrialization (v139f/g)

**Commits:** `ebe6b95` (boss skills UI+identity) · `e65db04` (Beat 2 arc) · fidelity commit on top.

- **v139f Boss Systems UI:** persistent trait-chip strip under the enemy panel (live state:
  cannon pips, enrage armed/hot, plating mult, grid resists, pulse countdown, volatile
  critical), phase-tinted enemy HP bar + enrage notch, hover explainers on every chip
  (strip + pre-fight card; ONE vocabulary via `UITheme.trait_info_for`), intel-modal
  "Boss Systems" section, defeat flight-recorder (SHORT factual cause only), activation
  drama (PHASE/ENRAGE center banners, colored bar flashes, chip pops). **OWNER RULE
  (memory-saved): no unsolicited explainer text on auto surfaces — advice lives in
  opt-in hover/modal ONLY.** First-encounter toast was built then REMOVED for this.
  Map-mod picker PARKED (combat_page call commented; backend intact) — appeared
  post-warp with zero introduction.
- **v139g trait redistribution (owner: "each boss is new flavor"):** Z4 pulse→SIPHON
  debut (pct 0.04 — 0.08 collapsed mission-real Rare 8/9→1/9, A/B-proven), Z5
  enrage→NANITE debut (12% regen, band-neutral vs old enrage), Z7 takes pulse-for-real.
  All 9 traits in play; `trait_ui_check` (40 asserts) guards Z3-Z8 distinctness.
  `boss_threshold` TRIALS 5→9 (5-trial cells swung ±2 on identical code — old
  "all-Rare wins Z1-Z5" was noise). Gearcheck Z1 "FAIL" = tier-1-hull artifact
  (mission path fights it on frigate: 8-9/9 Rare) — do NOT re-alarm on it.
- **⚠ OPEN OWNER DECISION:** 9-trial mission-real band Z3–Z6 reads ~30-50% all-Rare
  (bar 60%; Legendary covers 6-8/9) — Legendary is quietly the real mission-path gate,
  contradicting the locked "Rare suffices" rule. Options: boss-side hp trims (~10-15%,
  aligns with owner's ≤d6 first-warp target) vs accept+reword. Un-decided this session.
- **BEAT 2 (owner blessed the infra plan; Factorio-style exclusives locked for Beat 3):**
  missions m029a6-a9 at the measured desert — build Biomass Plant → research Industrial
  Automation → commission Electronics Assembler (1500 kW) → accumulate 100 Circuits.
  Funnel-tuned ×4 iterations: industrial_automation 9K/{Cir 25, Steel 80}; assembler
  {Cir 40, SalvageData 12}; accumulate 250→100 (hidden Resin chain). **Bot fidelity:**
  `player_like` now PROTECTS owned production-building feed syms from surplus sells +
  steers income to scarcest feed under a 900s buffer (protection alone sufficed).
  **Result: `building:` events in ALL follower seeds (was zero), deserts 8.7h→2-3.5h,
  rift d10/12/12 (baseline d8-11), 2 seeds at deepest-ever m030i.** Remaining band
  walls: m030g Circuit bill, m031 (pre-existing; passive Circuit supply now chips at
  m030g for real players). Next infra steps (family→demand engine): supply-order
  re-sizing (refining multiples) → ammo-plant pass (ordnance) → Beat 3 factory-only
  intermediates (fabrication; NO hand recipe — owner locked) → Foundation Kit on warp
  (parked). Goal: multiples of EVERY family via rate-based demand.
- **Turkish loc:** Warp/Atlama drift fixed (7 rows); ~60 new en/tr rows this session;
  CSV 0 dups. `trait_ui_check` + funnel probe green; full boots clean throughout.

---

# (previous) Session Handoff — 2026-07-17

## PREVIOUS BLOCK (2026-07-17 late) — Boss Overhaul SHIPPED (v139d)

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
- **VERIFIED WITH BOTS 3 WAYS (all green):** gearcheck matrix (U 0/9 everywhere, R 6–9/9,
  TTK in envelope) + boss_threshold at MISSION-REAL hulls (all-Uncommon 0/5 everywhere,
  all-Rare wins Z1–Z5, partial mixes fail → the FULL-set demand is real; Z6 2/5 on the
  −1-tier hull, Legendary covers) + 3-seed follower funnel: **first warp day 8–11 at
  1h/day** (was d12–14/never), all seeds reach m030i (deepest ever), chain flows Z3→Z4
  under the full Rare gate. Offline model now prices ALL traits conservatively (8daed67).
  Bot fidelity shipped: gear farms follow board contracts (gear-scoped — the unscoped
  version hijacked material farms, reverted).
- REMAINING: Z11+ warp-aware pass (ng_tune) vs the 5–10min envelope; watch Z3/Z9 Rare
  cells (wobble 45–60%, L columns 9/9 so progression never blocks); overdue-wall detector
  should move to ACTIVE-time basis (false-positives across parked nights at 1h/day);
  next-band pacing items surfaced by the funnel (m031 Co, m030g Circuit — ~on-curve).

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

## 2026-07-16 — Bounty/Quest split (v139)

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

- Branch `MissionFlow`, working dir `C:\Users\gokbe\Desktop\horizonidle-godot`.
  Local and `origin/MissionFlow` matched at `027a7eb` when this block was written.
- **Untracked and deliberately NOT committed:**
  - `steam/new_screenshots/` — Steam store marketing PNGs (Jun 30), unrelated to dev.
  - **174 one-shot balance-probe files** in `scripts/sim` and `scenes` (`rft_probe*`,
    `eft_*`, `chan_*`, `cumrule_*`, `nc_burn`, `infra_breadth_*` and similar), left over
    from earlier balance investigations. Swept on 2026-08-08: nothing tracked cites any
    of them. They are not in git history, so deleting is irreversible — needs an explicit
    go-ahead rather than a tidy-up.
  - The two probes that **are** cited by shipped code (`nc_audit`, `dr_audit`) were
    committed in `027a7eb`, along with ten missing `.uid` twins.
- One dead pointer remains: `shipyard_manager.gd` cites `scripts/sim/eft_verify.gd`,
  which does not exist. The surrounding comment may still be accurate, so removing the
  citation is a separate judgement call.

---|---|
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

## v175 — Zone 1 boss retuned for the corvette (owner ruling)

**Ruling:** soften the boss; the frigate stays after it.

The 2026-08-09 reorder (`4562435`) moved the Rogue Architect ahead of the frigate, making it the
only mandatory fight in the game on the **starting corvette**. Nothing was retuned to match. It was
not a hard fight — it was the wrong fight.

Measured (`scripts/sim/z1_boss_tune.gd`, the loadout the mission chain actually hands the player:
Common shield/armour/engine/batteries + 2 crafted Mass Drivers, one swapped for the m026d Rare):

| | before | after (51 trials) |
|---|---|---|
| CHAIN kit, corvette | **0/21** | **35/51 — 69% [55, 80]** |
| CHAIN kit, frigate | 21/21 | 51/51 |
| Common, corvette | 0/21 | **0/51** — the gate holds |
| Rare, corvette | 11/21 (52%) | 50/51 (98%) |

**Changes**, all local to `z1_boss_architect`:

- `hp` 1000 → **900** (960 → 864 after the 0.96 rebase)
- `atk` 26.667 → **16.0**
- `charge_nuke.mult` 4.2 → **2.5**

The mult was a **defect, not a tuning call**. The comment above it describes "every 4th swing,
x1.75"; when `every_n` moved 4 → 8 the mult should have been re-derived by this file's own
DPS-preserving rule (documented on `z4_frost_hulk`): `new_mult = 1 + (old_mult - 1) x new/old`
`= 1 + 0.75 x 2 = 2.5`. Shipped 4.2 was 68% above that — a 112-damage telegraph into a corvette
with ~155 max HP, a near-one-shot rather than the documented "dent".

### What the measurement refuted

The audit named `charge_nuke` as the lever. **It is not.** At mult 2.0 (a 53-damage spike) the chain
kit still cleared only 1/21. The player was dying to the sustained trade, not the telegraph —
21/21 deaths, zero timeouts. Cutting the spike alone would have changed nothing.

### The Uncommon exception (Z1 only)

`boss_gearcheck` applies a blanket "Common AND Uncommon must both lose" to every boss. **At Zone 1
that rule is not satisfiable alongside the mission chain**, and this is a measured fact rather than
a judgement call: the chain kit is Common gear plus ONE Rare weapon in one of the corvette's two
weapon slots, and it measures 69% [55, 80] against full Uncommon's 63% [49, 75] — the same power
class, intervals almost entirely overlapping. A 27-cell `hp x atk` grid confirmed no boss stat
separates them: **the chain kit never exceeded 38% in any cell where Uncommon still lost.**

So the owner's ruling ("the chain kit must clear its own capstone") entails Uncommon clearing it
too. That is also the better tutorial lesson — Zone 1 teaches *"crafted gear is not enough, go get
a drop"*, not *"get Rare specifically"*. **Common still loses 0/51**, which is the gate that
carries the lesson.

`boss_gearcheck` now encodes this as a **named, Z1-only exemption** that prints on the Z1 row
itself, so it cannot be mistaken for a silent pass. It reports 15/15 again. **Do not widen it** —
every later zone has a real gear ladder and a hull sized for its boss.

### Guard

`scenes/z1_boss_tune.tscn` — measures the chain-produced loadout directly (the question
`boss_gearcheck` structurally cannot ask, since it only builds tier-matched sets), on both hulls,
and fails if Common ever clears the boss or the chain kit drops below 60%. Prints Wilson intervals
so the noise is visible. Default 21 trials; use `--trials=51` near a threshold. `--sweep` and
`--grid` re-run the lever searches above.

---

## v175 — guidance follows the chain, not the source file

Reordering the Zone 1 chain (boss before the industrial arc) did not move the gold arrow.
A 175-minute save was still steered to research **Shipwright I** and craft the frigate
*before* the boss, because guidance was answered in three places by three different proxies
for "where is the player", none of which was the chain:

| Place | Old authority |
|---|---|
| `mission_manager.get_tutorial_frontier_id` | LAST active beat in **definition** order |
| `research_page.on_page_enter` | FIRST active research beat in **definition** order |
| `main.gd::_update_navigation_hints` | an `elif` cascade — **source-file** order |

All three agree with the chain until the chain is reordered, then they silently keep pointing
at the old shape. `m026` (Shipwright I) was written ~280 lines above `m026c` (the boss ramp),
so it won.

**The fork itself is not a bug.** `_rescue_orphan_chains` opens the successor of every claimed
beat, so a save that ran the arc under the old order legitimately has *two* fronts open —
`m026c` (after the claimed `m017`) and `m026` (after the claimed `m025b`). The question was only
which one owns the arrow.

**Fix:** one authority — `mission_manager.get_chain_index()`, a Kahn topological order over the
`next_mission` edges (seeded in definition order so merges like `m016b`/`m016c` → `m017` stay
deterministic), and `get_chain_frontier_id()` = the earliest active, incomplete, non-goal beat.
All 87 ladder branches were re-keyed from `"mNNN" in mm.active_missions` to `front == "mNNN"`,
which makes the cascade's order irrelevant. **No save surgery** — existing saves resolve to the
right beat on load and keep their progress.

**Guard:** `guidance_order_check` reproduces the reported save exactly (36 claimed beats, both
fronts open) and asserts the frontier is `m026c`; it also asserts the index respects every
`next_mission` edge, that no ladder branch has drifted back to membership testing, and that no
reachable beat is left with neither a branch nor a routable type.

Two guards had encoded the old shape and were repaired, not relaxed: `mission_routing_check`
scraped main.gd for the literal string `in mm.active_missions` (it found zero routed ids after
the conversion and blamed `m017`), and `stale_mission_check` was reading the **developer's live
save** on boot, so its answer depended on whatever that save happened to hold — it now clears
`active_missions` before installing its fixture.

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
