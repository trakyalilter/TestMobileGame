# Hack Stones — Module Crafting Currency

**Status:** DESIGN / NOT IMPLEMENTED (spec only).
**Loop:** Meta (Ship Designer / itemization) — the auto-battler's depth lives in the pre-fight build screen; this makes that screen a forge instead of a slot machine.
**Subsystems touched:** `shipyard_manager.gd` (affix system), `combat_manager.gd` (loot rolls), `research_manager.gd` (gate tech), `designer_page.gd`/`designer_slot_widget.gd`/`module_card.gd` (drag-drop UI), `save_game`/`migrate_save`.
**Origin:** port of Path of Exile 2's currency-orb crafting, adapted to Horizon Idle's fixed-affix-count rarity model.

---

## Player fantasy

*"That Legendary you farmed has three great rolls and one dud — so you don't scrap it, you crack open your hoard of salvaged data-stones, lock the keepers, and gamble the dud into something better."* Combat farming gains a permanent second reward axis (crafting material), and Liras gain a genuine deep endgame sink.

---

## The load-bearing insight

In PoE, "add a mod" and "raise rarity" are separate axes with prefix/suffix bookkeeping. **In Horizon Idle, rarity IS the affix-count budget:**

| Rarity | Affix count |
|---|---|
| COMMON | 0 (fixed-stat, no `custom_` instance) |
| UNCOMMON | 1 |
| RARE | 2 |
| LEGENDARY | 3 |
| UNIQUE | 4 |

That collapse welds PoE's "augment" and "raise rarity" into a single operation and deletes the fiddliest, most idle-hostile part of the source system (prefix/suffix caps). So the correct port is a **merged 7-stone set + 1 invented "lock" stone (8 total)** — not the literal 9 orbs.

---

## The stone set

Drag-drop a stone onto an equipped or inventory module in the Ship Designer's new **Hacking** sub-tab. Every application that changes rarity or destroys/rerolls an affix shows a **before → after confirm popup**; trash-tier stones apply instantly.

| # | Hack Stone | PoE2 origin | Exact effect | Input | Drop source & rate |
|---|---|---|---|---|---|
| 1 | **Splice Chip** | Transmutation | COMMON → materialize `custom_` instance at **UNCOMMON**, roll **1** legal affix (15% GA). Applies Uncommon base-stat boost once, then base stats lock. | COMMON | Z1+ ~25%/kill; craftable |
| 2 | **Firmware Injector** | Alchemy | COMMON → materialize at **RARE** with **2** fresh legal affixes (skips Uncommon; the instant-usable base). | COMMON | Z2+ ~12%/kill, boss guaranteed 1; craftable |
| 3 | **Root Key** | Regal (+ absorbs Augmentation & Exalted) | Rarity **+1 tier**, **keep all existing affixes + values**, roll **1** new legal affix into the opened slot (15% GA). | UNCOMMON–LEGENDARY | Z3+ boss ~8% / elite ~6%; craftable |
| 4 | **Corruption Worm** | Chaos | **Remove 1 random affix, roll 1 new** legal affix (no dupe, respects slot `limit_to`, 15% GA). Count & rarity unchanged. Locked affixes excluded from removal. | RARE+ | Z5+ ~5%/kill; craftable |
| 5 | **Resonance Calibrator** | Divine | Reroll the **value** of every non-locked affix within its zone-scaled range. Re-runs GA check per affix (only stone that can gain a GA on a placed affix). Identities/count/rarity/base untouched. | UNCOMMON+ | Z8+ boss ~3%, Warden guaranteed, Recursion lane; **not craftable** |
| 6 | **Purge Spike** | Annulment | Remove 1 random **non-locked** affix **and drop rarity 1 tier** (the undo/recovery verb). | RARE+ | Z9+ boss ~2%, Recursion lane; **not craftable** |
| 7 | **Precursor Echo** | Mirror of Kalandra | Exact duplicate (affixes, values, GA flags, base stats; **sockets emptied, durability → 100**). Copy is tagged `echoed:true` → refuses ALL stones forever, cannot be Echoed, cannot copy a UNIQUE-base or an already-echoed module. | any `custom_` | **Not a mob drop** — quest reward (1) + one gated Recursion deep-lane only |
| 8 | **Anchor Bolt** *(invention — no PoE2 equiv)* | — | **Lock 1 chosen affix.** Locked affixes are excluded from Corruption Worm / Resonance Calibrator / Purge Spike. Max **1 anchor per module**; right-click to release (free). | any `custom_` | Z4+ ~1.5%/kill; craftable |

