# Zone Tier-Gate — Sector Hardening & the Salvage→Forge Spine — design doc v0.1

**Status:** Spec LOCKED. **BUILT & sim-verified END-TO-END** (2026-06-18) — `phase_gate_spike.gd` (+32 tier-gate asserts, ALL PASS) + full headless boot clean (exit 0). Shipped: **engine** (`tier_hardened` floor — per-weapon offense + armor/shield defense factor; position-derived front/back split; module-loot routing; new-game-only `tier_gate_enabled` flag with old-save ungate migration; combat-log telegraphs), **content** (2 minted raws + 9 alloys in `element_db`; 9 refine recipes in `processing_manager`; flag-gated alloy injection into Z2-Z10 common costs via `shipyard_manager.get_effective_module_cost`; minted-raw front-half drops), **UI** (pre-fight ⚠ HARDENED card badge + effective-cost display). Z9 RegenPlating chain confirmed reachable (no deadlock). **REMAINING = tuning only** — per-zone refine ratios / signature drop rates to the ~4-6 min beat (Z7/Z8 still 1-2/kill; the deep Z9 chain), the z3/z4 "Cryo" display-name cleanup, and the `release/v0.2.0` gameplay port. Numbers marked *(tune)* below are the sim/playtest knobs, never the design itself.

**Player fantasy:** *Every sector's apex predators are armored against yesterday's technology. You strip the frontier's wrecks for its signature alloy, forge gear rated for this depth, and only then punch through to the prizes in the deep end.*

**Loop served:** **Core** (combat progression cadence) + **Meta** (it makes the processing/crafting chain mandatory, not optional). Not prestige — this is the Z2–Z10 mainline.

**Subsystems touched** (`docs/audit/SUBSYSTEM_MATRIX.md`): `combat_manager` (enemy defs, `resolve_damage`, `spawn_enemy`, loot routing), `shipyard_manager` (common recipes, module-tier/rarity lookup, combat-entry defensive recalc), `processing_manager` (refine recipes), `element_db` (signature materials), `research_manager` (no new gates — rides existing `zone_N_access`), UI (`combat_page` enemy cards + combat log), save (`game_state` new-game flag).

**Why it exists:** the loot curve makes Zone N Rare+ drops out-stat Zone N+1 **Common/Uncommon** crafts (Rare 2.30–2.65× base vs next-Common 2.20×; the code comment literally reads *"beats next zone Common"*). So a player arriving at N+1 with carry-over drops never crafts the N+1 commons — they're **dominated, dead content**, and the gather→process→craft (engineer) loop gets bypassed for every combat module. This gate makes the current-tier **common set mandatory to progress**, which (a) kills the dead-common problem and (b) converts the entire production chain into demand-driven supply. See the diagnosis thread in `CLAUDE.md` itemization notes.

---

## Structure — each zone is two stages, not a flat pool of 4

Every mainline zone (Z2–Z10) has 4 regulars + 1 boss. Split by enemy-array order:

- **Front half (e1, e2) — the salvage yard.** Killable with carried-over previous-zone Rare/Legendary gear. **Drop materials only** (no module rarity rolls) + the zone's **signature salvage component**. Fiction: damaged wrecks/drones you strip for parts.
- **Back half (e3, e4) — the apex threats.** `tier_hardened: Z`. Old gear is *floored* here (see below) — you must re-gear into the Zone Z common set. **Drop the Uncommon+ module ladder** (the real loot). Fiction: the intact predators your new cold-/rad-/etc-rated gear was built for.
- **Boss.** Also `tier_hardened: Z` (you have the set by now). Gates the next zone; drops the zone core (research) + enhanced rolls + Unique chances.
- **Z1 (Lunar Orbit): ungated.** Bootstrap — no carry-over to wall against; starter corvette + gathered-mat crafts clear it.
- **Z11+ : NOT tier-gated here.** The Threshold/Rift already gate on **damage type** (`warp_hardened`/Cryo, Corrosion) — an orthogonal axis. Do not double-gate; see `docs/NG_PLUS.md`.

### Per-zone enemy split (from `combat_manager.gd` zone defs)

