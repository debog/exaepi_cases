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


def load_cases(run_dir, step, disease=None, verbose=False):
    """Load a casesNNNNN file and return a 1-D numpy array of counts.

    Args:
        run_dir: Path to run directory
        step: Timestep number
        disease: Optional disease name. If provided, looks for disease-specific file.
        verbose: If True, print which file is loaded

    Returns:
        numpy array of case counts, or None if file not found
    """
    if disease:
        # Try disease-specific file: cases_<disease>_NNNNN
        fname = os.path.join(run_dir, f"cases_{disease}_{step:05d}")
        if os.path.exists(fname):
            data = np.loadtxt(fname)
            if verbose:
                print(f"      Loaded {os.path.basename(fname)}: sum={data.sum():,.0f}")
            return data
        # Try new format: casesNNNNN_<disease>
        fname = os.path.join(run_dir, f"cases{step:05d}_{disease}")
        if os.path.exists(fname):
            data = np.loadtxt(fname)
            if verbose:
                print(f"      Loaded {os.path.basename(fname)}: sum={data.sum():,.0f}")
            return data
        # Try disease subdirectory: <disease>/casesNNNNN
        fname = os.path.join(run_dir, disease, f"cases{step:05d}")
        if os.path.exists(fname):
            data = np.loadtxt(fname)
            if verbose:
                print(f"      Loaded {disease}/{os.path.basename(fname)}: sum={data.sum():,.0f}")
            return data
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
    steps_set = set()

    # Pattern 1: cases????? (single disease)
    pattern = os.path.join(run_dir, "cases?????")
    for f in glob.glob(pattern):
        base = os.path.basename(f)
        try:
            step = int(base.replace("cases", ""))
            steps_set.add(step)
        except ValueError:
            continue

    # Pattern 2: cases_*_????? (multidisease, disease first)
    pattern = os.path.join(run_dir, "cases_*_?????")
    for f in glob.glob(pattern):
        base = os.path.basename(f)
        try:
            # Extract last 5 digits
            step = int(base[-5:])
            steps_set.add(step)
        except ValueError:
            continue

    # Pattern 3: cases?????_* (multidisease, step first)
    pattern = os.path.join(run_dir, "cases?????_*")
    for f in glob.glob(pattern):
        base = os.path.basename(f)
        try:
            # Extract digits after "cases" and before "_"
            step = int(base[5:10])
            steps_set.add(step)
        except ValueError:
            continue

    return sorted(list(steps_set))


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


def detect_diseases_from_files(run_dir):
    """Detect diseases by examining actual case files in the directory.

    Returns:
        list: Disease names found in case files
    """
    diseases = set()

    # Check for cases?????_* format (step first)
    pattern = os.path.join(run_dir, "cases?????_*")
    for f in glob.glob(pattern):
        base = os.path.basename(f)
        if "_" in base:
            # Extract disease name after the underscore
            disease = base[11:]  # Skip "cases00000_"
            diseases.add(disease)

    # Check for cases_*_????? format (disease first)
    pattern = os.path.join(run_dir, "cases_*_?????")
    for f in glob.glob(pattern):
        base = os.path.basename(f)
        parts = base.split("_")
        if len(parts) >= 3:
            disease = parts[1]
            diseases.add(disease)

    return sorted(list(diseases))


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

    # Detect diseases from actual files in the directory
    diseases = detect_diseases_from_files(run_dir)

    return case_name, platform, diseases


def plot_step(counties_gdf, county_cases, step, case_name, platform, outdir, vmax=None, verbose=False):
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

    # Save as PNG
    outpath_png = os.path.join(outdir, f"infections_{case_name}_{platform}_day{step:05d}.png")
    fig.savefig(outpath_png, dpi=150, bbox_inches="tight", facecolor="white")

    # Save as PDF for LaTeX documents
    outpath_pdf = os.path.join(outdir, f"infections_{case_name}_{platform}_day{step:05d}.pdf")
    fig.savefig(outpath_pdf, bbox_inches="tight", facecolor="white")

    plt.close(fig)
    if verbose:
        print(f"    Saved {outpath_png}")
        print(f"    Saved {outpath_pdf}")