**Cut / merged from the literal 9:**
- **Augmentation → CUT** — no "open slot" state exists (count is rarity-locked); its verb is inside Root Key.
- **Exalted → MERGED into Root Key** — "add an affix" and "raise rarity" are the same operation here. With no player-to-player trade, PoE's need for Exalted as a benchmark currency doesn't exist.

**Anchor Bolt is the idle keystone.** Without it, rerolling means "gamble and pray you don't lose your good roll." With it, rerolling means "keep the keeper, reroll the trash." Ship it *with* the first reroll stone, never after.

---

## The crafted-common rule (the load-bearing edge case)

Crafted COMMON modules are fixed-stat base ids with **no `custom_` instance and no affix dict**. One rule the player learns once:

> **"Splice wakes it up; everything else needs it already awake."**

- Only **Splice Chip** and **Firmware Injector** accept a raw COMMON — they reuse the existing equip-time materialization path to mint a `custom_<base>_<ticks>_<seq>` instance, then apply their rarity + affix roll.
- **Base stats get the target rarity's boost once at materialization, then lock forever.** No stone ever re-rolls base `custom_stats` again. (This is the critical anti-exploit — see 5.1.)
- Every other stone hard-refuses a raw COMMON with a clear toast: *"Fixed-stat component — use a Splice Chip to awaken it first."* No stone consumed.
- Already-equipped Commons already have a `custom_` instance (equip minted one), so they behave normally — no special case in the player's head.

**Why keep the Common on-ramp:** it decouples "having something to craft" from drop RNG. A crafting-first player can always craft a cheap Common base and Splice it, so the F2P/engineer path is never gated on lucky drops.

---

## Progression & gating

One research gate: **`firmware_hacking`** (~Z3-era) reveals the Hacking sub-tab and enables stone drops. Invisible to the brand-new Z1 player; arrives exactly as the first Legendaries drop and "keep or scrap?" gets interesting.

| Phase | Stones online | Player experience |
|---|---|---|
| Early (Z1–Z3) | Splice, Injector | Turn junk Commons into rollable Uncommon/Rare bases. Abundant trash stones. |
| Mid (Z3–Z5) | + Root Key, Anchor Bolt | Climb the rarity ladder while protecting keepers — the controlled-craft bridge. |
| Mid-late (Z5–Z7) | + Corruption Worm | Swap the one bad affix on an otherwise-great Legendary. Highest-volume stone. |
| Late/Endgame (Z8+) | + Resonance Calibrator, Purge Spike | Perfect the numbers; undo over-commits. Scarce → "perfect all 4 rolls" is a multi-session goal. |
| Capstone | Precursor Echo | Freeze one god-item forever. Vanishingly rare, no mob source. |

**Tuning principle:** a player clearing Zone N gets enough Splice/Injector/Root Key/Anchor to fully craft *the gear that zone drops*, but Calibrator/Purge/Echo lag one tier — perfecting is always a slight stretch goal. Classic idle "always almost enough."

**Warp/prestige tie-in:** stones are consumable **items** → they **survive Warp** (crafting supply is meta-progression, not raw power); cleared only by hard reset. This gives the Z11 Threshold Warden and Recursion lanes meaningful **non-power** rewards, extending the endgame chase without power-creeping the flattened combat numbers. The free first-Warp Cryo-Lance can be Spliced into a rollable instance — your prestige-gift weapon becomes a crafting canvas. Slots naturally **after Step 5 (P5 Unique-tier modules)**: P5 adds drop targets worth crafting toward; Hack Stones add the agency to steer any drop there.

