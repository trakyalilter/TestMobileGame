import json, re

HZ = "/tmp/hz"
ELEM = "/tmp/horizonidle/assets/elements.json"
OUT = "/home/user/TestMobileGame/scripts/core/game_data.gd"

elements = json.load(open(ELEM))
gather = json.load(open(f"{HZ}/gather.json"))
recipes = json.load(open(f"{HZ}/recipes.json"))
tech = json.load(open(f"{HZ}/tech_tree.json"))
zones = json.load(open(f"{HZ}/zones.json"))
enemies = json.load(open(f"{HZ}/enemies.json"))
buildings = json.load(open(f"{HZ}/buildings.json"))
hulls = json.load(open(f"{HZ}/hulls.json"))
missions = json.load(open(f"{HZ}/missions.json"))
research_graphs = json.load(open(f"{HZ}/research_graphs.json"))
modules = {k: v for k, v in json.load(open(f"{HZ}/modules.json")).items() if not v.get("is_custom")}
all_modules = json.load(open(f"{HZ}/modules.json"))

# ---- colors by element category ----
CAT_COLOR = {
    "Raw Material": "b0895a", "Noble Gas": "7fd0e0", "Alkali Metal": "e0734f",
    "Alkaline Earth Metal": "e0a24f", "Transition Metal": "c4c8d0",
    "Post-transition Metal": "9aa3af", "Metalloid": "9ad36a", "Reactive Nonmetal": "6ad36a",
    "Nonmetal": "6ad36a", "Halogen": "d06ad0", "Lanthanide": "8a7ad6", "Actinide": "b07ad6",
    "Component": "5ad1e0", "Alloy": "cfd3da", "Crafted": "5ad17a", "Crafted Material": "5ad17a",
    "Ammunition": "e0654f", "Consumable": "e0b44f", "Artifact": "b07ad6", "Exotic": "e05fb0",
}
def color_for(cat, tier):
    return CAT_COLOR.get(cat, "9aa3af")

# ---- base resource table from elements.json ----
RES = {}
for e in elements:
    sym = e["symbol"]
    RES[sym] = {
        "name": e.get("name", sym),
        "color": color_for(e.get("category", ""), e.get("tier", 0)),
        "value": int(e.get("base_value", 0)),
    }

def prettify(sym):
    return re.sub(r'(?<!^)(?=[A-Z])', ' ', sym).strip()

def ensure(sym):
    if sym not in RES:
        RES[sym] = {"name": prettify(sym), "color": "9aa3af", "value": 1}

# collect symbols referenced everywhere so display never shows a raw id
for a in gather.values():
    for row in a.get("loot_table", []):
        ensure(row[0])
for r in recipes.values():
    for s in r.get("input", {}): ensure(s)
    for s in r.get("output", {}): ensure(s)
    for row in r.get("output_table", []): ensure(row[0])
for en in enemies.values():
    for row in en.get("loot", []): ensure(row[0])
for t in tech.values():
    for s in t.get("cost_items", {}): ensure(s)
for b in buildings.values():
    for s in b.get("cost", {}):
        if s != "credits": ensure(s)
    for s in b.get("input", {}): ensure(s)
    for s in b.get("yield", {}): ensure(s)
    for s in b.get("yield_bonus", {}): ensure(s)
for h in hulls.values():
    for s in h.get("cost", {}):
        if s != "credits": ensure(s)
for mo in modules.values():
    for s in mo.get("cost", {}):
        if s != "credits": ensure(s)

