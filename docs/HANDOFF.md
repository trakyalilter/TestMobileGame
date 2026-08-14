# Session Handoff — 2026-08-13

---

## LATEST BLOCK (2026-08-13) — v176: CHAIN GEAR LADDERS + SALVAGE VAULT

Started as "fix the m032a wall", became a structural finding about the mission chain, and
ended on the first feature of the new **features-and-gameplay** direction (owner call: stop
QoL/balance work).

### State right now

| | |
|---|---|
| `tools/boot_check.ps1` | **0 errors, 0 warnings** |
| new guards | `chain_readiness_check` **PASS (6 boss beats)**, `vault_carry_check` **PASS (6 assertions)**, `bounty_filter_check` **PASS (5 cases)** |
| `chain_supply_check` | **PASS** — now prices recipe paths, not just direct drops |
| `warp_layout_check` · `i18n_overflow_check` · `mission_i18n_check` | **PASS** |
| funnel depth | chain work moved it **not at all** (78.3 both). The **bounty filter fix took it to 81.7**, deepest single run `m033a1` (#85) — the only change all session that measurably moved the funnel |

### The finding: the chain hands over gear the guards assume it already gave

Two guards certify boss fights and **both assume equipment the mission chain never provides**:
`boss_gearcheck` fights every boss from `_set_hull(n)` (hull tier == zone), and
`energy_margin_check` equips tier-matched batteries. Neither reads the mission table. So:

- **The hull ladder skipped tier 4 entirely** — Frigate(2) → Destroyer(3) → **Battlecruiser(5)
  at m032c**, which landed *after* both the Z4 boss farm (m030i) and the Z5 boss farm (m032a).
  `cruiser_hull` had no construct mission at all.
- **The battery ladder ended at Zone 2** (`m030c2`) and was never revisited. Players flew
  Belt-era cells through Zones 3, 4, 5+. That is the bot's `power_wall: cannot fit <type>
  counter` — it owns the counter and physically cannot mount it.

New probe **`hull_gate_diag`** holds the kit fixed (full Rare Zone-N weak-type, power
over-provisioned) and varies ONLY the hull, 21 trials:

| boss | destroyer(3) | cruiser(4) | battlecruiser(5) |
|---|---|---|---|
| Z4 Overseer (m030i) | 2–6/21 | 17–18/21 | 19–21/21 |
| Z5 Harbinger (m032a) | 4–10/21 | 14–18/21 | 18–21/21 |

**In a Destroyer a full RARE Zone-N set wins 10–19%. The hull is the ceiling and no amount of
extra Rares lifts it.**

### What shipped in the chain

`m030h1` Heavy Cruiser + `m030h2` Power Refit II (Z4 cells) before m030i · `m032c`
Battlecruiser **moved ahead of m032a** + `m032c2` Power Refit III · `m033a1` Capital Ship +
`m033a2` Power Refit IV before m034. Rewired: `m032 → m032c → m032c2 → m032a → m032b → m032d
→ m033`. Existing saves are safe — `sync_progress:1020` already completes a construct beat
when `current_tier >= target_tier`, so a player already in a bigger hull is not sent backwards.

New guard **`chain_readiness_check`** encodes the invariant so this cannot recur: walk the
chain in topological order tracking what it has GIVEN, and assert at every boss beat that the
hull is tier ≥ zone and the batteries can fill every consumer slot. It measures power by
**equipping**, not by comparing draw to capacity — `equip_module` REFUSES an over-draw, so a
ship that cannot afford its guns never mounts them and reads as low-draw. A draw-vs-cap
comparison calls that a PASS.

### ⚠ THE HONEST RESULT: this did not fix the funnel

**The livelocks are not gone.** m030i still walls at 48h on seed 4; m030f2 still walls on
seed 27. Dwell for m030i, baseline → after chain fixes → after the bot-bar cap:

| seed | baseline | chain fixes | + cap |
|---|---|---|---|
| 4 | 7.7h | 127.6h | 103.7h |
| 11 | 39.8h | 71.8h | 40.1h |
| 27 | 39.8h | 32.2h | 32.0h |

Mean depth is **78.3 in both baseline and final** — the fixes bought nothing measurable inside
a 14-day cap, because they add five build beats that cost time.

`m030f2` is the control that makes this trustworthy: it sits upstream of every change and its
dwell is **byte-identical across all three runs** (47.6 / 31.7 / 95.9h), so the seeds are
deterministic and diverge only after the first inserted beat.

**Why the middle column is worse than baseline:** `_boss_gear_ready` required EVERY weapon slot
to hold a Rare weak-type Zone-N gun, so the bar scaled with the hull — the tier-4 cruiser's 5
mounts demanded 25% more farming than the destroyer's 4. **A better ship raised the gear bar.**
Now capped: `mini(weapon_slots, 4)`, frozen at the destroyer-era requirement, so hull upgrades
add capacity but never move the gate. (A MAJORITY-of-slots variant was tried and rejected: seed
4 went #74→#84 but seed 11 threw 24 walls losing to Zone-5 *trash*.)

**The real remaining cause was acquisition rate** — a weak-type Rare is
`drop_chance × 11.5% rarity × ~1-of-7 pool weight` ≈ **0.2%/kill ≈ 470 kills**, and the chain's
supposed deterministic bridge was not one. **Fixed below**, and that is what finally moved the
funnel; the chain ladders did not.

### `chain_supply_check` priced the wrong path

It failed `m033a2` at "8 ReactiveCore = ~100 kills". Mis-pricing: its `craftable` set means
"reachable with NO fighting at all", so a combat-fed recipe never enters it and the item gets
billed at its rare_loot rate. Real path: 8 cores = 4 crafts = 24 ColonySalvage, and the same
turret drops 5–12 a kill → **~3 kills**. Now prices the cheapest **path** via `_effort_at()`
(fixed-point relaxation over quantified recipes, cached per zone), asserting
`effort > MAX_KILLS × ehp`. Algebraically identical on the direct path — every other row still
prints its old kill count. Note the direction: where a recipe is cheaper the guard is strictly
**more permissive**, never stricter.

### The bounty board is finally the bridge it claimed to be — and it is what moved the funnel

`m030d`'s mission text has always told the player the board is the deterministic way out of a
gear wall: *"hunt contracts pay a GUARANTEED Rare module on claim."* It was guaranteed on
**rarity only**. The base module came from `pool[randi() % pool.size()]` — a uniform pick that
ignored the player's loot filters entirely, while ordinary drops have honoured them since
v135a. The wall the board exists to bridge is a **type** wall, so a board that ignores the
filter is not a bridge, it is another lottery ticket.

`bounty_manager` now awards through a new public
`combat_manager.pick_drop_like_module(pool, sm)`, which applies the research gate, the slot
filter, the weapon-damage-type filter, the over-narrow fallback (a claim NEVER pays nothing)
and `MODULE_DROP_WEIGHTS`. The Rare+ floor is untouched, so a bounty is now precisely "a drop
whose shape you chose, with the rarity guaranteed". Shared, not copied — shipyard's v141 note
records an inline duplicate of `_legal_affix_pool` silently diverging from the real rule.

`bounty_filter_check` claims 60 real contracts per case through `claim_contract()`. Run against
the OLD code it quantifies what was being wasted:

| | before | after |
|---|---|---|
| weapons off-type (energy filter set) | 14 of 20 | **0** |
| awards off-slot (weapon filter set) | 34 of 60 | **0** |
| batteries awarded | 8 | **0** |

Those batteries are the tell: live drops exclude them at weight 0, so the board was handing out
rewards the drop system considers impossible.

**Funnel effect, seeds 4/11/27 at 14 days** — and note this is UNDERSTATED, because
`player_like` never sets loot filters at all, so the bot only benefits from the slot/battery
half of the fix. A real player who filters gets the full effect.

| config | s4 | s11 | s27 | mean | walls |
|---|---|---|---|---|---|
| before | #78 | #77 | #80 | 78.3 | 2/2/2 |
| **bounty fix** | **#80** | **#80** | **#85** | **81.7** | **1/2/1** |

### ⚠ REJECTED: teaching the bot to set the loot filter

Making `player_like` point `loot_weapon_type_filter` at the boss's weak type when it enters the
gear-farm branch looks strictly more faithful — the bot already computes that type there and
prints it in `status`. **It measured worse and was removed**: mean **81.7 → 73.3**, seeds 4 and
11 both #80 → #70, and seed 4 gained a new 55h wall on the *Zone 1* boss.

Attribution required running the two changes SEPARATELY; the first run had both and was
unreadable. Likely mechanism (inference, not measured): the filter persists and the bot only
re-points it after losing to a new boss twice, so most farming runs biased toward the PREVIOUS
boss's channel, starving the breadth `_boss_gear_ready` also needs. A retry must clear the focus
when the objective changes, and be measured over more than three seeds. The table lives in
`player_like.gd::_do_farm_rarity`'s note so the next person to have this idea sees it first.

### v176 feature: the Salvage Vault

Spec: [`docs/design/SALVAGE_VAULT.md`](design/SALVAGE_VAULT.md). Owner framing — players should
warp several times before mid/endgame, AdVenture Capitalist angel-reset style. That exposed
the blocker: `shipyard_manager.reset()` wipes `module_inventory` + `loadout` +
`custom_modules` on every warp, so the ~470-kill hunt repeats **in full every run**. No
drop-rate number fixes that; it is a design gap, not balance.

**Mechanic:** nominate up to K modules at the warp confirm; they survive and land *unequipped*.
`K = clampi(2 + total_warps, 3, 8)` — automatic and permanent, not a purchase. Implemented as
the fleet's REC_1: snapshot before `shipyard_manager.reset()`, restore after. **`reset()` is
deliberately not special-cased** — it is also the new-game path.

**The anti-power-creep guard already existed and needed nothing new:** `can_equip_module`
enforces `research_req` and, for `custom_*` drops, the BASE module's requirement too
(`shipyard_manager.gd:6192`); `generate_module_drop` copies `research_req` onto every roll.
Warp resets research, so a vaulted Z6 gun waits until Z6 is re-researched. The vault removes
re-farming, **not** progression. The interesting decision is therefore *tier* — carry high and
the run starts slow and ends strong.

`vault_carry_check` asserts all six spec claims against the real `execute_warp()`. Broken on
purpose to confirm it bites; it also caught an unanticipated knock-on — a stripped def loses
`research_req`, so a bad restore defeats the power-creep gate too.

### Gotchas learned this block

- **`player_bot` reads flags via `OS.get_cmdline_user_args()` — they need a `--` separator.**
  Without it every run silently uses defaults (`follower`, seed 11, 14 days). Per-seed numbers
  reported earlier in the session were invalid for this reason. Correct form:
  `godot --headless --path . res://scenes/player_bot.tscn -- --seed=27 --days=2 --out=t.jsonl`
- **`boot_check.ps1` does NOT cover the warp page** (lazily loaded). A parse error in
  `warp_page.gd` booted clean and only `warp_layout_check` went red.
- **`hull_gate_diag` / `boss_gearcheck` cells are noisier than 21 trials can resolve.** The
  same Z3 destroyer configuration read **6/21 and 13/21 within a single run** — Rare stat rolls
  plus 2 affixes swing kit power that much. Only large gaps are trustworthy.
- **`const` Dictionaries are read-only**; `c["zone"] = x` on a const entry throws at runtime.
- A probe hardcoding the wrong zone id (`wreckage_field`; Z3 is `mars_debris`) made every Z3
  cell read 0/21 L100% on all hulls — wrong zone → wrong difficulty → the tier-penetration gate
  zeroes damage. Looked exactly like a catastrophic game finding. `hull_gate_diag` now derives
  zone from `cm.zones`.

### Next

1. **P3 for Z7–Z10** (Z1–Z6 already shipped in v139d, see the CLAUDE.md correction below).
2. Live playtest of the Vault — the guard covers mechanics, not feel. Cap 8 is the number most
   likely to be wrong; it decides whether run 2's early zones stay interesting.
3. The remaining walls are `m030f2` (Z3) and `m030i` (Z4), both still 30–100h dwell dominated by
   offline blocks plus a multi-hour gear detour. The bounty fix helped but did not close them,
   and `m030f2` sits upstream of every chain change made this session.

---

## PREVIOUS BLOCK (2026-08-13) — v175: AUDIT CLOSE-OUT + NG+ FARMABILITY

`e7bd4e5..b5cc8c1`. Started from a 12-agent measured audit of the mission chain and research
tree, ended in the NG+ loop. **Every audit finding is closed and the guard suite is green.**

### State right now

| | |
|---|---|
| guards | **50 run, 50 pass** |
| `boss_gearcheck` | **15/15 honour the rule** |
| `zone_gate_check` | **ALL GATES HONOR THE RULE**, now covering **Z1→Z2 … Z14→Z15** |
| `tools/boot_check.ps1` | **0 errors, 0 warnings** |
| branch | `MissionFlow`, HEAD = origin, tree clean |

### The audit

61 findings raised → 42 escalated to 14 adversarial verifiers → **12 survived** (2 critical,
10 major). **Two thirds of the audit's own severity ratings did not survive a second
measurement** — that ratio is the most useful number it produced. Full record with every
verifier's raw output: [`docs/audit/AUDIT_2026-08-11_MISSION_RESEARCH.md`](audit/AUDIT_2026-08-11_MISSION_RESEARCH.md).

All 12 fixed, each with a guard that was watched going red for the stated reason and back:
NG+ techs unreachable (16 modules uncraftable) · 10 dead processing-speed techs ·
`m029a8`'s Zone-3 stall · 27 untranslated mission strings · the bounty-across-warp exploit ·
three wrong refit slot counts · the Zone-1 corvette boss · guidance following source order.

### NG+ farmability (the second half of the session)

`zone_gate_check` skipped every warp-hardened zone, so **Z11–Z15 had no farmability check at
all**. Extending it needed exotic-weapon kits, per-zone armour, and the NG+ flags — and it
immediately found three real BLOCKs. The **Z10→Z11 warp gate is perfect**: a maxed Z10 kit
scores literally **0 kills** against warp-hardened Z11.

What moved, all measured with `ng_hp_sweep` / `nogain_diag` / `z14_boss_sweep`:

- **NG+ defence ladder was non-monotonic** — authored def ran 22820 → **16049** → 25834 →
  **24660** for Z12–Z15 while e3 attack *doubled* every zone. Z13 ×1.89, Z14 ×1.36, Z15 ×1.70.
- **Z14 needed three levers plus a boss compensation.** Defence alone still died; attack alone
  still died even at ×0.55. Final: armour ×1.36, trash hp ×0.60 / atk ×0.53, and
  `z14_boss_dissolution_tyrant` atk ×1.25 — because the shared armour made that boss lose to
  **Uncommon 8/9**, which the gear rule forbids.
- **Trash HP cuts** on `z11_exotic_leviathan` ×0.75, `z12_caustic_leviathan` ×0.75,
  `z13_patina_phantom` ×0.57 overall, `z15_blight_titan` ×0.40.

### `zone_gate_check` was flapping, and numbers had been tuned against it

Two **simultaneous** runs of identical code printed `ALL GATES HONOR THE RULE` and
`3 CELL(S) VIOLATE`, one of the flapping cells being Z2→Z3 — untouched in months. Two
independent causes, both fixed in the check:

- **death was a boolean** (`not died_any` over 5 windows). A 13% per-window death rate fails
  `1−0.87⁵` = **51% of runs**. Now a rate against `DEATH_RATE_MAX = 0.25`.
- **kills were a 5-sample median**, which jumps a whole unit on one sample. Now the **mean of
  9** (`TRIALS 5→9`, `TIER_TRIALS 3` for the cheap tier cell).

Statistics alone were not enough — cells within ±0.5 of the bar still flapped, so Z13 and Z14
were moved *clear* of the line rather than balanced on it. Verified by running the check
**five times before and three times after**, not once.

> **If you change an NG+ number, re-run `zone_gate_check` at least twice.** A single green run
> is what misled this session twice.

### Also landed

- **`tools/boot_check.ps1`** replaces the hand-typed boot grep. The old pattern
  (`SCRIPT ERROR|not declared|Nonexistent function|Cannot infer`) was blind to `ERROR:` and
  `Failed to load` — the last three terms are all `SCRIPT ERROR` substrings — so **a broken
  scene reference booted "clean"**. Proved: old pattern 0 matches on a run producing 3 `ERROR:`
  lines. Warnings print but never fail.
- **`atlas_page.tscn` / `warp_page.tscn` invalid UIDs fixed** — the build now has zero warnings.
- **Two guards repaired, not relaxed:** `phase_gate_spike` (17 stale assertions, and it exited
  **0** the whole time) and `bounty_check` (a bounty board is not always 4 cards).
- **`NOGAIN` now compares like with like.** It was pitting an *optimised* Zone-N kit against
  *fresh* Zone-(N+1) commons. Measured like-for-like, every tier is worth **×4.3–4.9** — acting
  on the old verdict would have meant a ~30–40% global affix nerf to fix a non-problem.

### Gotchas earned the hard way today

- **PowerShell `-Encoding utf8` writes a BOM.** It broke a `.tscn` (Godot: *"Expected '['"*) and
  left an invisible BOM in commit `b5cc8c1`'s subject. Use the editor for files Godot or git reads.
- **`sm.attack` excludes** affix/core multipliers *and* `atk_cryo`. It reads **0** for every NG+
  kit. Do not use it to compare gear power.
- **`_kit` lives on `boss_gearcheck`; `zone_gate_check` calls it `_use_kits`.** Mixing them throws
  on every one of 1,800 ticks per window — a probe that "runs long" is a lookup error first.
- **Phases are on BOSSES only.** A `grep -A` over a trash enemy spills into the boss below it.

### Next

1. **Playtest Zone 1** — it changed a lot (staged damage types, kit trim, mission XP removal,
   boss-before-industry, corvette retune).
2. **#28 Loop 2 — Plasma frontier Z16–Z19** (see the older *Next up* section below).
3. Optional cleanups the audit surfaced but nobody ruled on: `get_tier_defense_factors()` has no
   production caller (v120 left it behind); `chain_supply_check`'s cross-tab-parent list; the
   locale-dependence sweep for probes asserting on `tr()`-wrapped values.

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
  `powershell -NoProfile -File tools/boot_check.ps1`. (v175: was a hand-typed grep for
  `SCRIPT ERROR|not declared|Nonexistent function|Cannot infer`, which is blind to
  `ERROR:` / `Failed to load` and so missed resource-load failures entirely.)
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

## v175 — bounty_check repaired (2 red assertions, 1 root cause, 0 real regressions)

Both failures were the same stale premise: **a bounty board is not always 4 cards.**

`_generate_zone_pool` emits **one hunt per module-hunter**, and hunters = the last two trash
enemies. The staged damage-type ruling cut Zone 1 to a **single** trash enemy, so it has offered a
correct 3-card board (1 hunt + boss + elite) ever since — while the probe hardcoded `hunts != 2`
(test 1) and `size() != 4` (test 2).

| zone | trash | board |
|---|---|---|
| Z1 Lunar Orbit | **1** | **3** |
| Z2 Asteroid Belt | 2 | 4 |
| Z3+ | 3–4 | 4 |

**Fix:** both expectations are derived from the roster the generator actually reads, and the failure
line now prints got/want per zone (`hunts=1/2 ... (trash=2)`) instead of a bare false.

Two matching falsehoods in the source were corrected at the same time:

- `_generate_zone_pool`'s comment claimed *"Every zone ships 4 trash + boss, so last-two = e3/e4
  universally (defensive slice for odd rosters)"*. That slice is **load-bearing** now, not defensive.
- **`CARDS_PER_ZONE = 4` was declared and referenced nowhere** — a dead const asserting the same
  dead invariant. Removed; grep confirms no dangling references.

### Guard

Negative-controlled by breaking the generator to emit one hunt per board: both tests go red naming
every affected zone, and the process exits 1. **Zone 1 is correctly NOT flagged** — one trash
legitimately wants one hunt — which is what shows the derivation is roster-aware rather than
self-validating. Restoring gives ALL PASS and exit 0.

That self-validation risk is the real hazard when a guard computes its own expectation, and it is
the same trap the material-order guard fell into earlier in v175 (it marked its targets reachable
before testing them). Any "derive the expected value" assertion needs a control that moves the
PRODUCER and not the data both sides read.

---

## v175 — the boot check was blind to half of Godot's errors

The project's standing smoke test was a hand-typed grep, repeated in four docs:

    SCRIPT ERROR|not declared|Nonexistent function|Cannot infer

**The last three are all `SCRIPT ERROR` substrings**, so the whole pattern only ever caught GDScript
runtime faults. It matched none of `ERROR:` (engine errors, *including every resource-load
failure*), `Failed to load` / `instantiate` / `open`, `USER ERROR:` (our own `push_error`), or
`Invalid call` / `Invalid access` / `Attempt to call`. **A broken scene reference booted "clean."**

That is how the invalid-UID warnings in `atlas_page.tscn` and `warp_page.tscn` went unnoticed — they
only surfaced when a probe that instantiates `main.tscn` happened to print them.

**Now a script:** `powershell -NoProfile -File tools/boot_check.ps1` (`-Scene res://…` to boot-check
a probe, `-Seconds N` to change the window). Exit 1 on error, 0 on pass.

**Warnings print but never fail.** A `WARNING` is Godot saying it recovered — the UID fallbacks
resolve by text path and load fine. Failing on them would hand the repo another permanently-red
check, which is exactly how `phase_gate_spike` and `bounty_check` stopped being read.

### Measured, not assumed

A temporary probe that loads a nonexistent resource — `ERROR:` lines only, no `SCRIPT ERROR`
anywhere, which is the precise shape the old pattern could not see:

| | result |
|---|---|
| old grep pattern | **0 lines matched** |
| `tools/boot_check.ps1` | **3 ERROR lines, FAIL, exit 1** |

Control files deleted after use. Plain boot re-runs PASS at 0 errors / 0 warnings; the page-walking
scene reports the 2 UID warnings and still passes.

### Known gap, stated in the script

The boot instantiates the main scene and what it pulls in. Pages loaded **lazily on first visit**
(atlas, warp) are not touched, so a broken page scene still passes here — `i18n_overflow_check`
walks every page and is what covers those.

### Also worth cleaning

`atlas_page.tscn` and `warp_page.tscn` carry invalid UIDs (`uid://atlas_page_script`,
`uid://d3vk6u6u6u6u6`). Harmless — Godot falls back to the text path — but they are the only two
warnings in the build.

---

## v175 — Z3→Z4 BLOCK fixed: the Zone-4 e3 attack was a 6.5x step on a 3x curve

`zone_gate_check` reported **BLOCK** on Z3→Z4 — the clean Zone-4 COMMON set died to
`z4_glacial_drone`, breaking Rule B ("the intended answer must be able to farm the zone"). It was
the only BLOCK in the table.

### It nearly went unfixed for a good reason, and nearly got fixed for a bad one

`z4_glacial_drone` carries a **108-trials-per-cell** sweep in its comment block (v147) reporting the
clean-Common death rate at **1–3 per 108 windows**, concluding the discrimination ratio is maximal
at the shipped value, and saying in as many words *"Fix the affix axis, not this stat line."* v151
then raised its EHP ×1.75 and measured **0 deaths in 21 trials**.

Against that, one 5-trial `DIED` is weak evidence — `zone_gate_check` sets `died_any` if **any** of
its 5 windows ends in a death, so a 3% rate flips the cell ~14% of runs. So the rate was measured
before anything was touched:

| | deaths / 21 windows | | |
|---|---|---|---|
| shipped (atk 770 spawned) | **9/21 = 42.9%** | Wilson95 [24%, 63%] | median 15 kills |
| after (atk 510 spawned) | **0/21 = 0.0%** | Wilson95 [0%, 15%] | median 16 kills |

**The wall was real** — and the v147/v151 numbers have drifted ~20× without anyone re-measuring.
Nothing in that comment block explains it; whatever moved (Common kit power, the resist triangle,
the ×1.75 EHP raise lengthening exposure) happened elsewhere. **Do not quote those figures again
without re-running.**

### Why 510 and not lower

The size came from the curve, not from taste. Spawned e3 attack by zone was **119 / 770 / 2184 /
6600** for Z3–Z6: a **6.47×** step into Z4 against ~3× either side. 510 is the geometric mean of Z3
and Z5, making both steps **4.28×**. Cutting further does not help — it *moves* the cliff onto
Z4→Z5 (at ×0.45 that step becomes 6.30×, worse than the one being fixed).

`atk 155.555556 → 103.0` authored; ×`tier_rebase(4)` 4.952 = 510 spawned.

**Result:** Z3→Z4 now reports `BOOT` (maxedZ3 9 kills vs commonZ4 16) — Rule B satisfied, Rule A
satisfied at 9 ≤ 16/1.25. Violations 5 → 4; the remaining four are the untouched NOGAIN cells.
`boss_gearcheck` still 15/15, boot clean.

The v147 warning still stands on its own terms: the deep cause is the **affix axis** (carried
Legendary rolls `resist_e` 0.57–0.75, clean Common pinned at 0.28). This restores Rule B; it does
not fix that.

### Two instrument notes

- **`zone_gate_check`'s death test is a boolean over 5 trials.** It gave the right answer here (43%
  is unmissable), but at a few percent it would false-BLOCK ~14% of runs. It should be a rate with a
  threshold. Not changed — flagging it.
