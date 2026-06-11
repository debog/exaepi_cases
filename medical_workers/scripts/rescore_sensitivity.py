#!/usr/bin/env python3
"""
S1 sensitivity (Section 4.7): re-score saved H1/H3 runs over the treatment-quality
parameters (s_min, L_1/2) WITHOUT new simulations.

Why this works: with the workforce fixed and no in-hospital transmission (H1, H2),
s_min and L_1/2 enter ONLY the closed-form mortality map -- they do not change the
load trajectory or the admissions. So the strain-attributable excess mortality is a
deterministic functional of the saved per-day load and age-resolved admissions, and
the (s_min, L_1/2) sweep is post-processing.

Per admission cohort of age a on day t:
    q   = min_{d in [t, t+stay_a)} s(L_d)          (minimum-score accumulation)
    s(L)= 1                                    if L <= 1
        = 1 - (1-s_min)(e^{L-1}-1)/((e^{L_half}-1)+(e^{L-1}-1))   otherwise
    expected deaths = N_{a,t} * [1 - q (1 - p_base_a)]
where p_base_a = effective baseline P(death|hosp) by age, built from the deck
CIC/CVE escalation and hospCVF/icuCVF/ventCVF tier fatalities. The strain multiplier
is total deaths / baseline deaths (q == 1).

Validity (a screen, not a substitute for full runs):
  - Uses the region-aggregate load and a constant nominal capacity, so it sees the
    TEMPORAL strain but not the per-hospital heterogeneity.
  - VALIDATED where the whole region is overloaded: unmitigated H1 gives 6.1x, the
    full-run value. UNDERESTIMATES where the load is spatially concentrated: mitigated
    H1 gives ~1.1x here vs 3.2x in the full runs, because the strain sits in the
    hardest-hit hospitals. So: trust it at high uniform load; anchor the mitigated
    operating point with the S1_* full-run corners (inputs/make_inputs.sh).

Usage:
    rescore_sensitivity.py <ensemble_dir> [--capacity N] [--target] [--png out.png]
    <ensemble_dir> holds run_*/output.dat (e.g. .ensemble_bay_H1_capacity_tuolumne).
"""
import os, sys, glob, argparse
import numpy as np

# --- deck baseline mortality (matches inputs/make_inputs.sh BASE) -----------------
CIC = np.array([0.24, 0.24, 0.24, 0.36, 0.36, 0.35])
CVE = np.array([0.12, 0.12, 0.12, 0.22, 0.22, 0.22])
HOSPCVF = np.array([0.0024, 0.0024, 0.0095, 0.0188, 0.0409, 0.1497])
ICUCVF = np.array([0.0047, 0.0047, 0.0189, 0.0375, 0.0817, 0.2994])
VENTCVF = np.array([0.0071, 0.0071, 0.0284, 0.0563, 0.1226, 0.4490])
STAY = np.array([3, 3, 3, 3, 8, 7])                       # hospitalization_days
P_BASE = (1 - CIC) * HOSPCVF + CIC * (1 - CVE) * ICUCVF + CIC * CVE * VENTCVF
AGE_COLS = ['HospU5', 'Hosp5to17', 'Hosp18to29', 'Hosp30to49', 'Hosp50to64', 'HospO64']
HOSP_COMPARTMENTS = ['H/NI', 'H/I', 'ICU', 'V']          # in-hospital census = sum

# --- grids ----------------------------------------------------------------------
SMIN_GRID = [0.0, 0.1, 0.2, 0.3]
LHALF_GRID = [2.0, 3.13, 4.0, 6.0]
TARGET_GRID = [1.5, 2.0, 3.0]      # M(2.5) calibration target (Kadri/Bravata CI)
PBAR = 0.11                        # admission-weighted baseline in-hospital mortality


def score(L, s_min, L_half):
    L = np.asarray(L, float)
    ex = np.exp(np.clip(L - 1, 0, None)) - 1.0
    eh = np.exp(L_half) - 1.0
    return np.where(L <= 1.0, 1.0, 1.0 - (1 - s_min) * ex / (eh + ex))


def lhalf_from_target(s_min, m_target, L_peak=2.5):
    """Solve L_1/2 so the population multiplier M(L_peak) = m_target (Eq. 7)."""
    s_needed = (1 - m_target * PBAR) / (1 - PBAR)          # required score at L_peak
    if not (s_min < s_needed < 1):
        return np.nan
    ex = np.exp(L_peak - 1) - 1.0
    # s = 1 - (1-s_min) ex/((e^{Lhalf}-1)+ex)  ->  solve e^{Lhalf}
    frac = (1 - s_needed) / (1 - s_min)
    eh = ex * (1 - frac) / frac
    return np.log(eh + 1.0) if eh > 0 else np.nan


