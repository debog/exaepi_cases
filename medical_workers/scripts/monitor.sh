#!/bin/bash
#
# monitor.sh - Monitor ExaEpi ensemble runs
#
# This script monitors the progress of ensemble simulations by checking
# output files in .ensemble_* directories.
#
# Usage:
#   ./monitor.sh [PREFIX]
#
# Arguments:
#   PREFIX  Optional: monitor only cases starting with PREFIX (e.g., bay, CA, US)
#           If omitted, monitors all .ensemble_*/ directories

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# scheduler-agnostic job-status helpers (Slurm + Flux)
source "${SCRIPT_DIR}/job_lib.sh"

# Detect the platform this monitor is running on (matches run_exaepi.sh's
# detect_platform), so we only report ensembles created for THIS platform.
detect_platform() {
    if [[ -n "${LCHOST}" ]]; then
        echo "${LCHOST}" | tr '[:upper:]' '[:lower:]'
    elif [[ -n "${NERSC_HOST}" ]]; then
        echo "perlmutter"
    elif command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
        echo "linux-gpu"
    elif command -v mpirun &> /dev/null || command -v mpiexec &> /dev/null; then
        echo "linux"
    else
        echo "desktop"
    fi
}
CURRENT_PLATFORM="$(detect_platform)"

# Platform embedded in an ensemble dir basename, tolerating the optional cost-case
# _n<ntasks> suffix:  .ensemble_<case>_<platform>[_n<N>]
ensemble_platform() {
    local name="${1#.ensemble_}"
    [[ "$name" =~ _n[0-9]+$ ]] && name="${name%_*}"
    echo "${name##*_}"
}

# Determine which prefixes to monitor
PREFIXES=()
if [[ $# -eq 0 ]]; then
    # Monitor all ensemble directories
    MONITOR_ALL=true
else
    # Monitor specific prefix
    MONITOR_ALL=false
    PREFIXES=("$1")
fi

# Color output
if [[ -t 1 ]]; then
    BOLD='\033[1m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    BOLD=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    NC=''
fi

# Monitor loop
for iteration in {1..1000000}; do
    clear
    echo -e "${BOLD}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""

    # Find all ensemble directories
    ensemble_dirs=()
    if [[ "$MONITOR_ALL" == "true" ]]; then
        while IFS= read -r -d '' edir; do
            ensemble_dirs+=("$edir")
        done < <(find "$PROJECT_DIR" -maxdepth 1 -type d -name ".ensemble_*" -print0 | sort -z)
    else
        for prefix in "${PREFIXES[@]}"; do
            while IFS= read -r -d '' edir; do
                ensemble_dirs+=("$edir")
            done < <(find "$PROJECT_DIR" -maxdepth 1 -type d -name ".ensemble_${prefix}*" -print0 | sort -z)
        done
    fi

    # Keep only the ensembles for the platform this monitor runs on.
    platform_dirs=()
    for edir in "${ensemble_dirs[@]}"; do
        if [[ "$(ensemble_platform "$(basename "$edir")")" == "$CURRENT_PLATFORM" ]]; then
            platform_dirs+=("$edir")
        fi
    done
    ensemble_dirs=("${platform_dirs[@]}")

    if [[ ${#ensemble_dirs[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No ensemble directories for platform '${CURRENT_PLATFORM}' in ${PROJECT_DIR}${NC}"
        echo -e "${YELLOW}Looking for: .ensemble_*_${CURRENT_PLATFORM}[_n<ntasks>]/${NC}"
        echo ""
    else
        echo -e "${BOLD}${BLUE}========================================${NC}"
        echo -e "${BOLD}${BLUE}Monitoring ${#ensemble_dirs[@]} ensemble(s) on ${CURRENT_PLATFORM}${NC}"
        echo -e "${BOLD}${BLUE}========================================${NC}"
        echo ""

        for ensemble_dir in "${ensemble_dirs[@]}"; do
            dir_basename=$(basename "$ensemble_dir")
            # Parse .ensemble_<case>_<platform>[_n<ntasks>]
            parse_name="${dir_basename#.ensemble_}"
            ntasks=""
            if [[ "$parse_name" =~ _n[0-9]+$ ]]; then
                ntasks="${parse_name##*_}"
                parse_name="${parse_name%_*}"
            fi
            platform="${parse_name##*_}"
            case_name="${parse_name%_*}"

            # Check for completion statistics first
            if compgen -G "${ensemble_dir}"/output_*_mean.dat > /dev/null 2>&1; then
                # Completed - show concise output
                echo -e "${CYAN}${case_name}${NC} ${BOLD}[${platform}]${NC}${ntasks:+ (${ntasks})} ${GREEN}✓ Completed${NC}"
            else
                # In progress - show detailed output
                echo -e "${CYAN}${case_name}${NC} ${BOLD}[${platform}]${NC}${ntasks:+ (${ntasks})}"

                # Check if job is queued/running (Slurm or Flux)
                if [[ -f "${ensemble_dir}/job_id.txt" ]]; then
                    job_id=$(cat "${ensemble_dir}/job_id.txt" 2>/dev/null)
                    job_status=$(get_job_status "$job_id")
                    if [[ "$job_status" == "GONE" ]]; then
                        echo -e "  Status: ${YELLOW}not in queue (finished or failed)${NC}"
                    elif [[ -n "$job_status" && "$job_status" != "UNKNOWN" ]]; then
                        echo -e "  Status: ${GREEN}${job_status}${NC}"
                    fi
                fi

                # Show progress from output files
                if compgen -G "${ensemble_dir}/*.out" > /dev/null 2>&1; then
                    cat "${ensemble_dir}"/*.out 2>/dev/null | grep "Run" | tail -n 3 | sed 's/^/  /'
                else
                    echo -e "  ${YELLOW}(no output yet)${NC}"
                fi

                echo ""
            fi
        done
    fi

    echo -e "${BOLD}Refreshing in 2 minutes... (Ctrl+C to exit)${NC}"
    sleep 2m
done
