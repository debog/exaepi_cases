#!/usr/bin/env python3
"""Impact of the in-hospital asymptomatic-patient count fix (ExaEpi c463918) on the decks with
in-hospital transmission: old binary (5b7576a, "nofix") against the fixed one (c463918, "fix").

Layouts under <root> (a mirror of medical_workers):
  matrix:   bugcheck/{nofix,fix}/.ensemble_bay_<case>_matrix/run_001 (seed 1); the old-binary run must be
            bit-identical to revision run_001
  tuolumne: bugcheck/tuo/single_{nofix,fix}/.ensemble_bay_<case>_tuolumne/run_001 (seed 1) and
            bugcheck/tuo/ens_{nofix,fix}/.ensemble_bay_<case>_tuolumne/run_001..025
Changes in deaths relative to the unaffected partner decks use the Matrix revision ensemble means of
H1_mitigated and S3_gamma*_mit (those decks have no in-hospital transmission, so the fix cannot change them).

Usage: compare_bugfix.py [root] [matrix|tuolumne]
"""
import filecmp, glob, math, os, re, sys
import numpy as np
import yt

yt.set_log_level(50)
ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~/Runs/remote/ExaEpi_LC/medical_workers')
PLAT = sys.argv[2] if len(sys.argv) > 2 else 'matrix'
CASES = ['H3_hcw', 'S2_hcw_lo', 'S2_hcw_hi', 'S3_gamma05_hcw', 'S3_gamma08_hcw', 'covflu_w_noso', 'covflu_wo_noso']
PARTNER = {'H3_hcw': 'H1_mitigated', 'S2_hcw_lo': 'H1_mitigated', 'S2_hcw_hi': 'H1_mitigated',
           'S3_gamma05_hcw': 'S3_gamma05_mit', 'S3_gamma08_hcw': 'S3_gamma08_mit'}
CAP = 10876
AGES = ['U5', '5to17', '18to29', '30to49', '50to64', 'O64']
DIS = ['Cov19S1', 'FluS1']
if PLAT == 'matrix':
    SINGLE = {v: f'{ROOT}/bugcheck/{v}' for v in ('nofix', 'fix')}
    ENS = {}
else:
    SINGLE = {v: f'{ROOT}/bugcheck/tuo/single_{v}' for v in ('nofix', 'fix')}
    ENS = {v: f'{ROOT}/bugcheck/tuo/ens_{v}' for v in ('nofix', 'fix')}
REV = f'{ROOT}/revision'


def ens_dir(tree, case, plat=PLAT):
    return f'{tree}/.ensemble_bay_{case}_{plat}'


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


def workforce(r, days=(45, 60, 75, 90)):
    v = []
    for t in days:
        hd = f'{r}/hospital_data_{t:05d}'
        if not os.path.isdir(hd):
            continue
        d = yt.load(hd)
        g = d.covering_grid(level=0, left_edge=d.domain_left_edge, dims=d.domain_dimensions)
        a = np.asarray(g['boxlib', 'num_available_frontline_medworkers']).sum()
        b = np.asarray(g['boxlib', 'baseline_frontline_medworkers']).sum()
        if b > 0:
            v.append(a / b)
    return min(v) if v else float('nan')


def hosp_acquired(r):
    last = sorted(glob.glob(f'{r}/plt?????'))[-1]
    ad = yt.load(last).all_data()
    return {d: float(ad[('boxlib', f'{d}_hospital_acquired')].sum()) for d in DIS}


def metrics(r, case):
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


def first_divergence(a, b):
    first = None
    for f in sorted(os.path.basename(p) for p in glob.glob(f'{a}/*.dat')):
        ha, ma = table(f'{a}/{f}')
        hb, mb = table(f'{b}/{f}')
        n = min(len(ma), len(mb))
        bad = np.where(np.any(ma[:n] != mb[:n], axis=1))[0]
        if len(bad):
            first = int(ma[bad[0], 0]) if first is None else min(first, int(ma[bad[0], 0]))
    return first


def rev_mean_deaths(case):
    v = []
    for r in sorted(glob.glob(f'{ens_dir(REV, case, "matrix")}/run_*')):
        p = f'{r}/output.dat'
        h, m = table(p)
        v.append(col(h, m, 'D')[-1])
    return np.mean(v)


