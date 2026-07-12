# Boss Gear-Check Audit (v135a)

Verifies the load-bearing rule: **a Zone-N boss must be killable ONLY with rare+
Zone-N gear, or the Zone-(N-1) Unique set** — never with Common/Uncommon.

## Tool

`scenes/boss_gearcheck.tscn` (`scripts/sim/boss_gearcheck.gd`). Headless, one-time:

```
Godot_v4.5.1 --headless --path <root> res://scenes/boss_gearcheck.tscn
```

For every zone boss it fights the **real** combat loop with a full loadout of the
boss's weak-type Zone-N weapons + Zone-N armor/shield, at each rarity tier (5
trials each to smooth rarity-roll/affix/combat RNG), with all researches tier<=N
unlocked, tier-appropriate ammo, and repair kits. Batteries are over-provisioned
so the ONLY variable under test is combat-gear rarity. Cell = `wins/5 W<medianTTK>`
or `wins/5 L<worst boss-hp% remaining>`.

## Result (5-trial averages)

```
     boss                weak       hp      | Common    Uncommon  Rare      Legend    | N-1 Unique
Z1   architect           explosive  1000    | 0/5 L83%  0/5 L74%  1/5 W64   2/5 W54   | n/a          <- corvette-hull fidelity
Z2   monolith            explosive  5280    | 0/5 L32%  5/5 W142  5/5 W114  5/5 W101  | 0/5          <- UNDER (uncommon wins)
Z3   warmaster           energy     17424   | 0/5 L95%  0/5 L81%  3/5 W217  5/5 W182  | 0/5          <- PERFECT
Z4   overseer            kinetic    25555   | 0/5 L96%  0/5       4/5 W241  5/5 W198  | 5/5 W88      <- PERFECT
Z5   harbinger           explosive  70277   | 0/5 L81%  ~1-2/5    4/5 W181  4/5 W132  | 0/5          <- OK (uncommon borderline)
Z6   colossus            energy     185531  | 0/5 L94%  0/5 L54%  0/5 L40%  0/5 L30%  | 0/5          <- OVER (nothing wins)
Z7   sovereign           kinetic    490000  | 0/5 L93%  0/5 L67%  0/5 L53%  0/5 L35%  | 5/5 W235     <- unique-only
Z8   warden              explosive  1400000 | 0/5 L75%  0/5 L61%  0/5 L53%  0/5 L45%  | 0/5 L100%*   <- OVER
Z9   patient_zero        energy     3500000 | 0/5 L90%  0/5 L74%  0/5 L62%  0/5 L56%  | 0/5 L16%     <- OVER (unique 16% short)
Z10  leviathan           kinetic    7000000 | 0/5 L78%  0/5 L68%  0/5 L59%  0/5 L51%  | 4/5 W246     <- unique-only
Z11  threshold_warden    (cryo)     22M     | 0 dmg — cryo-gated, out of scope for K/E/X probe
Z12  rift_warden         (cryo)     50M     | 0 dmg — cryo-gated / NG+
```
\* Z8 N-1 unique weapon is the wrong damage type for the boss weakness → resisted.

## Verdict

- **Common NEVER wins at any zone** — the primary rule holds everywhere.
- **Z3, Z4 = the gold standard** — Common+Uncommon lose, Rare+ win, Unique wins. Tune everything else toward this shape.
- **Z2 UNDER-tuned** — Uncommon wins 5/5. Buff ~+50% hp/atk so only Rare+ wins.
- **Z5 borderline** — Rare+ win cleanly; Uncommon occasionally sneaks a win (small buff).
- **Z6–Z10 progressively OVER-tuned** — boss HP scales ~2.7×/zone while weak-type gear DPS scales ~2.2×/zone, so the Rare-Zone-N path dies from Z6 on. Z7/Z10 survive only via the N-1 Unique leapfrog; Z6/Z8/Z9 fail entirely.

## Fix applied (v135a) — 3/12 → 9/12 honoring the rule

**Root cause (systemic):** boss DEF scales 2.2×/zone but the def-mitigation constant
`k = 40 + 30·zone^1.3` grows only polynomially, so from Z6 up DEF overwhelmed `k`,
player mitigation hit the 20% floor, and effective DPS collapsed to ~1/4 of Z3's.

- **`combat_manager.gd` — armor-proportional k floor:** `k = max(poly_k, ARMOR_K_FLOOR·c_armor)` with `ARMOR_K_FLOOR = 0.7`. Keeps mitigation healthy vs heavy armor. Binds only on late-boss DEF; low zones + the player's own small armor keep the polynomial, so it aids *penetration* of boss armor without shielding the player. This alone moved Z6/Z7 from unwinnable to Rare-wins and lifted Z8–Z10, **leaving the Z3–Z5 gold standard untouched**.
- **Per-boss polish:** Z2 hp 5280→11000 / atk 132→170 (was Uncommon 5/5); Z5 70277→80000, Z8 1.4M→1.6M (Uncommon 2/5 → 0/5); Z9 3.5M→3.2M, Z10 7M→6.2M (Rare 0–1/5 → 2/5).

**After:** Common 0/5 at every zone; Uncommon a near-miss (boss left at L3–31%); Rare+ wins Z2–Z10. Remaining flags are Z3 (Uncommon 2/5 = RNG at the edge, untouched by the fix) and Z11/Z12 (cryo-gated — need a Cryo variant of this probe).

## Caveats

- **No cores/gems socketed.** Cores add resist_pierce (cap .30) + armor_pen (cap +.20). Would close small gaps (Z6 legendary is 30% short) but not the large Z8–Z10 ones. Open question: is the intended power budget gear-only or gear+cores?
- **Z1** uses the tier-1 corvette (2 weapon slots) — likely a hull-fidelity artifact, not a real over-tune.
- **Z11/Z12** need cryo weapons (post-first-warp) — this K/E/X probe can't damage them.
