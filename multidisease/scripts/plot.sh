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
CASE_NAMES=()
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
  -c, --case=NAME       Plot specific case(s) (can be specified multiple times)
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

  # Plot multiple cases
  ./plot.sh -c bay_01D_Cov19S1_dane CA_01D_Cov19S1_dane

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
import os
import numpy as np
import matplotlib
matplotlib.use('Agg')  # Use non-interactive backend
import matplotlib.pyplot as plt
from pathlib import Path

def save_eps(fig_or_plt, filepath):
    """Save EPS file with PostScript transparency warnings suppressed."""
    stderr_fd = sys.stderr.fileno()
    old_stderr = os.dup(stderr_fd)
    devnull = os.open(os.devnull, os.O_WRONLY)
    os.dup2(devnull, stderr_fd)
    try:
        fig_or_plt.savefig(filepath, format='eps', bbox_inches='tight')
    finally:
        os.dup2(old_stderr, stderr_fd)
        os.close(old_stderr)
        os.close(devnull)

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
COL_H_NI = 10         # Hospitalized/Non-infectious
COL_H_I = 11          # Hospitalized/Infectious
COL_ICU = 12          # ICU
COL_V = 13            # Ventilator
COL_R = 14            # Immune (Status::immune, wanes over time)
COL_D = 15            # Deaths (cumulative)
COL_NEWI = 16         # New Infections
COL_NEWS = 17         # New Symptomatic
COL_NEWH = 18         # New Hospitalizations
COL_NEWA = 19         # New Asymptomatic
COL_NEWP = 20         # New Presymptomatic

# Age-group columns (written after base columns in main.cpp lines 479-484)
# New Symptomatic by age group (columns 21-26)
COL_SYMP_U5 = 21
COL_SYMP_5TO17 = 22
COL_SYMP_18TO29 = 23
COL_SYMP_30TO49 = 24
COL_SYMP_50TO64 = 25
COL_SYMP_O64 = 26
# New Hospitalizations by age group (columns 27-32)
COL_HOSP_U5 = 27
COL_HOSP_5TO17 = 28
COL_HOSP_18TO29 = 29
COL_HOSP_30TO49 = 30
COL_HOSP_50TO64 = 31
COL_HOSP_O64 = 32

AGE_GROUP_HOSP_COLS = [COL_HOSP_U5, COL_HOSP_5TO17, COL_HOSP_18TO29,
                       COL_HOSP_30TO49, COL_HOSP_50TO64, COL_HOSP_O64]
AGE_GROUP_LABELS = ['<5', '5-17', '18-29', '30-49', '50-64', '65+']

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
        save_eps(plt, eps_file)
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
        save_eps(plt, eps_file)
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

    # Age-group hospitalization lines (thinner, dashed)
    if data.shape[1] > COL_HOSP_O64:
        age_colors = ['#1B9E77', '#D95F02', '#7570B3', '#E7298A', '#66A61E', '#E6AB02']
        for i, (col, label) in enumerate(zip(AGE_GROUP_HOSP_COLS, AGE_GROUP_LABELS)):
            ax.plot(days, data[:, col], color=age_colors[i], linewidth=1, linestyle='--',
                    label=f'New Hosp {label}')

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
        save_eps(plt, eps_file)
        print(f"Created: {eps_file}")

    plt.close()

def create_immune_plot(data, case_name, platform, output_format, plots_dir, disease_name=None):
    """Create plot of currently immune agents over time"""
    fig, ax = plt.subplots(figsize=(10, 6))

    days = data[:, COL_DAY]
    immune = data[:, COL_R]

    ax.plot(days, immune, color=COLOR_GREEN, linewidth=2.5)
    ax.set_xlabel('Day', fontsize=12)
    ax.set_ylabel('Currently Immune', fontsize=12)

    title = 'Immune Over Time'
    if disease_name:
        title += f' ({disease_name})'
    ax.set_title(title, fontsize=14, fontweight='bold')

    ax.grid(True, alpha=0.3)

    plt.tight_layout()

    base_name = f"{case_name}_immune_{platform}"
    if disease_name:
        base_name = f"{case_name}_{disease_name}_immune_{platform}"

    if output_format in ['png', 'both']:
        png_file = str(Path(plots_dir) / f"{base_name}.png")
        plt.savefig(png_file, dpi=300, bbox_inches='tight')
        print(f"Created: {png_file}")

    if output_format in ['eps', 'both']:
        eps_file = str(Path(plots_dir) / f"{base_name}.eps")
        save_eps(plt, eps_file)
        print(f"Created: {eps_file}")

    plt.close()

