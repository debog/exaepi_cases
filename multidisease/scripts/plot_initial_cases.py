#!/usr/bin/env python
"""Plot initial case seed files on a US county map.

Reads .cases files from the data/ directory and plots each disease's initial
case distribution on a county choropleth map.

Usage:
    python plot_initial_cases.py                  # Plot all .cases files
    python plot_initial_cases.py Jan1_FluS1.cases # Plot specific file(s)
    python plot_initial_cases.py --combined       # All diseases on one figure
"""

import argparse
import glob
import os
import sys

import numpy as np
import pandas as pd
import geopandas as gpd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LogNorm, Normalize
from matplotlib.colors import LinearSegmentedColormap

CENSUS_COUNTIES_URL = (
    "https://www2.census.gov/geo/tiger/GENZ2020/shp/cb_2020_us_county_5m.zip"
)

REGION_BOUNDS = {
    'US': {'xlim': (-125, -66), 'ylim': (24, 50)},
}

# Disease display names and colors
DISEASE_INFO = {
    'Cov19S1': {'label': 'SARS-CoV-2 Ancestral', 'color': '#cc3333'},
    'Cov19S2': {'label': 'SARS-CoV-2 Delta',     'color': '#ff7733'},
    'FluS1':   {'label': 'Influenza A/H3N2',      'color': '#3366cc'},
    'FluS2':   {'label': 'Influenza A/H1N1pdm09', 'color': '#33aa33'},
    'PneuS1':  {'label': 'S. pneumoniae',          'color': '#9933cc'},
}

DEFAULT_COLORS = ['#cc3333', '#3366cc', '#33aa33', '#ff7733', '#9933cc']


def load_case_file(filepath):
    """Read a .cases file and return a DataFrame with columns [GEOID, cases].

    Args:
        filepath: Path to .cases file (FIPS_code num_cases per line)

    Returns:
        DataFrame with GEOID (5-digit string) and cases (int) columns
    """
    fips_list = []
    cases_list = []
    with open(filepath) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split()
            if len(parts) >= 2:
                fips_list.append(f"{int(parts[0]):05d}")
                cases_list.append(int(parts[1]))
    return pd.DataFrame({'GEOID': fips_list, 'cases': cases_list})


def extract_disease_name(filename):
    """Extract disease name from case filename (e.g., Jan1_FluS1.cases -> FluS1)."""
    base = os.path.splitext(os.path.basename(filename))[0]
    # Try to find known disease names
    for disease in DISEASE_INFO:
        if disease in base:
            return disease
    # Fall back to everything after last underscore
    parts = base.split('_')
    return parts[-1] if len(parts) > 1 else base


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


def plot_single(counties_gdf, case_df, disease, outdir, verbose=False):
    """Plot a single disease's initial cases on a US map."""
    info = DISEASE_INFO.get(disease, {})
    color = info.get('color', '#cc3333')
    label = info.get('label', disease)
    cmap = LinearSegmentedColormap.from_list(f'{disease}_cmap', ['#ffffcc', color])

    merged = counties_gdf.merge(case_df, on="GEOID", how="left")
    merged["cases"] = merged["cases"].fillna(0)

    fig, ax = plt.subplots(1, 1, figsize=(14, 8))

    # Background counties
    merged[merged["cases"] == 0].plot(
        ax=ax, color="#f0f0f0", edgecolor="#cccccc", linewidth=0.2
    )

    # Counties with cases
    has_cases = merged[merged["cases"] > 0]
    if len(has_cases) > 0:
        vmax = has_cases["cases"].max()
        norm = Normalize(vmin=0, vmax=max(vmax, 2))
        has_cases.plot(
            ax=ax, column="cases", cmap=cmap, norm=norm,
            edgecolor="#444444", linewidth=0.5, legend=True,
            legend_kwds={"label": "Initial cases", "shrink": 0.6},
        )

    bounds = REGION_BOUNDS['US']
    ax.set_xlim(bounds['xlim'])
    ax.set_ylim(bounds['ylim'])
    ax.set_aspect("equal")
    ax.set_axis_off()

    total = case_df["cases"].sum()
    n_counties = len(case_df)
    ax.set_title(
        f"{label} — Initial Cases\n"
        f"{total:,} cases across {n_counties} counties "
        f"({total / 330e6 * 1e6:.1f} per million)",
        fontsize=14, fontweight="bold",
    )

    outpath = os.path.join(outdir, f"initial_cases_{disease}.png")
    fig.savefig(outpath, dpi=150, bbox_inches="tight", facecolor="white")
    outpath_pdf = os.path.join(outdir, f"initial_cases_{disease}.pdf")
    fig.savefig(outpath_pdf, bbox_inches="tight", facecolor="white")
    plt.close(fig)

    if verbose:
        print(f"  Saved {outpath}")
        print(f"  Saved {outpath_pdf}")


