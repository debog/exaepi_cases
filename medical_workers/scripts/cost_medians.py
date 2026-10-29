"""Per-step cost of the medical-workforce model from the TinyProfiler output of the cost ensembles:
median REG::Evolution / 120 steps, and the medians of the model regions (treatment routine, profiled as
HospitalModel::interactAgents; fastInteractHospital; updateHospitalCapacities; computeHospitalScores).
Usage: cost_medians.py <mirror root> [<mirror root> ...]. Sec 6.2 and Fig 16 of the IDM paper."""
import glob, re, sys, numpy as np
KEYS=['REG::Evolution','HospitalModel::interactAgents','fastInteractHospital','AgentContainer::updateHospitalCapacities','HospitalModel::computeHospitalScores','ParticleContainer::Redistribute_impl()','AgentContainer::updateStatus','amrex::ParticleToMesh','runAgent']
def parse(f):
    txt=open(f,errors='ignore').read()
    blocks=txt.split('TinyProfiler total time')[1:]
    out=[]
    for b in blocks:
        i=b.find('Incl. Min'); 
        if i<0: continue
        tab=b[i:].split('\n\n')[0]
        d={}
        for line in tab.splitlines():
            parts=line.split()
            if len(parts)>=6 and parts[0] in KEYS and parts[0] not in d:
                d[parts[0]]=float(parts[3])
        out.append(d)
    return out
for root in sys.argv[1:]:
    print('##', root)
    for cfg in ('off','on','on_full'):
        fs=glob.glob(f'{root}/.ensemble_bay_cost_{cfg}_matrix_n1/ensemble_*.out')
        rows=[r for f in fs for r in parse(f)]
        ev=np.array([r['REG::Evolution'] for r in rows])/120*1e3
        s=f'{cfg:8s} n={len(rows)} step median {np.median(ev):.1f} ms'
        for k in KEYS[1:6]:
            v=[r.get(k,0) for r in rows]; s+=f' | {k.split("::")[-1]} {np.median(v)/120*1e3:.2f}'
        s+=f' | runAgent {np.median([r["runAgent"] for r in rows]):.1f} s'
        print(s)

print('## spread of per-step time (ms): median, IQR, min-max')
for root in sys.argv[1:]:
    for cfg in ('off','on','on_full'):
        rows=[r for f in glob.glob(f'{root}/.ensemble_bay_cost_{cfg}_matrix_n1/ensemble_*.out') for r in parse(f)]
        ev=np.array([r['REG::Evolution'] for r in rows])/120*1e3
        q1,q3=np.percentile(ev,[25,75])
        prof=np.array([sum(r.get(k,0) for k in KEYS[1:6]) for r in rows])
        print(f'{root[-8:]} {cfg:8s} median {np.median(ev):.1f}  IQR {q1:.1f}-{q3:.1f}  range {ev.min():.1f}-{ev.max():.1f}')
