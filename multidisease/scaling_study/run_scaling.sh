#!/bin/bash
#
# run_scaling.sh - Submit a strong-scaling sweep for CA and US scenarios
#
# For each scenario, generates one Flux/SLURM job per parallelism level.
# Each job runs the same input file at a different (nodes, ntasks) setting.
# Per-step compute and MPI costs are extracted from the AMReX TinyProfiler
# output written to the job .out file at the end of each run.
#
# Default parallelism levels (4 GPUs per node on Tuolumne):
#   CA  (33.9M agents): 1, 2, 4, 8 GPUs       (1, 1, 1, 2 nodes)
#   US (281M agents):   8, 16, 32, 64 GPUs    (2, 4, 8, 16 nodes)
#
# Usage:
#   ./run_scaling.sh [OPTIONS]
#
# Options:
#   -d, --dry-run         Generate job scripts but do not submit
#   -s, --scenario=NAME   Only run "CA" or "US" (default: both)
#   -h, --help            Show this help message

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INPUTS_DIR="${SCRIPT_DIR}/inputs"

# Defaults
DRY_RUN="false"
SCENARIO="both"

if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

show_help() { sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dry-run)   DRY_RUN="true"; shift ;;
        -s|--scenario)  SCENARIO="$2"; shift 2 ;;
        --scenario=*)   SCENARIO="${1#*=}"; shift ;;
        -h|--help)      show_help ;;
        *)              echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

# Detect platform (matches run_exaepi.sh convention)
if [[ -n "${LCHOST}" ]]; then
    PLATFORM=$(echo "${LCHOST}" | tr '[:upper:]' '[:lower:]')
elif [[ -n "${NERSC_HOST}" ]]; then
    PLATFORM="perlmutter"
else
    PLATFORM="linux"
fi

# Locate agent executable (matches the path used by other run scripts in this project)
AGENT_EXE=""
for cand in \
    "${HOME}/Codes/ExaEpi-builds/${PLATFORM}/bin/agent" \
    "${HOME}/Codes/ExaEpi-build/bin/agent" \
    "${HOME}/Codes/ExaEpi/build/bin/agent"; do
    if [[ -x "$cand" ]]; then
        AGENT_EXE="$cand"; break
    fi
done
if [[ -z "$AGENT_EXE" ]]; then
    echo -e "${RED}ERROR:${NC} Could not locate agent executable; set AGENT_EXE manually in this script." >&2
    exit 1
fi
echo -e "${GREEN}Using agent: ${AGENT_EXE}${NC}"
echo -e "${GREEN}Platform: ${PLATFORM}${NC}"
echo ""

# Define scaling configurations: (case, nodes, ntasks)
# ntasks = number of GPUs across all nodes (1 GPU per task)
declare -a CONFIGS_CA=(
    "CA_03D_scale 1 1"
    "CA_03D_scale 1 2"
    "CA_03D_scale 1 4"
    "CA_03D_scale 2 8"
)

declare -a CONFIGS_US=(
    "US_04D_scale 2 8"
    "US_04D_scale 4 16"
    "US_04D_scale 8 32"
    "US_04D_scale 16 64"
)

CONFIGS=()
case "$SCENARIO" in
    CA|ca)      CONFIGS=("${CONFIGS_CA[@]}") ;;
    US|us)      CONFIGS=("${CONFIGS_US[@]}") ;;
    both|all)   CONFIGS=("${CONFIGS_CA[@]}" "${CONFIGS_US[@]}") ;;
    *)          echo -e "${RED}ERROR:${NC} Unknown scenario: $SCENARIO" >&2; exit 1 ;;
esac

# Symlink input files into main inputs/ so the agent finds the data files.
MAIN_INPUTS="${PROJECT_DIR}/inputs"
for cfg in "${CONFIGS[@]}"; do
    case_name=$(echo "$cfg" | awk '{print $1}')
    src="${INPUTS_DIR}/inputs_${case_name}"
    dst="${MAIN_INPUTS}/inputs_${case_name}"
    if [[ -L "$dst" || ! -e "$dst" ]]; then
        ln -sfn "$src" "$dst"
    fi
done

PARENT_DIR="${PROJECT_DIR}/.scaling_study"
mkdir -p "$PARENT_DIR"

