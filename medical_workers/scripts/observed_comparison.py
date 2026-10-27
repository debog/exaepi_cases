#!/usr/bin/env python3
"""Model quantities compared with reported observations (reviewer comment R1.3), from the LC mirror.

Per scenario: in-hospital mortality (deaths per admission; every death in the model occurs in
hospital), ensemble mean and population sigma over realizations, and the ratio of the ensemble
totals; the share of deaths caused by overload (real-bed minus ample-bed deaths, paired by seed,
over the real-bed deaths); and the unavailable fraction of the medical workforce on each
hospital_data snapshot day (regional, and median and 90th percentile over hospitals).
Usage: observed_comparison.py [mirror_dir]
"""
import glob
import os
import sys

import numpy as np

MIR = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    '~/Runs/remote/ExaEpi_LC/medical_workers/revision')
MORTALITY = ('verify_ample_mit', 'H1_mitigated', 'H3_hcw', 'verify_ample', 'H1_capacity')
OVERLOAD = (('mitigated', 'verify_ample_mit', 'H1_mitigated'), ('unmitigated', 'verify_ample', 'H1_capacity'))
ABSENCE = ('H1_mitigated', 'H3_hcw', 'H1_capacity')
DAYS = (45, 60, 75, 90)


def runs(case):
    return sorted(glob.glob(f'{MIR}/.ensemble_bay_{case}_matrix/run_*'))


def deaths_admissions(case):
    out = {}
    for r in runs(case):
        f = os.path.join(r, 'output.dat')
        if os.path.exists(f):
            with open(f) as fh:
                hdr = fh.readline().split()
            a = np.loadtxt(f, skiprows=1, ndmin=2)
            out[int(r[-3:])] = (a[-1, hdr.index('D')], a[:, hdr.index('NewH')].sum())
    return out


def unavailable(case):
    import yt
    yt.set_log_level(50)
    res = {}
    for r in runs(case):
        for t in DAYS:
            hd = f'{r}/hospital_data_{t:05d}'
            if not os.path.isdir(hd):
                continue
            d = yt.load(hd)
            g = d.covering_grid(level=0, left_edge=d.domain_left_edge, dims=d.domain_dimensions)
            a = np.asarray(g['boxlib', 'num_available_frontline_medworkers']).ravel()
            b = np.asarray(g['boxlib', 'baseline_frontline_medworkers']).ravel()
            k = b > 0
            u = 1 - a[k] / b[k]
            res.setdefault(t, []).append((1 - a[k].sum() / b[k].sum(), np.median(u), np.percentile(u, 90)))
    return res


def main():
    print('--- in-hospital mortality (deaths per admission)')
    for case in MORTALITY:
        v = np.array(list(deaths_admissions(case).values()))
        r = v[:, 0] / v[:, 1]
        print(f'  {case:<18} n={len(v):<2} mean {100 * r.mean():5.2f}% sigma {100 * r.std():.2f}%  '
              f'totals {100 * v[:, 0].sum() / v[:, 1].sum():5.2f}%  '
              f'(deaths {v[:, 0].mean():.0f}, admissions {v[:, 1].mean():.0f})')
    print('--- share of deaths caused by overload (paired by seed)')
    for lab, ample, real in OVERLOAD:
        A, B = deaths_admissions(ample), deaths_admissions(real)
        s = sorted(set(A) & set(B))
        x = np.array([B[k][0] - A[k][0] for k in s])
        print(f'  {lab:<12} n={len(s)} excess {x.mean():.0f} of {np.mean([B[k][0] for k in s]):.0f} deaths: '
              f'{100 * x.mean() / np.mean([B[k][0] for k in s]):.1f}%')
    print('--- unavailable fraction of the medical workforce (ensemble mean over realizations)')
    for case in ABSENCE:
        res = unavailable(case)
        for t in sorted(res):
            x = np.array(res[t])
            print(f'  {case:<14} day {t:3d} n={len(x):2d} regional {100 * x[:, 0].mean():4.1f}% '
                  f'(sigma {100 * x[:, 0].std():.1f})  hospital median {100 * x[:, 1].mean():4.1f}%  '
                  f'90th percentile {100 * x[:, 2].mean():4.1f}%')


if __name__ == '__main__':
    main()
