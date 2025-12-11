# ExaEpi Regression Test Suite - New Streamlined Workflow

This directory contains a streamlined, configuration-driven regression test suite for ExaEpi across multiple HPC systems.

## Overview

The new workflow replaces scattered bash scripts with a unified Python orchestration tool (`regtest.py`) and configuration files. This provides:

- **Single interface** for all test operations
- **Machine auto-detection**
- **Configuration-driven** test case and machine definitions
- **Dynamic directory generation** (no more 32+ pre-created directories)
- **Simplified workflow** with Makefile shortcuts

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

1. **Direct build** (typical for workstations/PCs):
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

   The tool automatically detects which structure you're using and finds the appropriate executable.

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
```

## Directory Structure

```
regtests/
├── config/                  # Configuration files
│   ├── machines.yaml       # Machine-specific settings
│   ├── test_cases.yaml     # Test case definitions
│   └── templates/          # (Future) Job script templates
├── common/                  # Shared data files and legacy scripts
├── scripts/                 # Legacy bash scripts (kept for reference)
├── baselines/              # Generated baseline test directories
├── tests/                  # Generated test directories
├── regtest.py              # Main orchestration script
├── Makefile                # Convenience wrapper
└── REGTEST_README.md       # This file
```

## Configuration Files

### config/machines.yaml

Defines machine-specific settings:
- Scheduler type (slurm, flux)
- Batch vs interactive mode
- Resource requirements (nodes, GPUs, etc.)
- Environment variables
- Run commands

To add a new machine, add an entry to this file.

### config/test_cases.yaml

Defines test cases:
- Input files
- Required data files
- Test parameters
- Tags and groupings

To add a new test case, add an entry to this file.

## Workflow Comparison

### Old Workflow
```bash
# Multiple separate steps with machine-specific scripts
./scripts/create_baseline_dirs.perlmutter.sh
./scripts/submit_baseline_jobs.perlmutter
# Wait...
./scripts/create_testing_dirs.perlmutter.sh
./scripts/submit_test_jobs.perlmutter
# Wait...
./scripts/compare_results.perlmutter
./scripts/create_plots.sh
```

### New Workflow
```bash
# Single unified interface
make baseline CASES=standard
# Wait...
make test CASES=standard
# Wait...
make compare
```

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

## Machine-Specific Notes

### Perlmutter (NERSC)
- Uses SLURM batch mode
- 4 GPUs per node
- Jobs submitted with `sbatch`
- Auto-detects via `$NERSC_HOST` environment variable

### LC Systems (Dane, Matrix, Tuolumne)
- Interactive mode (direct `srun` or `flux run`)
- Jobs run in background
- Auto-detects via `$LCHOST` environment variable

**Dane:**
- CPU-based system
- 100 MPI tasks

**Matrix:**
- GPU-based system
- 4 GPUs

**Tuolumne:**
- CPU-based system
- Uses Flux scheduler
- 100 MPI tasks

### Linux Workstation/Cluster
- Standard Linux systems with MPICH or OpenMPI
- No batch scheduler required
- Auto-detects MPI launcher (`mpirun` or `mpiexec`)
- Default: 4 MPI ranks (configurable)
- Manual specification required: `--machine linux`

**Configuration Options:**

You can customize the Linux machine settings in `config/machines.yaml`:

```yaml
linux:
  tasks: 8              # Change number of MPI ranks
  mpi_launcher: mpirun  # Force specific launcher
  mpi_flags: "--bind-to core"  # Add MPI flags
```

**Usage:**
```bash
# Run on Linux workstation with default settings (4 MPI ranks)
./regtest.py create-baseline --cases ca --machine linux
./regtest.py run-baseline --cases ca --machine linux

# Or use Makefile
make baseline CASES=ca MACHINE=linux
```

### Linux Workstation with CUDA GPUs
- Linux systems with NVIDIA GPUs
- Supports single or multiple GPUs
- No GPU-aware MPI by default (can be enabled in config)
- Default: 1 GPU, 1 MPI rank
- Manual specification required: `--machine linux-gpu`

**Configuration Options:**

```yaml
linux-gpu:
  gpus: 2               # Number of GPUs
  tasks: 2              # MPI ranks (typically 1 per GPU)
  gpu_aware_mpi: "amrex.use_gpu_aware_mpi=1"  # If your MPI supports it
```

**Usage:**
```bash
# Run on Linux workstation with GPU
./regtest.py run-test --cases bay --machine linux-gpu