---

## Economy

**Per-application Lira cost** (the anti-exploit + the deep sink), scaled by the module's target rarity, mirroring `RARITY_SELL_PRICES`:

| Target rarity | Lira cost / application |
|---|---|
| Uncommon | 500 |
| Rare | 3,000 |
| Legendary | 20,000 |
| Unique | 100,000 |

**Sources:** combat `rare_loot` rolls (rates in the stone table) + crafting recipes for the craftable stones (Splice/Injector/Root Key/Worm/Anchor). **Not craftable:** Calibrator, Purge Spike, Precursor Echo (endgame/Recursion/quest only). **Sinks:** Liras per application + the stones themselves + recipe materials for crafted stones. Demolishing a module grants SpareParts, **never** stones — there is no closed positive cycle.

---

## Failure modes & exploit audit

| # | Threat | Mitigation |
|---|---|---|
| 5.1 | **Infinite-reroll / free-craft loop** (craft Common → Splice → demolish → repeat) | Demolish gives SpareParts never stones; every application costs Liras; base stats lock at materialization. Every loop is net-negative on Liras + materials. No closed positive cycle. |
| 5.2 | **Mirror duplication abuse** (Echo a god-item, Echo the copy…) | Echoed modules are permanently frozen (`echoed:true`): can't be Echoed again, can't be Hack-Stoned, can't re-socket, can't copy a UNIQUE-base. Echo has **no mob source** — quest (1) + one gated Recursion lane. One Echo ≈ one god-item, ever, per source. |
| 5.3 | **Deterministic-BiS trivialization** (cheap rerolls → everyone converges, loot dies) | Base-stat lottery still lives on drops (stones never touch base stats). GA is a **15% gamble per roll, never buyable** → all-GA Unique ≈ 0.15⁴ ≈ **0.05%**. Value reroll is Z8+ scarce + Lira-gated. Affix *identity* in a slot is still random (Anchor locks what you *have*, not what you'll *get*). Perfect gear stays a long tail. |
| 5.4 | **4th-currency bloat** vs the three-currency rule | Stones are **items** (item-class like SparePart / matrix cores), never a fungible price denominator or balance gate. The three-currency discipline governs *currencies* (Liras / Exotic+Shards / Energy). SpareParts set the precedent. **No 4th currency.** |
| 5.5 | **FOMO / premium-safety** | Stones are pure gameplay drops/crafts, **never purchasable**, no timers, no expiring rewards. Precursor Echo is rare but never-expiring. HARD NO on any future "buy a stack" IAP — out of bounds. |
| 5.6 | **Float precision (2⁵³)** | Stones only roll affix values within existing zone-scaled ranges (same the drops use) — no new magnitude channel. Crafting can't exceed a naturally-dropped Unique's magnitude, just makes hitting it reliable. Log for the BigNumber audit; no action now. |
| 5.7 | **Mobile drag-drop UX** | Reuses the existing gem-insert/equip drag grammar. Dedicated **Hacking** sub-tab (doesn't eat the 28 gear/element slots). **Batch "Apply ×N"** for Calibrator (auto-stop at ≥85% of max roll) so no one drag-drops 40 times. |
| 5.8 | **Bricking a beloved item** | Anchor Bolt locks the keeper; Purge Spike is the recovery path; Precursor Echo freezes before further gambling. **No stone can destroy a module** — worst case is a bad affix, never item loss. Risk is opt-in and recoverable. |
| 5.9 | **GA highlight desync** (value changes, `greater_affixes` array doesn't) | Every stone that adds/removes/rerolls rewrites `greater_affixes` from what was actually written (single source of truth) and re-runs the naming + rarity-label block so the name stays truthful. |
| 5.10 | **Illegal/duplicate affix** (sensor-only affix on a weapon; a dupe) | Every rolling stone builds its pool exactly like `generate_module_drop`: `AFFIX_DB` filtered by the host slot's `limit_to`, minus affixes already present. Factor into a shared `_apply_affixes()` helper both the stones and the drop generator call. |
| 5.11 | **Save-shape break** (new fields on old saves) | New per-module fields default cleanly (`anchored_affix: ""`, `echoed: false`); stone counts default 0. One `migrate_save` step back-fills defaults on pre-feature `custom_modules`. Respects the versioned + atomic-write rule. |

**Resolved open question:** *Should Calibrator value-rerolls be allowed to lower a value?* **Yes — true gamble, floored only by the range minimum, with a batch auto-stop threshold.** A pure-upgrade "never below current" version burns too few stones and kills the sink; the true gamble keeps the sink healthy, and the auto-stop ("stop at ≥85% of max roll") removes the tedium.

---

## Implementation plan (build reference — not implemented)

**Spine: a shared `_apply_affixes()` helper**, factored out of `generate_module_drop`, that all stones AND the drop generator call. Responsibilities: build the legal pool (`AFFIX_DB` filtered by slot `limit_to`, minus present affixes), roll affix(es), run the 15% GA check per affix, write `greater_affixes` from what was actually placed, and re-run the naming + rarity-label block. Single source of truth → kills the desync (5.9), illegal-affix (5.10), and GA-truthfulness classes at once.

**Reference anchors** (approximate — verify at build time; the game version has since moved):
- `shipyard_manager.gd`: `generate_module_drop` (pool filter, GA, naming, `RARITY_STAT_RANGE`), the base→custom materialize path (~`handle_module_defeat`'s converter), `get_affix_scaled_range`.
- `combat_manager.gd`: existing `rare_loot` plumbing for stone drop rolls.
- `research_manager.gd`: new `firmware_hacking` tech.
- `designer_page.gd` / `designer_slot_widget.gd` / `module_card.gd`: Hacking sub-tab + drag-drop + confirm popups.
- `save_game` / `migrate_save`: `anchored_affix`, `echoed`, stone counts.

---

## MVP vs full system

**MVP — ship first (the vertical slice that proves the fantasy):**

- **Splice Chip** — entry ramp; without it there's nothing to craft.
- **Firmware Injector** — instant Rare base; immediate craft targets.
- **Root Key** — the rarity-climb "numbers go up" verb.
- **Anchor Bolt** — the idle keystone; ship it *with* the reroll, not after.
- **Corruption Worm** — the one reroll verb; proves the gamble loop.

MVP infra: the shared `_apply_affixes()` helper, the `firmware_hacking` tech + Hacking sub-tab, drag-drop + confirm popups, per-application Lira cost + Common-refusal toasts, save migration, and combat drop rolls for the 5 stones. **Rough effort: ~4–6 dev-days** (heavy lift is the helper + drag-drop wiring; the stones are thin once the helper exists).

**Fast-follow — the endgame chase (~3–4 dev-days on top):**

- **Resonance Calibrator** — value-perfection + batch Apply ×N with auto-stop (~1.5d, batch UI is the cost).
- **Purge Spike** — recovery/undo (~0.5d).
- **Precursor Echo** — capstone; frozen dupe + quest/Recursion gate + freeze-state guards across every system (~1.5d).

**Do NOT ship in v1:** batch-apply for anything but Calibrator, any second research tech, or Precursor Echo before the Recursion/Warden endgame exists to gate it. Ship the MVP, confirm Anchor + Worm feels good, *then* layer perfection on top.

---

## Synergy note

If the parked **K/E/X damage-type resistance** system ever ships as a rollable defensive affix, Hack Stones become the agency layer for it: instead of praying for a drop with the right resist profile for a zone, a player *steers* a module toward it (Root Key to add, Worm to swap, Anchor to lock, Calibrator to max). The two features compound — build first, or in either order.
