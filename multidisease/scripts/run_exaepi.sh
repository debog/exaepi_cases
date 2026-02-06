#!/bin/bash
#
# run_exaepi.sh - ExaEpi run script for multidisease simulations
#
# This script runs ExaEpi simulations using input files from the inputs/ directory.
# It supports both interactive and batch execution modes with platform detection.
#

set -e  # Exit on error

# Color output for terminal
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Script directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INPUTS_DIR="${PROJECT_DIR}/inputs"
REGTEST_DIR="${PROJECT_DIR}/../regtests"
CONFIG_DIR="${REGTEST_DIR}/config"

# Default values
DEFAULT_CASE="sdm_amsu"
DEFAULT_MODE="interactive"
CASE_NAME=""
MODE=""
OVERRIDE_NTASKS=""
OVERRIDE_NNODES=""
OVERRIDE_QUEUE=""
OVERRIDE_WALLTIME=""
OVERRIDE_MAX_STEP=""
OVERRIDE_STOP_TIME=""
DRY_RUN=false
VERBOSE=false

# Platform-specific defaults (from machines.yaml)
declare -A PLATFORM_DEFAULTS_TASKS
declare -A PLATFORM_DEFAULTS_NODES
declare -A PLATFORM_DEFAULTS_QUEUE
declare -A PLATFORM_DEFAULTS_WALLTIME
declare -A PLATFORM_DISPLAY_NAME

# Load platform configurations
PLATFORM_DEFAULTS_TASKS=(
    ["perlmutter"]="4"
    ["dane"]="100"
    ["matrix"]="4"
    ["tuolumne"]="4"
    ["linux"]="4"
    ["linux-gpu"]="1"
    ["desktop"]="4"
)

PLATFORM_DEFAULTS_NODES=(
    ["perlmutter"]="1"
    ["dane"]="1"
    ["matrix"]="1"
    ["tuolumne"]="1"
    ["linux"]="1"
    ["linux-gpu"]="1"
    ["desktop"]="1"
)

PLATFORM_DEFAULTS_QUEUE=(
    ["perlmutter"]="regular"
    ["dane"]="pdebug"
    ["matrix"]="pdebug"
    ["tuolumne"]="pdebug"
    ["linux"]=""
    ["linux-gpu"]=""
    ["desktop"]=""
)

PLATFORM_DEFAULTS_WALLTIME=(
    ["perlmutter"]="00:30:00"
    ["dane"]="01:00:00"
    ["matrix"]="01:00:00"
    ["tuolumne"]="01:00:00"
    ["linux"]=""
    ["linux-gpu"]=""
    ["desktop"]=""
)

PLATFORM_DISPLAY_NAME=(
    ["perlmutter"]="Perlmutter (NERSC)"
    ["dane"]="Dane (LLNL)"
    ["matrix"]="Matrix (LLNL)"
    ["tuolumne"]="Tuolumne (LLNL) - AMD GPU"
    ["linux"]="Linux Workstation/Cluster"
    ["linux-gpu"]="Linux Workstation with CUDA GPUs"
    ["desktop"]="Desktop/Local"
)

#------------------------------------------------------------------------------
# Helper functions
#------------------------------------------------------------------------------

print_error() {
    echo -e "${RED}ERROR:${NC} $*" >&2
}

print_warning() {
    echo -e "${YELLOW}WARNING:${NC} $*" >&2
}

print_info() {
    echo -e "${BLUE}INFO:${NC} $*"
}

print_success() {
    echo -e "${GREEN}SUCCESS:${NC} $*"
}

print_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[VERBOSE]${NC} $*" >&2
    fi
}

