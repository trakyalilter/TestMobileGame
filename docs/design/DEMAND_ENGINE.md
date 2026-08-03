# Station Procurement — the rate-based Demand Engine (spec, 2026-08-02)

**Player fantasy:** the sector *needs* what your factories make. Every line you bring online
— resin, circuits, carbide, dreadnought frames — has a standing buyer at the station, and
the order book grows with your industrial empire. You are not selling scrap; you are the
sector's supplier of record.

**Loop:** META primarily (the always-on parallel layer finally has a purpose between
refits); CORE secondarily (a new "is my next hour better spent expanding a line?"
decision). **Subsystems:** `quest_manager` (supply orders v2 — this replaces the 4-good
`supply_goods` table), `infrastructure_manager` (rate measurement, read-only),
`element_db` (unit-price + family tables), `ui/quest_page` (family-tabbed board),
sim (`supply_board_check.gd`, funnel re-run). No combat changes.

**Owner decisions this encodes:** sell path removed TOTALLY (UI gone) — confirmed
2026-08-02 · demand engine before Loop 2 · "multiples of EVERY family via rate-based
demand" (HANDOFF goal line) · premium, zero FOMO · three-currency discipline (rewards are
Liras only).

---

## A. WHY (measured, from the 2026-08-02 economy audit)

- Demand is refit-shaped: module bills, 94 item-costed techs, building costs and hulls are
  one-time. Standing flows today: generator fuel, T1–T3 ammo, consumables, and a supply
  table that touches **4 goods in 15 tiers** (T5+ is literally AdvCircuit/Superalloy
  alternating). None of the 9 fabrication-tier families ever has a buyer.
- With selling deleted, surplus has **zero outlets** until E5 ships. A 34-type Z10 complex
  has nothing to do between refits; the rational endgame move is throttling it down.
- The engineer has no Lira lane at all now. Combat carries ~100% of income. The fun-audit
  already measured captain-starved mid-funnel days (30/60/0 g/p/c mix); the inverse
  problem — factory-invested players with no income identity — ships with sell removal.

## B. THE SYSTEM IN ONE PARAGRAPH

A **Procurement board** (family-tabbed, replacing the supply-order section of the quest
board) offers never-expiring orders for **factory-producible goods only**. Order
**quantity** is sized from the player's own measured line rate (~30 min of output).
Order **reward** = quantity × a **fixed authored unit price** per good — so income scales
linearly with factory investment. The governor that keeps it from printing is a per-family
**24h demand pool** ("the station only needs so much"): a visible, continuously-refilling
value budget per family, sized so that a fully-invested engineer earns **~35% of era
combat income** across all families. Nothing expires, nothing is lost offline — stock
accumulates, pools refill, the returning player batch-claims. The factory is the timer.

## C. DATA — families, eligibility, prices

### C1. Eligibility rule (one sentence)

A good is board-eligible **iff it has an infrastructure producer** (drill outputs excluded
— gathering already has stockpile quests; combat-fed producers excluded — except ordnance,
where the combat-side inputs are the point). Zone alloys, exotics and trinkets stay
board-ineligible: alloys are processing's refit identity, not freight.

### C2. Families (tab appears when the first building of the family is owned)

| family | goods (all have live producers at HEAD) | era online |
|---|---|---|
| REFINING | Fe, Si, Cu, Sn, Zn, Ni, Cr, Co, Mg, Li, Al, Ti, Au, Germanium | Z2–Z3 |
| CHEMICAL | C, H, O, Graphite, Resin, Fiber, CompositeWeave | Z3–Z4 |
| STRUCTURAL | Steel, StructuralComponent, GalvanizedSteel, StainlessSteel, Superalloy | Z3–Z5 |
| ELECTRONICS | Circuit, Semiconductor, Chip, AdvCircuit | Z3–Z5 |
| ORDNANCE | SlugT1–T4, CellT1–T4, MissileT1–T4 | Z2+ (T4 needs step 2) |
| FABRICATION | NanoSubstrate, SinteredCarbide, PrecisionLattice, FabricationBus | Z6–Z8 |
| CAPITAL | NeutroniumPlate, VoidLattice, CapitalSpar, DreadnoughtFrame | Z9–Z10 |

7 families ≈ the infrastructure page's own mental model. A family with zero owned
buildings shows ONE **dormant contract** card — "Station demand: <family>. Requires an
operating line." — demand advertised before supply, the factory tier's own onboarding
trick, without ever generating an unfillable order.

### C3. Demand pools — the income governor

`pool_value_per_24h(family) = ERA_INCOME_PER_H(frontier) × ENGINEER_SHARE / families_online`

