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

# Check for EXAEPI_DIR (data files location)
if [[ -z "${EXAEPI_DIR}" ]]; then
    # Try to find it relative to ExaEpi build
    if [[ -n "${EXAEPI_BUILD}" ]]; then
        # Try common locations
        for possible_dir in "${EXAEPI_BUILD}/../" "${EXAEPI_BUILD}/../../" ~/Codes/ExaEpi; do
            if [[ -d "${possible_dir}/data" ]] || [[ -d "${possible_dir}/Data" ]]; then
                EXAEPI_DIR="${possible_dir}"
                break
            fi
        done
    fi
fi

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
  EXAEPI_DIR           Path to ExaEpi source directory with data files (optional, auto-detected)

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

get_case_specific_resources() {
    local case_name="$1"
    local platform="$2"
    local resource_type="$3"  # "tasks" or "gpus"

    # Extract base case name (e.g., "bay_01D_Cov19S1" -> "bay")
    local base_case=$(echo "$case_name" | cut -d'_' -f1 | tr '[:upper:]' '[:lower:]')

    # Bay case-specific overrides (from regtests/config/test_cases.yaml)
    if [[ "$base_case" == "bay" ]]; then
        case "$platform" in
            dane)
                if [[ "$resource_type" == "tasks" ]]; then
                    echo "25"
                else
                    echo "1"
                fi
                ;;
            perlmutter|matrix|tuolumne|linux-gpu)
                if [[ "$resource_type" == "tasks" ]]; then
                    echo "1"
                else
                    echo "1"
                fi
                ;;
            linux)
                if [[ "$resource_type" == "tasks" ]]; then
                    echo "4"
                else
                    echo "1"
                fi
                ;;
            *)
                echo ""
                ;;
        esac
    else
        echo ""
    fi
}

extract_data_files() {
    local input_file="$1"

    # Extract filenames from the input file
    # Look for lines with "filename" and extract the value
    grep -E "filename.*=" "$input_file" | \
        awk -F'=' '{print $2}' | \
        tr -d ' "'"'"'' | \
        grep -v "^output" | \
        sort -u
}

find_data_file() {
    local filename="$1"
    local search_dirs=()

    # Build list of directories to search
    if [[ -n "${EXAEPI_DIR}" ]]; then
        search_dirs+=("${EXAEPI_DIR}/data" "${EXAEPI_DIR}/Data" "${EXAEPI_DIR}")
    fi

    # Also check relative to ExaEpi source
    if [[ -n "${EXAEPI_BUILD}" ]]; then
        search_dirs+=("${EXAEPI_BUILD}/../data" "${EXAEPI_BUILD}/../Data")
        search_dirs+=("${EXAEPI_BUILD}/../../data" "${EXAEPI_BUILD}/../../Data")
    fi

    # Search for the file
    for dir in "${search_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local found=$(find "$dir" -name "$filename" -type f 2>/dev/null | head -n 1)
            if [[ -n "$found" ]]; then
                echo "$found"
                return 0
            fi
        fi
    done

    return 1
}

