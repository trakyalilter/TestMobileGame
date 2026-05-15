# Audit Log

Use this file to track concrete findings. Keep one row per finding.

## Status Values

- `open`
- `in_progress`
- `blocked`
- `fixed`
- `verified`

## Findings

| ID | Sev | Subsystem | Location | Summary | Impact | Owner | Status | Verification |
|---|---|---|---|---|---|---|---|---|
| AUD-P1-001 | P1 | Save/Load | `scripts/core/game_state.gd` | No backup fallback path when primary save is corrupted | Can cause effective save loss despite `.bak` creation | TBD | open | Manual corruption test |
| AUD-P1-002 | P1 | Reset Integrity | `scripts/core/game_state.gd` | `hard_reset()` does not reset `warp_manager` or `bounty_manager` state | "New game" can retain prestige/contracts in current session | TBD | open | In-session reset validation |
| AUD-P1-003 | P1 | Reset Integrity | `scripts/core/resources.gd` | `resources.reset()` leaves `lifetime_credits` (and `max_energy`) untouched | Hard reset can keep meta progression counters unexpectedly | TBD | open | Hard reset + inspect warp gains |
| AUD-P0-004 | P0 | Offline Progress | `scripts/core/game_state.gd`, `scripts/managers/gathering_manager.gd`, `scripts/managers/combat_manager.gd` | Offline `delta` is unbounded; large deltas can trigger huge per-action loops | Startup freeze/hang risk and extreme offline exploit window | TBD | open | Large-delta simulation |
| AUD-P2-005 | P2 | Save/Load Robustness | `scripts/core/game_state.gd` | `load_game()` does not guard null return from `FileAccess.open` | Can throw runtime errors on IO open failure | TBD | open | Forced open-failure test |
| AUD-P1-006 | P1 | Economy Integrity | `scripts/managers/combat_manager.gd`, `scripts/core/resources.gd` | Credit penalties use `add_currency(..., -cost)` but `add_currency` ignores non-positive values | Loss costs can be bypassed, breaking economy penalties | TBD | open | Combat deduction scenario |

## Detailed Evidence (Append Below)

### Template

```md
### [AUD-PX-000] Short title
- Severity: P0/P1/P2/P3
- Subsystem: 
- Location: 
- Repro Steps:
  1. 
  2. 
  3. 
- Expected:
- Actual:
- Impact:
- Likely Root Cause:
- Fix Direction:
- Owner:
- Status: open/in_progress/blocked/fixed/verified
- Verification:
```

### [AUD-P1-001] Missing backup fallback when JSON parse fails
- Severity: P1
- Subsystem: Save/Load
- Location: `scripts/core/game_state.gd` (`save_game`, `load_game`)
- Repro Steps:
  1. Create a valid save so `user://savegame.bak` exists.
  2. Corrupt `user://savegame.json` (invalid JSON).
  3. Launch game and trigger `load_game()`.
- Expected:
  - Game attempts to recover from `savegame.bak` when primary file parse fails.
- Actual:
  - Parse error is printed and load flow ends without backup recovery.
- Impact:
  - Players can lose progression if primary save becomes invalid.
  - Existing backup file is not used as a resilience mechanism.
- Likely Root Cause:
  - `load_game()` has no backup read path on parse or open failure.
- Fix Direction:
  - Add fallback chain: `savegame.json` -> `savegame.bak`.
  - If backup load succeeds, optionally restore primary file.
- Owner:
  - TBD
- Status:
  - open
- Verification:
  - Corruption simulation confirms automatic recovery from backup.

### [AUD-P1-002] Hard reset leaves prestige and bounty state alive in-memory
- Severity: P1
- Subsystem: Reset Integrity
- Location: `scripts/core/game_state.gd` (`hard_reset`), `scripts/managers/warp_manager.gd`, `scripts/managers/bounty_manager.gd`
- Repro Steps:
  1. Progress game until warp shards and active/available bounty contracts exist.
  2. Use Options -> Reset (`GameState.hard_reset()`), which reloads current scene.
  3. Open Warp/Bounty pages in same runtime session.
- Expected:
  - Hard reset clears all progression managers for a clean new state.
- Actual:
  - `hard_reset()` resets many managers but not `warp_manager` and `bounty_manager`.
  - Their in-memory state can persist until full app restart.
- Impact:
  - "Reset game" semantics are inconsistent.
  - Players may keep or observe stale prestige/contracts after reset.
- Likely Root Cause:
  - Missing reset calls for non-`Skill` manager (`bounty`) and prestige manager (`warp`) in `hard_reset()`.
