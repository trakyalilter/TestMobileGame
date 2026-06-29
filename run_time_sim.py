#!/usr/bin/env python3
"""
Income-rate sim for Horizon Idle — estimates time to clear each zone (Z1->Z10).

Reads exact game constants from income_data.json (produced by income_probe.gd):
per-zone research-gate credits, module credits, expanded raw demand, avg
credits/kill, and global gather/infra/warp constants. Applies an explicit,
tunable income + policy model on top.

KEY MODELLED MECHANICS (grounded in code):
- offline_combat = False  -> combat credits are ACTIVE-ONLY.
- Materials (gather + infrastructure) accrue 24/7 (no global offline cap yet).
- Single active task: active time is SPLIT between combat (credits) and
  gather (material deficit after free background infra).
- Warp multipliers: combat (1+shards*0.03)*2^tier ; production (1+shards*0.02)*2^tier.

Tune the PARAMS block and re-run. v1 tracks the explicit credit GATES
(research + modules) + material feasibility; it does NOT yet price in building
credit costs or combat-power gating, so it is a LOWER BOUND on late-game time.
"""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
D = json.load(open(os.path.join(HERE, "income_data.json")))
Z = D["zones"]

# ----------------------------- TUNABLE PARAMS -----------------------------
KILLS_PER_HOUR        = 180     # on-tier auto-combat throughput (incl. encounter overhead)
ACTIVE_HOURS_PER_DAY  = 3.0     # engaged play per real day
BG_CREDIT_FRAC        = 0.35    # bounty + quests + selling surplus, on top of combat credits
PRODUCE_WINDOW_HOURS  = 48.0    # target: background infra produces a zone's raw within this window
                                #   (sets how much building capacity, hence credits, you invest)

INFRA_ONE_EACH = D["infra_units_per_hour_one_each"]            # raw/hr if 1 of every building
COST_PER_RAW_HR = D["total_building_credit_cost"] / INFRA_ONE_EACH  # credits per (raw/hr) of capacity
# --------------------------------------------------------------------------


def fmt_hours(h):
    if h < 1:   return f"{h*60:.0f} min"
    if h < 48:  return f"{h:.1f} hr"
    return f"{h/24:.1f} days"


def scenario(shards, tier, label):
    combat_mult = (1.0 + shards * D["warp"]["combat_per_shard"])     * (2.0 ** tier)
    prod_mult   = (1.0 + shards * D["warp"]["production_per_shard"]) * (2.0 ** tier)

    print(f"\n=== {label}  (shards={shards}, tier={tier} -> combat x{combat_mult:.2f}, prod x{prod_mult:.2f}) ===")
    print(f"{'Z':>2} {'gate+mod_cr':>13} {'infra_cr':>12} {'cr/hr(act)':>13} "
          f"{'active_hrs':>10} {'calendar':>10} {'cumul_act':>10} {'cumul_cal':>10}")

    best_crpk = 0.0           # best credits/kill among CLEARED zones
    peak_rate = 0.0           # running-max infra capacity already built (raw/hr, pre-mult)
    cum_act = 0.0
    cum_cal_days = 0.0
    for z in range(1, 11):
        x = Z[str(z)]
        gate_mod = x["gate_credits"] + x["module_credits"]

        # cumulative infra: only pay for INCREMENTAL capacity when peak raw demand rises.
        # capacity needed (pre-mult) to make this zone's raw within PRODUCE_WINDOW:
        need_rate = x["raw_demand"] / PRODUCE_WINDOW_HOURS / prod_mult
        incr = max(0.0, need_rate - peak_rate)
        peak_rate = max(peak_rate, need_rate)
        infra_cr = incr * COST_PER_RAW_HR

        credit_cost = gate_mod + infra_cr

        # income = farm the most lucrative CLEARED zone (1..z-1); z1 = its own start
        income_crpk = best_crpk if z > 1 else (x["credits_per_kill"] or 50.0)
        income_crpk = max(income_crpk, 1.0)
        credit_rate = income_crpk * KILLS_PER_HOUR * combat_mult * (1.0 + BG_CREDIT_FRAC)  # credits / ACTIVE hr
        active_h = credit_cost / credit_rate
        cal_days = active_h / ACTIVE_HOURS_PER_DAY

        cum_act += active_h
        cum_cal_days += cal_days
        print(f"{z:>2} {gate_mod:>13,.0f} {infra_cr:>12,.0f} {credit_rate:>13,.0f} "
              f"{fmt_hours(active_h):>10} {fmt_hours(cal_days*24):>10} "
              f"{cum_act:>8.1f}h {cum_cal_days:>8.1f}d")

        best_crpk = max(best_crpk, x["credits_per_kill"])


def report_inputs():
    print("INPUT CONSTANTS (exact, from game data):")
    print(f"{'Z':>2} {'gate_cr':>12} {'mod_cr':>11} {'raw_demand':>11} {'cr/kill':>10}")
    for z in range(1, 11):
        x = Z[str(z)]
        print(f"{z:>2} {x['gate_credits']:>12,.0f} {x['module_credits']:>11,.0f} "
              f"{x['raw_demand']:>11,.0f} {x['credits_per_kill']:>10,.0f}")
    print(f"\nglobals: infra_one_each={INFRA_ONE_EACH:,.0f} raw/hr  "
          f"building_cost_total={D['total_building_credit_cost']:,.0f}  "
          f"cost_per_raw/hr={COST_PER_RAW_HR:,.0f}  offline_combat={D['offline_combat_default']}")
    print(f"params: KILLS_PER_HOUR={KILLS_PER_HOUR}  ACTIVE_HRS/DAY={ACTIVE_HOURS_PER_DAY}  "
          f"BG_CREDIT_FRAC={BG_CREDIT_FRAC}  PRODUCE_WINDOW={PRODUCE_WINDOW_HOURS}h")


report_inputs()
scenario(shards=0,  tier=0, label="RUN 1 - first climb, no warp bonuses")
scenario(shards=10, tier=1, label="MATURE RUN - ~10 shards, tier 1")
scenario(shards=30, tier=3, label="DEEP RUN - ~30 shards, tier 3")