setup_run_directory() {
    local case_name="$1"
    local platform="$2"
    local input_file="$3"

    # Create run directory name (set global variable)
    RUN_DIR="${PROJECT_DIR}/.run_${case_name}_${platform}"

    print_verbose "Creating run directory: ${RUN_DIR}"
    mkdir -p "$RUN_DIR"

    # Extract and copy data files
    local data_files=$(extract_data_files "$input_file")
    local copied_count=0
    local missing_files=()

    while IFS= read -r data_file; do
        if [[ -z "$data_file" ]]; then
            continue
        fi

        print_verbose "  Looking for: ${data_file}"

        # Check if file already exists in run directory
        if [[ -f "${RUN_DIR}/${data_file}" ]]; then
            print_verbose "    Already exists in run directory"
            copied_count=$((copied_count + 1))
            continue
        fi

        # Find the data file
        local source_file=$(find_data_file "$data_file")
        if [[ $? -eq 0 ]] && [[ -n "$source_file" ]]; then
            print_verbose "    Found: ${source_file}"
            cp "$source_file" "${RUN_DIR}/"
            if [[ $? -eq 0 ]]; then
                copied_count=$((copied_count + 1))
            else
                print_warning "Failed to copy: ${data_file}"
                missing_files+=("$data_file")
            fi
        else
            print_warning "Data file not found: ${data_file}"
            missing_files+=("$data_file")
        fi
    done <<< "$data_files"

    if [[ $copied_count -gt 0 ]]; then
        print_success "Copied ${copied_count} data file(s)"
    fi

    if [[ ${#missing_files[@]} -gt 0 ]]; then
        print_warning "Missing ${#missing_files[@]} data file(s):"
        for file in "${missing_files[@]}"; do
            echo "    - $file" >&2
        done
        print_warning "Set EXAEPI_DIR to the ExaEpi source directory containing data files"
        echo "Example: export EXAEPI_DIR=~/Codes/ExaEpi" >&2
        return 1
    fi

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

create_run_script() {
    local platform="$1"
    local ntasks="$2"
    local nnodes="$3"
    local queue="$4"
    local agent_exe="$5"
    local input_file="$6"
    local run_dir="$7"
    local run_script="${run_dir}/run.sh"

    cat > "$run_script" << 'EOF_HEADER'
#!/bin/bash
#
# Interactive run script for ExaEpi simulation
# Run this script from within the run directory: ./run.sh
#
EOF_HEADER

    case "$platform" in
        perlmutter)
            cat >> "$run_script" << EOF

export MPICH_OFI_NIC_POLICY=GPU
export OMP_NUM_THREADS=1

echo "Running ExaEpi on Perlmutter..."
echo "Command: srun -N ${nnodes} -n \$((${nnodes} * ${ntasks})) -c 32 --gpus-per-task=1 ${agent_exe} ${input_file}"
echo ""

srun -N ${nnodes} -n \$((${nnodes} * ${ntasks})) -c 32 --gpus-per-task=1 ${agent_exe} ${input_file}
EOF
            ;;
        dane)
            cat >> "$run_script" << EOF

export OMP_NUM_THREADS=1

echo "Running ExaEpi on Dane..."
echo "Command: srun -N ${nnodes} -n ${ntasks} -p ${queue} ${agent_exe} ${input_file}"
echo ""

srun -N ${nnodes} -n ${ntasks} -p ${queue} ${agent_exe} ${input_file}
EOF
            ;;
        matrix)
            cat >> "$run_script" << EOF

export OMP_NUM_THREADS=1

echo "Running ExaEpi on Matrix..."
echo "Command: srun -n ${ntasks} -G ${ntasks} -N ${nnodes} -p ${queue} ${agent_exe} ${input_file}"
echo ""

srun -n ${ntasks} -G ${ntasks} -N ${nnodes} -p ${queue} ${agent_exe} ${input_file}
EOF
            ;;
        tuolumne)
            cat >> "$run_script" << EOF

export OMP_NUM_THREADS=1
export MPICH_GPU_SUPPORT_ENABLED=1

echo "Running ExaEpi on Tuolumne..."
echo "Command: flux run --exclusive --nodes=${nnodes} --ntasks ${ntasks} --gpus-per-task 1 -q=${queue} ${agent_exe} ${input_file}"
echo ""

flux run --exclusive --nodes=${nnodes} --ntasks ${ntasks} --gpus-per-task 1 -q=${queue} ${agent_exe} ${input_file}
EOF
            ;;
        linux|linux-gpu|desktop)
            # Try to find MPI launcher
            local mpi_cmd=""
            if command -v mpirun &> /dev/null; then
                mpi_cmd="mpirun -n ${ntasks}"
            elif command -v mpiexec &> /dev/null; then
                mpi_cmd="mpiexec -n ${ntasks}"
            else
                mpi_cmd=""
            fi

            cat >> "$run_script" << EOF

export OMP_NUM_THREADS=1

echo "Running ExaEpi on ${platform}..."
EOF
            if [[ -n "$mpi_cmd" ]]; then
                cat >> "$run_script" << EOF
echo "Command: ${mpi_cmd} ${agent_exe} ${input_file}"
echo ""

${mpi_cmd} ${agent_exe} ${input_file}
EOF
            else
                cat >> "$run_script" << EOF
echo "Command: ${agent_exe} ${input_file}"
echo ""

${agent_exe} ${input_file}
EOF
            fi
            ;;
        *)
            cat >> "$run_script" << EOF

export OMP_NUM_THREADS=1

echo "Running ExaEpi..."
echo "Command: mpirun -n ${ntasks} ${agent_exe} ${input_file}"
echo ""

mpirun -n ${ntasks} ${agent_exe} ${input_file}
EOF
            ;;
    esac

    chmod +x "$run_script"
    print_verbose "Created run script: ${run_script}"
}

