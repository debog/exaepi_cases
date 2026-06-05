#!/bin/bash
#
# job_lib.sh - scheduler-agnostic job-status helpers (Slurm + Flux).
#
# Sourced by monitor.sh and restart_ensemble.sh so they work on both Slurm
# platforms (Matrix, Dane) and Flux platforms (Tuolumne). Tuolumne is Flux: its
# Slurm `squeue` wrapper may not honor `-o "%T"` (it echoes the format back) or
# may report nothing, so we fall back to `flux jobs`.
#

# get_job_status JOBID
#   Echoes one of:
#     <state>  a scheduler state string (RUNNING, PENDING, RUN, SCHED, INACTIVE, ...)
#     GONE     the scheduler answered but the job is not active (finished/failed/not queued)
#     UNKNOWN  could not determine (no scheduler, or the query did not work)
get_job_status() {
    local jid="$1" st rc
    [[ -z "$jid" ]] && { echo "UNKNOWN"; return 0; }

    if command -v squeue &> /dev/null; then
        st=$(squeue -j "$jid" -h -o "%T" 2>/dev/null); rc=$?
        if [[ -n "$st" && "$st" != *%* ]]; then
            echo "$st"; return 0                       # real Slurm state
        fi
        if [[ $rc -eq 0 && "$st" != *%* ]] && ! command -v flux &> /dev/null; then
            echo "GONE"; return 0                       # Slurm-only host, job not in queue
        fi
        # else: squeue echoed the format unexpanded (Flux wrapper) or there is a
        # Flux scheduler to consult -> fall through to flux.
    fi

    if command -v flux &> /dev/null; then
        st=$(flux jobs -a --no-header --format='{state}' "$jid" 2>/dev/null | head -n1)
        if [[ -n "$st" && "$st" != *%* ]]; then
            echo "$st"; return 0                       # Flux state (incl. INACTIVE)
        fi
        echo "GONE"; return 0                           # Flux present, job not found
    fi

    echo "UNKNOWN"
    return 0
}

# job_state_is_active STATE  ->  return 0 if the state means queued/running
job_state_is_active() {
    case "$1" in
        # Slurm active states
        PENDING|RUNNING|CONFIGURING|COMPLETING|SUSPENDED|RESIZING|REQUEUED|RESV_DEL_HOLD) return 0 ;;
        # Flux active states
        DEPEND|PRIORITY|SCHED|RUN|CLEANUP) return 0 ;;
        # GONE, UNKNOWN, COMPLETED, FAILED, TIMEOUT, CANCELLED, NODE_FAIL, INACTIVE, ...
        *) return 1 ;;
    esac
}