| Zone | Sector | Front (e1, e2) — salvage | Back (e3, e4) — `tier_hardened` | Boss |
|---|---|---|---|---|
| Z2 | Asteroid Belt | pirate_skiff, silicate_golem | claim_jumper, ore_hauler | monolith |
| Z3 | Mars Debris Field | scavenger_mech, martian_sentry | salvage_swarm, derelict_frigate | warmaster |
| Z4 | Glacier Belt | ice_wraith, frost_sentinel | **frost_hulk, glacial_drone** | overseer |
| Z5 | Sector Alpha | xenon_scout, xenon_corvette | alien_frigate, alien_probe | harbinger |
| Z6 | Sector Beta | defense_turret, mining_golem | rad_beast, ore_guardian | colossus |
| Z7 | Sector Gamma | shard_swarm, energy_wraith | void_hunter, gamma_beast | sovereign |
| Z8 | Sector Delta | prism_drone, crystal_golem | void_stalker, nebula_phantom | warden |
| Z9 | Sector Zeta | plague_drone, bio_horror | rogue_ai, quarantine_mech | patient_zero |
| Z10 | Sector Epsilon | void_stalker, temporal_phantom | omega_sentinel, primordial_titan | leviathan |

---

## The floor — `tier_hardened`

A sibling of `warp_hardened` (Z11), tier-keyed and applied to **both** damage directions, **per module**.

```
TIER_FLOOR = 0.02          # 2% — distinct constant from warp_hardened (0.02) so they can diverge

# A player module's combat contribution is floored to ×TIER_FLOOR UNLESS:
#   module_tier >= Z                                  # the craft path: tier-Z common pierces
#   OR (module_rarity == Unique AND module_tier == Z-1)   # the jackpot, one zone only
# where Z = enemy.tier_hardened, module_tier = module's `zone` field (cryo_lance: power_tier).
```

- **Offense:** a sub-tier **weapon** deals ×0.02 damage → effectively can't kill → retreat, no harm. (Extend the existing `warp_hardened` branch in `resolve_damage`, per-weapon.)
- **Defense:** a sub-tier **armor/shield** provides ×0.02 of its mitigation / pool → hits land near-full → you get *driven off* (no permadeath; you lose the encounter).

**Why 0.02 and not a soft 0.10:** in an idle game **time is free** — any floor leaving non-trivial DPS is AFK-brute-forceable. 0.02, with tier-scaled enemy HP + any regen, makes effective TTK unbounded. It's a true wall, and it reads as *"wrong tier gear,"* not *"grind harder."*

**Per-module = graduated, not a one-shot.** Upgrade the weapon but forget the armor → you deal damage yet stay fragile, not instantly deleted. Only a *fully* sub-tier kit melts. Partial progress feels partial; full re-gear feels complete.

### Gated slots: **weapon, armor, shield** (three pillars: deal / reduce / absorb)

| Slot | Gated? | Rationale |
|---|---|---|
| Weapon | ✅ offense floor | the core "can you damage them" |
| Armor | ✅ defense floor | damage reduction |
| Shield | ✅ defense floor | shield pool/regen — armor vs shield mitigate different damage types, so you still *choose* (build expression, not a leak) |
| Battery | ❌ exempt | already gated by the v110 energy budget; a sub-tier battery can't power the bigger hull anyway |
| Engine | ❌ ungated | evasion is a secondary lever; gating it adds telegraph noise + pushes re-gear from 3 crafts toward 5 (slog) |
| Sensor | ❌ ungated | accuracy is deliberately de-emphasized; same slog argument. Stays an optional convenience craft |

So the wall checks exactly: **can you damage them (weapon tier) and survive them (armor + shield tier).**

---

## The Unique skip-key — one zone only

A Zone N **Unique** (`tier == Z-1`) pierces Zone N+1's wall — the jackpot's reward is skipping one craft gate.

- Because gating is **per-module per-slot**, a *partial* Unique haul only covers its own slots (Unique weapon → you damage them, but sub-tier armor still gets you shredded). To **fully** skip the N+1 craft you need a Unique in **every** combat slot — a full Zone N Unique **set** — which is exactly the jackpot rarity that earns it. The "set" requirement enforces itself.
- At **Zone N+2** the same Unique is `tier == Z-2` → floored. It retires on schedule — which also caps the Unique's raw-stat leapfrog that would otherwise create downstream dead content. It does **not** become trash: N+2's *front half* is ungated, so the Unique still facerolls e1/e2 there; it only loses its back-half skip privilege.
- Same combat-log telegraph applies when a beloved Unique finally floors at N+2, so it never reads as a bug.