def save_combined(fig, base_name, output_format, plots_dir):
    """Save a combined figure in requested formats"""
    if output_format in ['png', 'both']:
        png_file = str(Path(plots_dir) / f"{base_name}.png")
        fig.savefig(png_file, dpi=300, bbox_inches='tight')
        print(f"Created: {png_file}")
    if output_format in ['eps', 'both']:
        eps_file = str(Path(plots_dir) / f"{base_name}.eps")
        save_eps(fig, eps_file)
        print(f"Created: {eps_file}")

DISEASE_COLORS = ['#1F77B4', '#D62728', '#2CA02C', '#FF7F0E', '#9467BD', '#8C564B']

def create_combined_plots(diseases, case_name, platform, output_format, plots_dir):
    """Create combined plots overlaying the same variable across diseases.
    diseases: list of (disease_name, data) tuples.
    Deaths and hospitalizations are not disease-specific, so only one line is plotted."""

    colors = DISEASE_COLORS[:len(diseases)]

    # 1. Combined Total Infections with subcategories
    fig, ax = plt.subplots(figsize=(10, 6))
    for (dname, data), color in zip(diseases, colors):
        days = data[:, COL_DAY]
        total_infected = (data[:, COL_PS_PI] + data[:, COL_S_PI_NH] + data[:, COL_S_PI_H] +
                         data[:, COL_PS_I] + data[:, COL_S_I_NH] + data[:, COL_S_I_H] +
                         data[:, COL_A_PI] + data[:, COL_A_I])
        exposed = data[:, COL_PS_PI] + data[:, COL_S_PI_NH] + data[:, COL_S_PI_H] + data[:, COL_A_PI]
        presymptomatic = data[:, COL_PS_PI] + data[:, COL_PS_I]
        asymptomatic = data[:, COL_A_PI] + data[:, COL_A_I]
        symptomatic = data[:, COL_S_PI_NH] + data[:, COL_S_PI_H] + data[:, COL_S_I_NH] + data[:, COL_S_I_H]
        ax.plot(days, total_infected, color=color, linewidth=2.5, label=f'{dname} Total')
        ax.plot(days, exposed, color=color, linewidth=1, linestyle='--', alpha=0.7, label=f'{dname} Exposed')
        ax.plot(days, presymptomatic, color=color, linewidth=1, linestyle=':', alpha=0.7, label=f'{dname} Presymp')
        ax.plot(days, asymptomatic, color=color, linewidth=1, linestyle='-.', alpha=0.7, label=f'{dname} Asymp')
        ax.plot(days, symptomatic, color=color, linewidth=1, linestyle=(0, (5, 1)), alpha=0.7, label=f'{dname} Symp')
    ax.set_xlabel('Day', fontsize=12)
    ax.set_ylabel('Number of Infected Individuals', fontsize=12)
    ax.set_title('Infections Over Time', fontsize=14, fontweight='bold')
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=8, loc='best', ncol=len(diseases))
    plt.tight_layout()
    save_combined(fig, f"{case_name}_infections_{platform}", output_format, plots_dir)
    plt.close()

    # 2. Deaths (not disease-specific, use first disease's data)
    days = diseases[0][1][:, COL_DAY]
    fig, ax = plt.subplots(figsize=(10, 6))
    ax.plot(days, diseases[0][1][:, COL_D], color=COLOR_RED, linewidth=2.5)
    ax.set_xlabel('Day', fontsize=12)
    ax.set_ylabel('Cumulative Deaths', fontsize=12)
    ax.set_title('Cumulative Deaths Over Time', fontsize=14, fontweight='bold')
    ax.grid(True, alpha=0.3)
    plt.tight_layout()
    save_combined(fig, f"{case_name}_deaths_{platform}", output_format, plots_dir)
    plt.close()

    # 3. Hospitalizations with subcategories (not disease-specific, use first disease's data)
    data = diseases[0][1]
    fig, ax = plt.subplots(figsize=(10, 6))
    total_hosp = data[:, COL_H_NI] + data[:, COL_H_I]
    ax.plot(days, total_hosp, color=COLOR_BLUE, linewidth=2.5, label='Total Hospitalized')
    ax.plot(days, data[:, COL_NEWH], color=COLOR_GREEN, linewidth=2, label='New Admissions')
    ax.plot(days, data[:, COL_ICU], color=COLOR_RED, linewidth=2, label='ICU Patients')
    if data.shape[1] > COL_HOSP_O64:
        age_colors = ['#1B9E77', '#D95F02', '#7570B3', '#E7298A', '#66A61E', '#E6AB02']
        for i, (col, label) in enumerate(zip(AGE_GROUP_HOSP_COLS, AGE_GROUP_LABELS)):
            ax.plot(days, data[:, col], color=age_colors[i], linewidth=1, linestyle='--',
                    label=f'New Hosp {label}')
    ax.set_xlabel('Day', fontsize=12)
    ax.set_ylabel('Number of Patients', fontsize=12)
    ax.set_title('Hospitalizations Over Time', fontsize=14, fontweight='bold')
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=10, loc='best')
    plt.tight_layout()
    save_combined(fig, f"{case_name}_hospitalizations_{platform}", output_format, plots_dir)
    plt.close()

    # 4. Combined Immune
    fig, ax = plt.subplots(figsize=(10, 6))
    for (dname, data), color in zip(diseases, colors):
        days = data[:, COL_DAY]
        ax.plot(days, data[:, COL_R], color=color, linewidth=2, label=dname)
    ax.set_xlabel('Day', fontsize=12)
    ax.set_ylabel('Currently Immune', fontsize=12)
    ax.set_title('Immune Over Time', fontsize=14, fontweight='bold')
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=10, loc='best')
    plt.tight_layout()
    save_combined(fig, f"{case_name}_immune_{platform}", output_format, plots_dir)
    plt.close()

