#!/bin/bash
#
# run_seed_sensitivity.sh - Submit seed-sensitivity ensemble runs
#
# Sweeps the initial seed counts for the Bay Area Cov19-S1 + Cov19-S2
# 2-disease scenario. The paper baseline (Cov19-S1 = 20, Cov19-S2 = 5)
# has a 4x within-scenario asymmetry; this sweep separates seed-count
# effects from coupling effects on peak timing and peak magnitude.
#
# Cases:
#   seed_equal  : Cov19-S1 = 20, Cov19-S2 = 20  (no asymmetry)
#   seed_half   : Cov19-S1 = 10, Cov19-S2 =  3  (baseline halved, ratio kept)
#   seed_double : Cov19-S1 = 40, Cov19-S2 = 10  (baseline doubled, ratio kept)
#
# All runs use Bay Area population (6.78M agents, 1 GPU, 1 node), 730 days.
#
# Usage:
#   ./run_seed_sensitivity.sh [OPTIONS]
#
# Options:
#   -d, --dry-run         Show commands without executing
#   -e, --ensemble-size=N Number of ensemble runs (default: 100)
#   -n, --max-step=N      Override number of timesteps (uses input file default if unset)
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
MAX_STEP=""
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

# Verify run script exists
if [[ ! -x "$RUN_SCRIPT" ]]; then
    echo -e "${RED}ERROR:${NC} run_exaepi.sh not found at ${RUN_SCRIPT}" >&2
    exit 1
fi

# Define sweep cases
CASES=(
    "bay_02D_Cov19S1S2_seed_equal"
    "bay_02D_Cov19S1S2_seed_half"
    "bay_02D_Cov19S1S2_seed_double"
)

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Seed-sensitivity sweep: ${#CASES[@]} cases${NC}"
echo -e "${BLUE}  Ensemble size: ${ENSEMBLE_SIZE}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Symlink seed-sensitivity inputs into the main inputs/ directory so that
# run_exaepi.sh's find_input_file() can locate them. Matches the layout
# convention used by sensitivity/run_sensitivity.sh.
MAIN_INPUTS="${PROJECT_DIR}/inputs"
LINKED=()
for case_name in "${CASES[@]}"; do
    src="${INPUTS_DIR}/inputs_${case_name}"
    dst="${MAIN_INPUTS}/inputs_${case_name}"
    if [[ ! -f "$src" ]]; then
        echo -e "${RED}ERROR:${NC} Input file not found: $src" >&2
        exit 1
    fi
    # Create or refresh the symlink. -L catches existing symlinks (including
    # broken ones from a different filesystem); -e by itself would miss them.
    # Real files at $dst are left alone.
    if [[ -L "$dst" || ! -e "$dst" ]]; then
        ln -sfn "$src" "$dst"
        LINKED+=("$dst")
    fi
done

# Ensemble parent directory (separate from the cross-immunity / co-susceptibility sweeps)
ENSEMBLE_PARENT=".seed_sensitivity"
mkdir -p "${PROJECT_DIR}/${ENSEMBLE_PARENT}"

# Submit each case
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

# Symlinks are left in place so re-runs work without re-linking.

exit $FAIL
