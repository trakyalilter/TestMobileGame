# BigNumber adoption plan — the 2^53 ceiling (NG+ precursor) — v0.1

**Status:** Plan. **Recommendation: HARDEN-AND-DEFER** (do the cheap Phase-1 hardening now; defer the full BigNumber rewrite until content actually demands it, behind a tripwire).
**Why it exists:** `NG_PLUS.md` lists BigNumber as the P0 precursor. This plan decides *how much* BigNumber the planned design actually needs — and the honest answer is "not the full rewrite, yet."

**Subsystems** (`docs/audit/SUBSYSTEM_MATRIX.md`): `format_utils`, `warp_manager` (prestige score/shard formula), `resources` (`lifetime_credits`), `combat_manager` (HP/ATK/damage), save/migration.

---

## The problem

GDScript `float` is IEEE-754 double: **exact integers only up to 2^53 ≈ 9.0e15.** Past that, integer values lose precision (gaps grow), which can produce: rounded/nondeterministic damage, a corrupt `progress_score`, and an off-by-N shard payout. The codebase uses raw `float` for HP, ATK, damage, credits, and `lifetime_credits`.

## Where it ACTUALLY bites (the audit — show the spreadsheet)

The blocker is real but **further out than the "before NG+ ships" framing implies**, for three measured reasons:

1. **Display already survives any magnitude.** `FormatUtils.format_number` drops to scientific notation past the suffix table (`…e42`). No display crash at large values — only *precision* is masked.
2. **The prestige formula is log-forgiving.** `calculate_warp_gains` = `floor(log2(progress_score/500k))+1`. `log2` compresses: even if `lifetime_credits` float-rots in its low bits near 2^53, the shard count is off by at most ~1. Not the catastrophe "corrupt shard payout" suggests.
3. **Planned NG+ live values stay far under 2^53.** Per `NG_PLUS.md` the ladder is ~6 authored tiers, gated at warps ≤ ~20 (warp-tier mult ≤ ×16–32). Worked numbers:

| Value | At Z10 (base) | At WT5 (×100 enemy, ×16 warp-tier) | 2^53 headroom |
|---|---|---|---|
| Enemy HP | 20M (2e7) | ~2.2B (2.2e9) | ×4,000,000 under |
| Damage/hit | ~1e6 | ~1e8 | comfortable |
| Credits/kill | ~1e6 | ~1.6e9 | comfortable |
| `lifetime_credits` (cumulative) | grows with playtime | ~1e12–1e14 over a long arc | the *first* to approach 2^53 — but only after an enormous kill count |

**Conclusion:** for the planned 6-tier NG+ ladder, `float64`'s 9e15 headroom is comfortable. The one value that grows unbounded is the cumulative `lifetime_credits` odometer, and it reaches the danger zone only at extreme playtime / much steeper scaling than designed.

---

## The scope decision (the fork)

**Option A — Full BigNumber now** (mantissa/exponent type everywhere numeric).
- *Pro:* infinite headroom; genre-correct if the game ever goes NGU/Antimatter-Dimensions deep (e30+).
- *Con:* weeks of refactor across every manager + every arithmetic op + every UI format + a save migration; GDScript has **no operator overloading**, so it becomes `a.mul(b)`/`a.add(b)` everywhere (verbose, regression-prone); per-tick combat takes a perf hit. **High cost paid speculatively for content that doesn't reach the ceiling.**

**Option B — Harden-and-defer (RECOMMENDED).**
- Keep `float64`. Do cheap hardening now (below). Hold the full rewrite behind a **tripwire**: adopt BigNumber only when content/scaling would push a *live* value over the budget.
- *Pro:* near-zero cost; no refactor, no perf hit, no migration; unblocks the entire planned NG+ ladder immediately.
- *Con:* finite — at extreme depth (≫WT6, or much steeper scaling) numbers still rot, so this is a deferral, not a permanent solve. The tripwire makes that explicit.

**Recommendation: B.** The full rewrite is premature for a bounded, slot-capped, ~6-tier NG+. If the design later commits to *infinite* NG+ depth (e30+), trip to Option A then — with the strategy below already written.

---

## The scaling budget (design constraint — the tripwire)

**Keep any single LIVE value (HP, ATK, damage, per-cycle credits) under ~1e15** (≈ 2^50, an 8× safety margin below 2^53). This is comfortably above the planned ×100 NG+ scaling.

**Tripwire:** if a content/balance change would push a live value over ~1e15 — or `lifetime_credits` is observed approaching ~1e15 in real telemetry — that triggers the full BigNumber adoption (Option A, strategy below) *before* that content ships. Add a debug-build assert in `note_production` / boss-spawn that logs when any value crosses 1e15, so the tripwire is automatic, not vibes.

---

## Phase 1 — harden now (cheap, unblocks NG+)

1. **`FormatUtils.format_number` `is_finite` guard.** Add `if not is_finite(val): return "∞"` at the top — INF/NaN currently render as "infe308"/"nan". (Closes the checklist "format_number guards non-finite" item. `UITheme.format_num` already guards; this protects every *direct* caller.) ← *doing this with this plan.*
2. **Prestige-formula robustness check.** Confirm `calculate_warp_gains` stays monotonic and finite for `lifetime_credits` up to 1e15 (it does — `log2` is forgiving; document it so it isn't "fixed" into something fragile).
3. **Scaling-budget assert.** Debug-build log when any live HP/damage/credit value crosses 1e15 (the automatic tripwire).
4. **NG+ scaling stays in budget.** When tuning the NG+ enemy-scaling curve (`NG_PLUS.md` ×2.5→×100), keep WT-max live values < 1e15. Trivially satisfied by the planned ladder.

## Deferred — full BigNumber migration strategy (for when the tripwire trips)

Documented now so it's ready, not invented under pressure:
- **Type:** a `BigNum` class — `{mantissa: float (1..10), exp: int}` — with `add/sub/mul/div/log2/to_float/format`. (Class, not struct: GDScript can't overload operators on either, but a class keeps the API in one place.)
- **Surface, in dependency order:** `resources` (`lifetime_credits`, currencies) → `warp_manager` (prestige score/shard) → `combat_manager` (HP/ATK/damage) → infra/gather/process yields → all `FormatUtils`/UI reads.
- **Migration:** bump save version; on load, convert stored floats → `BigNum` (lossless for values < 2^53, which all existing saves are). Keep the atomic `.tmp`→`.bak` pattern.
- **Perf:** keep hot per-tick combat paths on `float` where values are provably < 1e15 (small enemies), promote to `BigNum` only past the budget — a hybrid, so the common case stays fast.

---

## Failure modes → prevention
1. **Premature rewrite burns weeks for no player-visible gain** → Option B avoids it; build BigNumber only when content needs it.
2. **Silent precision rot ships unnoticed** → the 1e15 debug assert (tripwire) makes a breach loud, not silent.
3. **Deferral forgotten, then content blows the budget** → the tripwire + this doc + the `NG_PLUS.md` P0 link keep it on the radar; NG+ tuning is explicitly budget-bounded.
4. **Display garbage at the ceiling** → `is_finite` guard + existing scientific-notation fallback.

## Build sequence
- **Now:** Phase 1 hardening (items 1–4). Unblocks `NG_PLUS.md` P1 at the planned scale.
- **Tripwire:** full BigNumber (deferred strategy) — only if/when a live value would exceed ~1e15.
