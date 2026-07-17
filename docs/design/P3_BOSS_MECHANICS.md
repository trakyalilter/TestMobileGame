# Boss Overhaul — traits + Rare gate + TTK curve (P3 v2, owner-approved 2026-07-17)

**Player fantasy:** every boss is a *puzzle you solve in the hangar* — read the threat card,
farm and refit the RIGHT gear, and watch your plan beat a monster that hard-walls the lazy
loadout.

**Owner decisions (locked):**
1. **The gear farm is the core mechanic.** Every boss (Z2+) requires **at least a full
   RARE set** to beat. Common/Uncommon = mathematically DNF — an honest wall, not a slow
   maybe. **Legendary/Unique are ACCELERATORS, never gates** — they make runs faster/easier.
2. **TTK envelope: 5–10 min with correct gear at late/post-late game (Z11, Z12, …).**
   Earlier bosses scale up to that: Z2–Z4 ≈ 2–4 min at Rare, Z5–Z7 ≈ 3–6, Z8–Z10 ≈ 4–8,
   Z11+ = 5–10. Legendary ≈ 30–45% faster; Unique faster still (affix ceilings).
3. **No bounty pity rule.** The v139 boards' Rare-floor claims are already the designed
   deterministic path to the Rare set (~4–6 contracts per zone ≈ 1.5–2.5h at-tier).
4. This OVERRIDES the historical tuning invariant "Uncommon beats mandatory bosses"
   (boss_threshold). All bosses, probes, and bot gear bars re-base to the Rare gate.

**Pacing consequence (accepted):** first warp projected ~day 4–6 at 1h/day (Rare set via
board + drops), vs the curve's ideal day 2–4 — the gear-farm-is-the-game trade. Measure
with the [FUN] runs after the retune; the rarity ladder IS the zone-transition clock
(docs/design/ZONE_PACING_CURVE.md).

---

## The trait kit (v2 — merged with external suggestions, all auto-battler-clean)

All traits are **data-driven fields on the enemy def**, resolve purely in math (no new
in-fight inputs — the existing consumable buttons are the only interactive counter),
must be **copied in spawn_enemy** (the resist_cryo lesson), telegraphed 3× (pre-fight
card chip, atlas line, plain-text combat-log line), and priced into the **offline** boss
model conservatively (offline may refuse fights online could win, never the reverse).

| Trait | Data shape | In-fight effect | The hangar ANSWER |
|---|---|---|---|
| **Enrage** (exists) | `enrage_at: 0.4, enrage_atk_mult: 1.4` | Below X% HP, ATK ×Y | Race it or armor through it |
| **Sustain family** | `sustain: {"kind": "pulse"\|"siphon"\|"nanite", ...}` | pulse: +pct max_shield every N s · siphon: each enemy hit steals player shield · nanite: below 30% HP, rapid hull regen for N s | Minimum-DPS threshold — out-damage the healing (weak-type Rare weapons) |
| **Reactive Armor** | `reactive_armor: {"per_hits": 25, "def_mult": 1.4, "cap": 2.8}` | DEF multiplies per N player hits | Heavy slow per-hit builds beat fast peashooters |
| **Adaptive Grid** | `adaptive_grid: {"per_hit_resist": 0.02, "cap": 0.5}` | Gains resistance to EACH damage type as it is hit by it (per-type, capped) | Hybrid loadout — split weapon types so the second type finishes what the first started |
| **Charge Nuke** | `charge_nuke: {"every_n": 5, "mult": 4.0}` | Every Nth attack telegraphs ("CHARGING MAIN CANNON") then hits ×M | Burst-EHP: size the shield buffer for the spike; active players may pop a shield consumable on the telegraph (existing button) |
| **Volatile Core** | `volatile: {"mult": 3.0}` | On death: one unmitigated burst = mult × boss ATK, resolved BEFORE victory — if it kills you, you lose | Anti-glass-cannon: keep an EHP floor even when overgeared |
| **Corrosive Field** | `corrosive_field: {"hull_dps_pct": 0.004}` | Constant hull DoT that bypasses shields, per second alive | DPS race + hull-repair consumables; punishes turtling |

