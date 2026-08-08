# Economy: sources, sinks, and what money is for

## The one rule

**Every currency needs a faucet and a drain, and you must be able to name both.**

If you cannot say where a resource comes from and where it permanently leaves
the economy, you are designing inflation and will discover it three months after
launch when the auction house is meaningless.

Write it as a table before you ship anything that touches currency:

| Currency | Faucets | Drains | Net at hour 1 / 10 / 100 |
|---|---|---|---|

A drain must **destroy** the resource, not move it. Trading between players is
not a sink. Buying an item from another player is not a sink; the vendor cut on
that trade is. Crafting that consumes materials is a sink; crafting that returns
them on disassembly is not.

## Diagnosing a sick economy

**Symptom: players hoard and nothing feels worth buying.** Sinks are too weak or
too optional. Add a recurring cost — upkeep, repair, consumables — or a
high-value optional purchase that scales. Recurring beats one-off: a one-time
sink is absorbed and then the problem returns.

**Symptom: everything is grindy and players feel poor.** Faucets are too weak
relative to costs, or costs grew exponentially while income grew linearly. Check
whether income scales with the same curve as costs. This is the single most
common economy bug in RPGs — content designers scale costs by tier and forget
that income did not.

**Symptom: one activity dwarfs all others.** You have an income dominated
choice, and every other activity is now decorative. Either bring the others up
or accept it and cut them. Do not nerf the fun one first; find out *why* it is
better, because the reason is usually a multiplier interaction nobody planned.

**Symptom: new players cannot afford anything veterans consider trivial.** Your
curve is right but your entry point is wrong. Consider a separate early-game
currency, or price early content in absolute terms and late content in relative
ones.

## Currency roles

Keep currencies few and give each a distinct job. Three is a healthy maximum for
most RPGs:

- **Soft currency** — earned constantly, spent constantly, the pulse of the
  moment-to-moment loop
- **Hard/premium currency** — scarce, saved for meaningful choices
- **Meta/prestige currency** — earned by long-term achievement, spent on
  permanent progression

A fourth currency needs to justify itself against "why is this not just soft
currency with a different sprite". The test: does it enable a decision the
existing currencies cannot express? If two currencies are earned from the same
activity and spent on the same things, they are one currency with extra UI.

**Resources are currencies too.** A crafting material with a market value is
subject to every rule above.

## Crafting chains

Depth is what makes early resources matter late. The design question is how
deep, and the answer is usually deeper than the first draft.

A useful discipline: **define a minimum ingredient depth per tier.** Tier 8
recipes may not name a raw gathered material directly; they name something four
processing steps removed from raw. The raw material still matters — enormously,
because thousands of units flow up the chain — but the player interacts with it
through infrastructure rather than by clicking a rock 4000 times.

This does three things at once: it makes early gathering permanently relevant,
it forces automation to become the answer, and it turns "how do I get X" into a
supply-chain puzzle rather than a grind.

Two things to check whenever you touch a chain:

- **Dead ends.** A material with no consumer is a slot-inventory tax and a
  disappointment on every drop.
- **Deadlocks.** A material that is demanded but has no reachable source at the
  point it is demanded. These are invisible until a player hits them, and then
  they are progression-stopping.

Both are mechanically checkable — walk the recipe graph and assert every
material has at least one producer and one consumer reachable at its tier. Do it
in a test, not by eye; the graph gets big fast.

## Drop tables and expected value

State a drop table's **expected value per unit of time**, not per kill. The
player experiences time.

For a rare drop at rate `p`, the median number of attempts is `ln(2)/p ≈ 0.69/p`
and the mean is `1/p`, which means **most players get it faster than average and
a long unlucky tail gets it much later**. Half your players will beat the mean.
The unlucky decile at `p = 1%` needs ~230 kills against a mean of 100. Decide
deliberately whether that tail is acceptable — and if it is not, use bad-luck
protection (an escalating rate, or a hard pity counter) rather than raising `p`,
which makes the drop worthless for everyone else.

Sample your tables with an actual simulation. Intuitions about compound
probability across a multi-item table are reliably wrong.

## Sinks that feel good

Not all drains are equal. Ranked roughly by how well players tolerate them:

1. **Optional power** — buy the next tier when you want it
2. **Convenience and capacity** — inventory slots, faster travel, more build
   slots
3. **Cosmetics** — infinite ceiling, zero balance impact
4. **Consumables** — recurring, scales naturally with activity
5. **Upkeep and maintenance** — recurring and scaling, but must stay well under
   the income the maintained thing produces or it reads as a punishment for
   building
6. **Repair on failure** — acceptable when failure was avoidable
7. **Flat taxes on activity** — tolerated only when invisible or tiny
8. **Durability loss on ordinary use** — usually resented; the player pays for
   playing

Prefer sinks the player chooses. A sink attached to a decision ("do I want
this?") reads as an economy; a sink attached to existence ("you pay rent")
reads as a leak.