- Fix Direction:
  - Add explicit `warp_manager` and `bounty_manager` reset paths (or recreate managers on hard reset).
  - Ensure post-reset state is deterministic without requiring app restart.
- Owner:
  - TBD
- Status:
  - open
- Verification:
  - Reset in-session, inspect shard count/contracts before and after.

### [AUD-P1-003] Resource reset preserves meta counters during hard reset
- Severity: P1
- Subsystem: Reset Integrity
- Location: `scripts/core/resources.gd` (`reset`), `scripts/core/game_state.gd` (`hard_reset`)
- Repro Steps:
  1. Earn significant credits to increase `lifetime_credits`.
  2. Trigger hard reset from Options.
  3. Check systems that depend on historical credits (e.g., warp gain calculations).
- Expected:
  - Hard reset should clear persistent progression counters unless explicitly documented.
- Actual:
  - `resources.reset()` clears inventory/currencies but keeps `lifetime_credits` and `max_energy`.
- Impact:
  - Hard reset may not be a true full wipe.
  - Meta progression can remain higher than expected in current session.
- Likely Root Cause:
  - `resources.reset()` is shared between prestige reset and hard reset but uses one behavior for both.
- Fix Direction:
  - Split into `soft_reset` (prestige-safe) and `hard_reset` (full wipe) or pass reset mode flag.
- Owner:
  - TBD
- Status:
  - open
- Verification:
  - Confirm `lifetime_credits` and derived warp gains return to baseline after hard reset.

### [AUD-P0-004] Unbounded offline delta can cause startup stalls and economy abuse
- Severity: P0
- Subsystem: Offline Progress
- Location: `scripts/core/game_state.gd` (`process_offline_progress`), `scripts/managers/gathering_manager.gd` (`calculate_offline`), `scripts/managers/combat_manager.gd` (`calculate_offline`)
- Repro Steps:
  1. Set save `last_save_time` far in the past (or manipulate system clock).
  2. Start game and let `load_game()` process offline progress.
  3. Observe load time and resulting gains.
- Expected:
  - Offline gains should be capped and computed in bounded time.
- Actual:
  - `delta` is passed raw to managers.
  - Gathering and combat offline functions iterate per action/kill (`for i in range(num_actions)` / `num_kills`), which can explode with large `delta`.
- Impact:
  - Potential startup freeze/hang on load.
  - High exploit risk via time manipulation.
- Likely Root Cause:
  - No global offline cap/chunking before per-action simulations.
- Fix Direction:
  - Add global cap (example: 8h/24h configurable) and/or chunked/analytic calculation paths.
  - Add sanity guard for abnormal timestamp deltas.
- Owner:
  - TBD
- Status:
  - open
- Verification:
  - Large-delta test completes under bounded time and bounded reward.

### [AUD-P2-005] Missing null guard after opening save file
- Severity: P2
- Subsystem: Save/Load Robustness
- Location: `scripts/core/game_state.gd` (`load_game`)
- Repro Steps:
  1. Simulate `FileAccess.open` failure (locked file or access issue).
  2. Trigger `load_game()`.
- Expected:
  - Load flow should fail gracefully and avoid null dereference.
- Actual:
  - Code immediately calls `file.get_as_text()` without checking `file`.
- Impact:
  - Runtime error path under IO failures.
- Likely Root Cause:
  - Missing defensive null check in load path.
- Fix Direction:
  - Guard `if not file: ...` with fallback/early return.
- Owner:
  - TBD
- Status:
  - open
- Verification:
  - Open failure no longer throws; game starts with fallback behavior.

### [AUD-P1-006] Negative credit deductions are no-ops due to API contract mismatch
- Severity: P1
- Subsystem: Economy Integrity
- Location: `scripts/managers/combat_manager.gd` (`lose_fight`), `scripts/core/resources.gd` (`add_currency`)
- Repro Steps:
  1. Trigger a combat loss path that calls `add_currency("credits", -cost)`.
  2. Compare credits before/after.
- Expected:
  - Credits decrease by `cost` for penalties.
- Actual:
  - `resources.add_currency` returns early for `amount <= 0`, so no deduction happens.
- Impact:
  - Loss penalties are effectively disabled.
  - Progression economy and risk/reward balance are distorted.
- Likely Root Cause:
  - Deduction call sites use `add_currency` with negative values instead of `remove_currency`.
  - Currency API explicitly blocks non-positive amounts.
- Fix Direction:
  - Replace negative `add_currency` calls with `remove_currency`.
  - Add assertion/logging for invalid negative adds to detect future misuse.
- Owner:
  - TBD
- Status:
  - open
- Verification:
  - Credits reliably decrease in combat-loss scenarios.