def main():
    if len(sys.argv) < 5:
        print("Usage: plot_output.py <case_name> <platform> <output_format> <plots_dir> <output_file> [output_file ...]", file=sys.stderr)
        sys.exit(1)

    case_name = sys.argv[1]
    platform = sys.argv[2]
    output_format = sys.argv[3]
    plots_dir = sys.argv[4]
    output_files = sys.argv[5:]

    Path(plots_dir).mkdir(parents=True, exist_ok=True)

    # Read all output files and create per-disease plots
    diseases = []  # list of (disease_name, data)
    for output_file in output_files:
        if not Path(output_file).exists():
            print(f"ERROR: Output file not found: {output_file}", file=sys.stderr)
            continue

        data = read_output_file(output_file)
        if data is None:
            continue

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

        if disease_name:
            diseases.append((disease_name, data))
        else:
            # Single-disease case: create individual plots
            create_infections_plot(data, case_name, platform, output_format, plots_dir)
            create_deaths_plot(data, case_name, platform, output_format, plots_dir)
            create_hospitalizations_plot(data, case_name, platform, output_format, plots_dir)
            create_immune_plot(data, case_name, platform, output_format, plots_dir)

    # Multi-disease case: create combined plots only
    if len(diseases) > 1:
        print(f"Creating combined plots for {len(diseases)} diseases...")
        create_combined_plots(diseases, case_name, platform, output_format, plots_dir)
    elif len(diseases) == 1:
        # Single named disease: create individual plots
        dname, data = diseases[0]
        create_infections_plot(data, case_name, platform, output_format, plots_dir, dname)
        create_deaths_plot(data, case_name, platform, output_format, plots_dir, dname)
        create_hospitalizations_plot(data, case_name, platform, output_format, plots_dir, dname)
        create_immune_plot(data, case_name, platform, output_format, plots_dir, dname)

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
import os
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from pathlib import Path

