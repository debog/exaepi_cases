#!/usr/bin/env python3
"""Per-hospital nosocomial heterogeneity, controlling for hospital size.

For one run, per hospital cell:
  nosocomial      = cumulative hospital_acquired (final plotfile), per disease + total
  patient_days    = sum over snapshots of num_patients * plot_int  (exposure)
  load_pweighted  = patient-day-weighted mean load (crowding a typical patient sees)
  rate            = nosocomial / patient_days   (per-patient-day nosocomial hazard)
Then asks whether the per-patient-day rate rises with crowding (load), which the
raw count cannot show because count tracks hospital size.
Usage: python3 nosocomial_heterogeneity.py run_dir [plot_int]
"""
import sys, os, glob
import numpy as np
import yt
yt.set_log_level(50)

def cg(ds, name):
    g = ds.covering_grid(level=0, left_edge=ds.domain_left_edge, dims=ds.domain_dimensions)
    return np.asarray(g["boxlib", name]).squeeze()

def spearman(x, y):
    rx = np.argsort(np.argsort(x)).astype(float)
    ry = np.argsort(np.argsort(y)).astype(float)
    return np.corrcoef(rx, ry)[0, 1]

def main(run_dir, plot_int=15):
    plts = sorted(p for p in glob.glob(os.path.join(run_dir, "plt[0-9]*"))
                  if os.path.isdir(p) and ".old." not in p)
    ds = yt.load(plts[-1])
    fields = [f[1] for f in ds.field_list]
    ha = {f.replace("_hospital_acquired", ""): cg(ds, f)
          for f in fields if f.endswith("_hospital_acquired")}
    noso = sum(ha.values())

    hds = sorted(h for h in glob.glob(os.path.join(run_dir, "hospital_data_*"))
                 if os.path.isdir(h) and ".old." not in h)
    pdays = None; pl_w = None; npat_w = None; cap = None; peak = None
    for h in hds:
        d = yt.load(h)
        n = cg(d, "num_patients"); l = cg(d, "hospital_load"); c = cg(d, "patient_capacity")
        pdays = n*plot_int if pdays is None else pdays + n*plot_int
        pl_w  = l*n if pl_w is None else pl_w + l*n           # patient-weighted load numerator
        cap   = c if cap is None else np.maximum(cap, c)
        peak  = l if peak is None else np.maximum(peak, l)
    hosp = (cap > 0) & (pdays > 0)
    load_pw = np.where(pdays > 0, pl_w / np.maximum(pdays/plot_int, 1e-9), 0.0)  # patient-weighted mean load

    n = noso[hosp]; pd = pdays[hosp]; lw = load_pw[hosp]; pk = peak[hosp]
    rate = n / pd
    print(f"== {run_dir} ==  ({hosp.sum()} hospitals)")
    print(f"  total nosocomial {noso.sum():.0f}  per-disease " +
          "  ".join(f"{k} {v[hosp].sum():.0f}" for k, v in ha.items()))
    print(f"  patient-weighted mean load: min {lw.min():.2f}  median {np.median(lw):.2f}  max {lw.max():.2f}")
    print(f"  nosocomial / patient-day:   min {rate.min():.4f}  median {np.median(rate):.4f}  max {rate.max():.4f}")
    print(f"  Spearman( load , nosocomial COUNT ) = {spearman(lw, n):.2f}   (count tracks size)")
    print(f"  Spearman( load , nosocomial RATE  ) = {spearman(lw, rate):.2f}   (rate vs crowding)")
    print(f"  Spearman( patient-days , count )    = {spearman(pd, n):.2f}   (size check)")
    # tertiles of load: per-patient-day rate by crowding
    q = np.quantile(lw, [1/3, 2/3])
    lo, mid, hi = lw <= q[0], (lw > q[0]) & (lw <= q[1]), lw > q[1]
    print(f"  rate by load tertile:  low-load {np.median(rate[lo]):.4f}   mid {np.median(rate[mid]):.4f}   high-load {np.median(rate[hi]):.4f}")
    rates = {k: v[hosp] / pd for k, v in ha.items()}
    for k, r in rates.items():
        print(f"  {k}: Spearman( load , rate ) = {spearman(lw, r):.2f}   rate by load tertile:  "
              f"{np.median(r[lo]):.4f}  {np.median(r[mid]):.4f}  {np.median(r[hi]):.4f}")
    if len(rates) == 2:
        a, b = rates.values()
        ca, cb = (v[hosp] for v in ha.values())
        print(f"  Spearman( count of one disease , count of the other ) = {spearman(ca, cb):.2f}")
        print(f"  Spearman( rate of one disease , rate of the other ) = {spearman(a, b):.2f}")

if __name__ == "__main__":
    main(sys.argv[1],
         int(sys.argv[2]) if len(sys.argv) > 2 else 15)
