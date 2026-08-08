# Combat, difficulty, and itemization

## Difficulty is a distribution, not a point

"Is this boss too hard" has no answer until you say **for whom**. The only
useful form of the question is a matrix: outcome by player power level.

Build the matrix. Rows are gear or level tiers, columns are the metric you care
about (win rate, time to kill, deaths). A healthy gate looks like this:

| Player tier | Outcome |
|---|---|
| two tiers below | loses badly, obviously not ready |
| one tier below | loses close — visible progress, clear that it is nearly possible |
| on tier | wins with effort |
| one tier above | wins comfortably |

The "loses close" row is the important one and the one most often missing. A
player who gets a boss to 15% learns they need a bit more and comes back. A
player who gets it to 90% learns nothing except that they are not welcome.

State the pass rule for the matrix before you read it, or you will rationalize
whatever you find.

## TTK targets

Time to kill is the main dial for how an encounter feels.

| Encounter | Typical target |
|---|---|
| trash | 3–10 s |
| elite | 20–45 s |
| boss | 90–300 s |
| raid / capstone | 5–15 min |

Two failure modes bracket every one of these. **Too short** and mechanics never
get to fire — you built a phase system the player skips. **Too long** and you
are testing patience: past roughly 10 minutes a fight needs genuine phase
variety or it becomes a hold-button endurance test, and any death that late
costs more time than most players will re-spend.

When a fight overruns its target, ask whether the answer is less boss HP or more
player damage. They are not equivalent: cutting HP shortens this fight, raising
player damage shortens every fight.

## Counterplay: the auto-battler rule

An encounter should be beatable by a **decision**, not only by bigger numbers.
The decision can live anywhere:

- **Pre-fight** — build, gear, consumables, party composition, element choice
- **In-fight** — positioning, ability timing, target priority
- **Meta** — which encounter to attempt, when, with what preparation

In an idle or auto-battler game, in-fight input is off the table by design, so
**all** counterplay must be expressible in the loadout. That is a constraint,
not a limitation — it makes preparation the game. But it means every boss
mechanic has to be answerable before the fight starts, and you should verify
that a build exists that answers it. "The player must swap gear mid-fight" is
not a valid answer in a genre that promises you can walk away.

A mechanic with no answer is a stat check wearing a costume.

## Damage types and resistance triangles

A type triangle only creates decisions if the player can act on it. That
requires three things: the enemy's type must be **knowable before committing**,
switching must be **possible but costly**, and the payoff must be **big enough
to bother** — roughly a 2× swing between right and wrong choice. Below that,
players correctly ignore it and carry whatever.

Common mistakes:

- **Every enemy in a zone shares a weakness.** Then the zone has one answer and
  the other weapon types are dead weight for its whole duration.
- **The weakness is on the type the player already carries.** Free damage that
  teaches nothing.
- **Resist values too shallow to notice.** If wrong-type is a 15% penalty, the
  triangle is flavour text. Amplify resistances toward a real wall — a ~5× TTK
  penalty for the wrong tool makes the choice matter — while keeping weaknesses
  modest so the right tool feels correct rather than mandatory.
- **A type that exists mechanically but is never labelled.** If the player
  cannot see what type just hit them or what they just dealt, the system might
  as well not exist.

## Rarity and itemization

Rarity should answer "is this an upgrade?" instantly and correctly.

Set rarity as a **multiplier on the tier's power budget**, not as bonus stats.
Then the key relationship, which is easy to get wrong: **the best roll of tier N
must lose to a plain tier N+1.** Otherwise a lucky drop retires the next tier of
content before the player reaches it, and the reward for progressing is nothing.

A sensible spread within a tier: Common ×1.00, Uncommon ×1.1–1.2, Rare
×1.25–1.45, Legendary ×1.4–1.55, with the next tier's Common at ×2.2 of the
previous tier. Note how tight the top of that range is — the gap between Rare
and Legendary is small on purpose, because Legendary earns its identity from
affixes and modifiers rather than raw stats. If you want a jackpot rarity that
leapfrogs, make it leapfrog **exactly one tier** and then retire.

**Affixes are where build diversity lives.** Raw stat sticks are forgettable;
a modifier that changes how a build works is memorable and creates the
"is this better?" question that makes loot interesting. Prefer affixes that
change behaviour over affixes that add percentages.

## Build diversity, honestly measured

The test for build diversity is not "how many builds are viable" — it is
**"how many builds are the best answer to something."**

Run each build against each encounter type and look for a build that never wins
a column. That build is dominated and it is dead, no matter how good its
theorycraft looks. Either give it a column or cut it.

The inverse is worse: a build that wins every column. That is not a build, it is
the solution, and everything else in your itemization is now flavour.

## Boss mechanics that work

- **Phases** — the fight changes at HP thresholds, demanding a different answer.
  Telegraph the transition clearly; an unannounced phase change reads as a bug.
- **Enrage** — a soft timer. Preferable to a hard timer because it fails the
  under-geared without punishing the merely slow.
- **Adds** — tests target priority and area damage.
- **Environmental pressure** — a persistent drain that makes the fight a race.

Each should have a **pre-fight answer** and a **visible tell**. A mechanic the
player cannot see coming and cannot prepare for is a random loss, and random
losses in a long fight are the fastest route to a player quitting.
