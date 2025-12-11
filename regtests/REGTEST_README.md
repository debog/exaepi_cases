# ExaEpi Regression Test Suite

Configuration-driven regression test framework for ExaEpi across multiple HPC systems and Linux workstations.

## Overview

The regression test suite provides automated testing of ExaEpi across different test cases and computational platforms with:

- **Unified interface** - Single tool (`regtest.py`) for all test operations
- **Machine auto-detection** - Automatically detects Perlmutter, LC systems, or Linux
- **Configuration-driven** - YAML-based test case and machine definitions
- **Dynamic test management** - Directories created on-demand with smart symlinking
- **Python-based plotting** - Matplotlib visualization with multi-disease support
- **Makefile shortcuts** - Convenient commands for common workflows

## Quick Start

### Prerequisites

1. **Install Python dependencies:**
   ```bash
   pip install -r requirements.txt
   # or
   conda install --file requirements.txt
   ```

   Required packages: PyYAML, matplotlib, numpy

2. **Set environment variables:**
   ```bash
   export EXAEPI_BUILD=/path/to/exaepi/build
   export EXAEPI_DIR=/path/to/exaepi/source
   ```

**Note on EXAEPI_BUILD structure:**

The system supports two directory structures:

1. **Direct build** (typical for workstations):
   ```
   $EXAEPI_BUILD/
   └── bin/
       └── agent
   ```

2. **Machine-specific subdirectories** (for shared filesystems):
   ```
   $EXAEPI_BUILD/
   ├── perlmutter/
   │   └── bin/
   │       └── agent
   ├── dane/
   │   └── bin/
   │       └── agent
   └── linux/
       └── bin/
           └── agent
   ```

   The tool automatically detects which structure you're using.

### Validate Environment

```bash
./regtest.py validate
# or
make validate
```

### List Available Options

```bash
# List test cases
./regtest.py list-cases
make list-cases

# List machines
./regtest.py list-machines
make list-machines
```

### Run Baseline Tests

```bash
# Create and run baselines (auto-detects machine)
make baseline CASES=standard

# Specify machine explicitly
make baseline CASES=ca,bay MACHINE=perlmutter
```

### Run Test Cases

```bash
# Create and run tests (auto-detects machine on HPC systems)
make test CASES=standard

# For Linux workstation, specify machine explicitly
make test CASES=ca,bay MACHINE=linux

# Run all tests
make test CASES=all

# Run quick subset
make quick-test
```

### Compare Results

```bash
make compare
# or
./regtest.py compare --machine linux  # Specify machine if needed
```

### Generate Plots

```bash
# Plot all test results
make plot

# Plot specific cases
make plot CASES=ca,bay MACHINE=linux

# Plot all standard cases
make plot CASES=standard
```

## Detailed Usage

### Using regtest.py Directly

```bash
# Create baseline directories
./regtest.py create-baseline --cases standard --machine perlmutter

# Run baselines (submit jobs or run directly depending on machine)
./regtest.py run-baseline --cases ca,bay

# Create test directories
./regtest.py create-test --cases all

# Run tests
./regtest.py run-test --cases all

# Compare test results against baselines
./regtest.py compare

# Generate plots
./regtest.py plot --cases standard --machine linux
```

### Test Case Selection

You can specify test cases in multiple ways:

**Individual cases:**
```bash
--cases ca,bay,ma
```

**Test groups:**
```bash
--cases standard    # ca, bay, ma, nm
--cases all_ca      # All California variants
--cases quick       # bay, ma
--cases full        # All test cases
```

**Special keyword:**
```bash
--cases all         # All available test cases
```

### Machine Selection

**Auto-detect (recommended):**
```bash
./regtest.py run-baseline --cases ca
# Automatically detects perlmutter, dane, matrix, or tuolumne
```

**Explicit:**
```bash
--machine perlmutter
--machine dane
--machine linux
```

## Directory Structure

```
regtests/
├── config/                  # Configuration files
│   ├── machines.yaml       # Machine-specific settings
│   ├── test_cases.yaml     # Test case definitions
│   └── templates/          # (Future) Job script templates
├── common/                  # Shared data files
├── baselines/              # Generated baseline test directories
├── tests/                  # Generated test directories
├── plots/                  # Generated plot output
├── regtest.py              # Main orchestration script
├── plot_results.py         # Plotting system
├── Makefile                # Convenience wrapper
├── requirements.txt        # Python dependencies
├── REGTEST_README.md       # This file
└── LINUX_QUICKSTART.md     # Linux-specific quick start
```

