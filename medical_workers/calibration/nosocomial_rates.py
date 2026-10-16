"""Hospital-acquired rates in covflu_w_noso run_001: NewH vs the Symp x CHR admission estimate."""
import glob, re, sys
import numpy as np
import yt
yt.set_log_level(50)
M = '/home/ghosh/Runs/remote/ExaEpi_LC/medical_workers'
AGES = ['SympU5', 'Symp5to17', 'Symp18to29', 'Symp30to49', 'Symp50to64', 'SympO64']

def table(p):
    L = [l for l in open(p) if l.strip() and not l.startswith('#')]
    h = L[0].split()
    return h, np.array([[float(x) for x in l.split()] for l in L[1:]])

def chr_from_deck(deck):
    c = {}
    for l in open(deck):
        m = re.match(r'\s*disease(_\w+)?\.CHR\s*=\s*([\d.\s]+)', l)
        if m: c[(m.group(1) or '')[1:] or 'default'] = np.array([float(x) for x in m.group(2).split()])
    return c

def col(h, m, n): return m[:, h.index(n)]

def estadm(h, m, chr_): return sum(col(h, m, a).sum() * chr_[k] for k, a in enumerate(AGES))

def ha(run):
    last = sorted(glob.glob(f'{run}/plt?????'))[-1]
    ad = yt.load(last).all_data()
    return (float(ad[('boxlib', 'Cov19S1_hospital_acquired')].sum()),
            float(ad[('boxlib', 'FluS1_hospital_acquired')].sum()), last.split('/')[-1])

print('== estimator check, single-disease run_001: sum NewH vs sum(Symp x CHR)')
for c in ['H1_mitigated', 'H3_hcw', 'H1_capacity']:
    E = f'{M}/.ensemble_bay_{c}_matrix'
    ch = chr_from_deck(f'{E}/inputs_bay_{c}')['default']
    h, m = table(f'{E}/run_001/output.dat')
    nh, est = col(h, m, 'NewH').sum(), estadm(h, m, ch)
    print(f'  {c:13s} NewH={nh:8.0f} est={est:8.0f} ratio={nh/est:.3f}')

for plat in ['tuolumne', 'matrix']:
    E = f'{M}/.ensemble_bay_covflu_w_noso_{plat}'
    ch = chr_from_deck(f'{E}/inputs_bay_covflu_w_noso')
    chd = {'Cov19S1': ch.get('Cov19S1', ch['default']), 'FluS1': ch['FluS1']}
    print(f'\n== covflu_w_noso {plat}')
    for lab, base in [('run_001', f'{E}/run_001/output_%s.dat'), ('ens-mean', f'{E}/output_%s_mean.dat')]:
        r = {}
        for d in ['Cov19S1', 'FluS1']:
            h, m = table(base % d)
            r[d] = (col(h, m, 'NewH').sum(), estadm(h, m, chd[d]),
                    (col(h, m, 'H/NI') + col(h, m, 'H/I') + col(h, m, 'ICU') + col(h, m, 'V')).sum(),
                    col(h, m, 'NewS').sum())
        print(f'  {lab:8s} NewH cov={r["Cov19S1"][0]:8.0f} flu={r["FluS1"][0]:8.0f} sum={r["Cov19S1"][0]+r["FluS1"][0]:8.0f} | '
              f'est adm cov={r["Cov19S1"][1]:7.0f} flu={r["FluS1"][1]:7.0f} | patient-days={r["Cov19S1"][2]:8.0f} | '
              f'NewS cov={r["Cov19S1"][3]:8.0f} flu={r["FluS1"][3]:8.0f}')
        if lab == 'run_001': R1 = r
        else: RE = r
    runs = sorted(glob.glob(f'{E}/run_*'))
    for run in runs:
        if not glob.glob(f'{run}/plt?????'): continue
        hc, hf, last = ha(run)
        print(f'  HA {run.split("/")[-1]} ({last}): COVID acquired (by flu adm)={hc:6.0f}  flu acquired (by COVID adm)={hf:6.0f}  total={hc+hf:6.0f}')
        if run.endswith('run_001'): HC, HF = hc, hf
    T = HC + HF
    nc, nf = R1['Cov19S1'][0], R1['FluS1'][0]
    ac, af = R1['Cov19S1'][1], R1['FluS1'][1]
    print(f'  paper-style (run_001 HA / ens-mean COVID NewH {RE["Cov19S1"][0]:.0f}): total {T/RE["Cov19S1"][0]:.2%}  flu->COVID {HC/RE["Cov19S1"][0]:.2%}')
    print(f'  run_001 HA / run_001 summed NewH {nc+nf:.0f}: total {T/(nc+nf):.2%}')
    print(f'  correct (run_001 est adm): total {T:.0f}/{ac+af:.0f}={T/(ac+af):.1%}  flu->COVID {HC:.0f}/{af:.0f}={HC/af:.1%}  COVID->flu {HF:.0f}/{ac:.0f}={HF/ac:.1%}')
    print(f'  NewH contamination run_001: cov {nc-ac:.0f}  flu {nf-af:.0f}')
