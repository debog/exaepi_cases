#!/bin/bash
#
# run_sensitivity.sh - Submit sensitivity analysis ensemble runs
#
# This script submits all 10 sensitivity analysis cases as ensemble runs
# using the existing run_exaepi.sh infrastructure.
#
# Sweeps:
#   1. Co-immunity:       0.50, 0.70, 0.85*, 0.925, 1.00  (Cov19-S1 + Cov19-S2)
#   2. Co-susceptibility: 0.75, 1.0, 1.5*, 2.0, 3.0       (Cov19-S1 + Flu-S1)
#   (* = baseline value used in the paper)
#
# All runs use California population (33.9M agents, 4 GPUs, 1 node).
# Each case runs 100 ensemble realizations over 730 simulated days.
#
# Usage:
#   ./run_sensitivity.sh [OPTIONS]
#
# Options:
#   -n, --dry-run         Show commands without executing
#   -e, --ensemble-size=N Number of ensemble runs (default: 100)
#   -s, --sweep=NAME      Run only one sweep: "coimm" or "cosus" (default: both)
#   -v, --verbose         Enable verbose output
#   -h, --help            Show this help message

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUN_SCRIPT="${PROJECT_DIR}/scripts/run_exaepi.sh"
INPUTS_DIR="${SCRIPT_DIR}/inputs"

# Defaults
DRY_RUN=""
ENSEMBLE_SIZE=100
SWEEP="both"
VERBOSE=""
EXTRA_ARGS=""

# Color output
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

show_help() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run)       DRY_RUN="--dry-run"; shift ;;
        -e|--ensemble-size) ENSEMBLE_SIZE="$2"; shift 2 ;;
        --ensemble-size=*)  ENSEMBLE_SIZE="${1#*=}"; shift ;;
        -s|--sweep)         SWEEP="$2"; shift 2 ;;
        --sweep=*)          SWEEP="${1#*=}"; shift ;;
        -v|--verbose)       VERBOSE="--verbose"; shift ;;
        -h|--help)          show_help ;;
        *)                  EXTRA_ARGS="$EXTRA_ARGS $1"; shift ;;
    esac
done

# Verify run script exists
if [[ ! -x "$RUN_SCRIPT" ]]; then
    echo -e "${RED}ERROR:${NC} run_exaepi.sh not found at ${RUN_SCRIPT}" >&2
    exit 1
fi

# Define sweep cases
COIMM_CASES=(
    "CA_02D_Cov19S1S2_coimm050"
    "CA_02D_Cov19S1S2_coimm070"
    "CA_02D_Cov19S1S2_coimm085"
    "CA_02D_Cov19S1S2_coimm0925"
    "CA_02D_Cov19S1S2_coimm100"
)

COSUS_CASES=(
    "CA_02D_Cov19S1_FluS1_cosus075"
    "CA_02D_Cov19S1_FluS1_cosus100"
    "CA_02D_Cov19S1_FluS1_cosus150"
    "CA_02D_Cov19S1_FluS1_cosus200"
    "CA_02D_Cov19S1_FluS1_cosus300"
)

# Collect cases to run
CASES=()
case "$SWEEP" in
    coimm)  CASES=("${COIMM_CASES[@]}") ;;
    cosus)  CASES=("${COSUS_CASES[@]}") ;;
    both)   CASES=("${COIMM_CASES[@]}" "${COSUS_CASES[@]}") ;;
    *)      echo -e "${RED}ERROR:${NC} Unknown sweep: $SWEEP (use coimm, cosus, or both)" >&2; exit 1 ;;
esac

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Sensitivity Analysis: ${#CASES[@]} cases${NC}"
echo -e "${BLUE}  Ensemble size: ${ENSEMBLE_SIZE}${NC}"
echo -e "${BLUE}  Sweep: ${SWEEP}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# The run_exaepi.sh script looks for input files in its own inputs/ directory.
# We need to temporarily copy (or symlink) our sensitivity inputs there so
# that find_input_file() can locate them.  Alternatively, we can place the
# sensitivity inputs directly in the main inputs/ dir.  We choose symlinks
# to keep the separation clean.

MAIN_INPUTS="${PROJECT_DIR}/inputs"
LINKED=()
for case_name in "${CASES[@]}"; do
    src="${INPUTS_DIR}/inputs_${case_name}"
    dst="${MAIN_INPUTS}/inputs_${case_name}"
    if [[ ! -f "$src" ]]; then
        echo -e "${RED}ERROR:${NC} Input file not found: $src" >&2
        exit 1
    fi
    if [[ ! -e "$dst" ]]; then
        ln -s "$src" "$dst"
        LINKED+=("$dst")
    fi
done

# Submit each case
SUCCESS=0
FAIL=0
for case_name in "${CASES[@]}"; do
    echo -e "${GREEN}>>> Submitting: ${case_name}${NC}"
    if "$RUN_SCRIPT" --case="${case_name}" --mode=batch --ensemble \
       --ensemble-size="${ENSEMBLE_SIZE}" ${DRY_RUN} ${VERBOSE} ${EXTRA_ARGS}; then
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

# Clean up symlinks (optional — leave them so re-runs work)
# for lnk in "${LINKED[@]}"; do rm -f "$lnk"; done

exit $FAIL
