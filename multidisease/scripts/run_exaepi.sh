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
RUN_ALL=false
ENSEMBLE=false
ENSEMBLE_SIZE=100

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
  -c, --case=NAME       Input case name (required unless --all is used)
  -a, --all             Run or submit jobs for all available cases
  -m, --mode=MODE       Execution mode: interactive (default) or batch
  -e, --ensemble        Run ensemble of ${ENSEMBLE_SIZE} simulations with different seeds
                         (requires batch mode). Computes statistics across runs.
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

  # Submit batch jobs for all cases
  ./run_exaepi.sh --all --mode=batch

  # Override simulation parameters for all cases
  ./run_exaepi.sh --all --max-step=100 --mode=batch

  # Run ensemble of 100 simulations (batch mode only)
  ./run_exaepi.sh --case=bay_01D_Cov19S1 --mode=batch --ensemble

  # Dry run to see what would be executed for all cases
  ./run_exaepi.sh --all --dry-run

  # List available cases
  ./run_exaepi.sh --list-cases

EOF
}

get_all_cases() {
    # Return list of all available case names
    if [[ ! -d "${INPUTS_DIR}" ]]; then
        return 1
    fi

    for input_file in "${INPUTS_DIR}"/inputs_*; do
        if [[ -f "$input_file" ]]; then
            local basename=$(basename "$input_file")
            local case_name="${basename#inputs_}"
            echo "$case_name"
        fi
    done
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
            run_cmd="srun --cpu-bind=cores -n ${ntasks} bash -c 'export CUDA_VISIBLE_DEVICES=\$((3-SLURM_LOCALID)); ${agent_exe} ${input_file} amrex.use_gpu_aware_mpi=1'"
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
            cat >> "$run_script" << 'EOF'

export MPICH_OFI_NIC_POLICY=GPU
export OMP_NUM_THREADS=1

OUTFILE=out.${NERSC_HOST}.log

# Find ExaEpi executable (check direct build or machine subdirectory)
if [ -d "$EXAEPI_BUILD/bin" ] && ls $EXAEPI_BUILD/bin/*agent* &> /dev/null; then
    # Direct build
    EXEC=$(ls $EXAEPI_BUILD/bin/*agent*)
elif [ -d "$EXAEPI_BUILD/$NERSC_HOST/bin" ] && ls $EXAEPI_BUILD/$NERSC_HOST/bin/*agent* &> /dev/null; then
    # Machine-specific subdirectory
    EXEC=$(ls $EXAEPI_BUILD/$NERSC_HOST/bin/*agent*)
else
    echo "ERROR: ExaEpi executable not found in $EXAEPI_BUILD/bin/ or machine subdirectories"
    exit 1
fi
echo "Executable file is ${EXEC}."

INP=$(ls inputs*)
echo "Input file is ${INP}."
EOF
            cat >> "$run_script" << EOF

NGPU=${ntasks}

# pin to closest NIC to GPU
export MPICH_OFI_NIC_POLICY=GPU
export OMP_NUM_THREADS=1
GPU_AWARE_MPI="amrex.use_gpu_aware_mpi=1"

rm -rf Backtrace* plt* cases* \$OUTFILE output.dat *.core
echo "  running ExaEpi with input file \$INP"
# CUDA visible devices are ordered inverse to local task IDs
#   Reference: nvidia-smi topo -m
srun --cpu-bind=cores -n \$NGPU bash -c "
    export CUDA_VISIBLE_DEVICES=\$((3-SLURM_LOCALID));
    \${EXEC} \${INP} \${GPU_AWARE_MPI}" \\
    2>&1 |tee \$OUTFILE
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
    local job_script="${run_dir}/exaepi.job"

    case "$platform" in
        perlmutter)
            cat > "$job_script" << EOF
#!/bin/bash -l

#SBATCH -t ${walltime}
#SBATCH -N ${nnodes}
#SBATCH -J ExaEpi
#SBATCH -A m5071_g
#SBATCH -q ${queue}
#SBATCH -C gpu
#SBATCH --exclusive
#SBATCH --cpus-per-task=32
#SBATCH --gpu-bind=none
#SBATCH --ntasks-per-node=4
#SBATCH --gpus-per-node=4
#SBATCH -o ExaEpi.o%j
#SBATCH -e ExaEpi.e%j


OUTFILE=out.\${NERSC_HOST}.log

INP=\$(ls inputs*)
echo "Input file is \${INP}."

# Find ExaEpi executable (check direct build or machine subdirectory)
if [ -d "\$EXAEPI_BUILD/bin" ] && ls \$EXAEPI_BUILD/bin/*agent* &> /dev/null; then
    EXEC=\$(ls \$EXAEPI_BUILD/bin/*agent*)
elif [ -d "\$EXAEPI_BUILD/\$NERSC_HOST/bin" ] && ls \$EXAEPI_BUILD/\$NERSC_HOST/bin/*agent* &> /dev/null; then
    EXEC=\$(ls \$EXAEPI_BUILD/\$NERSC_HOST/bin/*agent*)
else
    echo "ERROR: ExaEpi executable not found"
    exit 1
fi
echo "Executable file is \${EXEC}."

# pin to closest NIC to GPU
export MPICH_OFI_NIC_POLICY=GPU
export OMP_NUM_THREADS=1
GPU_AWARE_MPI="amrex.use_gpu_aware_mpi=1"

# CUDA visible devices are ordered inverse to local task IDs
#   Reference: nvidia-smi topo -m
rm -rf Backtrace* plt* cases* \$OUTFILE output.dat *.core
srun --cpu-bind=cores bash -c "
    export CUDA_VISIBLE_DEVICES=\$((3-SLURM_LOCALID));
    \${EXEC} \${INP} \${GPU_AWARE_MPI}" \\
    2>&1 |tee \$OUTFILE
EOF
            ;;
        dane|matrix)
            cat > "$job_script" << EOF
#!/bin/bash
#SBATCH --job-name=exaepi_${case_name}
#SBATCH --nodes=${nnodes}
#SBATCH --ntasks=${ntasks}
EOF
            if [[ "$platform" == "matrix" ]]; then
                cat >> "$job_script" << EOF
#SBATCH --exclusive
EOF
            fi
            cat >> "$job_script" << EOF
#SBATCH --partition=${queue}
#SBATCH --time=${walltime}
#SBATCH --output=exaepi_%j.out
#SBATCH --error=exaepi_%j.err
EOF
            if [[ "$platform" == "matrix" ]]; then
                cat >> "$job_script" << EOF
#SBATCH --gpus-per-task=1

echo "Job started at: \$(date)"
echo "Running on host: \$(hostname)"
echo "Working directory: \$(pwd)"
echo ""

export OMP_NUM_THREADS=1

srun --exclusive -n ${ntasks} -G ${ntasks} -N ${nnodes} ${agent_exe} ${input_file}

echo ""
echo "Job finished at: \$(date)"
EOF
            else
                cat >> "$job_script" << EOF

echo "Job started at: \$(date)"
echo "Running on host: \$(hostname)"
echo "Working directory: \$(pwd)"
echo ""

export OMP_NUM_THREADS=1

srun -N ${nnodes} -n ${ntasks} ${agent_exe} ${input_file}

echo ""
echo "Job finished at: \$(date)"
EOF
            fi
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
            -a|--all)
                RUN_ALL=true
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
            -e|--ensemble)
                ENSEMBLE=true
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

create_ensemble_job_script() {
    local platform="$1"
    local ntasks="$2"
    local nnodes="$3"
    local queue="$4"
    local walltime="$5"
    local agent_exe="$6"
    local input_file="$7"
    local ensemble_dir="$8"
    local case_name="$9"
    local num_runs="${10}"
    local job_script="${ensemble_dir}/exaepi.job"

    # Build the MPI run command based on platform
    local run_cmd=""
    case "$platform" in
        perlmutter)
            run_cmd="srun --cpu-bind=cores bash -c \"export CUDA_VISIBLE_DEVICES=\\\$((3-SLURM_LOCALID)); \${EXEC}"
            ;;
        dane)
            run_cmd="srun -N ${nnodes} -n ${ntasks} ${agent_exe}"
            ;;
        matrix)
            run_cmd="srun --exclusive -n ${ntasks} -G ${ntasks} -N ${nnodes} ${agent_exe}"
            ;;
        tuolumne)
            run_cmd="flux run --exclusive --nodes=${nnodes} --ntasks ${ntasks} --gpus-per-task 1 ${agent_exe}"
            ;;
        linux|linux-gpu|desktop)
            if command -v mpirun &> /dev/null; then
                run_cmd="mpirun -n ${ntasks} ${agent_exe}"
            elif command -v mpiexec &> /dev/null; then
                run_cmd="mpiexec -n ${ntasks} ${agent_exe}"
            else
                run_cmd="${agent_exe}"
            fi
            ;;
        *)
            run_cmd="mpirun -n ${ntasks} ${agent_exe}"
            ;;
    esac

    # Write SBATCH header based on platform
    case "$platform" in
        perlmutter)
            cat > "$job_script" << EOF
#!/bin/bash -l

#SBATCH -t ${walltime}
#SBATCH -N ${nnodes}
#SBATCH -J ens_${case_name}
#SBATCH -A m5071_g
#SBATCH -q ${queue}
#SBATCH -C gpu
#SBATCH --exclusive
#SBATCH --cpus-per-task=32
#SBATCH --gpu-bind=none
#SBATCH --ntasks-per-node=4
#SBATCH --gpus-per-node=4
#SBATCH -o ensemble_%j.out
#SBATCH -e ensemble_%j.err

# Find ExaEpi executable (check direct build or machine subdirectory)
if [ -d "\$EXAEPI_BUILD/bin" ] && ls \$EXAEPI_BUILD/bin/*agent* &> /dev/null; then
    EXEC=\$(ls \$EXAEPI_BUILD/bin/*agent*)
elif [ -d "\$EXAEPI_BUILD/\$NERSC_HOST/bin" ] && ls \$EXAEPI_BUILD/\$NERSC_HOST/bin/*agent* &> /dev/null; then
    EXEC=\$(ls \$EXAEPI_BUILD/\$NERSC_HOST/bin/*agent*)
else
    echo "ERROR: ExaEpi executable not found"
    exit 1
fi
echo "Executable file is \${EXEC}."

# pin to closest NIC to GPU
export MPICH_OFI_NIC_POLICY=GPU
export OMP_NUM_THREADS=1
GPU_AWARE_MPI="amrex.use_gpu_aware_mpi=1"
EOF
            ;;
        dane|matrix)
            cat > "$job_script" << EOF
#!/bin/bash
#SBATCH --job-name=ens_${case_name}
#SBATCH --nodes=${nnodes}
#SBATCH --ntasks=${ntasks}
#SBATCH --partition=${queue}
#SBATCH --time=${walltime}
#SBATCH --output=ensemble_%j.out
#SBATCH --error=ensemble_%j.err
EOF
            if [[ "$platform" == "matrix" ]]; then
                cat >> "$job_script" << EOF
#SBATCH --exclusive
#SBATCH --gpus-per-task=1
EOF
            fi
            cat >> "$job_script" << EOF

export OMP_NUM_THREADS=1
EOF
            ;;
        tuolumne)
            cat > "$job_script" << EOF
#!/bin/bash
#SBATCH --job-name=ens_${case_name}
#SBATCH --nodes=${nnodes}
#SBATCH --ntasks=${ntasks}
#SBATCH --partition=${queue}
#SBATCH --time=${walltime}
#SBATCH --output=ensemble_%j.out
#SBATCH --error=ensemble_%j.err

export OMP_NUM_THREADS=1
export MPICH_GPU_SUPPORT_ENABLED=1
EOF
            ;;
        linux|linux-gpu|desktop)
            cat > "$job_script" << EOF
#!/bin/bash
#
# Ensemble job script for ${platform}
#

export OMP_NUM_THREADS=1
EOF
            ;;
        *)
            cat > "$job_script" << EOF
#!/bin/bash

export OMP_NUM_THREADS=1
EOF
            ;;
    esac

    # Write the ensemble loop
    cat >> "$job_script" << EOF

echo "Ensemble job started at: \$(date)"
echo "Running ${num_runs} simulations for case: ${case_name}"
echo "Working directory: \$(pwd)"
echo ""

ENSEMBLE_DIR="\$(pwd)"
FAILED=0

for i in \$(seq 1 ${num_runs}); do
    RUN_DIR="\${ENSEMBLE_DIR}/run_\$(printf '%03d' \$i)"
    mkdir -p "\${RUN_DIR}"

    echo "--- Run \$i/${num_runs} (seed=\$i) started at \$(date) ---"

    cd "\${RUN_DIR}"

    # Copy input file and data files into run directory
    for f in "\${ENSEMBLE_DIR}"/inputs_* "\${ENSEMBLE_DIR}"/*.dat "\${ENSEMBLE_DIR}"/*.bin; do
        if [ -f "\$f" ]; then
            ln -sf "\$f" "\${RUN_DIR}/" 2>/dev/null || cp "\$f" "\${RUN_DIR}/"
        fi
    done

    # Run simulation with unique seed
    ${run_cmd} ${input_file} agent.seed=\$i$(if [[ "$platform" == "perlmutter" ]]; then echo ' ${GPU_AWARE_MPI}"'; fi)
    EXIT_CODE=\$?

    if [ \$EXIT_CODE -ne 0 ]; then
        echo "WARNING: Run \$i failed with exit code \$EXIT_CODE"
        FAILED=\$((FAILED + 1))
    fi

    # Remove plt* directories to save space
    rm -rf "\${RUN_DIR}"/plt?????

    cd "\${ENSEMBLE_DIR}"
    echo "--- Run \$i/${num_runs} finished ---"
    echo ""
done

echo "All ${num_runs} runs completed at \$(date)"
echo "Failed runs: \$FAILED"

# Compute ensemble statistics
echo ""
echo "Computing ensemble statistics..."

python3 << 'PYEOF'
import sys, os
import numpy as np

ensemble_dir = os.environ.get('ENSEMBLE_DIR', '.')
num_runs = ${num_runs}

# Find output files from first successful run
first_run = None
for i in range(1, num_runs + 1):
    run_dir = os.path.join(ensemble_dir, 'run_%03d' % i)
    candidates = [f for f in os.listdir(run_dir) if f.startswith('output') and f.endswith('.dat')]
    if candidates:
        first_run = run_dir
        output_files = candidates
        break

if first_run is None:
    print('ERROR: No output files found in any run directory', file=sys.stderr)
    sys.exit(1)

for output_name in output_files:
    stats_base = output_name.replace('.dat', '')
    print(f'Processing {output_name}...')

    # Read header
    with open(os.path.join(first_run, output_name), 'r') as f:
        header_line = f.readline().strip()

    # Collect data from all runs
    all_data = []
    for i in range(1, num_runs + 1):
        run_file = os.path.join(ensemble_dir, 'run_%03d' % i, output_name)
        if not os.path.isfile(run_file):
            continue
        try:
            data = np.loadtxt(run_file, skiprows=1)
            if data.ndim == 1:
                data = data.reshape(1, -1)
            all_data.append(data)
        except Exception as e:
            print(f'  WARNING: Could not read {run_file}: {e}', file=sys.stderr)

    if len(all_data) == 0:
        print(f'  ERROR: No valid data for {output_name}', file=sys.stderr)
        continue

    min_rows = min(d.shape[0] for d in all_data)
    stacked = np.stack([d[:min_rows, :] for d in all_data], axis=0)

    mean_data = np.mean(stacked, axis=0)
    std_data  = np.std(stacked, axis=0)
    min_data  = np.min(stacked, axis=0)
    max_data  = np.max(stacked, axis=0)

    def write_stats_file(filepath, header, data):
        with open(filepath, 'w') as f:
            f.write(header + '\n')
            for row in data:
                f.write('%5d' % int(round(row[0])))
                for j in range(1, len(row)):
                    f.write('%12.2f' % row[j])
                f.write('\n')

    write_stats_file(os.path.join(ensemble_dir, stats_base + '_mean.dat'), header_line, mean_data)
    write_stats_file(os.path.join(ensemble_dir, stats_base + '_std.dat'),  header_line, std_data)
    write_stats_file(os.path.join(ensemble_dir, stats_base + '_min.dat'),  header_line, min_data)
    write_stats_file(os.path.join(ensemble_dir, stats_base + '_max.dat'),  header_line, max_data)
    print(f'  Wrote {stats_base}_mean.dat, {stats_base}_std.dat, {stats_base}_min.dat, {stats_base}_max.dat')
    print(f'  Used {len(all_data)} of {num_runs} runs, {min_rows} timesteps')

    # Compute per-timestep aggregated quantities (matching ExaEpi definitions):
    #   TotalInfected = PS/PI + S/PI/NH + S/PI/H + PS/I + S/I/NH + S/I/H
    #                   + A/PI + A/I + H/NI + H/I
    #                   (matches totalInfected() in AgentDefinitions.H)
    #   TotalHospitalized = H/NI + H/I + ICU + V (ventilator)
    #   Deaths = D
    # Column layout: Day(0) Su(1) PS/PI(2) S/PI/NH(3) S/PI/H(4) PS/I(5)
    #   S/I/NH(6) S/I/H(7) A/PI(8) A/I(9) H/NI(10) H/I(11) ICU(12)
    #   V(13) R(14) D(15) ...
    headers = header_line.split()
    infected_cols = ['PS/PI', 'S/PI/NH', 'S/PI/H', 'PS/I', 'S/I/NH', 'S/I/H', 'A/PI', 'A/I', 'H/NI', 'H/I']
    hosp_cols = ['H/NI', 'H/I', 'ICU', 'V']

    infected_idx = [headers.index(c) for c in infected_cols if c in headers]
    hosp_idx     = [headers.index(c) for c in hosp_cols     if c in headers]
    death_idx    = headers.index('D') if 'D' in headers else None
    recov_idx    = headers.index('R') if 'R' in headers else None

    if infected_idx and hosp_idx and death_idx is not None and recov_idx is not None:
        # stacked shape: (num_runs, num_timesteps, num_cols)
        total_infected = np.sum(stacked[:, :, infected_idx], axis=2)
        total_hosp     = np.sum(stacked[:, :, hosp_idx],     axis=2)
        deaths         = stacked[:, :, death_idx]
        recovered      = stacked[:, :, recov_idx]
        days           = stacked[0, :, 0]  # Day column (same for all runs)

        # Stack derived quantities: (num_runs, num_timesteps, 4)
        derived = np.stack([total_infected, total_hosp, deaths, recovered], axis=2)
        derived_mean = np.mean(derived, axis=0)
        derived_std  = np.std(derived, axis=0)
        derived_min  = np.min(derived, axis=0)
        derived_max  = np.max(derived, axis=0)

        summary_header = '%5s %16s %16s %16s %16s' % ('Day', 'TotalInfected', 'TotalHospitalized', 'Deaths', 'Recovered')

        def write_summary_file(filepath, header, days, data):
            with open(filepath, 'w') as f:
                f.write(header + '\n')
                for k in range(len(days)):
                    f.write('%5d' % int(round(days[k])))
                    for j in range(data.shape[1]):
                        f.write(' %16.2f' % data[k, j])
                    f.write('\n')

        write_summary_file(os.path.join(ensemble_dir, stats_base + '_summary_mean.dat'), summary_header, days, derived_mean)
        write_summary_file(os.path.join(ensemble_dir, stats_base + '_summary_std.dat'),  summary_header, days, derived_std)
        write_summary_file(os.path.join(ensemble_dir, stats_base + '_summary_min.dat'),  summary_header, days, derived_min)
        write_summary_file(os.path.join(ensemble_dir, stats_base + '_summary_max.dat'),  summary_header, days, derived_max)
        print(f'  Wrote {stats_base}_summary_mean.dat, {stats_base}_summary_std.dat, {stats_base}_summary_min.dat, {stats_base}_summary_max.dat')
    else:
        print('  WARNING: Could not find infected/hospitalized/death columns; skipping summary', file=sys.stderr)

PYEOF

echo ""
echo "Ensemble job finished at: \$(date)"
EOF

    chmod +x "$job_script"
    print_verbose "Created ensemble job script: ${job_script}"
}

#------------------------------------------------------------------------------
# Main execution
#------------------------------------------------------------------------------

process_ensemble_case() {
    local case_name="$1"
    local platform="$2"
    local agent_exe="$3"
    local dry_run="$4"
    local num_runs="$ENSEMBLE_SIZE"

    # Find input file
    print_verbose "Looking for input file for case: ${case_name}"
    local input_file=$(find_input_file "${case_name}")
    if [[ $? -ne 0 ]]; then
        print_error "Input file not found for case: ${case_name}"
        return 1
    fi
    print_success "Found input file: ${input_file}"

    # Get platform defaults, with case-specific overrides
    local case_tasks=$(get_case_specific_resources "${case_name}" "${platform}" "tasks")
    local ntasks nnodes queue walltime

    if [[ -z "$OVERRIDE_NTASKS" ]]; then
        if [[ -n "$case_tasks" ]]; then
            ntasks="$case_tasks"
        else
            ntasks="${PLATFORM_DEFAULTS_TASKS[$platform]:-4}"
        fi
    else
        ntasks="$OVERRIDE_NTASKS"
    fi

    nnodes="${OVERRIDE_NNODES:-${PLATFORM_DEFAULTS_NODES[$platform]:-1}}"
    queue="${OVERRIDE_QUEUE:-${PLATFORM_DEFAULTS_QUEUE[$platform]:-}}"
    walltime="${OVERRIDE_WALLTIME:-06:00:00}"

    # Create ensemble directory
    local ensemble_dir="${PROJECT_DIR}/.ensemble_${case_name}_${platform}"
    print_verbose "Creating ensemble directory: ${ensemble_dir}"
    mkdir -p "$ensemble_dir"

    # Copy data files using the existing setup machinery (reuse setup_run_directory logic)
    # Extract and copy data files
    local data_files=$(extract_data_files "$input_file")
    local copied_count=0
    local missing_files=()

    while IFS= read -r data_file; do
        if [[ -z "$data_file" ]]; then
            continue
        fi
        if [[ -f "${ensemble_dir}/${data_file}" ]]; then
            copied_count=$((copied_count + 1))
            continue
        fi
        local source_file=$(find_data_file "$data_file")
        if [[ $? -eq 0 ]] && [[ -n "$source_file" ]]; then
            cp "$source_file" "${ensemble_dir}/"
            copied_count=$((copied_count + 1))
        else
            print_warning "Data file not found: ${data_file}"
            missing_files+=("$data_file")
        fi
    done <<< "$data_files"

    if [[ ${#missing_files[@]} -gt 0 ]]; then
        print_error "Missing data files; set EXAEPI_DIR"
        return 1
    fi

    # Copy/create input file in ensemble directory
    local run_input="${ensemble_dir}/inputs_${case_name}"
    if [[ -n "$OVERRIDE_MAX_STEP" ]] || [[ -n "$OVERRIDE_STOP_TIME" ]]; then
        create_modified_input "$input_file" "$run_input"
    else
        cp "$input_file" "$run_input"
    fi

    # Create ensemble job script
    create_ensemble_job_script "$platform" "$ntasks" "$nnodes" "$queue" "$walltime" \
                               "$agent_exe" "inputs_${case_name}" "$ensemble_dir" \
                               "$case_name" "$num_runs"

    # Display configuration
    echo ""
    echo "=========================================="
    echo "ExaEpi Ensemble Configuration"
    echo "=========================================="
    echo "Case:        ${case_name}"
    echo "Mode:        batch (ensemble)"
    echo "Ensemble:    ${num_runs} runs"
    echo "Platform:    ${platform}"
    echo "Ensemble dir: ${ensemble_dir}"
    echo "Input file:  ${input_file}"
    echo "Agent exe:   ${agent_exe}"
    echo "MPI tasks:   ${ntasks}"
    echo "Nodes:       ${nnodes}"
    [[ -n "$queue" ]] && echo "Queue:       ${queue}"
    [[ -n "$walltime" ]] && echo "Walltime:    ${walltime}"
    [[ -n "$OVERRIDE_MAX_STEP" ]] && echo "Max steps:   ${OVERRIDE_MAX_STEP} (overridden)"
    [[ -n "$OVERRIDE_STOP_TIME" ]] && echo "Stop time:   ${OVERRIDE_STOP_TIME} (overridden)"
    echo "=========================================="
    echo ""

    if [[ "$dry_run" == "true" ]]; then
        print_info "Dry run - would submit:"
        echo "  cd ${ensemble_dir} && sbatch exaepi.job"
    else
        print_info "Submitting ensemble job for case: ${case_name}"
        case "$platform" in
            linux|linux-gpu|desktop)
                # No SLURM, run the job script directly in background
                print_info "No batch scheduler detected; running ensemble script directly..."
                (cd "$ensemble_dir" && bash exaepi.job)
                local exit_code=$?
                if [[ $exit_code -eq 0 ]]; then
                    print_success "Ensemble completed for ${case_name}!"
                else
                    print_error "Ensemble failed for ${case_name} with exit code: $exit_code"
                    return $exit_code
                fi
                ;;
            *)
                (cd "$ensemble_dir" && sbatch exaepi.job)
                print_success "Ensemble job submitted for ${case_name}!"
                ;;
        esac
    fi

    print_info "Ensemble output will be in: ${ensemble_dir}"
    print_info "Statistics files: output_*_mean.dat, output_*_std.dat, output_*_min.dat, output_*_max.dat"

    return 0
}

process_single_case() {
    local case_name="$1"
    local platform="$2"
    local agent_exe="$3"
    local mode="$4"
    local dry_run="$5"

    # Find input file
    print_verbose "Looking for input file for case: ${case_name}"
    local input_file=$(find_input_file "${case_name}")
    if [[ $? -ne 0 ]]; then
        print_error "Input file not found for case: ${case_name}"
        return 1
    fi
    print_success "Found input file: ${input_file}"

    # Get platform defaults, with case-specific overrides
    local case_tasks=$(get_case_specific_resources "${case_name}" "${platform}" "tasks")
    local ntasks nnodes queue walltime

    if [[ -z "$OVERRIDE_NTASKS" ]]; then
        if [[ -n "$case_tasks" ]]; then
            ntasks="$case_tasks"
        else
            ntasks="${PLATFORM_DEFAULTS_TASKS[$platform]:-4}"
        fi
    else
        ntasks="$OVERRIDE_NTASKS"
    fi

    nnodes="${OVERRIDE_NNODES:-${PLATFORM_DEFAULTS_NODES[$platform]:-1}}"
    queue="${OVERRIDE_QUEUE:-${PLATFORM_DEFAULTS_QUEUE[$platform]:-}}"
    walltime="${OVERRIDE_WALLTIME:-${PLATFORM_DEFAULTS_WALLTIME[$platform]:-01:00:00}}"

    # Setup run directory and copy data files
    print_verbose "Setting up run directory..."
    print_info "Copying data files to run directory..."
    setup_run_directory "${case_name}" "${platform}" "${input_file}"
    if [[ $? -ne 0 ]]; then
        print_error "Failed to setup run directory for case: ${case_name}"
        return 1
    fi
    # RUN_DIR is set by setup_run_directory function
    local run_dir="$RUN_DIR"
    print_success "Run directory: ${run_dir}"

    # Copy/create input file in run directory
    local run_input="${run_dir}/inputs_${case_name}"
    if [[ -n "$OVERRIDE_MAX_STEP" ]] || [[ -n "$OVERRIDE_STOP_TIME" ]]; then
        create_modified_input "$input_file" "$run_input"
        print_verbose "Created modified input file in run directory"
    else
        cp "$input_file" "$run_input"
        print_verbose "Copied input file to run directory"
    fi

    # Create run.sh and exaepi.job scripts in run directory
    print_verbose "Creating helper scripts in run directory..."
    create_run_script "$platform" "$ntasks" "$nnodes" "$queue" \
                      "$agent_exe" "inputs_${case_name}" "$run_dir"
    create_job_script "$platform" "$ntasks" "$nnodes" "$queue" "$walltime" \
                      "$agent_exe" "inputs_${case_name}" "$run_dir" "$case_name"
    print_success "Created run.sh and exaepi.job in run directory"

    # Display configuration
    echo ""
    echo "=========================================="
    echo "ExaEpi Run Configuration"
    echo "=========================================="
    echo "Case:        ${case_name}"
    echo "Mode:        ${mode}"
    echo "Platform:    ${platform}"
    echo "Run dir:     ${run_dir}"
    echo "Input file:  ${input_file}"
    echo "Agent exe:   ${agent_exe}"
    echo "MPI tasks:   ${ntasks}"
    echo "Nodes:       ${nnodes}"
    [[ -n "$queue" ]] && echo "Queue:       ${queue}"
    [[ -n "$walltime" ]] && echo "Walltime:    ${walltime}"
    [[ -n "$OVERRIDE_MAX_STEP" ]] && echo "Max steps:   ${OVERRIDE_MAX_STEP} (overridden)"
    [[ -n "$OVERRIDE_STOP_TIME" ]] && echo "Stop time:   ${OVERRIDE_STOP_TIME} (overridden)"
    echo "=========================================="
    echo ""
    print_info "Helper scripts created:"
    echo "  ${run_dir}/run.sh    - Interactive execution"
    echo "  ${run_dir}/exaepi.job   - Batch submission"
    echo ""

    # Execute based on mode
    if [[ "$mode" == "batch" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            print_info "Dry run - would submit:"
            echo "  cd ${run_dir} && sbatch exaepi.job"
        else
            print_info "Submitting batch job for case: ${case_name}"
            (cd "$run_dir" && sbatch exaepi.job)
            print_success "Job submitted for ${case_name}!"
        fi
    else
        # Interactive mode - run from run directory
        if [[ "$dry_run" == "true" ]]; then
            print_info "Dry run - would execute:"
            echo "  cd ${run_dir} && ./run.sh"
        else
            print_info "Starting ExaEpi simulation for case: ${case_name}..."
            echo ""
            (cd "$run_dir" && ./run.sh)
            local exit_code=$?
            echo ""

            if [[ $exit_code -eq 0 ]]; then
                print_success "Simulation completed successfully for ${case_name}!"
                print_info "Output files in: ${run_dir}"
            else
                print_error "Simulation failed for ${case_name} with exit code: $exit_code"
                print_info "Check logs in: ${run_dir}"
                return $exit_code
            fi
        fi
    fi

    return 0
}

main() {
    parse_args "$@"

    # Set defaults
    MODE="${MODE:-$DEFAULT_MODE}"

    # Ensemble mode implies batch
    if [[ "$ENSEMBLE" == "true" ]] && [[ "$MODE" != "batch" ]]; then
        MODE="batch"
    fi

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

    # Handle ensemble mode
    if [[ "$ENSEMBLE" == "true" ]]; then
        if [[ "$RUN_ALL" == "true" ]]; then
            local all_cases=($(get_all_cases))
            if [[ ${#all_cases[@]} -eq 0 ]]; then
                print_error "No input cases found in ${INPUTS_DIR}"
                exit 1
            fi
            print_info "Running ensemble for ${#all_cases[@]} case(s)..."
            local success_count=0
            local fail_count=0
            for case_name in "${all_cases[@]}"; do
                print_info "=========================================="
                print_info "Ensemble for case: ${case_name}"
                print_info "=========================================="
                process_ensemble_case "$case_name" "$PLATFORM" "$AGENT_EXE" "$DRY_RUN"
                if [[ $? -eq 0 ]]; then
                    success_count=$((success_count + 1))
                else
                    fail_count=$((fail_count + 1))
                fi
            done
            echo "Ensemble summary: ${success_count} succeeded, ${fail_count} failed"
            [[ $fail_count -gt 0 ]] && exit 1
        else
            if [[ -z "$CASE_NAME" ]]; then
                print_error "No case specified. Use -c/--case=NAME or -a/--all."
                echo ""
                show_help
                exit 1
            fi
            process_ensemble_case "$CASE_NAME" "$PLATFORM" "$AGENT_EXE" "$DRY_RUN"
            exit $?
        fi
        exit 0
    fi

    # Handle --all flag
    if [[ "$RUN_ALL" == "true" ]]; then
        # Get all available cases
        local all_cases=($(get_all_cases))

        if [[ ${#all_cases[@]} -eq 0 ]]; then
            print_error "No input cases found in ${INPUTS_DIR}"
            exit 1
        fi

        print_info "Processing ${#all_cases[@]} case(s)..."
        echo ""

        local success_count=0
        local fail_count=0
        local failed_cases=()

        for case_name in "${all_cases[@]}"; do
            print_info "=========================================="
            print_info "Processing case: ${case_name}"
            print_info "=========================================="

            process_single_case "$case_name" "$PLATFORM" "$AGENT_EXE" "$MODE" "$DRY_RUN"
            if [[ $? -eq 0 ]]; then
                success_count=$((success_count + 1))
            else
                fail_count=$((fail_count + 1))
                failed_cases+=("$case_name")
            fi
            echo ""
        done

        # Summary
        echo "=========================================="
        echo "All Cases Summary"
        echo "=========================================="
        echo "Total cases:     ${#all_cases[@]}"
        echo "Successful:      ${success_count}"
        echo "Failed:          ${fail_count}"
        if [[ $fail_count -gt 0 ]]; then
            echo ""
            echo "Failed cases:"
            for failed_case in "${failed_cases[@]}"; do
                echo "  - ${failed_case}"
            done
        fi
        echo "=========================================="

        if [[ $fail_count -gt 0 ]]; then
            exit 1
        fi
    else
        # Single case mode
        if [[ -z "$CASE_NAME" ]]; then
            print_error "No case specified. Use -c/--case=NAME or -a/--all."
            echo ""
            show_help
            exit 1
        fi
        process_single_case "$CASE_NAME" "$PLATFORM" "$AGENT_EXE" "$MODE" "$DRY_RUN"
        exit $?
    fi
}

# Run main function
main "$@"