show_help() {
    cat << EOF
ExaEpi Multidisease Simulation Runner

Usage:
  ./run_exaepi.sh [OPTIONS]

Options:
  -c, --case=NAME       Input case name (default: ${DEFAULT_CASE})
  -m, --mode=MODE       Execution mode: interactive (default) or batch
  -n, --ntasks=N        Override number of MPI tasks
  -N, --nnodes=N        Override number of nodes
  -q, --queue=NAME      Override queue/partition name
  -t, --walltime=TIME   Override walltime (e.g., 1:00:00 or 1h)
  -s, --max-step=N      Override number of timesteps (uses input file default if unset)
  -T, --stop-time=T     Override simulation stop time (uses input file default if unset)
  -d, --dry-run         Show what would be executed without running
  -l, --list-cases      List available input cases
  -p, --list-platforms  List supported platforms
  -v, --verbose         Enable verbose output
  -h, --help            Show this help message

Environment:
  LCHOST               Platform identifier (auto-detected, or 'desktop' if unset)
  EXAEPI_BUILD         Path to ExaEpi build directory (required)

Examples:
  # Run with default settings (interactive mode)
  ./run_exaepi.sh

  # Run specific case
  ./run_exaepi.sh --case=bay_01D_Cov19S1

  # Run in batch mode with custom resources
  ./run_exaepi.sh --case=CA_01D_Cov19S1 --mode=batch --nnodes=2 --ntasks=8

  # Override simulation parameters
  ./run_exaepi.sh --case=bay_01D_Cov19S1 --max-step=100

  # Dry run to see what would be executed
  ./run_exaepi.sh --case=CA_01D_Cov19S1 --dry-run

  # List available cases
  ./run_exaepi.sh --list-cases

EOF
}

list_cases() {
    echo "Available input cases in ${INPUTS_DIR}:"
    echo ""

    if [[ ! -d "${INPUTS_DIR}" ]]; then
        print_error "Inputs directory not found: ${INPUTS_DIR}"
        return 1
    fi

    local count=0
    for input_file in "${INPUTS_DIR}"/inputs_*; do
        if [[ -f "$input_file" ]]; then
            local basename=$(basename "$input_file")
            local case_name="${basename#inputs_}"

            # Try to extract some info from the file
            local nsteps=$(grep "^agent.nsteps" "$input_file" 2>/dev/null | awk '{print $3}' || echo "N/A")
            local ndiseases=$(grep "^agent.number_of_diseases" "$input_file" 2>/dev/null | awk '{print $3}' || echo "N/A")
            local census=$(grep "^agent.census_filename" "$input_file" 2>/dev/null | awk '{print $3}' | tr -d '"' || echo "N/A")

            echo "  ${case_name}"
            echo "    Input file: ${basename}"
            echo "    Census: ${census}"
            echo "    Timesteps: ${nsteps}"
            echo "    Diseases: ${ndiseases}"
            echo ""
            count=$((count + 1))
        fi
    done

    if [[ $count -eq 0 ]]; then
        print_warning "No input files found in ${INPUTS_DIR}"
        return 1
    fi

    echo "Total: ${count} case(s)"
}

list_platforms() {
    echo "Supported platforms:"
    echo ""

    # Sort platform names
    local sorted_platforms=($(for p in "${!PLATFORM_DISPLAY_NAME[@]}"; do echo "$p"; done | sort))

    for platform in "${sorted_platforms[@]}"; do
        local display="${PLATFORM_DISPLAY_NAME[$platform]}"
        local tasks="${PLATFORM_DEFAULTS_TASKS[$platform]}"
        local nodes="${PLATFORM_DEFAULTS_NODES[$platform]}"
        local queue="${PLATFORM_DEFAULTS_QUEUE[$platform]}"

        echo "  ${platform}"
        echo "    Name: ${display}"
        echo "    Default tasks: ${tasks}"
        echo "    Default nodes: ${nodes}"
        [[ -n "$queue" ]] && echo "    Default queue: ${queue}"
        echo ""
    done
}