# ---- emit helpers ----
def g(v):
    """GDScript literal for a python value."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, list):
        return "[" + ", ".join(g(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ", ".join(f"{g(k)}: {g(val)}" for k, val in v.items()) + "}"
    if v is None:
        return '""'
    return g(str(v))

lines = []
lines.append("extends Node")
lines.append("## AUTO-GENERATED from horizonidle-godot content. Autoloaded as `GameData`.")
lines.append("")

# RESOURCES
lines.append("const RESOURCES := {")
for sym, d in RES.items():
    lines.append(f'\t{g(sym)}: {{"name": {g(d["name"])}, "color": {g(d["color"])}, "value": {d["value"]}}},')
lines.append("}")
lines.append("")

# GATHER
lines.append('const GATHER_CATS := [')
lines.append('\t{"id": "terrestrial", "label": "Terrestrial"},')
lines.append('\t{"id": "orbital", "label": "Orbital"},')
lines.append('\t{"id": "void", "label": "Void"},')
lines.append(']')
lines.append("const GATHER := {")
for gid, a in gather.items():
    d = {
        "name": a["name"],
        "loot": a.get("loot_table", []),
        "xp": a.get("xp", 0),
        "level_req": a.get("level_req", 1),
        "duration": a.get("duration", 4.0),
        "category": a.get("category", "terrestrial"),
    }
    if a.get("research_req"):
        d["research_req"] = a["research_req"]
    lines.append(f"\t{g(gid)}: {g(d)},")
lines.append("}")
lines.append("")

# CRAFT (processing recipes)
# Category is inferred exactly like the desktop processing_page._get_recipe_category
# (explicit category honoured, else keyword rules) so recipes land in the right
# tab instead of all dumping into a single "Other" bucket.
RACK_LABELS = {
    "basics": "Basic Operations", "smelting": "Refining", "alloys": "Alloy Fabrication",
    "materials": "Advanced Materials", "electronics": "Electronics", "batteries": "Power Cells",
    "munitions": "Munitions", "consumables_hull": "Hull Repair", "consumables_shield": "Shield Kits",
    "research": "Research & Artifacts", "salvage": "Salvage", "endgame": "Endgame", "processing": "Processing",
}
RACK_ORDER = ["basics", "smelting", "alloys", "materials", "electronics", "batteries",
              "munitions", "consumables_hull", "consumables_shield", "research",
              "salvage", "endgame", "processing"]
def _has(rid, *kw):
    return any(k in rid for k in kw)
def recipe_category(rid, data):
    if data.get("category"):
        return data["category"]
    if _has(rid, "slug", "cell_t", "craft_cell", "rounds"): return "munitions"
    if "battery" in rid: return "batteries"
    if _has(rid, "circuit", "chip", "semiconductor", "hydraulics"): return "electronics"
    if _has(rid, "artifact", "res1", "res2", "res3", "nav_data", "decrypt"): return "research"
    if _has(rid, "bronze", "steel", "alloy", "galvanize", "stainless"): return "alloys"
    if _has(rid, "smelt", "refine", "extract", "centrifuge", "electrolysis", "leach", "process_", "panning"): return "smelting"
    if _has(rid, "sift", "charcoal", "burn", "wash"): return "basics"
    if _has(rid, "fiber", "polymer", "graphite", "nanoweave", "mesh", "sealant", "coolant", "carbon"): return "materials"
    return "materials"

_recipe_cat = {rid: recipe_category(rid, r) for rid, r in recipes.items()}
_used_cats = [c for c in RACK_ORDER if c in _recipe_cat.values()]
for c in _recipe_cat.values():            # any explicit category not in RACK_ORDER
    if c not in _used_cats:
        _used_cats.append(c)
lines.append("const CRAFT_CATS := [")
for cid in _used_cats:
    lines.append(f'\t{{"id": {g(cid)}, "label": {g(RACK_LABELS.get(cid, cid.capitalize()))}}},')
lines.append("]")
lines.append("const CRAFT := {")
for rid, r in recipes.items():
    d = {
        "name": r["name"],
        "inputs": r.get("input", {}),
        "outputs": r.get("output", {}),
        "bonus": r.get("output_table", []),
        "xp": r.get("xp", 0),
        "level_req": r.get("level_req", 1),
        "duration": r.get("duration", 4.0),
        "category": _recipe_cat[rid],
    }
    if r.get("research_req"):
        d["research_req"] = r["research_req"]
    lines.append(f"\t{g(rid)}: {g(d)},")
lines.append("}")
lines.append("")

# RESEARCH (tech tree; cost = credits, items = cost_items, parent chain)
lines.append("const RESEARCH := {")
for tid, t in tech.items():
    d = {
        "name": t.get("name", tid),
        "desc": (t.get("description", "") or "").replace("\n", " · "),
        "credits": int(t.get("cost", 0)),
        "items": t.get("cost_items", {}),
        "parent": t.get("parent") or "",
    }
    lines.append(f"\t{g(tid)}: {g(d)},")
lines.append("}")
lines.append("")

# ENEMIES
lines.append("const ENEMIES := {")
for eid, en in enemies.items():
    st = en.get("stats", {})
    loot = []
    for row in en.get("loot", []):
        if len(row) == 3:
            loot.append([row[0], 1.0, row[1], row[2]])
        elif len(row) == 4:
            loot.append(row)
    d = {
        "name": en.get("name", eid),
        "hp": st.get("hp", 10),
        "atk": st.get("atk", 1),
        "def": st.get("def", 0),
        "interval": st.get("atk_interval", 2.0),
        "accuracy": st.get("accuracy", 0),
        "max_shield": st.get("max_shield", 0),
        "eva": st.get("eva", 0),
        "is_boss": en.get("is_boss", False),
        "drop_chance": en.get("module_drop_chance", 0.0),
        "drop_pool": en.get("module_drop_pool", []),
        "loot": loot,
        "xp": en.get("xp", 0),
    }
    lines.append(f"\t{g(eid)}: {g(d)},")
lines.append("}")
lines.append("")

# ZONES (ordered)
lines.append("const ZONES := [")
for zid, z in zones.items():
    d = {
        "id": zid,
        "name": z.get("name", zid),
        "desc": z.get("desc", ""),
        "difficulty": z.get("difficulty", 1),
        "enemies": [e for e in z.get("enemies", []) if e in enemies],
    }
    if z.get("research_req"):
        d["research_req"] = z["research_req"]
    lines.append(f"\t{g(d)},")
lines.append("]")
lines.append("")

# RESEARCH_GRAPHS — per-tab node layout (positioned canvas + parent branches),
# ported 1:1 from the desktop research_page.gd `graphs` dict so the mobile
# research view shows the same trees, tabs and node positions.
TAB_ORDER = ["Operations", "Engineering", "Ships"]
lines.append("const RESEARCH_TABS := %s" % g(TAB_ORDER))
lines.append("const RESEARCH_GRAPHS := {")
for tab in TAB_ORDER:
    gd = research_graphs[tab]
    pos = gd["pos"]
    # Only nodes that exist in the tech tree AND have a position are drawn.
    items = [(nid, xy) for nid, xy in pos.items() if nid in tech]
    pos_str = "{" + ", ".join('%s: Vector2(%g, %g)' % (g(nid), xy[0], xy[1]) for nid, xy in items) + "}"
    lines.append(f"\t{g(tab)}: {{\"nodes\": {g([nid for nid,_ in items])}, \"pos\": {pos_str}}},")
lines.append("}")
lines.append("")

# BUILDINGS (infrastructure)
lines.append("const BUILDING_CATS := [")
for cid, lbl in [("power", "Power"), ("extraction", "Extraction"), ("industry", "Industry"), ("logistics", "Logistics")]:
    lines.append(f'\t{{"id": {g(cid)}, "label": {g(lbl)}}},')
lines.append("]")
lines.append("const BUILDINGS := {")
for bid, b in buildings.items():
    d = {
        "name": b.get("name", bid),
        "desc": b.get("description", ""),
        "cost": b.get("cost", {}),
        "yield": b.get("yield", {}),
        "input": b.get("input", {}),
        "energy_gen": b.get("energy_gen", 0.0),
        "energy_cons": b.get("energy_cons", 0.0),
        "interval": b.get("interval", 1.0),
        "category": b.get("category", "industry"),
    }
    if b.get("research_req"): d["research_req"] = b["research_req"]
    if b.get("max"): d["max"] = b["max"]
    if b.get("yield_bonus"): d["yield_bonus"] = b["yield_bonus"]
    if b.get("special"): d["special"] = b["special"]
    lines.append(f"\t{g(bid)}: {g(d)},")
lines.append("}")
lines.append("")

# SHIPYARD: hulls + modules
lines.append("const HULLS := {")
for hid, h in hulls.items():
    st = h.get("stats", {})
    d = {
        "name": h.get("name", hid),
        "hp": st.get("hp", 100),
        "atk": st.get("atk", 0),
        "energy_capacity": st.get("energy_capacity", 0),
        "cost": h.get("cost", {}),
        "slots": h.get("slots", []),
        "tier": h.get("tier", 0),
    }
    if h.get("research_req"): d["research_req"] = h["research_req"]
    lines.append(f"\t{g(hid)}: {g(d)},")
lines.append("}")
lines.append("const SLOT_LABELS := {\"weapon\": \"Weapon\", \"shield\": \"Shield\", \"engine\": \"Engine\", \"battery\": \"Battery\", \"sensor\": \"Sensor\", \"cooling\": \"Cooling\", \"armor\": \"Armor\", \"gem\": \"Core\", \"gem_synth\": \"Core\"}")
lines.append("const MODULES := {")
for mid, mo in modules.items():
    d = {
        "name": mo.get("name", mid),
        "slot": mo.get("slot_type", ""),
        "stats": mo.get("stats", {}),
        "cost": mo.get("cost", {}),
        "desc": (mo.get("desc", "") or "").replace("\n", " "),
    }
    if mo.get("research_req"): d["research_req"] = mo["research_req"]
    lines.append(f"\t{g(mid)}: {g(d)},")
lines.append("}")
lines.append("")

# SET pieces (unique 3-piece sets) + set defs + gems
import re as _re
set_modules = {k: v for k, v in all_modules.items() if (v.get("desc", "") or "").startswith("(Set)")}
SET_BOSS = {
    "Architect's Regalia": "rogue_architect", "Monolith's Resolve": "silicate_monolith",
    "Warmaster's Arsenal": "martian_warmaster", "Cryo-Lord's Chill": "cryo_lord",
    "Harbinger's Omen": "xenon_harbinger", "Overseer's Command": "overseer_prime",
    "Rad-Beast's Hide": "rad_beast_alpha", "Sovereign's Prism": "prismatic_sovereign",
    "Patient Zero's Strain": "patient_zero", "Time Weaver's Paradox": "time_weaver",
}
SET_BONUS = {"Cryo-Lord's Chill": "cryo", "Sovereign's Prism": "sovereign", "Patient Zero's Strain": "patient_zero"}
SET_BONUS_DESC = {
    "cryo": "Enemies attack 15% slower", "sovereign": "15% chance to reflect 100% damage",
    "patient_zero": "Regenerate hull during combat",
}
sets = {}
for mid, m in set_modules.items():
    sn = m["desc"].split("[")[0].replace("(Set)", "").strip()
    sets.setdefault(sn, []).append(mid)

lines.append("const SET_MODULES := {")
for mid, m in set_modules.items():
    sn = m["desc"].split("[")[0].replace("(Set)", "").strip()
    d = {"name": m.get("name", mid), "slot": m.get("slot_type", ""), "stats": m.get("stats", {}),
         "desc": (m.get("desc", "") or "").replace("\n", " "), "rarity": 4, "set": sn}
    lines.append(f"\t{g(mid)}: {g(d)},")
lines.append("}")
lines.append("const SETS := {")
for sn, pieces in sets.items():
    d = {"name": sn, "pieces": pieces, "boss": SET_BOSS.get(sn, ""),
         "bonus": SET_BONUS.get(sn, ""), "bonus_desc": SET_BONUS_DESC.get(SET_BONUS.get(sn, ""), "")}
    lines.append(f"\t{g(sn)}: {g(d)},")
lines.append("}")
GEMS = {
    "CrackedCrimsonCore": {"atk_kinetic_mult": 0.02, "atk_energy_mult": 0.02, "crit_chance": 0.02},
    "StableCrimsonCore": {"atk_kinetic_mult": 0.05, "atk_energy_mult": 0.05, "crit_chance": 0.05},
    "PristineCrimsonCore": {"atk_kinetic_mult": 0.10, "atk_energy_mult": 0.10, "crit_chance": 0.10},
    "CrackedCobaltCore": {"max_shield_mult": 0.02, "shield_regen_mult": 0.02, "eva_mult": 0.02},
    "StableCobaltCore": {"max_shield_mult": 0.05, "shield_regen_mult": 0.05, "eva_mult": 0.05},
    "PristineCobaltCore": {"max_shield_mult": 0.10, "shield_regen_mult": 0.10, "eva_mult": 0.10},
    "CrackedTopazCore": {"energy_capacity_mult": 0.02}, "StableTopazCore": {"energy_capacity_mult": 0.05},
    "PristineTopazCore": {"energy_capacity_mult": 0.10},
    "CrackedAmethystCore": {"def_mult": 0.02, "hp_mult": 0.02}, "StableAmethystCore": {"def_mult": 0.05, "hp_mult": 0.05},
    "PristineAmethystCore": {"def_mult": 0.10, "hp_mult": 0.10},
}
GEM_NAMES = {"Crimson": "Crimson Core", "Cobalt": "Cobalt Core", "Topaz": "Topaz Core", "Amethyst": "Amethyst Core"}
lines.append("const GEMS := {")
for gid, eff in GEMS.items():
    ensure(gid)
    tier = "Cracked" if gid.startswith("Cracked") else ("Stable" if gid.startswith("Stable") else "Pristine")
    color = gid.replace("Cracked", "").replace("Stable", "").replace("Pristine", "").replace("Core", "")
    lines.append(f'\t{g(gid)}: {{"name": {g(tier + " " + GEM_NAMES.get(color, color))}, "effects": {g(eff)}}},')
lines.append("}")
lines.append("")

# CONSUMABLES (auto-use repair/shield kits) + ammo bonus tiers
lines.append('const CONSUMABLES := {')
for cid, ctype, pct, nm in [
    ("EmergencyPatch", "hull", 0.10, "Emergency Patch"),
    ("ChitinPatch", "hull", 0.15, "Chitin Hull Patch"),
    ("Mesh", "hull", 0.25, "Nanoweave Mesh"),
    ("Seal", "hull", 0.35, "Hull Sealant"),
    ("AdvMaintenanceKit", "hull", 0.50, "Adv. Maintenance Kit"),
    ("CapacitorShard", "shield", 0.10, "Capacitor Shard"),
    ("BasicBooster", "shield", 0.15, "Shield Booster"),
    ("IonField", "shield", 0.25, "Ion Field Projector"),
    ("NitroCoolant", "shield", 0.35, "Cryo-Shield Matrix"),
    ("ZeroPoint", "shield", 0.50, "Zero-Point Injector"),
]:
    ensure(cid)
    lines.append(f'\t{g(cid)}: {{"type": {g(ctype)}, "heal_pct": {pct}, "name": {g(nm)}}},')
lines.append('}')
lines.append("")

# MISSIONS (tutorial chain)
# Restore the two missions that the original extraction skipped (their special
# types are now supported): m005 Mineral Washing (gather_multi) and m016b Combat
# Ready (loadout_check). Insert each right after its predecessor.
def _insert_after(lst, after_id, item):
    if any(x["id"] == item["id"] for x in lst):
        return
    for i, x in enumerate(lst):
        if x["id"] == after_id:
            lst.insert(i + 1, item)
            return
    lst.append(item)
_insert_after(missions, "m004", {
    "id": "m005", "name": "Mineral Washing",
    "desc": "Recover 75 Silicon and 75 Iron from Dirt.",
    "type": "gather_multi", "target": {"Si": 75, "Fe": 75},
    "qty": 150, "cr": 1000, "xp": 200, "next": "m007"})
_insert_after(missions, "m024", {
    "id": "m016b", "name": "Combat Ready",
    "desc": "Equip a Weapon and a Shield in the Ship Designer.",
    "type": "loadout_check", "target": "combat_ready",
    "qty": 1, "cr": 300, "xp": 100, "next": "m017"})

# Re-link each mission to the next SURVIVING mission by chasing the ORIGINAL
# chain order (robust to any mission still missing).
import re as _re2
_orig_next = {}
try:
    _mm = open("/tmp/horizonidle/scripts/managers/mission_manager.gd").read()
    for _line in _mm.splitlines():
        _m = _re2.match(r'\s*\["(m\w+)".*,\s*"(\w*)"\s*\],?\s*$', _line)
        if _m:
            _orig_next[_m.group(1)] = _m.group(2)
except Exception as _e:
    print("WARN: could not parse original mission chain:", _e)
_present = {m["id"] for m in missions}
def _fix_next(mid):
    n = _orig_next.get(mid, "")
    seen = set()
    while n and n not in _present and n not in seen:
        seen.add(n)
        n = _orig_next.get(n, "")
    return n if n in _present else ""
if _orig_next:
    for m in missions:
        m["next"] = _fix_next(m["id"])

lines.append("const MISSIONS := {")
for m in missions:
    d = {"name": m["name"], "desc": m["desc"], "type": m["type"], "target": m["target"],
         "qty": m["qty"], "cr": m["cr"], "xp": m["xp"], "next": m["next"]}
    lines.append(f"\t{g(m['id'])}: {g(d)},")
lines.append("}")
lines.append('const MISSION_ORDER := %s' % g([m["id"] for m in missions]))
lines.append("")

# helpers
lines.append("func res_name(sym: String) -> String:")
lines.append('\treturn RESOURCES.get(sym, {}).get("name", sym)')
lines.append("")
lines.append("func color_for(sym: String) -> Color:")
lines.append('\treturn Color.html(RESOURCES.get(sym, {}).get("color", "ffffff"))')
lines.append("")
lines.append("func value_of(sym: String) -> int:")
lines.append('\treturn int(RESOURCES.get(sym, {}).get("value", 0))')
lines.append("")
lines.append("func fmt(n) -> String:")
lines.append("\tvar v := int(n)")
lines.append('\tif v >= 1000000: return "%.2fM" % (v / 1000000.0)')
lines.append('\tif v >= 1000: return "%.1fK" % (v / 1000.0)')
lines.append("\treturn str(v)")
lines.append("")

open(OUT, "w").write("\n".join(lines))
print(f"Wrote {OUT}")
print(f"  resources={len(RES)} gather={len(gather)} craft={len(recipes)} research={len(tech)} enemies={len(enemies)} zones={len(zones)}")
