# Quick Start Guide for Linux Workstations

This guide helps you run ExaEpi regression tests on standard Linux workstations or clusters with MPICH/OpenMPI.

## Prerequisites

1. **ExaEpi built with MPI support**
   ```bash
   export EXAEPI_BUILD=/path/to/your/exaepi/build
   export EXAEPI_DIR=/path/to/your/exaepi/source
   ```

   **Build directory structure:**
   - For a PC/workstation: `$EXAEPI_BUILD/bin/agent` (direct build)
   - For shared filesystems: `$EXAEPI_BUILD/linux/bin/agent` (machine subdirectory)

   The system automatically detects which structure you're using.

2. **MPI installation** (one of):
   - MPICH: `mpiexec` available in PATH
   - OpenMPI: `mpirun` available in PATH

3. **Python 3 with PyYAML**
   ```bash
   pip install pyyaml
   # or
   conda install pyyaml
   ```

## Basic Usage

### CPU-only Linux System

```bash
# Validate environment
./regtest.py validate

# Create and run a single test
./regtest.py create-test --cases ca --machine linux
./regtest.py run-test --cases ca --machine linux

# Or use Makefile shortcut
make test CASES=ca MACHINE=linux

# Compare against baseline (after creating baselines)
./regtest.py compare --machine linux

# Generate comparison plots
./regtest.py plot --machine linux
```

### Linux System with NVIDIA GPU(s)

```bash
# Single GPU test
make test CASES=bay MACHINE=linux-gpu

# For multiple GPUs, edit config/machines.yaml first:
# linux-gpu:
#   gpus: 4
#   tasks: 4

make test CASES=ca MACHINE=linux-gpu
```

## Customizing for Your System

Edit `config/machines.yaml` to customize settings:

### Example: 16-core workstation with OpenMPI

```yaml
linux:
  display_name: "My Workstation"
  env_var: null
  scheduler: none
  batch_mode: false
  mpi_launcher: mpirun
  mpi_flags: "--bind-to core"
  nodes: 1
  tasks: 16  # Use all 16 cores
  env_setup:
    OMP_NUM_THREADS: 1
```

### Example: Workstation with 2 GPUs

```yaml
linux-gpu:
  display_name: "My GPU Workstation"
  env_var: null
  scheduler: none
  batch_mode: false
  mpi_launcher: mpirun
  nodes: 1
  gpus: 2
  tasks: 2  # 1 task per GPU
  env_setup:
    OMP_NUM_THREADS: 1
  gpu_aware_mpi: "amrex.use_gpu_aware_mpi=0"
```

## Common Workflows

### Create Baselines Once

```bash
# Run with current code version to establish baseline
make baseline CASES=standard MACHINE=linux

# This creates baselines/ directory with reference results
```

### Test Code Changes

```bash
# After modifying code, rebuild and test
make test CASES=standard MACHINE=linux

# Compare against baselines
make compare MACHINE=linux
```

### Quick Validation

```bash
# Run smaller test cases for quick validation
make test CASES=quick MACHINE=linux
```

## Selecting Test Cases

Available test case groups:

- `standard` - Main test suite (ca, bay, ma, nm)
- `quick` - Fast tests (bay, ma)
- `all_ca` - All California variants
- `full` - All test cases

Individual cases:
- `ca` - California with air travel (120 days)
- `bay` - Bay Area (70 days)
- `ma` - Massachusetts (70 days)
- `nm` - New Mexico/Texas (120 days)

```bash
# Single test
make test CASES=ca MACHINE=linux

# Multiple tests
make test CASES="ca,bay,ma" MACHINE=linux

# Test group
make test CASES=standard MACHINE=linux
```

## Monitoring Test Execution

Tests run in the background. Monitor progress:

```bash
# Check test directories
ls -la tests/

# View output logs
tail -f tests/ca.linux/out.linux.log

# Check for output files
ls -la tests/ca.linux/output.dat
```

## Troubleshooting

### MPI launcher not found

```bash
# Check if MPI is installed
which mpirun
which mpiexec

# For MPICH
sudo apt install mpich
# or
conda install mpich

# For OpenMPI
sudo apt install openmpi-bin libopenmpi-dev
# or
conda install openmpi
```

### Wrong number of MPI ranks

Edit `config/machines.yaml`:
```yaml
linux:
  tasks: 8  # Change to desired number
```

### GPU not detected

```bash
# Check NVIDIA driver
nvidia-smi

# Ensure CUDA is in PATH
echo $CUDA_HOME

# Verify ExaEpi was built with GPU support
ldd $EXAEPI_BUILD/bin/agent | grep cuda
```

### Performance tuning

For OpenMPI, add binding flags in `config/machines.yaml`:
```yaml
linux:
  mpi_flags: "--bind-to core --map-by socket"
```

For MPICH:
```yaml
linux:
  mpi_launcher: mpiexec
  mpi_flags: "-bind-to core"
```

## Complete Example Session

```bash
# 1. Set up environment
export EXAEPI_BUILD=$HOME/exaepi/build
export EXAEPI_DIR=$HOME/exaepi

# 2. Validate
./regtest.py validate

# 3. Create baselines with current version
make baseline CASES=standard MACHINE=linux

# 4. Wait for completion (check logs)
ls -la baselines/*/output.dat

# 5. Make code changes and rebuild ExaEpi
cd $EXAEPI_DIR
# ... make changes ...
cd build && make -j8

# 6. Run tests
cd $EXAEPI_DIR/../Runs/exaepi/regtests
make test CASES=standard MACHINE=linux

# 7. Wait for completion
ls -la tests/*/output.dat

# 8. Compare results
make compare MACHINE=linux

# 9. Generate plots
make plot MACHINE=linux

# 10. View plots
ls plots/*/
# Open PNG files with your preferred image viewer
```

## See Also

- `REGTEST_README.md` - Complete documentation
- `config/linux_machine_examples.yaml` - More configuration examples
- `config/machines.yaml` - Current machine configuration
- `config/test_cases.yaml` - Test case definitions
