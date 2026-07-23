# Steam Store Copy — Horizon Idle DEMO

Rewritten 2026-07-23 after Steam review caution:
> "Your written description does not give enough information about what's included in this demo
> when compared to the full game. If possible, please clearly describe what content is included
> in this specific product."

Fix: an explicit **WHAT'S IN THE DEMO** block placed high in the description (before the pillars),
plus a **WHAT THE FULL GAME ADDS** block at the bottom. Both use concrete counts, not vibes.

---

## SHORT DESCRIPTION (max 300 chars)

```
Free demo. A space-themed idle RPG of skilling and crafting: mine, refine, research and automate
your way from a lone ship to an industrial empire. Play Sectors 1-3 and trigger your first Warp
prestige. No time limit, no energy gates, and your save carries into the full game.
```

(297 chars.)

---

## GENERAL DESCRIPTION

Steam BBCode tags shown inline. Strip them if pasting into a plain field.

```
[h2]HORIZON IDLE — FREE DEMO[/h2]

Strand a lone ship at the edge of charted space and turn it into a self-running industrial
empire. Horizon Idle is a space-themed skilling and crafting idle RPG: commit to one task,
automate the rest, and watch the numbers climb — online or off.

[h2]WHAT'S IN THIS DEMO[/h2]

This demo is the opening arc of the full game, played end to end. It has no time limit and no
paywall — it stops at a content boundary, not a timer.

[list]
[*] [b]Combat Sectors 1-3 of 15[/b] — Lunar Orbit, the Asteroid Belt, and the Mars Debris Field,
    including all three sector bosses and their module drop tables.
[*] [b]All four skill lines, uncapped[/b] — gathering, processing, research and combat progress
    on the full 1-100 curve. Nothing is level-locked below the content boundary.
[*] [b]The full core loop[/b] — single-active-task skilling, the crafting economy, always-on
    infrastructure buildings, per-sector bounty boards, the ship loadout designer, and offline
    progression exactly as they work in the full game.
[*] [b]One complete prestige[/b] — kill the Sector 3 boss, tear open the Singularity, and run the
    Warp Core reset once. You keep your research, you spend your first Warp Shards, and you see
    what the meta-progression actually feels like.
[*] [b]Roughly 5-8 hours of active play[/b] to reach the Warp, plus however long you leave it
    running.
[*] [b]Your save carries over[/b] — buy the full game and continue from the same empire. Nothing
    is replayed.
[/list]

The demo ends after your first Warp. Sectors 4 and beyond, the rest of the Warp Mastery Tree, and
the endgame are not included — see the full-game list at the bottom.

[h2]COMMIT TO THE GRIND, ONE TASK AT A TIME[/h2]

This isn't a clicker. Choose a single focus — mine raw elements, refine them into advanced
materials, research new tech, or send your ship into combat — and every tick earns resources and
skill XP. Level each skill from 1 to 100 along a deep, satisfying XP curve, unlocking better
actions, recipes and gear at every milestone. The real game is the decision: what's the best use
of your next hour?

[h2]AUTOMATE EVERYTHING[/h2]

While you focus on the active grind, your infrastructure never sleeps. Build always-on production
facilities, run background bounty contracts, and overclock your factories for exponential output.
Walk away and come back to a fat offline-progress report — your empire keeps earning while you're
gone.

[h2]BUILD THE PERFECT SHIP[/h2]

Salvage modules from escalating combat sectors and engineer the ultimate loadout — kinetic,
energy, missile and shield systems, plus the exotic Cryo and Corrosion armaments the deeper
frontier demands. Combat is a pure auto-battler: no twitch reflexes, every fight is won or lost in
the loadout designer before you engage. Hunt sector bosses for rare and unique drops that rewrite
your build.

[h2]WARP, RESET, ASCEND[/h2]

Cross the threshold and a black hole opens on your Sector Chart. Fly into it and trigger the Warp
Core: a prestige reset that trades your progress for permanent Exotic Matter and Warp Shards.
Spend them in a branching Mastery Tree, keep your research forever, and return faster and stronger
every loop. Your first Warp is hours away — mastering the full tree is a journey of days.

[h2]NUMBERS GO UP. FOREVER.[/h2]

A premium, single-purchase game built for the long haul. No energy gates. No stamina timers. No
pay-to-win microtransactions. Just deep, honest idle progression.

[h2]WHAT THE FULL GAME ADDS[/h2]

[list]
[*] [b]Combat Sectors 4-15[/b] — the full escalation through Sector Epsilon, the warp-hardened
    Threshold, and the Corrosion frontier beyond it.
[*] [b]The complete Warp Mastery Tree[/b] — both branches, every node, and an endgame prestige
    arc measured in days rather than hours.
[*] [b]Exotic armaments[/b] — Cryo and Corrosion weapon lines, and the enemies that require them.
[*] [b]The full research tree[/b] — 100+ technologies gating advanced recipes, buildings and
    sectors.
[*] [b]The full mission campaign[/b], the deeper crafting economy, larger hulls up to dreadnought,
    fleet support ships, and module modification.
[*] [b]New Game Plus[/b] — repeatable frontier loops with stacking sector modifiers and
    escalating rewards.
[/list]

No microtransactions. No energy gates. No FOMO. One purchase, the whole game.
```

---

## Notes / owner action items

1. **The 5-8 hour figure is an estimate** derived from the v138 cadence (first Warp lands at the
   Zone 3 boss, week one at ~1h/day). Verify against a real playthrough before publishing — a
   wrong playtime claim is the kind of thing reviewers and players both punish.
2. **The demo build must actually enforce the boundary.** Currently nothing does — see
   "Demo gating work" below. Publishing this copy against an ungated build is a false claim.
3. **Save carry-over** is asserted in the copy. Confirm the demo and full-game save paths are
   compatible (same `save_game` version, same `user://` filename) or drop that bullet.

### Alternative: if the demo ships ungated (whole game, no cut)

Replace the whole `WHAT'S IN THIS DEMO` block with:

```
[h2]WHAT'S IN THIS DEMO[/h2]

This demo is the complete current build of Horizon Idle, unrestricted: all 15 combat sectors, the
full research tree, the entire Warp Mastery Tree and the New Game Plus frontier. There is no time
limit, no content lock and no paywall.

What the paid release adds is continued development: new sectors, new frontier loops, and ongoing
balance and content updates. If you enjoy the demo and want the game to keep growing, that's what
you're buying.
```

...and delete the `WHAT THE FULL GAME ADDS` block. This is honest, but it is a weak conversion
pitch and Steam may still query why the demo and the paid product are the same build.

### Demo gating work (if taking the recommended cut)

Rough shape, ~1-2 hours:

- `combat_manager.gd::get_available_zones` — add a `DEMO_MAX_ZONE_DIFFICULTY = 3` gate alongside
  the existing `unlock_flag` check, so Sectors 4+ never list.
- `warp_manager.gd` — allow `total_warps` to reach 1, then present a "demo complete" panel instead
  of a second Singularity. Mastery Tree stays spendable for the shards earned.
- Research / missions — anything whose prerequisite is a Sector 4+ clear is already unreachable;
  audit for nodes that would sit visible-but-unbuyable and hide them (see the research_page
  `graphs` allowlist gotcha in CLAUDE.md — a tech missing from the allowlist is invisible AND
  softlocks its mission).
- Gate behind one const so the paid export flips a single flag.
```
