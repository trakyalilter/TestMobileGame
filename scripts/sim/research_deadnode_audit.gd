extends Node

# Research dead-node audit. For every tech_tree node, cross-references EVERY way a
# tech can matter and classifies the ones that matter for NOTHING.
#
# A node "does something" if ANY of:
#   - gate: something has research_req == it (building / recipe / gather / module / zone)
#   - late_mod: it's in shipyard LATE_MODULE_REQ_TECHS (late-module cost gate)
#   - effect: non-empty effects[] (a displayed stat bonus)
#   - code_bonus: get_efficiency_bonus() hardcodes a bonus for it
#   - literal: some script hardcodes is_tech_unlocked("it") to gate a feature/reveal
# Structural / reward-only roles (grants nothing itself, but load-bearing):
#   - bridge: it's a parent/req_tech of another tech (gates other research)
#   - mission: a research-type mission targets it (peeling soft-locks the mission)
#
# Run: tools/run_sim.ps1 -Scene "res://scenes/research_deadnode_audit.tscn"

# From get_efficiency_bonus() match arms + hub bonuses (research_manager.gd).
const CODE_BONUS_NODES := [
	"combat_heuristics", "shield_harmonics", "hull_hardening", "core_overclocking",
	"deep_core_optics", "colony_automation", "nano_fabrication", "perfect_automation",
	"industrial_catalysis", "basic_engineering", "materials_science",
	"industrial_logistics", "xeno_engineering",
]
# From: grep is_tech_unlocked("literal") across scripts/.
const TECH_LITERAL_CHECKS := [
	"advanced_mineralogy", "auto_repair_20", "auto_repair_40", "auto_repair_60",
	"auto_repair_80", "basic_engineering", "combustion", "efficiency_1",
	"efficiency_2", "efficiency_3", "efficiency_4", "efficiency_5",
	"firmware_hacking", "industrial_logistics", "materials_science",
	"oxygen_blast_furnace", "shipwright_1", "void_shielding_1", "void_weaponry_1",
	"xeno_engineering", "zone_2_access",
]

func _ready() -> void:
	call_deferred("_boot")

var gate_names := {}   # tech_id -> ["Building: X", "Recipe: Y", ...] (what it ACTUALLY gates)

func _collect_req(container, field: String, out: Dictionary, label: String) -> void:
	for k in container:
		var e = container[k]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var rk: String = str(e.get(field, ""))
		if rk != "" and rk != "-" and rk != "null":
			if not out.has(rk):
				out[rk] = {}
			out[rk][label] = int(out[rk].get(label, 0)) + 1
			if not gate_names.has(rk):
				gate_names[rk] = []
			gate_names[rk].append("%s: %s" % [label, str(e.get("name", k))])