def plot_combined(counties_gdf, all_cases, outdir, verbose=False):
    """Plot all diseases' initial cases in a single multi-panel figure."""
    diseases = sorted(all_cases.keys())
    n = len(diseases)

    if n <= 2:
        nrows, ncols = 1, n
        figsize = (7 * ncols, 5)
    elif n <= 4:
        nrows, ncols = 2, 2
        figsize = (14, 10)
    else:
        ncols = 3
        nrows = (n + ncols - 1) // ncols
        figsize = (7 * ncols, 5 * nrows)

    fig, axes = plt.subplots(nrows, ncols, figsize=figsize)
    if n == 1:
        axes = [axes]
    else:
        axes = axes.flatten()

    for idx, disease in enumerate(diseases):
        ax = axes[idx]
        case_df = all_cases[disease]
        info = DISEASE_INFO.get(disease, {})
        color = info.get('color', DEFAULT_COLORS[idx % len(DEFAULT_COLORS)])
        label = info.get('label', disease)
        cmap = LinearSegmentedColormap.from_list(f'{disease}_cmap', ['#ffffcc', color])

        merged = counties_gdf.merge(case_df, on="GEOID", how="left")
        merged["cases"] = merged["cases"].fillna(0)

        # Background
        merged[merged["cases"] == 0].plot(
            ax=ax, color="#f0f0f0", edgecolor="#cccccc", linewidth=0.2
        )

        # Cases
        has_cases = merged[merged["cases"] > 0]
        if len(has_cases) > 0:
            vmax = has_cases["cases"].max()
            norm = Normalize(vmin=0, vmax=max(vmax, 2))
            has_cases.plot(
                ax=ax, column="cases", cmap=cmap, norm=norm,
                edgecolor="#444444", linewidth=0.5, legend=True,
                legend_kwds={"label": "Cases", "shrink": 0.5},
            )

        bounds = REGION_BOUNDS['US']
        ax.set_xlim(bounds['xlim'])
        ax.set_ylim(bounds['ylim'])
        ax.set_aspect("equal")
        ax.set_axis_off()

        total = case_df["cases"].sum()
        n_counties = len(case_df)
        ax.set_title(
            f"{label}\n{total:,} cases, {n_counties} counties",
            fontsize=11, fontweight="bold",
        )

    # Hide unused subplots
    for idx in range(n, len(axes)):
        axes[idx].axis('off')

    fig.suptitle("Initial Case Seeding — US Simulations",
                 fontsize=16, fontweight="bold", y=0.98)
    plt.tight_layout(rect=[0, 0, 1, 0.95])

    outpath = os.path.join(outdir, "initial_cases_combined.png")
    fig.savefig(outpath, dpi=150, bbox_inches="tight", facecolor="white")
    outpath_pdf = os.path.join(outdir, "initial_cases_combined.pdf")
    fig.savefig(outpath_pdf, bbox_inches="tight", facecolor="white")
    plt.close(fig)

    if verbose:
        print(f"  Saved {outpath}")
        print(f"  Saved {outpath_pdf}")


def main():
    parser = argparse.ArgumentParser(
        description="Plot initial case seed files on a US county map",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                           # Plot all .cases files individually
  %(prog)s --combined                # All diseases on one figure
  %(prog)s Jan1_FluS1.cases          # Plot specific file
  %(prog)s --datadir /path/to/data   # Specify data directory
"""
    )
    parser.add_argument(
        "files", nargs="*", default=[],
        help="Specific .cases files to plot (default: all in data/)"
    )
    parser.add_argument(
        "--datadir", default=None,
        help="Directory containing .cases files (default: data/)"
    )
    parser.add_argument(
        "--outdir", default=None,
        help="Output directory for plots (default: plots/)"
    )
    parser.add_argument(
        "--combined", action="store_true",
        help="Generate a combined multi-panel plot of all diseases"
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true",
        help="Enable verbose output"
    )
    args = parser.parse_args()

    # Resolve directories
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.abspath(os.path.join(script_dir, ".."))

    if args.datadir:
        datadir = args.datadir
    else:
        datadir = os.path.join(project_dir, "data")

    if args.outdir:
        outdir = args.outdir
    else:
        outdir = os.path.join(project_dir, "plots")
    os.makedirs(outdir, exist_ok=True)

    # Find case files
    if args.files:
        case_files = []
        for f in args.files:
            path = f if os.path.isabs(f) else os.path.join(datadir, f)
            if os.path.exists(path):
                case_files.append(path)
            else:
                print(f"Warning: {path} not found, skipping")
    else:
        case_files = sorted(glob.glob(os.path.join(datadir, "*.cases")))

    if not case_files:
        print(f"No .cases files found in {datadir}")
        sys.exit(1)

    print(f"Data directory: {datadir}")
    print(f"Output directory: {outdir}")
    print(f"Case files: {len(case_files)}")
    print()

    # Load county shapefile
    counties_gdf = load_counties_shapefile(script_dir)

    # Load all case data
    all_cases = {}
    for filepath in case_files:
        disease = extract_disease_name(filepath)
        case_df = load_case_file(filepath)
        total = case_df["cases"].sum()
        n_counties = len(case_df)
        print(f"  {os.path.basename(filepath)}: {disease} — "
              f"{total:,} cases across {n_counties} counties")
        all_cases[disease] = case_df
    print()

    # Generate individual plots
    print("Generating individual plots...")
    for disease, case_df in sorted(all_cases.items()):
        info = DISEASE_INFO.get(disease, {})
        label = info.get('label', disease)
        print(f"  Plotting {label}...")
        plot_single(counties_gdf, case_df, disease, outdir, verbose=args.verbose)

    # Generate combined plot
    if args.combined or len(all_cases) > 1:
        print("Generating combined plot...")
        plot_combined(counties_gdf, all_cases, outdir, verbose=args.verbose)

    print("\nDone!")


if __name__ == "__main__":
    main()
