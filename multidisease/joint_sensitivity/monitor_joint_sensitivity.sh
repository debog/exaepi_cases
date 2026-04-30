#!/bin/bash
#
# monitor_joint_sensitivity.sh - Monitor joint-sensitivity ensemble runs
#
# Watches ensembles under .joint_sensitivity/ in the project root for
# the current platform, refreshing every 2 minutes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SWEEP_DIR="${PROJECT_DIR}/.joint_sensitivity"

if [[ -n "${LCHOST}" ]]; then
    CURRENT_PLATFORM=$(echo "${LCHOST}" | tr '[:upper:]' '[:lower:]')
elif [[ -n "${NERSC_HOST}" ]]; then
    CURRENT_PLATFORM="perlmutter"
else
    CURRENT_PLATFORM="unknown"
fi

if [[ -t 1 ]]; then
    BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    BOLD=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; NC=''
fi

for iteration in {1..1000000}; do
    clear
    echo -e "${BOLD}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""

    if [[ ! -d "$SWEEP_DIR" ]]; then
        echo -e "${YELLOW}Joint-sensitivity directory not found at: ${SWEEP_DIR}${NC}"
        echo ""
        echo -e "${BOLD}Refreshing in 2 minutes... (Ctrl+C to exit)${NC}"
        sleep 2m
        continue
    fi

    echo -e "${BOLD}${BLUE}========================================${NC}"
    echo -e "${BOLD}${BLUE}Joint-sensitivity sweep [${CURRENT_PLATFORM}]${NC}"
    echo -e "${BOLD}${BLUE}========================================${NC}"
    echo ""

    ensemble_dirs=()
    while IFS= read -r -d '' edir; do
        ensemble_dirs+=("$edir")
    done < <(find "$SWEEP_DIR" -maxdepth 1 -type d -name ".ensemble_*_${CURRENT_PLATFORM}" -print0 | sort -z)

    if [[ ${#ensemble_dirs[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No ensemble directories found for platform '${CURRENT_PLATFORM}' in ${SWEEP_DIR}${NC}"
        echo ""
    else
        for ensemble_dir in "${ensemble_dirs[@]}"; do
            dir_basename=$(basename "$ensemble_dir")
            case_name=$(echo "$dir_basename" | sed -E 's/^\.ensemble_(.*)_[^_]+$/\1/')
            platform=$(echo "$dir_basename" | sed -E 's/^\.ensemble_.*_([^_]+)$/\1/')

            if compgen -G "${ensemble_dir}"/output_*_mean.dat > /dev/null 2>&1; then
                echo -e "${CYAN}${case_name}${NC} ${BOLD}[${platform}]${NC} ${GREEN}✓ Completed${NC}"
            else
                echo -e "${CYAN}${case_name}${NC} ${BOLD}[${platform}]${NC}"

                if [[ -f "${ensemble_dir}/job_id.txt" ]]; then
                    job_id=$(cat "${ensemble_dir}/job_id.txt" 2>/dev/null)
                    if [[ -n "$job_id" ]] && command -v squeue &>/dev/null; then
                        job_status=$(squeue -j "$job_id" -h -o "%T" 2>/dev/null)
                        if [[ -n "$job_status" ]]; then
                            echo -e "  Status: ${GREEN}${job_status}${NC}"
                        fi
                    fi
                fi

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
