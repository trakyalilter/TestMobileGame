# Retention, session shape, and monetization

## What the retention numbers actually mean

D1, D7, D30 are the fraction of players who return that many days after
install. They fail for different reasons and are fixed in different places —
treating "retention is bad" as one problem is why retention work often achieves
nothing.

**D1 is an onboarding metric.** A player who does not come back tomorrow did not
understand what the game was, or did not reach anything satisfying in their
first session. Look at the first ten minutes: time to first meaningful decision,
time to first reward, whether the core verb was clear. Nothing you build in the
mid-game moves D1.

**D7 is a core-loop metric.** They understood it, they came back a few times,
and then the loop stopped paying. Look at whether the thing they do repeatedly
still has variance and decisions at hour five, and whether a visible next goal
always exists. This is where dominated choices and grind walls show up in the
data.

**D30 is a meta-loop metric.** They like the game and ran out of reasons to
keep going. Look at long-term goals, prestige pacing, content cadence, and
whether there is a reason to log in on a day when they have no time.

Rough healthy bands for a mid-core RPG: D1 around 40%, D7 around 20%, D30
around 10%. Genre and acquisition source move these a lot — a wishlist-driven
premium PC audience behaves nothing like broad mobile UA, so compare against
your own cohorts over time rather than against a benchmark you read somewhere.

## Session shape

Design the session explicitly. What does a player do in 2 minutes, 15 minutes,
and 2 hours?

- **The 2-minute session** must be worth opening the game for: collect, claim,
  set the next task, leave. If a short session cannot conclude cleanly, you are
  training players to only open the app when they have an hour — and most days
  they do not.
- **The 15-minute session** is where the meta loop lives: spend, plan, craft,
  push one fight.
- **The 2-hour session** should have internal structure and a place to stop. A
  game with no satisfying exit point produces guilt, and guilt produces churn.

**Always leave a next goal visible on exit.** The single strongest predictor of
return is knowing what you are coming back to.

## Idle and offline progress

For idle games specifically: offline progress is the genre's core promise and
the returning report is its dopamine hit. Two rules.

**Be generous.** Offline should be a substantial fraction of active — 50–80% is
typical. Punishing offline yield fights the entire reason the player chose this
genre.

**Cap long, or not at all.** If you must cap, set it in the 8–24 hour range so
an overnight absence is fully paid. A short cap punishes exactly the players
with jobs, and they notice immediately.

And make the return **legible**: a report showing what accrued is worth more
than the resources themselves. The player needs to see that leaving was
rewarded, or the mechanic does not register.

Offline must also be computed in **bounded time** — a closed-form calculation or
a capped replay, never a per-second simulation of eight hours. A player
returning after a week should not watch a loading bar.

## Onboarding

- **Teach the core verb in under 60 seconds.** Not the systems — the verb.
- **One new concept at a time**, each with a use before the next arrives.
- **Tutorialize by doing**, never by reading. A modal explaining a system is a
  system the player will not remember.
- **Front-load the first three rewards** and space them tightly.
- **Delay every system that is not the core loop.** A player shown six tabs in
  the first minute learns that the game is complicated, not that it is deep.
  Reveal each system when the player has a problem it solves — that moment turns
  a tutorial into a relief.

## Ethical monetization

The distinction that matters: **sell time and breadth, not power over other
players.**

Reasonable: cosmetics, convenience, inventory and capacity, offline-time boosts,
account-wide quality-of-life, expansions, battle passes with earnable value,
one-time premium purchase.

Corrosive: power sold directly in a competitive context, mechanics designed to
create a problem the shop solves, timers whose only purpose is to sell the
skip, loot boxes for progression-critical items, FOMO cycles that punish taking
a break.

The design test: **would this system exist if the shop did not?** If the answer
is no — if the friction was manufactured to be sold — it is a monetization
mechanic wearing a design costume, and players eventually see it. The ones who
see it first are the ones who were going to spend the most.

For a premium (buy-once) game, the whole question simplifies: there is no shop,
so every piece of friction has to justify itself as design. That is a freedom
worth protecting. Do not import free-to-play patterns — daily login rewards,
energy timers, artificial scarcity — into a game nobody has to be nickel-and-
dimed into finishing. They read as vestigial at best and insulting at worst.

## Diagnosing churn

When players leave, find **where** before asking why. Instrument the funnel:
session count and playtime at churn, last completed objective, last screen,
whether they hit a failure they never recovered from.

The most common findings, in rough order of frequency:

1. **A wall** — a difficulty or cost spike with no visible path through it
2. **A dead end** — no clear next goal after finishing something
3. **A dominated strategy** — they optimized the fun out and noticed
4. **A grind with no variance** — the outcome became known
5. **A loss that cost too much** — a punishment that exceeded the player's
   investment tolerance

Each has a different fix, and applying the wrong one is worse than doing
nothing: smoothing a curve that was not the problem removes tension and loses
the players who were still engaged.