# Colors
COLOR_RED = '#D62728'
COLOR_BLUE = '#1F77B4'
COLOR_GREEN = '#2CA02C'
COLOR_ORANGE = '#FF7F0E'
COLOR_PURPLE = '#9467BD'
COLOR_BROWN = '#8C564B'

DISEASE_COLORS = [COLOR_BLUE, COLOR_RED, COLOR_GREEN, COLOR_ORANGE, COLOR_PURPLE, COLOR_BROWN]

def save_eps(fig_or_plt, filepath):
    """Save EPS file with PostScript transparency warnings suppressed."""
    stderr_fd = sys.stderr.fileno()
    old_stderr = os.dup(stderr_fd)
    devnull = os.open(os.devnull, os.O_WRONLY)
    os.dup2(devnull, stderr_fd)
    try:
        fig_or_plt.savefig(filepath, format='eps', bbox_inches='tight')
    finally:
        os.dup2(old_stderr, stderr_fd)
        os.close(old_stderr)
        os.close(devnull)

def blend_color_with_white(color_hex, alpha):
    """Blend a hex color with white background to simulate transparency for EPS."""
    # Convert hex to RGB
    color_hex = color_hex.lstrip('#')
    r, g, b = tuple(int(color_hex[i:i+2], 16) for i in (0, 2, 4))
    # Blend with white (255, 255, 255)
    r_blend = int(r * alpha + 255 * (1 - alpha))
    g_blend = int(g * alpha + 255 * (1 - alpha))
    b_blend = int(b * alpha + 255 * (1 - alpha))
    return f'#{r_blend:02x}{g_blend:02x}{b_blend:02x}'

def read_summary_file(filename):
    """Read ensemble summary file, skipping header. Returns (data, headers)."""
    try:
        with open(filename, 'r') as f:
            header_line = f.readline().strip()
        headers = header_line.split()
        data = np.loadtxt(filename, skiprows=1)
        return data, headers
    except Exception as e:
        print(f"ERROR: Failed to read {filename}: {e}", file=sys.stderr)
        return None, None

def save_figure(fig, base_name, output_format, plots_dir):
    """Save figure in requested formats"""
    if output_format in ['png', 'both']:
        png_file = str(Path(plots_dir) / f"{base_name}.png")
        fig.savefig(png_file, dpi=300, bbox_inches='tight')
        print(f"Created: {png_file}")
    if output_format in ['eps', 'both']:
        eps_file = str(Path(plots_dir) / f"{base_name}.eps")
        save_eps(fig, eps_file)
        print(f"Created: {eps_file}")

def plot_ensemble_quantity(days, mean, std, ylabel, title,
                           color, base_name, output_format, plots_dir,
                           subcats=None, disease_label=None):
    """Create a single ensemble plot with mean line and variation bands.
    subcats: optional list of (mean_array, label, color) for subcategory lines.
    disease_label: optional disease name to add to legend labels."""
    fig, ax = plt.subplots(figsize=(10, 6))

    # Clamp lower bounds at zero (negative counts are unphysical)
    lo_2std = np.maximum(mean - 2*std, 0)
    lo_1std = np.maximum(mean - std, 0)

    # For EPS compatibility, use solid colors blended with white instead of alpha
    color_2std = blend_color_with_white(color, 0.15)
    color_1std = blend_color_with_white(color, 0.3)

    # Build label prefix
    label_prefix = f'{disease_label} ' if disease_label else ''

    # 2-std band (lighter) - use solid color for EPS compatibility
    ax.fill_between(days, lo_2std, mean + 2*std, color=color_2std,
                    edgecolor='none', label=f'{label_prefix}Mean +/- 2 Std')
    # 1-std band (darker) - use solid color for EPS compatibility
    ax.fill_between(days, lo_1std, mean + std, color=color_1std,
                    edgecolor='none', label=f'{label_prefix}Mean +/- 1 Std')
    # Mean line
    ax.plot(days, mean, color=color, linewidth=2.5, label=f'{label_prefix}Mean')

    # Subcategory mean lines (thinner, dashed)
    if subcats:
        for sub_mean, sub_label, sub_color in subcats:
            full_label = f'{label_prefix}{sub_label}' if disease_label else sub_label
            ax.plot(days, sub_mean, color=sub_color, linewidth=1, linestyle='--', label=full_label)

    ax.set_xlabel('Day', fontsize=12)
    ax.set_ylabel(ylabel, fontsize=12)
    ax.set_title(title, fontsize=14, fontweight='bold')
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=10, loc='best')

    plt.tight_layout()
    save_figure(fig, base_name, output_format, plots_dir)
    plt.close()