---

## The recipe spine — salvage → refine → forge (the Satisfactory move)

Each zone gets a **named signature alloy with a short refine chain** — the per-zone "new content" discovery beat (Satisfactory tier-parts / Melvor next-tier bar). The alloy is the visible discovery; its *input* is the zone's signature material — often one you've been hoarding as junk (see the audit-locked table below) — so consuming it reads as *"so THAT's what these are for,"* not silent bookkeeping. The refine step is what pulls the **Processing skill** into mandatory demand — so combat **and** processing **and** crafting all converge on the wall-breaker. That is the "nothing goes to waste" payoff, delivered as a beat the player feels.

### Worked example — Glacier Belt (Z4), real current numbers

| Step | Recipe | Pulls in |
|---|---|---|
| 1. Strip the wrecks | front half (Ice Wraith, Frost Sentinel) drops **Rimeplate Scrap** *(new)* + existing Ti / Glacial Essence | combat |
| 2. Refine | `3 Rimeplate Scrap + 2 Glacial Essence → 1 Rime Alloy` *(tune)* | **Processing** |
| 3. Forge the set | re-point Z4 commons onto Rime Alloy | crafting |

Re-pointed Z4 common recipes (current → new; current costs from `shipyard_manager.gd`):

| Module | Current cost | New cost |
|---|---|---|
| Cryo Shield (`z4_shield`) | `Ti 40, AdvCircuit 8` | `Ti 40, AdvCircuit 8, + Rime Alloy ×6` *(tune)* |
| Stainless Armor (`z4_armor`) | `Steel 60, Ti 20, GalvanizedSteel 10` | `…, + Rime Alloy ×8` *(tune)* |
| each Z4 weapon (`z4_kinetic/energy/missile`) | `~Ti/Steel/AdvCircuit` | `…, + Rime Alloy ×5` *(tune)* |

**Minutes-beat check (Z4, reference):** Rimeplate Scrap drops **~3/front-kill**, front enemy ~10 s TTK → ~18/min → **~6 Rime Alloy/min**. A wall-cracking *starter* set (2 weapons ×5 + armor ×8 + shield ×6 = **24 alloy**) ≈ **4 min** of front-farming; then the back half drops the rest. Every other zone scales drop-rate/ratio to hold this **~4–6 min** beat — sim-tuned, never hand-tuned.

Now the *only* path through the back-half wall is **front-farm → refine → forge**. Surplus past your set feeds the **Fleet** (glut sink) and **Reclamation Foundry** (E5). The gate is the demand floor; Fleet/Foundry are the overflow valve.

### Signature inputs & alloys Z2–Z10 (LOCKED by the economy audit, 2026-06-18)

