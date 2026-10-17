#!/usr/bin/env python3
"""Compare the revision ensembles (<root>/revision) with the paper ensembles (<root>).

Per case: bitwise identity of member outputs, first day of divergence (ignoring the
columns the NewH fix changes), ensemble statistics and their difference. Then paired
(same-seed) differences between scenarios, hospital-acquired rates of the two-disease
runs, and the per-step cost.

Usage: compare_ensembles.py [root]   (default /p/vast1/ghosh5/exaepi/medical_workers)
"""
import filecmp, glob, math, os, re, sys
import numpy as np

ROOT = sys.argv[1] if len(sys.argv) > 1 else '/p/vast1/ghosh5/exaepi/medical_workers'
PAP, REV = ROOT, os.path.join(ROOT, 'revision')
N = 25
CAP = 10876
T975 = 2.064  # t_{0.975, 24}
AGES = ['U5', '5to17', '18to29', '30to49', '50to64', 'O64']
FIXCOLS = {'NewH'} | {'Hosp' + a for a in AGES}
INFCOLS = ['PS/PI', 'S/PI/NH', 'S/PI/H', 'PS/I', 'S/I/NH', 'S/I/H', 'A/PI', 'A/I', 'H/NI', 'H/I']
DIS = ['Cov19S1', 'FluS1']


def ens(tree, case):
    return os.path.join(tree, f'.ensemble_bay_{case}_matrix')


def run(tree, case, i):
    return os.path.join(ens(tree, case), 'run_%03d' % i)


def table(p):
    L = [l for l in open(p) if l.strip()]
    h = L[0].split()
    return h, np.array([[float(x) for x in l.split()] for l in L[1:]])


def chr_from_deck(deck):
    c = {}
    for l in open(deck):
        m = re.match(r'\s*disease(_\w+)?\.CHR\s*=\s*([\d.\s]+)', l)
        if m:
            c[(m.group(1) or '_default')[1:]] = np.array([float(x) for x in m.group(2).split()])
    return c


def col(h, m, n):
    return m[:, h.index(n)]


def out_metrics(h, m, chr_):
    cen = col(h, m, 'H/NI') + col(h, m, 'H/I')
    inf = sum(col(h, m, c) for c in INFCOLS)
    k = int(np.argmax(cen))
    return dict(deaths=col(h, m, 'D')[-1], peak_load=cen[k] / CAP, peak_day=col(h, m, 'Day')[k],
                peak_icu=col(h, m, 'ICU').max(), peak_inf=inf.max(), infections=col(h, m, 'NewI').sum(),
                newh=col(h, m, 'NewH').sum(),
                adm_est=sum(col(h, m, 'Symp' + a).sum() * chr_[j] for j, a in enumerate(AGES)))


def mw_metrics(p):
    h, m = table(p)
    s0, s1 = col(h, m, 'MW_susc'), col(h, m, 'OW_susc')
    lm, lo = math.log(s0[0] / s0[-1]), math.log(s1[0] / s1[-1])
    return dict(mw_inf=1 - s0[-1] / s0[0], ow_inf=1 - s1[-1] / s1[0], chr_ach=lm / lo,
                mw_dead=col(h, m, 'MW_dead')[-1], ow_dead=col(h, m, 'OW_dead')[-1])


def member(tree, case, i):
    r = run(tree, case, i)
    chr_ = chr_from_deck(os.path.join(ens(tree, case), f'inputs_bay_{case}'))
    if os.path.exists(f'{r}/output.dat'):
        x = out_metrics(*table(f'{r}/output.dat'), chr_['default'])
        if os.path.exists(f'{r}/medical_workers.dat'):
            x.update(mw_metrics(f'{r}/medical_workers.dat'))
        return x
    x, cen = {}, []
    for d in DIS:
        h, m = table(f'{r}/output_{d}.dat')
        y = out_metrics(h, m, chr_.get(d, chr_['default']))
        cen.append(col(h, m, 'H/NI') + col(h, m, 'H/I'))
        for k, v in y.items():
            x[f'{k}_{d}'] = v
    # D and the census count all agents in each disease file
    x['deaths'] = x.pop('deaths_Cov19S1')
    x['deaths_mismatch'] = abs(x.pop('deaths_FluS1') - x['deaths'])
    x['peak_load'] = x.pop('peak_load_Cov19S1')
    x['census_mismatch'] = float(np.abs(cen[0] - cen[1]).max())
    for k in ('peak_load', 'peak_day', 'peak_icu'):
        x.pop(f'{k}_FluS1')
    return x


