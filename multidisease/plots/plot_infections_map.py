#!/usr/bin/env python
"""Plot ExaEpi infection counts on a US county map at various timesteps.

Usage:
    python plot_infections_map.py <run_directory> [options]

Examples:
    python plot_infections_map.py .run_US_01D_Cov19S1_perlmutter
    python plot_infections_map.py .run_US_01D_Cov19S1_perlmutter --steps 0 10 30 50 70
    python plot_infections_map.py .run_US_01D_Cov19S1_perlmutter --outdir my_plots
"""

import argparse
import os
import sys
import glob

import numpy as np
import pandas as pd
import geopandas as gpd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LogNorm, Normalize


CENSUS_COUNTIES_URL = (
    "https://www2.census.gov/geo/tiger/GENZ2020/shp/cb_2020_us_county_5m.zip"
)

# Continental US bounding box
CONUS_XLIM = (-125, -66)
CONUS_YLIM = (24, 50)


def load_fips_mapping(run_dir):
    """Read US.dat and return a Series mapping location index to 5-digit FIPS string."""
    us_dat = os.path.join(run_dir, "US.dat")
    if not os.path.exists(us_dat):
        sys.exit(f"Error: {us_dat} not found")

    fips_list = []
    with open(us_dat) as f:
        f.readline()  # skip header (count of locations)
        for line in f:
            parts = line.split()
            fips_int = int(parts[3])
            fips_list.append(f"{fips_int:05d}")
    return fips_list


def load_cases(run_dir, step):
    """Load a casesNNNNN file and return a 1-D numpy array of counts."""
    fname = os.path.join(run_dir, f"cases{step:05d}")
    if not os.path.exists(fname):
        sys.exit(f"Error: {fname} not found")
    return np.loadtxt(fname)


def aggregate_by_county(cases, fips_list):
    """Sum case counts per county FIPS code. Returns a DataFrame with columns [GEOID, cases]."""
    df = pd.DataFrame({"GEOID": fips_list, "cases": cases})
    return df.groupby("GEOID", as_index=False)["cases"].sum()


def detect_steps(run_dir):
    """Auto-detect available timestep numbers from cases* files."""
    pattern = os.path.join(run_dir, "cases?????")
    files = sorted(glob.glob(pattern))
    steps = []
    for f in files:
        base = os.path.basename(f)
        try:
            steps.append(int(base.replace("cases", "")))
        except ValueError:
            continue
    return steps


def load_counties_shapefile(cache_dir):
    """Load US county shapefile, caching locally after first download."""
    cache_path = os.path.join(cache_dir, "cb_2020_us_county_5m")
    if os.path.isdir(cache_path):
        shp_files = glob.glob(os.path.join(cache_path, "*.shp"))
        if shp_files:
            return gpd.read_file(shp_files[0])

    print("Downloading US county shapefile (one-time)...")
    gdf = gpd.read_file(CENSUS_COUNTIES_URL)

    os.makedirs(cache_path, exist_ok=True)
    gdf.to_file(os.path.join(cache_path, "counties.shp"))
    print(f"Cached shapefile to {cache_path}")
    return gdf


def detect_run_label(run_dir):
    """Extract a short label from the run directory name."""
    name = os.path.basename(os.path.normpath(run_dir))
    # e.g. .run_US_01D_Cov19S1_perlmutter -> Cov19S1
    parts = name.split("_")
    for p in parts:
        if p.startswith("Cov") or p.startswith("Flu"):
            return p
    return name


