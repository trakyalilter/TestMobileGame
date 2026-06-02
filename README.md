# ✦ Stellar Forge

A mobile-first **idle / incremental** game built in **Godot 4.5** (GDScript).
Same loop DNA as a Melvor/HorizonIdle-style game, but redesigned for a phone:
a bottom tab bar instead of a 14-button sidebar, a single active task, and
offline progress that does the heavy lifting between short sessions.

## The core loop

```
Gather raw resources  →  Craft refined goods  →  Research tech (unlocks more)
        ▲                                                      │
        └──────────────  bigger yields / new actions  ◄────────┘
```

- **One active task at a time** (gather *or* craft). It ticks every frame and,
  when its timer fills, rolls loot + XP, then repeats.
- **Skill levels** (`Harvesting`, `Fabrication`) grant +2% yield per level.
- **Research** is paid with resources and permanently unlocks new actions /
  bonuses (`Prospecting → Electronics → Automation Core`).
- **Offline progress**: close the app, come back, and the game fast-forwards
  your active task and shows a "Welcome Back" summary.
- **Autosave** every 15s + on quit, written atomically with a `.bak` fallback.

## How to run / test

1. Install **Godot 4.5** (standard build): <https://godotengine.org/download>
2. Open Godot → **Import** → select this folder's `project.godot`.
3. Press **F5** (Play). It launches in a 720×1280 portrait window.
4. To test on a phone: *Project → Export → Add Android preset* and deploy,
   or run **Remote Deploy** from the editor with a USB-connected device.

### Try this first
- Tap **Salvage Scrap** and **Mine Iron Ore** to see the loop run.
- Go to **Craft → Smelt Iron Plate** (needs Iron Ore + Water).
- Open **Tech → Prospecting**, research it, then a new **Mine Crystal**
  action appears under Gather (progressive disclosure).
- Close and reopen the app to see the **offline progress** modal.

## Project layout

```
project.godot              # Godot 4.5 config, portrait mobile, GL Compatibility
scenes/main.tscn           # single root scene
scripts/
  core/
    game_data.gd  (autoload GameData)   # ALL content: resources, actions, recipes, tech
    game_state.gd (autoload GameState)  # engine: tasks, XP, tech, save/load, offline
  ui/
    main.gd                             # mobile shell (HUD + pages + tab bar), built in code
```

Adding content is data-only: drop a new entry into `GATHER`, `CRAFT`, or
`TECH` in `game_data.gd` and it appears in the UI automatically — no UI edits,
unlike the hardcoded mission ladder in the reference project.

## Status

v0.1 vertical slice — a complete, playable loop (gather → craft → research →
offline). Combat, infrastructure/automation buildings, fleets and prestige are
the natural next layers, following the same data-driven pattern.