- **`scripts/sim/z4_block_diag.gd`** (kept, diagnostic) measures that rate. Its first version
  hand-rolled the window loop and called `_kit()`, which lives on `boss_gearcheck`, not
  `zone_gate_check` — so it threw *"Nonexistent function '_kit'"* on every one of 1,800 ticks per
  window and ran for an hour without finishing. It calls `zone_gate_check._run()` now, which is both
  correct and fast (it early-exits on death). A probe that "runs long" is a parse/lookup error until
  proven otherwise.



It had been failing **17** assertions **and exiting 0**, so nothing surfaced it and by the time it
was read nobody trusted it. Every one of the 17 was stale or a probe bug. **No real regressions.**

| n | cluster | why it was red |
|---|---|---|
| 5 | v119 explosive-teach | `m026d2`/`m026d3` deleted in v174; staged damage-types took explosive out of Zone 1 and zeroed the boss's `resist_x`. Could not pass however the game behaved. **Deleted.** |
| 7 | v114 alloy injection | `tier_gate_enabled` no longer injects a signature alloy. `compose_module_costs()` bakes the charged cost into the authored dict and `get_effective_module_cost()` is a plain `duplicate()`. **Replaced** with the invariant that mattered: charged cost == displayed cost. |
| 2 | spawn-time armour floor | **Removed in v120** — `combat_manager` sets `_tier_def_factor = 1.0` under a comment saying exactly that, and nothing else writes it. Now pins the no-op so re-wiring is visible. |
| 2 | `can_swap_loadout_in_combat` | Rule deliberately broadened; `combat_page.gd` says "swapping in any fight is now allowed". Expectation updated to the shipped contract. |
| 2 | display names | `ElementDB.get_display_name()` calls `tr()`, so these compared English against `user://locale.cfg`. **This machine persists "tr"** — they failed here and would have passed on an English box. Now read `ELEMENT_NAMES` directly. |

