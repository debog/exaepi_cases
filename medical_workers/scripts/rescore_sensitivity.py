#!/usr/bin/env python3
"""
S1 sensitivity (Section 4.7): re-score saved H1/H3 runs over the load->mortality map
parameters (M_max, L_1/2) WITHOUT new simulations.

Why this works: with the workforce fixed and no in-hospital transmission (H1, H2),
M_max and L_1/2 enter ONLY the closed-form mortality map -- they do not change the
load trajectory or the admissions. So the strain-attributable excess mortality is a
deterministic functional of the saved per-day load and age-resolved admissions, and
the (M_max, L_1/2) sweep is post-processing.

Per admission cohort of age a on day t:
    g   = max_{d in [t, t+stay_a)} g(L_d)          (minimum-score / worst-day accumulation)
    g(L)= 0                                         if L <= 1
        = (e^{L-1}-1)/((e^{L_half}-1)+(e^{L-1}-1))   otherwise
    p_death = min(1, p_base_a * (1 + (M_max-1) g))
    expected deaths = N_{a,t} * p_death
where p_base_a = effective baseline P(death|hosp) by age, built from the deck CIC/CVE
escalation and hospCVF/icuCVF/ventCVF tier fatalities. The overload multiplier
1 + (M_max-1) g is identical across baseline-risk groups and capped at p_death=1 (so it
does not push low-risk patients toward certain death). The score floor s_min does NOT
enter -- it only normalizes the score field, not the mortality. The strain multiplier
reported is total deaths / baseline deaths (M_max = 1).

Validity (a screen, not a substitute for full runs):
  - Uses the region-aggregate load and a constant nominal capacity, so it sees the
    TEMPORAL strain but not the per-hospital heterogeneity. The patient count is the
    one the model scores: the census of day t-1 plus the admissions of day t.
  - Trust it at high uniform load; anchor the mitigated operating point with the S1_*
    full-run corners (inputs/make_inputs.sh).

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
HOSP_COMPARTMENTS = ['H/NI', 'H/I']                      # in-hospital census (ICU, V are subsets)

# --- grids ----------------------------------------------------------------------
MMAX_GRID = [1.5, 2.0, 2.5, 3.0, 3.5, 4.0]   # overload mortality ceiling; baseline 3.0
LHALF_GRID = [1.0, 1.5, 2.0, 2.5]            # load for half-degradation; baseline 1.5
TARGET_GRID = [1.5, 2.0, 3.0]                # M(2.5) calibration target (Kadri/Bravata)


def degradation(L, L_half):
    """g(L) in [0,1]: 0 at/below capacity, -> 1 as load -> infinity. s_min-independent."""
    L = np.asarray(L, float)
    ex = np.exp(np.clip(L - 1, 0, None)) - 1.0
    eh = np.exp(L_half) - 1.0
    return np.where(L <= 1.0, 0.0, ex / (eh + ex))


def lhalf_from_target(m_max, m_target, L_peak=2.5):
    """Solve L_1/2 so the (risk-independent) multiplier M(L_peak) = m_target."""
    if not (1.0 < m_target < m_max):
        return np.nan
    g_needed = (m_target - 1.0) / (m_max - 1.0)            # required degradation at L_peak
    ex = np.exp(L_peak - 1) - 1.0
    eh = ex * (1.0 - g_needed) / g_needed                  # g = ex/(eh+ex) -> solve eh
    return np.log(eh + 1.0) if eh > 0 else np.nan


def read_run(path):
    with open(path) as f:
        hdr = f.readline().split()
    idx = {n: i for i, n in enumerate(hdr)}
    d = np.loadtxt(path, skiprows=1)
    census = sum(d[:, idx[c]] for c in HOSP_COMPARTMENTS)  # end-of-day in-hospital census
    npat = np.r_[census[0], census[:-1]] + d[:, idx['NewH']]  # patients scored on day t
    adm = np.stack([d[:, idx[c]] for c in AGE_COLS], axis=1)  # (days, 6) admissions
    return npat, adm


def rescore(census, adm, capacity, m_max, L_half):
    """Total in-hospital deaths for one realization at (M_max, L_half)."""
    L = census / capacity
    g = degradation(L, L_half)
    nday = len(g)
    deaths = 0.0
    for a in range(6):
        st = STAY[a]
        for t in range(nday):
            n = adm[t, a]
            if n <= 0:
                continue
            g_acc = g[t:min(t + st, nday)].max()           # worst-day degradation over stay
            p_death = min(1.0, P_BASE[a] * (1.0 + (m_max - 1.0) * g_acc))
            deaths += n * p_death
    return deaths


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('ensemble_dir')
    ap.add_argument('--capacity', type=float, default=10876.0,
                    help='nominal staffed-bed capacity (Bay Area HHS = 10876)')
    ap.add_argument('--target', action='store_true',
                    help='sweep M_max x M(2.5) target instead of M_max x L_1/2')
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
        lhalf_of = {(mm, m): lhalf_from_target(mm, m) for mm in MMAX_GRID for m in TARGET_GRID}
    else:
        cols, col_lab = LHALF_GRID, 'L_1/2'

    print(f'Strain-attributable excess-mortality multiplier  (rows M_max, cols {col_lab}):')
    print('  M_max  ' + ''.join(f'{c:>9}' for c in cols))
    grid = np.zeros((len(MMAX_GRID), len(cols)))
    for i, mm in enumerate(MMAX_GRID):
        row = []
        for j, c in enumerate(cols):
            L_half = lhalf_of[(mm, c)] if args.target else c
            if not np.isfinite(L_half):
                grid[i, j] = np.nan; row.append('     --'); continue
            mult = np.mean([rescore(cs, ad, args.capacity, mm, L_half) /
                            rescore(cs, ad, args.capacity, 1.0, L_half) for cs, ad in data])
            grid[i, j] = mult
            row.append(f'{mult:>8.2f}')
        print(f'  {mm:<5}  ' + ''.join(f'{r:>9}' for r in row))

    # baseline calibrated point cross-check
    base = np.mean([rescore(cs, ad, args.capacity, 3.0, 1.5) /
                    rescore(cs, ad, args.capacity, 1.0, 1.5) for cs, ad in data])
    print(f'\nbaseline (M_max=3.0, L_1/2=1.5): multiplier = {base:.2f}  '
          f'(compare against the full-run value in the paper; the gap is the '
          f'spatial-heterogeneity correction this aggregate re-scoring omits)')

    if args.png:
        import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
        fig, ax = plt.subplots(figsize=(6, 4.5))
        im = ax.imshow(grid, origin='lower', aspect='auto', cmap='YlOrRd')
        ax.set_xticks(range(len(cols))); ax.set_xticklabels(cols)
        ax.set_yticks(range(len(MMAX_GRID))); ax.set_yticklabels(MMAX_GRID)
        ax.set_xlabel(col_lab); ax.set_ylabel('mortality ceiling M_max')
        for i in range(len(MMAX_GRID)):
            for j in range(len(cols)):
                if np.isfinite(grid[i, j]):
                    ax.text(j, i, f'{grid[i,j]:.1f}', ha='center', va='center', fontsize=9)
        fig.colorbar(im, label='excess-mortality multiplier'); fig.tight_layout()
        fig.savefig(args.png, dpi=150); print(f'saved {args.png}')


if __name__ == '__main__':
    main()