## Configuration Files

### config/machines.yaml

Defines machine-specific settings:
- Scheduler type (slurm, flux, none)
- Resource requirements (nodes, GPUs, MPI tasks)
- MPI launcher and flags
- Environment variables
- Run commands

To add a new machine, add an entry to this file.

### config/test_cases.yaml

Defines test cases:
- Input files
- Required data files
- Test parameters (nsteps, tags)
- Machine-specific resource overrides

To add a new test case, add an entry to this file.

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make help` | Show help message |
| `make validate` | Validate environment setup |
| `make list-cases` | List available test cases |
| `make list-machines` | List available machines |
| `make baseline` | Create and run baseline tests |
| `make test` | Create and run tests |
| `make compare` | Compare results |
| `make plot` | Generate comparison plots |
| `make clean` | Remove test directories |
| `make clean-baselines` | Remove baseline directories |
| `make clean-all` | Remove all generated directories |

### Quick Test Shortcuts

```bash
make ca          # Run just California test
make bay         # Run just Bay Area test
make ma          # Run just Massachusetts test
make nm          # Run just New Mexico test
make quick-test  # Run quick test subset (bay, ma)
```

## Test Case Groups

- **standard**: ca, bay, ma, nm (main test suite)
- **all_ca**: All California variants (ca, ca.noair, ca.random, ca.2dc1c2)
- **quick**: bay, ma (fast tests for quick validation)
- **full**: All available test cases
- **all_variants**: Alternative configurations (ca.noair, ca.random, etc.)

## Supported Machines

### Perlmutter (NERSC)
- Auto-detected via `$NERSC_HOST`
- SLURM batch scheduler
- 4 GPUs per node (NVIDIA A100)
- GPU-aware MPI

### LC Systems (Dane, Matrix, Tuolumne)
- Auto-detected via `$LCHOST`
- Interactive mode (direct execution)
- Jobs run in background

**Dane:**
- CPU-based system
- 100 MPI tasks (default)
- SLURM scheduler

**Matrix:**
- GPU-based system (NVIDIA)
- 4 GPUs
- SLURM scheduler

**Tuolumne:**
- GPU-based system (AMD MI250X)
- 4 GPUs
- Flux scheduler

### Linux Workstation/Cluster
- Standard Linux with MPICH or OpenMPI
- No batch scheduler required
- Auto-detects MPI launcher (`mpirun` or `mpiexec`)
- Default: 4 MPI ranks (configurable)
- Manual specification required: `--machine linux` or `--machine linux-gpu`

**Configuration options** in `config/machines.yaml`:
```yaml
linux:
  tasks: 8              # Number of MPI ranks
  mpi_launcher: mpirun  # Force specific launcher
  mpi_flags: "--bind-to core"  # Add MPI flags
```

**Linux with CUDA GPUs:**
```yaml
linux-gpu:
  gpus: 2               # Number of GPUs
  tasks: 2              # MPI ranks (typically 1 per GPU)
  gpu_aware_mpi: "amrex.use_gpu_aware_mpi=1"
```

## Generating Plots

After running tests and baselines, generate comparison plots:

### Basic Plotting

```bash
# Generate plots for all test cases on current machine
./regtest.py plot

# Or use Makefile
make plot

# Generate plots for specific cases
make plot CASES=ca,bay MACHINE=linux

# Plot all standard cases
make plot CASES=standard
```

### Plot Output

The plotting system (`plot_results.py`) generates PNG files for test cases:

**Single-disease simulations**: `plots/<case.machine>.png`
- Single image with 6 subplots (2x3 grid)
- Metrics: Susceptible, Total Infectious, Hospitalized, ICU, Deaths, Recovered
- Example: `plots/bay.linux.png`, `plots/ca.perlmutter.png`

**Multi-disease simulations** (e.g., ca.2dc1c2): `plots/<case.machine>.png`
- Single image with all diseases on the same axes
- Each disease uses a different color (red, green, orange, etc.)
- Example: `plots/ca.2dc1c2.linux.png` shows both covid1 and covid2
- Disease names read from `agent.disease_names` in input file
- Default names (`default00`, `default01`, ...) used if not specified

Each subplot shows:
- Baseline results as a solid line
- Test results as markers
- Grid and legends for easy interpretation

**Multi-disease detection**: The plotting system automatically:
1. Parses input files for `agent.number_of_diseases`
2. Reads `agent.disease_names` if specified
3. Looks for `output_<disease_name>.dat` files
4. Plots all diseases on the same axes for direct comparison

### Norm Calculations

The script automatically computes and prints difference norms for each metric:

- **L1 norm**: Sum of absolute differences
- **L2 norm**: Root mean square difference
- **L∞ norm**: Maximum absolute difference

Both absolute and relative (normalized by baseline) norms are reported:

```
  Metric               L1 (abs)     L2 (abs)     L∞ (abs)     L1 (rel)     L2 (rel)     L∞ (rel)
  -------------------- ------------ ------------ ------------ ------------ ------------ ------------
  Susceptible          1.23e+05     4.56e+03     7.89e+02     1.23e-03     3.45e-03     5.67e-03
  Total Infectious     2.34e+04     5.67e+02     8.90e+01     2.34e-03     4.56e-03     6.78e-03
  ...
