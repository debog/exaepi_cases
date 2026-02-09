#!/bin/bash
#
# plot.sh - ExaEpi plotting script for multidisease simulations
#
# This script creates plots from ExaEpi output.dat files showing infections,
# deaths, and hospitalizations over time.
#

set -e  # Exit on error

# Color output for terminal
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Script directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLOTS_DIR="${PROJECT_DIR}/plots"

# Default values
CASE_NAME=""
PLOT_ALL=false
VERBOSE=false
OUTPUT_FORMAT="both"  # eps, png, or both
PLATFORM=""
ENSEMBLE=false

#------------------------------------------------------------------------------
# Helper functions
#------------------------------------------------------------------------------

print_error() {
    echo -e "${RED}ERROR:${NC} $*" >&2
}

print_warning() {
    echo -e "${YELLOW}WARNING:${NC} $*" >&2
}

print_info() {
    echo -e "${BLUE}INFO:${NC} $*"
}

print_success() {
    echo -e "${GREEN}SUCCESS:${NC} $*"
}

print_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[VERBOSE]${NC} $*" >&2
    fi
}

show_help() {
    cat << EOF
ExaEpi Plotting Script

Usage:
  ./plot.sh [OPTIONS]

Options:
  -c, --case=NAME       Plot specific case (run directory name without .run_ prefix)
  -a, --all             Plot all available cases for the current/specified platform
  -e, --ensemble        Plot ensemble results (from .ensemble_ directories)
  -P, --platform=NAME   Specify platform (default: auto-detect)
  -f, --format=FMT      Output format: eps, png, or both (default: both)
  -l, --list-cases      List available cases with output data
  -v, --verbose         Enable verbose output
  -h, --help            Show this help message

Environment:
  LCHOST               Platform identifier (auto-detected)

Examples:
  # Plot specific case
  ./plot.sh --case=bay_01D_Cov19S1_dane

  # Plot all cases
  ./plot.sh --all

  # Generate only PNG files
  ./plot.sh --case=CA_01D_Cov19S1_dane --format=png

  # Plot ensemble results
  ./plot.sh --case=bay_01D_Cov19S1 --ensemble

  # List available cases
  ./plot.sh --list-cases

Output:
  For each case, generates plots in the plots/ directory with naming:
    <case>_infections_<platform>.png/eps      : New infections over time
    <case>_deaths_<platform>.png/eps          : Cumulative deaths over time
    <case>_hospitalizations_<platform>.png/eps : Hospital admissions and ICU

  For multi-disease cases:
    <case>_<disease>_infections_<platform>.png/eps
    <case>_<disease>_deaths_<platform>.png/eps
    <case>_<disease>_hospitalizations_<platform>.png/eps

  For ensemble results:
    <case>_ensemble_infections_<platform>.png/eps      : Mean with min/max band
    <case>_ensemble_deaths_<platform>.png/eps           : Mean with min/max band
    <case>_ensemble_hospitalizations_<platform>.png/eps : Mean with min/max band

EOF
}

detect_platform() {
    # Check for LLNL systems (LCHOST environment variable)
    if [[ -n "${LCHOST}" ]]; then
        local lchost_lower=$(echo "${LCHOST}" | tr '[:upper:]' '[:lower:]')
        echo "${lchost_lower}"
        return 0
    fi

    # Check for NERSC systems
    if [[ -n "${NERSC_HOST}" ]]; then
        echo "perlmutter"
        return 0
    fi

    # Check for GPU availability on Linux
    if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
        echo "linux-gpu"
        return 0
    fi

    # Default to generic Linux or desktop
    if command -v mpirun &> /dev/null || command -v mpiexec &> /dev/null; then
        echo "linux"
    else
        echo "desktop"
    fi
}

get_all_run_dirs() {
    # Return list of all run directories for specified platform
    local platform="$1"

    if [[ ! -d "${PROJECT_DIR}" ]]; then
        return 1
    fi

    for run_dir in "${PROJECT_DIR}"/.run_*; do
        if [[ -d "$run_dir" ]]; then
            local basename=$(basename "$run_dir")
            # Check if this run dir matches the platform
            if [[ -n "$platform" ]]; then
                # Extract platform from directory name: .run_<case>_<platform>
                local dir_platform="${basename##*_}"
                if [[ "$dir_platform" == "$platform" ]]; then
                    echo "$basename"
                fi
            else
                echo "$basename"
            fi
        fi
    done
}