def plot_multidisease_step(counties_gdf, disease_county_cases, step, case_name, platform, outdir, vmax_dict=None, verbose=False):
    """Create and save a map with multiple diseases in separate subplots.

    Args:
        counties_gdf: GeoDataFrame with county geometries
        disease_county_cases: dict mapping disease name -> DataFrame with columns [GEOID, cases]
        step: Timestep number
        case_name: Case name for title and filename
        platform: Platform name for filename
        outdir: Output directory
        vmax_dict: Optional dict mapping disease name -> vmax value
    """
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
    n_diseases = len(diseases)
    total_infections = {}

    # Determine subplot layout
    if n_diseases <= 2:
        nrows, ncols = 1, n_diseases
        figsize = (7 * ncols, 4.5)
    elif n_diseases <= 4:
        nrows, ncols = 2, 2
        figsize = (14, 9)
    else:
        ncols = 3
        nrows = (n_diseases + ncols - 1) // ncols
        figsize = (7 * ncols, 4.5 * nrows)

    fig, axes = plt.subplots(nrows, ncols, figsize=figsize)

    # Ensure axes is always a flat array
    if n_diseases == 1:
        axes = [axes]
    else:
        axes = axes.flatten()

    # Plot each disease in its own subplot
    for idx, disease in enumerate(diseases):
        ax = axes[idx]
        county_cases = disease_county_cases[disease]
        merged = counties_gdf.merge(county_cases, on="GEOID", how="left")
        merged["cases"] = merged["cases"].fillna(0)

        # Plot background (counties with 0 cases)
        merged[merged["cases"] == 0].plot(
            ax=ax, color="#f0f0f0", edgecolor="#cccccc", linewidth=0.2
        )

        has_cases = merged[merged["cases"] > 0]
        total_infections[disease] = county_cases["cases"].sum()

        if len(has_cases) > 0:
            # Get base color for this disease
            base_color = disease_colors.get(disease, default_colors[idx % len(default_colors)])

            # Determine vmax
            if vmax_dict and disease in vmax_dict:
                vmax = vmax_dict[disease]
            else:
                vmax = has_cases["cases"].max()

            # Plot with standard colormap
            norm = LogNorm(vmin=1, vmax=max(vmax, 2))
            has_cases.plot(
                ax=ax, column="cases", cmap="YlOrRd", norm=norm,
                edgecolor="#cccccc", linewidth=0.2, legend=True,
                legend_kwds={"label": "Infections", "shrink": 0.6}
            )

        ax.set_xlim(CONUS_XLIM)
        ax.set_ylim(CONUS_YLIM)
        ax.set_aspect("equal")
        ax.set_axis_off()
        ax.set_title(f"{disease}: {total_infections[disease]:,.0f} infections",
                     fontsize=12, fontweight="bold")

    # Hide unused subplots
    for idx in range(n_diseases, len(axes)):
        axes[idx].axis('off')

    # Overall title
    total_all = sum(total_infections.values())
    fig.suptitle(
        f"{case_name} — Day {step}  (total infections: {total_all:,.0f})",
        fontsize=16, fontweight="bold", y=0.98
    )

    # Adjust layout
    plt.tight_layout(rect=[0, 0, 1, 0.96])

    # Save as PNG
    outpath_png = os.path.join(outdir, f"infections_{case_name}_{platform}_day{step:05d}.png")
    fig.savefig(outpath_png, dpi=150, bbox_inches="tight", facecolor="white")

    # Save as PDF for LaTeX documents
    outpath_pdf = os.path.join(outdir, f"infections_{case_name}_{platform}_day{step:05d}.pdf")
    fig.savefig(outpath_pdf, bbox_inches="tight", facecolor="white")

    plt.close(fig)
    if verbose:
        print(f"    Saved {outpath_png}")
        print(f"    Saved {outpath_pdf}")


