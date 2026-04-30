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
# ntasks = number of GPUs across all nodes (1 GPU per task).
# Lower-GPU configurations were dropped because the per-GPU memory
# footprint exceeds the device limit (CA at 1 GPU; US at 8 and 16 GPUs)
# and the runs OOM at agent initialization.  Replaced with larger-GPU
# configurations on the high end.
declare -a CONFIGS_CA=(
    "CA_03D_scale 1 2"
    "CA_03D_scale 1 4"
    "CA_03D_scale 2 8"
    "CA_03D_scale 4 16"
)

declare -a CONFIGS_US=(
    "US_04D_scale 8 32"
    "US_04D_scale 16 64"
    "US_04D_scale 32 128"
)

CONFIGS=()
case "$SCENARIO" in
    CA|ca)      CONFIGS=("${CONFIGS_CA[@]}") ;;
    US|us)      CONFIGS=("${CONFIGS_US[@]}") ;;
    both|all)   CONFIGS=("${CONFIGS_CA[@]}" "${CONFIGS_US[@]}") ;;
    *)          echo -e "${RED}ERROR:${NC} Unknown scenario: $SCENARIO" >&2; exit 1 ;;
esac

# Platform-specific node-count limits.  Matrix does not allow jobs at
# 16 or 32 nodes, which the US sweep requires (64- and 128-GPU points).
# Skip the US sweep entirely on Matrix; warn if the user explicitly
# asked for it.
if [[ "$PLATFORM" == "matrix" ]]; then
    if [[ "$SCENARIO" =~ ^(US|us)$ ]]; then
        echo -e "${RED}ERROR:${NC} The US sweep is not runnable on Matrix " \
                "(requires 16- and 32-node jobs, which the partition does not allow)." >&2
        exit 1
    fi
    if [[ ${#CONFIGS[@]} -gt 0 ]]; then
        FILTERED=()
        for cfg in "${CONFIGS[@]}"; do
            case_name=$(echo "$cfg" | awk '{print $1}')
            if [[ "$case_name" == US_04D_scale ]]; then
                continue
            fi
            FILTERED+=("$cfg")
        done
        if [[ ${#FILTERED[@]} -lt ${#CONFIGS[@]} ]]; then
            echo -e "${YELLOW}NOTE:${NC} skipping US sweep on Matrix" \
                    "(16- and 32-node jobs not allowed)."
        fi
        CONFIGS=("${FILTERED[@]}")
    fi
fi

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
            # ~3 s/day at 4 GPUs; 50 days => ~150 s + buffer
            if   (( ntasks == 2 )); then echo "00:40:00"
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

    # Platform-specific SLURM directives and launcher.
    # Tuolumne (Flux scheduler under SLURM): no partition, launch via flux run.
    # Matrix (vanilla SLURM with GPUs):     --partition=pbatch, --gpus-per-task,
    #                                       --exclusive, launch via srun.
    local extra_sbatch=""
    local launcher=""
    case "$PLATFORM" in
        tuolumne)
            extra_sbatch=""
            launcher="flux run --exclusive --nodes=${nodes} --ntasks ${ntasks} --gpus-per-task 1"
            ;;
        matrix|dane|ruby)
            extra_sbatch="#SBATCH --partition=pbatch
#SBATCH --gpus-per-task=1
#SBATCH --exclusive"
            launcher="srun --exclusive -N ${nodes} -n ${ntasks} -G ${ntasks}"
            ;;
        *)
            # Generic fallback: best-effort srun
            extra_sbatch=""
            launcher="srun -N ${nodes} -n ${ntasks}"
            ;;
    esac

    cat > "${rundir}/exaepi.job" <<EOF
#!/bin/bash
#SBATCH --job-name=scale_${case}_$(printf '%03d' "${ntasks}")gpu
#SBATCH --nodes=${nodes}
#SBATCH --ntasks=${ntasks}
#SBATCH --time=${walltime}
#SBATCH --account=asccasc
#SBATCH --output=scale_%j.out
#SBATCH --error=scale_%j.err
${extra_sbatch}

echo "Job started at: \$(date)"
echo "Running on host: \$(hostname)"
echo "Working directory: \$(pwd)"
echo "Configuration: ${case}, nodes=${nodes}, ntasks=${ntasks}, platform=${PLATFORM}"
echo ""

export OMP_NUM_THREADS=1
export MPICH_GPU_SUPPORT_ENABLED=1

${launcher} \\
    ${AGENT_EXE} inputs_${case}

echo ""
echo "Job finished at: \$(date)"
EOF
}

extract_data_deps() {
    # Print the list of data filenames referenced from an input file:
    # agent.census_filename, agent.workerflow_filename, disease.case_filename,
    # disease_<NAME>.case_filename, and any *.initial_case_filename / *.cases_filename.
    local input="$1"
    grep -E '^(agent\.(census|workerflow)_filename|disease(_[A-Za-z0-9]+)?\.(case|initial_case|cases)_filename)' "$input" | \
        awk -F'=' '{print $2}' | tr -d ' ' | tr '"' '\n' | grep -v '^$'
}

resolve_data_file() {
    # Locate a single data filename in the standard search paths.
    # ExaEpi source tree is expected to live at $EXAEPI_DIR (set in the
    # user's shell environment on every machine they work on).
    local filename="$1"
    local agent_dir; agent_dir=$(dirname "$AGENT_EXE")
    local search_dirs=("${PROJECT_DIR}/data")
    if [[ -n "${EXAEPI_DIR}" ]]; then
        search_dirs+=(
            "${EXAEPI_DIR}/data/CensusData"
            "${EXAEPI_DIR}/data"
            "${EXAEPI_DIR}"
        )
    fi
    search_dirs+=(
        "${agent_dir}/../data/CensusData"
        "${agent_dir}/../data"
        "${agent_dir}/../../data/CensusData"
        "${agent_dir}/../../data"
    )
    for d in "${search_dirs[@]}"; do
        if [[ -f "${d}/${filename}" ]]; then
            echo "${d}/${filename}"
            return 0
        fi
    done
    return 1
}

stage_run_dir() {
    local case=$1
    local nodes=$2
    local ntasks=$3
    # Zero-pad GPU count to 3 digits so directory listings sort numerically.
    local ngpu_pad
    ngpu_pad=$(printf '%03d' "${ntasks}")
    local rundir="${PARENT_DIR}/run_${case}_${ngpu_pad}gpu_${PLATFORM}"

    # Wipe any prior outputs from a previous submission of the same
    # configuration so the analyzer cannot pick up stale logs.  Matches
    # the convention in scripts/run_exaepi.sh's setup_run_directory().
    if [[ -d "$rundir" ]]; then
        rm -rf "$rundir"
    fi
    mkdir -p "$rundir"

    # Copy input file (so each scaling run is self-contained for reproduction).
    local input_src="${INPUTS_DIR}/inputs_${case}"
    cp "$input_src" "${rundir}/inputs_${case}"

    # Parse the input file for every data dependency and symlink each into the
    # rundir. Missing files are reported but not fatal -- the agent will fail
    # at startup with a clear message.
    local missing=()
    while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue
        if [[ -e "${rundir}/${dep}" ]]; then continue; fi
        local src
        if src=$(resolve_data_file "$dep"); then
            ln -sfn "$src" "${rundir}/${dep}"
        else
            missing+=("$dep")
        fi
    done < <(extract_data_deps "$input_src")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "  ${YELLOW}WARN:${NC} could not resolve data files for ${case}: ${missing[*]}" >&2
    fi

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
