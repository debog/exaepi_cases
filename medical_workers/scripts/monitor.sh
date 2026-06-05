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

    if [[ ${#ensemble_dirs[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No ensemble directories found in ${PROJECT_DIR}${NC}"
        echo -e "${YELLOW}Looking for: .ensemble_*/${NC}"
        echo ""
    else
        echo -e "${BOLD}${BLUE}========================================${NC}"
        echo -e "${BOLD}${BLUE}Monitoring ${#ensemble_dirs[@]} ensemble(s)${NC}"
        echo -e "${BOLD}${BLUE}========================================${NC}"
        echo ""

        for ensemble_dir in "${ensemble_dirs[@]}"; do
            dir_basename=$(basename "$ensemble_dir")
            case_name=$(echo "$dir_basename" | sed -E 's/^\.ensemble_(.*)_[^_]+$/\1/')
            platform=$(echo "$dir_basename" | sed -E 's/^\.ensemble_.*_([^_]+)$/\1/')

            # Check for completion statistics first
            if compgen -G "${ensemble_dir}"/output_*_mean.dat > /dev/null 2>&1; then
                # Completed - show concise output
                echo -e "${CYAN}${case_name}${NC} ${BOLD}[${platform}]${NC} ${GREEN}✓ Completed${NC}"
            else
                # In progress - show detailed output
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

                echo ""
            fi
        done
    fi

    echo -e "${BOLD}Refreshing in 2 minutes... (Ctrl+C to exit)${NC}"
    sleep 2m
done