The audit (verified against `combat_manager` enemy defs, all module/processing/research/building costs) found the deadest revive targets and reshaped the plan: **7 of 9 zones already have a DEAD/THIN material dropping from the front half**, so the signature *input is that material* (reviving it) and only the **alloy** is minted. **Z4 and Z10 mint a new raw** (no dead material fits — Z4's CryoEssence chain dead-ends; all Z10 raws are healthy). This turns junk into the progression key *and* gives the old demand-breadth pass the durable craft demand it lacked (those mats had only one-time research gates).

| Zone | Signature input (front-half) | Refine: input + co-input → | Alloy *(new, named)* | Revives |
|---|---|---|---|---|
| Z2 | **PirateSalvage** (THIN) | + Circuit | **Chondrite Alloy** | PirateSalvage |
| Z3 | **MartianRelics** (THIN) | + Steel | **Wreckforged Alloy** | MartianRelics *(CoolantCell alt)* |
| Z4 | **Rimeplate Scrap** *(mint raw)* | + Glacial Essence | **Rime Alloy** | — *(worked example)* |
| Z5 | **XenoFragment** (THIN) | + AdvCircuit | **Xenoforged Alloy** | XenoFragment |
| Z6 | **ColonySalvage** (THIN, e1) | + Superalloy | **Colony-Forged Alloy** | ColonySalvage |
| Z7 | **ExoticIsotope** (DEAD, e1) | + VoidCrystal | **Gamma Alloy** | ExoticIsotope ⭐ |
| Z8 | **AntimatterParticle** (DEAD, e2) | + VoidCrystal | **Prismatic Alloy** | AntimatterParticle ⭐ *(deadest in game)* |
| Z9 | **BiohazardSample** (HEALTHY — ok to reuse) | + **RegenPlating** (DEAD) | **Bioforged Alloy** | RegenPlating |
| Z10 | **Aeon Residuum** *(mint raw)* | + VoidEssence | **Aeon Alloy** | — *(all Z10 raws healthy)* |

⭐ = the audit's top revive candidates (zero / near-zero current consumers). **New items: 2 raws (Z4, Z10) + 9 alloys = 11**, down from the 18 a per-zone-raw plan would cost. You hold only the current zone's input+alloy at a time; surplus → Foundry/Fleet.

**Signature drop rate:** when a material becomes a zone's signature input, its front-half drop is set to **~3–6/kill** (the front half no longer rolls modules, freeing drop budget) — e.g. ExoticIsotope/AntimatterParticle move from their current 1–2 to ~3–6, which also amplifies the revival. Two supply caveats to verify at build: **Z6 ColonySalvage** is e1-only (bump its rate), and **Z9 RegenPlating** is a deep-craft output — confirm its own chain is reachable so it doesn't become a deadlock co-input.

---

## Failure modes (how this could feel bad — and the guard)

1. **"My stronger Legendary does chip damage."** → **Telegraph hard.** Pre-fight **lock badge** on e3/e4 cards ("Requires Zone N armaments") so the player never *enters* blind; **combat-log line** on floored hits ("ARMOR TOO DENSE — Zone N grade required"). This is mandatory, not polish.
2. **Gate fatigue** (every zone is the same lock-and-key). → The **named signature component per zone** gives each wall distinct flavor even though the mechanic is identical (Satisfactory ships the same loop 8 tiers and it stays satisfying). Idle/incremental players *expect* gates; the flavor is the variety.
3. **Re-gear slog** (front-farm too slow to afford the set). → Tune front-half drop-rate × recipe cost to a **minutes** beat; the front-farm-to-full-set time must stay *under* the back-half clear it unlocks. Hard cap if needed.
4. **Progression deadlock** (a common recipe needs an unreachable material). Now *critical* — the set is mandatory, so an unsourceable input = an unbeatable zone. → Every common recipe must be satisfiable with what's reachable on arrival; runs through the existing deadlock audit.
5. **Defense one-shot frustration.** → Per-module *graduated* floor (only a fully sub-tier kit melts) + no permadeath (lose the encounter, retreat). A fast loss with a clear badge reads as "wrong gear," not "unfair."
6. **Unique "expiry" feels bad at N+2.** → It still facerolls unwalled front-half content; it's framed/telegraphed as "it bought you a free zone," not "it broke."
7. **Inventory clutter** from ~9 new raws. → 1 per zone, held only while you work that zone, surplus auto-flows to Foundry/Fleet. Slot pressure is an intentional sink.

---

## Rollout — **new-game-only** (flag-gated)

- New game sets `game_settings["tier_gate_enabled"] = true`. The floor logic **and** the front/back loot split both check this flag.
- **Existing saves load with the flag absent/false → ungated**, playing exactly as before. No re-walling of already-cleared zones (matches the v110 "New Game for clean state" migration philosophy).
- The `tier_hardened` data lives on the enemy defs always; the *floor* only fires when the flag is on. No save-shape change beyond the one boolean (still add it to `save_game`/`migrate_save` for cleanliness).
- **Branch rule:** this is gameplay → ships to **both** `MissionFlow` and the release branch; only debug differs between branches.

---

## Implementation checklist + gotchas

- [ ] Add `tier_hardened: Z` to **e3, e4, and boss** defs for Z2–Z10. Add `drops_modules: false` to e1, e2 (front-half = materials + signature raw only); e3/e4/boss keep module rolls.
- [ ] **⚠ `spawn_enemy` MUST copy `tier_hardened` (and `drops_modules`) into `current_enemy`.** This is the exact gotcha that left `warp_hardened`/`resist_cryo`/`phases` dead until copied — the gate is a no-op without it.
- [ ] `resolve_damage`: extend the `warp_hardened` branch — per-weapon, floor to `TIER_FLOOR` unless the pierce test passes. Needs a `get_module_tier(id)` + rarity lookup helper (module `zone` field; `cryo_lance` → `power_tier`).
- [ ] **Defense:** on combat entry vs a `tier_hardened` enemy (gate on), do a **filtered recalc** — recompute effective armor/shield counting each defensive module at full only if it passes the pierce test, else ×`TIER_FLOOR`. (`recalc_stats` aggregates totals and can't decompose per-hit, so compute the floored defensive profile once at entry.)
- [ ] `tier_hardened` is orthogonal to HP/ATK scaling — no zone-steepening exemption needed (unlike `warp_hardened`, where base≈effective mattered for binary tuning).
- [ ] Loot routing: front-half → materials + signature raw, no rarity roll; back-half/boss → existing Uncommon+ roll.
- [ ] `element_db`: register the **2 minted raws** (Rimeplate Scrap, Aeon Residuum) + the **9 alloys** (display names, endgame/material categories). The 7 revived inputs already exist.
- [ ] `processing_manager`: add the refine recipe per zone (signature input + co-input → alloy) per the **locked table** — inputs and revive targets are fixed, not a build-time choice.
- [ ] `shipyard_manager`: re-point each Z2–Z10 **weapon/armor/shield** common recipe to require the refined intermediate.
- [ ] `game_state`: `tier_gate_enabled` flag (new game = true), save/migrate, hard-reset behaviour.
- [ ] UI: e3/e4 pre-fight **lock badge** + combat-log floored-hit message (`combat_page`).
- [ ] **Naming cleanup** (related confusion the user already flagged): `z3_energy` "Cryo Beam", `z4_shield` "Cryo Shield", `z4_engine` "Cryo-Pulse Drive" still carry "Cryo" — collides with the *actual* Cryo (warp-breach) damage type **and** the Z4→Glacier/Frost re-theme. Rename to Frost/Rime/Glacial.
- [ ] **Verify via FULL HEADLESS BOOT** (`Godot_console.exe --headless --quit-after 18`), not `--check-only` (syntax-only). Grep `SCRIPT ERROR|not declared|Nonexistent function|Cannot infer`.
- [ ] Extend `scripts/sim/phase_gate_spike.gd` (MissionFlow) with tier-gate asserts: floor applies sub-tier, common pierces, Unique-Z−1 pierces / Z−2 floors, front-half drops no modules, `spawn_enemy` copies the flag.

---

## Locked by the economy audit (2026-06-18) & what remains

**Locked:** revive target + signature input + alloy name per zone (table above); front-half signature drop **~3–6/kill**; Z4 reference ratio (`3 Rimeplate Scrap + 2 Glacial Essence → 1 Rime Alloy`; recipes **+5** weapon / **+8** armor / **+6** shield; **~4-min** starter-set beat); telegraph copy (below). Z10 raw named **Aeon Residuum** (avoids the PrimordialShard clash).

**Telegraph copy (locked):**
- e3/e4 pre-fight card badge: **`⚠ HARDENED`** — subtext *"Shrugs off outdated equipment — requires Sector N-grade weapon, armor & shield."*
- Combat log, offense floored (per weapon, throttled): **`HARDENED HULL — Sector N armaments required.`**
- Combat log, defense floored: **`ARMOR OUTCLASSED — Sector N plating required.`**

**Remaining (sim/playtest — NOT blocking build):**
- Per-zone refine ratios + recipe alloy-quantities scaled to hold the **~4–6 min** beat at each tier (Z4 is the reference; others scale by drop rate). Sim-tune against the TTK harness, never hand-tune.
- **Z6 supply check:** ColonySalvage is e1-only (5–12/kill) — verify/raise front-farm throughput before locking its ratio.
- **Z9 deadlock check:** confirm RegenPlating's own craft chain is reachable when used as a Z9 co-input.
- **Pre-existing bug to sweep in the same deadlock audit:** `MutatedTissue` is a bounty/quest *delivery target with no drop source* (`bounty_manager.gd:28`, `quest_manager.gd:22`) — players can never fill those contracts. Independent of this design, but fix it while the deadlock audit is open.
