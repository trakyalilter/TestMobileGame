# Subsystem Audit Matrix

Track coverage and completion for each game subsystem.

## Legend

- Coverage:
  - `not_started`
  - `in_review`
  - `reviewed`
- Risk:
  - `low`
  - `medium`
  - `high`

## Matrix

| Subsystem | Primary Files | State Transitions | Resource I/O | Unlock/Gates | Reset/Warp | Save/Load | Offline Logic | UI Sync | Risk | Coverage | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Gathering | `scripts/managers/gathering_manager.gd`, `scripts/ui/gathering_page.gd` | pending | pending | pending | pending | pending | pending | pending | medium | not_started | |
| Processing | `scripts/managers/processing_manager.gd`, `scripts/ui/processing_page.gd` | pending | pending | pending | pending | pending | pending | pending | high | not_started | |
| Infrastructure | `scripts/managers/infrastructure_manager.gd`, `scripts/ui/infrastructure_page.gd` | pending | pending | pending | pending | pending | pending | pending | high | not_started | |
| Shipyard/Loadout | `scripts/managers/shipyard_manager.gd`, `scripts/ui/designer_page.gd`, `scripts/ui/module_card.gd` | pending | pending | pending | pending | pending | pending | pending | high | not_started | Large manager; high coupling with combat |
| Research | `scripts/managers/research_manager.gd`, `scripts/ui/research_page.gd` | pending | pending | pending | pending | pending | pending | pending | high | not_started | |
| Combat | `scripts/managers/combat_manager.gd`, `scripts/ui/combat_page.gd` | in_review | in_review | pending | pending | in_review | in_review | pending | high | in_review | Logged economy bug: negative add_currency penalty no-op |
| Missions | `scripts/managers/mission_manager.gd`, `scripts/ui/mission_page.gd` | pending | pending | pending | pending | pending | pending | pending | medium | not_started | |
| Bounty | `scripts/managers/bounty_manager.gd`, `scripts/ui/bounty_page.gd` | in_review | pending | pending | in_review | in_review | pending | pending | medium | in_review | Hard reset path currently does not clear bounty manager state |
| Warp/Prestige | `scripts/managers/warp_manager.gd`, `scripts/ui/warp_page.gd` | in_review | in_review | pending | in_review | in_review | pending | pending | high | in_review | Hard reset path currently does not clear prestige manager state |
| Global Save/State | `scripts/core/game_state.gd`, `scripts/core/resources.gd` | reviewed | reviewed | n/a | reviewed | reviewed | reviewed | pending | high | in_review | Key risks logged: backup fallback, null open guard, offline delta cap |
| Main Navigation/UI Shell | `scripts/main.gd`, `scenes/main.tscn` | pending | pending | pending | pending | pending | pending | pending | medium | not_started | Page gate visibility and page enter hooks |

## Prioritized Start Order

1. Global Save/State
2. Shipyard/Loadout
3. Combat
4. Processing
5. Research
6. Infrastructure
7. Warp/Prestige
8. Missions/Bounty
9. Remaining UI-shell validation