func _boot() -> void:
	GameState.set_process(false)
	var rm = GameState.research_manager
	var tt = rm.tech_tree

	# 1. research_req gate references across all content subsystems.
	var gates := {}
	_collect_req(GameState.infrastructure_manager.building_db, "research_req", gates, "bld")
	_collect_req(GameState.processing_manager.recipes, "research_req", gates, "rcp")
	_collect_req(GameState.gathering_manager.actions, "research_req", gates, "gth")
	_collect_req(GameState.shipyard_manager.modules, "research_req", gates, "mod")
	_collect_req(GameState.shipyard_manager.hulls, "research_req", gates, "hull")
	_collect_req(GameState.combat_manager.zones, "research_req", gates, "zone")

	# early/late-module cost-scaling gates (shipyard consts)
	var late_mod := {}
	for t in GameState.shipyard_manager.LATE_MODULE_REQ_TECHS:
		late_mod[str(t)] = true
	for t in GameState.shipyard_manager.EARLY_MODULE_REQ_TECHS:
		late_mod[str(t)] = true

	# 2. bridge links: node -> [children that list it as parent/req_tech]
	var children := {}
	for tid_v in tt:
		var node = tt[tid_v]
		for pf in ["parent", "req_tech"]:
			var pk: String = str(node.get(pf, ""))
			if pk != "" and pk != "null":
				if not children.has(pk):
					children[pk] = []
				if not (str(tid_v) in children[pk]):
					children[pk].append(str(tid_v))

	# 3. research-type mission targets
	var mtargets := {}
	for mid in GameState.mission_manager.missions:
		var m = GameState.mission_manager.missions[mid]
		if str(m.get("type", "")) == "research":
			var t: String = str(m.get("target", ""))
			if t != "":
				if not mtargets.has(t):
					mtargets[t] = []
				mtargets[t].append(str(mid))

	# classify
	var dead := []
	var pure_bridge := []
	var mission_only := []
	var bridge_and_mission := []
	var hidden := []   # functional but shows an EMPTY tooltip (contribution invisible)
	var functional: int = 0

	for tid_v in tt:
		var tid: String = str(tid_v)
		var node = tt[tid]
		var gated: int = 0
		if gates.has(tid):
			for s in gates[tid]:
				gated += int(gates[tid][s])
		var eff = node.get("effects", [])
		var has_effect: bool = (eff is Array and eff.size() > 0)
		var has_code: bool = (tid in CODE_BONUS_NODES)
		var has_literal: bool = (tid in TECH_LITERAL_CHECKS)
		var has_latemod: bool = late_mod.has(tid)
		var is_bridge: bool = children.has(tid)
		var is_mtarget: bool = mtargets.has(tid)
		var is_functional: bool = gated > 0 or has_effect or has_code or has_literal or has_latemod

		if is_functional:
			functional += 1
			# Does the player SEE why it matters? Tooltip = unlocks[] + effects[].
			# If both empty, the node's contribution (code bonus / cost-gate / literal
			# feature-gate) is invisible in the tree — a "why is this here?" node.
			var ud0 = node.get("unlocks", [])
			var ud_empty: bool = (not (ud0 is Array)) or ud0.size() == 0
			if ud_empty and not has_effect and gated == 0:
				hidden.append({
					"id": tid, "name": str(node.get("name", tid)), "tier": int(node.get("tier", 0)),
					"why": _why(has_code, has_literal, has_latemod, children.has(tid), mtargets.has(tid)),
				})
			continue

		var row := {
			"id": tid, "name": str(node.get("name", tid)), "tier": int(node.get("tier", 0)),
			"type": str(node.get("type", "?")),
			"children": children.get(tid, []), "missions": mtargets.get(tid, []),
			"unlocks_disp": node.get("unlocks", []), "cost": node.get("cost", 0),
		}
		if is_bridge and is_mtarget:
			bridge_and_mission.append(row)
		elif is_bridge:
			pure_bridge.append(row)
		elif is_mtarget:
			mission_only.append(row)
		else:
			dead.append(row)

	# Tooltip-completeness pass: functional nodes whose DISPLAY (unlocks[]/effects[])
	# under-reports what they do — the blank/misleading-tooltip class (Automated
	# Logistics gates the Industrial Centrifuge but shows nothing).
	var tooltip_gaps := []
	for tid_v2 in tt:
		var tid2: String = str(tid_v2)
		var node2 = tt[tid2]
		var actual = gate_names.get(tid2, [])
		var du = node2.get("unlocks", [])
		var du_empty: bool = (not (du is Array)) or du.size() == 0
		var de = node2.get("effects", [])
		var de_empty: bool = (not (de is Array)) or de.size() == 0
		var reasons := []
		if actual.size() > 0 and du_empty:
			reasons.append("gates {%s} but unlocks[] is EMPTY" % ", ".join(actual))
		if (tid2 in CODE_BONUS_NODES) and de_empty:
			reasons.append("grants a coded stat bonus but effects[] is EMPTY")
		if reasons.size() > 0:
			tooltip_gaps.append({"id": tid2, "name": str(node2.get("name", tid2)),
				"tier": int(node2.get("tier", 0)), "reasons": reasons})

	print("[RA] tech nodes: %d | functional: %d | dead-ish: %d" % [
		tt.size(), functional, dead.size() + pure_bridge.size() + mission_only.size() + bridge_and_mission.size()])
	_print_group("TRULY DEAD  (grants nothing, gates nothing, no bridge, no mission) -> SAFE PEEL", dead)
	_print_group("PURE BRIDGE (grants nothing; ONLY gates other research) -> COLLAPSE + REPARENT", pure_bridge)
	_print_group("MISSION-ONLY (grants/gates nothing; a mission points at it) -> peel needs mission retarget", mission_only)
	_print_group("BRIDGE + MISSION (grants nothing; bridges AND mission target)", bridge_and_mission)
	print("[RA] ===== HIDDEN CONTRIBUTION (functional but EMPTY tooltip -> SURFACE, don't peel) : %d =====" % hidden.size())
	for h in hidden:
		print("[RA]   T%d  %-24s  %-26s  does: %s" % [h["tier"], h["id"], h["name"], h["why"]])
	print("[RA] ===== TOOLTIP GAPS (functional, but tooltip under-reports) -> POPULATE unlocks/effects : %d =====" % tooltip_gaps.size())
	for g in tooltip_gaps:
		print("[RA]   T%d  %-24s  %s" % [g["tier"], g["id"], g["name"]])
		for rr in g["reasons"]:
			print("[RA]        - %s" % rr)
	_print_collapse_plan(tt, children, mtargets)
	print("[RA] done")
	get_tree().quit(0)