create_job_script() {
    local platform="$1"
    local ntasks="$2"
    local nnodes="$3"
    local queue="$4"
    local walltime="$5"
    local agent_exe="$6"
    local input_file="$7"
    local run_dir="$8"
    local case_name="$9"
    local job_script="${run_dir}/erf.job"

    case "$platform" in
        perlmutter)
            cat > "$job_script" << EOF
#!/bin/bash
#SBATCH --job-name=exaepi_${case_name}
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

echo "Job started at: \$(date)"
echo "Running on host: \$(hostname)"
echo "Working directory: \$(pwd)"
echo ""

export MPICH_OFI_NIC_POLICY=GPU
export OMP_NUM_THREADS=1

srun -N ${nnodes} -n \$((${nnodes} * ${ntasks})) -c 32 --gpus-per-task=1 ${agent_exe} ${input_file}

echo ""
echo "Job finished at: \$(date)"
EOF
            ;;
        dane|matrix)
            cat > "$job_script" << EOF
#!/bin/bash
#SBATCH --job-name=exaepi_${case_name}
#SBATCH --nodes=${nnodes}
#SBATCH --ntasks=${ntasks}
#SBATCH --partition=${queue}
#SBATCH --time=${walltime}
#SBATCH --output=exaepi_%j.out
#SBATCH --error=exaepi_%j.err

echo "Job started at: \$(date)"
echo "Running on host: \$(hostname)"
echo "Working directory: \$(pwd)"
echo ""

export OMP_NUM_THREADS=1

EOF
            if [[ "$platform" == "matrix" ]]; then
                cat >> "$job_script" << EOF
srun -n ${ntasks} -G ${ntasks} -N ${nnodes} ${agent_exe} ${input_file}
EOF
            else
                cat >> "$job_script" << EOF
srun -N ${nnodes} -n ${ntasks} ${agent_exe} ${input_file}
EOF
            fi
            cat >> "$job_script" << 'EOF'

echo ""
echo "Job finished at: $(date)"
EOF
            ;;
        tuolumne)
            cat > "$job_script" << EOF
#!/bin/bash
#SBATCH --job-name=exaepi_${case_name}
#SBATCH --nodes=${nnodes}
#SBATCH --ntasks=${ntasks}
#SBATCH --partition=${queue}
#SBATCH --time=${walltime}
#SBATCH --output=exaepi_%j.out
#SBATCH --error=exaepi_%j.err

echo "Job started at: \$(date)"
echo "Running on host: \$(hostname)"
echo "Working directory: \$(pwd)"
echo ""

export OMP_NUM_THREADS=1
export MPICH_GPU_SUPPORT_ENABLED=1

flux run --exclusive --nodes=${nnodes} --ntasks ${ntasks} --gpus-per-task 1 ${agent_exe} ${input_file}

echo ""
echo "Job finished at: \$(date)"
EOF
            ;;
        linux|linux-gpu|desktop)
            # Create a generic batch script even for non-SLURM systems
            cat > "$job_script" << EOF
#!/bin/bash
#
# Generic batch job script for ${platform}
# Note: This system may not have a batch scheduler
#

echo "Job started at: \$(date)"
echo "Running on host: \$(hostname)"
echo "Working directory: \$(pwd)"
echo ""

export OMP_NUM_THREADS=1

EOF
            if command -v mpirun &> /dev/null; then
                echo "mpirun -n ${ntasks} ${agent_exe} ${input_file}" >> "$job_script"
            elif command -v mpiexec &> /dev/null; then
                echo "mpiexec -n ${ntasks} ${agent_exe} ${input_file}" >> "$job_script"
            else
                echo "${agent_exe} ${input_file}" >> "$job_script"
            fi
            cat >> "$job_script" << 'EOF'

echo ""
echo "Job finished at: $(date)"
EOF
            ;;
        *)
            print_warning "Batch script creation not fully supported for platform: $platform"
            cat > "$job_script" << EOF
#!/bin/bash
# Generic job script - may need customization

export OMP_NUM_THREADS=1