def divergence(case, i):
    """(all files bit-identical, first differing day ignoring FIXCOLS or None)."""
    a, b = run(PAP, case, i), run(REV, case, i)
    files = sorted(os.path.basename(f) for f in glob.glob(f'{a}/output*.dat') + glob.glob(f'{a}/medical_workers*.dat'))
    same = all(filecmp.cmp(f'{a}/{f}', f'{b}/{f}', shallow=False) for f in files)
    first = None
    for f in files:
        ha, ma = table(f'{a}/{f}')
        hb, mb = table(f'{b}/{f}')
        keep = [j for j, c in enumerate(ha) if c not in FIXCOLS]
        n = min(len(ma), len(mb))
        bad = np.where(np.any(ma[:n, keep] != mb[:n, keep], axis=1))[0]
        d = int(ma[bad[0], 0]) if len(bad) else (int(ma[n - 1, 0]) + 1 if len(ma) != len(mb) else None)
        if d is not None:
            first = d if first is None else min(first, d)
    return same, first


def mean_curve_peak(tree, case):
    f = 'output.dat' if os.path.exists(f'{run(tree, case, 1)}/output.dat') else 'output_Cov19S1.dat'
    C = []
    for i in range(1, N + 1):
        h, m = table(f'{run(tree, case, i)}/{f}')
        C.append(col(h, m, 'H/NI') + col(h, m, 'H/I'))
    n = min(len(c) for c in C)
    return np.mean([c[:n] for c in C], axis=0).max() / CAP


def stats(v):
    v = np.asarray(v, float)
    return v.mean(), v.std(), v.std(ddof=1)


def ha_counts(r):
    import yt
    yt.set_log_level(50)
    last = sorted(glob.glob(f'{r}/plt?????'))[-1]
    ad = yt.load(last).all_data()
    return {d: float(ad[('boxlib', f'{d}_hospital_acquired')].sum()) for d in DIS}


def cost(tree, case, nsteps=120):
    """Per-step ms (REG::Evolution inclusive avg / nsteps) per member."""
    o = sorted(glob.glob(os.path.join(tree, f'.ensemble_bay_{case}', 'ensemble_*.out')))
    if not o:
        return []
    blocks = open(o[-1]).read().split('TinyProfiler total time')[1:]
    v = []
    for b in blocks:
        L = [x for x in (l.split() for l in b.splitlines() if l.startswith('REG::Evolution '))
             if len(x) == 6 and x[5].endswith('%')]
        if len(L) >= 2:
            v.append(1000 * float(L[1][3]) / nsteps)
    return v


cases = sorted(os.path.basename(d)[len('.ensemble_bay_'):-len('_matrix')]
               for d in glob.glob(f'{REV}/.ensemble_bay_*_matrix'))
M = {}
print('=' * 100)
print('Per-case comparison: paper (P) vs revision (R); mean (sd) over 25 members; z = (R-P)/SE')
print('=' * 100)
for c in cases:
    div = [divergence(c, i) for i in range(1, N + 1)]
    nid = sum(s for s, _ in div)
    nfix = sum(f is None for _, f in div)
    days = [f for _, f in div if f is not None]
    M[c] = {t: [member(t, c, i) for i in range(1, N + 1)] for t in (PAP, REV)}
    dtxt = f'first divergence day min/median/max {min(days)}/{int(np.median(days))}/{max(days)}' if days else ''
    print(f'\n{c}: bit-identical members {nid}/{N}; identical except NewH/Hosp* {nfix}/{N}; {dtxt}')
    print('  peak load of the ensemble-mean census curve: ' +
          '  '.join(f'{lab} {mean_curve_peak(t, c):.3f}' for t, lab in ((PAP, 'P'), (REV, 'R'))))
    for k in M[c][REV][0]:
        p, r = [x[k] for x in M[c][PAP]], [x[k] for x in M[c][REV]]
        mp, sp, sp1 = stats(p)
        mr, sr, sr1 = stats(r)
        se = math.sqrt((sp1 ** 2 + sr1 ** 2) / N)
        z = (mr - mp) / se if se > 0 else 0.0
        rel = 100 * (mr - mp) / mp if mp else float('nan')
        print(f'  {k:22s} P {mp:12.4g} ({sp:9.3g})  R {mr:12.4g} ({sr:9.3g})  d {rel:+7.2f}%  z {z:+6.2f}')