def read_run(path):
    with open(path) as f:
        hdr = f.readline().split()
    idx = {n: i for i, n in enumerate(hdr)}
    d = np.loadtxt(path, skiprows=1)
    census = sum(d[:, idx[c]] for c in HOSP_COMPARTMENTS)  # in-hospital patients/day
    adm = np.stack([d[:, idx[c]] for c in AGE_COLS], axis=1)  # (days, 6) admissions
    return census, adm


def rescore(census, adm, capacity, s_min, L_half):
    """Total in-hospital deaths for one realization at (s_min, L_half)."""
    L = census / capacity
    s = score(L, s_min, L_half)
    nday = len(s)
    deaths = 0.0
    for a in range(6):
        st = STAY[a]
        for t in range(nday):
            n = adm[t, a]
            if n <= 0:
                continue
            q = s[t:min(t + st, nday)].min()
            deaths += n * (1 - q * (1 - P_BASE[a]))
    return deaths


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('ensemble_dir')
    ap.add_argument('--capacity', type=float, default=10876.0,
                    help='nominal staffed-bed capacity (Bay Area HHS = 10876)')
    ap.add_argument('--target', action='store_true',
                    help='sweep s_min x M(2.5) target instead of s_min x L_1/2')
    ap.add_argument('--png', default=None)
    args = ap.parse_args()

    runs = sorted(glob.glob(os.path.join(args.ensemble_dir, 'run_*', 'output.dat')))
    if not runs:
        runs = sorted(glob.glob(os.path.join(args.ensemble_dir, 'output.dat')))
    if not runs:
        sys.exit(f'no output.dat under {args.ensemble_dir}')
    data = [read_run(p) for p in runs]
    peak = np.mean([(c / args.capacity).max() for c, _ in data])
    print(f'{len(runs)} realizations; mean peak load {peak:.1f}x capacity '
          f'(capacity={args.capacity:.0f})\n')

    if args.target:
        cols, col_lab = TARGET_GRID, 'M(2.5) target'
        lhalf_of = {(sm, m): lhalf_from_target(sm, m) for sm in SMIN_GRID for m in TARGET_GRID}
    else:
        cols, col_lab = LHALF_GRID, 'L_1/2'

    print(f'Strain-attributable excess-mortality multiplier  (rows s_min, cols {col_lab}):')
    print('  s_min  ' + ''.join(f'{c:>9}' for c in cols))
    grid = np.zeros((len(SMIN_GRID), len(cols)))
    for i, sm in enumerate(SMIN_GRID):
        row = []
        for j, c in enumerate(cols):
            L_half = lhalf_of[(sm, c)] if args.target else c
            if not np.isfinite(L_half):
                grid[i, j] = np.nan; row.append('     --'); continue
            mult = np.mean([rescore(cs, ad, args.capacity, sm, L_half) /
                            rescore(cs, ad, args.capacity, 1.0, L_half) for cs, ad in data])
            grid[i, j] = mult
            row.append(f'{mult:>8.2f}')
        print(f'  {sm:<5}  ' + ''.join(f'{r:>9}' for r in row))

    # baseline calibrated point cross-check
    base = np.mean([rescore(cs, ad, args.capacity, 0.1, 3.13) /
                    rescore(cs, ad, args.capacity, 1.0, 3.13) for cs, ad in data])
    print(f'\nbaseline (s_min=0.1, L_1/2=3.13): multiplier = {base:.2f}  '
          f'(compare against the full-run value in the paper; the gap is the '
          f'spatial-heterogeneity correction this aggregate re-scoring omits)')

    if args.png:
        import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
        fig, ax = plt.subplots(figsize=(6, 4.5))
        im = ax.imshow(grid, origin='lower', aspect='auto', cmap='YlOrRd')
        ax.set_xticks(range(len(cols))); ax.set_xticklabels(cols)
        ax.set_yticks(range(len(SMIN_GRID))); ax.set_yticklabels(SMIN_GRID)
        ax.set_xlabel(col_lab); ax.set_ylabel('score floor s_min')
        for i in range(len(SMIN_GRID)):
            for j in range(len(cols)):
                if np.isfinite(grid[i, j]):
                    ax.text(j, i, f'{grid[i,j]:.1f}', ha='center', va='center', fontsize=9)
        fig.colorbar(im, label='excess-mortality multiplier'); fig.tight_layout()
        fig.savefig(args.png, dpi=150); print(f'saved {args.png}')


if __name__ == '__main__':
    main()
