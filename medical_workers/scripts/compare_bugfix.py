#!/usr/bin/env python3
"""One-realization check of the in-hospital asymptomatic-patient count fix (ExaEpi c463918).

Seed 1 of every deck with in-hospital transmission, run with the old binary (5b7576a, bugcheck/nofix)
and the fixed one (c463918, bugcheck/fix). The old-binary run must be bit-identical to revision run_001.
Paired quantities use revision run_001 of the unaffected partner deck (H1_mitigated, S3_gamma*_mit).

Usage: compare_bugfix.py [mirror_root]   (default ~/Runs/remote/ExaEpi_LC/medical_workers)
"""
import filecmp, glob, math, os, re, sys
import numpy as np
import yt

yt.set_log_level(50)
ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~/Runs/remote/ExaEpi_LC/medical_workers')
TREES = {'rev': f'{ROOT}/revision', 'nofix': f'{ROOT}/bugcheck/nofix', 'fix': f'{ROOT}/bugcheck/fix'}
CASES = ['H3_hcw', 'S2_hcw_lo', 'S2_hcw_hi', 'S3_gamma05_hcw', 'S3_gamma08_hcw', 'covflu_w_noso', 'covflu_wo_noso']
CAP = 10876
AGES = ['U5', '5to17', '18to29', '30to49', '50to64', 'O64']
DIS = ['Cov19S1', 'FluS1']


def run(tree, case):
    return f'{TREES[tree]}/.ensemble_bay_{case}_matrix/run_001'


def table(p):
    L = [l for l in open(p) if l.strip()]
    return L[0].split(), np.array([[float(x) for x in l.split()] for l in L[1:]])


def col(h, m, n):
    return m[:, h.index(n)]


def chr_from_deck(deck):
    c = {}
    for l in open(deck):
        m = re.match(r'\s*disease(_\w+)?\.CHR\s*=\s*([\d.\s]+)', l)
        if m:
            c[(m.group(1) or '_Cov19S1')[1:]] = np.array([float(x) for x in m.group(2).split()])
    return c


def out_metrics(p, chr_):
    h, m = table(p)
    cen = col(h, m, 'H/NI') + col(h, m, 'H/I')
    k = int(np.argmax(cen))
    return dict(deaths=col(h, m, 'D')[-1], infections=col(h, m, 'NewI').sum(), peak_load=cen[k] / CAP,
                peak_day=col(h, m, 'Day')[k], peak_icu=col(h, m, 'ICU').max(),
                admissions=sum(col(h, m, 'Symp' + a).sum() * chr_[j] for j, a in enumerate(AGES)))


def mw_metrics(p):
    h, m = table(p)
    s0, s1 = col(h, m, 'MW_susc'), col(h, m, 'OW_susc')
    return dict(mw_attack=1 - s0[-1] / s0[0], ow_attack=1 - s1[-1] / s1[0],
                hazard_ratio=math.log(s0[0] / s0[-1]) / math.log(s1[0] / s1[-1]),
                mw_deaths=col(h, m, 'MW_dead')[-1])


def workforce(r):
    v = []
    for hd in sorted(glob.glob(f'{r}/hospital_data_*')):
        d = yt.load(hd)
        g = d.covering_grid(level=0, left_edge=d.domain_left_edge, dims=d.domain_dimensions)
        a = np.asarray(g['boxlib', 'num_available_frontline_medworkers']).sum()
        b = np.asarray(g['boxlib', 'baseline_frontline_medworkers']).sum()
        if b > 0:
            v.append(a / b)
    return min(v)


def hosp_acquired(r):
    last = sorted(glob.glob(f'{r}/plt?????'))[-1]
    ad = yt.load(last).all_data()
    return {d: float(ad[('boxlib', f'{d}_hospital_acquired')].sum()) for d in DIS}