**The exit code is fixed.** It was `get_tree().quit(0)` unconditionally — a guard CI cannot see is not
a guard, and that single line is why 17 failures survived this long.

Negative-controlled by breaking `can_swap_loadout_in_combat` to `return false`: 3 assertions go red
and the process exits **1**; restoring gives ALL PASS and exit 0.

### Two things this turned up, not fixed here

- **`shipyard_manager.get_tier_defense_factors()` has no production caller.** v120 removed the
  feature it served; the helper survived. Dead code, cleanup candidate.
- The locale-dependence class is worth a sweep: any probe asserting on a `tr()`-wrapped value has a
  verdict that depends on whose machine it runs on. `stale_mission_check` had the save-state version
  of the same disease earlier in v175.

---

## v175 — m029a8's Zone-3 material stall (audit MAJOR, fixed — after one wrong fix)

`m029a8` commissions the Electronics Assembler at chain step 56. That building costs
`{credits 25000, Ti 50, Circuit 40, SalvageData 12}`, and **SalvageData's only faucet in the game was
`z3_derelict_frigate`** — Zone 3, which the chain does not open until `m030e` at step 63.

### The first fix was wrong, and adversarial verification caught it

I put the faucet on the **Zone-2 boss** (Silicate Monolith), reasoning that a boss is slower to farm
than trash so Zone 3 would stay the real source. Five skeptics measured it and three returned
PROBLEMATIC. The killing measurement, 21 trials per cell:

    step56 literal: frigate + Z1 KINETIC Common     0/21   best loss left 100% of boss HP
    step56 best   : frigate + Z1 ENERGY  Common     0/21   best loss left 100% of boss HP
    step56 dream  : frigate + Z1 ENERGY  Legendary  0/21   best loss left  72% of boss HP
    step62 kit    : destroyer + Z2 ENERGY Rare     19/21   median 135s

