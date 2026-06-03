# Stellar Forge (mobile) vs. horizonidle-godot — System Comparison

Fresh system-by-system comparison of the mobile port (`scripts/core/game_state.gd`,
`game_data.gd`, `ui/main.gd`) against the desktop original
(`/tmp/horizonidle`, 11 managers + core + ~38 UI scripts).

Legend: ✅ faithful (logic matches) · 🟇 present but simplified/different · ❌ missing.

---

## A. Content (data) — ✅ 1:1
Materials (178), gather actions (20), recipes (91), research nodes (106),
enemies (56), zones (10), buildings (71), hulls (5), modules (72), sets (10),
gems (12), consumables (10), missions (43) — all generated 1:1 from source.

---

## B. Systems that are faithful (✅)

| System | Notes |
|---|---|
| **Gathering YIELD** | `(1+lvl·0.01) × 1.10(milestone10) × efficiency(2–32×) × warp × (1+extractor affix)` + flat `gathering_yield` research bonus — matches `get_yield_multiplier`. |
| **Research effects** | Efficiency I–V (2/4/8/16/32×), `get_efficiency_bonus` keys (combat_xp, shield_regen, max_hp_mult, attack_speed, processing_speed, gathering_yield, research industrial), hub passives, auto-repair thresholds (20/40/60/80%). |
| **Combat model** | kinetic/energy/explosive vs shield (`0.5/1.5/1.1`) then armor (`k=max(20,diff·50)`, type splits 100/70/20%), accuracy/evasion, crit, heat/overheat/vent, shield regen, ammo per shot. |
| **Unique-module effects** | Warp Stabilizer, Broadside, Plasma Overcharger, Reactive Armor, Exotic Shield Matrix, Reflective Sheath, Chrono, static/void affixes, capacitor/nanite on kill. |
| **Rarity / affixes / gem sockets / set bonuses** | Rarity roll, affix DB + roll ranges, sockets by rarity, 3 coded set bonuses, zone-scaled drop stats. |
| **Shipyard stat aggregation** | hull+modules × Engineering skill (`1+lvl·0.01`) × gems × sets × affixes; energy_cap with `applied_physics`. |
| **Warp / prestige** | shards `floor(log2(score/500k))+1`, tier `total/5`, mults `(1+shards·k)·2^tier` (k=.02/.03/.015/.025), keeps 30% XP (70% decay). |
| **Bounty board** | hunt/elite/delivery, difficulty scaling, refresh, rolled-module reward, elite-forcing. |
| **Missions** | 43-mission chain, event tracking + `_mission_sync` retroactive reconcile (research/gather/craft/build/construct). |
| **Infrastructure core** | energy gen/cons, count-scaled cost (1.15→1.24→1.32 tiers), per-building throttle, global `yield_bonus`, Engineering log-yield scaling on auto_smelter/hydro/centrifuge/munitions. |
| **Zone research-gating** | zones require `research_req`, locked sectors blocked. |
| **Repair model** | flat per-hull cost × damage ratio; defeat charges fee; no passive regen. |

---

## C. Systems present but DIFFERENT (🟇) — *behavioral divergences*