# Or use Makefile
make test CASES=bay MACHINE=linux-gpu
```

## Migrating from Old Scripts

The old workflow scripts in `scripts/` directory are preserved for reference. To migrate:

1. Use `regtest.py` or `Makefile` instead of individual bash scripts
2. Baselines and tests are now created in `baselines/` and `tests/` directories
3. No need to maintain `shell_directories/` - directories are generated on demand
4. Machine detection is automatic - no need for separate scripts per machine

## Troubleshooting

**Environment validation fails:**
- Ensure `EXAEPI_BUILD` and `EXAEPI_DIR` are set
- Check that ExaEpi executable exists in `$EXAEPI_BUILD/bin/`
- Verify comparison tool exists at `$EXAEPI_DIR/utilities/tests/chkdiff.sh`

**Machine not auto-detected:**
- Check that machine environment variable is set (`NERSC_HOST` or `LCHOST`)
- For Linux workstations, auto-detection is not available - use `--machine linux` or `--machine linux-gpu`
- Use `--machine` flag to specify explicitly
- Run `./regtest.py list-machines` to see available machines

**MPI launcher not found (Linux systems):**
- Ensure `mpirun` or `mpiexec` is in your PATH
- For MPICH: `which mpiexec`
- For OpenMPI: `which mpirun`
- If using a custom launcher, specify it in `config/machines.yaml`

**Test case not found:**
- Run `./regtest.py list-cases` to see available cases
- Check spelling (case-sensitive)
- Ensure test case is defined in `config/test_cases.yaml`

**Comparison fails:**
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
    tuolumne:
      tasks: 1
      gpus: 1
    dane:
      tasks: 25
    linux:
      tasks: 4
    linux-gpu:
      tasks: 1
      gpus: 1
```

This allows test cases to scale appropriately for their problem size while still using the same configuration system.

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

## Generating Plots

After running tests and baselines, you can generate comparison plots:

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

The plotting system (`plot_results.py`) generates a single PNG file per test case: `plots/<case.machine>.png`

**Single-disease simulations**:
- Single image with 6 subplots (2x3 grid)
- Metrics: Susceptible, Total Infectious, Hospitalized, ICU, Deaths, Recovered
- Example: `plots/bay.linux.png`, `plots/ca.perlmutter.png`
- Each subplot shows:
  - Baseline results as a solid black line
  - Test results as blue points

**Multi-disease simulations** (e.g., ca.2dc1c2):
- Single image with 6 subplots showing all diseases on the same axes
- Example: `plots/ca.2dc1c2.linux.png`
- Each disease uses a different color (red, green, orange, etc.)
- Each subplot shows:
  - For each disease: baseline (solid line) and test results (markers)
  - Legend identifies each disease strain
- Disease names are read from `agent.disease_names` in input file
- Default names (`default00`, `default01`, ...) used if not specified

All plots include:
- Grid and legends for easy interpretation
- Norm calculations (L1, L2, L∞) displayed in subplot titles or printed to console

**Multi-disease detection**: The plotting system automatically detects multi-disease simulations by:
1. Parsing the input file for `agent.number_of_diseases`
2. Reading `agent.disease_names` if specified
3. Looking for `output_<disease_name>.dat` files instead of `output.dat`
4. Plotting all diseases on the same axes for direct comparison

### Norm Calculations

The script automatically computes and prints difference norms for each metric:

- **L1 norm**: Sum of absolute differences
- **L2 norm**: Root mean square difference
- **L∞ norm**: Maximum absolute difference

Both absolute and relative (normalized by baseline) norms are reported in scientific notation:

```
  Metric               L1 (abs)     L2 (abs)     L∞ (abs)     L1 (rel)     L2 (rel)     L∞ (rel)
  -------------------- ------------ ------------ ------------ ------------ ------------ ------------
  Susceptible          1.23e+05     4.56e+03     7.89e+02     1.23e-03     3.45e-03     5.67e-03
  Total Infectious     2.34e+04     5.67e+02     8.90e+01     2.34e-03     4.56e-03     6.78e-03
  ...
```

The relative norms are also displayed in each subplot title for quick visual reference.

### Plot Requirements

The plotting system requires matplotlib:

```bash
pip install matplotlib
# or
conda install matplotlib
```

If matplotlib is not installed, the plotting commands will show an informative error message.

### Customizing Plots

Edit `plot_results.py` to customize:
- Plot styles (colors, line styles, markers)
- Figure size and DPI (default: 16x10 inches at 150 DPI)
- Metrics to plot (currently: Susceptible, Total Infectious, Hospitalized, ICU, Deaths, Recovered)
- Subplot layout (currently: 2x3 grid)
- Grid and legend positioning

Metrics are defined by combining output.dat columns based on ExaEpi epidemiological compartments. See the column definitions at the top of `plot_results.py`.

## Future Enhancements

Planned improvements:
- [ ] Templated job scripts using Jinja2
- [ ] HTML test report generation
- [ ] Test result database/history tracking
- [ ] Parallel test execution optimization
- [ ] CI/CD integration hooks
