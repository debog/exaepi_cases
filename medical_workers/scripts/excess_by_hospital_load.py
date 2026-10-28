"""Excess deaths per tract (ensemble mean, mitigated H1 minus ample beds) against the mean load
(days 60, 75, 90) of the nearest hospital: rank correlation and shares of residents and excess
deaths. Sec 5.2 / 7.1 of the IDM paper. Run with the default venv."""
import numpy as np, pandas as pd, geopandas as gpd, yt, glob, os
from scipy.stats import spearmanr
yt.set_log_level(50)
MIR='/home/ghosh/Runs/remote/ExaEpi_LC/medical_workers/revision'; GEO='/home/ghosh/Runs/exaepi/medical_workers/geo'
cells=pd.read_csv(f'{GEO}/bayarea_cell_fips.csv', dtype={'geoid':str})
tr=gpd.read_file(f'{GEO}/bayarea_2000_tracts.shp').to_crs(3310); cen=tr.set_index(tr.geoid.astype(str)).geometry.centroid
def grid(case, run, name, kind):
    ds=yt.load(f'{MIR}/.ensemble_bay_{case}_matrix/{run}/{kind}')
    g=ds.covering_grid(0, ds.domain_left_edge, ds.domain_dimensions); return np.array(g[('boxlib',name)][:,:,0])
runs=sorted(os.path.basename(r) for r in glob.glob(f'{MIR}/.ensemble_bay_H1_mitigated_matrix/run_*'))
loads=[]; ovl=[]; exc=[]
for run in runs:
    L=[]; 
    for s in ('00060','00075','00090'):
        p=grid('H1_mitigated',run,'num_patients',f'hospital_data_{s}'); c=grid('H1_mitigated',run,'patient_capacity',f'hospital_data_{s}')
        L.append(np.where(c>0,p/np.where(c>0,c,1),np.nan))
    L=np.array(L); loads.append(np.nanmean(L,0)); ovl.append(np.nanmean(np.clip(L-1,0,None),0))
    def deaths(case):
        f=lambda n: grid(case,run,n,'plt00365'); t=f('total'); return t, t-f('never_infected')-f('immune')-f('infected')
    pop, dm = deaths('H1_mitigated'); _, da = deaths('verify_ample_mit')
    exc.append(dm-da)
load=np.nanmean(loads,0); over=np.nanmean(ovl,0); E=np.mean(exc,0)
cells['pop']=pop[cells.i,cells.j]; cells['exc']=E[cells.i,cells.j]
cap=grid('H1_mitigated',runs[0],'patient_capacity','hospital_data_00075')
hc=cells[cap[cells.i,cells.j]>0].copy(); hc['load']=load[hc.i,hc.j]; hc['over']=over[hc.i,hc.j]
hc=hc.groupby('geoid').agg(load=('load','mean'),over=('over','mean')).reset_index()
hx=np.array([cen[g].x for g in hc.geoid]); hy=np.array([cen[g].y for g in hc.geoid])
t=cells[cells['pop']>0].groupby('geoid').agg(pop=('pop','sum'),exc=('exc','sum')).reset_index()
t=t[t.geoid.isin(cen.index)]
tx=np.array([cen[g].x for g in t.geoid]); ty=np.array([cen[g].y for g in t.geoid])
near=np.argmin((tx[:,None]-hx[None,:])**2+(ty[:,None]-hy[None,:])**2,axis=1)
t['hload']=hc.load.values[near]; t['hover']=hc.over.values[near]; t['rate']=1000*t.exc/t['pop']
r,p=spearmanr(t.rate,t.hload); print('tracts %d, hospitals %d; Spearman(excess rate, nearest-hospital mean load) = %.2f (p=%.1e)'%(len(t),len(hc),r,p))
for thr in (1.0,1.5,2.0):
    m=t.hload>thr
    print('nearest-hospital mean load > %.1f: %.0f%% of residents, %.0f%% of excess deaths'%(thr,100*t['pop'][m].sum()/t['pop'].sum(),100*t.exc[m].sum()/t.exc.sum()))
q=t.hload.rank(pct=True)>=0.75
print('top quartile of tracts by hospital load: %.0f%% of residents, %.0f%% of excess deaths'%(100*t['pop'][q].sum()/t['pop'].sum(),100*t.exc[q].sum()/t.exc.sum()))
# per hospital: share of excess vs share of residents served
g=t.groupby(near).agg(pop=('pop','sum'),exc=('exc','sum')); g['load']=hc.load.values[g.index]
g=g.sort_values('load',ascending=False); top=g.head(len(g)//4)
print('top quarter of hospitals by load (%d): serve %.0f%% of residents, %.0f%% of excess deaths'%(len(top),100*top['pop'].sum()/g['pop'].sum(),100*top.exc.sum()/g.exc.sum()))
