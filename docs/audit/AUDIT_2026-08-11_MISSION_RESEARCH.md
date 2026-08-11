# Audit — mission flow + research tree (2026-08-11)

Two-stage measured audit. **Stage 1:** 11 independent lenses + a completeness critic swept the
mission chain (~111 beats) and the research tree (~113 nodes), each required to run a probe and
quote literal output rather than reason from source. **Stage 2:** 14 adversarial skeptics tried to
*kill* every critical/major finding, instructed to default to REFUTED and to treat an owner ruling
as an automatic refutation.

| | raw | after verification |
|---|---|---|
| critical | 10 | **2** (one defect, found twice) |
| major | 32 | **10** |
| minor | 17 | 19 |
| note | 2 | 13 |
| not a defect | 0 | 2 |

Verification verdicts on the 42 escalated findings: **15 CONFIRMED, 28 PARTLY_TRUE, 2 REFUTED,
1 INTENDED_DESIGN.** Two thirds of the audit's own severity ratings did not survive contact with a
second measurement. That ratio is the most useful number in this document.

Raw findings: `scratchpad/audit_findings.json`. Probe sources used by both stages were temporary
and have been removed; each finding below carries its own repro.

---

## CRITICAL

### [27] The entire NG+ Z12-Z15 gear ladder is unreachable: 4 techs are in no research tab, stranding 16 modules

**Verdict:** CONFIRMED · raised as *critical*, corrected to **critical** · lens `res_graph`

**What is actually true.** rift_armaments, verdigris_armaments, dissolution_armaments and caustic_armaments are defined in research_manager.tech_tree and are fully functional (can_unlock() -> true, unlock_tech() -> true once their prereq chain and world flag are satisfied), but they appear in no research_page.gd `graphs` tab list, so no widget is ever instantiated for them and the player has no way to click them. Every legitimate route to the Z12-Z15 ladder therefore dies: all 16 modules report can_craft=false and can_equip=false, and no mission, warp-tree node, or combat grant path targets the four techs. The 8 weapon modules DO appear in their own boss's loot tables, but _focused_drop_pool() filters research-locked ids out of the 0.30 pool and can_equip_module() re-gates any copy that does land via the unfiltered rare_loot path, so they arrive unusable. The only thing in the shipped build that can grant them is the Options -> Testing -> "Unlock All Research" debug button, which is not a progression path.

**What the original finding got wrong.** Two evidence lines are false, though neither rescues the content.

1. Section G's "all 16 report loot sources: []" is wrong for 8 of them. My scan of BOTH loot tables (the auditor evidently only read `rare_loot`):
[VER]   z12_corrosion_blaster    loot sources: ["z12_boss_rift_warden:rare_loot@1.0", "z12_boss_rift_warden:drop_pool@0.3"]
[VER]   z13_cryo_lance           loot sources: ["z13_boss_verdigris_warden:drop_pool@0.3"]
[VER]   z15_corrosion_blaster    loot sources: ["z15_boss_caustic_sovereign:drop_pool@0.3"]
[VER] of 16 modules, 8 HAVE at least one loot source
Every Z12-Z15 boss carries its own weapon pair in module_drop_pool at 0.30, and the Rift Warden guarantees z12_corrosion_blaster at 1.0 in rare_loot.

2. "cannot be obtained by any means" overstates it a second way: options_page.gd:585 `_on_dbg_unlock_all_research_pressed` unlocks every tech_tree key, and _build_testing_section() is called unconditionally at options_page.gd:81 with no OS.is_debug_build gate — so the shipped Options page contains a button that grants all four.

Neither loophole is a real path. can_equip_module() re-checks research_req against the dropped copy's base_module (shipyard_manager.gd:~6172), so a looted Z12 lance is inert in the bay; and _focused_drop_pool() (combat_manager.gd:~3673) strips research-locked ids from the pool, so the 0.30 pool path yields nothing at all — only the unfiltered rare_loot entry ever lands, and it lands un-equippable. The conclusion holds; the reported evidence does not, and "loot sources: []" is precisely the shape of probe sloppiness this project keeps getting bitten by.

Minor: the finding calls this the "fourth recurrence"; finding 45 calls it the fifth. The file documents three prior events (v137, v145 x2), so this is the fourth event covering the sixth-through-ninth tech. Not load-bearing.

**Is the proposed fix sound?** The mechanical fix works: appending the four ids to the "Warp Tech" node list makes them render and click. Their requires_flag values (z12..z15_unlocked) mean _is_node_hidden() keeps them invisible until the sector unlocks and _update_tab_visibility() already handles the tab, so nothing leaks early.

But the stated RATIONALE is wrong, and would mislead whoever applies it. _on_graph_draw() (research_page.gd:398-410) draws prereq lines from `parent`, never from `req_tech`, and all four techs have `parent: null` — so calculate_layout() will place them as separate floating roots with NO connecting line, exactly like cryo_armaments and corrosion_armaments already are. "append them there so calculate_layout() draws the prereq line" will not happen. If the visual chain matters, `parent` has to be set on each of the four as well.

The second half of the fix — wire the already-red research_graph_audit into a release gate — is sound and is the part that actually stops the fifth recurrence. A cheaper equivalent: assert tech_tree.keys() is a subset of the union of the graphs node lists.

**Repro:** `"$TEMP/godot_check/Godot_v4.5.1-stable_win64_console.exe" --headless --path . res://scenes/research_graph_audit.tscn`

<details><summary>Verifier's own measurement</summary>

```
My own probe, independently written:

[VER] sim_mode = true   (must be true)
[VER] ===== A. tab membership (real research_page.gd `graphs`) =====
[VER] tabs = ["Gathering", "Industry", "Automation", "Ships", "Combat", "Warp Tech", "Sectors"]
[VER] Warp Tech nodes = ["cryo_armaments", "corrosion_armaments"]
[VER] distinct ids listed across all tabs: 105 ; tech_tree size: 109
[VER] tech_tree ids in NO tab list: 4 -> ["caustic_armaments", "dissolution_armaments", "rift_armaments", "verdigris_armaments"]

[VER] ===== B. live render with every world flag set =====
[VER] node widgets actually instantiated: 105
[VER]   widget for rift_armaments           = null   (get_node_widget)
[VER]   widget for verdigris_armaments      = null   (get_node_widget)
[VER]   widget for dissolution_armaments    = null   (get_node_widget)
[VER]   widget for caustic_armaments        = null   (get_node_widget)
[VER]   CONTROL cryo_armaments           = FOUND
[VER]   CONTROL corrosion_armaments      = FOUND
[VER]   CONTROL warp_drive               = FOUND

[VER] ===== C. the 16 modules: craft + equip gates =====
[VER]   z12_armor                req=rift_armaments         unlocked=false can_equip=false
[VER]   z15_corrosion_blaster    req=caustic_armaments      unlocked=false can_equip=false
[VER] modules blocked by an un-unlocked research gate: 16 / 16
[VER] craft_module('z12_cryo_lance')  tech-absent=false  tech-present=true
[VER] rm.can_unlock('rift_armaments') with FULL prereq chain + flags + funds = true
[VER] rm.unlock_tech('rift_armaments') = true  -> is_tech_unlocked=true
[VER] craft_module('z12_armor') after a LEGITIMATE unlock_tech = true

[VER] ===== E. non-UI grant routes =====
[VER] missions targeting/rewarding the 4 techs: []
[VER] warp tree nodes mentioning 'armaments': []

The positive controls are the point: 105 of 109 widgets DO build, and the two Warp Tech siblings are FOUND, so the four nulls are not a broken instrument. Section C proves the techs themselves are healthy — can_unlock() returns true and the real unlock_tech() succeeds the moment the prereq chain is satisfied — so the defect is exactly and only the missing UI entry. Nothing in CLAUDE.md, docs/HANDOFF.md or docs/RULINGS_2026-08-08.md rules this intended; grep over docs/ for all four tech ids returns zero hits, and research_manager.gd:1069-1072 documents the opposite intent ("you earn zone N's weapon by clearing N-1 and warping, so the weapon that beats a boss is never behind that same boss").
```
</details>

### [45] The four NG+ armament techs render in no research tab, so all 16 Z12-Z15 modules are permanently uncraftable

**Verdict:** CONFIRMED · raised as *critical*, corrected to **critical** · lens `res_mission_join`

**What is actually true.** Identical to idx 27: the four NG+ armament techs are absent from every tab list in research_page.gd `graphs`, so 105 of 109 tech_tree entries render and these four never do. They gate all 16 Z12-Z15 modules, which measure can_craft=false / can_equip=false in every state a player can reach. The techs themselves are sound — can_unlock() and unlock_tech() both succeed once the prereq chain and sector flag are satisfied — which localises the defect entirely to the missing UI registration.