mpirun -n ${ntasks} ${agent_exe} ${input_file}
EOF
            ;;
    esac

    chmod +x "$job_script"
    print_verbose "Created job script: ${job_script}"
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

    # Get platform defaults, with case-specific overrides
    local case_tasks=$(get_case_specific_resources "${CASE_NAME}" "${PLATFORM}" "tasks")
    if [[ -z "$OVERRIDE_NTASKS" ]]; then
        if [[ -n "$case_tasks" ]]; then
            NTASKS="$case_tasks"
        else
            NTASKS="${PLATFORM_DEFAULTS_TASKS[$PLATFORM]:-4}"
        fi
    else
        NTASKS="$OVERRIDE_NTASKS"
    fi

    NNODES="${OVERRIDE_NNODES:-${PLATFORM_DEFAULTS_NODES[$PLATFORM]:-1}}"
    QUEUE="${OVERRIDE_QUEUE:-${PLATFORM_DEFAULTS_QUEUE[$PLATFORM]:-}}"
    WALLTIME="${OVERRIDE_WALLTIME:-${PLATFORM_DEFAULTS_WALLTIME[$PLATFORM]:-01:00:00}}"

    # Setup run directory and copy data files
    print_verbose "Setting up run directory..."
    print_info "Copying data files to run directory..."
    setup_run_directory "${CASE_NAME}" "${PLATFORM}" "${INPUT_FILE}"
    if [[ $? -ne 0 ]]; then
        print_error "Failed to setup run directory"
        exit 1
    fi
    # RUN_DIR is set by setup_run_directory function
    print_success "Run directory: ${RUN_DIR}"

    # Copy/create input file in run directory
    RUN_INPUT="${RUN_DIR}/inputs_${CASE_NAME}"
    if [[ -n "$OVERRIDE_MAX_STEP" ]] || [[ -n "$OVERRIDE_STOP_TIME" ]]; then
        create_modified_input "$INPUT_FILE" "$RUN_INPUT"
        print_verbose "Created modified input file in run directory"
    else
        cp "$INPUT_FILE" "$RUN_INPUT"
        print_verbose "Copied input file to run directory"
    fi

    # Create run.sh and erf.job scripts in run directory
    print_verbose "Creating helper scripts in run directory..."
    create_run_script "$PLATFORM" "$NTASKS" "$NNODES" "$QUEUE" \
                      "$AGENT_EXE" "inputs_${CASE_NAME}" "$RUN_DIR"
    create_job_script "$PLATFORM" "$NTASKS" "$NNODES" "$QUEUE" "$WALLTIME" \
                      "$AGENT_EXE" "inputs_${CASE_NAME}" "$RUN_DIR" "$CASE_NAME"
    print_success "Created run.sh and erf.job in run directory"

    # Display configuration
    echo ""
    echo "=========================================="
    echo "ExaEpi Run Configuration"
    echo "=========================================="
    echo "Case:        ${CASE_NAME}"
    echo "Mode:        ${MODE}"
    echo "Platform:    ${PLATFORM}"
    echo "Run dir:     ${RUN_DIR}"
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
    print_info "Helper scripts created:"
    echo "  ${RUN_DIR}/run.sh    - Interactive execution"
    echo "  ${RUN_DIR}/erf.job   - Batch submission"
    echo ""

    # Execute based on mode
    if [[ "$MODE" == "batch" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "Dry run - would submit:"
            echo "  cd ${RUN_DIR} && sbatch erf.job"
            echo ""
            echo "Or alternatively:"
            echo "  cd ${RUN_DIR}"
            echo "  sbatch erf.job"
            echo ""
            echo "Job script contents (erf.job):"
            cat "${RUN_DIR}/erf.job"
        else
            print_info "Submitting batch job..."
            cd "$RUN_DIR" && sbatch erf.job
            print_success "Job submitted!"
            print_info "To monitor: cd ${RUN_DIR} && tail -f exaepi_*.out"
            cd "$PROJECT_DIR"
        fi
    else
        # Interactive mode - run from run directory
        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "Dry run - would execute:"
            echo "  cd ${RUN_DIR} && ./run.sh"
            echo ""
            echo "Or alternatively:"
            echo "  cd ${RUN_DIR}"
            echo "  ./run.sh"
            echo ""
            echo "Run script contents (run.sh):"
            cat "${RUN_DIR}/run.sh"
        else
            print_info "Starting ExaEpi simulation..."
            echo ""
            cd "$RUN_DIR"
            ./run.sh
            EXIT_CODE=$?
            cd "$PROJECT_DIR"
            echo ""

            if [[ $EXIT_CODE -eq 0 ]]; then
                print_success "Simulation completed successfully!"
                print_info "Output files in: ${RUN_DIR}"
            else
                print_error "Simulation failed with exit code: $EXIT_CODE"
                print_info "Check logs in: ${RUN_DIR}"
                exit $EXIT_CODE
            fi
        fi
    fi
}

# Run main function
main "$@"
