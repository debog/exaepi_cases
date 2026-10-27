#!/usr/bin/env python3
"""Worker- and patient-infection paths in the same two-disease setting (reviewer comment R2.4),
from the LC mirror. A 2x2 design of COVID-19 and influenza ensembles:

  noxmit        no in-hospital transmission
  wo_noso       worker paths only (d2d, p2d)
  patient_only  patient paths only (d2p, p2p)
  w_noso        both

Each path's effect is given without and with the other path, in deaths and in percent of the
no-transmission toll, with the paired 95% CI and the population sigma of the paired differences
(realizations with the same seed). Deaths are D of output_Cov19S1.dat, which counts all agents.
Usage: worker_patient_paths.py [mirror_dir]
"""
import glob
import os
import sys

import numpy as np

from capacity_exponent_sweep import T95

MIR = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    '~/Runs/remote/ExaEpi_LC/medical_workers/revision')
CASES = {'none': 'covflu_noxmit', 'worker': 'covflu_wo_noso',
         'patient': 'covflu_patient_only', 'both': 'covflu_w_noso'}


def totals(case):
    """Per seed: final deaths, and admissions and infections of each disease."""
    out = {}
    for d in sorted(glob.glob(f'{MIR}/.ensemble_bay_{case}_matrix/run_*')):
        row = []
        for dis in ('Cov19S1', 'FluS1'):
            f = os.path.join(d, f'output_{dis}.dat')
            if not os.path.exists(f):
                break
            with open(f) as fh:
                hdr = fh.readline().split()
            a = np.loadtxt(f, skiprows=1, ndmin=2)
            if dis == 'Cov19S1':
                row.append(a[-1, hdr.index('D')])
            row += [a[:, hdr.index('NewH')].sum(), a[:, hdr.index('NewI')].sum()]
        if len(row) == 5:
            out[int(d[-3:])] = row
    return out


def main():
    T = {k: totals(c) for k, c in CASES.items()}
    print('case      n   deaths            COVID adm  flu adm   COVID inf  flu inf')
    for k, v in T.items():
        if not v:
            print(f'{k:<8}   0   missing ({CASES[k]})')
            continue
        x = np.array(list(v.values()))
        print(f'{k:<8} {len(x):>3} {x[:, 0].mean():>7.0f} ± {x[:, 0].std():>4.0f} '
              f'{x[:, 1].mean():>10.0f} {x[:, 3].mean():>8.0f} {x[:, 2].mean():>11.0f} {x[:, 4].mean():>9.0f}')
    seeds = sorted(set.intersection(*(set(v) for v in T.values())))
    if len(seeds) < 2:
        print(f'only {len(seeds)} common seeds; no comparison')
        return
    D = {k: np.array([T[k][s][0] for s in seeds]) for k in T}
    ref = D['none'].mean()
    effects = {'worker paths, without patient paths': D['worker'] - D['none'],
               'worker paths, with patient paths': D['both'] - D['patient'],
               'patient paths, without worker paths': D['patient'] - D['none'],
               'patient paths, with worker paths': D['both'] - D['worker'],
               'interaction': D['both'] - D['worker'] - D['patient'] + D['none'],
               'both paths': D['both'] - D['none']}
    print(f'\npaired over {len(seeds)} seeds; % of the no-transmission toll ({ref:.0f})')
    for lab, x in effects.items():
        m, hw, sd = x.mean(), T95.get(len(x) - 1, 1.96) * x.std(ddof=1) / np.sqrt(len(x)), x.std()
        print(f'  {lab:<37} {m:>6.0f} [{m - hw:.0f}, {m + hw:.0f}] sigma {sd:.0f}   '
              f'{100 * m / ref:>5.1f}% [{100 * (m - hw) / ref:.1f}, {100 * (m + hw) / ref:.1f}] '
              f'sigma {100 * sd / ref:.1f}%   positive {np.sum(x > 0)}/{len(x)}')
    print('\nfor reference, patient paths over the worker-only toll (the paper\'s 2.0%): '
          f'{100 * effects["patient paths, with worker paths"].mean() / D["worker"].mean():.1f}%')


if __name__ == '__main__':
    main()
