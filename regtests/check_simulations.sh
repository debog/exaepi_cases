#!/bin/bash
# Check simulation completion status for ExaEpi regression tests
#
# Usage: check_simulations.sh <baseline|test> [machine]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
TARGET_DIR="$1"
MACHINE="$2"

if [[ -z "$TARGET_DIR" ]]; then
    echo "Usage: $0 <baseline|test> [machine]"
    echo "Example: $0 baseline"
    echo "Example: $0 test dane"
    exit 1
fi

# Determine directory to check
if [[ "$TARGET_DIR" == "baseline" ]]; then
    CHECK_DIR="baselines"
elif [[ "$TARGET_DIR" == "test" ]]; then
    CHECK_DIR="tests"
else
    CHECK_DIR="$TARGET_DIR"
fi

if [[ ! -d "$CHECK_DIR" ]]; then
    echo "Error: Directory $CHECK_DIR does not exist"
    exit 1
fi

# Determine machine
if [[ -z "$MACHINE" ]]; then
    # Auto-detect machine
    if [[ -n "$LCHOST" ]]; then
        MACHINE="$LCHOST"
    elif [[ -n "$NERSC_HOST" ]]; then
        MACHINE="$NERSC_HOST"
    else
        MACHINE="linux"
    fi
fi

echo "Checking simulations in $CHECK_DIR/ for machine: $MACHINE"
echo "============================================================"
echo ""

# Find all directories matching the machine
DIRS=$(find "$CHECK_DIR" -maxdepth 1 -type d -name "*.$MACHINE" | sort)

if [[ -z "$DIRS" ]]; then
    echo "No simulation directories found for machine: $MACHINE"
    exit 0
fi

TOTAL=0
SUCCESS=0
FAILED=0
RUNNING=0
PENDING=0

# Check each directory
for DIR in $DIRS; do
    TOTAL=$((TOTAL + 1))
    CASENAME=$(basename "$DIR")

    # Initialize status
    STATUS="UNKNOWN"
    ISSUES=()

    # Check for error indicators
    BACKTRACE=$(find "$DIR" -name "Backtrace*" 2>/dev/null | wc -l)
    COREDUMP=$(find "$DIR" -name "*.core" 2>/dev/null | wc -l)

    # Find output log
    LOGFILE=$(ls "$DIR"/out.*.log 2>/dev/null | head -1)

    # Check if directory only contains input files (not run yet)
    OUTPUT_FILES=$(find "$DIR" -type f \( -name "cases*" -o -name "plt*" -o -name "out.*.log" \) 2>/dev/null | wc -l)
    if [[ $OUTPUT_FILES -eq 0 ]]; then
        STATUS="PENDING"
        PENDING=$((PENDING + 1))
        printf "  ${YELLOW}%-35s [PENDING]${NC} (not run yet)\n" "$CASENAME"
        continue
    fi

    # Perform checks
    if [[ $BACKTRACE -gt 0 ]]; then
        ISSUES+=("Found $BACKTRACE Backtrace file(s)")
    fi

    if [[ $COREDUMP -gt 0 ]]; then
        ISSUES+=("Found $COREDUMP core dump file(s)")
    fi

    if [[ -z "$LOGFILE" ]]; then
        ISSUES+=("No output log file found")
    else
        # Check if log contains finalization message
        if grep -q "AMReX.*finalized" "$LOGFILE" 2>/dev/null; then
            # Check for error messages (but exclude false positives)
            ERROR_COUNT=$(grep -i "error\|fail\|abort" "$LOGFILE" 2>/dev/null | \
                         grep -v "error_est\|Solver failure\|error tolerance\|fail-safe\|error check" | \
                         wc -l)

            if [[ $ERROR_COUNT -gt 0 ]]; then
                ISSUES+=("Found $ERROR_COUNT error message(s) in log")
            fi
        else
            # Check if simulation might still be running
            # Method 1: Check if log file was modified in last 10 minutes
            if [[ -n "$(find "$LOGFILE" -mmin -10 2>/dev/null)" ]]; then
                STATUS="RUNNING"
                RUNNING=$((RUNNING + 1))
            # Method 2: Check for run script or slurm job
            elif pgrep -f "$(basename $DIR)" >/dev/null 2>&1 || \
                 squeue -u $USER 2>/dev/null | grep -q "$(basename $DIR | cut -d. -f1)"; then
                STATUS="RUNNING"
                RUNNING=$((RUNNING + 1))
            # Method 3: Check if there are open file descriptors in this directory
            elif lsof +D "$DIR" >/dev/null 2>&1; then
                STATUS="RUNNING"
                RUNNING=$((RUNNING + 1))
            else
                ISSUES+=("Log does not contain 'AMReX finalized' message")
            fi
        fi

        # Check for expected output files (cases* files)
        CASES_COUNT=$(ls "$DIR"/cases* 2>/dev/null | wc -l)
        if [[ $CASES_COUNT -eq 0 ]] && [[ "$STATUS" != "RUNNING" ]] && [[ "$STATUS" != "PENDING" ]]; then
            ISSUES+=("No cases* output files found")
        fi
    fi

    # Determine final status
    if [[ "$STATUS" == "RUNNING" ]]; then
        printf "  ${YELLOW}%-35s [RUNNING]${NC}\n" "$CASENAME"
    elif [[ ${#ISSUES[@]} -eq 0 ]]; then
        STATUS="SUCCESS"
        SUCCESS=$((SUCCESS + 1))
        printf "  ${GREEN}%-35s [SUCCESS]${NC}\n" "$CASENAME"
    else
        STATUS="FAILED"
        FAILED=$((FAILED + 1))
        printf "  ${RED}%-35s [FAILED]${NC}\n" "$CASENAME"
        for ISSUE in "${ISSUES[@]}"; do
            printf "      ${RED}✗ %s${NC}\n" "$ISSUE"
        done
    fi
done

echo ""
echo "============================================================"
echo "Summary:"
echo "  Total:   $TOTAL"
echo "  Success:  $SUCCESS"
echo "  Failed:  $FAILED"
echo "  Running: $RUNNING"
echo "  Pending: $PENDING"
echo ""

# Exit with error only if there are actual failures
# Running and Pending simulations are not considered failures
if [[ $FAILED -gt 0 ]]; then
    echo "Note: ${FAILED} simulation(s) failed. See details above."
    exit 1
elif [[ $RUNNING -gt 0 ]] || [[ $PENDING -gt 0 ]]; then
    echo "Note: Some simulations are still running or pending."
    exit 0
else
    exit 0
fi