detect_platform() {
    # Check for LLNL systems (LCHOST environment variable)
    if [[ -n "${LCHOST}" ]]; then
        local lchost_lower=$(echo "${LCHOST}" | tr '[:upper:]' '[:lower:]')

        # Check if it's a known platform
        for platform in "${!PLATFORM_DISPLAY_NAME[@]}"; do
            if [[ "$lchost_lower" == "$platform" ]]; then
                echo "$platform"
                return 0
            fi
        done

        # Default to the LCHOST value even if not in our list
        print_verbose "Unknown LCHOST value: ${LCHOST}"
        echo "${lchost_lower}"
        return 0
    fi

    # Check for NERSC systems
    if [[ -n "${NERSC_HOST}" ]]; then
        echo "perlmutter"
        return 0
    fi

    # Check for GPU availability on Linux
    if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
        echo "linux-gpu"
        return 0
    fi

    # Default to generic Linux or desktop
    if command -v mpirun &> /dev/null || command -v mpiexec &> /dev/null; then
        echo "linux"
    else
        echo "desktop"
    fi
}

find_input_file() {
    local case_name="$1"
    local input_file="${INPUTS_DIR}/inputs_${case_name}"

    if [[ -f "$input_file" ]]; then
        echo "$input_file"
        return 0
    else
        return 1
    fi
}

check_exaepi_build() {
    if [[ -z "${EXAEPI_BUILD}" ]]; then
        print_error "EXAEPI_BUILD environment variable not set"
        echo "Please set EXAEPI_BUILD to point to your ExaEpi build directory."
        echo "Example: export EXAEPI_BUILD=~/Codes/ExaEpi/build"
        return 1
    fi

    if [[ ! -d "${EXAEPI_BUILD}" ]]; then
        print_error "EXAEPI_BUILD directory does not exist: ${EXAEPI_BUILD}"
        return 1
    fi

    # Look for the agent executable
    local agent_exe=""
    if [[ -f "${EXAEPI_BUILD}/bin/agent" ]]; then
        agent_exe="${EXAEPI_BUILD}/bin/agent"
    elif [[ -f "${EXAEPI_BUILD}/agent" ]]; then
        agent_exe="${EXAEPI_BUILD}/agent"
    else
        # Try to find it anywhere in the build directory
        agent_exe=$(find "${EXAEPI_BUILD}" -name "agent" -type f -executable 2>/dev/null | head -n 1)
    fi

    if [[ -z "$agent_exe" ]] || [[ ! -x "$agent_exe" ]]; then
        print_error "ExaEpi agent executable not found in ${EXAEPI_BUILD}"
        return 1
    fi

    print_verbose "Found agent executable: $agent_exe"
    echo "$agent_exe"
    return 0
}

create_modified_input() {
    local input_file="$1"
    local temp_input="$2"

    # Copy the original input file
    cp "$input_file" "$temp_input"

    # Apply overrides if specified
    if [[ -n "$OVERRIDE_MAX_STEP" ]]; then
        print_verbose "Overriding agent.nsteps to $OVERRIDE_MAX_STEP"
        sed -i "s/^agent.nsteps.*$/agent.nsteps = $OVERRIDE_MAX_STEP/" "$temp_input"
    fi

    if [[ -n "$OVERRIDE_STOP_TIME" ]]; then
        print_verbose "Overriding agent.stop_time to $OVERRIDE_STOP_TIME"
        # Check if stop_time exists in the file
        if grep -q "^agent.stop_time" "$temp_input"; then
            sed -i "s/^agent.stop_time.*$/agent.stop_time = $OVERRIDE_STOP_TIME/" "$temp_input"
        else
            # Add it after nsteps if it doesn't exist
            sed -i "/^agent.nsteps/a agent.stop_time = $OVERRIDE_STOP_TIME" "$temp_input"
        fi
    fi
}