def plot_combined_ensemble(diseases_data, case_name, platform, output_format, plots_dir):
    """Create combined ensemble plots for multiple diseases.
    diseases_data: list of (disease_name, mean_data, std_data, col_dict, days) tuples."""

    colors = DISEASE_COLORS[:len(diseases_data)]

    # 1. Combined Total Infections
    fig, ax = plt.subplots(figsize=(10, 6))
    for (dname, mean_data, std_data, col, days), color in zip(diseases_data, colors):
        if 'TotalInfected' in col:
            mean = mean_data[:, col['TotalInfected']]
            std = std_data[:, col['TotalInfected']]
            lo_2std = np.maximum(mean - 2*std, 0)
            lo_1std = np.maximum(mean - std, 0)

            # Use solid blended colors for EPS compatibility
            color_2std = blend_color_with_white(color, 0.15)
            color_1std = blend_color_with_white(color, 0.3)

            ax.fill_between(days, lo_2std, mean + 2*std, color=color_2std, edgecolor='none')
            ax.fill_between(days, lo_1std, mean + std, color=color_1std, edgecolor='none')
            ax.plot(days, mean, color=color, linewidth=2.5, label=f'{dname}')

    ax.set_xlabel('Day', fontsize=12)
    ax.set_ylabel('Number of Agents', fontsize=12)
    ax.set_title('Total Infections Over Time', fontsize=14, fontweight='bold')
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=10, loc='best')
    plt.tight_layout()
    save_figure(fig, f"{case_name}_ensemble_infections_{platform}", output_format, plots_dir)
    plt.close()

    # 2. Combined Deaths (not disease-specific, use first disease)
    dname, mean_data, std_data, col, days = diseases_data[0]
    if 'Deaths' in col:
        fig, ax = plt.subplots(figsize=(10, 6))
        mean = mean_data[:, col['Deaths']]
        std = std_data[:, col['Deaths']]
        lo_2std = np.maximum(mean - 2*std, 0)
        lo_1std = np.maximum(mean - std, 0)

        color_2std = blend_color_with_white(COLOR_RED, 0.15)
        color_1std = blend_color_with_white(COLOR_RED, 0.3)

        ax.fill_between(days, lo_2std, mean + 2*std, color=color_2std, edgecolor='none')
        ax.fill_between(days, lo_1std, mean + std, color=color_1std, edgecolor='none')
        ax.plot(days, mean, color=COLOR_RED, linewidth=2.5)

        ax.set_xlabel('Day', fontsize=12)
        ax.set_ylabel('Cumulative Deaths', fontsize=12)
        ax.set_title('Deaths Over Time', fontsize=14, fontweight='bold')
        ax.grid(True, alpha=0.3)
        plt.tight_layout()
        save_figure(fig, f"{case_name}_ensemble_deaths_{platform}", output_format, plots_dir)
        plt.close()

    # 3. Combined Hospitalizations (not disease-specific, use first disease)
    if 'TotalHospitalized' in col:
        fig, ax = plt.subplots(figsize=(10, 6))
        mean = mean_data[:, col['TotalHospitalized']]
        std = std_data[:, col['TotalHospitalized']]
        lo_2std = np.maximum(mean - 2*std, 0)
        lo_1std = np.maximum(mean - std, 0)

        color_2std = blend_color_with_white(COLOR_GREEN, 0.15)
        color_1std = blend_color_with_white(COLOR_GREEN, 0.3)

        ax.fill_between(days, lo_2std, mean + 2*std, color=color_2std, edgecolor='none')
        ax.fill_between(days, lo_1std, mean + std, color=color_1std, edgecolor='none')
        ax.plot(days, mean, color=COLOR_GREEN, linewidth=2.5, label='Total Hospitalized')

        # Add subcategories if available
        if 'NewAdmissions' in col:
            ax.plot(days, mean_data[:, col['NewAdmissions']], color=COLOR_BLUE,
                   linewidth=1.5, linestyle='--', label='New Admissions')
        if 'ICU' in col:
            ax.plot(days, mean_data[:, col['ICU']], color=COLOR_RED,
                   linewidth=1.5, linestyle='--', label='ICU')

        ax.set_xlabel('Day', fontsize=12)
        ax.set_ylabel('Number of Patients', fontsize=12)
        ax.set_title('Hospitalizations Over Time', fontsize=14, fontweight='bold')
        ax.grid(True, alpha=0.3)
        ax.legend(fontsize=10, loc='best')
        plt.tight_layout()
        save_figure(fig, f"{case_name}_ensemble_hospitalizations_{platform}", output_format, plots_dir)
        plt.close()

    # 4. Combined Immune
    fig, ax = plt.subplots(figsize=(10, 6))
    for (dname, mean_data, std_data, col, days), color in zip(diseases_data, colors):
        if 'Recovered' in col:
            mean = mean_data[:, col['Recovered']]
            std = std_data[:, col['Recovered']]
            lo_2std = np.maximum(mean - 2*std, 0)
            lo_1std = np.maximum(mean - std, 0)

            color_2std = blend_color_with_white(color, 0.15)
            color_1std = blend_color_with_white(color, 0.3)

            ax.fill_between(days, lo_2std, mean + 2*std, color=color_2std, edgecolor='none')
            ax.fill_between(days, lo_1std, mean + std, color=color_1std, edgecolor='none')
            ax.plot(days, mean, color=color, linewidth=2.5, label=f'{dname}')

    ax.set_xlabel('Day', fontsize=12)
    ax.set_ylabel('Currently Immune', fontsize=12)
    ax.set_title('Immune Over Time', fontsize=14, fontweight='bold')
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=10, loc='best')
    plt.tight_layout()
    save_figure(fig, f"{case_name}_ensemble_immune_{platform}", output_format, plots_dir)
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

    # Collect all disease data
    diseases_data = []

    for mean_file in summary_mean_files:
        fname = mean_file.name
        stats_base = fname.replace('_summary_mean.dat', '')
        std_file = ensemble_dir / f"{stats_base}_summary_std.dat"

        if not std_file.exists():
            print(f"WARNING: Missing {std_file}, skipping {stats_base}", file=sys.stderr)
            continue

        mean_data, headers = read_summary_file(mean_file)
        std_data, _ = read_summary_file(std_file)

        if mean_data is None or std_data is None:
            continue

        col = {name: i for i, name in enumerate(headers)}
        days = mean_data[:, 0]

        # Determine disease name
        disease_name = None
        if stats_base.startswith('output_'):
            disease_name = stats_base[7:]  # Remove 'output_'

        print(f"Processing ensemble data for {stats_base}...")

        if disease_name:
            diseases_data.append((disease_name, mean_data, std_data, col, days))
        else:
            # Single disease case - create individual plots
            subcats = []
            if 'TotalInfected' in col:
                for name, label, color in [('Presymptomatic', 'Presymptomatic', COLOR_PURPLE),
                                           ('Asymptomatic', 'Asymptomatic', COLOR_ORANGE),
                                           ('Symptomatic', 'Symptomatic', COLOR_RED)]:
                    if name in col:
                        subcats.append((mean_data[:, col[name]], label, color))
                plot_ensemble_quantity(
                    days, mean_data[:, col['TotalInfected']], std_data[:, col['TotalInfected']],
                    'Number of Agents', 'Total Infections Over Time',
                    COLOR_BLUE, f"{case_name}_ensemble_infections_{platform}",
                    output_format, plots_dir, subcats=subcats)

            if 'TotalHospitalized' in col:
                subcats = []
                for name, label, color in [('NewAdmissions', 'New Admissions', COLOR_BLUE),
                                          ('ICU', 'ICU', COLOR_RED)]:
                    if name in col:
                        subcats.append((mean_data[:, col[name]], label, color))
                plot_ensemble_quantity(
                    days, mean_data[:, col['TotalHospitalized']], std_data[:, col['TotalHospitalized']],
                    'Number of Patients', 'Total Hospitalizations Over Time',
                    COLOR_GREEN, f"{case_name}_ensemble_hospitalizations_{platform}",
                    output_format, plots_dir, subcats=subcats)

            if 'Deaths' in col:
                plot_ensemble_quantity(
                    days, mean_data[:, col['Deaths']], std_data[:, col['Deaths']],
                    'Cumulative Deaths', 'Deaths Over Time',
                    COLOR_RED, f"{case_name}_ensemble_deaths_{platform}",
                    output_format, plots_dir)

            if 'Recovered' in col:
                plot_ensemble_quantity(
                    days, mean_data[:, col['Recovered']], std_data[:, col['Recovered']],
                    'Currently Immune', 'Immune Over Time',
                    COLOR_GREEN, f"{case_name}_ensemble_immune_{platform}",
                    output_format, plots_dir)

    # Multi-disease case: create combined plots
    if len(diseases_data) > 1:
        print(f"Creating combined ensemble plots for {len(diseases_data)} diseases...")
        plot_combined_ensemble(diseases_data, case_name, platform, output_format, plots_dir)
    elif len(diseases_data) == 1:
        # Single named disease - create individual plots with disease name
        dname, mean_data, std_data, col, days = diseases_data[0]

        if 'TotalInfected' in col:
            subcats = []
            for name, label, color in [('Presymptomatic', 'Presymptomatic', COLOR_PURPLE),
                                       ('Asymptomatic', 'Asymptomatic', COLOR_ORANGE),
                                       ('Symptomatic', 'Symptomatic', COLOR_RED)]:
                if name in col:
                    subcats.append((mean_data[:, col[name]], label, color))
            plot_ensemble_quantity(
                days, mean_data[:, col['TotalInfected']], std_data[:, col['TotalInfected']],
                'Number of Agents', f'Total Infections Over Time ({dname})',
                COLOR_BLUE, f"{case_name}_{dname}_ensemble_infections_{platform}",
                output_format, plots_dir, subcats=subcats, disease_label=dname)

        if 'TotalHospitalized' in col:
            subcats = []
            for name, label, color in [('NewAdmissions', 'New Admissions', COLOR_BLUE),
                                      ('ICU', 'ICU', COLOR_RED)]:
                if name in col:
                    subcats.append((mean_data[:, col[name]], label, color))
            plot_ensemble_quantity(
                days, mean_data[:, col['TotalHospitalized']], std_data[:, col['TotalHospitalized']],
                'Number of Patients', f'Total Hospitalizations Over Time ({dname})',
                COLOR_GREEN, f"{case_name}_{dname}_ensemble_hospitalizations_{platform}",
                output_format, plots_dir, subcats=subcats, disease_label=dname)

        if 'Deaths' in col:
            plot_ensemble_quantity(
                days, mean_data[:, col['Deaths']], std_data[:, col['Deaths']],
                'Cumulative Deaths', f'Deaths Over Time ({dname})',
                COLOR_RED, f"{case_name}_{dname}_ensemble_deaths_{platform}",
                output_format, plots_dir, disease_label=dname)

        if 'Recovered' in col:
            plot_ensemble_quantity(
                days, mean_data[:, col['Recovered']], std_data[:, col['Recovered']],
                'Currently Immune', f'Immune Over Time ({dname})',
                COLOR_GREEN, f"{case_name}_{dname}_ensemble_immune_{platform}",
                output_format, plots_dir, disease_label=dname)

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

    # Plot all output files (combined plots created when multiple diseases)
    print_info "Plotting ${#output_files[@]} output file(s)..."
    if python3 "$python_script" "$case_name" "$platform" "$output_format" "$PLOTS_DIR" "${output_files[@]}"; then
        print_success "Created plots for ${#output_files[@]} disease(s) in ${PLOTS_DIR}"
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
                shift
                while [[ $# -gt 0 ]] && [[ "$1" != -* ]]; do
                    CASE_NAMES+=("$1")
                    shift
                done
                ;;
            --case=*)
                CASE_NAMES+=("${1#*=}")
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
            # Plot specified ensemble case(s)
            if [[ ${#CASE_NAMES[@]} -eq 0 ]]; then
                print_error "No case specified"
                echo "Use --case=NAME or --all with --ensemble"
                exit 1
            fi

            local success_count=0
            local fail_count=0
            local failed_cases=()

            for case_name in "${CASE_NAMES[@]}"; do
                print_info "=========================================="
                print_info "Plotting ensemble case: ${case_name}"
                print_info "=========================================="

                local ENS_DIR=$(find_ensemble_directory "${case_name}" "$PLATFORM")
                if [[ $? -ne 0 ]]; then
                    print_error "Ensemble directory not found for case: ${case_name} (platform: ${PLATFORM})"
                    echo "Expected: ${PROJECT_DIR}/.ensemble_${case_name}_${PLATFORM}"
                    fail_count=$((fail_count + 1))
                    failed_cases+=("$case_name")
                    continue
                fi

                if plot_ensemble_case "$ENS_DIR" "$OUTPUT_FORMAT"; then
                    success_count=$((success_count + 1))
                else
                    fail_count=$((fail_count + 1))
                    failed_cases+=("$case_name")
                fi
            done

            if [[ ${#CASE_NAMES[@]} -gt 1 ]]; then
                echo "=========================================="
                echo "Ensemble Plotting Summary"
                echo "=========================================="
                echo "Total cases:     ${#CASE_NAMES[@]}"
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
            fi

            [[ $fail_count -gt 0 ]] && exit 1
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
        # Plot specified case(s)
        if [[ ${#CASE_NAMES[@]} -eq 0 ]]; then
            print_error "No case specified"
            echo "Use --case=NAME or --all"
            echo "Use --list-cases to see available cases"
            exit 1
        fi

        local success_count=0
        local fail_count=0
        local failed_cases=()

        for case_name in "${CASE_NAMES[@]}"; do
            if [[ ${#CASE_NAMES[@]} -gt 1 ]]; then
                print_info "=========================================="
                print_info "Plotting case: ${case_name}"
                print_info "=========================================="
            fi

            RUN_DIR=$(find_run_directory "${case_name}" "$PLATFORM")
            if [[ $? -ne 0 ]]; then
                print_error "Run directory not found for case: ${case_name} (platform: ${PLATFORM})"
                echo "Use --list-cases to see available cases"
                fail_count=$((fail_count + 1))
                failed_cases+=("$case_name")
                continue
            fi

            if plot_case "$RUN_DIR" "$OUTPUT_FORMAT"; then
                success_count=$((success_count + 1))
            else
                fail_count=$((fail_count + 1))
                failed_cases+=("$case_name")
            fi

            if [[ ${#CASE_NAMES[@]} -gt 1 ]]; then
                echo ""
            fi
        done

        if [[ ${#CASE_NAMES[@]} -gt 1 ]]; then
            echo "=========================================="
            echo "Plotting Summary"
            echo "=========================================="
            echo "Total cases:     ${#CASE_NAMES[@]}"
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
        fi

        [[ $fail_count -gt 0 ]] && exit 1
    fi
}

# Run main function
main "$@"
