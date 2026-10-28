"""Hospital-acquired infections per disease at day 365 (sum of <disease>_hospital_acquired),
per realization and ensemble mean, with shares of all infections. Usage: hospital_acquired.py <ensemble dir>.
Fig 13a and Sec 5.5 of the IDM paper."""
import numpy as np, yt, glob, os
yt.set_log_level(50)
import sys
D=sys.argv[1]
rows=[]
for r in sorted(glob.glob(D+'/run_*')):
    p=sorted(glob.glob(r+'/plt*'))[-1]
    ds=yt.load(p)
    if not rows: print('last plotfile', os.path.basename(p), [f for f in ds.field_list if 'acquired' in f[1]])
    g=ds.covering_grid(0, ds.domain_left_edge, ds.domain_dimensions)
    hc=float(np.sum(g[('boxlib','Cov19S1_hospital_acquired')])); hf=float(np.sum(g[('boxlib','FluS1_hospital_acquired')]))
    tot=[]
    for d in ('Cov19S1','FluS1'):
        f=f'{r}/output_{d}.dat'; hdr=open(f).readline().split(); a=np.loadtxt(f,skiprows=1); tot.append(a[:,hdr.index('NewI')].sum())
    rows.append((hc,hf,tot[0],tot[1]))
a=np.array(rows)
print('run_001', a[0,:2], 'share %.3f%% cov %.3f%% flu %.3f%%'%(100*a[0,:2].sum()/a[0,2:].sum(),100*a[0,0]/a[0,2],100*a[0,1]/a[0,3]))
m=a.mean(0); print('mean HA cov %.0f flu %.0f (sd %.0f %.0f); share combined %.3f%% cov %.3f%% flu %.3f%%'%(m[0],m[1],a[:,0].std(),a[:,1].std(),100*(m[0]+m[1])/(m[2]+m[3]),100*m[0]/m[2],100*m[1]/m[3]))
print('per-run combined share range %.3f-%.3f%%'%((100*a[:,:2].sum(1)/a[:,2:].sum(1)).min(),(100*a[:,:2].sum(1)/a[:,2:].sum(1)).max()))