with `ENGINEER_SHARE = 0.35` (tunable 0.30–0.40) and the era income table the cost curve
already uses (Z4 67.5K/h … Z10 112.5M/h, from the 6h budgets). Worked values:

| frontier | era L/h | families online | pool per family per 24h |
|---|---|---|---|
| Z4 | 67.5K | 4 | ~142K |
| Z6 | 630K | 5 | ~1.06M |
| Z8 | 5.625M | 6 | ~7.9M |
| Z10 | 112.5M | 7 | ~135M |

Pools refill **continuously** (value/86400 per second, ticks offline like bounty refresh).
A full pool just sits full — nothing expires, nothing is punished. UI: one meter per
family tab, "STATION DEMAND: 84.2M / 135M — refills continuously." Pools are
frontier-keyed, so NG+ (Z11+) scales automatically off the same income table and old
families **stay demanded forever at growing volume** — "multiples of EVERY family,"
literally.

### C4. Unit prices — fixed per good, authored once

Priced so a DR-ceiling line of the good ≈ its family's pool at the good's home era
(i.e., one maxed line *can* carry its family when the good is current). ~40 values, all
in one `element_db` table. Marquee rows to anchor tuning:

| good | ceiling rate/h (DR 20×, eng where applicable) | price/unit | maxed-line L/h |
|---|---|---|---|
| Steel | 72K | 2 | 144K (caps at pool) |
| Circuit | 18.7K | 30 | 560K |
| AdvCircuit | 34.5K (eng ×2) | 165 | 5.7M |
| Superalloy | 28.8K | 200 | 5.75M |
| Resin / Fiber | 21.6K / 43.2K | 12 / 6 | ~260K each |
| StainlessSteel | 36K | 90 | 3.2M |
| SinteredCarbide | 1.9K | 2,600 | 5M |
| PrecisionLattice | 965 | 8,500 | 8.2M |
| FabricationBus | 238 | 34K | 8.1M |
| NeutroniumPlate | 3.6K | 2,300 | 8.3M |
| CapitalSpar | 238 | 55K | 13M |
| DreadnoughtFrame | 122 | 275K | 33.6M |
| SlugT2 / CellT3 / MissileT4 | — | 25 / 320 / 900 | (ordnance ladder) |

Two consequences, both intended: (1) endgame income is carried by the fabrication/capital
families — the tier you just shipped becomes the thing that *earns*; (2) old goods fade in
share but never in absolute demand (pool quantity grows with frontier), so the Z2 smelter
row keeps its job for 200 hours.

**Deliberate rejection:** frontier-scaled prices on old goods (Steel paying Z10 rates)
were rejected — that's the classic idle-game inflation bug; it deletes any reason to build
new factory types, which is the opposite of the tier's fantasy.

### C5. Order generation