**What the original finding got wrong.** The word "permanently uncraftable" is right; "can never be obtained" (idx 27's phrasing, shared here) is not, for the same two reasons I logged against idx 27 — 8 of the 16 have real boss loot entries (measured: 8/16 with sources, including a 1.0 rare_loot on the Rift Warden), and options_page.gd:585 ships an unconditional "Unlock All Research" button. Both are dead ends in practice (can_equip_module re-gates dropped copies; the debug button is not progression), so the verdict stands.

One bookkeeping error: this finding calls it "the fifth recurrence (v137 firmware_hacking, v145 refractory_metallurgy + industrial_chemistry, v145 the three fabrication techs)" while idx 27 calls it the fourth. research_page.gd documents three prior FIX EVENTS covering five techs; this is the fourth event. Cosmetic.

The finding is also a straight duplicate of idx 27 — same file, same line, same four ids, same fix. It should be merged, not counted twice in any violation tally.

**Is the proposed fix sound?** Yes for reachability, with the same caveat as idx 27: this finding correctly says the four "chain off corrosion_armaments via req_tech", which is true, but req_tech is not what draws the graph edge — _on_graph_draw() reads `parent`, and all four have parent: null. They will render as unconnected floating roots in the Warp Tech tab. Functional, but the tree will not show the chain unless `parent` is also set.

The suggested permanent guard — assert tech_tree.keys() is a subset of the union of the graphs node lists — is the right shape and is cheap. The companion suggestion "have boss_gearcheck refuse to inject a tech that no tab renders" is aimed at the wrong line; see my verdict on idx 28, where the explicit injection turns out to be redundant with the harness's blanket tier<=N unlock.

**Repro:** `$TEMP/godot_check/Godot_v4.5.1-stable_win64_console.exe --headless --path . res://scenes/audit_tmp/res_mission_join.tscn | grep 'A2:'`

<details><summary>Verifier's own measurement</summary>

```
Same probe, same run — this finding is a duplicate of idx 27 from a different lens, and it reproduces identically. The two claims it makes that idx 27 does not, both verified:

Claim "the Warp Tech tab lists only cryo_armaments and corrosion_armaments":
[VER] Warp Tech nodes = ["cryo_armaments", "corrosion_armaments"]

Claim "105 rendered across 7 tabs, tech_tree holds 109":
[VER] tabs = ["Gathering", "Industry", "Automation", "Ships", "Combat", "Warp Tech", "Sectors"]
[VER] distinct ids listed across all tabs: 105 ; tech_tree size: 109
[VER] node widgets actually instantiated: 105

Claim "craft_module = false, and after force-appending the tech, = true, proving the gate is the ONLY blocker" — reproduced with 1e15 credits and 1e9 of every input element so cost could not be a confound:
[VER] craft_module('z12_cryo_lance')  tech-absent=false  tech-present=true

And, going further than the auditor did, via the LEGITIMATE unlock path rather than a force-append:
[VER] rm.can_unlock('rift_armaments') with FULL prereq chain + flags + funds = true
[VER] rm.unlock_tech('rift_armaments') = true  -> is_tech_unlocked=true
[VER] craft_module('z12_armor') after a LEGITIMATE unlock_tech = true

That last block is the strongest version of the finding and neither auditor ran it: the tech is not broken, not mis-gated, and not cost-walled — research_manager will happily sell it. There is simply no button.
```
</details>

---

## MAJOR

### [3] m029a8 hard-stops the main chain: Electronics Assembler needs a Zone-3-only material eight beats before Zone 3 opens

**Verdict:** CONFIRMED · raised as *critical*, corrected to **major** · lens `chain_prereq`

**What is actually true.** The main chain orders m029a8 (build electronics_assembler, cost includes SalvageData 12) at chain index 55, while the only faucet for SalvageData in the entire game — z3_derelict_frigate in mars_debris, gated by research_req zone_3_access — is not opened by the chain until m030e at index 63, and the Z2_Core that research needs is not directed until m030d at index 62. A chain-obedient player therefore reaches a build objective with zero reachable sources, and the beat's text actively misdirects ("Salvage Data drops from wrecked hostiles, so run a sector if you are short" — neither enterable sector drops it). This stalls the guided path and its rewards; it is not a softlock, because the player can self-research zone_3_access off-script (parent already owned, Z2 boss already reachable) and the chain resumes with no state lost.

**What the original finding got wrong.** Only the framing, not the facts. (1) "Hard-stops" / "the run ends here" is false. A stalled mission gates NOTHING: grepping every reader of mission_manager outside the manager itself yields only game_state save/load/reset, main.gd::has_progress, combat_manager::sync_progress and UI display — no research, zone, recipe or building consults mission state. zone_3_access has req_tech "" and parent zone_2_access, which the chain already granted 14 beats earlier at m027 (idx 41), so the player can buy Mars Debris Clearance off-script the moment they own a Z2_Core — and the Z2 boss that drops it is in asteroid_belt, already enterable. I executed that route in-probe: can_unlock -> true, unlock_tech -> true, mars_debris enterable, SalvageData reachable. (2) "The only escape is to guess" overstates: the in-game Atlas already indexes SalvageData as "Derelict Frigate / Mars Debris Field / zone_ord 3", so the game does tell the player where it lives — it just doesn't tell them the sector is locked. (3) The downstream damage the impact statement implies does not occur: mission_manager::sync_progress back-fills type=="research" beats from already-unlocked techs, so an off-script zone_3_access auto-satisfies m030e when it activates. (4) Not the auditor's error but worth recording: the beat's own text also omits Circuit 40 and 25,000 Liras from the cost it recites.

**Is the proposed fix sound?** Half of it. The preferred fix — "reorder so m030d (Silicate Monolith) and m030e run before m029a8, the block moves as a unit" — is NOT sound. That block does not move as a unit: m030d is deliberately preceded by m030c (Destroyer hull) -> m030c2 (3x z2_battery) -> m030c3 (3x z2_energy), and m030c depends on m030 (shipwright_2) which depends on m029b (6x AdvCircuit) which depends on m029a9 (100 Circuits) — the very output the assembler exists to bootstrap. Moving m030d/m030e ahead of m029a8 would put a Rare-gated Zone-2 boss in front of the refits written to make it winnable, i.e. relocate the wall rather than remove it. The alternative in the same fix field is sound: swap SalvageData 12 for a Zone-1/2 token. I verified DamagedCircuitry is the right substitute — z1 boss rare_loot [0.90, 2-4], z2_silicate_golem rare_loot [0.40, 1-3], z2_boss_monolith rare_loot [0.90, 3-6] — and it is thematically an electronics token. Any such swap must also rewrite the mission description, which names Salvage Data explicitly. Note SalvageData still has two other sinks (firmware_hacking, xeno_engineering) and one recipe use, so removing this one does not orphan the material.

**Repro:** `"$TEMP/godot_check/Godot_v4.5.1-stable_win64_console.exe" --headless --path . res://scenes/audit_tmp/chain_prereq.tscn 2>&1 | grep m029a8`

<details><summary>Verifier's own measurement</summary>

```
My own probe, fresh boot, sim_mode = true:

[SK] ===== Q1 DEEP SCAN: every occurrence of SalvageData in live data =====
[SK] HIT combat.enemy_db/z3_derelict_frigate/loot[5][0]
[SK] HIT process.recipes/decrypt_nav_data/input/<KEY>SalvageData
[SK] HIT infra.building_db/electronics_assembler/cost/<KEY>SalvageData
[SK] HIT research.tech_tree/firmware_hacking/cost_items/<KEY>SalvageData
[SK] HIT research.tech_tree/xeno_engineering/cost_items/<KEY>SalvageData
[SK] PRODUCERS of SalvageData = ["enemy:z3_derelict_frigate.loot"]
[SK] counts: enemies=65 zones=15 hazards=1 recipes=121 gather=21 buildings=97 techs=109 modules=194
[SK] producer z3_derelict_frigate lives in zone 'mars_debris' (diff 3) req_tech=zone_3_access unlock_flag=<none>
[SK] ATLAS sources = [{ "type": "combat", "name": "Derelict Frigate", "rate": "Öldürme başına 2-4", "zone_name": "Mars Debris Field", "zone_ord": 3 }]

[SK] idx=54   m029a7   type=research  target=industrial_automation  qty=1 next=m029a8
[SK] idx=55   m029a8   type=build     target=electronics_assembler  qty=1 next=m029a9
[SK] idx=62   m030d    type=defeat    target=z2_boss_monolith       qty=1 next=m030e
[SK] idx=63   m030e    type=research  target=zone_3_access          qty=1 next=m017c

[SK] techs the chain has directed by m029a8: ["shipwright_1", "zone_2_access", "adv_materials", "metallurgy_advanced", "automation", "industrial_automation"]
[SK] zones enterable at m029a8 = ["lunar_orbit(diff ?)", "asteroid_belt(diff ?)"]
[SK] SalvageData reachable at m029a8 ? []

But the escape route also reproduces:
[SK] zone_3_access FULL = { "name": "Mars Debris Clearance", "tier": 3, "category": "zone", "cost": 75000, "cost_items": { "Z2_Core": 1, "Steel": 80, "Circuit": 15 }, "type": "technology", "parent": "zone_2_access", ... }
[SK] Z2_Core drops from z2_boss_monolith in zone asteroid_belt (enterable now? true)
[SK] can_unlock('zone_3_access') = true
[SK] unlock_tech('zone_3_access') = true
[SK] zones AFTER off-script zone_3_access = ["lunar_orbit", "asteroid_belt", "mars_debris"]
[SK] SalvageData reachable AFTER off-script research = ["mars_debris/z3_derelict_frigate"]
```
</details>

### [4] The opening Spodumene -> Lithium pair is one skill level short on both sides

**Verdict:** CONFIRMED · raised as *major*, corrected to **major** · lens `chain_prereq`

**What is actually true.** Two consecutive opening beats direct the player at actions that are level-locked on arrival, and the coach arrow pulses the disabled button. Measured from a fresh game with the shipped starter kit and inventory-latched mission progress: at m012 the player is Mining 4 (474 xp) and extract_salts requires 6 (762) — short 288 xp, about 20 more Pump Water actions. At m013 the player is Engineering 1 (120 xp) and refine_lithium requires 3 (274) — short 154 xp, about 31 more Mineral Washings. Both are deeper than the audit reported. Corollary worth flagging separately: resources.gd:34 asserts "the player clears Lv.2 while doing the Si/Fe refine at m005"; the measured value is 120 xp against a 133 threshold, so that comment is false by 13 xp.

**What the original finding got wrong.** The model behind every number. chain_prereq.gd:420 declares "mission GATHER targets must be produced fresh (progress counts element_added)". sync_progress() does the opposite: line 945 latches current_qty = max(current_qty, min(inv_qty, target_qty)), and line 698 calls sync_progress() the instant a mission activates. So the starter kit (Dirt 120, Water 100, Si 30, Fe 25) counts toward m001/m004/m005. m004 and m005 latch for certain (they activate via the completion path); only m001 is ambiguous, and even taking m001 unlatched the total is 300+270 = 570, which is still level 4 (L5 = 588). Consequences: Mining at m012 is 474 (or at most 570), i.e. level FOUR and short 288 xp — not "exactly 675 xp = level 5, short 87". Engineering at m013 is 120 xp, i.e. level ONE and short 154 xp — not "exactly 170 = level 2, short 104". Both walls are roughly twice as deep as reported. Two smaller overstatements: "exactly" is not available from an 8-20 uniform roll (an unlucky player reaches Mining 6 and never meets the m012 wall), and "the player has no way to know" is false — the widget literally reads LEVEL 6 REQUIRED. What is genuinely bad is that the coach arrow pulses that disabled button.

**Is the proposed fix sound?** No — the proposed fix does not clear either wall, because it was computed from the same wrong arithmetic. extract_salts 6 -> 5 still locks a level-4 player (588 needed, 474 held). refine_lithium 3 -> 2 still locks a level-1 player (133 needed, 120 held). The stated alternative fails too: with the latch, 420 Dirt / 420 Water = 22 + 23 actions = 609 xp = level 5, still short of 6; and m005 at Si 160 = 44 centrifuge runs = 220 xp = level 2, still short of 3. Numbers that actually work, measured: extract_salts level_req -> 4, or raise m004 to about 560 Water (33 actions, 204+495 = 699... still short, so the level_req route is the clean one); refine_lithium level_req -> 1, or raise m005 to Si 200 (57 runs = 285 xp = level 3). Whatever is chosen, re-measure with the inventory latch in the loop — hand arithmetic against the RS curve is exactly what went wrong here, and the committed guard scripts/sim/onboarding_order_check.gd makes the same starter-kit omission at its step 3 (it only survives because that one check has 71 xp of headroom).

**Repro:** `"$TEMP/godot_check/Godot_v4.5.1-stable_win64_console.exe" --headless --path . res://scenes/audit_tmp/chain_prereq.tscn 2>&1 | grep -E "m012|m013 VERDICT|Mining xp"`

<details><summary>Verifier's own measurement</summary>

```
My own run (verify_prereq_levels):

[V] fresh skills: mining L1 (0 xp), eng L1 (0 xp)
[V] thresholds L2..L8: 133 274 426 588 762 950 1151
[V] starter inventory: { "Dirt": 120.0, "Water": 100.0, "Fe": 25.0, "Si": 30.0 }
[V] --- m001 (gather) mining L1/0xp  eng L1/0xp
[V]     Dirt: 17 x gather_dirt (gather, +204 xp) -> mining L2/204
[V] --- m004 (gather) mining L2/204xp  eng L1/0xp
[V]     Water: 18 x collect_water (gather, +270 xp) -> mining L4/474
[V] --- m005 (gather_multi) mining L4/474xp  eng L1/0xp
[V]     Si: 24 x centrifuge_dirt (recipe, +120 xp) -> eng L1/120
[V]     Fe: inventory already 145/80 — zero work
[V] --- m012 (gather) mining L4/474xp  eng L1/120xp
[V] *** WALL  m012: to obtain Spodumene the player must run extract_salts (GATHER level_req 6) but is level 4 — short 288 xp
[V] --- m013 (gather) mining L8/1274xp  eng L1/120xp
[V] *** WALL  m013: to obtain Li the player must run refine_lithium (RECIPE level_req 3) but is level 1 — short 154 xp

Loot-roll sensitivity (the auditor said "exactly"):
[V] BRACKET lucky(max roll)    dirt 12 acts + water 13 acts =  339 mining xp -> L3 (extract_salts needs 6)
[V] BRACKET average            dirt 17 acts + water 18 acts =  474 mining xp -> L4 (extract_salts needs 6)
[V] BRACKET unlucky(min roll)  dirt 29 acts + water 32 acts =  828 mining xp -> L6 (extract_salts needs 6)
[V] BRACKET auditor-model(fresh 350 each, avg roll) dirt 25 + water 25 =  675 mining xp -> L5

Live new game, sim_mode-gated:
[V] --- LIVE NEW GAME (sim_mode=true, saves+deletes are gated) ---
[V] LATCH after hard_reset: Dirt=120  m001 current_qty=0 / 350  active=true
[V] LATCH after one sync_progress(): m001 current_qty=120 / 350
[V] LATCH inventory: Water=100 Si=30 Fe=25  (m004 target 350, m005 Si 100 / Fe 80)

Enforcement is real (gathering_manager.start_action): `if lvl < req: print("Level too low."); return`, and gathering_action_widget.gd:288 renders `btn.text = tr("LEVEL %d REQUIRED") % req` with `btn.disabled = true`. main.gd:1344 still points the coach arrow at that disabled button (`pages["gathering"].focus_action("extract_salts")`).
```
</details>

### [7] Yesterday's hull slot redistribution left four refit missions asking for the wrong number of modules

**Verdict:** PARTLY_TRUE · raised as *major*, corrected to **major** · lens `chain_prereq`

**What is actually true.** Three of the four refit beats state something the shipped slot table contradicts, and all three are on the two slot types commit ca26034 changed: m030c3 and m030f1 each say "equip one per weapon slot" while asking for 3 on a destroyer that has 4, and m030fa says "equip one per armor slot" while asking for 2 on a destroyer that has 1 (the second Composite Plate — 7260 Liras, 364 Steel, 7 Ti, and one each of WreckforgedAlloy / MartianRelics / ReinforcedPlating — cannot be equipped). The clean control is in the same block: m030c2 asks 3 batteries for 3 battery slots and m030fb asks 2 shields for 2 shield slots, and battery/shield are exactly the slot types ca26034 left alone. m017a is not part of this — its text makes no per-slot claim and says nothing untrue.

**What the original finding got wrong.** One of the four is a probe artifact. chain_prereq.gd:219 flags MISMATCH on `int(qty) != have` for EVERY craft beat, regardless of what the text says — so it fires on m017a, whose description contains no "one per slot" claim at all. m017a says "craft 2 'Pulse Laser Mk.I'" and its partner m017b says "equip BOTH Pulse Lasers" — internally consistent, nothing false. (There is a real but different nit there: after ca26034 the frigate has a third weapon slot the directed loadout leaves EMPTY at the Silicate Golem fight — not "on the previous tier" as claimed, since loadout 2 starts empty.) Second error: "occupies one of 28 inventory slots forever" is false — crafted modules never touch the 28-slot element inventory. Third, smaller: the same commit also cut the frigate from 2 armor slots to 1, which the finding does not mention.

**Is the proposed fix sound?** Yes for the three real ones: m030c3 3 -> 4, m030f1 3 -> 4, m030fa 2 -> 1 all match the shipped table, and none has a downstream dependency (no loadout_check beat follows them, and the missions only gate on craft count). m017a 2 -> 3 is a defensible balance choice — it fills the frigate's third weapon slot for the energy-weak Golem — but it is not a text correction and should be argued on its own merits, not folded into a desync fix. The proposed committed guard needs one change: assert on beats whose DESCRIPTION contains "per <slot> slot", not on `target_qty != slot_count`. Keyed the way the probe was, it will flag m017a forever and every future beat that deliberately asks for a partial fit.

**Repro:** `"$TEMP/godot_check/Godot_v4.5.1-stable_win64_console.exe" --headless --path . res://scenes/audit_tmp/chain_prereq.tscn 2>&1 | grep MISMATCH`

<details><summary>Verifier's own measurement</summary>

```
Live slot arrays and mission texts, read off the running managers:

[V] HULL|frigate_hull|["weapon", "weapon", "weapon", "shield", "shield", "armor", "engine", "battery", "battery", "sensor"]
[V] HULL|destroyer_hull|["weapon", "weapon", "weapon", "weapon", "shield", "shield", "armor", "engine", "battery", "battery", "battery", "sensor"]

[V] DESC|m017a|craft|z1_energy|2|Energy Doctrine|... In the Shipyard, craft 2 'Pulse Laser Mk.I'
[V] DESC|m030c2|craft|z2_battery|3|Power Refit|... Fabricate 3 'Improved Battery' (Z2) and equip one per battery slot ...
[V] DESC|m030c3|craft|z2_energy|3|Heavier Ordnance|... Fabricate 3 'Plasma Cutter' (Z2 ENERGY) and equip one per weapon slot before the fight.
[V] DESC|m030fa|craft|z3_armor|2|Zone-3 Plating|... Fabricate 2 'Composite Plate' (Z3 armor) and equip one per armor slot.
[V] DESC|m030fb|craft|z3_shield|2|Zone-3 Shielding|... Fabricate 2 'Hardened Shield' (Z3) and equip one per shield slot before the Warmaster.
[V] DESC|m030f1|craft|z3_kinetic|3|Zone-3 Ordnance|... Fabricate 3 'Autocannon' (Z3 KINETIC) and equip one per weapon slot — swap before the fight.

Hull ownership at each beat, from the chain walk (m026b constructs frigate at index 40, m030c constructs destroyer at index 59): m017a=42 frigate, m030c3=61 destroyer, m030fa=68 destroyer, m030f1=70 destroyer.

Commit verified:
$ git show --stat --format="" ca26034 | tail
 docs/RULINGS_2026-08-08.md | 66 +++
 scenes/hull_tier_rule_check.tscn | 6 ++
 scripts/managers/shipyard_manager.gd | 38 ++--
 scripts/sim/energy_margin_check.gd.uid | 1 +
 scripts/sim/hull_tier_rule_check.gd | 147 +++++
 scripts/sim/onboarding_order_check.gd.uid | 1 +
(no mission_manager.gd — the auditor's causal claim holds)

[V] MODCOST|z3_armor|{ "credits": 7260, "WreckforgedAlloy": 1, "MartianRelics": 1, "Steel": 364, "Ti": 7, "ReinforcedPlating": 1 }

Storage: shipyard_manager.craft_module ends at `module_inventory[module_id] = module_inventory.get(module_id, 0) + 1` — a separate dict from resources.elements, and resources.gd:75 says "v147: armory stock costs no slot at all, so it can never be capped out."
```
</details>

### [15] 29% of the main mission chain ships in English inside the Turkish build

**Verdict:** CONFIRMED · raised as *major*, corrected to **major** · lens `chain_text`

**What is actually true.** 24 mission descriptions and 3 mission names have no row in localization/strings.csv (NO_ROW=27; zero empty-tr and zero identical-to-English rows), so 25 of the 85 beats on the m001..m033c chain — 29.4% by beat, 40.6% of the chain's description text by character — render as raw English for a Turkish player via the ENGLISH-AS-KEY fallback in scripts/core/localization.gd, surfaced by tr() at scripts/ui/mission_widget.gd:23 and :25. The gap is concentrated in the instructional beats (m025->m026b steel/Shipwright/Frigate, m017a-m017d damage doctrine, m029a2->m030c industrial spine); the first hit is at chain beat 3 (m002), not beat 2.

**What the original finding got wrong.** Two small overstatements, neither load-bearing. (1) "A Turkish player hits English at chain step 2 (m002)" — the real chain order is m001 -> m004 -> m002, so m002 is beat 3, not 2 (my walk: first 6 ids = ["m001","m004","m002","m005","m012","m013"]). (2) "25 beats render English" bundles one name-only case: m013 has an untranslated NAME but a translated description, so 24 beats show an English body and one shows an English title over Turkish text. In the other direction the auditor UNDERSTATED it: by character volume 4,381 of 10,790 chain description characters (40.6%) are untranslated, because the missing rows are the long instructional beats and the translated ones are short flavour beats.

**Is the proposed fix sound?** Yes. Appending 27 en/tr rows is the whole fix — the loader keys on the exact English string, so no code change is needed and there is no migration risk (locale preference lives in user://locale.cfg, outside the save). The proposed committed guard is also sound and is the more valuable half: iterate mission_manager.missions under locale tr and fail if TranslationServer.translate(s) == s. One caveat worth flagging to whoever writes it — that assertion must run AFTER Localization._ready has added the translation and must restore the locale afterwards, and it should skip empty strings, otherwise it will produce false failures. It would break nothing else; a guard scene launched as a non-main scene auto-enables sim_mode, so it cannot touch the save.

**Repro:** `"$TEMP/godot_check/Godot_v4.5.1-stable_win64_console.exe" --headless --path . res://scenes/audit_tmp/chain_text.tscn 2>&1 | grep -E "NO-TR-|MAIN CHAIN"`

<details><summary>Verifier's own measurement</summary>

```
My own probe, independent CSV parse + live TranslationServer:

[V] CSV header = ["en", "tr"]
[V] CSV data rows = 2755 ; duplicate keys = 0 ; unique keys = 2755
[V] total missions in mission_manager.missions = 111
[V] locale set to 'tr'
[V] CONTROL translated : tr('CONTINUE') -> 'DEVAM ET'  (differs=true)
[V] CONTROL missing    : tr('ZZ_NOT_A_REAL_KEY_QQ') -> 'ZZ_NOT_A_REAL_KEY_QQ'  (differs=false)
[V] classify buckets (names+descs, 2 per mission) = { "NO_ROW": 27, "EMPTY_TR": 0, "IDENTICAL": 0, "TRANSLATED": 195, "EMPTY_SRC": 0 }
[V] mission NAMES not translated: 3
[V]   NAME m013|NO_ROW|Battery Electrolyte
[V]   NAME m019e|NO_ROW|Field Manual
[V]   NAME m028|NO_ROW|Belt Metallurgy
[V] mission DESCS not translated: 24
[V] LIVE tr() untranslated missions (name and/or desc) = 25 / 111
[V] chain walk from m001 length = 85 ; last = m033c
[V] MAIN CHAIN: 85 beats, 25 render English under tr = 29.4%
[V] chain positions untranslated: ["3:m002", "6:m013", "21:m017", "26:m011", "27:m013b", "28:m013c", "36:m019e", "37:m025", "38:m025a", "39:m025b", "40:m026", "41:m026b", "43:m017a", "45:m017b", "47:m028", "50:m029a2", "51:m029a3", "53:m029a6", "54:m029a6t", "55:m029a7", "56:m029a8", "58:m029b", "60:m030c", "65:m017c", "67:m017d"]
[V] chain description chars: 10790 total, 4381 untranslated (40.6%)

The three distinctions the task asked me to separate all resolve cleanly: NO_ROW=27, EMPTY_TR=0, IDENTICAL=0 — every failure is a genuinely absent CSV row, not a row that happens to equal English. The key IS looked up: scripts/ui/mission_widget.gd line 25 is literally `desc_lbl.text = tr(data["description"])` and line 23 `name_lbl.text = tr(data["name"])`. The lookup path is scripts/core/localization.gd, which loads the CSV at runtime and calls TranslationServer.add_translation — project.godot has no [internationalization] section, so the imported strings.tr.translation is NOT in the live path and my CSV parse and the live tr() agree exactly (25 = 25). Turkish is reachable by a real player: scripts/ui/main_menu.gd:433 `_on_language_selected` -> `Localization.set_locale(code)`.
Not intended design: docs/HANDOFF.md treats exactly this shape as a defect it has fixed before — "the whole 8-section HOW TO PLAY briefing had zero rows in strings.csv and shipped English under Turkish".
```
</details>

### [21] Research page centres a [CORE GOAL]'s tech instead of the chain beat's

**Verdict:** CONFIRMED · raised as *major*, corrected to **major** · lens `chain_guidance`

**What is actually true.** research_page.on_page_enter (research_page.gd:225-240) sorts active research beats by get_chain_index() but does not exclude tag == "[CORE GOAL]", and Kahn seeds every indeg-0 root first, so the two research-type goals land at index 13-14, ahead of all 16 non-goal research beats. On a clean new game, goal_hack_1 opens when m027 completes (zone_2_access) and stays open until the player buys firmware_hacking - an optional side arc - so for the whole Zone 2 -> Zone 7 stretch every entry to the Research Lab switches to the Combat tab and centres Firmware Hacking. For the 10 chain research beats in that window (m029a1, m029a2, m029a5, m029a7, m030, m030e, m030g, m031, m032b, m033b) the page lands on a different tab than the one the gold arrow is pulsing; for the remaining beats it simply hijacks the page toward a side goal. Post-warp, goal_cryo_1 (idx 13, Ships tab) does the same and outranks goal_hack_1.

**What the original finding got wrong.** The headline scenario is not reachable as described. The auditor's F2/F6 fixture opens goal_hack_1 + m026 with m026c absent, and reports 'the gold arrow is pulsing a node on the Ships tab'. goal_hack_1 reveals on zone_2_access, bought by m027, which sits AFTER m026 in the chain (idx 65 vs 67), so in forward play m026 is long gone by then; and in the reordered two-front save the arrow is m026c (drop_rarity, Combat PAGE, not a research node on the Ships tab) - it is only m026 in the auditor's artificial state. The claim 'the pre-v175 definition-order rule gave the right answer here' is also only true for goal_hack_1: goal_cryo_1 (idx 13) targets cryo_armaments on the Ships tab and would break the old rule too if goals were ever defined before m-beats. None of this saves the finding - I found a strictly more reachable version of it.

**Is the proposed fix sound?** Half of it. Adding the `tag == "[CORE GOAL]"` skip to the candidate loop restores the v139h behaviour and is correct - and the `claimed` skip is harmless (purge_claimed_actives already keeps claimed ids out of active_missions). But the auditor's 'better still' variant - defer to get_chain_frontier_id() and return - is worse than the current bug: the frontier is non-goal by construction and is usually NOT a research beat at all (my walk shows the arrow on gather/craft/defeat beats most steps), so the page would stop switching tabs entirely, and my case2 control shows the goal-only state (Combat tab, firmware_hacking) is the correct and useful answer when no chain research beat is open. The fix that actually works is a two-pass preference: take the lowest-index non-goal research beat, and only fall back to goals when that set is empty.

**Repro:** `"$TEMP/godot_check/Godot_v4.5.1-stable_win64_console.exe" --headless --path . res://scenes/audit_tmp/chain_guidance.tscn   # read sections F2 and F6`

<details><summary>Verifier's own measurement</summary>

```
My own probe, independent of the auditor's:

[VG] ===== A1  where does goal_hack_1 land in the Kahn order? =====
[VG] goal_hack_1 chain_index=14  type=research  target=firmware_hacking  tab=combat  tag=[CORE GOAL]
[VG] non-goal research beats with a HIGHER (= later) chain index: 16
[VG]   m002, m003, m018, m025, m026, m027, m029a1, m029a2, m029a5, m029a7, m030, m030e, m030g, m031, m032b, m033b
[VG]   research CORE GOAL goal_cryo_1    idx= 13 target=cryo_armaments     tab=ships
[VG]   research CORE GOAL goal_hack_1    idx= 14 target=firmware_hacking   tab=combat

Reachability on a CLEAN NEW GAME (no reordered save, no orphan rescue) - my forward walk:
[VG] ===== A2  FORWARD playthrough ... =====
[VG]   (m027 finished -> zone_2_access researched -> goal_hack_1 revealed)
[VG]   DISAGREE step 49  arrow=m029a1  (processing tab, adv_materials)  page=goal_hack_1 (combat tab, firmware_hacking)
[VG]   DISAGREE step 50  arrow=m029a2  (processing tab, metallurgy_advanced)  page=goal_hack_1 (combat tab, firmware_hacking)
[VG] walked 85 beats; steps where research page and gold arrow point at DIFFERENT missions: 43

LIVE UI, real main.tscn, real rp.on_page_enter(), with controls:
[VG]   case1 arrow=m029a1 -> tech adv_materials (processing tab); tab before = Gathering
[VG]   case1 tab AFTER on_page_enter = Combat
[VG]   case2 (goal only, control) tab AFTER = Combat
[VG]   case3 (chain beat only, control) tab AFTER = Industry
[VG]   case4 (m026 shipwright_1=ships tab + goal) tab AFTER = Combat

case3 isolates the cause: remove the goal and the same beat routes to Industry correctly. Not intended design - the function's own v139h comment (research_page.gd:208-212) states the opposite intent, and docs/HANDOFF.md line 496 lists this function as one of the three places the v175 fix was meant to re-key.
```
</details>

### [22] Header objective chip and the gold arrow name different missions

**Verdict:** CONFIRMED · raised as *major*, corrected to **major** · lens `chain_guidance`

**What is actually true.** get_active_objective (mission_manager.gd:1222-1240) was left out of the v175 re-key: it still returns the FIRST rank-1 entry in active_missions APPEND order (`if rank < best_rank` - strict, so first wins ties). get_save_data_manager iterates `missions` in definition order and JSON preserves that order, so after any save/load active_missions is in definition order. On the reported 36-claimed-beat two-front save this makes the header chip read "Master Constructor" (m026, idx 65) while get_chain_frontier_id and the gold arrow point at "Elite Salvage" (m026c, idx 47), on every session after the first, until one of the two fronts is claimed. Fresh post-reorder playthroughs never hit it (0/85 steps measured).

**What the original finding got wrong.** Two overstatements. (1) 'permanently contradicting each other' - it lasts until either front is claimed (m026 = research shipwright_1, m026c = get one rare drop), a bounded near-term window, not permanent. (2) The implication that this is a general guidance defect: my forward walk over all 85 chain beats on a fresh game finds chip != arrow in 0 steps, and a co-open [CORE GOAL] does not trigger it either (goals rank 2 vs 1 in get_active_objective). It requires two m-beats open at once, which today only happens on a save that crossed the Zone 1 reorder - i.e. exactly the owner's save and no other. The auditor's own probe also never JSON-serialised, so its 'after any normal save/load' was an assumption; I verified it and it holds.

**Is the proposed fix sound?** Yes, with one guard. Keeping the rank-0 completed-unclaimed CLAIM branch first, then returning missions[get_chain_frontier_id()], then falling back to a goal is correct and matches the documented 'one authority' intent - get_chain_frontier_id already excludes claimed and [CORE GOAL] beats, so the goal fallback is still reachable for a player whose only open mission is a goal. The guard: get_chain_frontier_id() returns "" in that goal-only case, so the implementation must test for empty rather than indexing missions[""]. The auditor's weaker alternative (break rank ties by get_chain_index()) is also sound and is a one-line change.

**Repro:** `"$TEMP/godot_check/Godot_v4.5.1-stable_win64_console.exe" --headless --path . res://scenes/audit_tmp/chain_guidance.tscn   # read section F3`

<details><summary>Verifier's own measurement</summary>

```
My probe, using a REAL JSON round trip (the auditor only handed the in-memory Dictionary back):

[VG] ===== B1  chip vs arrow across a REAL json save/load round-trip =====
[VG] in-memory after rescue : active=["m026c", "m026"]
[VG]   chip=m026c  arrow=m026c  agree=true
[VG] after json save+load   : active=["m026", "m026c"]
[VG]   header CHIP = m026   "Master Constructor"
[VG]   gold  ARROW = m026c  "Elite Salvage"
[VG]   AGREE=false
[VG]   chain idx: m026=65  m026c=47   (arrow takes the smaller)

The real widget, not the function - live main.tscn, global_header.update_objective():
[VG]   case5 chip widget text = "▸ Master Constructor" | arrow = m026c ("Elite Salvage")

The owner's screenshot check the task asked for passes: pre-fix the arrow came from main.gd's elif cascade in source order (m026, Shipwright I) and the reloaded chip also read m026, so the two AGREED (both wrong) - nothing would have been visible. The divergence is new with e7bd4e5.

`git show e7bd4e5 -- scripts/managers/mission_manager.gd | grep get_active_objective` returns NOTHING - the chip's picker was not touched, while docs/HANDOFF.md line ~494 tabulates only three places as the authorities being unified. get_active_objective is a fourth.

Bounding it, from my forward walk:
[VG] walked 85 beats, max simultaneously-open missions=2, chip!=arrow steps=0
[VG]   m029a1 + goal_hack_1 -> chip=m029a1 arrow=m029a1 page=goal_hack_1
```
</details>

### [39] upgrades_db in get_recipe_speed_multiplier is declared and never read - all ten per-recipe processing speed techs do nothing

**Verdict:** CONFIRMED · raised as *critical*, corrected to **major** · lens `res_gating`

**What is actually true.** processing_manager.gd::get_recipe_speed_multiplier() builds the 6-recipe upgrades_db table (lines 1875-1893) and never iterates it - the gathering twin's `if action_id in upgrades_db:` apply loop (gathering_manager.gd:428-431) has no counterpart in the processing copy. All ten per-recipe action_speed research nodes (fast_centrifuges, maglev_bearings, quantum_separators, catalytic_electrodes, ion_exchange, resonance_splitters, pyrolysis_control, blast_furnace, basic_electronics, hydraulic_press - 19,000 Liras plus Res1/Res2/Res3/AdvCircuit/Cu/Si) produce a measured zero delta on both the multiplier and on 60 s of real ticks, and the recipe widget renders the same unchanged duration. Major, not critical.

**What the original finding got wrong.** Two overstatements, neither fatal. (1) Severity: rated critical, but nothing softlocks, no save/data is at risk, and no progression is blocked - the whole ladder costs 19,000 Liras (COST_MULTIPLIER is 1.0, so that figure is literal) at a stage where a single Industrial Centrifuge costs 500,000. This is a dead-purchase/false-advertising defect at scale, which is major, not critical. (2) The 'lands squarely in the m029-m030 Circuit/AdvCircuit desert' framing is unmeasured by me and by the auditor - craft_circuit's dead +25% is directionally relevant, but no funnel measurement was shown tying these techs to that wall. (3) Cosmetic: the card does not read '+25% centrifuge_dirt speed'; _format_effect calls _resolve_action_name, so the player sees the display name ('Mineral Washing'). The auditor quoted internal ids as card text.

**Is the proposed fix sound?** Yes - the four-line apply loop mirroring gathering_manager.gd:428-431 is the correct and minimal fix, and the auditor is right to demand a re-run of the economy probes rather than treating it as free. Concretely what it turns on: centrifuge_dirt and electrolysis each gain +1.50 additive on a base that measured 1.5263 at Engineering Lv25, i.e. duration 1.9656s -> ~0.65s and 1.3104s -> ~0.43s - a ~3x throughput jump on two early recipes, which is a real balance event, not a bugfix. Two cautions the fix text misses: (a) complete_process() sets action_progress = 0.0 and discards overflow, so any recipe pushed below the frame delta silently loses throughput - at ~0.43s that is still safe at 60fps but it is the floor docs/SANITY_CHECKLIST.md:73 already flags; (b) processing_manager's own calculate_offline must be re-checked for the same multiplier or online and offline rates will diverge. The proposed regression probe asserting a nonzero delta per pair is the right guard.

**Repro:** `"$TEMP/godot_check/Godot_v4.5.1-stable_win64_console.exe" --headless --path . res://scenes/audit_tmp/res_gating.tscn 2>&1 | grep "RG\]\[H\]"`

<details><summary>Verifier's own measurement</summary>

```
My own probe, independent of the auditor's, with two positive controls through the same call:

[VD] sim_mode=true
[VD] neutralized: mastery cleared, buildings cleared, techs cleared.
[VD][39] centrifuge_dirt    + fast_centrifuges        mult 1.5263 -> 1.5263  (card promises +25%)  dur 1.9656s -> 1.9656s  DEAD
[VD][39] centrifuge_dirt    + maglev_bearings         mult 1.5263 -> 1.5263  (card promises +50%)  dur 1.9656s -> 1.9656s  DEAD
[VD][39] centrifuge_dirt    + quantum_separators      mult 1.5263 -> 1.5263  (card promises +75%)  dur 1.9656s -> 1.9656s  DEAD
[VD][39] electrolysis       + catalytic_electrodes    mult 1.5263 -> 1.5263  (card promises +25%)  dur 1.3104s -> 1.3104s  DEAD
[VD][39] electrolysis       + ion_exchange            mult 1.5263 -> 1.5263  (card promises +50%)  dur 1.3104s -> 1.3104s  DEAD
[VD][39] electrolysis       + resonance_splitters     mult 1.5263 -> 1.5263  (card promises +75%)  dur 1.3104s -> 1.3104s  DEAD
[VD][39] charcoal_burning   + pyrolysis_control       mult 1.5263 -> 1.5263  (card promises +25%)  dur 2.6208s -> 2.6208s  DEAD
[VD][39] smelt_steel_basic  + blast_furnace           mult 1.5263 -> 1.5263  (card promises +25%)  dur 3.2760s -> 3.2760s  DEAD
[VD][39] craft_circuit      + basic_electronics       mult 1.5263 -> 1.5263  (card promises +25%)  dur 3.9312s -> 3.9312s  DEAD
[VD][39] press_graphite     + hydraulic_press         mult 1.5263 -> 1.5263  (card promises +25%)  dur 3.9312s -> 3.9312s  DEAD
[VD][39] CONTROL centrifuge_dirt + industrial_catalysis (processing_speed key): 1.5263 -> 1.8315  MOVES
[VD][39] CONTROL gather_dirt + diamond_drills (gathering twin has apply loop): 1.0000 -> 1.5000  MOVES
[VD][39] 60s of centrifuge_dirt ticks, techs=[] -> Fe +210
[VD][39] 60s of centrifuge_dirt ticks, techs=["fast_centrifuges"] -> Fe +210
[VD][39] 60s of centrifuge_dirt ticks, techs=["maglev_bearings"] -> Fe +210
[VD][39] 60s of centrifuge_dirt ticks, techs=["quantum_separators"] -> Fe +210
[VD][39] 60s of centrifuge_dirt ticks, techs=["industrial_catalysis"] -> Fe +245

The controls are the point: the same function, the same probe, the same tech-list mechanism moves for industrial_catalysis (+0.25 lands exactly) and for the gathering twin (+0.50 lands exactly). Only the upgrades_db table is inert. 600 real process_tick(0.1) calls give byte-identical Fe (210) for all three centrifuge tiers and 245 for the control, so this is not a display artifact.
Secondary claim in player_impact also verified by read: scripts/ui/processing_recipe_widget.gd:311-312 and :322 compute the shown duration from manager.get_recipe_speed_multiplier(rid), so the UI reports the unchanged duration too.
No ruling makes this intended: nothing in CLAUDE.md, docs/RULINGS_2026-08-08.md or docs/HANDOFF.md mentions it, and docs/SANITY_CHECKLIST.md:73 assumes processing speed bonuses stack.
```
</details>

### [46] m029a8 demands 12 Salvage Data, a Zone-3-only drop, eight beats before the chain unlocks Zone 3

**Verdict:** CONFIRMED · raised as *critical*, corrected to **major** · lens `res_mission_join`

**What is actually true.** Duplicate of finding 3. Confirmed: electronics_assembler costs SalvageData 12 (infrastructure_manager.gd:754), the single faucet in live data is z3_derelict_frigate's loot row in mars_debris (research_req zone_3_access), and the chain orders the build 8 beats before it opens Zone 3. The correct beat indices are 55 (m029a8) and 63 (m030e) by next_mission walk, not 81 and 89. The consequence is a stalled guided path plus a factually wrong mission description, not an unwinnable run.

**What the original finding got wrong.** (1) The absolute chain indices are wrong and unreproducible. "idx 81" for m029a8 and "idx 89" for m030e do not match a next_mission walk (55 / 63) or the declaration-row order (71 / 79). Only the delta of 8 survives, and finding 3 — the same defect from another lens — reports the same delta with different absolute numbers, so at least one of the two lenses is mis-indexing. Anyone acting on "idx 81" will look at the wrong beat. (2) This is a duplicate of finding 3, not a second defect; counting it separately double-weights the severity of one authoring mistake. (3) "the only escape is to guess" overstates — the Atlas indexes SalvageData to "Derelict Frigate / Mars Debris Field", and zone_3_access is buyable off-script at that point (I ran can_unlock -> true, unlock_tech -> true). (4) "walls on a material that cannot drop yet" is right about the material and wrong about the run: nothing outside mission_manager reads mission state, and sync_progress back-fills research beats, so no permanent state is lost.

**Is the proposed fix sound?** Yes, for the option this finding actually prefers. "Swap the 12 SalvageData for 12 DamagedCircuitry" is correct and verified: DamagedCircuitry drops from the Z1 boss (0.90, 2-4), z2_silicate_golem (0.40, 1-3) and z2_boss_monolith (0.90, 3-6), all reachable at m029a8, and it is already the Reclamation lane's feedstock so the demand lands on a live economy. Two caveats: the mission text must be rewritten with it (it names Salvage Data and also omits the Circuit 40 / 25,000 Lira half of the real cost), and the third option in the fix ("reorder so m029a8 sits after m030e") is the weak one — the m030c..m030d refit block depends on the assembler's own Circuit/AdvCircuit output, so reordering relocates the wall onto a Rare-gated boss fought without the refits written for it. The "add a Zone-2 SalvageData faucet" option would also work but dilutes the material's Mars identity for no gain over the swap.

**Repro:** `$TEMP/godot_check/Godot_v4.5.1-stable_win64_console.exe --headless --path . res://scenes/audit_tmp/res_mission_join.tscn | grep -E "m029a8|sources of SalvageData"`

<details><summary>Verifier's own measurement</summary>

```
Same defect as idx 3, reproduced by the same independent probe. Single-faucet claim, by generic recursion over all live data rather than a loot-table scan:
[SK] PRODUCERS of SalvageData = ["enemy:z3_derelict_frigate.loot"]
[SK] counts: enemies=65 zones=15 hazards=1 recipes=121 gather=21 buildings=97 techs=109 modules=194
[SK] producer z3_derelict_frigate lives in zone 'mars_debris' (diff 3) req_tech=zone_3_access unlock_flag=<none>

Ordering, by next_mission walk from m001 (chain length = 85):
[SK] idx=55   m029a8   type=build     target=electronics_assembler  qty=1 next=m029a9
[SK] idx=62   m030d    type=defeat    target=z2_boss_monolith       qty=1 next=m030e
[SK] idx=63   m030e    type=research  target=zone_3_access          qty=1 next=m017c

Independent second index instrument (declaration-row order in mission_manager.gd): m029a8 = row 71, m030d = row 78, m030e = row 79. Neither instrument yields the auditor's 81/89.

Substitute-token check for the proposed fix (read from combat_manager.gd enemy_db):
  z1 boss  rare_loot [["SalvagedAlloy",0.90,2,4],["DamagedCircuitry",0.90,2,4]]
  z2_silicate_golem rare_loot [["Ti",0.10,1,3],["DamagedCircuitry",0.40,1,3]]
  z2_boss_monolith  rare_loot [... ["DamagedCircuitry",0.90,3,6] ...]
```
</details>

### [47] The Zone-1 reorder makes the tutorial boss a corvette fight: Rare wins 7/21, against the project's own 60% Rare bar

**Verdict:** CONFIRMED · raised as *major*, corrected to **major** · lens `res_mission_join`

**What is actually true.** The reorder (commit 4562435, owner-driven and intended) moved m026e ahead of the frigate, so the Rogue Architect is now the only mandatory fight in the game fought on the starting corvette. Measured over 144 pooled trials, a full tier-matched RARE Zone-1 set clears it 43.8% of the time (Wilson 95% [35.9%, 51.9%]) — under any 60% reading. The stronger and previously unmeasured fact is that the loadout the chain actually produces at that beat — m026d's one RARE weapon plus the crafted Common Mass Driver / Basic Shield / Iron Plate / Basic Thruster / two Basic Batteries — clears it 1/51 = 2% [0%..10%], and the same loadout on the frigate clears 47/51 = 92%. The formal gear-check rule is still satisfied (Legendary 18/21 = 86%), so this is not a harness violation; it is a mission-chain/difficulty mismatch that no probe currently guards. Two records encode the pre-reorder order and are stale — boss_threshold.gd:31 (hull "frigate_hull") and HANDOFF:206-207 — and HANDOFF's companion claim that gearcheck reports Z1 "FAIL" is also now wrong (it reports OK).

**What the original finding got wrong.** Three things. (1) "the project's own 60% Rare bar" does not exist as a standalone bar. boss_gearcheck._test is `c_ok and u_ok and (rare_win or leg_win or uni_win)` and its own header says "Rare WIN (or Legendary WIN)". Legendary clears the corvette at 18/21 (86%), so the harness passes Z1 — my run of the real boss_gearcheck at 21 trials reports "OK Z1" and "15 bosses: 15 honor the rule, 0 VIOLATE". The auditor implies the harness flags this; it does not. (The nearest owner ruling that WOULD bite is RULINGS_2026-08-08 Ruling 3, "the zone must be clearable with Rare or better from that zone" — but that was ruled for Z11 specifically.) (2) 7/21 is a noisy low point estimate on a metric the project has a documented rule about; the true rate is ~44% [36%,52%] over 144 pooled trials. (3) Their harness omits the z1_engine the chain explicitly directs at m007/m007b — immaterial as it turns out (eva 4 vs accuracy 25 gives a 2.1% dodge; the +engine cell reads 26/51, identical to without) but it was an untested assumption. Finally, HANDOFF's line is stale in BOTH directions — the auditor flags "fights it on frigate" as stale but not "Gearcheck Z1 FAIL", which my run shows is also no longer true.

**Is the proposed fix sound?** Option (a) — put the frigate back before the boss — would revert an owner ruling made two days ago with an explicit rationale; not sound without owner sign-off, and it also re-creates the dependency inversion the commit fixed (the frigate frame costs Steel, which is the END of the industrial arc). Option (c) has the same problem. Option (b) is the sound one and my data names the lever exactly: charge_nuke {every_n: 8, mult: 4.2} on atk 26.667 is 112 damage per swing against a corvette that recalcs to maxhp 154-163 / shield 40-105, and a 65 s Rare fight eats ~4 of them. Cutting mult toward the ~2.0-3.0 band the other early bosses use (z3_derelict_frigate is 3.0; this boss's own comment still claims a stale "x1.75") is a single-number change with room to spare — Common and Uncommon currently lose with 70-82% boss HP left, so c_ok/u_ok will not break. Whatever is chosen, boss_threshold.gd:31 must derive its hull from get_chain_index()/the walked chain rather than being typed, and HANDOFF:206-207 needs both halves corrected, not just the "on frigate" half.

**Repro:** `$TEMP/godot_check/Godot_v4.5.1-stable_win64_console.exe --headless --path . res://scenes/audit_tmp/res_mission_join.tscn | grep -E "corvette_hull|frigate_hull|idx=(49|65|66)"`

<details><summary>Verifier's own measurement</summary>

```
ORDER + HULL (my chain walk from m001, not a topo sort):
[VCW]   m026e  walk_pos=23   topo_idx=49   type=defeat         target=z1_boss_architect
[VCW]   m026   walk_pos=39   topo_idx=65   type=research       target=shipwright_1
[VCW]   m026b  walk_pos=40   topo_idx=66   type=construct      target=frigate_hull
[VCW] --- every 'construct' beat in walk order ---
[VCW]   pos=40   m026b  construct frigate_hull   AFTER boss
[VCW]   pos=59   m030c  construct destroyer_hull   AFTER boss
[VCW] HULLS OWNED AT m026e (boss) = ["corvette_hull"]

COMBAT, 51 trials/cell, two independent runs:
run 1: corvette FLAT-Rare legBatt   20/51 =  39% [27%..53%]  medTTK= 65s
run 2: corvette FLAT-Rare legBatt   26/51 =  51% [38%..64%]  medTTK= 65s
run 2: corvette FLAT-Common legBatt  0/51 =   0% [0%..7%]
run 2: corvette FLAT-Uncommon        0/51 =   0% [0%..7%]
run 2: corvette FLAT-Legendary      43/51 =  84% [72%..92%]
run 2: corvette MIXED (1 rare + rest unc)  1/51 = 2% [0%..10%]
run 2: corvette CHAIN-real (1 rare gun)    1/51 = 2% [0%..10%]  | maxhp=154 shield=40 atkK=20.4 pwr=50/80
run 2: frigate  FLAT-Uncommon       50/51 =  98% [90%..100%]
run 2: frigate  FLAT-Rare           51/51 = 100% [93%..100%]
run 2: frigate  MIXED (1 rare + rest unc) 47/51 = 92% [81%..97%]

REAL boss_gearcheck, my run, --trials=21 (its _set_hull picks tier==zone, i.e. the corvette for Z1):
[BGC] OK   Z1  z1_boss_architect  w:kinetic hp:960 | C 0/21 L82% U 0/21 L70% R 10/21 W65 L 18/21 W58 | N-1uniq n/a
[BGC] ===== 15 bosses: 15 honor the rule, 0 VIOLATE =====

POOLED Rare-on-corvette (auditor 7/21 + mine 20/51 + 26/51 + 10/21) = 63/144 = 43.8%, Wilson 95% = [35.9%, 51.9%]. 60% is excluded. My 123 trials alone: 56/123 = 45.5%.
21 trials is NOT enough here either — the boss_gearcheck cell 10/21 has a Wilson interval of [28%, 68%], which straddles the bar. The auditor's 7/21 has [17%, 55%].

STALE RECORDS: boss_threshold.gd:31 still says hull "frigate_hull" under a comment claiming it is "traced from mission_manager construct/defeat order"; docs/HANDOFF.md:206-207 still says "mission path fights it on frigate: 8-9/9 Rare".

INTENT: git show 4562435 "Zone 1 ends with its boss; the industry that follows is what builds the frigate" — owner-driven, dated 2026-08-09 (one day after HANDOFF). Its own verification list is "type_unlock, onboarding_order, mission_routing, stale_mission, objective_marker, mission_reward, coach_arrow and quest_stock all pass" — no combat probe ran.

DEATH COST: combat_manager.gd:4189 "v124: no Lira death penalty — losing costs the consumed kits + module durability damage below, not credits."
```
</details>

### [51] Bounty payouts bank across a warp and instantly re-arm the prestige gate

**Verdict:** CONFIRMED · raised as *critical*, corrected to **major** · lens `warp_reset`

**What is actually true.** `execute_warp()` resets seven managers but never `bounty_manager` (grep: `bounty_manager.reset()` has exactly one caller, game_state.gd:638 in hard_reset). A completed-but-unclaimed contract therefore survives the warp, and claiming it afterwards adds to `lifetime_credits` AFTER the `credits_at_warp_start` snapshot, so it counts in full as post-warp progress. This does nothing at the earliest possible warp (Z3: 0 extra shards, measured) but from Zone 5 onward, banking the 3-contract cap across the warp and claiming immediately after yields a free second warp worth +3 shards at Z5, +4 at Z6 (the Warp-Core reveal tier, on top of a 5-shard first warp), +8 at Z8 and +11 at Z10 — roughly doubling the prestige yield of every run, for free, by delaying one button press. It is a bounded exploit, not a runaway loop: the second warp re-snapshots the baseline to 0, so escalation requires re-earning contracts each cycle.

**What the original finding got wrong.** Two things, both in the part that justified `critical`.

1. The named repro is refuted. player_impact says "The default flow triggers this by accident: the Singularity opens on a Z3+ boss kill... Kill boss -> rift opens -> warp -> then open the Bounty tab and claim." I ran exactly that: at Z3 the three best bankable contracts total 192,121 raw / 195,961 paid against a 500,000 threshold, and `FREE EXTRA SHARDS = 0`. The second warp did not fire. At the earliest warp the game offers, the gate is NOT re-armed.

2. The headline numbers are fixture artifacts. `[WR] ... +7205052519` and `shards 5 -> 19` come from `_build_fixture(true)`, which force-sets every flag in `get_progression_flags()` and then deliberately selects the single highest-difficulty contract on ANY board — a Zone-15 `the_caustic_core` bounty (I reproduced it: raw 7,494,222,774) dropped into a run whose lifetime_credits was 8,025,000. That is a ~900x mismatch between the banked contract and the run that banked it; it is not "the default flow", it is an NG+ endgame player. The finding is real without those numbers, so I am confirming it — but on the Z5-Z10 evidence, not the Z3 story or the 7.2B figure.

Also minor: the evidence line "MAX_ACTIVE contracts = 3 (that many payouts can be banked)" is right, and the amplification-by-production_multiplier claim is directionally right but small at the point it matters — I measured `production_multiplier=1.020` immediately post-warp at 1 shard, not a meaningful in-cycle amplifier.

**Is the proposed fix sound?** Yes, with one ordering caveat the fix already half-anticipates. Paying out completed-unclaimed contracts and then calling `bounty_manager.reset()` must both happen BEFORE the `credits_at_warp_start = lifetime_credits` snapshot (warp_manager.gd:218) and AFTER `research_manager.reset()` (~line 200) — the proposed insertion point at lines 201-202 satisfies both, since `reset()` ends in `generate_all_pools()` which calls `get_unlocked_zones()` and would otherwise reseed the new run's boards at the OLD research tier. Note the payout is intentionally value-lossy for the player: `gains` is already computed at line 142, so Liras settled at line 201 raise `lifetime_credits` and are then snapshotted away, meaning the player gets the money but no shards for it. That is the correct incentive (claim before you warp) and worth stating in the notification. The suggested `bounty_check.gd` assertion (`active_contracts` empty and `calculate_warp_gains() == 0` right after `execute_warp`) is exactly the right guard and would have caught this. Nothing breaks: no doc, ruling, or code comment claims bounty state is meant to survive a warp — the only recorded stance (AUD-P1-002, SANITY_CHECKLIST.md:153) is about hard_reset, and v132 added `reset()` precisely to stop prior-life contracts being claimable.

**Repro:** `"$TEMP/godot_check/Godot_v4.5.1-stable_win64_console.exe" --headless --path . res://scenes/audit_tmp/warp_reset.tscn   # read SECTION 5`

<details><summary>Verifier's own measurement</summary>

```
My own sweep, one clean hard_reset per row, MAX_ACTIVE(3) top contracts banked, real execute_warp, claim, then a second execute_warp:

[VWS] ===== V51: banked-bounty re-arm sweep across every plausible first-warp tier =====
[VWS]   Z3  rift opens (v138 singularity: any Z3+ boss kill) first-warp shards= 1 | 3 banked (raw 192121) paid 195961 post-warp | score 195961 vs thr 500000 | FREE EXTRA SHARDS = 0
[VWS]   Z5                                                   first-warp shards= 3 | 3 banked (raw 3369213) paid 3571364 post-warp | score 3571364 vs thr 500000 | FREE EXTRA SHARDS = 3
[VWS]   Z6  Warp-Core REVEAL (CLAUDE.md: zone_6_access)      first-warp shards= 5 | 3 banked (raw 7218509) paid 7940359 post-warp | score 7940359 vs thr 500000 | FREE EXTRA SHARDS = 4
[VWS]   Z8                                                   first-warp shards= 7 | 3 banked (raw 95323351) paid 108668619 post-warp | score 108668619 vs thr 500000 | FREE EXTRA SHARDS = 8
[VWS]   Z10 end of base game                                 first-warp shards=14 | 3 banked (raw 680984252) paid 871659841 post-warp | score 871659841 vs thr 500000 | FREE EXTRA SHARDS = 11

And the mechanism itself, measured directly (first probe run):
[VWS]      POST-WARP: shards=1 total_warps=1 credits_at_warp_start=705000 score=0 gains=0
[VWS]      POST-WARP: bounty active_contracts SURVIVED = 3 (completed-unclaimed=3)
[VWS]      claimed 3 PRE-warp contracts AFTER the warp: lifetime_credits 705000 -> 884990 (+179990)

So the survival + post-snapshot banking is real, and from Z5 onward it is worth +80% to +115% of the run's entire shard yield, repeatable every warp.
```
</details>

---

## Downgraded, refuted, and intended

| idx | verdict | now | finding |
|---|---|---|---|
| 5 | PARTLY_TRUE | minor | m024b tells the player to craft Battery Cells first; that recipe needs Engineering 6 and the chain h |
| 6 | PARTLY_TRUE | minor | The Hack Card arc reveals at the Zone-2 gate but its research bills a Zone-3 drop |
| 9 | PARTLY_TRUE | minor | Reward `stage` is the TABLE row index, not the chain position — the Zone 1 boss pays 98,750 and the  |
| 10 | PARTLY_TRUE | minor | Second cliff in the Zone 3 band: 200,000 -> 4,320 -> back to 303,000, a 46x trough over three beats |
| 16 | CONFIRMED | minor | m030fa orders 2 Composite Plates "one per armor slot" — every hull the chain has given the player ha |
| 17 | PARTLY_TRUE | minor | m029a8 itemizes the Electronics Assembler's cost and leaves out the 40 Circuit Boards |
| 24 | CONFIRMED | minor | get_chain_index() is not a chain order across branches - Kahn seeds all 17 roots first, so m002 rank |
| 28 | PARTLY_TRUE | minor | boss_gearcheck's "15/15, 0 violations" was measured with the four unreachable techs force-granted |
| 29 | CONFIRMED | minor | Cryogenic Armaments advertises two weapons — Cryo Repeater and Cryo Cannon — that exist nowhere in t |
| 34 | PARTLY_TRUE | minor | efficiency_1 demands 15,000 Common Artifacts, which only Zone 1 and Zone 2 drop |
| 35 | PARTLY_TRUE | minor | quantum_dynamics asks 40,000 RadIsotope from two trash mobs = 7,272 kills = for a node nothing else  |
| 40 | PARTLY_TRUE | minor | Omni-Fabrication's advertised "+30% Research Speed" is paid into a bonus key with zero consumers - h |
| 41 | PARTLY_TRUE | minor | Cryogenic Armaments promises three Cryo weapons; only one exists in the game |
| 42 | PARTLY_TRUE | minor | Advanced Mineralogy's card promises Titanium from Dirt centrifuging; 400 hand-crafts produce zero Ti |
| 43 | PARTLY_TRUE | minor | Warp Drive Theory and Quantum Dynamics have swapped unlock claims — one advertises a nonexistent ite |
| 48 | PARTLY_TRUE | minor | The Zone-1 corridor bills 40 Circuit Boards but only ever directs 10 — the Tin and Copper legs were  |
| 49 | PARTLY_TRUE | minor | The Hack Card core goal reveals a full zone before its research cost item can drop |
| 53 | PARTLY_TRUE | minor | quest_manager is never reset by a warp, contradicting its own code comment |
| 55 | CONFIRMED | minor | m017's kill is stored in an unpersisted field, so an autosave during the fight erases it |
| 0 | PARTLY_TRUE | note | Deprecated orphan beats outrank the entire live chain in get_chain_index, so guidance points at a cu |
| 11 | PARTLY_TRUE | note | Shipwright II costs 120,000 Liras and its mission pays 19,000 — the deepest mid-game negative-value  |
| 12 | PARTLY_TRUE | note | Every zone-access research from Sector Alpha on pays a small fraction of its own Lira cost (Z7: cost |
| 14 | PARTLY_TRUE | note | Same-era craft beats pay 2.7x apart purely from table row: Basic Shield (1,500 cost) pays 8,125 whil |
| 25 | PARTLY_TRUE | note | 20 beats use types that can never self-heal |
| 33 | PARTLY_TRUE | note | Z15 gear research bills 19,200 VoidLattice = 178 hours of a single faucet |
| 36 | PARTLY_TRUE | note | A node's material cost is decided by its Lira price at hard thresholds, so a one-Lira price edit mul |
| 37 | PARTLY_TRUE | note | Palladium's only source is a 30% byproduct and a research gate wants 450 of it |
| 38 | INTENDED_DESIGN | note | 19 prerequisite Lira inversions - the Zone 2 gate advertises 30,000 Liras but really costs 80,000 |
| 50 | PARTLY_TRUE | note | 45 gating techs are never named nor implied by the chain, including every ammo tier above T1 and the |
| 52 | PARTLY_TRUE | note | Every claimed research beat is orphaned by the warp — the chain re-teaches nothing |
| 56 | PARTLY_TRUE | note | _rescue_orphan_chains cannot rescue a deleted mission id — the case its own comment says it exists f |
| 57 | PARTLY_TRUE | note | Renaming or folding a research tech silently voids the player's paid unlock — no migration hook exis |
| 13 | REFUTED | not-a-defect | Three of the four early weapon/battery craft beats pay less than the Liras they cost, at the point t |
| 23 | REFUTED | not-a-defect | Earliest-in-chain removed the old defence against stale beats: a cut-from-chain legacy beat now owns |

### The two outright refutations

**[13] Three of the four early weapon/battery craft beats pay less than the Liras they cost, at the point the player has no income**

1) The headline count. m005b pays 2,025 against a 2,000-Lira cost — it is positive. Three becomes two, and the finding's own -35 is manufactured by pricing self-gathered Fe and Li at procurement rates as though the player bought them.

2) The premise. "at the point the player has no income" and "only ~5,000 banked by the time m015 is played at pos 10" — measured 12,090 gross / 8,765 net. Worse, the evidence block quotes a pos-23 cumulative and simply asserts the pos-10 number in a parenthetical. The quoted output does not show what the claim says.

3) The inflating caveat is backwards. "module costs are read pre-get_effective_module_cost (tier-gate alloys not counted), the real deficit is at least this large" — that function returns an identical duplicate of the cost dict. The v114 tier-gate comment above it is stale. There are no uncounted alloys; the deficit is exactly as measured and no larger.

4) It treats the crafted module as worthless. m015 buys two permanent Mass Drivers, which is the whole point of Liras at that stage — there is nothing else to spend them on — and Z1 drones drop those same modules at a 30% roll anyway.

5) "the worst possible first impression of the mission board as an income source" contradicts the game's own economy doc, which lists mission rewards as one faucet with combat credits dominant (docs/audit/ECONOMY_AUDIT_2026-08-02.md §4). The chain auth

**[23] Earliest-in-chain removed the old defence against stale beats: a cut-from-chain legacy beat now owns the arrow ahead of the player's real step**

Their "OLD rule" simulation silently dropped the tag == "[TUTORIAL]" filter from the function it claims to reproduce -- exactly the documented failure shape on this project (a probe written to find a bug, not to disprove one). With the real function the old rule returns m023, the same answer v175 gives, so the claimed "defence" never existed. They also never modelled the mechanism that actually drove the arrow pre-v175 (main.gd's source-file-order cascade), which picked the stale beat in 3/3 of my fixtures. And they did not check whether any save can hold the flag: nothing in the current build can set active:true on an orphan, and the developer's save does not.
