#!/bin/bash
#
# run_joint_sensitivity.sh - Submit joint cross-immunity x co-susceptibility sweep
#
# 3x3 sweep over:
#   cross-immunity   (Cov19-S1 <-> Cov19-S2)  : 0.50, 0.85*, 1.00
#   co-susceptibility (Cov-Flu, off-diagonal) : 1.00, 1.50*, 3.00
#   (* = baseline value used in the paper)
#
# All runs use California population (33.9M agents, 4 GPUs, 1 node) for
# the 3-disease scenario (Cov19-S1, Cov19-S2, Flu-S1), 730 simulated days,
# 100 ensemble realizations per case.
#
# Usage:
#   ./run_joint_sensitivity.sh [OPTIONS]
#
# Options:
#   -d, --dry-run         Show commands without executing
#   -e, --ensemble-size=N Number of ensemble runs (default: 100)
#   -n, --max-step=N      Override number of timesteps
#   -v, --verbose         Enable verbose output
#   -h, --help            Show this help message

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUN_SCRIPT="${PROJECT_DIR}/scripts/run_exaepi.sh"
INPUTS_DIR="${SCRIPT_DIR}/inputs"

DRY_RUN=""
ENSEMBLE_SIZE=100
MAX_STEP=""
VERBOSE=""
EXTRA_ARGS=""

if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

show_help() { sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dry-run)       DRY_RUN="--dry-run"; shift ;;
        -e|--ensemble-size) ENSEMBLE_SIZE="$2"; shift 2 ;;
        --ensemble-size=*)  ENSEMBLE_SIZE="${1#*=}"; shift ;;
        -n|--max-step)      MAX_STEP="$2"; shift 2 ;;
        --max-step=*)       MAX_STEP="${1#*=}"; shift ;;
        -v|--verbose)       VERBOSE="--verbose"; shift ;;
        -h|--help)          show_help ;;
        *)                  EXTRA_ARGS="$EXTRA_ARGS $1"; shift ;;
    esac
done

if [[ ! -x "$RUN_SCRIPT" ]]; then
    echo -e "${RED}ERROR:${NC} run_exaepi.sh not found at ${RUN_SCRIPT}" >&2
    exit 1
fi

CASES=()
for ci in 050 085 100; do
    for cs in 100 150 300; do
        CASES+=("CA_03D_Cov19S1S2_FluS1_coimm${ci}_cosus${cs}")
    done
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Joint sensitivity sweep: ${#CASES[@]} cases${NC}"
echo -e "${BLUE}  Ensemble size: ${ENSEMBLE_SIZE}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

MAIN_INPUTS="${PROJECT_DIR}/inputs"
LINKED=()
for case_name in "${CASES[@]}"; do
    src="${INPUTS_DIR}/inputs_${case_name}"
    dst="${MAIN_INPUTS}/inputs_${case_name}"
    if [[ ! -f "$src" ]]; then
        echo -e "${RED}ERROR:${NC} Input file not found: $src" >&2
        exit 1
    fi
    # Refresh symlink if it exists (handles broken cross-filesystem links).
    if [[ -L "$dst" || ! -e "$dst" ]]; then
        ln -sfn "$src" "$dst"
        LINKED+=("$dst")
    fi
done

ENSEMBLE_PARENT=".joint_sensitivity"
mkdir -p "${PROJECT_DIR}/${ENSEMBLE_PARENT}"

SUCCESS=0
FAIL=0
for case_name in "${CASES[@]}"; do
    echo -e "${GREEN}>>> Submitting: ${case_name}${NC}"
    MAX_STEP_ARG=""
    [[ -n "$MAX_STEP" ]] && MAX_STEP_ARG="--max-step=${MAX_STEP}"
    if "$RUN_SCRIPT" --case="${case_name}" --mode=batch --ensemble \
       --ensemble-size="${ENSEMBLE_SIZE}" --ensemble-parent-dir="${ENSEMBLE_PARENT}" \
       ${MAX_STEP_ARG} ${DRY_RUN} ${VERBOSE} ${EXTRA_ARGS}; then
        SUCCESS=$((SUCCESS + 1))
    else
        echo -e "${YELLOW}WARNING:${NC} Failed to submit ${case_name}" >&2
        FAIL=$((FAIL + 1))
    fi
    echo ""
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Summary: ${SUCCESS} submitted, ${FAIL} failed${NC}"
echo -e "${BLUE}========================================${NC}"

exit $FAIL
