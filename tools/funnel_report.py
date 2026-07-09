#!/usr/bin/env python3
"""funnel_report.py -- aggregate player-bot JSONL runs into a diffable digest.

    python tools/funnel_report.py <dir-with-player_*.jsonl> [--out digest.txt]

The digest answers "did this rebalance break the new-player path": per-mission
funnel table (p50/p90 across seeds, time splits), wall heatmap, milestones,
D1/D3/D7 funnel depth, fight ledger summary, dead time, offline share, and the
REALISM VIOLATION gate (any run with violations > 0 is a sim bug report, not a
balance report -- excluded from aggregates, loudly).
"""
import json
import sys
import glob
import os
from collections import defaultdict


def pct(sorted_vals, p):
    if not sorted_vals:
        return -1
    i = min(len(sorted_vals) - 1, int(round(p / 100.0 * (len(sorted_vals) - 1))))
    return sorted_vals[i]


def hms(s):
    if s < 0:
        return "-"
    return "%d:%02d" % (s // 3600, (s % 3600) // 60)


def load_runs(dirpath):
    runs = []
    for path in sorted(glob.glob(os.path.join(dirpath, "player_*.jsonl"))):
        recs = []
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    recs.append(json.loads(line))
        meta = next((r for r in recs if r["t"] == "meta"), {})
        summ = next((r for r in recs if r["t"] == "summary"), {})
        runs.append({"path": os.path.basename(path), "meta": meta, "summary": summ,
                     "recs": recs})
    return runs


def main():
    dirpath = sys.argv[1] if len(sys.argv) > 1 else "sim_out/players"
    runs = load_runs(dirpath)
    if not runs:
        print("no player_*.jsonl runs found in %s" % dirpath)
        return 1
    out = []
    w = out.append

    # ---- validity gate -------------------------------------------------
    valid, invalid = [], []
    for r in runs:
        if int(r["summary"].get("violations", 0)) > 0:
            invalid.append(r)
        else:
            valid.append(r)
    w("=" * 78)
    w("PLAYER-BOT FUNNEL DIGEST  (%d runs: %d valid, %d EXCLUDED for realism violations)"
      % (len(runs), len(valid), len(invalid)))
    w("=" * 78)
    for r in invalid:
        w("!! EXCLUDED %s: %d REALISM VIOLATIONS -- fix the sim before reading numbers"
          % (r["path"], int(r["summary"].get("violations", 0))))

    by_arch = defaultdict(list)
    for r in valid:
        by_arch[r["meta"].get("archetype", "?")].append(r)

    # ---- summaries -----------------------------------------------------
    w("")
    w("-- RUN SUMMARIES " + "-" * 60)
    for r in valid:
        s = r["summary"]
        w("%-34s %-11s deepest=%-7s claimed=%2d sim=%7s days=%2d walls=%d"
          % (r["path"], s.get("result", "?"), s.get("deepest_mid", "-"),
             int(s.get("claimed", 0)), hms(int(s.get("sim_s", 0))),
             int(s.get("days", 0)), int(s.get("walls", 0))))

    # ---- milestones ----------------------------------------------------
    w("")
    w("-- MILESTONES (median sim time per archetype) " + "-" * 31)
    names = ["first_powered", "first_fight", "kits_equipped", "frigate",
             "first_boss", "destroyer", "chain_end", "first_warp"]
    w("%-12s %s" % ("archetype", " ".join("%10s" % n[:10] for n in names)))
    for arch, rs in sorted(by_arch.items()):
        row = []
        for n in names:
            vals = sorted(int(r["summary"].get("milestones", {}).get(n, -1))
                          for r in rs if n in r["summary"].get("milestones", {}))
            row.append("%10s" % hms(pct(vals, 50)) if vals else "%10s" % "-")
        w("%-12s %s" % (arch, " ".join(row)))

    # ---- per-mission funnel (per archetype) -----------------------------
    for arch, rs in sorted(by_arch.items()):
        per_mid = defaultdict(list)
        for r in rs:
            for rec in r["recs"]:
                if rec["t"] == "mission":
                    per_mid[(int(rec.get("idx", -1)), rec["mid"])].append(rec)
        w("")
        w("-- FUNNEL: %s (%d runs; act->claim p50/p90; splits are p50) %s"
          % (arch, len(rs), "-" * 20))
        w("idx mid       p50      p90      direct  detour  blocked offline")
        for (idx, mid), recs in sorted(per_mid.items()):
            dur = sorted(int(x["t_claim"]) - int(x["t_act"]) for x in recs)
            d50 = pct(sorted(int(x["direct_s"]) for x in recs), 50)
            e50 = pct(sorted(int(x["detour_s"]) for x in recs), 50)
            b50 = pct(sorted(int(x["blocked_s"]) for x in recs), 50)
            o50 = pct(sorted(int(x["offline_s"]) for x in recs), 50)
            w("%3d %-9s %8s %8s %7s %7s %7s %7s"
              % (idx, mid, hms(pct(dur, 50)), hms(pct(dur, 90)),
                 hms(d50), hms(e50), hms(b50), hms(o50)))

    # ---- walls ---------------------------------------------------------
    w("")
    w("-- WALL HEATMAP " + "-" * 61)
    wall_count = defaultdict(int)
    for r in valid:
        for rec in r["recs"]:
            if rec["t"] == "wall":
                wall_count[(rec.get("mid", "?"), rec.get("code", "?"),
                            rec.get("suspect", "?"))] += 1
    if not wall_count:
        w("(none)")
    for (mid, code, suspect), n in sorted(wall_count.items(), key=lambda kv: -kv[1]):
        w("%4dx %-9s %-14s suspect=%s" % (n, mid, code, suspect))

    # ---- funnel depth by day -------------------------------------------
    w("")
    w("-- FUNNEL DEPTH AT DAY CUTS (median deepest claimed idx) " + "-" * 19)
    for arch, rs in sorted(by_arch.items()):
        cuts = {}
        for dcut in (1, 3, 7, 14):
            vals = []
            for r in rs:
                best = -1
                for rec in r["recs"]:
                    if rec["t"] == "mission" and int(rec.get("day", 99)) <= dcut:
                        best = max(best, int(rec.get("idx", -1)))
                vals.append(best)
            cuts[dcut] = pct(sorted(vals), 50)
        w("%-12s D1=%3d  D3=%3d  D7=%3d  D14=%3d"
          % (arch, cuts[1], cuts[3], cuts[7], cuts[14]))

    # ---- fights ----------------------------------------------------------
    w("")
    w("-- BOSS FIGHT LEDGER " + "-" * 56)
    boss = defaultdict(lambda: {"win": 0, "lost": 0, "deaths": 0, "kits": 0, "durs": []})
    for r in valid:
        for rec in r["recs"]:
            if rec["t"] == "fight" and rec.get("boss"):
                b = boss[rec["enemy"]]
                if rec["result"] == "WIN":
                    b["win"] += 1
                    b["durs"].append(int(rec["dur_s"]))
                elif rec["result"] == "LOST":
                    b["lost"] += 1
                b["deaths"] += int(rec.get("deaths", 0))
                b["kits"] += int(rec.get("kits", 0))
    if not boss:
        w("(no boss fights)")
    for eid, b in sorted(boss.items()):
        w("%-24s win=%2d lost=%2d deaths=%2d kits=%2d win-dur p50=%s"
          % (eid, b["win"], b["lost"], b["deaths"], b["kits"],
             hms(pct(sorted(b["durs"]), 50))))

    # ---- dead time + offline -------------------------------------------
    w("")
    w("-- DEAD TIME / OFFLINE " + "-" * 54)
    for arch, rs in sorted(by_arch.items()):
        dead = sum(float(rec.get("s", 0)) for r in rs for rec in r["recs"]
                   if rec["t"] == "dead")
        off_cr = sum(float(rec.get("credits_delta", 0)) for r in rs
                     for rec in r["recs"] if rec["t"] == "offline")
        bored = sum(1 for r in rs for rec in r["recs"]
                    if rec["t"] == "session" and rec.get("end_cause") == "boredom")
        w("%-12s dead=%s total  boredom-exits=%d  offline-credits=%.0f"
          % (arch, hms(int(dead / max(1, len(rs)))), bored, off_cr / max(1, len(rs))))

    text = "\n".join(out)
    print(text)
    for i, a in enumerate(sys.argv):
        if a == "--out" and i + 1 < len(sys.argv):
            with open(sys.argv[i + 1], "w", encoding="utf-8") as f:
                f.write(text + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