Per family tab: **3 order cards**, drawn from goods with player rate > 0 (weighted toward
the family's deepest online good — depth is what we want factories to chase):

- `qty = round_qty(ORDER_MINUTES × rate_trailing_24h(good))`, `ORDER_MINUTES = 30`,
  floor 10 min of a single neutral building (so a 1-building line still gets orders).
- `reward = qty × unit_price` — shown as both total and L/unit (legibility beats mystery).
- Claim: consumed-at-claim, stock re-verified, live "own N" bar — **all shipped v139c
  mechanics, reused verbatim.**
- On claim: card refills instantly with a new order **iff the family pool has ≥ that
  order's value remaining**; otherwise the slot shows the pool meter ("Demand met —
  refilling"). Pool decrements at claim.
- Trailing-24h rate (not instantaneous) kills the throttle-down-then-claim-from-stock
  angle; snapshot at generation so open orders never resize.
- Reroll: reuse the existing escalating reroll heat unchanged.

### C6. Rush convoys — the session-spike layer (step 3, not v1)

One extra card per family: **CONVOY** — 2.5× unit price, qty = 75 min of rate, and after
claiming, the next convoy for that family docks in 8h (bounty-refresh precedent; ticks
offline; nothing expires — a cooldown is not FOMO). This is the check-in beat and the
reason a returning session opens the board first. Expected value: ~+6–8% on top of the
35% lane if every convoy is caught; sim must confirm ≤ 45% total.

## D. WHAT IT TOUCHES / WHAT IT DOESN'T

- `quest_manager`: `supply_goods` table retired (kept for legacy claim of open orders —
  defensive loaders, no save bump; bounty v139 migration precedent). New: `family_pools`
  {family: {value, ts}}, procurement generation, pool tick in `calculate_offline`.
- `infrastructure_manager`: read-only — `get_effective_yield` summed per good, plus a
  trailing-24h EMA sampled on the existing production tick (one dict, saved).
- Warp: pools and boards regenerate at reset (contracts are ephemeral RNG — bounty
  precedent); rates re-measure as the new run's factories come online. Foundation Kit
  (parked) can later pre-seed a family.
- Combat, module costs, research costs: untouched. This ships zero balance risk to the
  gear game.

## E. FAILURE MODES

1. **Engineer lane eclipses combat → captain fantasy starves.** Prevention: pools cap the
   lane at 35% + convoys ≤ 45%; combat stays the top payer per active minute (the v139
   risk/attention principle). Sim-asserted, not vibes.
2. **Prestige inflation.** +35–45% income → `floor(log2(score/500K))+1` moves ≤ +0.55
   shards. Funnel assert: first-warp shards stay in the locked 15–17 band; if the +0.5
   materializes, trim ENGINEER_SHARE to 0.30 — one constant.
3. **Rubber-band feel ("I built more, orders just got bigger").** Reward = qty × fixed
   price, so bigger orders pay proportionally more; the pool meter and L/unit line make
   the linearity visible. The failure would be authoring reward-per-order flat — that
   version was considered and rejected (income/h goes flat vs investment).
4. **Chore-ification.** No expiry, no dailies, batch-claiming blessed (offline stock →
   claim spree is the *intended* return-session dopamine), one CLAIM ALL READY button per
   tab. On 720p/mobile: 7 tabs × 3 cards max, same widget as today's quest cards.
5. **Board asks for what you can't make.** Eligibility = rate > 0, dormant card otherwise;
   ordnance T4 goods enter only when step 2 ships the plants.
6. **m029–m030 interaction.** New Lira lane at Z2–Z4 is small (pool 142K/24h at Z4) but
   nonzero alongside the walls the funnel measured. Re-run the 3-seed follower funnel; the
   acceptance is deserts don't regress and the Circuit research walls chip slightly
   faster (passive supply + procurement income both point at them).

## F. NUMBERS THAT MUST SURVIVE CONTACT (verification plan)

`scripts/sim/supply_board_check.gd` (mirror `bounty_check.gd`): eligibility (no drill/
combat-fed/alloy goods; no zero-rate orders), pool decrement/refill math incl. offline
tick, claim-consumes-and-reverifies, legacy supply-order claim path, reroll heat, warp
regeneration. Then the real gates:

1. Saturated-sim engineer income = 35% ±5 of era combat income at Z6, Z8, Z10 states.
2. First-warp shard count unchanged (15–17) on the 3-seed follower funnel.
3. `player_like` gains a procurement policy **scoped like the gear-contract fix** (the
   unscoped version hijacked material farms once already — HANDOFF on record): claim only
   from surplus above the 900s feed buffer it already protects.
4. Fun-audit counters: context-switch density and MIX should *improve* d3–d7 (the board
   gives processing days a payoff event); DESERT spans must not grow.

## G. BUILD SEQUENCE (each step ends with full headless boot + probe)

1. **S1 — Engine + board (the ship):** family/price tables in `element_db`, pool engine +
   generation in `quest_manager`, EMA rate sampling in `infrastructure_manager`,
   family-tabbed UI on quest_page (bounty tab-strip pattern), dormant cards, migration.
   Probe + funnel re-run. *~everything above except convoys/T4.*
2. **S2 — Ordnance pass:** 3 T4 plants (`capital_ship_armament` gate exists; spec ratios
   from the T3 plants ×0.25 rate), ORDNANCE family live to T4. This was already next in
   the HANDOFF thread; it rides along.
3. **S3 — Convoys** (rush layer + 8h dock cadence + coach mark).
4. **S4 — E5 Reclamation Foundry** immediately after (already-specced numbers, §H of the
   factory-tier doc): with sell gone the board handles *demanded* surplus; E5 is the
   valve for *undemanded* surplus. Both outlets exist by end of this arc.
5. **S5 — polish:** first-procurement fanfare (P0 pattern), pool meter styling, CLAIM ALL.

## H. OPEN OWNER CALLS (small, none blocking S1)

- ENGINEER_SHARE 0.35 vs 0.30 — I'd ship 0.35 and let the shard assert arbitrate.
- Do convoys reward Liras only (my recommendation — three-currency discipline) or
  occasionally a hack stone (crosses lanes; bounties already own combat-adjacent drops)?
- Does CAPITAL-family demand include DreadnoughtFrame pre-Z10 clear (I say yes — selling
  frames before you can refit with them is a legitimate strategy and a lovely tension)?
- Board name: "Procurement" vs "Logistics" vs keep "Supply Orders" (my vote: PROCUREMENT
  tab title, cards keep the shipped "Supply Order:" prefix — zero loc churn on claims).