build_run_command() {
    local platform="$1"
    local ntasks="$2"
    local nnodes="$3"
    local queue="$4"
    local agent_exe="$5"
    local input_file="$6"

    local run_cmd=""

    case "$platform" in
        perlmutter)
            run_cmd="srun -N ${nnodes} -n ${ntasks} -c 32 --gpus-per-task=1 ${agent_exe} ${input_file}"
            ;;
        dane)
            if [[ -n "$queue" ]]; then
                run_cmd="srun -N ${nnodes} -n ${ntasks} -p ${queue} ${agent_exe} ${input_file}"
            else
                run_cmd="srun -N ${nnodes} -n ${ntasks} ${agent_exe} ${input_file}"
            fi
            ;;
        matrix)
            local ngpus=${ntasks}  # Assume 1 GPU per task
            if [[ -n "$queue" ]]; then
                run_cmd="srun -p ${queue} -n ${ntasks} -G ${ngpus} -N ${nnodes} ${agent_exe} ${input_file}"
            else
                run_cmd="srun -n ${ntasks} -G ${ngpus} -N ${nnodes} ${agent_exe} ${input_file}"
            fi
            ;;
        tuolumne)
            if [[ -n "$queue" ]]; then
                run_cmd="flux run --exclusive --nodes=${nnodes} --ntasks ${ntasks} --gpus-per-task 1 -q=${queue} ${agent_exe} ${input_file}"
            else
                run_cmd="flux run --exclusive --nodes=${nnodes} --ntasks ${ntasks} --gpus-per-task 1 ${agent_exe} ${input_file}"
            fi
            ;;
        linux|linux-gpu|desktop)
            # Try to find MPI launcher
            if command -v mpirun &> /dev/null; then
                run_cmd="mpirun -n ${ntasks} ${agent_exe} ${input_file}"
            elif command -v mpiexec &> /dev/null; then
                run_cmd="mpiexec -n ${ntasks} ${agent_exe} ${input_file}"
            else
                # No MPI, run directly
                run_cmd="${agent_exe} ${input_file}"
            fi
            ;;
        *)
            # Generic fallback
            run_cmd="mpirun -n ${ntasks} ${agent_exe} ${input_file}"
            ;;
    esac

    echo "$run_cmd"
}

create_batch_script() {
    local platform="$1"
    local ntasks="$2"
    local nnodes="$3"
    local queue="$4"
    local walltime="$5"
    local agent_exe="$6"
    local input_file="$7"
    local batch_script="$8"

    case "$platform" in
        perlmutter)
            cat > "$batch_script" << EOF
#!/bin/bash
#SBATCH --job-name=exaepi_${CASE_NAME}
#SBATCH --nodes=${nnodes}
#SBATCH --ntasks-per-node=${ntasks}
#SBATCH --cpus-per-task=32
#SBATCH --gpus-per-node=${ntasks}
#SBATCH --qos=${queue}
#SBATCH --time=${walltime}
#SBATCH --constraint=gpu
#SBATCH --account=m5071_g
#SBATCH --output=exaepi_%j.out
#SBATCH --error=exaepi_%j.err

export MPICH_OFI_NIC_POLICY=GPU
export OMP_NUM_THREADS=1

srun -N ${nnodes} -n \$((${nnodes} * ${ntasks})) -c 32 --gpus-per-task=1 ${agent_exe} ${input_file}
EOF
            ;;
        dane|matrix)
            cat > "$batch_script" << EOF
#!/bin/bash
#SBATCH --job-name=exaepi_${CASE_NAME}
#SBATCH --nodes=${nnodes}
#SBATCH --ntasks=${ntasks}
#SBATCH --partition=${queue}
#SBATCH --time=${walltime}
#SBATCH --output=exaepi_%j.out
#SBATCH --error=exaepi_%j.err

export OMP_NUM_THREADS=1

EOF
            if [[ "$platform" == "matrix" ]]; then
                echo "srun -n ${ntasks} -G ${ntasks} -N ${nnodes} ${agent_exe} ${input_file}" >> "$batch_script"
            else
                echo "srun -N ${nnodes} -n ${ntasks} ${agent_exe} ${input_file}" >> "$batch_script"
            fi
            ;;
        tuolumne)
            cat > "$batch_script" << EOF
