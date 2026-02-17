#!/bin/bash
#
# monitor_sensitivity.sh - Monitor sensitivity analysis ensemble runs
#
# This script monitors the progress of all sensitivity analysis cases
# by checking the output files in the sensitivity subdirectories.
#
# Usage:
#   ./monitor_sensitivity.sh [SWEEP]
#
# Arguments:
#   SWEEP  Optional: monitor only one sweep (coimm, cosus, both)
#          If omitted, monitors all .sensitivity_*/ directories

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Determine which sweeps to monitor
SWEEPS=()
if [[ $# -eq 0 ]]; then
    # Find all sensitivity directories
    for dir in "${PROJECT_DIR}"/.sensitivity_*/; do
        if [[ -d "$dir" ]]; then
            sweep_name=$(basename "$dir" | sed 's/^\.sensitivity_//')
            SWEEPS+=("$sweep_name")
        fi
    done
    if [[ ${#SWEEPS[@]} -eq 0 ]]; then
        echo "No sensitivity directories found in ${PROJECT_DIR}"
        echo "Looking for: .sensitivity_*/"
        exit 1
    fi
else
    SWEEPS=("$1")
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

    for sweep in "${SWEEPS[@]}"; do
        sens_dir="${PROJECT_DIR}/.sensitivity_${sweep}"

        if [[ ! -d "$sens_dir" ]]; then
            echo -e "${YELLOW}Sweep '${sweep}' not found at: ${sens_dir}${NC}"
            echo ""
            continue
        fi

        echo -e "${BOLD}${BLUE}========================================${NC}"
        echo -e "${BOLD}${BLUE}Sweep: ${sweep}${NC}"
        echo -e "${BOLD}${BLUE}========================================${NC}"
        echo ""

        # Find all ensemble directories in this sensitivity directory
        ensemble_dirs=()
        while IFS= read -r -d '' edir; do
            ensemble_dirs+=("$edir")
        done < <(find "$sens_dir" -maxdepth 1 -type d -name ".ensemble_*" -print0 | sort -z)

        if [[ ${#ensemble_dirs[@]} -eq 0 ]]; then
            echo -e "${YELLOW}No ensemble directories found in ${sens_dir}${NC}"
            echo ""
            continue
        fi

        for ensemble_dir in "${ensemble_dirs[@]}"; do
            dir_basename=$(basename "$ensemble_dir")
            case_name=$(echo "$dir_basename" | sed -E 's/^\.ensemble_(.*)_[^_]+$/\1/')
            platform=$(echo "$dir_basename" | sed -E 's/^\.ensemble_.*_([^_]+)$/\1/')
            echo -e "${CYAN}${case_name}${NC} ${BOLD}[${platform}]${NC}"

            # Check if job is queued/running
            if [[ -f "${ensemble_dir}/job_id.txt" ]]; then
                job_id=$(cat "${ensemble_dir}/job_id.txt" 2>/dev/null)
                if [[ -n "$job_id" ]] && command -v squeue &>/dev/null; then
                    job_status=$(squeue -j "$job_id" -h -o "%T" 2>/dev/null)
                    if [[ -n "$job_status" ]]; then
                        echo -e "  Status: ${GREEN}${job_status}${NC}"
                    fi
                fi
            fi

            # Show progress from output files
            if compgen -G "${ensemble_dir}/*.out" > /dev/null 2>&1; then
                cat "${ensemble_dir}"/*.out 2>/dev/null | grep "Run" | tail -n 3 | sed 's/^/  /'
            else
                echo -e "  ${YELLOW}(no output yet)${NC}"
            fi

            # Check for completion statistics
            if compgen -G "${ensemble_dir}"/output_*_mean.dat > /dev/null 2>&1; then
                echo -e "  ${GREEN}✓ Statistics computed${NC}"
            fi

            echo ""
        done
    done

    echo -e "${BOLD}Refreshing in 2 minutes... (Ctrl+C to exit)${NC}"
    sleep 2m
done