**The step-56 player cannot damage that boss at all** — "100% of boss HP left" is literal; Z1 guns
never outpace the Monolith's +5%-shield-per-8s sustain. And the gear that beats it (destroyer,
Z2 batteries, Z2 energy guns) arrives at steps **60, 61, 62** — all *behind* the beat it was meant to
unblock. The fix moved the wall instead of removing it, and made the mission text confidently wrong:
it now pointed a player at a fight they lose in 8 seconds.

### The actual fix

`z2_pirate_skiff` (Zone-2 **trash**, 633 EHP, already farmed by `m029`/`m030c2`/`m030c3`) gains
`rare_loot ["SalvageData", 0.5, 1, 2]` — 0.75/kill, so 12 units is **~16 kills**, inside the chain's
own ceiling. The Z3 frigate keeps 2-4 guaranteed, **4x better per kill**, so Zone 3 is still the farm
once it opens.

Mission text now names a reachable enemy and completes the enumeration — it was still omitting the
**25,000 Liras**, the largest line, after the first edit added the 40 Circuit Boards. Turkish moved
with the key again, and dropped a calque: `çalıştır` means *operate a machine* (`Su Elektrolizi
çalıştır`) and read as "start the boss up" when applied to an enemy.

**`firmware_hacking` now becomes affordable a zone earlier — and that is the intent, not a side
effect.** Its own v137 comment calls it "a goal that REVEALS at the Zone-2 gate"; SalvageData was the
last Zone-3 lock holding affordability out of step with the reveal.

