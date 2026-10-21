#!/usr/bin/env python3
"""Capacity-exponent sweep (reviewer comment R1.1): deaths, excess-mortality multiplier, and
depletion-driven amplification at gamma = 0.5, 0.8, 1, from the LC mirror of the ensembles.

  multiplier    = mean deaths (mitigated, no in-hospital transmission) / ample-bed mitigated deaths
  amplification = deaths with in-hospital transmission / deaths without, minus 1 (same gamma)

Paired statistics use realizations with the same seed. gamma = 1 is H1_mitigated / H3_hcw.
Usage: capacity_exponent_sweep.py [mirror_dir]
"""
import glob
import os
import sys

import numpy as np

MIR = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    '~/Runs/remote/ExaEpi_LC/medical_workers/revision')
CASES = {1.0: ('H1_mitigated', 'H3_hcw'),
         0.8: ('S3_gamma08_mit', 'S3_gamma08_hcw'),
         0.5: ('S3_gamma05_mit', 'S3_gamma05_hcw')}
T95 = {24: 2.064}  # two-sided Student t, 24 degrees of freedom


def final_deaths(case):
    out = {}
    for d in sorted(glob.glob(f'{MIR}/.ensemble_bay_{case}_matrix/run_*')):
        f = os.path.join(d, 'output.dat')
        if not os.path.exists(f):
            continue
        with open(f) as fh:
            hdr = fh.readline().split()
            last = [ln for ln in fh if ln.strip()][-1]
        out[int(d[-3:])] = float(last.split()[hdr.index('D')])
    return out


def paired(a, b):
    """Mean and 95% half-width of b - a over common seeds."""
    seeds = sorted(set(a) & set(b))
    d = np.array([b[s] - a[s] for s in seeds])
    hw = T95.get(len(d) - 1, 1.96) * d.std(ddof=1) / np.sqrt(len(d))
    return d.mean(), hw, len(d)


def ample_deaths():
    f = f'{MIR}/.ensemble_bay_verify_ample_mit_matrix/output_summary_mean.dat'
    with open(f) as fh:
        hdr = fh.readline().split()
        last = [ln for ln in fh if ln.strip()][-1]
    return float(last.split()[hdr.index('Deaths')])


def main():
    ample = ample_deaths()
    print(f'ample-bed mitigated deaths (mean): {ample:.1f}')
    D = {g: (final_deaths(m), final_deaths(h)) for g, (m, h) in CASES.items()}
    res = {}
    print(f'{"gamma":>5} {"n":>3} {"deaths mit":>16} {"deaths hcw":>16} {"multiplier":>10} '
          f'{"amplification [95% CI]":>26}')
    for g in sorted(D):
        m, h = D[g]
        dm, hm = np.array(list(m.values())), np.array(list(h.values()))
        mult = dm.mean() / ample
        diff, hw, n = paired(m, h)
        amp, amp_hw = diff / dm.mean(), hw / dm.mean()
        res[g] = (mult, amp, amp_hw, dm.mean(), hm.mean())
        print(f'{g:>5.1f} {n:>3} {dm.mean():>9.0f} ± {dm.std(ddof=1):>4.0f} {hm.mean():>9.0f} ± '
              f'{hm.std(ddof=1):>4.0f} {mult:>10.3f} {100 * amp:>11.1f}% [{100 * (amp - amp_hw):.1f}, '
              f'{100 * (amp + amp_hw):.1f}]')
    print('\npaired change against gamma = 1 (same seeds), deaths [95% CI]:')
    for g in (0.8, 0.5):
        for i, lab in ((0, 'mit'), (1, 'hcw')):
            diff, hw, n = paired(D[1.0][i], D[g][i])
            print(f'  gamma={g} {lab}: {diff:+.0f} [{diff - hw:+.0f}, {diff + hw:+.0f}] '
                  f'({100 * diff / np.mean(list(D[1.0][i].values())):+.1f}%)')
    print('\nlinearity at gamma = 0.8 (value vs linear interpolation between 0.5 and 1):')
    for k, lab in ((0, 'multiplier'), (1, 'amplification')):
        interp = res[0.5][k] + 0.6 * (res[1.0][k] - res[0.5][k])
        print(f'  {lab}: {res[0.8][k]:.4f} vs {interp:.4f} (difference {res[0.8][k] - interp:+.4f})')


if __name__ == '__main__':
    main()
