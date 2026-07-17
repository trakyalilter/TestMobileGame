# Turkish Localization Glossary

Locked term translations so ~2,500 strings stay consistent. **Review these first** —
every later section's translations depend on these choices. Flagged (⚑) = needs your call.

## Currencies & prestige
| English | Turkish | Notes |
|---|---|---|
| Liras | Lira | internal key stays `credits`; display only |
| Exotic Matter | Egzotik Madde | |
| Warp Shard | Warp Parçası | |
| Warp Core | Warp Çekirdeği | |
| Energy | Enerji | combat resource |

## Core nouns
| English | Turkish | Notes |
|---|---|---|
| Zone | Bölge | code uses "Zone"; sectors in lore |
| Sector | Sektör | |
| Hull | Gövde | ship hull |
| Shield | Kalkan | |
| Module | Modül | |
| Research | Araştırma | |
| Mission | Görev | main story chain |
| Quest | Sipariş | supply quests (distinguished from Mission) |
| Bounty | Ödül Avı | bounty contracts |
| Infrastructure | Altyapı | buildings |
| Element / material | Element / Malzeme | symbols (Fe, Si) stay as-is |

## Verbs / actions (buttons — usually UPPERCASE)
| English | Turkish |
|---|---|
| CONTINUE | DEVAM ET |
| NEW GAME | YENİ OYUN |
| EXIT | ÇIKIŞ |
| BUILD | İNŞA ET |
| RESEARCH | ARAŞTIR |
| CRAFT | ÜRET |
| EQUIP | KUŞAN |
| CONSTRUCT | İNŞA ET |
| WARP | WARP (kept) |

## Do NOT translate
- Brand: "HORIZON", "IDLE", "HORIZON IDLE"
- Element symbols: Fe, Si, Cu, Ti, … (periodic table)
- Numbers / format tokens: `%d`, `%s`, `K/M/B/T`, `◆◇◈`, `→ ▲▼`

## Casing note
Turkish uppercase is NOT the same as ASCII: `i → İ` (not `I`), `ı → I`. Strings that
appear UPPERCASE in-game are stored **already-uppercased** in the CSV, and any runtime
`.to_upper()` on Turkish text routes through `UITheme.tr_upper()` (i→İ aware).
