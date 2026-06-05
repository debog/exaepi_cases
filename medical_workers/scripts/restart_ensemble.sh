#!/bin/bash
#
# restart_ensemble.sh - resubmit incomplete ExaEpi ensemble jobs.
#
# The ensemble job (exaepi.job) already skips runs that finished and re-runs the
# incomplete ones, so a "restart" is just resubmitting the job for any ensemble
# that is neither complete nor currently queued/running. Run after a job hits the
# walltime, a node fails, or some replicates crashed.
#
# Usage:
#   ./restart_ensemble.sh [PREFIX] [--force]
#     PREFIX   only act on .ensemble_<PREFIX>*  (default: all ensembles)
#     --force  resubmit even if a job appears to be queued/running
#
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# scheduler-agnostic job-status helpers (Slurm + Flux)
source "${SCRIPT_DIR}/job_lib.sh"

PREFIX=""
FORCE=false
for a in "$@"; do
    case "$a" in
        --force) FORCE=true ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) PREFIX="$a" ;;
    esac
done

shopt -s nullglob
dirs=( "${PROJECT_DIR}"/.ensemble_${PREFIX}* )
if [[ ${#dirs[@]} -eq 0 ]]; then
    echo "No .ensemble_${PREFIX}* directories found in ${PROJECT_DIR}"
    exit 0
fi

submitted=0
for edir in "${dirs[@]}"; do
    [[ -d "$edir" ]] || continue
    name=$(basename "$edir")

    # Complete? ensemble statistics present -> nothing to do.
    if compgen -G "${edir}/output_*_mean.dat" > /dev/null 2>&1; then
        echo "[${name}] complete - skipping"
        continue
    fi

    # Already queued/running? skip unless --force (works under Slurm and Flux).
    if [[ "$FORCE" != true && -f "${edir}/job_id.txt" ]]; then
        jid=$(cat "${edir}/job_id.txt" 2>/dev/null)
        state=$(get_job_status "$jid")
        if job_state_is_active "$state"; then
            echo "[${name}] job ${jid} is ${state} - skipping"
            continue
        fi
        if [[ "$state" == "UNKNOWN" ]]; then
            echo "[${name}] job ${jid:-?} status unknown - skipping (use --force to resubmit)"
            continue
        fi
        # GONE / finished / failed -> fall through and resubmit
    fi

    if [[ ! -f "${edir}/exaepi.job" ]]; then
        echo "[${name}] no exaepi.job - skipping (recreate with run_exaepi.sh --ensemble)"
        continue
    fi

    echo "[${name}] resubmitting incomplete ensemble ..."
    if command -v sbatch &> /dev/null; then
        jid=$( (cd "$edir" && sbatch exaepi.job) | awk '{print $NF}')
        echo "$jid" > "${edir}/job_id.txt"
        echo "[${name}] submitted job ${jid}"
        submitted=$((submitted + 1))
    else
        echo "[${name}] no sbatch found; running the job script directly in the background"
        (cd "$edir" && nohup bash exaepi.job > resubmit.out 2>&1 &)
        submitted=$((submitted + 1))
    fi
done

echo ""
echo "Resubmitted ${submitted} ensemble(s). Monitor with: ./scripts/monitor.sh ${PREFIX}"
