#!/usr/bin/env python3
"""
Aggregate balance-sim telemetry (JSONL) across runs into a progression-pacing
report. Reads every *.jsonl in a directory, pulls the `summary` record from
each, groups by archetype, and reports median + p10/p90 (never single runs —
combat/loot RNG makes a single run noisy).

Usage:
  python analyze.py [dir]
Default dir: %APPDATA%/Godot/app_userdata/horizonidle/sim_out  (Windows)
"""
import json, os, sys, glob, statistics

def default_dir():
    appdata = os.environ.get("APPDATA", "")
    return os.path.join(appdata, "Godot", "app_userdata", "horizonidle", "sim_out")

def pct(vals, p):
    if not vals:
        return None
    s = sorted(vals)
    if len(s) == 1:
        return s[0]
    k = (len(s) - 1) * p
    lo = int(k)
    hi = min(lo + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (k - lo)

def hrs(sec):
    return None if sec is None else round(sec / 3600.0, 1)

def fmt(sec):
    if sec is None:
        return "  never"
    h = sec / 3600.0
    if h < 48:
        return f"{h:6.1f}h"
    return f"{h/24:6.1f}d"

def band(vals):
    """median (p10–p90) formatted in hours/days."""
    if not vals:
        return "n=0"
    med = pct(vals, 0.5)
    lo = pct(vals, 0.1)
    hi = pct(vals, 0.9)
    return f"{fmt(med)}  ({fmt(lo)} - {fmt(hi)})  n={len(vals)}"

def main():
    d = sys.argv[1] if len(sys.argv) > 1 else default_dir()
    # Recursive: a run in any sub-batch folder still rolls into one report.
    files = glob.glob(os.path.join(d, "**", "*.jsonl"), recursive=True)
    if not files:
        print(f"No .jsonl files in {d}")
        return

    by_arch = {}
    for f in files:
        summary = None
        with open(f, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if rec.get("t") == "summary":
                    summary = rec
        if summary:
            by_arch.setdefault(summary["archetype"], []).append(summary)

    print(f"\n=== Balance-Sim Progression Report ===  ({d})")
    milestones = ["10", "25", "50", "75", "100"]
    for arch in sorted(by_arch):
        runs = by_arch[arch]
        days = runs[0].get("days", "?")
        print(f"\n### {arch.upper()}  ({len(runs)} runs, {days}-day horizon)")

        for skill in ("gathering", "processing"):
            print(f"  time-to-milestone [{skill}]:")
            for m in milestones:
                vals = [r["ttm"].get(skill, {}).get(m) for r in runs]
                vals = [v for v in vals if v is not None]
                print(f"     L{m:<3} {band(vals)}")

        warp_vals = [r.get("time_to_first_warp") for r in runs]
        warp_vals = [v for v in warp_vals if v is not None]
        print(f"  time-to-first-warp:  {band(warp_vals)}")

        tw = [r.get("total_warps", 0) for r in runs]
        rc = [r.get("research_count", 0) for r in runs]
        bd = [r.get("buildings", 0) for r in runs]
        gl = [r.get("final_g_lvl", 0) for r in runs]
        pl = [r.get("final_p_lvl", 0) for r in runs]
        lc = [r.get("final_lifetime_credits", 0) for r in runs]
        print(f"  totals (median): warps={pct(tw,0.5)}  research={pct(rc,0.5)}  "
              f"buildings={pct(bd,0.5)}  g_lvl={pct(gl,0.5)}  p_lvl={pct(pl,0.5)}  "
              f"lifetime_cr={pct(lc,0.5):,.0f}")

        # combat metrics (only meaningful for the combat archetype)
        ck = [r.get("combat_kills", 0) for r in runs]
        hz = [r.get("highest_zone_diff", 0) for r in runs]
        cl = [r.get("final_c_lvl", 1) for r in runs]
        if any(k > 0 for k in ck):
            print(f"  combat (median): kills={pct(ck,0.5)}  highest_zone={pct(hz,0.5)}  c_lvl={pct(cl,0.5)}")

        # ---- automated flags ----
        flags = []
        if all(p <= 1 for p in pl):
            flags.append("PROCESSING never leveled - dominated choice for this archetype")
        if all(b == 0 for b in bd):
            flags.append("BUILDINGS never bought - warp lever unused")
        if warp_vals and pct(warp_vals, 0.5) is not None and pct(warp_vals, 0.5) < 3600 * 6:
            flags.append("FIRST WARP < 6h median - may be too fast vs 'first warp at hours' intent")
        gl_max = max(gl) if gl else 0
        if gl_max > 100:
            flags.append("SKILL CAP BREACH - gathering reached L%d (cap is 100)" % gl_max)
        if any(k > 0 for k in ck) and all(z <= 1 for z in hz):
            flags.append("COMBAT stuck in Zone 1 - basic loadout can't clear the boss for a core -> zone_2_access")
        if arch == "combat" and pct(lc, 0.5) is not None and pct(lc, 0.5) < 5_000_000:
            flags.append("COMBAT credit rate << gather-sell (no offline combat + ammo logistics eat active sessions)")
        for fl in flags:
            print(f"  [!] {fl}")

    print()

if __name__ == "__main__":
    main()
