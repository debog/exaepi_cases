#!/usr/bin/env python3
"""Paired between-simulation differences in the death toll (reviewer comment R2.5), from the LC mirror.

Realizations with the same seed are paired. For each comparison B - A: the mean difference, its
95% CI (Student t), the population sigma of the per-realization differences, the same in percent
of the mean toll of A (or of a stated reference), and the number of realizations with B > A.
Ratios (multipliers) use 1 + difference / mean(A).
Usage: paired_differences.py [mirror_dir]
"""
import glob
import os
import sys

import numpy as np

import capacity_exponent_sweep as ces
from capacity_exponent_sweep import T95

if len(sys.argv) > 1:
    ces.MIR = sys.argv[1]
D = {}


def deaths(case):
    if case not in D:
        D[case] = ces.final_deaths(case)
    return D[case]


def final_value(case, col, fname):
    out = {}
    for d in sorted(glob.glob(f'{ces.MIR}/.ensemble_bay_{case}_matrix/run_*')):
        f = os.path.join(d, fname)
        if os.path.exists(f):
            with open(f) as fh:
                hdr = fh.readline().split()
            out[int(d[-3:])] = np.loadtxt(f, skiprows=1, ndmin=2)[-1, hdr.index(col)]
    return out


def row(label, a, b, ref=None, ratio=False, col=None, fname=None):
    A, B = (deaths(a), deaths(b)) if col is None else (final_value(a, col, fname), final_value(b, col, fname))
    s = sorted(set(A) & set(B))
    d = np.array([B[k] - A[k] for k in s])
    m, hw = d.mean(), T95.get(len(d) - 1, 1.96) * d.std(ddof=1) / np.sqrt(len(d))
    r = np.mean([A[k] for k in s]) if ref is None else np.mean([deaths(ref)[k] for k in s])
    txt = (f'{label:<44} n={len(d):<2} {np.mean([A[k] for k in s]):>7.0f} -> {np.mean([B[k] for k in s]):>7.0f}  '
           f'diff {m:>7.0f} [{m - hw:.0f}, {m + hw:.0f}] sigma {d.std():>5.0f}  '
           f'{100 * m / r:>+7.2f}% [{100 * (m - hw) / r:+.2f}, {100 * (m + hw) / r:+.2f}] sigma {100 * d.std() / r:.2f}%  '
           f'B>A {np.sum(d > 0)}/{len(d)}')
    if ratio:
        txt += f'  ratio {1 + m / r:.3f} [{1 + (m - hw) / r:.3f}, {1 + (m + hw) / r:.3f}]'
    print(txt)


def main():
    print('--- Sec 5.2 verification (model at ample capacity vs without the model)')
    row('verify: with model vs without', 'verify_off', 'verify_ample')
    print('--- Sec 5.3 capacity burden (real vs ample beds)')
    row('H1 unmitigated: real vs ample beds', 'verify_ample', 'H1_capacity', ratio=True)
    row('H1 mitigated: real vs ample beds', 'verify_ample_mit', 'H1_mitigated', ratio=True)
    row('H1 mitigated: without vs with patient transfer', 'H1_mitigated', 'H1_mitigated_notransfer')
    print('--- Sec 5.4 workforce size')
    row('H2: 13% vs 8% medical workers', 'H2_mw08', 'H2_mw13')
    row('H2: 20% vs 13% medical workers', 'H2_mw13', 'H2_mw20')
    row('H2: 20% vs 8% medical workers', 'H2_mw08', 'H2_mw20')
    print('--- Sec 5.5 in-hospital transmission')
    row('H3: with vs without in-hospital transmission', 'H1_mitigated', 'H3_hcw')
    row('H3: medical-worker deaths', 'H1_mitigated', 'H3_hcw', col='MW_dead', fname='medical_workers.dat')
    print('--- Sec 6.1 S1: multiplier at each M_max, L_1/2 (vs ample mitigated); change vs calibrated')
    for c in ('S1_mmax2', 'S1_mmax4', 'S1_lhalf10', 'S1_lhalf25'):
        row(f'{c}: multiplier', 'verify_ample_mit', c, ratio=True)
        row(f'{c}: change vs calibrated', 'H1_mitigated', c)
    print('--- Sec 6.1 S2: amplification at scaled transmissivities (vs H1_mitigated)')
    for c in ('S2_hcw_lo', 'H3_hcw', 'S2_hcw_hi'):
        row(f'{c}: amplification', 'H1_mitigated', c)
    print('--- Sec 6.1 Table 9 (score forms): multiplier, amplification, change vs logistic')
    for f in ('linear', 'saturating', 'logistic3'):
        row(f'{f}: multiplier', 'verify_ample_mit', f'S5_{f}_mit', ratio=True)
        row(f'{f}: amplification', f'S5_{f}_mit', f'S5_{f}_hcw')
        row(f'{f}: change without in-hospital transmission', 'H1_mitigated', f'S5_{f}_mit')
        row(f'{f}: change with in-hospital transmission', 'H3_hcw', f'S5_{f}_hcw')
    print('--- Sec 6.1 gamma (R1.1)')
    for g in ('05', '08'):
        row(f'gamma 0.{g[1]}: multiplier', 'verify_ample_mit', f'S3_gamma{g}_mit', ratio=True)
        row(f'gamma 0.{g[1]}: amplification', f'S3_gamma{g}_mit', f'S3_gamma{g}_hcw')
        row(f'gamma 0.{g[1]}: change without in-hospital transmission', 'H1_mitigated', f'S3_gamma{g}_mit')
        row(f'gamma 0.{g[1]}: change with in-hospital transmission', 'H3_hcw', f'S3_gamma{g}_hcw')
    print('--- letter R2.1: age split of the 30-64 group')
    for s in ('111', '136'):
        row(f'split {s}: unmitigated', 'H1_capacity', f'S4_split{s}_unmit')
        row(f'split {s}: mitigated', 'H1_mitigated', f'S4_split{s}_mit')


if __name__ == '__main__':
    main()