# Choose walltime based on case (rough upper bound for 50 simulated days)
estimate_walltime() {
    local case=$1; local ntasks=$2
    case "$case" in
        CA_03D_scale)
            # ~3 s/day at 4 GPUs; ~12 s/day at 1 GPU; 50 days => 600 s + buffer
            if   (( ntasks == 1 )); then echo "01:00:00"
            elif (( ntasks == 2 )); then echo "00:40:00"
            elif (( ntasks == 4 )); then echo "00:30:00"
            else                          echo "00:30:00"
            fi ;;
        US_04D_scale)
            # ~1.5 s/day at 32 GPUs => 75 s for 50 days; budget generously
            if   (( ntasks <= 8 ));  then echo "02:00:00"
            elif (( ntasks <= 16 )); then echo "01:30:00"
            elif (( ntasks <= 32 )); then echo "01:00:00"
            else                          echo "00:45:00"
            fi ;;
    esac
}

write_jobscript() {
    local case=$1
    local nodes=$2
    local ntasks=$3
    local rundir=$4
    local walltime=$(estimate_walltime "$case" "$ntasks")

    cat > "${rundir}/exaepi.job" <<EOF
#!/bin/bash
#SBATCH --job-name=scale_${case}_${ntasks}gpu
#SBATCH --nodes=${nodes}
#SBATCH --ntasks=${ntasks}
#SBATCH --time=${walltime}
#SBATCH --account=asccasc
#SBATCH --output=scale_%j.out
#SBATCH --error=scale_%j.err

echo "Job started at: \$(date)"
echo "Running on host: \$(hostname)"
echo "Working directory: \$(pwd)"
echo "Configuration: ${case}, nodes=${nodes}, ntasks=${ntasks}"
echo ""

export OMP_NUM_THREADS=1
export MPICH_GPU_SUPPORT_ENABLED=1

flux run --exclusive --nodes=${nodes} --ntasks ${ntasks} --gpus-per-task 1 \\
    ${AGENT_EXE} inputs_${case}

echo ""
echo "Job finished at: \$(date)"
EOF
}

stage_run_dir() {
    local case=$1
    local nodes=$2
    local ntasks=$3
    local rundir="${PARENT_DIR}/run_${case}_${ntasks}gpu_${PLATFORM}"

    mkdir -p "$rundir"
    # Copy input file (so each scaling run is self-contained for reproduction)
    cp "${INPUTS_DIR}/inputs_${case}" "${rundir}/inputs_${case}"
    # Symlink data files needed by the agent (population data lives in the main inputs/data area)
    for data_dep in BayArea.dat BayArea-wf.bin CA.dat CA-wf.bin US.dat US-wf.bin; do
        src="${PROJECT_DIR}/inputs/${data_dep}"
        if [[ -e "$src" && ! -e "${rundir}/${data_dep}" ]]; then
            ln -sfn "$src" "${rundir}/${data_dep}"
        fi
    done
    write_jobscript "$case" "$nodes" "$ntasks" "$rundir"
    echo "$rundir"
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Scaling study: ${#CONFIGS[@]} configurations${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

SUCCESS=0
FAIL=0
for cfg in "${CONFIGS[@]}"; do
    read -r case_name nodes ntasks <<< "$cfg"
    rundir=$(stage_run_dir "$case_name" "$nodes" "$ntasks")
    echo -e "${GREEN}>>> ${case_name}  nodes=${nodes}  ntasks(gpus)=${ntasks}${NC}"
    echo "    rundir: ${rundir}"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "    (dry-run, not submitted)"
    else
        if ( cd "$rundir" && sbatch exaepi.job ) ; then
            SUCCESS=$((SUCCESS + 1))
        else
            FAIL=$((FAIL + 1))
        fi
    fi
    echo ""
done

echo -e "${BLUE}========================================${NC}"
if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${BLUE}  Generated ${#CONFIGS[@]} job scripts (dry-run, none submitted)${NC}"
else
    echo -e "${BLUE}  Submitted: ${SUCCESS}  Failed: ${FAIL}${NC}"
fi
echo -e "${BLUE}========================================${NC}"

exit $FAIL