### The guard had certified the bad fix. Four defects, all now closed

`chain_supply_check` passed the boss version and reported "~4 kills, matches the norm". It was wrong
four ways:

1. **It never inspected `gather` beats** — 24 of 85 beats, the most literal form of "this beat demands
   N of a material", walked past unchecked. It did not close the class it was written for.
2. **It priced a boss identically to trash.** It picked the *highest per-kill yield* source, so a
   17,897-EHP capstone and a 633-EHP trash mob both printed "~4 kills". It now picks the **cheapest
   by EHP** and prints the effort.
3. **It never asserted the kill count** it computed — any nonzero faucet produced the same green.
   Now fails past a ceiling.
4. **It had no boss gate.** Now fails when a demand's only source is a boss the chain has not yet
   sent the player at, comparing against a pre-pass of every scheduled fight.

Negative-controlled by restoring the bad fix: the repaired guard fails with
*"m029a8 (step 56) can only source SalvageData from BOSS z2_boss_monolith, which the chain does not
send the player at until step 63"*, while the six legitimate boss demands (`m027`, `m030e`, `m030g`,
`m031`, `m032b`, `m033b`) still pass.

**Correction to the previous session note:** the chain's combat-drop norm is **up to 20 kills**
(`m026` asks 30 Res1 = 20 drone kills), not the "1-4 kills" recorded earlier. That figure came from
the broken highest-yield selection and should not be quoted.