#!/bin/bash
#SBATCH --job-name=exaepi_${CASE_NAME}
#SBATCH --nodes=${nnodes}
#SBATCH --ntasks=${ntasks}
#SBATCH --partition=${queue}
#SBATCH --time=${walltime}
#SBATCH --output=exaepi_%j.out
#SBATCH --error=exaepi_%j.err

export OMP_NUM_THREADS=1
export MPICH_GPU_SUPPORT_ENABLED=1

flux run --exclusive --nodes=${nnodes} --ntasks ${ntasks} --gpus-per-task 1 ${agent_exe} ${input_file}
EOF
            ;;
        *)
            print_error "Batch mode not supported for platform: $platform"
            return 1
            ;;
    esac

    chmod +x "$batch_script"
}

#------------------------------------------------------------------------------
# Parse command line arguments
#------------------------------------------------------------------------------

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -l|--list-cases)
                list_cases
                exit 0
                ;;
            -p|--list-platforms)
                list_platforms
                exit 0
                ;;
            -c|--case)
                CASE_NAME="$2"
                shift 2
                ;;
            --case=*)
                CASE_NAME="${1#*=}"
                shift
                ;;
            -m|--mode)
                MODE="$2"
                shift 2
                ;;
            --mode=*)
                MODE="${1#*=}"
                shift
                ;;
            -n|--ntasks)
                OVERRIDE_NTASKS="$2"
                shift 2
                ;;
            --ntasks=*)
                OVERRIDE_NTASKS="${1#*=}"
                shift
                ;;
            -N|--nnodes)
                OVERRIDE_NNODES="$2"
                shift 2
                ;;
            --nnodes=*)
                OVERRIDE_NNODES="${1#*=}"
                shift
                ;;
            -q|--queue)
                OVERRIDE_QUEUE="$2"
                shift 2
                ;;
            --queue=*)
                OVERRIDE_QUEUE="${1#*=}"
                shift
                ;;
            -t|--walltime)
                OVERRIDE_WALLTIME="$2"
                shift 2
                ;;
            --walltime=*)
                OVERRIDE_WALLTIME="${1#*=}"
                shift
                ;;
            -s|--max-step)
                OVERRIDE_MAX_STEP="$2"
                shift 2
                ;;
            --max-step=*)
                OVERRIDE_MAX_STEP="${1#*=}"
                shift
                ;;
            -T|--stop-time)
                OVERRIDE_STOP_TIME="$2"
                shift 2
                ;;
            --stop-time=*)
                OVERRIDE_STOP_TIME="${1#*=}"
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

#------------------------------------------------------------------------------
# Main execution
#------------------------------------------------------------------------------

