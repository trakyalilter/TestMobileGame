# Fleet System Audit — 2026-08-15

Scope: `fleet_manager.gd`, `fleet_page.gd`, the combat wiring (`combat_manager`
line ~3120), reset/save paths, offline model, sim coverage, i18n, and doc drift
against `docs/FLEET_SIEGE_GATES.md`.

Method: every load-bearing claim measured through real code paths by the new
permanent guard **`scenes/fleet_check.tscn`** (8 cases). Code-reading findings
are labelled as such. The probe misfired twice while being built and both
misfires are recorded in its comments — the second one (independent kit rolls
crossing a naive threshold) had produced the exact OPPOSITE of the true offline
verdict before it was fixed.

## What is HEALTHY (measured)

| claim | measurement |
|---|---|
| +25%/ship, cap +100% | empty 1.0 · 4 ships 2.0 · 7 ships 2.0 |
| the bonus lands in real fights | Z1 boss mean TTK 50.3s bare → 24.4s with 4 frigates (×2.06, 7+7 wins) |
| roster persists across warp | 2 ships held through a real `execute_warp()`; capacity 2 → 3 |
| hard reset clears it | roster empty after `hard_reset()` |
| build economy | exact deduction, refuses over-cap and unaffordable with NO partial pay, scrap refunds nothing |
| cost table | every cost element exists in ElementDB |
| save/load | wired in game_state (`"fleet"` key), array shape, load tolerates missing key |
| i18n / owner text rules | all page strings have TR rows except one (finding 5); "▸" is on the allowed list |

## FINDINGS (ranked)

### 1 — MAJOR · Destroyer and Cruiser are strictly dominated; `power` is a dead stat

The live bonus counts **ships**, not power: `get_combat_dps_mult()` uses
`get_fleet_count()`. Measured: a Cruiser + 3 Frigates gives *exactly* the mult
of 4 Frigates. `get_fleet_power()` has no gameplay consumer — only the Fleet
page label and a stale spike. So:

- **Fleet Destroyer (≈7.5× frigate cost) and Fleet Cruiser (≈25×, incl. 500
  Superalloy) buy nothing a Frigate doesn't.** Textbook dominated choice, on the
  system whose stated purpose is spending surplus.
- **The sink under-delivers its own design by ~7–25×** for a rational player:
  the doc sizes hulls to "soak 30–60 min of infra output", but the optimal fill
  is frigates-only at 8k Water per slot.

Smallest-blast-radius fix: weight the per-ship fraction by `power/100`
(frigate keeps +25%, destroyer ≈ +80%, cruiser ≈ cap alone), keep the +100%
cap. That makes hull tier the interesting decision ("fewer big or more small")
and restores the sink. Needs an owner ruling — it changes live player numbers.

### 2 — MAJOR · The fleet does not exist offline

Measured with ONE kit: online mult ×2.00, offline model TTK **79.1s → 79.1s**,
byte-identical. `_offline_winnable` prices DPS from `player_weapon_states`
only; `get_combat_dps_mult()` never enters. A prestige feature whose pitch is
"fights beside you" contributes 0% in the mode an idle player lives in —
against the project's own fundamental that background/offline must pay.

The omission direction matches the offline model's stated conservatism rule
("offline may refuse fights online could win, never the reverse") but ×2 is
far past conservative. Fix candidate is one line — multiply the offline `dps`
by `get_combat_dps_mult()` (deterministic, no RNG, cannot over-promise).

*Context, out of fleet scope:* the offline model also omits the warp combat
multiplier (`get_combat_multiplier()`: shards ×3% + ×2^tier) and research
combat bonuses — same defect family, and at warp 10 that term alone is ×4–10.
Offline yield for deep-prestige players under-prices by an order of magnitude.
Pre-existing; deserves its own ruling.

### 3 — MAJOR · Post-cap builds buy nothing, and the button stays live

Ships 5+ add 0% (cap) and power has no consumer, so at W10 (capacity 11) seven
slots are pure material burn behind an enabled Build button. The header calls
capacity head-room for the CUT siege role. Until something consumes it, either
finding 1's power-weighting (which gives big hulls a reason to exist inside
the cap) or a UI line at the cap ("further ships add no combat bonus") is
needed — silence is the failure mode.

### 4 — MINOR · The bot never builds fleet ships (instrument gap)

`player_like.gd` has zero fleet references. The bot warps, so every post-warp
funnel measurement runs at ×1.0 damage where a real player sits at ×1.5–2.0.
All post-warp balance data is pessimistic by up to 2×. (Same instrument-gap
family as the loot-filter case — and that one measured WORSE when taught to
the bot, so this needs its own A/B before shipping, not an assumption.)

### 5 — MINOR · "Build" button label is untranslated

`fleet_page.gd::_update_states`: `btn.text = tr("Cap Full") if full else
"Build"` — the "Build" literal is outside `tr()` and has no CSV row. Renders
English in the TR build.

### 6 — MINOR · `combat_spike.gd` header documents the pre-P2 world

It claims "Combat does NOT read fleet power … fleeted TTK == unfleeted TTK by
construction — this run PROVES that empirically." False since v112 P2. Anyone
running it gets an inverted conclusion from a probe that says it proves things.

### 7 — MINOR · Doc drift (3 spots)

- `FLEET_SIEGE_GATES.md` says `get_external_progression_combat_mult()` is
  "currently uncalled / dead" — it was **deleted** in v112 (`combat_manager:421`).
- Same doc's capacity section still shows the pre-÷5 frigate bill (40k Water)
  as its example; the header cadence note corrects it but the example line reads
  as current.
- `warp_manager.gd:321` "The fleet does NOT survive" means the *main ship*, in
  a codebase where `fleet_manager`'s roster DOES survive warp. Accurate in
  context, primed for misreading — one clarifying word ("the shipyard fleet /
  main ship") would close it.

### 8 — CLEANUP

- Orphaned CSV row 1649 keyed on the forbidden "⟢" pictograph (dead since the
  v140 string fix).
- No unlock moment: the Fleet tab appears silently on first warp (coach tour
  only fires on first visit). A short-fact notification matches the house
  reveal pattern. Low.
- Scrap is one-click irreversible with no refund and no confirm. Cheap ships,
  low stakes — but the Vault set the precedent for point-of-no-return
  disclosure. Low.

## Guard added

`scenes/fleet_check.tscn` — permanent, 8 cases, all against real paths
(`build_ship`, `execute_warp`, `hard_reset`, live fights, `_offline_winnable`).
The offline case PRINTS its measurement rather than asserting, deliberately:
the assert direction is finding 2's owner ruling. Once ruled, flip it to an
assertion so the ruling cannot drift.
