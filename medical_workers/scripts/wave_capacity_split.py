#!/usr/bin/env python3
"""Wave/capacity split of the mortality amplification (reviewer comment R2.3), from the LC mirror.

The excess deaths with in-hospital transmission, E1 = H3_hcw - H1_mitigated, combine a larger,
earlier wave and the capacity lost to absent workers. With the capacity fixed at the bed supply
(gamma = 0, S6), absence does not lower capacity, so E0 = S6_gamma0_hcw - S6_gamma0_mit is the
wave alone and E1 - E0 is the capacity lost to absence. Both are given in deaths and in
percentage points of the H1_mitigated death toll, so that they add up to the 22%. Paired
statistics use realizations with the same seed.
Usage: wave_capacity_split.py [mirror_dir]
"""
import glob
import os
import sys

import numpy as np

import capacity_exponent_sweep as ces
from capacity_exponent_sweep import T95

MIR = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    '~/Runs/remote/ExaEpi_LC/medical_workers/revision')
CASES = {'mit g=1': 'H1_mitigated', 'hcw g=1': 'H3_hcw',
         'mit g=0': 'S6_gamma0_mit', 'hcw g=0': 'S6_gamma0_hcw'}


def totals(case):
    """Per seed: final deaths, admissions (sum of NewH), and peak patient count."""
    out = {}
    for d in sorted(glob.glob(f'{MIR}/.ensemble_bay_{case}_matrix/run_*')):
        f = os.path.join(d, 'output.dat')
        if not os.path.exists(f):
            continue
        with open(f) as fh:
            hdr = fh.readline().split()
        a = np.loadtxt(f, skiprows=1, ndmin=2)
        patients = sum(a[:, hdr.index(c)] for c in ('H/NI', 'H/I', 'ICU', 'V'))
        out[int(d[-3:])] = (a[-1, hdr.index('D')], a[:, hdr.index('NewH')].sum(), patients.max())
    return out


def ci(x):
    return x.mean(), T95.get(len(x) - 1, 1.96) * x.std(ddof=1) / np.sqrt(len(x))


def main():
    ces.MIR = MIR
    T = {k: totals(c) for k, c in CASES.items()}
    seeds = sorted(set.intersection(*(set(v) for v in T.values())))
    print('case      n   deaths          admissions   deaths/adm  peak patients')
    for k, v in T.items():
        if not v:
            print(f'{k:<8}   0   missing ({CASES[k]})')
            continue
        x = np.array(list(v.values()))
        print(f'{k:<8} {len(x):>3} {x[:, 0].mean():>7.0f} ± {x[:, 0].std(ddof=1):>4.0f} '
              f'{x[:, 1].mean():>10.0f} {x[:, 0].sum() / x[:, 1].sum():>11.4f} {x[:, 2].mean():>10.0f}')
    if len(seeds) < 2:
        print(f'only {len(seeds)} common seeds; no split')
        return
    D = {k: np.array([T[k][s][0] for s in seeds]) for k in T}
    ref = D['mit g=1'].mean()
    parts = {'E1 total (g=1)': D['hcw g=1'] - D['mit g=1'],
             'E0 wave (g=0)': D['hcw g=0'] - D['mit g=0'],
             'E1-E0 capacity': (D['hcw g=1'] - D['mit g=1']) - (D['hcw g=0'] - D['mit g=0'])}
    print(f'\nsplit over {len(seeds)} common seeds; pp = percent of the H1_mitigated toll ({ref:.0f})')
    for lab, x in parts.items():
        m, hw = ci(x)
        print(f'  {lab:<15} {m:>6.0f} [{m - hw:.0f}, {m + hw:.0f}] deaths  '
              f'{100 * m / ref:>5.1f} pp [{100 * (m - hw) / ref:.1f}, {100 * (m + hw) / ref:.1f}]')
    m0, hw0 = ci(parts['E0 wave (g=0)'])
    r0 = D['mit g=0'].mean()
    print(f'  amplification at g=0 (over its own toll {r0:.0f}): {100 * m0 / r0:.1f}% '
          f'[{100 * (m0 - hw0) / r0:.1f}, {100 * (m0 + hw0) / r0:.1f}]')
    print(f'  capacity share of E1: {100 * parts["E1-E0 capacity"].mean() / parts["E1 total (g=1)"].mean():.0f}%')
    print('\ndeaths from absence-reduced capacity in each setting (g=1 minus g=0):')
    for k in ('mit', 'hcw'):
        m, hw = ci(D[f'{k} g=1'] - D[f'{k} g=0'])
        print(f'  {k}: {m:.0f} [{m - hw:.0f}, {m + hw:.0f}] ({100 * m / D[f"{k} g=1"].mean():.1f}% of its g=1 toll)')
    print('\nadmissions and deaths per admission, hcw over mit (ratio of ensemble totals):')
    for g in ('1', '0'):
        a = np.array([T[f'mit g={g}'][s] for s in seeds])
        b = np.array([T[f'hcw g={g}'][s] for s in seeds])
        rd, ra = b[:, 0].sum() / a[:, 0].sum(), b[:, 1].sum() / a[:, 1].sum()
        print(f'  g={g}: deaths x{rd:.4f}, admissions x{ra:.4f}, deaths/admission x{rd / ra:.4f}; '
              f'admissions share of log increase {np.log(ra) / np.log(rd):.2f}; '
              f'peak patients x{b[:, 2].mean() / a[:, 2].mean():.3f}')


if __name__ == '__main__':
    main()
