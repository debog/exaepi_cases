# ExaEpi Medical Workers Studies - Quick Start Guide

Complete guide to running parameter sweep studies for medical workers and hospital interactions.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Environment Setup](#environment-setup)
3. [Running Studies](#running-studies)
4. [Checking Status](#checking-status)
5. [Generating Plots](#generating-plots)
6. [Understanding Results](#understanding-results)
7. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Software

1. **Python 3.7+** with packages:
   ```bash
   pip install pyyaml matplotlib numpy
   # or
   conda install pyyaml matplotlib numpy
   ```

2. **ExaEpi executable** built with your desired configuration

3. **MPI** (MPICH, OpenMPI, or SLURM/Flux on HPC systems)

### Environment Variables

Set these before running studies:

```bash
export EXAEPI_BUILD=/path/to/exaepi/build
export EXAEPI_DIR=/path/to/exaepi/source
```

**Note**: The build directory can be:
- Direct: `$EXAEPI_BUILD/bin/agent`
- Machine-specific: `$EXAEPI_BUILD/<machine>/bin/agent`

The system automatically detects which structure you're using.

---

## Environment Setup

### 1. Validate Your Environment

```bash
cd /path/to/medical_workers
./sweeps.py validate
```

Expected output:
```
Validating environment...
  ✓ EXAEPI_BUILD: /home/user/exaepi/build
  ✓ EXAEPI_DIR: /home/user/exaepi
  ✓ Detected machine: dane
  ✓ PyYAML installed

✓ Environment validation successful
```

### 2. List Available Studies

```bash
./sweeps.py list-studies
```

This shows:
- **recovery**: Medical workers proportion × patients per doctor (15 combos + baseline)
- **hosp_interactions**: Medical workers × hospital transmission rates (324 combos)

### 3. List Available Machines

```bash
./sweeps.py list-machines
```

Shows configured HPC systems and Linux workstations.

---

## Running Studies

### Recovery Study

Studies the impact of medical workers proportion and patient-to-doctor ratios.

#### Step 1: Create Run Directories

```bash
# Auto-detect machine
./sweeps.py create --study recovery --case CA

# Or specify machine explicitly
./sweeps.py create --study recovery --case CA --machine dane

# Using Makefile
make create STUDY=recovery CASE=CA
```

This creates:
- 1 baseline directory: `.run_recovery.CA.dane.baseline`
- 15 parameter sweep directories: `.run_recovery.CA.dane.mwprop003.nppd005`, etc.
- Symlinks to input files and data
- Machine-specific run scripts

#### Step 2: Run Parameter Sweep

```bash
# Run all parameter combinations
./sweeps.py run --study recovery --case CA --machine dane

# Using Makefile
make run STUDY=recovery CASE=CA

# Control parallel execution
make run STUDY=recovery CASE=CA MAX_PARALLEL=8
```

The system:
- Runs jobs in background (interactive) or submits to scheduler (batch)
- Automatically skips completed runs
- Manages parallel execution

#### Step 3: Check Status

```bash
./sweeps.py status --study recovery --case CA --machine dane

# Using Makefile
make status STUDY=recovery CASE=CA
```

Output:
```
Status for recovery/CA/dane:
  Total runs:    16
  Completed:     12 (75%)
  Running:       3
  Not started:   1
  Failed:        0
```

#### Step 4: Generate Plots

```bash
./sweeps.py plot --study recovery --case CA --machine dane

# Using Makefile
make plot STUDY=recovery CASE=CA
```

Creates plots in `recovery/plots/`:
- `recovery_CA_dane_mwprop03.png` (3% medical workers)
- `recovery_CA_dane_mwprop06.png` (6% medical workers)
- `recovery_CA_dane_mwprop09.png` (9% medical workers)

### Hospital Interactions Study

Studies hospital transmission between doctors and patients.

#### Complete Workflow

```bash
# Create run directories
make create STUDY=hosp_interactions CASE=CA

# Run parameter sweep (324 combinations - may take time!)
make run STUDY=hosp_interactions CASE=CA MAX_PARALLEL=4

# Check progress
make status STUDY=hosp_interactions CASE=CA

# Generate plots when complete
make plot STUDY=hosp_interactions CASE=CA
```

---

## Checking Status

### Monitor Running Jobs

```bash
# Check overall status
make status STUDY=recovery CASE=CA

# View log files
tail -f recovery/.run_recovery.CA.dane.baseline/out.dane.log

# Check specific parameter combination
tail -f recovery/.run_recovery.CA.dane.mwprop003.nppd010/out.dane.log
```

### Identify Failed Runs

```bash
# Status command shows failed count
make status STUDY=recovery CASE=CA

# Find failed runs manually
cd recovery
for dir in .run_recovery.CA.dane.*; do
    if [ ! -f "$dir/out.dane.log" ] || ! tail -1 "$dir/out.dane.log" | grep -q "finalized"; then
        echo "Failed or incomplete: $dir"
    fi
done
```

### Rerun Failed Cases

```bash
# Simply run again - completed runs are automatically skipped
make run STUDY=recovery CASE=CA
```

---

## Generating Plots

### Plot Types

#### Recovery Study Plots

Each plot (one per medical workers percentage) contains 5 panels:

1. **Infections** - Total infectious individuals over time
   - Baseline (black solid line)
   - Parameter sweep (colored lines with markers)

2. **Hospitalizations** - Hospital census (non-ICU)
   - Shows impact of patient-to-doctor ratios

3. **Deaths** - Cumulative deaths
   - Compares outcomes across parameters

4. **Overloaded Hospitals** - Number of hospitals exceeding capacity
   - Log scale
   - Shows healthcare system stress

5. **Underserved Patients** - Patients not receiving adequate care
   - Log scale
   - Indicates access to care issues

**Legend**: Different colors/markers represent different patients-per-doctor values (5, 10, 20, 50, 100)

#### Hospital Interactions Study Plots

Each plot (one per medical workers percentage) contains 3 panels:

1. **Infections** - Total infectious over time
2. **Hospitalizations** - Hospital census
3. **Deaths** - Cumulative deaths

Shows sample of transmission rate combinations (d2d, d2p, p2d, p2p) with varied line styles.

### Plot Customization

Edit `config/studies.yaml`:

```yaml
plot_config:
  figsize: [14, 10]  # Figure size (width, height) in inches
  dpi: 150           # Resolution for publication quality
  xrange: [0, 80]    # X-axis range (simulation days)
  grid: true         # Show grid lines
  format: png        # Output format: png or eps
```

### Output Location

Plots are saved in:
- `recovery/plots/recovery_<case>_<machine>_mwprop<XX>.png`
- `hosp_interactions/plots/hosp_interactions_<case>_<machine>_mwprop<XX>.png`

---

## Understanding Results

### Recovery Study Parameters

**Medical Workers Proportion** (mwprop):
- `0.00` - Baseline (no healthcare workers affected)
- `0.03` - 3% of population are medical workers
- `0.06` - 6% of population are medical workers
- `0.09` - 9% of population are medical workers

**Patients Per Doctor** (nppd):
- `5` - Very high doctor-to-patient ratio (best care)
- `10` - High ratio
- `20` - Moderate ratio
- `50` - Low ratio
- `100` - Very low ratio (worst care)
- `5000000` - Baseline (essentially infinite capacity)

### Hospital Interactions Study Parameters

**Medical Workers Proportion**: Same as recovery study

**Hospital Transmission Rates**:
- `xmit_hosp_d2d` - Doctor-to-doctor transmission (0.000, 0.006, 0.012)
- `xmit_hosp_d2p` - Doctor-to-patient transmission (0.000, 0.005, 0.010)
- `xmit_hosp_p2d` - Patient-to-doctor transmission (0.000, 0.006, 0.012)
- `xmit_hosp_p2p` - Patient-to-patient transmission (0.000, 0.003, 0.006)

### Output Files

Each run directory contains:

- `output.dat` - Main simulation output (18 columns)
  - Column definitions documented in `plot_sweeps.py`
  - Day, susceptible, various infectious states, hospitalized, deaths, etc.

- `num_bad_hospitals.dat` - Hospital metrics (recovery study only)
  - Column 2: Day
  - Column 3: Number of overloaded hospitals
  - Column 7: Number of underserved patients

- `out.<machine>.log` - Simulation log
  - Check last line for "finalized" to confirm completion

---

## Troubleshooting

### Common Issues

#### 1. Environment Not Validated

**Problem**: `./sweeps.py validate` fails

**Solution**:
```bash
# Check environment variables
echo $EXAEPI_BUILD
echo $EXAEPI_DIR

# Verify paths exist
ls $EXAEPI_BUILD/bin/
ls $EXAEPI_DIR/

# Set if missing
export EXAEPI_BUILD=/correct/path/to/build
export EXAEPI_DIR=/correct/path/to/source
```

#### 2. Machine Not Auto-Detected

**Problem**: "Could not auto-detect machine"

**Solution**:
```bash
# Check machine environment variables
echo $NERSC_HOST  # Should be set on NERSC systems
echo $LCHOST      # Should be set on LC systems

# Specify explicitly
./sweeps.py create --study recovery --case CA --machine linux
```

#### 3. No Run Directories Created

**Problem**: `make create` doesn't create directories

**Solution**:
```bash
# Verify data files exist
ls recovery/common/
ls hosp_interactions/common/

# Check for error messages
./sweeps.py create --study recovery --case CA --machine dane 2>&1 | grep ERROR
```

#### 4. Runs Not Completing

**Problem**: Jobs start but don't finish

**Solution**:
```bash
# Check logs for errors
tail -100 recovery/.run_recovery.CA.dane.baseline/out.dane.log

# Verify executable
ls -la $EXAEPI_BUILD/bin/*agent*

# Check resource limits
ulimit -a

# Test single run manually
cd recovery/.run_recovery.CA.dane.baseline
bash run.dane.sh
```

#### 5. Plotting Fails

**Problem**: `make plot` produces errors

**Solution**:
```bash
# Check matplotlib installation
python3 -c "import matplotlib; print(matplotlib.__version__)"

# Install if missing
pip install matplotlib numpy

# Verify completed runs exist
make status STUDY=recovery CASE=CA

# Check for output files
ls recovery/.run_recovery.CA.dane.*/output.dat
```

#### 6. Parallel Jobs Hang

**Problem**: Jobs submitted but system hangs

**Solution**:
```bash
# Reduce parallel job count
make run STUDY=recovery CASE=CA MAX_PARALLEL=2

# Check system resources
top
free -h
df -h

# Kill stuck jobs if needed
killall agent
```

---

## Complete Example Workflows

### Example 1: Recovery Study on LC System

```bash
# 1. Set environment
export EXAEPI_BUILD=$HOME/exaepi/build
export EXAEPI_DIR=$HOME/exaepi

# 2. Navigate to directory
cd /path/to/medical_workers

# 3. Validate
./sweeps.py validate

# 4. Create run directories for California case
make create STUDY=recovery CASE=CA

# 5. Run parameter sweep
make run STUDY=recovery CASE=CA MAX_PARALLEL=4

# 6. Monitor progress
watch -n 10 'make status STUDY=recovery CASE=CA'

# 7. Generate plots when complete
make plot STUDY=recovery CASE=CA

# 8. View plots
ls -lh recovery/plots/*.png
```

### Example 2: Hospital Interactions on Perlmutter

```bash
# 1. Set environment (if not already in .bashrc)
export EXAEPI_BUILD=/global/u1/username/exaepi/build
export EXAEPI_DIR=/global/u1/username/exaepi

# 2. Navigate and validate
cd /path/to/medical_workers
./sweeps.py validate

# 3. Create run directories
./sweeps.py create --study hosp_interactions --case Bay --machine perlmutter

# 4. Run sweep (324 combinations - batch mode on Perlmutter)
./sweeps.py run --study hosp_interactions --case Bay --machine perlmutter

# 5. Check status
./sweeps.py status --study hosp_interactions --case Bay --machine perlmutter

# 6. Generate plots
./sweeps.py plot --study hosp_interactions --case Bay --machine perlmutter
```

### Example 3: Quick Test with Bay Area Case

```bash
# Bay Area is smaller/faster than California

# Complete workflow using shortcuts
make create STUDY=recovery CASE=Bay
make run STUDY=recovery CASE=Bay MAX_PARALLEL=8
make status STUDY=recovery CASE=Bay
make plot STUDY=recovery CASE=Bay

# View results
ls -lh recovery/plots/*Bay*.png
```

---

## Makefile Quick Reference

### Basic Commands

```bash
make validate              # Validate environment
make list-studies          # List available studies
make list-machines         # List available machines

make create STUDY=<name> CASE=<case>   # Create run directories
make run STUDY=<name> CASE=<case>      # Run parameter sweep
make status STUDY=<name> CASE=<case>   # Check completion status
make plot STUDY=<name> CASE=<case>     # Generate plots

make clean STUDY=<name>                # Remove run directories
```

### Variables

```bash
STUDY        # recovery or hosp_interactions
CASE         # CA or Bay
MACHINE      # dane, perlmutter, matrix, tuolumne, linux, etc.
MAX_PARALLEL # Number of parallel jobs (default: 4)
```

### Shortcuts

```bash
make recovery-ca    # Create and run recovery/CA
make recovery-bay   # Create and run recovery/Bay
make hosp-ca        # Create and run hosp_interactions/CA
make hosp-bay       # Create and run hosp_interactions/Bay
```

---

## Advanced Topics

### Running on Different Machines

The system automatically adapts to different HPC systems:

**NERSC (Perlmutter)**:
- Auto-detected via `$NERSC_HOST`
- Uses SLURM scheduler
- GPU-aware MPI
- 4 GPUs per node

**LC Systems (Dane, Matrix, Tuolumne)**:
- Auto-detected via `$LCHOST`
- Dane: CPU-based, 100 MPI ranks
- Matrix: GPU-based, 4 GPUs
- Tuolumne: AMD GPU-based, 4 GPUs with Flux scheduler

**Linux Workstation**:
- Specify with `--machine linux` or `--machine linux-gpu`
- Auto-detects MPI launcher (mpirun/mpiexec)
- Configurable resources in `config/machines.yaml`

### Customizing Studies

Edit `config/studies.yaml` to modify:

**Parameter ranges**:
```yaml
parameters:
  med_workers_proportion: [0.03, 0.06, 0.09, 0.12]  # Add 12%
  num_patients_per_doctor: [5, 10, 15, 20, 50, 100] # Add 15
```

**Baseline configuration**:
```yaml
baseline:
  med_workers_proportion: 0.00
  num_patients_per_doctor: 10000000  # Different baseline
```

**Output metrics**:
```yaml
metrics:
  - name: "Custom Metric"
    columns: [1, 2, 3]  # Which columns to sum
    ylabel: "Custom Y-Label"
```

### Batch Processing Multiple Cases

```bash
#!/bin/bash
# run_all_studies.sh

for STUDY in recovery hosp_interactions; do
    for CASE in CA Bay; do
        echo "Running $STUDY/$CASE..."
        make create STUDY=$STUDY CASE=$CASE
        make run STUDY=$STUDY CASE=$CASE
    done
done

# Wait for completion, then plot all
for STUDY in recovery hosp_interactions; do
    for CASE in CA Bay; do
        make plot STUDY=$STUDY CASE=$CASE
    done
done
```

---

## Getting Help

### Command Help

```bash
./sweeps.py --help           # General help
./sweeps.py create --help    # Action-specific help
make help                    # Makefile help
```

### Check Logs

```bash
# Find recent errors
grep -r "ERROR" recovery/.run_*/out.*.log

# Check completion status
grep -r "finalized" recovery/.run_*/out.*.log | wc -l

# View full log
less recovery/.run_recovery.CA.dane.baseline/out.dane.log
```

### Documentation

- `README.md` - Comprehensive documentation
- `config/studies.yaml` - Study definitions and parameters
- `config/machines.yaml` - Machine configurations
- `plot_sweeps.py` - Column definitions and plotting details

---

## Summary

### Quick Workflow

```bash
# 1. Setup
export EXAEPI_BUILD=/path/to/build
export EXAEPI_DIR=/path/to/source
./sweeps.py validate

# 2. Run
make create STUDY=recovery CASE=CA
make run STUDY=recovery CASE=CA

# 3. Results
make status STUDY=recovery CASE=CA
make plot STUDY=recovery CASE=CA

# 4. View
ls -lh recovery/plots/*.png
```

### Key Points

- **Two studies**: recovery (15+1 runs), hosp_interactions (324 runs)
- **Two cases**: CA (California), Bay (Bay Area)
- **Auto-detection**: Machines detected from environment
- **Smart execution**: Skips completed runs automatically
- **Publication quality**: 150 DPI plots with proper legends
- **Easy to use**: Makefile shortcuts for common tasks

For detailed information, see `README.md` or run `./sweeps.py --help`.
