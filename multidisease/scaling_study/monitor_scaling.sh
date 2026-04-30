#!/bin/bash
#
# monitor_scaling.sh - Monitor scaling-study runs
#
# Watches single-runs under .scaling_study/ in the project root for the
# current platform, refreshing every 1 minute.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCALE_DIR="${PROJECT_DIR}/.scaling_study"

if [[ -n "${LCHOST}" ]]; then
    CURRENT_PLATFORM=$(echo "${LCHOST}" | tr '[:upper:]' '[:lower:]')
elif [[ -n "${NERSC_HOST}" ]]; then
    CURRENT_PLATFORM="perlmutter"
else
    CURRENT_PLATFORM="unknown"
fi

if [[ -t 1 ]]; then
    BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
else
    BOLD=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; RED=''; NC=''
fi

for iteration in {1..1000000}; do
    clear
    echo -e "${BOLD}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""

    if [[ ! -d "$SCALE_DIR" ]]; then
        echo -e "${YELLOW}Scaling-study directory not found at: ${SCALE_DIR}${NC}"
        echo ""
        echo -e "${BOLD}Refreshing in 1 minute... (Ctrl+C to exit)${NC}"
        sleep 1m
        continue
    fi

    echo -e "${BOLD}${BLUE}========================================${NC}"
    echo -e "${BOLD}${BLUE}Scaling study [${CURRENT_PLATFORM}]${NC}"
    echo -e "${BOLD}${BLUE}========================================${NC}"
    echo ""

    run_dirs=()
    while IFS= read -r -d '' rdir; do
        run_dirs+=("$rdir")
    done < <(find "$SCALE_DIR" -maxdepth 1 -type d -name "run_*_${CURRENT_PLATFORM}" -print0 | sort -z)

    if [[ ${#run_dirs[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No run directories found for platform '${CURRENT_PLATFORM}' in ${SCALE_DIR}${NC}"
        echo ""
    else
        for rd in "${run_dirs[@]}"; do
            name=$(basename "$rd")
            # Job is complete if a "Job finished at" line appears in any scale_*.out
            done_marker=""
            if compgen -G "${rd}/scale_*.out" > /dev/null 2>&1; then
                if grep -l "Job finished at" "${rd}"/scale_*.out > /dev/null 2>&1; then
                    done_marker="yes"
                fi
            fi
            if [[ -n "$done_marker" ]]; then
                # The job script appends "Job finished at" unconditionally,
                # so the marker is present even on a crashed run.  Treat
                # the run as cleanly completed only if the AMReX TinyProfiler
                # produced its summary line and no OOM / crash markers
                # appear in the .out / .err files.
                logf=$(ls -t "${rd}"/scale_*.out 2>/dev/null | head -1)
                ranks=$(grep "MPI initialized with" "$logf" 2>/dev/null | head -1 |
                        awk '{print $4}')
                # Line format:
                #   TinyProfiler total time across processes [min...avg...max]: 1594 ... 1594 ... 1595
                # Split on '[' or ']' -> field 3 is ': 1594 ... 1594 ... 1595';
                # split that on '...' -> field 3 is the max value.
                total=$(grep "TinyProfiler total time" "$logf" 2>/dev/null | head -1 |
                        awk -F'[][]' '{print $3}' | awk -F'\\.\\.\\.' '{print $3}' | tr -d ' :')

                # Detect failure: missing TinyProfiler output or known
                # OOM/crash markers in the run logs.
                fail_reason=""
                [[ -z "$total" ]] && fail_reason="no profiler output"
                if grep -qiE 'out of memory|oom-kill|^Killed$|bad_alloc|out_of_memory_handler|hipError|cudaError|RSMI_STATUS_OUT_OF_RESOURCES|Resource temporarily unavailable' \
                       "${rd}"/scale_*.out "${rd}"/scale_*.err 2>/dev/null; then
                    fail_reason="OOM/crash"
                fi

                if [[ -z "$fail_reason" ]]; then
                    echo -e "${CYAN}${name}${NC} ${GREEN}✓ Completed${NC}  ranks=${ranks:-?}  total=${total}s"
                else
                    echo -e "${CYAN}${name}${NC} ${RED}✗ Failed${NC}  ranks=${ranks:-?}  reason=${fail_reason}"
                fi
            else
                echo -e "${CYAN}${name}${NC}"
                # Show last status line from the most recent .out, if any
                logf=$(ls -t "${rd}"/scale_*.out 2>/dev/null | head -1)
                if [[ -n "$logf" ]]; then
                    last=$(tail -3 "$logf" 2>/dev/null | head -1)
                    echo "  $last"
                else
                    echo -e "  ${YELLOW}(queued or no output yet)${NC}"
                fi
                echo ""
            fi
        done
    fi

    echo -e "${BOLD}Refreshing in 1 minute... (Ctrl+C to exit)${NC}"
    sleep 1m
done
