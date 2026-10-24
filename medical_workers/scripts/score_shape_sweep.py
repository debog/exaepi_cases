#!/usr/bin/env python3
"""Score-shape sweep (reviewer comment R1.2): deaths, excess-mortality multiplier, and
depletion-driven amplification for the shapes of the treatment-quality degradation, from the
LC mirror of the ensembles. Every shape has the half score at an excess load of 1.5 and M_max = 3.

  multiplier    = mean deaths (mitigated, no in-hospital transmission) / ample-bed mitigated deaths
  amplification = deaths with in-hospital transmission / deaths without, minus 1 (same shape)

Paired statistics use realizations with the same seed. The original shape (logistic, k = 1) is
H1_mitigated / H3_hcw.
Usage: score_shape_sweep.py [mirror_dir]
"""
import os
import sys

import numpy as np

from capacity_exponent_sweep import ample_deaths, final_deaths, paired

MIR = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    '~/Runs/remote/ExaEpi_LC/medical_workers/revision')
CASES = {'logistic k=1 (paper)': ('H1_mitigated', 'H3_hcw'),
         'linear': ('S5_linear_mit', 'S5_linear_hcw'),
         'saturating': ('S5_saturating_mit', 'S5_saturating_hcw'),
         'logistic k=3': ('S5_logistic3_mit', 'S5_logistic3_hcw')}
REF = 'logistic k=1 (paper)'


def main():
    import capacity_exponent_sweep as ces
    ces.MIR = MIR
    ample = ample_deaths()
    print(f'ample-bed mitigated deaths (mean): {ample:.1f}')
    D = {s: (final_deaths(m), final_deaths(h)) for s, (m, h) in CASES.items()}
    print(f'{"shape":>22} {"n":>3} {"deaths mit":>16} {"deaths hcw":>16} {"multiplier":>10} '
          f'{"amplification [95% CI]":>26}')
    for s, (m, h) in D.items():
        if not m or not h:
            print(f'{s:>22}  missing ({len(m)} mit, {len(h)} hcw realizations)')
            continue
        dm, hm = np.array(list(m.values())), np.array(list(h.values()))
        diff, hw, n = paired(m, h)
        amp, amp_hw = diff / dm.mean(), hw / dm.mean()
        print(f'{s:>22} {n:>3} {dm.mean():>9.0f} ± {dm.std(ddof=1):>4.0f} {hm.mean():>9.0f} ± '
              f'{hm.std(ddof=1):>4.0f} {dm.mean() / ample:>10.3f} {100 * amp:>11.1f}% '
              f'[{100 * (amp - amp_hw):.1f}, {100 * (amp + amp_hw):.1f}]')
    print(f'\npaired change against {REF} (same seeds), deaths [95% CI]:')
    for s in CASES:
        if s == REF or not D[s][0]:
            continue
        for i, lab in ((0, 'mit'), (1, 'hcw')):
            diff, hw, n = paired(D[REF][i], D[s][i])
            ref = np.mean(list(D[REF][i].values()))
            print(f'  {s:>14} {lab}: {diff:+.0f} [{diff - hw:+.0f}, {diff + hw:+.0f}] '
                  f'({100 * diff / ref:+.1f}% [{100 * (diff - hw) / ref:+.1f}, {100 * (diff + hw) / ref:+.1f}])')


if __name__ == '__main__':
    main()