def plot_step(counties_gdf, county_cases, step, run_label, outdir, vmax=None):
    """Create and save a single map for one timestep."""
    merged = counties_gdf.merge(county_cases, on="GEOID", how="left")
    merged["cases"] = merged["cases"].fillna(0)

    fig, ax = plt.subplots(1, 1, figsize=(14, 8))

    # Plot background (counties with 0 cases)
    merged[merged["cases"] == 0].plot(
        ax=ax, color="#f0f0f0", edgecolor="#cccccc", linewidth=0.2
    )

    # Plot counties with cases
    has_cases = merged[merged["cases"] > 0]
    if len(has_cases) > 0:
        if vmax is None:
            vmax = has_cases["cases"].max()
        norm = LogNorm(vmin=1, vmax=max(vmax, 2))
        has_cases.plot(
            ax=ax, column="cases", cmap="YlOrRd", norm=norm,
            edgecolor="#cccccc", linewidth=0.2, legend=True,
            legend_kwds={"label": "Infection count", "shrink": 0.6},
        )

    ax.set_xlim(CONUS_XLIM)
    ax.set_ylim(CONUS_YLIM)
    ax.set_axis_off()

    total = county_cases["cases"].sum()
    ax.set_title(
        f"{run_label} — Day {step}  (total infections: {total:,.0f})",
        fontsize=14, fontweight="bold",
    )

    outpath = os.path.join(outdir, f"infections_{run_label}_day{step:05d}.png")
    fig.savefig(outpath, dpi=150, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    print(f"  Saved {outpath}")


def main():
    parser = argparse.ArgumentParser(
        description="Plot ExaEpi infections on a US county map"
    )
    parser.add_argument("run_dir", help="Path to a .run_* simulation directory")
    parser.add_argument(
        "--steps", type=int, nargs="+", default=None,
        help="Timesteps to plot (default: 0, then every 10th, plus last)"
    )
    parser.add_argument(
        "--outdir", default=None,
        help="Output directory for PNGs (default: plots/ next to this script)"
    )
    parser.add_argument(
        "--vmax", type=float, default=None,
        help="Fixed upper limit for color scale (default: auto per step)"
    )
    parser.add_argument(
        "--global-vmax", action="store_true",
        help="Use a single color scale across all steps (max over all steps)"
    )
    args = parser.parse_args()

    run_dir = os.path.abspath(args.run_dir)
    if not os.path.isdir(run_dir):
        sys.exit(f"Error: {run_dir} is not a directory")

    # Output directory
    if args.outdir:
        outdir = args.outdir
    else:
        outdir = os.path.join(os.path.dirname(os.path.abspath(__file__)))
    os.makedirs(outdir, exist_ok=True)

    # Detect available steps
    all_steps = detect_steps(run_dir)
    if not all_steps:
        sys.exit(f"Error: no cases* files found in {run_dir}")

    if args.steps is not None:
        steps = args.steps
    else:
        # Default: 0, every 10th, and last
        steps = list(range(0, all_steps[-1] + 1, 10))
        if all_steps[-1] not in steps:
            steps.append(all_steps[-1])

    print(f"Run directory: {run_dir}")
    print(f"Timesteps to plot: {steps}")
    print(f"Output directory: {outdir}")

    # Load FIPS mapping
    print("Loading FIPS mapping from US.dat...")
    fips_list = load_fips_mapping(run_dir)
    print(f"  {len(fips_list)} locations, {len(set(fips_list))} counties")

    # Load county shapefile
    counties_gdf = load_counties_shapefile(outdir)

    # Determine run label
    run_label = detect_run_label(run_dir)

    # If global-vmax, pre-scan all steps
    vmax = args.vmax
    if args.global_vmax and vmax is None:
        print("Computing global color scale...")
        global_max = 0
        for step in steps:
            cases = load_cases(run_dir, step)
            county_cases = aggregate_by_county(cases, fips_list)
            step_max = county_cases["cases"].max()
            if step_max > global_max:
                global_max = step_max
        vmax = global_max
        print(f"  Global vmax: {vmax:,.0f}")

    # Generate plots
    print("Generating maps...")
    for step in steps:
        cases = load_cases(run_dir, step)
        county_cases = aggregate_by_county(cases, fips_list)
        plot_step(counties_gdf, county_cases, step, run_label, outdir, vmax=vmax)

    print("Done!")


if __name__ == "__main__":
    main()