def detect_platform():
    """Detect the current platform from environment variables."""
    import socket

    # Check for LLNL systems (LCHOST environment variable)
    lchost = os.environ.get("LCHOST", "").lower()
    if lchost:
        return lchost

    # Check for NERSC systems
    if os.environ.get("NERSC_HOST"):
        return "perlmutter"

    # Check for GPU availability on Linux
    try:
        import subprocess
        result = subprocess.run(["nvidia-smi"], capture_output=True, timeout=2)
        if result.returncode == 0:
            return "linux-gpu"
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    # Default to generic Linux
    return "linux"


def find_run_directories(platform=None):
    """Find all .run_* directories, optionally filtering by platform.

    Returns list of (run_dir_path, case_name, dir_platform) tuples.
    """
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.abspath(os.path.join(script_dir, ".."))

    run_dirs = []
    pattern = os.path.join(project_dir, ".run_*")

    for run_dir in glob.glob(pattern):
        if not os.path.isdir(run_dir):
            continue

        basename = os.path.basename(run_dir)
        # Extract case_name and platform from .run_<case_name>_<platform>
        if basename.startswith(".run_"):
            name_parts = basename[5:].split("_")
            dir_platform = name_parts[-1] if len(name_parts) > 1 else "unknown"
            case_name = "_".join(name_parts[:-1]) if len(name_parts) > 1 else basename[5:]

            # Filter by platform if specified
            if platform and dir_platform != platform:
                continue

            # Check for cases* files (multiple formats)
            if glob.glob(os.path.join(run_dir, "cases?????")) or \
               glob.glob(os.path.join(run_dir, "cases_*_?????")) or \
               glob.glob(os.path.join(run_dir, "cases?????_*")):
                run_dirs.append((run_dir, case_name, dir_platform))

    return sorted(run_dirs, key=lambda x: x[1])


def list_cases(platform=None):
    """List all available cases with cases* files."""
    run_dirs = find_run_directories(platform)

    if not run_dirs:
        if platform:
            print(f"No cases with cases* files found for platform: {platform}")
        else:
            print("No cases with cases* files found")
        print("Run simulations first using run_exaepi.sh")
        return

    if platform:
        print(f"Available cases with cases* files for platform: {platform}\n")
    else:
        print("Available cases with cases* files (all platforms):\n")

    for run_dir, case_name, dir_platform in run_dirs:
        print(f"  {case_name}_{dir_platform}")
        print(f"    Directory: {run_dir}")

        # Count cases files (check multiple formats)
        cases_files = glob.glob(os.path.join(run_dir, "cases?????"))
        disease_cases_old = glob.glob(os.path.join(run_dir, "cases_*_?????"))
        disease_cases_new = glob.glob(os.path.join(run_dir, "cases?????_*"))
        disease_cases = disease_cases_old + disease_cases_new

        if disease_cases:
            # Extract unique disease names
            diseases = set()
            for f in disease_cases:
                basename = os.path.basename(f)
                if "_" in basename:
                    # Try format: cases_<disease>_NNNNN
                    parts = basename.split("_")
                    if len(parts) >= 3 and parts[0] == "cases":
                        diseases.add(parts[1])
                    # Try format: casesNNNNN_<disease>
                    elif len(parts) >= 2 and parts[0].startswith("cases"):
                        disease = "_".join(parts[1:])
                        diseases.add(disease)
            print(f"    Diseases: {', '.join(sorted(diseases))}")
            print(f"    Cases files: {len(disease_cases)} (multidisease)")
        elif cases_files:
            print(f"    Cases files: {len(cases_files)}")

        # Get timestep range
        all_case_files = cases_files + disease_cases
        if all_case_files:
            steps = []
            for f in all_case_files:
                basename = os.path.basename(f)
                try:
                    # Extract step number (last 5 digits)
                    step = int(basename[-5:])
                    steps.append(step)
                except ValueError:
                    pass
            if steps:
                print(f"    Timesteps: {min(steps)} to {max(steps)}")
        print()

    print(f"Total: {len(run_dirs)} case(s) with cases* files")


