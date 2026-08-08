# Measurement: harnesses that tell the truth

Most design arguments are unresolvable because both people are reasoning from
the code rather than from the game. A ten-second simulation ends the argument.
This file is about building those, and about the ways they lie to you.

## What to measure, by question

| Question | Measure | Report as |
|---|---|---|
| Is this encounter tuned? | win rate and TTK across a **matrix** of player power tiers | matrix, plus the pass rule you set beforehand |
| Is this item worth using? | its win/clear rate vs. alternatives, per encounter type | which column each build wins |
| Is this cost right? | wall-clock time to afford it at realistic income | minutes/sessions, not resource units |
| Is this drop rate right? | simulated attempts to first drop: median, mean, 90th percentile | the unlucky tail, not the average |
| Is progression paced? | cumulative time to each tier | hours to tier N, and the ratio between tiers |
| Is this chain buildable? | walk the recipe graph for dead ends and unreachable inputs | list of violations |
| Is this economy stable? | net faucet minus drain over a simulated run | net at hour 1 / 10 / 100 |

The common thread: **report in the player's units.** "Costs 40 000 iron" is not
a finding. "Costs 40 000 iron, which is 3.2 hours of foreground mining or 40
minutes once the smelter chain is up" is a finding, and it makes the ruling
obvious.

## Building a harness

The bar is low and worth clearing. A harness needs to:

1. **Drive the real code.** Instantiate the actual combat manager, the actual
   recipe graph. A reimplementation measures your reimplementation.
2. **Set up state explicitly** — gear, level, resources — rather than depending
   on whatever a save file happens to hold.
3. **Print one unambiguous verdict line** — `RESULT: PASS (0 failures)` — and a
   nonzero exit on failure, so it can run unattended in CI or a batch.
4. **Run in seconds** so nobody avoids running it.

Run enough trials to see through variance. With crits, drop rolls, and dodge in
the loop, a single fight tells you almost nothing; 9–20 trials per cell is
usually enough to distinguish "wins" from "sometimes wins", which is the
distinction that matters.

## Ways harnesses lie

**It does not play the way a player would.** The most common and most expensive
failure. A simulation that never uses consumables, never brings the counter-tool
an encounter demands, or never swaps presets against a phase boss will report
content as impossible when it is merely demanding. Before believing "unwinnable",
confirm the harness performs the intended solution.

**It mirrors the logic instead of calling it.** A test carrying its own copy of
a formula passes after the real one regresses and fails after the real one is
fixed. If the logic is buried somewhere untestable — inside a UI callback, say —
extract it to a function both can call. That is usually the right refactor
anyway.

**The assertion is unreachable.** Check that the expected outcome is something
the system can produce at all. An assertion that filters to category A while
expecting a member of category B fails permanently and looks exactly like a real
regression.

**It compares against the wrong locale, format, or units.** Comparing a
localized string against an English literal, or seconds against milliseconds,
produces confident nonsense.

**It measures the input, not the output.** Asserting on a stat you set rather
than the damage that resulted tests your setup code.

**It mutates shared state.** A harness that resets progress, writes a save, or
deletes files can destroy real data. Isolate it: a mode flag that disables
persistence, a scratch data directory, or an assertion that refuses to run
unless isolation is confirmed.

## The negative control

**Before believing a new check, watch it fail.** Revert the fix, run it, confirm
it goes red for the stated reason, restore.

```
snapshot the file → revert the fix → run the check (must fail) → restore
```

This catches the class of test that asserts against its own assumptions and
therefore passes unconditionally. It costs two minutes and it is the difference
between a guard and a decoration.

## Reading results honestly

- **State the pass rule before you look.** Otherwise you will rationalize
  whatever the numbers say.
- **Report the whole matrix, not the summary.** "10 of 15 pass" hides which five
  and why. The pattern in the failures is the actual finding.
- **A cell that is 100% or 0% across every configuration is not measuring
  anything** — it passes or fails regardless of the change under test. Either
  fix the cell or drop it.
- **High variance between identical trials means the metric is unstable.** Add
  trials or find the source of the noise before drawing conclusions from it.
- **Say what you truncated.** If you sampled, capped, or tested a subset, say
  so. Silent truncation reads as full coverage and someone will act on it.