| System | Original | Mobile (current) | Impact |
|---|---|---|---|
| **XP / level curve** | RuneScape-style table, **cap 99**, milestones [10/25/50/75]. | `40·(lvl-1)^1.6`, **no cap**. | Levels scale differently; skill thresholds reached at different rates. |
| **Gathering SPEED** | `base + Σ per-action techs (diamond/ultrasonic/plasma_bore, high_flow/superfluid/hydro, laser/mono/molecular, magnetic_funnels +0.25–0.75) × warp gathering mult`, + Biosphere +5%/bldg. | **Raw duration only** — no speed scaling at all. | Mobile gathering is much slower late-game; those speed research nodes do nothing. |
| **Processing SPEED** | `1 + lvl·0.01 + recipe-techs(+0.25–0.75) + research(.45) + buildings(fabricator/catalyst +.60) + industrial_logistics + refinery_link` × `1.10(m10) × 1.11(m25)`. | `1 + refinery_link + research processing_speed`. | Missing skill-level, recipe-specific techs, building speed bonuses, processing milestones. |
| **Processing special outputs** | oxygen_blast_furnace ×5 Steel, milestone-50 5% double-output, `scrap_rolls` extra rolls. | none. | A few recipes yield less than original. |
| **Combat milestones** | +5% crit @ L10, +15 eva @ L25, +25% vent @ L75 (auto-consume unlock @ L50). | dmg `+0.5%/lvl` and HP `+20/lvl` present; **crit/eva/vent milestones absent**. | Slightly weaker high-combat-level survivability. |
| **Energy grid** | battery **stores** surplus and **drains** to cover deficits; fuel generators ignore efficiency and run to jumpstart. | simple `eff = gen/cons` when in deficit, applied to all production; **no battery, no fuel priority**. | No energy banking; deficit behaviour is cruder. |
| **Offline progress** | gathering + processing + **infrastructure** + research + fleet (+combat if toggled), cinematic modal. | **only the single active task** (gather/craft/research/combat); plain text banner. | **Buildings earn nothing while the app is closed**; combat always runs offline (no toggle). |

---

## D. Systems MISSING entirely (❌)

| System | What it is in the original | Status |
|---|---|---|
| **Atlas / Encyclopedia** | Full materials+enemies codex: every item's sources & uses across all managers, net-growth/min, enemy intel with drop pools & lock states. | Not ported. (Mobile shows stats on the combat card only.) |
| **Storage slot cap + upgrade** | 28-slot cap; new materials beyond cap are dropped; buy `+1 slot` for `1000·1.5^n` credits. | Not ported — mobile storage is **unlimited**, no upgrade sink. |
| **Repeatable / Recursion research** | `production_focus` / `combat_focus` / `gathering_focus`: infinite +5%/level, cost `base·1.3^lvl` / items `·1.2^lvl`. The 4th research tab. | Not ported (dropped the Recursion tab; nodes aren't in the tech tree). |
| **Fleet** | 5 expedition types, deploy hulls to passive-income missions, risk/damage/repair, Administration skill. | **Intentionally removed by owner.** Research nodes `fleet_logistics_1/2`, `automated_expeditions` are now orphaned (purchasable, no effect). |
| **Grid-overload enforcement** | Equipping a module that exceeds energy capacity is **blocked** (with battery-upgrade exceptions). | Mobile tracks `energy_load`/`energy_cap` but **never blocks** equipping. |
| **Building special effects** | Drone Recovery Bay (25% passive gather roll), Crew Quarters (+10% XP/bldg), Biosphere Dome (+5% gather speed), infra-L10 (+10% generation). | None of these effects implemented (data exists, behaviour doesn't). |
| **Offline-combat toggle / Options page** | Options page with `offline_combat` switch + save/reset. | No options page; combat is **always** processed offline. |
| **Enemy "Intel" modal** | Tap enemy → modal with full drop pool + module variants + lock icons. | Card shows TARGET/SALVAGE only; no module-drop preview. |

---

## E. Equivalent / non-issues
- **Trophies** — the original defines trophy buffs but **nothing awards them** (no award site); mobile omits them. Functionally identical (both unobtainable).
- **Module crafting** = buy-with-materials (same as original `craft_module`).
- **Gem source** = combat drops (original has no gem-synth recipe).

---

## F. Suggested priority if closing gaps
1. **Offline infrastructure catch-up** — biggest felt gap for an idle game (buildings idle while closed).
2. **Gathering & processing SPEED scaling** — makes the speed research/building nodes meaningful again.
3. **Storage cap + upgrade** — restores an economy sink (or leave unlimited as a deliberate mobile QoL choice).
4. **Repeatable/Recursion research tab** — endgame infinite sink.
5. **Atlas/Encyclopedia** — large UI feature; high effort, medium value on mobile.
6. Combat milestones, grid-overload enforcement, building special effects — small correctness fixes.
7. Decide on **XP curve**: match the original 99-cap table, or keep the mobile curve deliberately.
