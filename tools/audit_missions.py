#!/usr/bin/env python3
"""audit_missions.py — static sanity check of every mission/goal step.

Parses the GENERATED scripts/core/game_data.gd (each const entry is one
JSON-compatible line) and validates the full mission flow without needing
Godot: chain linkage, target existence per mission type, gating research
reachability, and material obtainability. Exit code 1 on any ERROR.
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
GD = open(os.path.join(HERE, "..", "scripts", "core", "game_data.gd")).read()
MAIN = open(os.path.join(HERE, "..", "scripts", "ui", "main.gd")).read()
STATE = open(os.path.join(HERE, "..", "scripts", "core", "game_state.gd")).read()

def parse_dict_block(name):
    m = re.search(r'const %s := \{\n(.*?)\n\}' % name, GD, re.S)
    out = {}
    if not m:
        return out
    for line in m.group(1).splitlines():
        line = line.strip().rstrip(",")
        mm = re.match(r'"([^"]+)": (\{.*\})$', line)
        if mm:
            out[mm.group(1)] = json.loads(mm.group(2))
    return out

def parse_list_of_dicts(name):
    m = re.search(r'const %s := \[\n(.*?)\n\]' % name, GD, re.S)
    out = []
    if not m:
        return out
    for line in m.group(1).splitlines():
        line = line.strip().rstrip(",")
        if line.startswith("{"):
            out.append(json.loads(line))
    return out

def parse_string_list(name):
    m = re.search(r'const %s := (\[[^\]]*\])' % name, GD)
    return json.loads(m.group(1)) if m else []

MISSIONS = parse_dict_block("MISSIONS")
GATHER = parse_dict_block("GATHER")
CRAFT = parse_dict_block("CRAFT")
RESEARCH = parse_dict_block("RESEARCH")
ENEMIES = parse_dict_block("ENEMIES")
BUILDINGS = parse_dict_block("BUILDINGS")
HULLS = parse_dict_block("HULLS")
MODULES = parse_dict_block("MODULES")
SET_MODULES = parse_dict_block("SET_MODULES")
RESOURCES = parse_dict_block("RESOURCES")
ZONES = parse_list_of_dicts("ZONES")
ORDER = parse_string_list("MISSION_ORDER")
GOALS = parse_string_list("MISSION_GOALS")

errors, warns = [], []
def err(msg): errors.append(msg)
def warn(msg): warns.append(msg)

# ---------- obtainability: every way a resource symbol can be acquired ----------
sources = {}
def add_src(sym, how):
    sources.setdefault(sym, set()).add(how)
for gid, a in GATHER.items():
    for row in a.get("loot", []):
        add_src(row[0], "gather:" + gid)
for rid, r in CRAFT.items():
    for s in r.get("outputs", {}):
        add_src(s, "craft:" + rid)
    for row in r.get("bonus", []):
        add_src(row[0], "craftbonus:" + rid)
for eid, e in ENEMIES.items():
    for row in e.get("loot", []):
        add_src(row[0], "enemy:" + eid)
    bc = e.get("boss_core", "")
    if bc:
        add_src(bc, "bosscore:" + eid)
for bid, b in BUILDINGS.items():
    for s in b.get("yield", {}):
        add_src(s, "building:" + bid)
# code-granted drops (grep game_state for add_resource with a literal symbol)
for sym in re.findall(r'add_resource\("([A-Za-z0-9_]+)"', STATE):
    add_src(sym, "code-drop")

zone_ids = [z.get("id", "") for z in ZONES]
zone_enemies = set()
for z in ZONES:
    zone_enemies.update(z.get("enemies", []))
hz = parse_dict_block("HAZARD_ZONES")
for h in hz.values():
    zone_enemies.update(h.get("enemies", []) if isinstance(h.get("enemies", []), list) else [])
    for k in ("boss_enemy", "elite_enemy", "unlock_boss"):
        if h.get(k):
            zone_enemies.add(h[k])

# research reachability: walk parent + req_tech to roots. Memoized DFS with a
# recursion stack — a shared visited set would misread diamond deps (a tech
# required by both a node and its ancestor) as cycles.
_reach_memo = {}
def research_reachable(rid, stack=None):
    if rid in _reach_memo:
        return _reach_memo[rid]
    if stack is None:
        stack = set()
    if rid in stack:
        return False  # true cycle
    node = RESEARCH.get(rid)
    if node is None:
        _reach_memo[rid] = False
        return False
    stack.add(rid)
    ok = True
    parent = node.get("parent", "")
    if parent and not research_reachable(parent, stack):
        ok = False
    if ok:
        for req in node.get("req_tech", []):
            if not research_reachable(req, stack):
                ok = False
                break
    stack.discard(rid)
    _reach_memo[rid] = ok
    return ok

def check_research_gate(owner, rid):
    if not rid:
        return
    if rid not in RESEARCH:
        err("%s: research gate '%s' not in RESEARCH" % (owner, rid))
    elif not research_reachable(rid):
        err("%s: research gate '%s' has a broken prereq chain" % (owner, rid))
    else:
        for s in RESEARCH[rid].get("items", {}):
            if s not in sources:
                err("%s: research '%s' costs unobtainable item '%s'" % (owner, rid, s))

# mission types the runtime actually handles (sync/event/live-eval)
SYNC_TYPES = set(re.findall(r'^\t\t\t"([a-z_]+)":', re.search(r'func _mission_sync.*?missions_changed\.emit', STATE, re.S).group(0), re.M))
EVENT_TYPES = set(re.findall(r'_mission_event\("([a-z_]+)"', STATE))
# match arms may carry trailing comments — match the quoted arm at line start.
LIVE_TYPES = set(re.findall(r'^\t\t"([a-z_]+)":', re.search(r'func mission_completed.*?\n\treturn int', STATE, re.S).group(0), re.M))
HANDLED = SYNC_TYPES | EVENT_TYPES | LIVE_TYPES
COACH_TYPES = set(re.findall(r'"([a-z_]+)": "[a-z]*"', re.search(r'const COACH_PAGE := \{[^\n]*\}', MAIN).group(0)))
PAGE_IDS = set(json.loads(re.search(r'const PAGE_IDS := (\[[^\]]*\])', MAIN).group(1)))

# ---------- 1. chain linkage ----------
for i, mid in enumerate(ORDER):
    if mid not in MISSIONS:
        err("MISSION_ORDER[%d] '%s' missing from MISSIONS" % (i, mid)); continue
    nxt = MISSIONS[mid].get("next", "")
    want = ORDER[i + 1] if i + 1 < len(ORDER) else ""
    if nxt != want:
        err("chain: %s.next = '%s' but MISSION_ORDER expects '%s'" % (mid, nxt, want))

for gid in GOALS:
    if gid not in MISSIONS:
        err("MISSION_GOALS head '%s' missing from MISSIONS" % gid)
    if gid in ORDER:
        err("goal '%s' also appears in MISSION_ORDER" % gid)

# every goal chain terminates, no cycles, members not in ORDER
goal_members = set()
for gid in GOALS:
    cur, hops = gid, 0
    while cur:
        if hops > 20:
            err("goal chain from '%s' loops or is too long" % gid); break
        if cur not in MISSIONS:
            err("goal chain from '%s': '%s' missing" % (gid, cur)); break
        goal_members.add(cur)
        cur = MISSIONS[cur].get("next", ""); hops += 1

orphans = set(MISSIONS) - set(ORDER) - goal_members
if orphans:
    warn("missions not reachable from tutorial chain or goal heads: %s" % sorted(orphans))

# ---------- 2. per-mission validation ----------
def check_target_obtainable(mid, sym):
    if sym not in RESOURCES:
        err("%s: gather target '%s' not in RESOURCES" % (mid, sym))
    elif sym not in sources:
        err("%s: gather target '%s' has NO acquisition source" % (mid, sym))

for mid, m in MISSIONS.items():
    t = m.get("type", "")
    target = m.get("target", "")
    qty = int(m.get("qty", 1))
    if t not in HANDLED:
        err("%s: type '%s' is not handled by game_state (sync/event/live)" % (mid, t))
    if qty <= 0:
        err("%s: qty %d <= 0" % (mid, qty))
    nxt = m.get("next", "")
    if nxt and nxt not in MISSIONS:
        err("%s: next '%s' missing from MISSIONS" % (mid, nxt))
    # visit_page routes to its own target page in the coach — no COACH_PAGE entry needed.
    if mid in ORDER and t not in COACH_TYPES and t != "visit_page":
        warn("%s (tutorial): type '%s' has no COACH_PAGE entry (no nav hint)" % (mid, t))

    if t == "gather":
        check_target_obtainable(mid, target)
    elif t == "gather_multi":
        if not isinstance(target, dict) or not target:
            err("%s: gather_multi target must be a non-empty dict" % mid)
        else:
            for s in target:
                check_target_obtainable(mid, s)
    elif t == "research":
        check_research_gate(mid, target)
    elif t == "research_multi":
        if not isinstance(target, list) or not target:
            err("%s: research_multi target must be a non-empty list" % mid)
        else:
            for rid in target:
                check_research_gate(mid, rid)
            if qty > len(target):
                err("%s: qty %d > %d listed techs" % (mid, qty, len(target)))
    elif t == "craft":
        md = MODULES.get(target) or SET_MODULES.get(target)
        if md is None:
            err("%s: craft target '%s' not a module (craft event fires on buy_module)" % (mid, target))
        else:
            check_research_gate(mid, md.get("research_req", ""))
            for s in md.get("cost", {}):
                if s != "credits" and s not in sources:
                    err("%s: module '%s' costs unobtainable '%s'" % (mid, target, s))
    elif t == "construct":
        if target not in HULLS:
            err("%s: construct target '%s' not in HULLS" % (mid, target))
        else:
            for s in HULLS[target].get("cost", {}):
                if s != "credits" and s not in sources:
                    err("%s: hull '%s' costs unobtainable '%s'" % (mid, target, s))
    elif t == "build":
        if target not in BUILDINGS:
            err("%s: build target '%s' not in BUILDINGS" % (mid, target))
        else:
            check_research_gate(mid, BUILDINGS[target].get("research_req", ""))
    elif t == "defeat":
        if target not in ENEMIES:
            err("%s: defeat target '%s' not in ENEMIES" % (mid, target))
        elif target not in zone_enemies:
            err("%s: enemy '%s' not spawned by any zone/hazard" % (mid, target))
    elif t == "discover":
        if target not in zone_ids:
            err("%s: discover target '%s' not a zone id %s" % (mid, target, zone_ids))
    elif t == "visit_page":
        if target not in PAGE_IDS:
            err("%s: visit_page target '%s' not in PAGE_IDS" % (mid, target))
    elif t in ("drop_rarity", "loadout_rare_weapon"):
        if not str(target).isdigit():
            err("%s: %s target should be a rarity number, got '%s'" % (mid, t, target))
    elif t == "loadout_check":
        # target must be a module slot id (or ""/"combat_ready" for the full check)
        slots = {md.get("slot", "") for md in MODULES.values()} - {""}
        if target not in slots and target not in ("", "combat_ready"):
            err("%s: loadout_check target '%s' not a module slot %s" % (mid, target, sorted(slots)))
    elif t == "equip_consumables":
        if not str(target).isdigit():
            err("%s: equip_consumables target should be a count, got '%s'" % (mid, target))
    # warp_perform / overclock_install: no data target to validate

# ---------- 3. tutorial-specific pacing gates ----------
# For each tutorial gather target, the cheapest producing gather action / recipe
# must exist; flag its level/research gates for eyeballing.
for i, mid in enumerate(ORDER):
    m = MISSIONS.get(mid, {})
    if m.get("type") != "gather":
        continue
    sym = m.get("target", "")
    hows = sources.get(sym, set())
    gates = []
    for how in hows:
        kind, _, oid = how.partition(":")
        if kind == "gather":
            g = GATHER[oid]
            gates.append((int(g.get("level_req", 1)), g.get("research_req", ""), how))
        elif kind == "craft":
            r = CRAFT[oid]
            gates.append((int(r.get("level_req", 1)), r.get("research_req", ""), how))
    if gates:
        best = min(gates)
        if best[0] > 45:
            warn("%s (step %d): cheapest source for '%s' needs level %d (%s)" % (mid, i, sym, best[0], best[2]))
        if best[1]:
            check_research_gate("%s source %s" % (mid, best[2]), best[1])

# ---------- 4. tutorial ordering: research gates should be introduced first ----------
# A research gate on a step's target should be a tech the chain has already
# steered the player to (target of an earlier research/research_multi mission,
# or an ancestor of one) — otherwise the coach points at a locked card.
def closure(rid, acc):
    if rid in acc or rid not in RESEARCH:
        return
    acc.add(rid)
    node = RESEARCH[rid]
    if node.get("parent"):
        closure(node["parent"], acc)
    for req in node.get("req_tech", []):
        closure(req, acc)

# zone lookup helpers for steering checks
zone_by_id = {z.get("id", ""): z for z in ZONES}
def zone_of_enemy(eid):
    for z in ZONES:
        if eid in z.get("enemies", []):
            return z
    return None

introduced = set()
for i, mid in enumerate(ORDER):
    m = MISSIONS.get(mid, {})
    t = m.get("type", "")
    gates = []
    if t == "build" and m.get("target") in BUILDINGS:
        g = BUILDINGS[m["target"]].get("research_req", "")
        if g:
            gates.append(g)
    elif t == "craft":
        md = MODULES.get(m.get("target"), {}) or SET_MODULES.get(m.get("target"), {})
        if md.get("research_req"):
            gates.append(md["research_req"])
    elif t == "defeat":
        # The coach can only ring the enemy card if its zone is unlocked — the
        # zone's research gate must have been steered to by an earlier mission.
        z = zone_of_enemy(m.get("target", ""))
        if z is not None:
            g = z.get("research_req", "")
            if g and g not in introduced:
                err("order: step %d %s defeats '%s' in zone '%s' but its gate '%s' was never steered to by an earlier mission" % (i, mid, m["target"], z.get("id"), g))
    elif t == "gather":
        hows = sources.get(m.get("target"), set())
        cands = []
        for how in hows:
            kind, _, oid = how.partition(":")
            if kind == "gather":
                cands.append((int(GATHER[oid].get("level_req", 1)), GATHER[oid].get("research_req", "")))
            elif kind == "craft":
                cands.append((int(CRAFT[oid].get("level_req", 1)), CRAFT[oid].get("research_req", "")))
        # ok if ANY source is already introduced / ungated
        if cands and all(g and g not in introduced for _, g in cands):
            gates.append(min(cands)[1])
    for g in gates:
        if g and g not in introduced:
            warn("order: step %d %s needs research '%s' not steered to by any earlier mission" % (i, mid, g))
    # Desc-vs-gate consistency: a research mission claiming to "unlock Sector X"
    # must target the tech that actually gates that zone (catches display-name
    # collisions like deep_space_nav vs zone_6_access, both "Deep Space Navigation").
    if t == "research":
        dm = re.search(r'unlock (Sector [A-Za-z]+|[A-Z][a-z]+ (?:Belt|Debris|Orbit|Field|Expedition))', m.get("desc", ""))
        if dm:
            zone_name = dm.group(1)
            gz = [z for z in ZONES if zone_name.lower() in z.get("name", "").lower()]
            if gz and gz[0].get("research_req", "") and gz[0]["research_req"] != m.get("target"):
                err("desc: %s says it unlocks '%s' (gate '%s') but targets '%s'" % (mid, zone_name, gz[0]["research_req"], m.get("target")))
    if t == "research":
        closure(m.get("target", ""), introduced)
    elif t == "research_multi":
        for rid in m.get("target", []):
            closure(rid, introduced)

# ---------- 5. coach direction: every step must resolve to a real pointer ----------
# Mirrors main.gd _coach_resolve: page + (optionally) a pulsable card. A card-page
# pair is healthy when the card exists in the dataset that page builds cards from
# (all card builders set coach_id metas; sub-tabs are pre-selected by _show()).
COACH_PAGE = dict(re.findall(r'"([a-z_]+)": "([a-z]*)"', re.search(r'const COACH_PAGE := \{[^\n]*\}', MAIN).group(0)))
def coach_resolve(m):
    t, tgt = m.get("type", ""), m.get("target", "")
    if t == "gather":
        gs = [g for g in GATHER.values() for row in g.get("loot", []) if row[0] == tgt]
        if gs:
            return ("gather", "ok")
        if any(tgt in r.get("outputs", {}) for r in CRAFT.values()):
            return ("craft", "ok")
        if any(row[0] == tgt for e in ENEMIES.values() for row in e.get("loot", [])):
            return ("combat", "ok")
        return ("gather", "")
    if t == "gather_multi":
        return ("craft", "ok" if isinstance(tgt, dict) else "")
    if t == "research_multi":
        return ("research", "ok")
    if t == "visit_page":
        return (str(tgt), "")
    if t == "discover":
        z = zone_by_id.get(str(tgt))
        return ("research", z.get("research_req", "") if z else "MISSING-ZONE")
    return (COACH_PAGE.get(t, ""), "")

for mid in list(ORDER) + sorted(goal_members):
    m = MISSIONS.get(mid, {})
    page, card = coach_resolve(m)
    if m.get("type") not in ("", None) and page == "" and m.get("type") not in ("warp_perform", "overclock_install"):
        # page-less steps show only the desc — fine for goal-only types, worth
        # flagging for tutorial steps.
        if mid in ORDER:
            err("coach: tutorial step %s (type %s) resolves to NO page" % (mid, m.get("type")))
    if page and page not in PAGE_IDS:
        err("coach: %s resolves to unknown page '%s'" % (mid, page))
    if card == "MISSING-ZONE":
        err("coach: %s discover target '%s' is not a zone" % (mid, m.get("target")))
    if m.get("type") == "discover" and card == "":
        warn("coach: %s discover zone '%s' has no research gate to ring (flag-gated?)" % (mid, m.get("target")))

# ---------- report ----------
print("missions=%d order=%d goals=%d handled_types=%s" % (len(MISSIONS), len(ORDER), len(GOALS), sorted(HANDLED)))
for w in warns:
    print("WARN  " + w)
for e in errors:
    print("ERROR " + e)
print("RESULT: %d errors, %d warnings" % (len(errors), len(warns)))
sys.exit(1 if errors else 0)