list_cases() {
    local platform="$1"

    if [[ -n "$platform" ]]; then
        echo "Available cases with output data for platform: ${platform}"
    else
        echo "Available cases with output data (all platforms):"
    fi
    echo ""

    local count=0
    for run_dir in "${PROJECT_DIR}"/.run_*; do
        if [[ -d "$run_dir" ]]; then
            local basename=$(basename "$run_dir")
            local case_display="${basename#.run_}"

            # Filter by platform if specified
            if [[ -n "$platform" ]]; then
                local dir_platform="${basename##*_}"
                if [[ "$dir_platform" != "$platform" ]]; then
                    continue
                fi
            fi

            # Check for output files
            local output_files=()
            if [[ -f "${run_dir}/output.dat" ]]; then
                output_files+=("output.dat")
            fi
            for f in "${run_dir}"/output_*.dat; do
                if [[ -f "$f" ]]; then
                    output_files+=("$(basename "$f")")
                fi
            done

            if [[ ${#output_files[@]} -gt 0 ]]; then
                echo "  ${case_display}"
                echo "    Directory: ${run_dir}"
                echo "    Output files: ${output_files[@]}"

                # Try to get line count (timesteps)
                local nlines=$(wc -l < "${run_dir}/${output_files[0]}" 2>/dev/null || echo "0")
                local nsteps=$((nlines - 1))  # Subtract header
                if [[ $nsteps -gt 0 ]]; then
                    echo "    Timesteps: ${nsteps}"
                fi
                echo ""
                count=$((count + 1))
            fi
        fi
    done

    if [[ $count -eq 0 ]]; then
        if [[ -n "$platform" ]]; then
            print_warning "No cases with output data found for platform: ${platform}"
        else
            print_warning "No cases with output data found"
        fi
        echo "Run simulations first using run_exaepi.sh"
        return 1
    fi

    echo "Total: ${count} case(s) with output data"
}

find_run_directory() {
    local case_name="$1"
    local platform="$2"

    # If case_name already includes platform, use it directly
    if [[ "$case_name" == *_* ]]; then
        # Check if it ends with a platform name
        local possible_platform="${case_name##*_}"
        if [[ -d "${PROJECT_DIR}/.run_${case_name}" ]]; then
            # Verify it matches the requested platform
            if [[ -z "$platform" ]] || [[ "$possible_platform" == "$platform" ]]; then
                echo "${PROJECT_DIR}/.run_${case_name}"
                return 0
            fi
        fi
    fi

    # Try with platform suffix
    if [[ -n "$platform" ]]; then
        if [[ -d "${PROJECT_DIR}/.run_${case_name}_${platform}" ]]; then
            echo "${PROJECT_DIR}/.run_${case_name}_${platform}"
            return 0
        fi
    fi

    # Try exact match first
    if [[ -d "${PROJECT_DIR}/.run_${case_name}" ]]; then
        echo "${PROJECT_DIR}/.run_${case_name}"
        return 0
    fi

    # Try without .run_ prefix if provided
    if [[ "$case_name" == .run_* ]]; then
        local stripped="${case_name#.run_}"
        if [[ -d "${PROJECT_DIR}/.run_${stripped}" ]]; then
            echo "${PROJECT_DIR}/.run_${stripped}"
            return 0
        fi
    fi

    # Try with .run_ prefix if not provided
    if [[ "$case_name" != .run_* ]]; then
        if [[ -d "${PROJECT_DIR}/${case_name}" ]]; then
            echo "${PROJECT_DIR}/${case_name}"
            return 0
        fi
    fi

    return 1
}

create_plotting_script() {
    local python_script="${PLOTS_DIR}/plot_output.py"

    cat > "$python_script" << 'PYTHON_EOF'
#!/usr/bin/env python3
"""
ExaEpi Output Plotter

Reads output.dat or output_<disease>.dat files and creates plots of:
- Total infections and infection states over time
- Cumulative deaths over time
- Hospitalizations (total hospital and ICU) over time
"""

import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')  # Use non-interactive backend
import matplotlib.pyplot as plt
from pathlib import Path

# Column indices in output.dat based on main.cpp line 192-194
# Headers: Day, Su, PS/PI, S/PI/NH, S/PI/H, PS/I, S/I/NH, S/I/H, A/PI, A/I, H/NI, H/I, ICU, V, R, D, NewI, NewS, NewH, NewA, NewP
COL_DAY = 0           # Day
COL_SU = 1            # Susceptible
COL_PS_PI = 2         # Presymptomatic/Pre-Infectious
COL_S_PI_NH = 3       # Symptomatic/Pre-Infectious/Not Hospitalized
COL_S_PI_H = 4        # Symptomatic/Pre-Infectious/Hospitalized
COL_PS_I = 5          # Presymptomatic/Infectious
COL_S_I_NH = 6        # Symptomatic/Infectious/Not Hospitalized
COL_S_I_H = 7         # Symptomatic/Infectious/Hospitalized
COL_A_PI = 8          # Asymptomatic/Pre-Infectious
COL_A_I = 9           # Asymptomatic/Infectious
COL_H_NI = 10         # Hospital/Not in ICU
COL_H_I = 11          # Hospital/In ICU
COL_ICU = 12          # ICU
COL_V = 13            # Vaccinated
COL_R = 14            # Recovered
COL_D = 15            # Deaths (cumulative)
COL_NEWI = 16         # New Infections
COL_NEWS = 17         # New Symptomatic
COL_NEWH = 18         # New Hospitalizations
COL_NEWA = 19         # New Asymptomatic
COL_NEWP = 20         # New Presymptomatic

# Primary colors for plotting (prioritize these)
COLOR_RED = '#D62728'      # Red
COLOR_BLUE = '#1F77B4'     # Blue
COLOR_GREEN = '#2CA02C'    # Green
COLOR_ORANGE = '#FF7F0E'   # Orange
COLOR_PURPLE = '#9467BD'   # Purple
COLOR_BROWN = '#8C564B'    # Brown

def read_output_file(filename):
    """Read ExaEpi output file, skipping header"""
    try:
        data = np.loadtxt(filename, skiprows=1)
        return data
    except Exception as e:
        print(f"ERROR: Failed to read {filename}: {e}", file=sys.stderr)
        return None

def create_infections_plot(data, case_name, platform, output_format, plots_dir, disease_name=None):
    """Create plot of total infections and infection states over time"""
    fig, ax = plt.subplots(figsize=(10, 6))

    days = data[:, COL_DAY]

    # Calculate infection states
    # Total infected = sum of all infected compartments
    total_infected = (data[:, COL_PS_PI] + data[:, COL_S_PI_NH] + data[:, COL_S_PI_H] +
                     data[:, COL_PS_I] + data[:, COL_S_I_NH] + data[:, COL_S_I_H] +
                     data[:, COL_A_PI] + data[:, COL_A_I])

    # Exposed (pre-infectious)
    exposed = data[:, COL_PS_PI] + data[:, COL_S_PI_NH] + data[:, COL_S_PI_H] + data[:, COL_A_PI]

    # Presymptomatic (both pre-infectious and infectious)
    presymptomatic = data[:, COL_PS_PI] + data[:, COL_PS_I]

    # Asymptomatic (both pre-infectious and infectious)
    asymptomatic = data[:, COL_A_PI] + data[:, COL_A_I]

    # Symptomatic (both pre-infectious and infectious)
    symptomatic = data[:, COL_S_PI_NH] + data[:, COL_S_PI_H] + data[:, COL_S_I_NH] + data[:, COL_S_I_H]

    # Plot with primary colors, total infections thicker
    ax.plot(days, total_infected, color=COLOR_BLUE, linewidth=2.5, label='Total Infected')
    ax.plot(days, exposed, color=COLOR_ORANGE, linewidth=1.2, label='Exposed', linestyle='--')
    ax.plot(days, presymptomatic, color=COLOR_GREEN, linewidth=1.2, label='Presymptomatic')
    ax.plot(days, asymptomatic, color=COLOR_PURPLE, linewidth=1.2, label='Asymptomatic')
    ax.plot(days, symptomatic, color=COLOR_RED, linewidth=1.2, label='Symptomatic')

    ax.set_xlabel('Day', fontsize=12)
    ax.set_ylabel('Number of Infected Individuals', fontsize=12)

    title = 'Infections Over Time'
    if disease_name:
        title += f' ({disease_name})'
    ax.set_title(title, fontsize=14, fontweight='bold')

    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=10, loc='best')

    plt.tight_layout()

    # Create filename: <case>_infections_<platform>.<ext>
    base_name = f"{case_name}_infections_{platform}"
    if disease_name:
        base_name = f"{case_name}_{disease_name}_infections_{platform}"

    # Save in requested formats
    if output_format in ['png', 'both']:
        png_file = str(Path(plots_dir) / f"{base_name}.png")
        plt.savefig(png_file, dpi=300, bbox_inches='tight')
        print(f"Created: {png_file}")

    if output_format in ['eps', 'both']:
        eps_file = str(Path(plots_dir) / f"{base_name}.eps")
        plt.savefig(eps_file, format='eps', bbox_inches='tight')
        print(f"Created: {eps_file}")

    plt.close()

def create_deaths_plot(data, case_name, platform, output_format, plots_dir, disease_name=None):
    """Create plot of cumulative deaths over time"""
    fig, ax = plt.subplots(figsize=(10, 6))

    days = data[:, COL_DAY]
    deaths = data[:, COL_D]

    # Use primary red color, no legend since variable is in y-axis label
    ax.plot(days, deaths, color=COLOR_RED, linewidth=2.5)
    ax.set_xlabel('Day', fontsize=12)
    ax.set_ylabel('Cumulative Deaths', fontsize=12)

    title = 'Cumulative Deaths Over Time'
    if disease_name:
        title += f' ({disease_name})'
    ax.set_title(title, fontsize=14, fontweight='bold')

    ax.grid(True, alpha=0.3)
    # No legend - only one variable and it's clear from y-axis

    plt.tight_layout()

    # Create filename: <case>_deaths_<platform>.<ext>
    base_name = f"{case_name}_deaths_{platform}"
    if disease_name:
        base_name = f"{case_name}_{disease_name}_deaths_{platform}"

    # Save in requested formats
    if output_format in ['png', 'both']:
        png_file = str(Path(plots_dir) / f"{base_name}.png")
        plt.savefig(png_file, dpi=300, bbox_inches='tight')
        print(f"Created: {png_file}")

    if output_format in ['eps', 'both']:
        eps_file = str(Path(plots_dir) / f"{base_name}.eps")
        plt.savefig(eps_file, format='eps', bbox_inches='tight')
        print(f"Created: {eps_file}")

    plt.close()

def create_hospitalizations_plot(data, case_name, platform, output_format, plots_dir, disease_name=None):
    """Create plot of hospitalizations over time"""
    fig, ax = plt.subplots(figsize=(10, 6))

    days = data[:, COL_DAY]
    new_hosp = data[:, COL_NEWH]
    icu = data[:, COL_ICU]
    total_hosp = data[:, COL_H_NI] + data[:, COL_H_I]

    # Use primary colors
    ax.plot(days, total_hosp, color=COLOR_BLUE, linewidth=2.5, label='Total Hospitalized')
    ax.plot(days, new_hosp, color=COLOR_GREEN, linewidth=2, label='New Admissions')
    ax.plot(days, icu, color=COLOR_RED, linewidth=2, label='ICU Patients')

    ax.set_xlabel('Day', fontsize=12)
    ax.set_ylabel('Number of Patients', fontsize=12)

    title = 'Hospitalizations Over Time'
    if disease_name:
        title += f' ({disease_name})'
    ax.set_title(title, fontsize=14, fontweight='bold')

    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=10, loc='best')

    plt.tight_layout()

    # Create filename: <case>_hospitalizations_<platform>.<ext>
    base_name = f"{case_name}_hospitalizations_{platform}"
    if disease_name:
        base_name = f"{case_name}_{disease_name}_hospitalizations_{platform}"

    # Save in requested formats
    if output_format in ['png', 'both']:
        png_file = str(Path(plots_dir) / f"{base_name}.png")
        plt.savefig(png_file, dpi=300, bbox_inches='tight')
        print(f"Created: {png_file}")

    if output_format in ['eps', 'both']:
        eps_file = str(Path(plots_dir) / f"{base_name}.eps")
        plt.savefig(eps_file, format='eps', bbox_inches='tight')
        print(f"Created: {eps_file}")

    plt.close()

def main():
    if len(sys.argv) < 5:
        print("Usage: plot_output.py <output_file> <case_name> <platform> <output_format> <plots_dir>", file=sys.stderr)
        sys.exit(1)

    output_file = sys.argv[1]
    case_name = sys.argv[2]
    platform = sys.argv[3]
    output_format = sys.argv[4] if len(sys.argv) > 4 else 'both'
    plots_dir = sys.argv[5] if len(sys.argv) > 5 else '.'

    if not Path(output_file).exists():
        print(f"ERROR: Output file not found: {output_file}", file=sys.stderr)
        sys.exit(1)

    # Create plots directory if it doesn't exist
    Path(plots_dir).mkdir(parents=True, exist_ok=True)

    # Read data
    data = read_output_file(output_file)
    if data is None:
        sys.exit(1)

    # Determine disease name from filename
    disease_name = None
    filename = Path(output_file).name
    if filename.startswith('output_') and filename.endswith('.dat'):
        disease_name = filename[7:-4]  # Remove 'output_' and '.dat'

    print(f"Processing: {output_file}")
    print(f"Case: {case_name}, Platform: {platform}")
    if disease_name:
        print(f"Disease: {disease_name}")
    print(f"Timesteps: {len(data)}")

    # Create plots
    create_infections_plot(data, case_name, platform, output_format, plots_dir, disease_name)
    create_deaths_plot(data, case_name, platform, output_format, plots_dir, disease_name)
    create_hospitalizations_plot(data, case_name, platform, output_format, plots_dir, disease_name)

    print("Plotting complete!")

if __name__ == '__main__':
    main()
PYTHON_EOF

    chmod +x "$python_script"
    echo "$python_script"
}

create_ensemble_plotting_script() {
    local python_script="${PLOTS_DIR}/plot_ensemble.py"

    cat > "$python_script" << 'PYTHON_EOF'
#!/usr/bin/env python3
"""
ExaEpi Ensemble Plotter

Reads ensemble summary statistics files (*_summary_mean.dat, *_summary_std.dat,
*_summary_min.dat, *_summary_max.dat) and creates plots of:
- Total infections over time (mean with min/max and +/- 1 std bands)
- Total hospitalizations over time (mean with min/max and +/- 1 std bands)
- Deaths over time (mean with min/max and +/- 1 std bands)
"""

import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from pathlib import Path

# Colors
COLOR_RED = '#D62728'
COLOR_BLUE = '#1F77B4'
COLOR_GREEN = '#2CA02C'

BAND_ALPHA_MINMAX = 0.15
BAND_ALPHA_STD = 0.3

def read_summary_file(filename):
    """Read ensemble summary file, skipping header"""
    try:
        data = np.loadtxt(filename, skiprows=1)
        return data
    except Exception as e:
        print(f"ERROR: Failed to read {filename}: {e}", file=sys.stderr)
        return None

def save_figure(fig, base_name, output_format, plots_dir):
    """Save figure in requested formats"""
    if output_format in ['png', 'both']:
        png_file = str(Path(plots_dir) / f"{base_name}.png")
        fig.savefig(png_file, dpi=300, bbox_inches='tight')
        print(f"Created: {png_file}")
    if output_format in ['eps', 'both']:
        eps_file = str(Path(plots_dir) / f"{base_name}.eps")
        fig.savefig(eps_file, format='eps', bbox_inches='tight')
        print(f"Created: {eps_file}")

def plot_ensemble_quantity(days, mean, std, qmin, qmax, ylabel, title,
                           color, base_name, output_format, plots_dir):
    """Create a single ensemble plot with mean line and variation bands"""
    fig, ax = plt.subplots(figsize=(10, 6))

    # Min/max band (lighter)
    ax.fill_between(days, qmin, qmax, alpha=BAND_ALPHA_MINMAX, color=color, label='Min/Max')
    # Std band (darker)
    ax.fill_between(days, mean - std, mean + std, alpha=BAND_ALPHA_STD, color=color, label='Mean +/- 1 Std')
    # Mean line
    ax.plot(days, mean, color=color, linewidth=2.5, label='Mean')

    ax.set_xlabel('Day', fontsize=12)
    ax.set_ylabel(ylabel, fontsize=12)
    ax.set_title(title, fontsize=14, fontweight='bold')
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=10, loc='best')

    plt.tight_layout()
    save_figure(fig, base_name, output_format, plots_dir)
    plt.close()

def main():
    if len(sys.argv) < 6:
        print("Usage: plot_ensemble.py <ensemble_dir> <case_name> <platform> <output_format> <plots_dir>",
              file=sys.stderr)
        sys.exit(1)

    ensemble_dir = Path(sys.argv[1])
    case_name = sys.argv[2]
    platform = sys.argv[3]
    output_format = sys.argv[4]
    plots_dir = sys.argv[5]

    Path(plots_dir).mkdir(parents=True, exist_ok=True)

    # Find all summary file sets: <stats_base>_summary_mean.dat
    summary_mean_files = sorted(ensemble_dir.glob('*_summary_mean.dat'))
    if not summary_mean_files:
        print("ERROR: No ensemble summary files found", file=sys.stderr)
        sys.exit(1)

    for mean_file in summary_mean_files:
        # Derive stats_base: output_summary_mean.dat -> output
        # or output_Covid19_summary_mean.dat -> output_Covid19
        fname = mean_file.name  # e.g. output_summary_mean.dat
        stats_base = fname.replace('_summary_mean.dat', '')

        std_file  = ensemble_dir / f"{stats_base}_summary_std.dat"
        min_file  = ensemble_dir / f"{stats_base}_summary_min.dat"
        max_file  = ensemble_dir / f"{stats_base}_summary_max.dat"

        for f in [std_file, min_file, max_file]:
            if not f.exists():
                print(f"WARNING: Missing {f}, skipping {stats_base}", file=sys.stderr)
                continue

        mean_data = read_summary_file(mean_file)
        std_data  = read_summary_file(std_file)
        min_data  = read_summary_file(min_file)
        max_data  = read_summary_file(max_file)

        if any(d is None for d in [mean_data, std_data, min_data, max_data]):
            continue

        # Columns: Day(0), TotalInfected(1), TotalHospitalized(2), Deaths(3)
        days = mean_data[:, 0]

        # Determine disease name for titles
        disease_name = None
        if stats_base.startswith('output_'):
            disease_name = stats_base[7:]  # Remove 'output_'
        disease_suffix = f" ({disease_name})" if disease_name else ""

        print(f"Processing ensemble plots for {stats_base}...")

        # Filename prefix
        if disease_name:
            prefix = f"{case_name}_{disease_name}_ensemble"
        else:
            prefix = f"{case_name}_ensemble"

        # 1. Total Infections
        plot_ensemble_quantity(
            days,
            mean_data[:, 1], std_data[:, 1], min_data[:, 1], max_data[:, 1],
            'Total Infected', f'Total Infections Over Time{disease_suffix}',
            COLOR_BLUE, f"{prefix}_infections_{platform}",
            output_format, plots_dir)

        # 2. Total Hospitalizations
        plot_ensemble_quantity(
            days,
            mean_data[:, 2], std_data[:, 2], min_data[:, 2], max_data[:, 2],
            'Total Hospitalized', f'Total Hospitalizations Over Time{disease_suffix}',
            COLOR_GREEN, f"{prefix}_hospitalizations_{platform}",
            output_format, plots_dir)

        # 3. Deaths
        plot_ensemble_quantity(
            days,
            mean_data[:, 3], std_data[:, 3], min_data[:, 3], max_data[:, 3],
            'Cumulative Deaths', f'Deaths Over Time{disease_suffix}',
            COLOR_RED, f"{prefix}_deaths_{platform}",
            output_format, plots_dir)

    print("Ensemble plotting complete!")

if __name__ == '__main__':
    main()
PYTHON_EOF

    chmod +x "$python_script"
    echo "$python_script"
}

