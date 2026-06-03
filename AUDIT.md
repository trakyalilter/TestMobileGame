# Stellar Forge (mobile) vs. horizonidle-godot — System-by-System Audit

Comparison of the mobile port against the original desktop game.
Legend: ✅ faithful (1:1 logic) · 🟡 faithful core, minor gaps · ❌ not ported.

## Content (data ported 1:1 from the source)
| Data | Count | Status |
|---|---|---|
| Materials/elements | 178 | ✅ from `elements.json` |
| Gather actions | 20 | ✅ loot tables, xp, gates, categories |
| Processing recipes | 91 | ✅ inputs→outputs + bonus, 8 categories |
| Research nodes | 106 | ✅ parent chain, credit + item costs |
| Enemies / Zones | 56 / 10 | ✅ full combat stats + loot + drop pools |
| Buildings | 71 | ✅ energy, yields, intervals, gates |
| Hulls / Modules | 5 / 72 | ✅ |
| Set pieces / Gems / Consumables | 30 / 12 / 10 | ✅ |

## Mechanics (logic matched to original)
| System | Status | Notes |
|---|---|---|
| **Gathering** | ✅ | +1%/level, milestone-10 (+10%), **research Efficiency I–V (2×–32×)**, flat gathering-yield research bonus, warp + extractor affix — matches `get_yield_multiplier`. |
| **Processing / Crafting** | ✅ | Recipes + multi-output + bonus; speed via **research processing_speed** + Refinery-Link affix. |
| **Research tree** | ✅ | Unlock gating **and** the passive `get_efficiency_bonus` layer now applied (gather, processing/attack speed, shield regen, max-HP, combat XP, energy cap, industrial, rare-loot). |
| **Combat (real-time duel)** | ✅ | Weapon-slot firing, kinetic/energy/explosive vs shields→armor, accuracy/eva, crit, heat/overheat, shield regen; **research attack-speed / shield-regen / max-HP / combat-XP** wired; elites (random + bounty-forced). |
| **Hull / repair** | ✅ | **No passive regen** — repaired with credits (flat per-hull cost) or in-combat consumables/sets; defeat charges the repair fee. |
| **Auto-consumables** | ✅ | **Research-gated threshold** (Auto-Repair 20/40/60/80%), 1.5s cooldown. |
| **Ammo** | ✅ | Per-slot Slug/Cell/Missile, consumed per shot, tiered bonus. |
| **Module rarity + affixes** | ✅ | Rarity tiers, rolled stats (range × zone), 1–3 affixes, full AFFIX_DB across combat/industrial/economy, sell-by-rarity. |
| **Gem sockets** | 🟡 | Sockets on Rare/Leg/Unique; 12 cores with global mults. *Source:* gems drop from combat (original crafts via gem-synth). |
| **Set bonuses** | ✅ | 10 sets obtainable from themed bosses; 3 coded bonuses (Cryo slow, Sovereign reflect, Patient-Zero regen). |
| **Infrastructure** | 🟡 | Energy grid + efficiency, production, count-scaled cost, offline, **research industrial speed** wired. *Gap:* per-building throttle UI (engine ready). |
| **Bounty board** | ✅ | Hunt/elite/delivery, pool, refresh, difficulty scaling, **rolled module reward** on claim, elite-hunt forces elite spawn. |
| **Warp / Prestige** | ✅ | Shard formula (lifetime credits + buildings, log2), tier×2 multipliers, 30% XP-decay reset, research persists. |

## Newly ported
| System | Status | Notes |
|---|---|---|
| **Missions** | ✅ | 43-mission tutorial chain, event-tracked (gather/research/craft/construct/build/defeat), prestige-scaled credit rewards, auto-advancing chain. New Missions page. |
| **Unique-module effects** | ✅ | All 7 wired: Warp Stabilizer (+15% fire rate), Chrono Stabilizer (−20% enemy speed), Plasma Overcharger (2× energy), Reflective Sheath (20% reflect 50%), Reactive Armor (mitigation scales as hull drops), Exotic Shield Matrix (−30% in Sector Gamma), Broadside Array (20s kinetic salvo). |
| **Infrastructure throttle** | ✅ | Per-building throttle control (0–100%) added to the Build page. |

## Verified-absent / equivalent (faithful)
| Item | Why |
|---|---|
| **Trophies** | The `get_trophy_buff` reads Trophy_X items but **nothing in the source awards them** — they're unobtainable in the original too. Correctly absent. |
| **Module crafting** | Original `craft_module` pays the module's material cost — identical to the port's buy-with-materials. |
| **Gem source** | The source has **no gem-synth recipe**; gems come from drops — matched. |
| **Fleet** | Removed from the game by the owner. |

## Summary
Content is a 1:1 data port and **every system matches the original's logic** —
including the research passive-bonus layer, repair (no-free-regen) model,
research-gated auto-consume, gather-yield formula, bounty module rewards, the
mission chain, all unique-module combat effects, and per-building throttling. The
only things not present are features that are **also absent/unused in the source**
(Trophies) or already equivalent (module crafting, gem source).
</content>