### Transitive recipe inputs — closed

The last hole: anything a recipe *output* was treated as reachable without asking whether that
recipe's own **inputs** were. One level of indirection defeated the whole check.

Replaced with a real resolver. `req[sym]` = the shallowest zone that can produce sym — gathered is
0, dropped is that enemy's zone, a recipe costs **MAX over its inputs**, a building costs MAX over
its inputs **and its construction cost** — then MIN across every path. Relaxed to a fixed point
rather than recursed, so production cycles never lower a value and resolve to unreachable on their
own instead of needing a visited-set.

It runs **twice**, and that split is the part worth remembering. Seeding drops into the same pass
that decides "can this be made" conflates farming with refining, and the first attempt promptly
demanded the player kill 67 Scavenger Mechs for Steel they smelt. So:

- **pass A** seeds gathering only -> `craftable`, i.e. obtainable with no fighting at all, inputs
  verified transitively. This is what the old naive `non_combat` claimed to be and was not: it
  counted **139** materials, the honest resolver counts **90**. It was over-claiming 49.
- **pass B** seeds gathering + drops -> `req`, the true earliest zone by any path.

Kill maths and the boss gate now apply only when a material is NOT in `craftable` — combat has to be
mandatory before the guard prices it in kills.

Negative-controlled by breaking a single input of `smelt_steel_basic` to something nothing produces:
`craftable` drops **90 -> 81** (Steel plus eight downstream materials fall out together, which is
transitivity doing its job), the Steel beats fall back to the drop path and fail the kill ceiling,
and restoring returns 90 and PASS.

---

## v175 — banked bounties bought a free second warp (audit MAJOR, fixed)

`execute_warp()` reset seven managers and never `bounty_manager` — `reset()` had exactly one caller,
`hard_reset`. A completed-but-unclaimed contract survived the warp, and claiming it afterwards
landed in `lifetime_credits` **after** the `credits_at_warp_start` snapshot, so it read as post-warp
progress and re-armed the shard gate.