def main():
    parser = argparse.ArgumentParser(
        description="Plot ExaEpi infections on a US county map",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Plot specific case
  %(prog)s -c bay_01D_Cov19S1

  # Plot multiple cases
  %(prog)s -c bay_01D_Cov19S1 CA_01D_Cov19S1

  # Plot all cases for current platform
  %(prog)s -a

  # List available cases
  %(prog)s -l

  # Specify timesteps
  %(prog)s -c US_01D_Cov19S1 --steps 0 10 30 50 70

Output:
  Maps saved to plots/ directory with naming:
    infections_<case_name>_<platform>_day<step>.png
"""
    )

    # Main arguments
    parser.add_argument(
        "-c", "--case", dest="cases", action="append", default=[],
        help="Plot specific case(s) (can be specified multiple times)"
    )
    parser.add_argument(
        "-a", "--all", action="store_true",
        help="Plot all available cases for current/specified platform"
    )
    parser.add_argument(
        "-l", "--list-cases", action="store_true",
        help="List available cases with cases* files"
    )

    # Options
    parser.add_argument(
        "-P", "--platform", default=None,
        help="Specify platform (default: auto-detect)"
    )
    parser.add_argument(
        "--steps", type=int, nargs="+", default=None,
        help="Timesteps to plot (default: 0, then every 10th, plus last)"
    )
    parser.add_argument(
        "--outdir", default=None,
        help="Output directory for PNGs (default: plots/)"
    )
    parser.add_argument(
        "--vmax", type=float, default=None,
        help="Fixed upper limit for color scale (default: auto per step)"
    )
    parser.add_argument(
        "--per-step-vmax", action="store_true",
        help="Use a separate color scale per step instead of a global one"
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true",
        help="Enable verbose output"
    )

    args = parser.parse_args()

    # Detect platform if not specified
    platform = args.platform or detect_platform()

    # Handle --list-cases
    if args.list_cases:
        list_cases(platform)
        return

    # Determine which cases to plot
    if args.all:
        run_dirs = find_run_directories(platform)
        if not run_dirs:
            print(f"ERROR: No cases found for platform: {platform}")
            sys.exit(1)
        cases_to_plot = [(rd, cn, dp) for rd, cn, dp in run_dirs]
    elif args.cases:
        cases_to_plot = []
        for case_spec in args.cases:
            # Check if case_spec includes platform
            if "_" in case_spec:
                parts = case_spec.split("_")
                possible_platform = parts[-1]
                # Try as full name first
                run_dirs = find_run_directories()
                found = False
                for rd, cn, dp in run_dirs:
                    if f"{cn}_{dp}" == case_spec or cn == case_spec:
                        cases_to_plot.append((rd, cn, dp))
                        found = True
                        break

                if not found:
                    print(f"ERROR: Case not found: {case_spec}")
                    sys.exit(1)
            else:
                # Try with detected platform
                run_dirs = find_run_directories(platform)
                found = False
                for rd, cn, dp in run_dirs:
                    if cn == case_spec:
                        cases_to_plot.append((rd, cn, dp))
                        found = True
                        break

                if not found:
                    print(f"ERROR: Case not found: {case_spec} for platform {platform}")
                    sys.exit(1)
    else:
        parser.print_help()
        sys.exit(0)

    # Directories
    script_dir = os.path.dirname(os.path.abspath(__file__))
    if args.outdir:
        outdir = args.outdir
    else:
        outdir = os.path.join(os.path.dirname(script_dir), "plots")
    os.makedirs(outdir, exist_ok=True)

    print(f"Platform: {platform}")
    print(f"Output directory: {outdir}")
    print(f"Cases to plot: {len(cases_to_plot)}")
    print()

    # Load county shapefile once (cached in scripts/ dir)
    counties_gdf = load_counties_shapefile(script_dir)

    # Process each case
    for run_dir, case_name, dir_platform in cases_to_plot:
        print(f"Processing case: {case_name}_{dir_platform}")
        process_case(run_dir, case_name, dir_platform, counties_gdf, outdir, args, script_dir)
        print()

    print("Done!")


def process_case(run_dir, case_name, dir_platform, counties_gdf, outdir, args, script_dir):
    """Process a single case and generate all requested plots."""
    if not os.path.isdir(run_dir):
        print(f"  ERROR: {run_dir} is not a directory")
        return

    # Detect available steps
    all_steps = detect_steps(run_dir)
    if not all_steps:
        print(f"  ERROR: no cases* files found in {run_dir}")
        return

    if args.steps is not None:
        steps = args.steps
    else:
        # Default: 0, every 10th, and last
        steps = list(range(0, all_steps[-1] + 1, 10))
        if all_steps[-1] not in steps:
            steps.append(all_steps[-1])

    if args.verbose:
        print(f"  Run directory: {run_dir}")
        print(f"  Timesteps to plot: {steps}")

    # Load FIPS mapping
    if args.verbose:
        print("  Loading FIPS mapping from US.dat...")
    fips_list = load_fips_mapping(run_dir)
    if args.verbose:
        print(f"    {len(fips_list)} locations, {len(set(fips_list))} counties")

    # Determine diseases
    _, _, diseases = detect_run_info(run_dir)
    if args.verbose:
        print(f"  Diseases: {diseases if diseases else ['single disease']}")

    is_multidisease = len(diseases) > 1
    platform = dir_platform  # Use the platform from directory name

    if is_multidisease:
        # Multidisease: compute global color scale per disease
        vmax_dict = {}
        if not args.per_step_vmax and args.vmax is None:
            if args.verbose:
                print("  Computing global color scale per disease...")
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
                if args.verbose:
                    print(f"    {disease} vmax: {disease_max:,.0f}")
        elif args.vmax is not None:
            # Use same vmax for all diseases
            for disease in diseases:
                vmax_dict[disease] = args.vmax

        # Generate multidisease plots
        if args.verbose:
            print("  Generating multidisease maps...")
        for step in steps:
            disease_county_cases = {}
            if args.verbose:
                print(f"    Loading data for step {step}...")
            for disease in diseases:
                cases = load_cases(run_dir, step, disease=disease, verbose=args.verbose)
                if cases is not None:
                    disease_county_cases[disease] = aggregate_by_county(cases, fips_list)
                    if args.verbose:
                        total = disease_county_cases[disease]["cases"].sum()
                        print(f"      {disease}: {total:,.0f} total cases")
                elif args.verbose:
                    print(f"      {disease}: file not found")
            if disease_county_cases:
                plot_multidisease_step(
                    counties_gdf, disease_county_cases, step, case_name, platform, outdir,
                    vmax_dict=vmax_dict if vmax_dict else None, verbose=args.verbose
                )
    else:
        # Single disease: compute global color scale
        vmax = args.vmax
        if not args.per_step_vmax and vmax is None:
            if args.verbose:
                print("  Computing global color scale...")
            global_max = 0
            for step in steps:
                cases = load_cases(run_dir, step)
                county_cases = aggregate_by_county(cases, fips_list)
                step_max = county_cases["cases"].max()
                if step_max > global_max:
                    global_max = step_max
            vmax = global_max
            if args.verbose:
                print(f"    Global vmax: {vmax:,.0f}")

        # Generate single disease plots
        if args.verbose:
            print("  Generating maps...")
        for step in steps:
            cases = load_cases(run_dir, step)
            county_cases = aggregate_by_county(cases, fips_list)
            plot_step(counties_gdf, county_cases, step, case_name, platform, outdir, vmax=vmax, verbose=args.verbose)


if __name__ == "__main__":
    main()