main() {
    parse_args "$@"

    # Set defaults
    CASE_NAME="${CASE_NAME:-$DEFAULT_CASE}"
    MODE="${MODE:-$DEFAULT_MODE}"

    # Detect platform
    PLATFORM=$(detect_platform)
    print_info "Detected platform: ${PLATFORM} (${PLATFORM_DISPLAY_NAME[$PLATFORM]:-Unknown})"

    # Check EXAEPI_BUILD
    print_verbose "Checking for ExaEpi build..."
    AGENT_EXE=$(check_exaepi_build)
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
    print_success "Found ExaEpi agent: ${AGENT_EXE}"

    # Find input file
    print_verbose "Looking for input file for case: ${CASE_NAME}"
    INPUT_FILE=$(find_input_file "${CASE_NAME}")
    if [[ $? -ne 0 ]]; then
        print_error "Input file not found for case: ${CASE_NAME}"
        echo "Available cases:"
        list_cases
        exit 1
    fi
    print_success "Found input file: ${INPUT_FILE}"

    # Get platform defaults
    NTASKS="${OVERRIDE_NTASKS:-${PLATFORM_DEFAULTS_TASKS[$PLATFORM]:-4}}"
    NNODES="${OVERRIDE_NNODES:-${PLATFORM_DEFAULTS_NODES[$PLATFORM]:-1}}"
    QUEUE="${OVERRIDE_QUEUE:-${PLATFORM_DEFAULTS_QUEUE[$PLATFORM]:-}}"
    WALLTIME="${OVERRIDE_WALLTIME:-${PLATFORM_DEFAULTS_WALLTIME[$PLATFORM]:-01:00:00}}"

    # Create modified input file if needed
    WORK_INPUT="${INPUT_FILE}"
    if [[ -n "$OVERRIDE_MAX_STEP" ]] || [[ -n "$OVERRIDE_STOP_TIME" ]]; then
        TEMP_INPUT="/tmp/exaepi_input_${CASE_NAME}_$$.tmp"
        create_modified_input "$INPUT_FILE" "$TEMP_INPUT"
        WORK_INPUT="$TEMP_INPUT"
        print_verbose "Created temporary input file: $TEMP_INPUT"
    fi

    # Display configuration
    echo ""
    echo "=========================================="
    echo "ExaEpi Run Configuration"
    echo "=========================================="
    echo "Case:        ${CASE_NAME}"
    echo "Mode:        ${MODE}"
    echo "Platform:    ${PLATFORM}"
    echo "Input file:  ${INPUT_FILE}"
    echo "Agent exe:   ${AGENT_EXE}"
    echo "MPI tasks:   ${NTASKS}"
    echo "Nodes:       ${NNODES}"
    [[ -n "$QUEUE" ]] && echo "Queue:       ${QUEUE}"
    [[ -n "$WALLTIME" ]] && echo "Walltime:    ${WALLTIME}"
    [[ -n "$OVERRIDE_MAX_STEP" ]] && echo "Max steps:   ${OVERRIDE_MAX_STEP} (overridden)"
    [[ -n "$OVERRIDE_STOP_TIME" ]] && echo "Stop time:   ${OVERRIDE_STOP_TIME} (overridden)"
    echo "=========================================="
    echo ""

    # Execute based on mode
    if [[ "$MODE" == "batch" ]]; then
        # Create batch script
        BATCH_SCRIPT="submit_exaepi_${CASE_NAME}.sh"
        print_info "Creating batch script: ${BATCH_SCRIPT}"

        create_batch_script "$PLATFORM" "$NTASKS" "$NNODES" "$QUEUE" "$WALLTIME" \
                           "$AGENT_EXE" "$WORK_INPUT" "$BATCH_SCRIPT"

        if [[ $? -ne 0 ]]; then
            exit 1
        fi

        print_success "Batch script created: ${BATCH_SCRIPT}"

        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "Dry run - would submit:"
            echo "  sbatch ${BATCH_SCRIPT}"
            echo ""
            echo "Batch script contents:"
            cat "$BATCH_SCRIPT"
        else
            print_info "Submitting batch job..."
            sbatch "$BATCH_SCRIPT"
            print_success "Job submitted!"
        fi
    else
        # Interactive mode
        RUN_CMD=$(build_run_command "$PLATFORM" "$NTASKS" "$NNODES" "$QUEUE" \
                                    "$AGENT_EXE" "$WORK_INPUT")

        print_info "Run command:"
        echo "  ${RUN_CMD}"
        echo ""

        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "Dry run - not executing"
        else
            print_info "Starting ExaEpi simulation..."
            echo ""
            eval "$RUN_CMD"
            EXIT_CODE=$?
            echo ""

            if [[ $EXIT_CODE -eq 0 ]]; then
                print_success "Simulation completed successfully!"
            else
                print_error "Simulation failed with exit code: $EXIT_CODE"
                exit $EXIT_CODE
            fi
        fi
    fi

    # Clean up temporary input file
    if [[ -f "$TEMP_INPUT" ]]; then
        rm -f "$TEMP_INPUT"
        print_verbose "Cleaned up temporary input file"
    fi
}

# Run main function
main "$@"