**Measured** (`bounty_warp_check`, banking the 3-contract cap from the run's own boards):

| zone | free extra shards |
|---|---|
| Z3 | **0** |
| Z5 | +3 |
| Z6 | +5 |
| Z8 | +8 |
| Z10 | **+11** |

Roughly doubling a run's prestige yield by delaying one button press. **Z3 — the earliest warp the
game offers — gives 0**, which is why this is a mid-game exploit and not the tutorial bug the audit
originally described.

**Fix:** settle completed contracts (pay their Liras), then `bounty_manager.reset()`. The position
is load-bearing in **both** directions:

- **After** `research_manager.reset()` — that reset ends in `generate_all_pools()`, which calls
  `get_unlocked_zones()`; settling earlier would seed the new run's boards at the OLD research tier.
- **Before** the `credits_at_warp_start` snapshot — which is what makes the payout deliberately
  value-lossy. The player keeps the Liras as starting capital and the snapshot zeroes them for shard
  purposes, so banking pays money but never shards. The incentive is "claim before you warp", and a
  notification says so.

**The player is not robbed.** A/B at Z8: the banked run leaves the warp with **+90.87M Liras**, exactly
the banked face value. Legitimate warp gains are untouched (Z10 still 0 -> 8 shards).

### Guard

`scenes/bounty_warp_check.tscn` — per zone: bank the cap, warp, assert nothing survived and
`calculate_warp_gains()` is 0, then A/B the settlement to prove the money was paid rather than
deleted. Negative-controlled by removing `bounty_manager.reset()` and watching Z5/Z6/Z8/Z10 go red.

### The probe lied twice before it told the truth

**It reported "no exploit" at every zone while banking nothing.** `get_unlocked_zones()` returns
`{id, name, difficulty}` **dictionaries**, not ids; `str()` over them built a board for a zone key
that does not exist. Five clean green rows from a probe that never ran the scenario. There is now a
**tripwire**: banking zero contracts is itself a failure, so this cannot pass vacuously again.

**Then it understated the exploit to zero.** `get_unlocked_zones()` sorts **ascending** by
difficulty, so taking the first three banked Zone-1 trash contracts inside a Zone-10 run — 12.8K
Liras against a 500K threshold. A player banking before a warp banks their *most valuable*
contracts. Ranking by reward across the run's own zones is what produced the +3/+5/+8/+11 above.

### Pre-existing, NOT caused by this change

`bounty_check` fails 2 assertions (`comp(2+1+1)=false`, `all-regen=false`). Verified identical on a
`git stash` of this work — it was already red before. Another guard in the state `phase_gate_spike`
is in: failing for an unrelated historical reason and therefore no longer read. Worth a session.

---

## v175 — three refit beats quoted a slot table that had moved (audit MAJOR, fixed)

Commit `ca26034` redistributed the hull slot tables (+1 weapon every tier, second slot alternating
defence/battery) without revisiting the missions that quote them. The Destroyer is
**4 weapon / 2 shield / 1 armor / 3 battery**:

| beat | claim | asked | slots | |
|---|---|---|---|---|
| `m030c2` | one per battery slot | 3 | 3 | control, untouched by ca26034 |
| `m030c3` | one per weapon slot | 3 | **4** | fixed -> 4 |
| `m030fa` | one per armor slot | 2 | **1** | fixed -> 1 |
| `m030fb` | one per shield slot | 2 | 2 | control, untouched by ca26034 |
| `m030f1` | one per weapon slot | 3 | **4** | fixed -> 4 |

The two beats that were already right are on exactly the slot types `ca26034` left alone — that is
the control that identifies the cause rather than just the symptom.

`m030fa`'s second Composite Plate was **unequippable**: a Destroyer has one armour slot, so the
player paid 7,260 Liras + 30 Steel + 10 Ti + 5 Reinforced Plating for an item that could never go on
the ship.

**Net economy effect** of all three: **+6,820 Liras**, +10 Steel, +5 Ti, +60 Si, +20 Cu,
**-5 Reinforced Plating** — against beats that pay 30,000-50,000 each, so immaterial. Raising the
weapon beats to 4 also aligns the chain with what `boss_gearcheck` already assumes (it fills every
weapon slot), so the fights these beats prepare for are now the fights being tested.

`m017a` was NOT changed. The audit flagged it as a fourth case, but its text makes no per-slot claim
("craft 2 'Pulse Laser Mk.I'", partner beat says "equip BOTH") and says nothing untrue. Raising it
to 3 is a defensible balance idea for the frigate's third weapon slot, but it is a balance argument,
not a text correction, and does not belong in a desync fix.

### Guard

`scenes/slot_claim_check.tscn` keys on the **claim, not the quantity**: only beats whose description
contains "per <slot> slot" are judged, and they are judged against the hull the chain has actually
put the player in (derived by walking the chain and remembering the last `construct` of a hull, so
it survives reordering). Asserting `target_qty == slot_count` on every craft beat instead is what
produced the audit's false positive on `m017a`. It also fails if **zero** claims match, so a
rephrase cannot silently reduce coverage to nothing.

### The i18n coupling, exactly as predicted one commit earlier

All three descriptions name their quantity in prose, and the English text IS the localization key —
so editing the number orphans the Turkish row and the beat reverts to English. The key and the
number inside the Turkish value were moved **in the same pass** (`3 adet 'Plazma Kesici'` ->
`4 adet`, etc.), and `mission_i18n_check` re-run clean at 0 untranslated confirms nothing dropped.

---

## v175 — 27 mission strings shipped in English inside the Turkish build (audit MAJOR, fixed)

Localization is ENGLISH-AS-KEY with an English fallback, which is the right runtime behaviour and a
terrible authoring signal: a missing row is not an error, not a warning, not a visible placeholder.
It is just English text sitting in a Turkish UI, and nothing reported it. `mission_widget` renders
BOTH the name and the description through `tr()`, so each gap was a whole English paragraph on the
objective card.

**Measured:** 27 strings (3 names, 24 descriptions) across 25 of the 111 beats, with the **first gap
at chain position 2** (`m002`, the third thing a new player reads). Concentrated exactly where the
game is most instructional — the steel/Shipwright/Frigate run, the damage-doctrine legs, and the
`m029a2 -> m030c` industrial spine.

**Fix:** 27 `en,tr` rows appended to `localization/strings.csv`, plus 2 element rows
(`Pentlandite` -> `Pentlandit`, `Resin` -> `Reçine`) that the new prose references — element display
names go through `tr()` too, so without them the instruction would point at a word the inventory
does not show. No code change; the loader keys on the exact English string.

Terminology was taken from the shipped glossary rather than invented. Worth knowing, because the
obvious guess was wrong: **Loadout is "Dizilim"** in this game (`"LOADOUTS","DİZİLİMLER"`), not
"Donanım". Likewise Liras -> "Lira" (no plural after a numeral), Common Artifact -> "Sıradan Eser",
Shipwright I -> "Gemi Üretimi I", Destroyer -> "Muhrip", Scavenger Mech -> "Toplayıcı Mekanik".

### Guard

`scenes/mission_i18n_check.tscn` — sets locale to `tr`, walks the chain in play order, and fails on
any mission name or description where `TranslationServer.translate()` hands back the key unchanged.
`--dump` prints the offenders as ready-to-translate CSV rows.

It opens with a **canary**: a string known to be translated (`CONTINUE` -> `DEVAM ET`) must come back
different, or the probe aborts without reporting counts. Without that, a CSV that failed to load
would make every string look untranslated and the guard would report a catastrophe that is really a
loader problem.

Negative-controlled by setting one row's Turkish equal to its English — the exact silent-fallback
shape — confirming it goes red naming the beat (`m019e name`), then restored.

`font_turkish_check` re-run: 0 of 12 Turkish glyphs missing. File verified as clean UTF-8 (ı `U+0131`,
ş `U+015F`, ç `U+00E7` present, zero `U+FFFD`); the `?` characters in a Windows console are the
terminal's codepage, not the file.

### One thing to expect

The keys ARE the English text, so **correcting an English string orphans its Turkish row** and the
beat silently reverts to English. Three strings translated here are already flagged for correction
by the 2026-08-11 audit — `m029a8` (omits 40 Circuit Boards), `m030c` (bill wrong, "same recipe as
the Frigate" is false), `m030fa`. When those are fixed, re-run this guard and re-add the rows; it
will name them.

---

## v175 — ten processing-speed techs did nothing (audit MAJOR, fixed)

`processing_manager.get_recipe_speed_multiplier()` built a 6-recipe `upgrades_db` table on every
call and **never iterated it**. The gathering twin has had the apply loop all along; the processing
copy was written without it. Ten research nodes were sold, bought, and paid exactly **+0.000**:
`fast_centrifuges`, `maglev_bearings`, `quantum_separators`, `catalytic_electrodes`, `ion_exchange`,
`resonance_splitters`, `pyrolysis_control`, `blast_furnace`, `basic_electronics`, `hydraulic_press`.

**Fix:** the four-line apply loop, mirroring `gathering_manager`.

**Measured before → after** (`recipe_speed_check`, 60 s of ticks at 60 fps):

| recipe | crafts before | crafts after | |
|---|---|---|---|
| `centrifuge_dirt` | 32 | **70** | x2.19 |
| `electrolysis` | 51 | **109** | x2.14 |

### Is that a balance event? Less than it looks

The doubling needs the **whole** ladder, and the ladder is staged across three tiers:

| | tier | cost |
|---|---|---|
| `fast_centrifuges` / `catalytic_electrodes` | 1 | 200 / 300 Liras, no items |
| `maglev_bearings` / `ion_exchange` | 2 | 1,000 / 1,500 + Res2 15 |
| `quantum_separators` / `resonance_splitters` | 3 | 5,000 / 7,500 + Res3 10 + AdvCircuit 10 |

The tier-1 node alone is +0.305 on a 1.648 base (x1.19) for 200 Liras — a cheap, correct early win.
The full x2.19 is gated behind Res3 and AdvCircuit, i.e. mid-game. So this is the intended upgrade
ladder starting to work, delivered in three earned stages, not a cliff dropped on the early economy.

### Guard

`scenes/recipe_speed_check.tscn` — every tech named in `upgrades_db` exists in the tree; each one
moves its OWN recipe's multiplier and no other (a wildcard apply would satisfy the first check while
silently buffing everything); and the multiplier survives into **real counted output**, since
`process_tick()` completes at most one craft per tick and `complete_process()` discards the overflow.

### Two things the probe got wrong first, both recorded so the next one does not

**The authored bonus is not the observed delta.** A +0.25 tech measures as **+0.305**, because the
bonus is added into `multiplier` and then scaled by the multiplicative tail of the same function
(x1.10 x 1.11 = **x1.221** from two building buffs, plus the warp tree). Asserting the raw authored
number fails on a *working* game — this probe did exactly that on its first run after the fix. It now
derives the scale from the first live measurement instead of hardcoding 1.221, which would rot the
moment a building or the warp tree moves.

**A bare `after > before` is not enough on throughput.** With the techs dead, `electrolysis` measured
51 -> 52 crafts — one craft of boundary rounding, which passes a greater-than and hides the bug. The
assertion is a ratio floor (x1.5 against a theoretical x1.9), not an inequality.

---

## v175 — the NG+ gear ladder was unreachable (audit CRITICAL, fixed)

`rift_armaments`, `verdigris_armaments`, `dissolution_armaments` and `caustic_armaments` were
authored in `research_manager.tech_tree`, wired into the Z12-Z15 gear gate, and **never added to a
research tab**. `research_page.graphs` is a second, hand-maintained list of which node ids each tab
renders; a tech in the tree but absent from that list is fully functional and completely
unclickable. **All 16 Z12-Z15 modules were uncraftable.**

`boss_gearcheck` never caught it because it grants research through the manager
(`_unlock_research`), not through the UI — so its "15/15" for the NG+ bosses was measured with the
four techs force-granted. The harness was testing a game the player could not reach.

**Fix, two parts:**

1. The four ids appended to the `"Warp Tech"` tab in `research_page.gd`. Each keeps its own
   `requires_flag` (`z12..z15_unlocked`), so they reveal one sector at a time rather than all at
   once — verified, not assumed (see the leak guard below).
2. `parent` set on the five ladder links (`corrosion -> rift -> verdigris -> dissolution ->
   caustic`), which were all `parent: null`. `can_unlock()` checks `parent` and `req_tech`
   identically against `unlocked_techs`, so setting `parent := req_tech` leaves gating
   **bit-identical** and only adds the connecting line — the tab rendered as six floating roots
   before. `cryo_armaments` keeps `parent: null` because its prereq lives in another tab, and
   `research_page`'s own v145 note records that a cross-tab parent cannot draw a line.

**Measured after the fix** (`tech_reachable_check`): 109/109 techs reachable, and the ladder walks
end to end — each tech unlocks when its flag lands, and 3/1/4/4/4/4 = **20 gated modules become
craftable**, the 16 stranded ones among them.

### Guard

`scenes/tech_reachable_check.tscn` reconciles the two lists that drifted, in both directions:
every `tech_tree` id appears in exactly one tab; every tab id exists in the tree; nothing is listed
twice; and the ladder is walked as a player would — grant the sector flag, unlock, confirm the
gated modules flip to craftable. It also asserts each rung stays **locked while its flag is false**,
so the fix cannot leak the NG+ ladder into a pre-warp game.

Both halves were negative-controlled: the reachability check was seen red on the real bug before
the fix, and the leak guard was deliberately broken (flag forced true during the must-be-locked
phase), seen red for the stated reason on all six rungs, and restored.

Cross-tab `parent` values are reported but **do not fail** the guard — ten pre-existing cases exist
(`industrial_logistics`/`basic_engineering`, `energy_shields`/`basic_engineering`, ...) and they are
cosmetic: the node is still clickable, it just draws no line. Failing on them would hand the repo
another permanently-red guard, which is exactly how `phase_gate_spike` stopped being read.

### Note for whoever builds the next probe

`can_unlock()` checks **affordability before it checks any gate**, so an unfunded probe gets `false`
for every tech and reads it as "locked". The first version of this walk reported all six rungs
broken, including the two that already shipped working. The probe now bankrolls itself, verifies the
funding landed, and on failure names which of the seven conditions actually bit.

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

**Added v175.** Boot: `powershell -NoProfile -File tools/boot_check.ps1` (never hand-grep).
Guards: `chain_supply_check` (a beat may not demand a drop you cannot farm yet — transitive
producer resolver), `tech_reachable_check` (every tech clickable in a tab), `recipe_speed_check`,
`bounty_warp_check`, `slot_claim_check`, `mission_i18n_check` (locale-tr sweep with a canary),
`guidance_order_check`, `z1_boss_tune`.
Tuning probes, all reusable: `ng_hp_sweep` (`--eid= --trials= --mults= --amults=`, 1D or 2D
atk×hp grid, reports death RATE), `nogain_diag` (affix/core decomposition), `z14_boss_sweep`,
`ngplus_gate_diag` (dumps a built NG+ kit), `z4_block_diag` (death rate for a clean common set).

## Standing constraints (still in force)
Internal `"credits"` key never renamed (Liras = display only) · commit/push only when asked ·
batteries destructible in real game (sim-only protection OK) · no save reset (migrate) ·
premium paid, zero F2P-isms/FOMO · prestige cadence long.