```

The relative norms are also displayed in subplot titles (for single-disease cases).

### Plot Customization

Edit `plot_results.py` to customize:
- Plot styles (colors, line styles, markers)
- Figure size and DPI (default: 16x10 inches at 150 DPI)
- Metrics to plot
- Subplot layout (currently: 2x3 grid)
- Grid and legend positioning

## Troubleshooting

### Environment validation fails

- Ensure `EXAEPI_BUILD` and `EXAEPI_DIR` are set
- Check that ExaEpi executable exists in `$EXAEPI_BUILD/bin/` or `$EXAEPI_BUILD/<machine>/bin/`
- Verify comparison tool exists at `$EXAEPI_DIR/utilities/tests/chkdiff.sh`

### Machine not auto-detected

- Check that machine environment variable is set (`NERSC_HOST` or `LCHOST`)
- For Linux workstations, auto-detection is not available - use `--machine linux` or `--machine linux-gpu`
- Use `--machine` flag to specify explicitly
- Run `./regtest.py list-machines` to see available machines

### MPI launcher not found (Linux systems)

- Ensure `mpirun` or `mpiexec` is in your PATH
- For MPICH: `which mpiexec`
- For OpenMPI: `which mpirun`
- If using a custom launcher, specify it in `config/machines.yaml`

### Test case not found

- Run `./regtest.py list-cases` to see available cases
- Check spelling (case-sensitive)
- Ensure test case is defined in `config/test_cases.yaml`

### Comparison fails

- Ensure both baseline and test runs completed successfully
- Check that output files exist in both directories
- Verify `chkdiff.sh` tool is available

## Advanced Usage

### Machine-Specific Resource Overrides

Test cases can specify different resource requirements for different machines using the `machine_overrides` section. For example, the Bay Area case uses fewer resources:

```yaml
bay:
  name: "Bay Area"
  # ... other config ...
  machine_overrides:
    perlmutter:
      tasks_per_node: 1
      gpus_per_node: 1
    matrix:
      tasks: 1
      gpus: 1
    dane:
      tasks: 25
    linux:
      tasks: 4
```

This allows test cases to scale appropriately while using the same configuration system.

### Adding a New Test Case

Edit `config/test_cases.yaml`:

```yaml
test_cases:
  my_new_test:
    name: "My New Test"
    description: "Description of test"
    input_file: inputs.mytest
    data_files:
      - data1.dat
      - data2.bin
    nsteps: 100
    tags: [custom, experimental]
```

Then run:
```bash
./regtest.py create-test --cases my_new_test
```

### Adding a New Machine

Edit `config/machines.yaml`:

```yaml
machines:
  my_machine:
    display_name: "My Machine"
    env_var: MY_MACHINE_ENV
    scheduler: slurm
    batch_mode: true
    nodes: 1
    tasks: 4
    # ... other settings
```

### Disabling a Test

Create a `.disabled` file in the test directory:
```bash
touch baselines/ca.perlmutter/.disabled
```

The test will be skipped during runs and comparisons.

### Running Specific Test Variants

```bash
# Run only California without air travel
./regtest.py run-test --cases ca.noair

# Run all California variants
./regtest.py run-test --cases all_ca
```

## Complete Example Workflow

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
cd /path/to/regtests
make test CASES=standard MACHINE=linux

# 7. Wait for completion
ls -la tests/*/output.dat

# 8. Compare results
make compare MACHINE=linux

# 9. Generate plots
make plot MACHINE=linux

# 10. View plots
ls plots/*.png
# Each plot contains 6 subplots showing all key metrics
```

## See Also

- `LINUX_QUICKSTART.md` - Quick start guide for Linux workstations
- `config/machines.yaml` - Machine configuration
- `config/test_cases.yaml` - Test case definitions
- `requirements.txt` - Python dependencies
