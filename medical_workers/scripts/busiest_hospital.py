"""Per-hospital load in every realization on the map days (H1 unmitigated day 60, mitigated day 75):
busiest-hospital range, hospitals over capacity, median and regional load. Sec 5.2 of the IDM paper."""
import numpy as np, yt, glob
yt.set_log_level(50)
MIR='/home/ghosh/Runs/remote/ExaEpi_LC/medical_workers/revision'
for case, step in (('H1_capacity','00060'),('H1_mitigated','00075')):
    mx=[];med=[];n1=[];reg=[]
    for r in sorted(glob.glob(f'{MIR}/.ensemble_bay_{case}_matrix/run_*')):
        ds=yt.load(f'{r}/hospital_data_{step}')
        g=ds.covering_grid(0, ds.domain_left_edge, ds.domain_dimensions)
        pat=np.array(g[('boxlib','num_patients')][:,:,0]); cap=np.array(g[('boxlib','patient_capacity')][:,:,0])
        m=cap>0; L=pat[m]/cap[m]; mx.append(L.max()); med.append(np.median(L)); n1.append((L>1).sum()); reg.append(pat[m].sum()/cap[m].sum())
    mx=np.array(mx)
    print(case, 'run001 max %.1f; max over runs: mean %.1f sd %.1f min %.1f max %.1f; median-hosp mean %.2f; n>1 %d-%d; regional mean %.2f' % (mx[0], mx.mean(), mx.std(), mx.min(), mx.max(), np.mean(med), min(n1), max(n1), np.mean(reg)))