def metrics(tree, case):
    r = run(tree, case)
    chr_ = chr_from_deck(f'{os.path.dirname(r)}/inputs_bay_{case}')
    if os.path.exists(f'{r}/output.dat'):
        x = out_metrics(f'{r}/output.dat', chr_['Cov19S1'])
        x.update(mw_metrics(f'{r}/medical_workers.dat'))
    else:
        x = {}
        for d in DIS:
            y = out_metrics(f'{r}/output_{d}.dat', chr_[d])
            if d == 'Cov19S1':
                x.update({k: y[k] for k in ('deaths', 'peak_load', 'peak_day', 'peak_icu')})
            x[f'infections_{d}'], x[f'admissions_{d}'] = y['infections'], y['admissions']
            x.update({f'{k}_{d}': v for k, v in mw_metrics(f'{r}/medical_workers_{d}.dat').items()
                      if not (k == 'mw_deaths' and d == 'FluS1')})
        ha = hosp_acquired(r)
        x['HA_flu_adm_to_covid'] = ha['Cov19S1'] / x['admissions_FluS1']
        x['HA_covid_adm_to_flu'] = ha['FluS1'] / x['admissions_Cov19S1']
        x['HA_all_admissions'] = sum(ha.values()) / (x['admissions_FluS1'] + x['admissions_Cov19S1'])
    x['min_workforce_avail'] = workforce(r)
    return x


def first_divergence(case):
    a, b = run('nofix', case), run('fix', case)
    first = None
    for f in sorted(os.path.basename(p) for p in glob.glob(f'{a}/*.dat')):
        ha, ma = table(f'{a}/{f}')
        hb, mb = table(f'{b}/{f}')
        n = min(len(ma), len(mb))
        bad = np.where(np.any(ma[:n] != mb[:n], axis=1))[0]
        if len(bad):
            first = int(ma[bad[0], 0]) if first is None else min(first, int(ma[bad[0], 0]))
    return first


def deaths(r):
    p = f'{r}/output.dat' if os.path.exists(f'{r}/output.dat') else f'{r}/output_Cov19S1.dat'
    h, m = table(p)
    return col(h, m, 'D')[-1]


M = {}
for c in CASES:
    a, b = run('rev', c), run('nofix', c)
    files = sorted(os.path.basename(p) for p in glob.glob(f'{a}/*.dat'))
    same = all(filecmp.cmp(f'{a}/{f}', f'{b}/{f}', shallow=False) for f in files)
    M[c] = {t: metrics(t, c) for t in ('nofix', 'fix')}
    print(f'\n== {c}: without fix vs revision run_001 {"bit-identical" if same else "DIFFERENT"} '
          f'({len(files)} files); with fix diverges from day {first_divergence(c)}')
    print(f'  {"metric":26s} {"without fix":>13s} {"with fix":>13s} {"change":>9s}')
    for k, v0 in M[c]['nofix'].items():
        v1 = M[c]['fix'][k]
        rel = f'{100 * (v1 - v0) / v0:+8.2f}%' if v0 else '        -'
        print(f'  {k:26s} {v0:13.5g} {v1:13.5g} {rel}')

print('\n== Paired with unaffected partner decks (revision run_001, seed 1): deaths increase')
PAIRS = [('H3_hcw', 'H1_mitigated'), ('S2_hcw_lo', 'H1_mitigated'), ('S2_hcw_hi', 'H1_mitigated'),
         ('S3_gamma05_hcw', 'S3_gamma05_mit'), ('S3_gamma08_hcw', 'S3_gamma08_mit')]
for a, b in PAIRS:
    base = deaths(run('rev', b))
    v = [deaths(run(t, a)) - base for t in ('nofix', 'fix')]
    print(f'  {a:16s} - {b:16s} without fix {v[0]:7.0f} ({100 * v[0] / base:+6.2f}%)'
          f'  with fix {v[1]:7.0f} ({100 * v[1] / base:+6.2f}%)')
v = [deaths(run(t, 'covflu_w_noso')) - deaths(run(t, 'covflu_wo_noso')) for t in ('nofix', 'fix')]
base = [deaths(run(t, 'covflu_wo_noso')) for t in ('nofix', 'fix')]
print(f'  {"covflu_w_noso":16s} - {"covflu_wo_noso":16s} without fix {v[0]:7.0f} ({100 * v[0] / base[0]:+6.2f}%)'
      f'  with fix {v[1]:7.0f} ({100 * v[1] / base[1]:+6.2f}%)')
