#!/usr/bin/env python3
"""Death-split sweep (reviewer comment R2.1): deaths for the ward:ICU:ventilator split of the
in-hospital death probability, 1:1:1 and 1:3:6 against the paper's 1:2:3, with the same overall
death probability of hospitalized patients by age. Unmitigated cases pair with H1_capacity,
mitigated ones with H1_mitigated; paired statistics use realizations with the same seed.
Usage: death_split_sweep.py [mirror_dir]
"""
import os
import sys

import numpy as np

import capacity_exponent_sweep as ces
from capacity_exponent_sweep import final_deaths, paired

MIR = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    '~/Runs/remote/ExaEpi_LC/medical_workers/revision')
CASES = {'unmitigated': {'1:2:3 (paper)': 'H1_capacity', '1:1:1': 'S4_split111_unmit',
                         '1:3:6': 'S4_split136_unmit'},
         'mitigated': {'1:2:3 (paper)': 'H1_mitigated', '1:1:1': 'S4_split111_mit',
                       '1:3:6': 'S4_split136_mit'}}
REF = '1:2:3 (paper)'


def main():
    ces.MIR = MIR
    for scen, cases in CASES.items():
        D = {s: final_deaths(c) for s, c in cases.items()}
        print(f'{scen}:')
        for s, d in D.items():
            v = np.array(list(d.values()))
            print(f'  {s:>14} n={len(v):>2} deaths {v.mean():>7.0f} ± {v.std(ddof=1):>4.0f}')
        for s in cases:
            if s == REF:
                continue
            diff, hw, n = paired(D[REF], D[s])
            ref = np.mean(list(D[REF].values()))
            print(f'  {s:>14} vs {REF}: {diff:+.0f} [{diff - hw:+.0f}, {diff + hw:+.0f}] '
                  f'({100 * diff / ref:+.1f}% [{100 * (diff - hw) / ref:+.1f}, {100 * (diff + hw) / ref:+.1f}], n={n})')


if __name__ == '__main__':
    main()