print('=' * 96)
print(f'Seed 1, without fix (5b7576a) vs with fix (c463918), {PLAT}')
print('=' * 96)
for c in CASES:
    a, b = f'{ens_dir(SINGLE["nofix"], c)}/run_001', f'{ens_dir(SINGLE["fix"], c)}/run_001'
    note = ''
    if PLAT == 'matrix':
        ref = f'{ens_dir(REV, c)}/run_001'
        files = sorted(os.path.basename(p) for p in glob.glob(f'{ref}/*.dat'))
        same = all(filecmp.cmp(f'{ref}/{f}', f'{a}/{f}', shallow=False) for f in files)
        note = f'without fix vs revision run_001 {"bit-identical" if same else "DIFFERENT"}; '
    x0, x1 = metrics(a, c), metrics(b, c)
    print(f'\n== {c}: {note}runs diverge from day {first_divergence(a, b)}')
    print(f'  {"metric":26s} {"without fix":>13s} {"with fix":>13s} {"change":>9s}')
    for k, v0 in x0.items():
        rel = f'{100 * (x1[k] - v0) / v0:+8.2f}%' if v0 else '        -'
        print(f'  {k:26s} {v0:13.5g} {x1[k]:13.5g} {rel}')

if not ENS:
    sys.exit(0)

N = 25
T = 2.011  # t_{0.975, 48}
E = {c: {v: [metrics(f'{ens_dir(ENS[v], c)}/run_{i:03d}', c) for i in range(1, N + 1)] for v in ENS} for c in CASES}
print('\n' + '=' * 96)
print(f'Ensembles ({N} seeds each), {PLAT}: mean (sd); change = fix - nofix with 95% CI (Welch)')
print('=' * 96)
for c in CASES:
    print(f'\n== {c}')
    for k in E[c]['nofix'][0]:
        a = np.array([x[k] for x in E[c]['nofix']])
        b = np.array([x[k] for x in E[c]['fix']])
        d = b.mean() - a.mean()
        h = T * math.sqrt(a.var(ddof=1) / N + b.var(ddof=1) / N)
        rel = f'{100 * d / a.mean():+7.2f}% [{100 * (d - h) / a.mean():+6.2f}, {100 * (d + h) / a.mean():+6.2f}]' \
            if a.mean() else ''
        print(f'  {k:24s} {a.mean():11.5g} ({a.std(ddof=1):8.3g})  {b.mean():11.5g} ({b.std(ddof=1):8.3g})  {rel}')
    a = np.array([x['deaths'] for x in E[c]['nofix']])
    d = np.array([x['deaths'] for x in E[c]['fix']]) - a
    h = 2.064 * d.std(ddof=1) / math.sqrt(N)
    print(f'  deaths, paired by seed: {100 * d.mean() / a.mean():+6.2f}% '
          f'[{100 * (d.mean() - h) / a.mean():+6.2f}, {100 * (d.mean() + h) / a.mean():+6.2f}]')

print('\n' + '=' * 96)
print('Paper quantities by arm: deaths relative to the unaffected partner deck (Matrix revision mean),')
print('and the two-disease difference with vs without in-hospital infection (paired seeds, same arm)')
print('=' * 96)
for c, p in PARTNER.items():
    base = rev_mean_deaths(p)
    s = '  '.join(f'{v} {100 * (np.mean([x["deaths"] for x in E[c][v]]) - base) / base:+6.2f}%' for v in ENS)
    print(f'  {c:16s} vs {p:16s} (base {base:8.1f})  {s}')
for v in ENS:
    w = np.array([x['deaths'] for x in E['covflu_w_noso'][v]])
    wo = np.array([x['deaths'] for x in E['covflu_wo_noso'][v]])
    d = w - wo
    h = 2.064 * d.std(ddof=1) / math.sqrt(N)
    print(f'  covflu w - wo, {v:5s}: {d.mean():7.1f} [{d.mean() - h:7.1f}, {d.mean() + h:7.1f}]'
          f'  ({100 * d.mean() / wo.mean():+5.2f}%)')
