# Stellar Forge (mobile) vs. horizonidle-godot — System-by-System Audit

Comparison of the mobile port against the original desktop game, system by system.
Legend: ✅ faithful · 🟡 faithful core, minor gaps · 🔶 partial · ❌ not ported.

## Content (data ported 1:1 from the source)
| Data | Original | Mobile | Status |
|---|---|---|---|
| Materials/elements | 174 | 178 (incl. ammo/gem/consumable ids) | ✅ names + sell values from `elements.json` |
| Gather actions | 20 | 20 | ✅ loot tables, xp, level/research gates, categories |
| Processing recipes | 91 | 91 | ✅ inputs→outputs + bonus rolls, 8 categories |
| Research nodes | 106 | 106 | ✅ parent chain, credit + item costs |
| Enemies | 56 | 56 | ✅ hp/atk/def/interval/accuracy/shield/eva/loot/drops |
| Zones | 10 | 10 | ✅ |
| Buildings | 71 | 71 | ✅ energy, yields, inputs, intervals, research gates |
| Hulls | 5 | 5 | ✅ slots, stats, costs |
| Modules (base) | 72 | 72 | ✅ |
| Set pieces / Gems / Consumables | yes | 30 / 12 / 10 | ✅ |

## Mechanics
| System | Status | Notes |
|---|---|---|
| **Gathering** | 🟡 | Action loop, loot, XP, gates faithful. Leveling curve adapted (+2%/lvl). **Missing:** per-action research speed upgrades (diamond drills etc.), skill milestones. |
| **Processing / Crafting** | 🟡 | Recipes, multi-output, bonus rolls, gates faithful. **Missing:** processing milestones. |
| **Research tree** | 🔶 | Unlock gating + credit/item costs faithful. **Missing: the passive efficiency-bonus layer** — in the original, researched nodes grant `get_efficiency_bonus(...)` boosts (gather yield, processing speed, attack speed, shield regen, max-HP, combat XP, industrial, research speed). The mobile tree **unlocks** content but does not yet apply those passive %s. |
| **Combat (real-time duel)** | 🟡 | Weapon-slot firing, kinetic/energy/explosive vs shields→armor, accuracy/evasion, crit, heat/overheat, shield regen, elites — all faithful. **Missing:** research combat bonuses (attack_speed, shield_regen, combat_xp, max_hp), jamming/electronic-warfare, broadside & a few unique non-set module effects, skill milestone crit/eva/heat. |
| **Ship Designer (hulls/modules/loadout)** | 🟡 | Buy/equip, ammo per slot, derived stats faithful. **Missing:** crafting modules via recipes (buy/drop only), credit repair-cost on combat loss. |
| **Module rarity + affixes** | ✅ | Rarity tiers, rolled stats (range × zone scaling), 1–3 affixes from slot pools, full AFFIX_DB wired into combat/industrial/economy, sell-by-rarity. |
| **Gem sockets** | 🟡 | Sockets on Rare/Legendary/Unique, 12 gem cores with global mults applied. **Difference:** gems drop from combat rather than the gem-synth crafting recipes. |
| **Set bonuses** | 🟡 | All 10 sets obtainable (drop from themed bosses); the **3 coded set bonuses** (Cryo-Lord slow, Sovereign reflect, Patient-Zero regen) are implemented. Other 7 sets are strong gear without a coded bonus (same as source). |
| **Infrastructure** | 🟡 | Energy grid + efficiency throttle, per-building production, count-scaled cost, offline, Engineering scaling — faithful. **Missing:** per-building throttle **UI** (engine supports it), `industrial_logistics` research bonus, crew-quarters XP, grid milestone. |
| **Bounty board** | 🟡 | Hunt/elite/delivery, pool, 8h + paid refresh, difficulty scaling — faithful. **Missing:** module rewards on claim (credits only), Trophy rewards. |
| **Warp / Prestige** | ✅ | Shard formula (lifetime credits + buildings, log2), tier×2 multipliers, reset with 30% XP decay, research persists. |

## Cross-cutting systems NOT yet ported
| System | Impact | Note |
|---|---|---|
| **Research efficiency bonuses** | High | The passive %-boost layer that touches nearly every system; ~13 bonus keys across 8 source files. |
| **Trophies** | Medium | Bounty/zone reward items (Trophy_Lunar, etc.) that buff yield/xp/combat. No source in the port. |
| **Missions** | Medium | 47-step linear tutorial chain + its credit/XP rewards. |
| **Skill milestones** | Low–Med | Per-skill bonuses unlocked at level thresholds (3 managers use them). |
| **Fleet** | — | Removed from the game per the owner. |

## Summary
Every **content** set is a 1:1 data port, and every **major gameplay loop** (gather → craft → research → combat → infrastructure → ship designer → bounty → warp, plus rarity/affixes/sockets/sets) is mechanically faithful. The largest remaining fidelity gap is the **research passive-bonus layer** (and the smaller Trophy/Mission/Milestone reward layers), which make the original's numbers ramp faster but do not change how any system *works*.
</content>
