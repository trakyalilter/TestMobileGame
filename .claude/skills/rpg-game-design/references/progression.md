# Progression: curves, budgets, pacing

## The shape of a good curve

Progression is a race between two curves: what the next step **costs** and what
it **gives**. Their relationship is the entire feel of a game.

| Cost | Reward | Result |
|---|---|---|
| linear | linear | flat and dull — no sense of growth |
| exponential | linear | a wall; the classic MMO grind complaint |
| linear | exponential | runaway; the game solves itself by hour three |
| exponential | exponential, slower base | the workhorse: growth feels real, but each step costs more of your life |

The workhorse in practice: cost grows at ~1.15× per step, reward at ~1.10×. The
ratio between them sets how fast the player decelerates. Tighten to 1.15/1.13
for a gentle late game; widen to 1.15/1.05 when you want a hard wall that
prestige or a new system is meant to break.

**Diminishing returns are the honest way to cap something** without a hard wall.
`effect = cap × n/(n + k)` approaches `cap` and never exceeds it; `k` is the
count at which you get half. Players accept this far better than "maximum 10" —
the eleventh still does something, just visibly less.

## Level curves

The RuneScape curve is the reference implementation for a long climb:
each level's increment is `floor(L + 300 × 2^(L/7))`, summed and divided by 4.
It gives ~90 s to the first level and hundreds of hours to the last, on one
formula with no tables to hand-maintain.

Whatever curve you pick, check three things:

1. **Time to level 2** — under two minutes, ideally under one. This is the
   single most-watched number in onboarding.
2. **The ratio between adjacent late levels** — if level 79→80 takes 1.5× level
   78→79, the player feels the wall. Above ~1.3× per level, add a reason to
   keep going that is not the level itself (milestone rewards, unlocks).
3. **Where the milestones land.** Levels that only add a stat are invisible.
   Levels that unlock something are events. Space real unlocks 5–10 levels
   apart early, widening later; put a distinct reward at each round number the
   player will fixate on.

## Power budgets

A **power budget** is the total stat allocation a tier is allowed. It is the
only reliable defence against power creep.

Method: pick a reference item at each tier and define its total power as a
weighted sum of its stats — where the weights are how much one point of each
stat is worth in your combat math. Every other item at that tier must sum to
the same budget, spent differently. An item with more attack has less defence.
Rarity multiplies the budget; it does not add a free extra stat.

This makes two things possible that are otherwise guesswork:

- **Comparing across archetypes.** Is a 40-attack sword stronger than a
  25-attack-15-crit dagger? Budget math answers it.
- **Sanity-checking new content.** If tier 8 is 2.2× tier 7's budget and someone
  proposes an item at 4×, the conversation is about the number, not taste.

Set the between-tier ratio deliberately (2× and 2.2× are common) and hold it.
Then the crucial rule: **the best item of tier N must sit below a plain item of
tier N+1.** If a maxed-out legendary from the previous tier beats a fresh common
from the next, you have retired an entire tier of content on arrival, and the
player who grinded that legendary is punished for it. Rarity should be a comfort
margin within a tier, not a tier leapfrog — with one deliberate exception if you
want a jackpot rarity that skips exactly one tier and then retires.

## Gating

Gates control pace. Every gate should be one of:

- **Skill/level gate** — you have played enough
- **Resource gate** — you have accumulated enough
- **Knowledge gate** — you have unlocked the recipe/research/map
- **Capability gate** — you have the specific tool this content demands

The fourth is the most interesting and the most underused. A gate that asks
"do you have a cryo weapon" creates a goal, a shopping list, and a moment of
understanding. A gate that asks "is your attack above 5000" creates a grind.

**Binary capability gates are easier to balance than numeric ones** and they
stay balanced. "Conventional weapons do 2% damage here" is either satisfied or
not; it cannot drift when you retune attack values next month. Numeric walls
need re-checking after every stat change in the game.

Watch for the failure where a gate can be reached but not passed — the player
unlocks a zone whose requirement is an item that drops in that zone. Every gate
needs a reachable answer from *outside* the gate.

## Prestige and new game plus

Prestige works when the reset gives back more than it takes, and the player can
feel that before they commit.

Design checklist:

- **First prestige early, full climb long.** The first reset should land in
  hours so the player learns the mechanic while stakes are low. Maxing the
  prestige tree can and should take days or weeks.
- **Show the multiplier before the reset.** The player must be able to see what
  they will get. A reset you cannot preview is a leap of faith most players
  decline.
- **Never a full wipe.** Keep something — a fraction of levels, permanent
  unlocks, the tech tree, cosmetics. A reset that returns you to literal minute
  zero reads as punishment, and the second one never happens.
- **The second run must be visibly faster.** If it is not at least 2–3× faster
  to reach the previous ceiling, the loop is not paying and players will feel
  it by mid-run.
- **Prestige currency needs its own sink tree** that is not just "number goes
  up" — nodes that change how you play beat nodes that add 5%.

A logarithmic prestige payout — `shards = floor(log2(score/threshold)) + 1` —
is well-behaved: it rewards overshooting the gate without letting a player who
grinds 100× longer get 100× the reward, so "reset now" stays roughly optimal.

For NG+, escalate on a **new axis**, not the same numbers larger. Rotating
resistances, new mechanics layered onto known encounters, modifiers the player
chooses — these keep old content meaningful. Pure stat inflation makes NG+ a
re-run with bigger numbers, and players who wanted more game feel cheated.
