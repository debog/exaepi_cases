# ExaEpi Regression Test Suite

Unified, configuration-driven regression testing for ExaEpi across HPC systems and Linux workstations.

## Quick Reference

```bash
# Setup
export EXAEPI_BUILD=/path/to/exaepi/build
export EXAEPI_DIR=/path/to/exaepi/source
pip install -r requirements.txt

# Validate environment
./regtest.py validate

# Run tests (auto-detects HPC machines, specify for Linux)
make baseline CASES=standard              # HPC auto-detect
make baseline CASES=standard MACHINE=linux   # Linux workstation
make test CASES=ca,bay MACHINE=linux
make compare MACHINE=linux
make plot MACHINE=linux

# List available options
./regtest.py list-cases
./regtest.py list-machines
```

### Common Test Case Groups

- `standard` - Main suite (ca, bay, ma, nm)
- `quick` - Fast validation (bay, ma)
- `all_ca` - All California variants
- `full` - All test cases

### Key Commands

```bash
# Single test
make test CASES=ca MACHINE=linux

# Multiple tests
make test CASES="ca,bay,ma" MACHINE=linux

# Create baselines
make baseline CASES=standard MACHINE=linux

# Compare and plot
make compare MACHINE=linux
make plot MACHINE=linux

# Individual case shortcuts
make ca MACHINE=linux    # Run just CA test
make bay MACHINE=linux   # Run just Bay Area
```

## Prerequisites

1. **Python dependencies:**
   ```bash
   pip install -r requirements.txt
   ```
   Installs: PyYAML, matplotlib, numpy

2. **Environment variables:**
   ```bash
   export EXAEPI_BUILD=/path/to/exaepi/build
   export EXAEPI_DIR=/path/to/exaepi/source
   ```

3. **Build directory structure:**
   - Workstation: `$EXAEPI_BUILD/bin/agent`
   - Shared filesystem: `$EXAEPI_BUILD/<machine>/bin/agent`

   The system auto-detects your structure.

4. **MPI (Linux systems only):**
   - MPICH: `mpiexec` in PATH
   - OpenMPI: `mpirun` in PATH

## Supported Machines

### HPC Systems (auto-detected)

- **Perlmutter** (NERSC): SLURM batch mode, 4 GPUs per node
- **Dane** (LC): Interactive mode, 100 MPI tasks (CPU)
- **Matrix** (LC): Interactive mode, 4 GPUs
- **Tuolumne** (LC): Flux scheduler, 100 MPI tasks (CPU)

### Linux Workstations (manual specification)

- **linux**: CPU-only systems with MPICH/OpenMPI
- **linux-gpu**: Systems with NVIDIA GPUs

Linux systems require explicit `--machine` or `MACHINE=` specification.

## Configuration

### Customize Linux Settings

Edit `config/machines.yaml`:

**CPU workstation (16 cores):**
```yaml
linux:
  display_name: "My Workstation"
  tasks: 16
  mpi_launcher: mpirun
  mpi_flags: "--bind-to core"
  env_setup:
    OMP_NUM_THREADS: 1
```

**GPU workstation (2 GPUs):**
```yaml
linux-gpu:
  display_name: "My GPU Workstation"
  nodes: 1
  gpus: 2
  tasks: 2  # 1 task per GPU
  mpi_launcher: mpirun
  gpu_aware_mpi: "amrex.use_gpu_aware_mpi=0"
```

## Complete Example Workflow

```bash
# 1. Set up environment
export EXAEPI_BUILD=$HOME/exaepi/build
export EXAEPI_DIR=$HOME/exaepi

# 2. Validate
./regtest.py validate

# 3. Create baselines
make baseline CASES=standard MACHINE=linux

# 4. Wait for completion
ls -la baselines/*/output.dat

# 5. Make code changes and rebuild
cd $EXAEPI_DIR && make -j8

# 6. Run tests
cd ../Runs/exaepi/regtests
make test CASES=standard MACHINE=linux

# 7. Compare results
make compare MACHINE=linux

# 8. Generate plots
make plot MACHINE=linux

# 9. View plots
ls plots/*.png
```

## Monitoring Tests

```bash
# Check progress
ls -la tests/

# View logs
tail -f tests/ca.linux/out.linux.log

# Check output files
ls -la tests/ca.linux/output.dat
```

## Plotting Results

```bash
# Generate comparison plots
make plot MACHINE=linux

# Plots saved to plots/ directory
ls plots/*.png
```