# Exact collapse map for the 5 nodes being removed: resolve each one's surviving
# ancestor (skip nodes also being removed) — that's the reconnect target for its
# children AND the content it gates — plus list its missions.
const COLLAPSE := ["industrial_logistics", "nano_fabrication", "automated_logistics", "laser_cutters", "catalytic_electrodes"]

func _survivor(tt, tid: String) -> String:
	var cur: String = str(tt[tid].get("parent", ""))
	while cur != "" and cur != "null" and (cur in COLLAPSE):
		if not tt.has(cur):
			break
		cur = str(tt[cur].get("parent", ""))
	return cur

func _print_collapse_plan(tt, children, mtargets) -> void:
	print("[RA] ===== COLLAPSE PLAN (remove these 5, reconnect to survivor) =====")
	for tid in COLLAPSE:
		if not tt.has(tid):
			print("[RA]   %s : NOT IN TREE" % tid)
			continue
		var surv: String = _survivor(tt, tid)
		print("[RA]   -- %s (parent=%s) -> RECONNECT TARGET: %s" % [tid, str(tt[tid].get("parent","")), surv])
		print("[RA]        children to reparent -> %s : %s" % [surv, str(children.get(tid, []))])
		print("[RA]        content to re-gate  -> %s : %s" % [surv, str(gate_names.get(tid, []))])
		print("[RA]        missions to retarget: %s" % [str(mtargets.get(tid, []))])

func _why(code: bool, literal: bool, latemod: bool, bridge: bool, mission: bool) -> String:
	var parts := []
	if code: parts.append("get_efficiency_bonus code stat")
	if literal: parts.append("is_tech_unlocked feature-gate")
	if latemod: parts.append("module cost-scaling gate")
	if bridge: parts.append("bridges other research")
	if mission: parts.append("mission target")
	return ", ".join(parts) if parts.size() > 0 else "?"

func _print_group(title: String, rows: Array) -> void:
	print("[RA] ===== %s : %d =====" % [title, rows.size()])
	for r in rows:
		var extra := ""
		if r["children"].size() > 0:
			extra += "  children=%s" % [r["children"]]
		if r["missions"].size() > 0:
			extra += "  MISSIONS=%s" % [r["missions"]]
		var ud = r["unlocks_disp"]
		if ud is Array and ud.size() > 0:
			extra += "  unlocks_disp=%s" % [ud]
		print("[RA]   T%d  %-26s  %-28s (%s, cost %s)%s" % [
			r["tier"], r["id"], r["name"], r["type"], str(r["cost"]), extra])
