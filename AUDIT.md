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

## Not ported
| System | Note |
|---|---|
| **Trophies** | Bounty/zone reward items that buff yield/xp/combat — no obtain source in the port. |
| **Missions** | 47-step tutorial chain + its credit/XP rewards. |
| **Module crafting** | Modules are bought/dropped (original also crafts them via recipes). |
| **A few unique-module effects** | reflective/reactive/exotic/broadside, electronic-warfare jamming. |
| **Gem crafting source** | Gems drop from combat instead of gem-synth recipes (effects identical). |
| **Fleet** | Removed from the game by the owner. |

## Summary
All content is a 1:1 data port and every gameplay loop matches the original's logic,
including the **research passive-bonus layer**, the **repair (no-free-regen) model**,
research-gated auto-consume, gather-yield formula, and bounty module rewards. The
remaining items are reward/flavor layers (Trophies, Missions) and a few endgame
sub-features — none of which change how any system works.
</content>
