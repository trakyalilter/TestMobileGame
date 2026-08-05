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

## C. Systems formerly DIVERGENT — now fixed to match the original (✅)

All of the behavioural divergences below have been brought in line with the
desktop game (verified headless):

| System | Now matches original |
|---|---|
| **XP / level curve** | RuneScape-style table `floor(l + boost + 300·2^(l/7))/4` (boost +200 for l<20), **cap 99**. |
| **Gathering SPEED** | `(1 + Σ per-action techs: diamond/ultrasonic/plasma_bore, high_flow/superfluid/hydro, laser/mono/molecular +0.25–0.75) × warp gathering mult`; warp moved out of yield into speed. *(Biosphere +5%/bldg still pending — building special effect, §D.)* |
| **Processing SPEED** | `1 + fab·0.01 + recipe-techs + research(processing_speed) + industrial_logistics + refinery_link + buildings(fabricator .20 / catalyst .25 / silver .15)` × `1.10(m10) × 1.11(m25)`. |
| **Processing outputs** | Efficiency multiplier (2–32×) now applied to craft outputs **and** bonus rolls; oxygen_blast_furnace ×5 Steel; milestone-50 5% double; `scrap_rolls` extra rolls. |
| **Combat milestones** | +5% crit @ L10, +15 eva @ L25, +25% vent @ L75, auto-consume gated @ L50. |
| **Energy grid** | grid battery (capacity = ship energy_cap) banks surplus and drains to cover deficits; fuel generators run at 100% to jumpstart (fractional fuel draw); milestone-10 +10% generation. |
| **Offline progress** | infrastructure offline catch-up is battery-aware and grants Infra XP + a loot summary in the away report. |

> Note: the earlier claim that "buildings earn nothing while closed" was
> incorrect — offline infra was already credited via `_offline_infra` at load;
> it is now battery/fuel-accurate and reported.

---

## D. Systems MISSING entirely

### ✅ Now implemented
| System | What it is | Notes |
|---|---|---|
| **Storage slot cap + upgrade** | 28-slot cap, new materials dropped when full, Expand Storage at `1000·1.5^n`. | Storage page shows used/max + upgrade button; persists through prestige. |
| **Repeatable / Recursion research** | `production_focus`/`combat_focus`/`gathering_focus`, +5%/level, cost `base·1.3^lvl` / items `·1.2^lvl`. | New **Recursion** tab; bonuses wired to processing speed / ship damage / gather yield. |
| **Grid-overload enforcement** | Equip blocked if energy load > capacity, unless the module adds capacity (battery anti-softlock). | Ship page shows live grid load/capacity + rejection notice. |
| **Building special effects** | Drone Bay 25% passive gather, Crew Quarters +10% XP/bldg, Biosphere +5% gather speed, infra-L10 +10% gen. | All wired (online + offline); upkeep consumers (Crew Quarters Food) now consume input. |
| **Atlas / Codex** | Materials codex (per-item sources & uses across all systems) + enemies grouped by zone. | New **Atlas** page under More. |
| **Enemy "Intel" modal** | Full stats, guaranteed/rare drops, and module drop pool with lock icons. | ⓘ button on every enemy card (combat + atlas). |
| **Options: offline-combat toggle** | Process combat while away (off by default, like desktop). | Toggle in Storage & Crew → System; saved. |

### ❌ Still missing
| System | What it is in the original | Status |
|---|---|---|
| **Fleet** | Expedition passive-income system. | **Intentionally removed by owner**; `fleet_logistics_*`/`automated_expeditions` nodes orphaned. |

> The only "missing" system left is **Fleet**, which the owner deliberately
> removed from the game.

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

---

## E. 2026-08-05 four-agent parity audit vs MissionFlow refs (tools/ref_*.gd)

### Fixed in this pass (version-independent bugs)
- Craft recipes with credit costs/outputs now use the WALLET (were phantom
  `resources["credits"]` stacks); credit outputs are flat (no efficiency/m50).
- Offline gathering now applies flat `gathering_yield` bonuses (+research/spine).
- `void_weaponry_1` (+5% dmg) and `void_shielding_1` (+5% shield) now consumed.
- Removed dead crew_quarters XP term (building exists in no data source).
- gather_multi missions lock in per-material high-water progress (desktop
  parity; spending before claiming no longer regresses m005/m012/m024b).
- Standing-order tier-9 material reward: Neutronium → MutatedTissue (ref).
- Mastery toasts: one-time MASTERY UNLOCKED intro + per-milestone celebrate.
- Unique modules (rarity 4) can no longer be equipped twice.
- repair_hull blocked during combat (desktop rule).
- Cryo Shard Pistol re-granted on EVERY warp when unowned (was first warp only).
- Matrix Synthesis + gem fusion recipes now purchasable (Cores/Fusion shop
  tabs) and actually roll/fuse gem resources (were dead data).

### Open items needing MissionFlow-branch adjudication (refs are v110-111 for
### some managers; desktop target is v135a — cannot confirm from this repo)
- Research finite-tech material costs: ref applies ×2 MATERIAL_MULTIPLIER at
  unlock; mobile spends raw values (half price). Repeatables match exactly.
- Zone-gate research costs 4-10 far below ref (v109-era numbers); also
  quantum_dynamics / perfect_automation / shipwright_2 credits 950k vs 1M.
- Warp tree v2 divergences: E1 flat +1 vs ×1.10; E2 −15% vs −10%; C1 +15% vs
  +10%; C3/C4 costs 5/6 vs 3/5; C5 Cryo Overcharge (+50% cryo) missing.
- Combat economy: defeat credit tax (ref charges full repair), module
  destruction on defeat (ref 1/6 + 10-50% durability), consumable CD 10s vs
  1.5s, Coolant Flush + Nanite HoT consumables missing.
- Loot: weighted base pick (battery weight 0 on desktop), rare-loot rows
  inflated by loot multiplier, elite rarity odds 15/35 vs 4/26, extra 8%
  set-piece roll, set pieces 3 sockets no affixes vs 4-affix uniques.
- Mobile-only combat formula changes: resist amplification ×1.78 cap 0.80,
  ARMOR_K_FLOOR, comp multiplier extras (fab level + attack_speed research).
- Infra: non-passive cost curve (1.12/1.08/1.05, cap ×5) missing; buy
  multiplier missing; grid buffer = ship energy_cap vs desktop 1M kJ; warp
  mult applied to yield not interval; claim-all for standing orders missing.
- Trophy buffs: all trophies inert on mobile — desktop buff keys exist
  (mining_yield, gathering_xp, processing_xp, infrastructure_yield,
  kinetic/energy_dmg, evasion, ship_speed, research_speed) but the
  trophy→buff mapping lives in desktop bounty_manager (not vendored).
- Phase-19 unique modules (reflective_sheath etc.): combat hooks live,
  module defs absent from data — unobtainable.
- Boss stats: VERIFIED correct vs v135a enemies.json (ref enemy_db is stale
  v111 tuning — not a gap).