**Plot structure:**
- Single-disease: 6 subplots (Susceptible, Infectious, Hospitalized, ICU, Deaths, Recovered)
- Multi-disease: Same 6 subplots with all diseases overlaid
- Includes L1, L2, L∞ norms for quantitative comparison
- Baseline: solid lines, Test: markers

## Directory Structure

```
regtests/
├── config/
│   ├── machines.yaml        # Machine configurations
│   ├── test_cases.yaml      # Test case definitions
│   └── templates/           # Job script templates
├── common/                  # Shared data files
├── baselines/              # Generated baseline tests
├── tests/                  # Generated test runs
├── plots/                  # Generated comparison plots
├── regtest.py              # Main orchestration script
├── plot_results.py         # Plotting script
└── Makefile                # Convenience wrapper
```

## Troubleshooting

### Environment validation fails

```bash
# Check variables
echo $EXAEPI_BUILD
echo $EXAEPI_DIR

# Verify executable exists
ls $EXAEPI_BUILD/bin/agent
# or
ls $EXAEPI_BUILD/linux/bin/agent
```

### MPI launcher not found (Linux)

```bash
# Check installation
which mpirun
which mpiexec

# Install if needed
sudo apt install mpich              # Debian/Ubuntu
sudo apt install openmpi-bin        # Debian/Ubuntu
conda install mpich                 # Conda
conda install openmpi               # Conda
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

# Verify CUDA
echo $CUDA_HOME

# Check ExaEpi GPU support
ldd $EXAEPI_BUILD/bin/agent | grep cuda
```

### Performance tuning

**OpenMPI:**
```yaml
linux:
  mpi_flags: "--bind-to core --map-by socket"
```

**MPICH:**
```yaml
linux:
  mpi_launcher: mpiexec
  mpi_flags: "-bind-to core"
```

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make help` | Show help message |
| `make validate` | Validate environment |
| `make list-cases` | List test cases |
| `make list-machines` | List machines |
| `make baseline` | Create and run baselines |
| `make test` | Create and run tests |
| `make compare` | Compare results |
| `make plot` | Generate plots |
| `make clean` | Remove test directories |
| `make clean-baselines` | Remove baselines |
| `make clean-all` | Remove all generated directories |

### Quick Test Shortcuts

```bash
make ca MACHINE=linux          # Run California test
make bay MACHINE=linux         # Run Bay Area test
make ma MACHINE=linux          # Run Massachusetts test
make nm MACHINE=linux          # Run New Mexico test
make quick-test MACHINE=linux  # Run bay + ma
```

## Advanced Usage

### Using regtest.py directly

```bash
# Create and run baselines
./regtest.py create-baseline --cases standard --machine linux
./regtest.py run-baseline --cases standard --machine linux

# Create and run tests
./regtest.py create-test --cases ca,bay --machine linux
./regtest.py run-test --cases ca,bay --machine linux

# Compare and plot
./regtest.py compare --machine linux
./regtest.py plot --machine linux
```

### Adding a new test case

Edit `config/test_cases.yaml`:
```yaml
test_cases:
  my_test:
    name: "My Test"
    description: "Test description"
    input_file: inputs.mytest
    data_files:
      - data1.dat
    nsteps: 100
    tags: [custom]
```

### Machine-specific overrides

Test cases can specify different resources per machine:
```yaml
bay:
  name: "Bay Area"
  machine_overrides:
    linux:
      tasks: 4
    linux-gpu:
      tasks: 1
      gpus: 1
```

### Disabling a test

```bash
touch baselines/ca.linux/.disabled
```

## Migration from Old Scripts

The new workflow replaces scattered bash scripts with unified commands:

**Old:**
```bash
./scripts/create_baseline_dirs.perlmutter.sh
./scripts/submit_baseline_jobs.perlmutter
./scripts/create_testing_dirs.perlmutter.sh
./scripts/submit_test_jobs.perlmutter
./scripts/compare_results.perlmutter
./scripts/create_plots.sh
```

**New:**
```bash
make baseline CASES=standard
make test CASES=standard
make compare
make plot
```

## Key Features

- **Single interface** for all operations
- **Machine auto-detection** (HPC systems)
- **Configuration-driven** (YAML files)
- **Dynamic directory generation** (no pre-created directories)
- **Unified plotting** with automatic multi-disease support
- **Makefile shortcuts** for common workflows

## See Also

- `LINUX_QUICKSTART.md` - Original Linux guide (deprecated)
- `REGTEST_README.md` - Original detailed guide (deprecated)
- `config/machines.yaml` - Machine configurations
- `config/test_cases.yaml` - Test case definitions