find_ensemble_directory() {
    local case_name="$1"
    local platform="$2"

    local ensemble_dir="${PROJECT_DIR}/.ensemble_${case_name}_${platform}"
    if [[ -d "$ensemble_dir" ]]; then
        echo "$ensemble_dir"
        return 0
    fi

    return 1
}

get_all_ensemble_dirs() {
    local platform="$1"
    for ens_dir in "${PROJECT_DIR}"/.ensemble_*; do
        if [[ -d "$ens_dir" ]]; then
            local basename=$(basename "$ens_dir")
            if [[ -n "$platform" ]]; then
                local dir_platform="${basename##*_}"
                if [[ "$dir_platform" == "$platform" ]]; then
                    echo "$basename"
                fi
            else
                echo "$basename"
            fi
        fi
    done
}

plot_ensemble_case() {
    local ensemble_dir="$1"
    local output_format="$2"
    local dir_basename=$(basename "$ensemble_dir")

    # Parse case name and platform: .ensemble_<case>_<platform>
    local case_platform="${dir_basename#.ensemble_}"
    local platform="${case_platform##*_}"
    local case_name="${case_platform%_*}"

    print_info "=========================================="
    print_info "Plotting ensemble: ${case_name} (${platform})"
    print_info "=========================================="
    print_verbose "Ensemble directory: ${ensemble_dir}"

    # Check for summary files
    local summary_count=$(ls "${ensemble_dir}"/*_summary_mean.dat 2>/dev/null | wc -l)
    if [[ "$summary_count" -eq 0 ]]; then
        print_error "No ensemble summary files found in ${ensemble_dir}"
        print_info "Run ensemble simulations first using: run_exaepi.sh --ensemble --mode=batch"
        return 1
    fi
    print_success "Found ${summary_count} summary file set(s)"

    mkdir -p "${PLOTS_DIR}"

    local python_script=$(create_ensemble_plotting_script)
    print_verbose "Created ensemble plotting script: ${python_script}"

    if python3 "$python_script" "$ensemble_dir" "$case_name" "$platform" "$output_format" "$PLOTS_DIR"; then
        print_success "Ensemble plots created in ${PLOTS_DIR}"
        echo ""
        return 0
    else
        print_error "Failed to create ensemble plots"
        return 1
    fi
}

plot_case() {
    local run_dir="$1"
    local output_format="$2"
    local dir_basename=$(basename "$run_dir")

    # Parse case name and platform from directory name: .run_<case>_<platform>
    # Remove .run_ prefix
    local case_platform="${dir_basename#.run_}"

    # Split by last underscore to get platform
    local platform="${case_platform##*_}"
    local case_name="${case_platform%_*}"

    print_info "=========================================="
    print_info "Plotting case: ${case_name} (${platform})"
    print_info "=========================================="
    print_verbose "Run directory: ${run_dir}"

    # Find output files
    local output_files=()
    if [[ -f "${run_dir}/output.dat" ]]; then
        output_files+=("${run_dir}/output.dat")
    fi
    for f in "${run_dir}"/output_*.dat; do
        if [[ -f "$f" ]]; then
            output_files+=("$f")
        fi
    done

    if [[ ${#output_files[@]} -eq 0 ]]; then
        print_error "No output.dat files found in ${run_dir}"
        print_info "Run the simulation first using run_exaepi.sh"
        return 1
    fi

    print_success "Found ${#output_files[@]} output file(s)"

    # Create plots directory if it doesn't exist
    mkdir -p "${PLOTS_DIR}"
    print_verbose "Plots directory: ${PLOTS_DIR}"

    # Create plotting script
    local python_script=$(create_plotting_script)
    print_verbose "Created plotting script: ${python_script}"

    # Plot each output file
    local plot_count=0
    for output_file in "${output_files[@]}"; do
        print_info "Plotting: $(basename "$output_file")"

        if python3 "$python_script" "$output_file" "$case_name" "$platform" "$output_format" "$PLOTS_DIR"; then
            plot_count=$((plot_count + 1))
        else
            print_error "Failed to create plots for $(basename "$output_file")"
        fi
    done

    if [[ $plot_count -gt 0 ]]; then
        print_success "Created plots for ${plot_count} disease(s) in ${PLOTS_DIR}"
        echo ""
        return 0
    else
        return 1
    fi
}

#------------------------------------------------------------------------------
# Parse command line arguments
#------------------------------------------------------------------------------

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -l|--list-cases)
                # Will be handled in main after platform detection
                LIST_CASES=true
                shift
                ;;
            -c|--case)
                CASE_NAME="$2"
                shift 2
                ;;
            --case=*)
                CASE_NAME="${1#*=}"
                shift
                ;;
            -a|--all)
                PLOT_ALL=true
                shift
                ;;
            -e|--ensemble)
                ENSEMBLE=true
                shift
                ;;
            -P|--platform)
                PLATFORM="$2"
                shift 2
                ;;
            --platform=*)
                PLATFORM="${1#*=}"
                shift
                ;;
            -f|--format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --format=*)
                OUTPUT_FORMAT="${1#*=}"
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

#------------------------------------------------------------------------------
# Main execution
#------------------------------------------------------------------------------

main() {
    parse_args "$@"

    # Detect or validate platform
    if [[ -z "$PLATFORM" ]]; then
        PLATFORM=$(detect_platform)
        print_info "Detected platform: ${PLATFORM}"
    else
        print_info "Using specified platform: ${PLATFORM}"
    fi
    print_verbose "Filtering cases for platform: ${PLATFORM}"

    # Handle list cases
    if [[ "${LIST_CASES:-false}" == "true" ]]; then
        list_cases "$PLATFORM"
        exit 0
    fi

    # Validate output format
    if [[ ! "$OUTPUT_FORMAT" =~ ^(eps|png|both)$ ]]; then
        print_error "Invalid output format: ${OUTPUT_FORMAT}"
        echo "Valid formats: eps, png, both"
        exit 1
    fi

    # Check for Python and matplotlib
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is required but not found"
        exit 1
    fi

    if ! python3 -c "import matplotlib" &> /dev/null; then
        print_error "Python matplotlib is required but not found"
        echo "Install with: pip install matplotlib"
        exit 1
    fi

    # Handle ensemble mode
    if [[ "$ENSEMBLE" == "true" ]]; then
        if [[ "$PLOT_ALL" == "true" ]]; then
            local all_ens=($(get_all_ensemble_dirs "$PLATFORM"))
            if [[ ${#all_ens[@]} -eq 0 ]]; then
                print_error "No ensemble directories found"
                exit 1
            fi
            print_info "Plotting ${#all_ens[@]} ensemble(s)..."
            local success_count=0
            local fail_count=0
            for dir_name in "${all_ens[@]}"; do
                if plot_ensemble_case "${PROJECT_DIR}/${dir_name}" "$OUTPUT_FORMAT"; then
                    success_count=$((success_count + 1))
                else
                    fail_count=$((fail_count + 1))
                fi
            done
            echo "Ensemble plotting summary: ${success_count} succeeded, ${fail_count} failed"
            [[ $fail_count -gt 0 ]] && exit 1
        else
            if [[ -z "$CASE_NAME" ]]; then
                print_error "No case specified"
                echo "Use --case=NAME or --all with --ensemble"
                exit 1
            fi
            local ENS_DIR=$(find_ensemble_directory "${CASE_NAME}" "$PLATFORM")
            if [[ $? -ne 0 ]]; then
                print_error "Ensemble directory not found for case: ${CASE_NAME} (platform: ${PLATFORM})"
                echo "Expected: ${PROJECT_DIR}/.ensemble_${CASE_NAME}_${PLATFORM}"
                exit 1
            fi
            plot_ensemble_case "$ENS_DIR" "$OUTPUT_FORMAT"
            exit $?
        fi
        exit 0
    fi

    if [[ "$PLOT_ALL" == "true" ]]; then
        # Plot all cases for this platform
        local all_dirs=($(get_all_run_dirs "$PLATFORM"))

        if [[ ${#all_dirs[@]} -eq 0 ]]; then
            print_error "No run directories found"
            echo "Run simulations first using run_exaepi.sh"
            exit 1
        fi

        print_info "Plotting ${#all_dirs[@]} case(s)..."
        echo ""

        local success_count=0
        local fail_count=0
        local failed_cases=()

        for dir_name in "${all_dirs[@]}"; do
            local full_path="${PROJECT_DIR}/${dir_name}"
            if plot_case "$full_path" "$OUTPUT_FORMAT"; then
                success_count=$((success_count + 1))
            else
                fail_count=$((fail_count + 1))
                failed_cases+=("$dir_name")
            fi
        done

        # Summary
        echo "=========================================="
        echo "Plotting Summary"
        echo "=========================================="
        echo "Total cases:     ${#all_dirs[@]}"
        echo "Successful:      ${success_count}"
        echo "Failed:          ${fail_count}"
        if [[ $fail_count -gt 0 ]]; then
            echo ""
            echo "Failed cases:"
            for failed_case in "${failed_cases[@]}"; do
                echo "  - ${failed_case}"
            done
        fi
        echo "=========================================="

        if [[ $fail_count -gt 0 ]]; then
            exit 1
        fi
    else
        # Plot single case
        if [[ -z "$CASE_NAME" ]]; then
            print_error "No case specified"
            echo "Use --case=NAME or --all"
            echo "Use --list-cases to see available cases"
            exit 1
        fi

        RUN_DIR=$(find_run_directory "${CASE_NAME}" "$PLATFORM")
        if [[ $? -ne 0 ]]; then
            print_error "Run directory not found for case: ${CASE_NAME} (platform: ${PLATFORM})"
            echo "Use --list-cases to see available cases"
            exit 1
        fi

        plot_case "$RUN_DIR" "$OUTPUT_FORMAT"
        exit $?
    fi
}

# Run main function
main "$@"