print('\n' + '=' * 100)
print('Paired (same-seed) differences of deaths, A - B: mean, sd, 95% CI, mean % of B')
print('=' * 100)
PAIRS = [('H3_hcw', 'H1_mitigated'), ('covflu_w_noso', 'covflu_wo_noso'),
         ('H1_mitigated_notransfer', 'H1_mitigated'), ('H1_mitigated', 'verify_ample_mit'),
         ('H1_capacity', 'verify_ample'), ('verify_off', 'verify_ample'), ('verify_match', 'verify_ample'),
         ('H2_mw08', 'H1_mitigated'), ('H2_mw13', 'H1_mitigated'), ('H2_mw20', 'H1_mitigated'),
         ('S2_hcw_lo', 'H1_mitigated'), ('S2_hcw_hi', 'H1_mitigated'),
         ('S1_lhalf10', 'H1_mitigated'), ('S1_lhalf25', 'H1_mitigated'),
         ('S1_mmax2', 'H1_mitigated'), ('S1_mmax4', 'H1_mitigated')]
for a, b in PAIRS:
    if a not in M or b not in M:
        continue
    for t, lab in ((PAP, 'P'), (REV, 'R')):
        d = np.array([x['deaths'] for x in M[a][t]]) - np.array([x['deaths'] for x in M[b][t]])
        base = np.mean([x['deaths'] for x in M[b][t]])
        m, s = d.mean(), d.std(ddof=1)
        h = T975 * s / math.sqrt(N)
        print(f'  {lab} {a:24s} - {b:18s} {m:9.1f}  sd {s:8.1f}  CI [{m - h:9.1f}, {m + h:9.1f}]  {100 * m / base:+6.2f}%')

print('\n' + '=' * 100)
print('Two-disease runs: admissions and hospital-acquired (HA) infections')
print('=' * 100)
for c in ('covflu_w_noso', 'covflu_wo_noso'):
    for t, lab in ((PAP, 'P'), (REV, 'R')):
        rows = []
        for i in range(1, N + 1):
            r = run(t, c, i)
            if not glob.glob(f'{r}/plt?????'):
                continue
            try:
                ha = ha_counts(r)
            except Exception as e:
                print(f'  {lab} {c} run_{i:03d}: HA read failed ({e})')
                continue
            x = M[c][t][i - 1]
            rows.append([ha['Cov19S1'], ha['FluS1'], x['newh_Cov19S1'], x['newh_FluS1'],
                         x['adm_est_Cov19S1'], x['adm_est_FluS1'], x['infections_Cov19S1'], x['infections_FluS1']])
        if not rows:
            print(f'  {lab} {c}: no plotfiles')
            continue
        A = np.array(rows)
        hc, hf, nc, nf, ec, ef, ic, if_ = A.T
        print(f'  {lab} {c}: {len(A)} members with plotfiles')
        for nm, v in [('HA COVID (flu adm acquire COVID)', hc), ('HA flu (COVID adm acquire flu)', hf),
                      ('NewH COVID', nc), ('NewH flu', nf), ('est adm COVID', ec), ('est adm flu', ef),
                      ('NewH/est COVID', nc / ec), ('NewH/est flu', nf / ef),
                      ('rate flu->COVID per flu adm', hc / nf), ('rate COVID->flu per COVID adm', hf / nc),
                      ('rate total per adm', (hc + hf) / (nc + nf)),
                      ('HA share of all infections', (hc + hf) / (ic + if_))]:
            print(f'      {nm:34s} {v.mean():12.5g} (sd {v.std():9.3g})  run_001 {v[0]:12.5g}')

print('\n' + '=' * 100)
print('Per-step cost (ms), median over members: REG::Evolution inclusive / 120 steps')
print('=' * 100)
for n in (1, 2, 3, 4):
    for c in ('cost_off', 'cost_on', 'cost_on_full'):
        cp, cr = cost(PAP, f'{c}_matrix_n{n}'), cost(REV, f'{c}_matrix_n{n}')
        fmt = lambda v: f'{np.median(v):7.2f} [{min(v):6.1f}-{max(v):6.1f}] n={len(v)}' if v else '   none'
        print(f'  n{n} {c:13s} P {fmt(cp)}   R {fmt(cr)}')