**Evaluated and DEFERRED:** Drone Carrier / summoner (needs multi-entity combat + AoE
weapon stats — neither exists; a 1v1 target-swap abstraction is possible but is the
biggest lift of the set → park for the P2 sector-map era). EMP accuracy-drain aura
(stacking misses = maximum frustration per unit difficulty — corrosive field delivers the
same DPS-check without the feel-bad).

## Per-boss assignment (owner add: SOFT flavors start at Z1 — the very first boss
## already signals "these are not straightforward combats")

**Soft tier rule (Z1–Z2):** tutorial-grade numbers — the mechanic must be VISIBLE
(telegraph line, moving bar) but contribute ~zero kill risk at mission-directed gear.
They are diegetic signposts, not checks; the checks start at Z3.

| Z | Boss | Trait(s) | New lesson |
|---|---|---|---|
| 1 | The Architect | **SOFT Charge Nuke** every 4th/×1.75 ("CHARGING MAIN CANNON" telegraph) | "Watch the fight — bosses telegraph" (first boss ever; spike dents, never kills) |
| 2 | Silicate Monolith | **SOFT Sustain-pulse** 10s/+4% ("lattice re-crystallizes") | "Out-damage the healing" — at Uncommon the stalling shield bar EXPLAINS the Rare wall instead of a mute number check |
| 3 | Martian Warmaster | Enrage 0.35/×1.4 | "Finish fast or armor up" (first-warp boss, first REAL check) |
| 4 | Glacial Overseer | Sustain-pulse 8s/+6% | Pulse ESCALATION (intro'd softly at Z2) |
| 5 | Xenon Harbinger | Enrage 0.5/×1.5 | Escalation — earlier, harder |
| 6 | Beta Colossus | Reactive Armor 25/×1.4/cap×2.8 | "Attack speed isn't free — hit heavy" |
| 7 | Sovereign Prism | Sustain-siphon | "It eats your shields — out-sustain it" |
| 8 | Prismatic Warden | Charge Nuke 4th/×4 | The Z1 telegraph, now lethal — "survive the SPIKE" |
| 9 | Patient Zero | Corrosive Field + Enrage 0.4/×1.3 | First combo — DoT race under pressure |
| 10 | Void Leviathan | Adaptive Grid + Volatile | Capstone: hybrid build + EHP floor; primes Z11's "damage type is everything" break |
| 11+ | (existing warp-hardened/phases) | Layer traits in a later pass | TTKs re-checked vs the 5–10 min envelope (current 8.8–10.7 min → trim tails >10) |

## Rebalance methodology (the real project)

1. **Stat-budget table** per zone × rarity: expected player DPS/EHP with a full set at each
   rarity (weak-type weapons + armor/shield + kits) — derived from module stats × rarity
   multipliers (Rare / Legendary [1.40–2.00] / Unique [2.30–3.30]) × zone tier.
2. **Boss stats tuned WITH traits included** against the acceptance matrix:
   - Full Rare, weak-type: win rate ≥ 4/5, TTK inside the zone's envelope.
   - Full Uncommon: 0/5 — death or hard DNF (the v115 penetration wall must make this
     mathematical, not luck).
   - Full Legendary: ~30–45% faster than Rare (verify the accelerator promise).
3. **Per-boss probe gate:** boss_gearcheck matrix (Uncommon/Rare/Legendary rows) after each
   boss lands; funnel [FUN] run after each zone-band (Z3–4, Z5–7, Z8–10).
4. **Re-base the harness:** boss_threshold invariant flips to the Rare gate; player-bot
   `_boss_gear_ready` bar starts at Rare (2) for every boss (no Uncommon first bar);
   mission coaching texts say RARE (m030d etc.); bounty-board routing text stays.
5. **Gear-scaling touch-ups only if the matrix demands them** (owner: maybe per-zone and
   per-rarity scaling) — change module/rarity scaling AFTER measuring, not speculatively.

## Failure modes

- **Wall reads as unfair** → the wall must be TELEGRAPHED: pre-fight card shows the trait
  chip + a "RECOMMENDED: RARE" gear line; m030d-style mission text points at the board.
- **Volatile + auto-repeat combat** → on player death to the death-burst, do NOT auto-re-engage
  (loss handling as usual); offline model treats volatile as +EHP requirement.
- **Charge nuke + kits** → kitted big hulls may face-tank spikes (kit-dominance ceiling);
  if kitted-Rare face-tanks everything, raise nuke mult, not boss ATK.
- **Adaptive grid vs 3-slot hulls** → at destroyer (3 weapon slots) a 2+1 split must still
  clear Z10's envelope at Rare; verify explicitly.
- **First-warp cadence** → Z3's enrage is the gentlest CHECK number; funnel-verify rift
  timing after the Z3 retune (target ≤ day 6 at 1h/day).
- **Soft tier creep** → Z1/Z2 mechanics must never become the reason a mission-geared
  player loses (acceptance: Z1 boss win rate at crafted starter gear unchanged vs
  pre-trait baseline; Z2 at full Rare unchanged). If a soft number starts killing, cut
  the number, never the telegraph.

## Measured results (2026-07-17, commit e4a78bb — 9-trial acceptance matrix)

**Z1–Z11 all honor the rule** (`sim_out/bgc_hardgate.txt`): Common 0/9 everywhere
(L99–100%), Uncommon 0/9 at nine bosses, Rare wins everywhere, Legendary ~15–30% faster
as promised. Z12–Z15 rows are the known phased-probe blindness (ng_tune is the authority).

**The load-bearing discovery:** five soft-tuning iterations proved a stat-only Rare gate
unwinnable — affix RNG lets a god-rolled Uncommon set overlap a floor Rare set (Uncommon
leaks wobbled 0–6/9 between identical runs). A binary rule needs a binary mechanism:
**bosses take ×0.25 damage from sub-Rare weapons** (`BOSS_SUBRARE_DMG_FACTOR`, the
warp_hardened pattern applied to rarity; live path + offline model; trash ungated).
Second discovery en route: kits make survival near-infinite, so soft Uncommon-gating only
ever worked through LETHALITY (spikes/enrage/volatile), never HP/TTK stretch.

Tracked follow-ups:
- Z3/Z5 Rare comfort reads 4/9 (variance-dominated cells; true rate ~45–60%). Small hp
  trims are the lever if funnel data shows first-warp friction. Z2 (the mandatory m030d
  boss) reads 8/9 @5.1min.
- Z11 Rare-cryo 1/9 in the NO-WARP probe context — the warp-aware ng_tune pass owns
  Z11+ TTK/winrate calibration (player has warp mults there by definition).
- Two 1/9 Uncommon "wins" remain as ~20-min god-affix crawls (W1180/W1268, MAXT-bounded).
  Lower the factor to 0.20 if literal-zero is wanted at any cost.
- Funnel [FUN] re-measure pending (rift timing under the Rare gate + board-driven farming).

## Build order

1. Trait engine in combat_manager (7 blocks + spawn copy + log lines) — zero bosses use
   them yet; boot + spike-probe verified (zero balance impact).
2. Pre-fight card chips + atlas lines + "RECOMMENDED: RARE" gear hint.
3. Stat-budget table + retune Z2 (no trait, pure Rare-gate calibration boss) → Z3/Z4 (+
   traits) → probe gate → Z5–Z7 → Z8–Z10 → Z11+ TTK trim.
4. Harness re-base (threshold, bot bars, texts) alongside step 3's first pair.
5. Full matrix + funnel re-measure; update ZONE_PACING_CURVE.md results.
