#!/usr/bin/env python3
"""
Calibrate the capacity-limited treatment-quality response of the ExaEpi
medical-worker / hospital-capacity model.

Goal: pick hospital_model.halfscore_load (and score_minimum) so that, at a
realistic peak hospital load, the overall in-hospital mortality is a target
multiple of the unstrained baseline -- the ~2x at peak strain reported in
caseload-surge studies (Kadri 2021, Bravata 2021).

Model (src/HospitalModel.H):
  score(load) = 1                                                  load <= 1
              = 1 - (1-floor)*e^(load-1)/(e^half + e^(load-1))      load > 1
  Each hospital day the agent's treatment-quality multiplier q is updated by the
  community's daily score, in one of two modes
  (hospital_model.treatment_score_type):
      minimum     q = min(daily scores)        -- the worst day of the stay
      cumulative  q = product(daily scores)     -- compounds each day
  Death at end of stay:  p_death = 1 - q*(1 - p_death_baseline).

For the MINIMUM model p_death is linear in the baseline, so the *overall*
mortality multiplier depends only on the overall baseline b and the score at the
worst (peak-load) day:
      M(L) = [1 - score(L)*(1 - b)] / b
We invert this for halfscore_load at the target load. The CUMULATIVE model is
shown only for contrast -- it raises q to the stay-length power and is far more
aggressive at the same parameters.

Baseline parameters below match medical_workers/inputs/make_inputs.sh; the
admission age mix and baseline b match the ample-bed verification run
(20456 deaths / 185697 admissions = 0.110).
"""

import argparse
import math

# ---- baseline in-hospital outcome parameters (match inputs/make_inputs.sh) ----
# age groups:  U5, 5-17, 18-29, 30-49, 50-64, 65+
CIC      = [0.24, 0.24, 0.24, 0.36, 0.36, 0.35]              # P(ICU | hospitalized)
CVE      = [0.12, 0.12, 0.12, 0.22, 0.22, 0.22]              # P(ventilator | ICU)
HOSP_CVF = [0.0024, 0.0024, 0.0095, 0.0188, 0.0409, 0.1497]  # ward death prob
ICU_CVF  = [0.0047, 0.0047, 0.0189, 0.0375, 0.0817, 0.2994]  # ICU (non-vent) death prob
VENT_CVF = [0.0071, 0.0071, 0.0284, 0.0563, 0.1226, 0.4490]  # ventilator death prob

# age mix of hospital admissions: sum of the Hosp* columns over the ample-bed
# verification run (output_mean.dat). Used only to weight the per-age baseline.
HOSP_FRAC = [0.0393, 0.0593, 0.1343, 0.1100, 0.2300, 0.4271]

# representative stay length (days) per tier, for the cumulative-model contrast only
STAY = {"ward": 4.0, "icu": 8.0, "vent": 11.0}


def baseline_pdeath(a):
    return ((1 - CIC[a]) * HOSP_CVF[a]
            + CIC[a] * (1 - CVE[a]) * ICU_CVF[a]
            + CIC[a] * CVE[a] * VENT_CVF[a])


def overall_baseline():
    return sum(HOSP_FRAC[a] * baseline_pdeath(a) for a in range(6))


def score(load, floor, half):
    if load <= 1.0:
        return 1.0
    x = load - 1.0
    return 1.0 - (1.0 - floor) * math.exp(x) / (math.exp(half) + math.exp(x))


def mult_min(load, floor, half, b):
    """Overall in-hospital mortality multiplier, minimum-score model."""
    s = score(load, floor, half)
    return (1.0 - s * (1.0 - b)) / b


def mult_cumulative(load, floor, half, b):
    """Overall multiplier, cumulative (compounding) model -- contrast only."""
    s = score(load, floor, half)
    num = 0.0
    for a in range(6):
        qw, qi, qv = s ** STAY["ward"], s ** STAY["icu"], s ** STAY["vent"]
        pw = (1 - CIC[a]) * (1 - qw * (1 - HOSP_CVF[a]))
        pi = CIC[a] * (1 - CVE[a]) * (1 - qi * (1 - ICU_CVF[a]))
        pv = CIC[a] * CVE[a] * (1 - qv * (1 - VENT_CVF[a]))
        num += HOSP_FRAC[a] * (pw + pi + pv)
    return num / b


def solve_half(load_target, mult_target, floor, b):
    """halfscore_load so the minimum-score multiplier hits mult_target at load_target."""
    s_req = (1.0 - mult_target * b) / (1.0 - b)   # required peak-day score
    if not (0.0 < s_req < 1.0):
        raise SystemExit("target multiplier {} not reachable for baseline b={:.4f} "
                         "(needs 1 < M < {:.2f})".format(mult_target, b, 1.0 / b))
    lo, hi = 0.01, 25.0                            # score increases with half
    for _ in range(300):
        mid = 0.5 * (lo + hi)
        if score(load_target, floor, mid) < s_req:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi), s_req


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--load", type=float, default=2.5,
                    help="peak hospital load (x capacity) to calibrate at [2.5]")
    ap.add_argument("--mult", type=float, default=2.0,
                    help="target overall mortality multiplier at that load [2.0]")
    ap.add_argument("--floor", type=float, default=0.1,
                    help="score_minimum (floor at very high load) [0.1]")
    args = ap.parse_args()

    b = overall_baseline()
    half, s_req = solve_half(args.load, args.mult, args.floor, b)

    print("Overall unstrained in-hospital mortality (baseline)  b = {:.4f}".format(b))
    print("Per-age baseline P(death|hosp): " +
          " ".join("{:.3f}".format(baseline_pdeath(a)) for a in range(6)))
    print()
    print("Target: M = {:.2f}x  at load = {:.2f}x   (minimum-score model)".format(
        args.mult, args.load))
    print("  required peak-day score      = {:.4f}".format(s_req))
    print("  => hospital_model.score_minimum   = {:.3f}".format(args.floor))
    print("     hospital_model.halfscore_load  = {:.3f}".format(half))
    print("     hospital_model.treatment_score_type = minimum")
    print("  asymptotic (load->inf) multiplier  = {:.2f}x".format(
        (1.0 - args.floor * (1.0 - b)) / b))
    print()
    hdr = "{:>8} {:>8} {:>12} {:>14}".format("load", "score", "M_minimum", "M_cumulative")
    print(hdr)
    print("-" * len(hdr))
    for load in (1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 5.7, 8.0):
        print("{:>8.1f} {:>8.3f} {:>11.2f}x {:>13.2f}x".format(
            load, score(load, args.floor, half),
            mult_min(load, args.floor, half, b),
            mult_cumulative(load, args.floor, half, b)))
    print()
    print("M_cumulative uses representative stays ward/icu/vent = "
          "{}/{}/{} days; it compounds and is shown only to motivate the switch."
          .format(int(STAY["ward"]), int(STAY["icu"]), int(STAY["vent"])))


if __name__ == "__main__":
    main()
