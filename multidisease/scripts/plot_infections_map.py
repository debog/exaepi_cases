#!/usr/bin/env python
"""Plot ExaEpi infection counts on a US county map at various timesteps.

Supports both single disease and multidisease cases. For multidisease cases,
plots all diseases on the same map using transparency with different colors.

Usage:
    python plot_infections_map.py <run_directory> [options]

Examples:
    # Single disease
    python plot_infections_map.py .run_US_01D_Cov19S1_perlmutter
    python plot_infections_map.py .run_US_01D_Cov19S1_perlmutter --steps 0 10 30 50 70

    # Multidisease
    python plot_infections_map.py .run_bay_02D_Cov19S1_FluS1_tuolumne
    python plot_infections_map.py .run_bay_02D_Cov19S1_FluS1_tuolumne --outdir my_plots
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


def load_cases(run_dir, step, disease=None):
    """Load a casesNNNNN file and return a 1-D numpy array of counts.

    Args:
        run_dir: Path to run directory
        step: Timestep number
        disease: Optional disease name. If provided, looks for disease-specific file.

    Returns:
        numpy array of case counts, or None if file not found
    """
    if disease:
        # Try disease-specific file: cases_<disease>_NNNNN
        fname = os.path.join(run_dir, f"cases_{disease}_{step:05d}")
        if os.path.exists(fname):
            return np.loadtxt(fname)
        # Try disease subdirectory: <disease>/casesNNNNN
        fname = os.path.join(run_dir, disease, f"cases{step:05d}")
        if os.path.exists(fname):
            return np.loadtxt(fname)
        return None
    else:
        # Single disease: standard filename
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


def detect_run_info(run_dir):
    """Extract case name and platform from the run directory name.

    Returns:
        tuple: (case_name, platform, diseases)
        Example: .run_bay_02D_Cov19S1_FluS1_tuolumne -> ('bay_02D_Cov19S1_FluS1', 'tuolumne', ['Cov19S1', 'FluS1'])
    """
    name = os.path.basename(os.path.normpath(run_dir))
    # Remove .run_ prefix if present
    if name.startswith(".run_"):
        name = name[5:]

    # Split by underscore
    parts = name.split("_")

    # Last part is platform
    platform = parts[-1] if len(parts) > 1 else "unknown"

    # Everything before platform is case name
    case_name = "_".join(parts[:-1]) if len(parts) > 1 else name

    # Extract disease names (parts starting with Cov or Flu)
    diseases = []
    for p in parts:
        if p.startswith("Cov") or p.startswith("Flu"):
            diseases.append(p)

    return case_name, platform, diseases


def plot_step(counties_gdf, county_cases, step, case_name, platform, outdir, vmax=None):
    """Create and save a single map for one timestep (single disease)."""
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
    ax.set_aspect("equal")
    ax.set_axis_off()

    total = county_cases["cases"].sum()
    ax.set_title(
        f"{case_name} — Day {step}  (total infections: {total:,.0f})",
        fontsize=14, fontweight="bold",
    )

    outpath = os.path.join(outdir, f"infections_{case_name}_{platform}_day{step:05d}.png")
    fig.savefig(outpath, dpi=150, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    print(f"  Saved {outpath}")


def plot_multidisease_step(counties_gdf, disease_county_cases, step, case_name, platform, outdir, vmax_dict=None):
    """Create and save a map with multiple diseases overlaid using transparency.

    Args:
        counties_gdf: GeoDataFrame with county geometries
        disease_county_cases: dict mapping disease name -> DataFrame with columns [GEOID, cases]
        step: Timestep number
        case_name: Case name for title and filename
        platform: Platform name for filename
        outdir: Output directory
        vmax_dict: Optional dict mapping disease name -> vmax value
    """
    fig, ax = plt.subplots(1, 1, figsize=(14, 8))

    # Plot background (all counties)
    counties_gdf.plot(ax=ax, color="#f0f0f0", edgecolor="#cccccc", linewidth=0.2)

    # Color palette for diseases
    disease_colors = {
        'Cov19S1': '#ff4444',  # Red
        'Cov19S2': '#ff8844',  # Orange
        'FluS1': '#4444ff',    # Blue
        'FluS2': '#44ff44',    # Green
    }
    default_colors = ['#ff4444', '#4444ff', '#44ff44', '#ffaa00', '#ff44ff', '#44ffff']

    # Get ordered list of diseases
    diseases = sorted(disease_county_cases.keys())
    total_infections = {}

    # Plot each disease with transparency
    for idx, disease in enumerate(diseases):
        county_cases = disease_county_cases[disease]
        merged = counties_gdf.merge(county_cases, on="GEOID", how="left")
        merged["cases"] = merged["cases"].fillna(0)

        has_cases = merged[merged["cases"] > 0]
        if len(has_cases) == 0:
            total_infections[disease] = 0
            continue

        total_infections[disease] = county_cases["cases"].sum()

        # Get base color for this disease
        base_color = disease_colors.get(disease, default_colors[idx % len(default_colors)])

        # Create a custom colormap from white to the disease color
        from matplotlib.colors import LinearSegmentedColormap
        cmap = LinearSegmentedColormap.from_list(
            f"{disease}_cmap",
            ["#ffffff", base_color],
            N=256
        )

        # Determine vmax
        if vmax_dict and disease in vmax_dict:
            vmax = vmax_dict[disease]
        else:
            vmax = has_cases["cases"].max()

        # Plot with transparency
        norm = LogNorm(vmin=1, vmax=max(vmax, 2))
        has_cases.plot(
            ax=ax, column="cases", cmap=cmap, norm=norm,
            edgecolor=None, linewidth=0,
            alpha=0.6,
            label=f"{disease} ({total_infections[disease]:,.0f})"
        )

    ax.set_xlim(CONUS_XLIM)
    ax.set_ylim(CONUS_YLIM)
    ax.set_aspect("equal")
    ax.set_axis_off()

    # Add legend
    ax.legend(loc='lower right', fontsize=10, framealpha=0.9)

    # Title with all disease totals
    total_all = sum(total_infections.values())
    ax.set_title(
        f"{case_name} — Day {step}  (total infections: {total_all:,.0f})",
        fontsize=14, fontweight="bold",
    )

    outpath = os.path.join(outdir, f"infections_{case_name}_{platform}_day{step:05d}.png")
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
        "--per-step-vmax", action="store_true",
        help="Use a separate color scale per step instead of a global one"
    )
    args = parser.parse_args()

    run_dir = os.path.abspath(args.run_dir)
    if not os.path.isdir(run_dir):
        sys.exit(f"Error: {run_dir} is not a directory")

    # Directories
    script_dir = os.path.dirname(os.path.abspath(__file__))
    if args.outdir:
        outdir = args.outdir
    else:
        outdir = os.path.join(os.path.dirname(script_dir), "plots")
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

    # Load county shapefile (cached in scripts/ dir, not in plots/)
    counties_gdf = load_counties_shapefile(script_dir)

    # Determine case name, platform, and diseases
    case_name, platform, diseases = detect_run_info(run_dir)
    print(f"Case name: {case_name}")
    print(f"Platform: {platform}")
    print(f"Diseases: {diseases if diseases else ['single disease']}")

    is_multidisease = len(diseases) > 1

    if is_multidisease:
        # Multidisease: compute global color scale per disease
        vmax_dict = {}
        if not args.per_step_vmax and args.vmax is None:
            print("Computing global color scale per disease...")
            for disease in diseases:
                disease_max = 0
                for step in steps:
                    cases = load_cases(run_dir, step, disease=disease)
                    if cases is None:
                        continue
                    county_cases = aggregate_by_county(cases, fips_list)
                    step_max = county_cases["cases"].max()
                    if step_max > disease_max:
                        disease_max = step_max
                vmax_dict[disease] = disease_max
                print(f"  {disease} vmax: {disease_max:,.0f}")
        elif args.vmax is not None:
            # Use same vmax for all diseases
            for disease in diseases:
                vmax_dict[disease] = args.vmax

        # Generate multidisease plots
        print("Generating multidisease maps...")
        for step in steps:
            disease_county_cases = {}
            for disease in diseases:
                cases = load_cases(run_dir, step, disease=disease)
                if cases is not None:
                    disease_county_cases[disease] = aggregate_by_county(cases, fips_list)
            if disease_county_cases:
                plot_multidisease_step(
                    counties_gdf, disease_county_cases, step, case_name, platform, outdir,
                    vmax_dict=vmax_dict if vmax_dict else None
                )
    else:
        # Single disease: compute global color scale
        vmax = args.vmax
        if not args.per_step_vmax and vmax is None:
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

        # Generate single disease plots
        print("Generating maps...")
        for step in steps:
            cases = load_cases(run_dir, step)
            county_cases = aggregate_by_county(cases, fips_list)
            plot_step(counties_gdf, county_cases, step, case_name, platform, outdir, vmax=vmax)

    print("Done!")


if __name__ == "__main__":
    main()
