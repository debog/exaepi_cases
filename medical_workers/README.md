# ExaEpi Medical Workers Parameter Sweep Studies

Streamlined parameter sweep framework for studying medical workers and hospital interactions in epidemic simulations.

## Overview

This directory contains parameter sweep studies investigating the impact of medical workers and hospital-related factors on epidemic dynamics:

1. **recovery**: Medical workers proportion and patients per doctor
2. **hosp_interactions**: Hospital transmission rates and medical workers

## Quick Start

### Prerequisites

1. **Set environment variables:**
   ```bash
   export EXAEPI_BUILD=/path/to/exaepi/build
   export EXAEPI_DIR=/path/to/exaepi/source
   ```

2. **Install Python dependencies:**
   ```bash
   pip install pyyaml matplotlib numpy
   # or
   conda install pyyaml matplotlib numpy
   ```

### Validate Environment

```bash
./sweeps.py validate
# or
make validate
```

### List Available Studies

```bash
./sweeps.py list-studies
```

Output:
```
Available parameter sweep studies:

  recovery
    Name: Medical Workers Recovery Study
    Description: Parameter sweep for medical workers proportion and patients per doctor
    Cases: CA, Bay
    Runs: 15 parameter combinations + 1 baseline

  hosp_interactions
    Name: Hospital Interactions Study
    Description: Parameter sweep for medical workers and hospital transmission rates
    Cases: CA, Bay
    Runs: 324 parameter combinations
```

## Running Parameter Sweeps

### Recovery Study

```bash
# Create run directories
make create STUDY=recovery CASE=CA

# Run parameter sweep (auto-detects machine)
make run STUDY=recovery CASE=CA

# Or specify machine explicitly
make run STUDY=recovery CASE=CA MACHINE=dane

# Check completion status
make status STUDY=recovery CASE=CA
```

### Hospital Interactions Study

```bash
# Create and run
make create STUDY=hosp_interactions CASE=CA
make run STUDY=hosp_interactions CASE=CA

# Limit parallel jobs
make run STUDY=hosp_interactions CASE=CA MAX_PARALLEL=8
```

## Parameter Sweep Configurations

### Recovery Study

**Parameters:**
- Medical workers proportion: 0.03, 0.06, 0.09
- Patients per doctor: 5, 10, 20, 50, 100
- **Total**: 15 combinations + 1 baseline (mwprop=0.00, nppd=5000000)

**Metrics tracked:**
- Infections (sum of infectious compartments)
- Hospitalizations
- Deaths
- Number of overloaded hospitals
- Number of underserved patients

**Cases:** CA (California), Bay (Bay Area)

### Hospital Interactions Study

**Parameters:**
- Medical workers proportion: 0.00, 0.03, 0.06, 0.09
- Hospital transmission rates (4 parameters):
  - Doctor-to-doctor (d2d): 0.000, 0.006, 0.012
  - Doctor-to-patient (d2p): 0.000, 0.005, 0.010
  - Patient-to-doctor (p2d): 0.000, 0.006, 0.012
  - Patient-to-patient (p2p): 0.000, 0.003, 0.006
- **Total**: 324 combinations (4 × 3 × 3 × 3 × 3)

**Metrics tracked:**
- Infections
- Hospitalizations
- Deaths

**Cases:** CA, Bay

## Directory Structure

```
medical_workers/
├── config/
│   ├── studies.yaml        # Study and parameter definitions
│   └── machines.yaml       # Symlink to ../regtests/config/machines.yaml
├── recovery/
│   ├── common/             # Input files and data
│   ├── .run_*              # Generated run directories
│   └── plots/              # Generated plots
├── hosp_interactions/
│   ├── common/             # Input files and data
│   ├── .run_*              # Generated run directories
│   └── plots/              # Generated plots
├── sweeps.py               # Main orchestration tool
├── Makefile                # Convenience wrapper
└── README.md               # This file
```

## Run Directory Naming Convention

Run directories are automatically named based on parameters:

**Recovery study:**
```
.run_recovery.CA.dane.baseline                    # Baseline
.run_recovery.CA.dane.mwprop003.nppd005          # mwprop=0.03, nppd=5
.run_recovery.CA.dane.mwprop006.nppd010          # mwprop=0.06, nppd=10
```

**Hospital interactions study:**
```
.run_hosp_interactions.CA.matrix.mwprop000.xmitd2d000.xmitp2d000.xmitd2p000.xmitp2p000
.run_hosp_interactions.CA.matrix.mwprop003.xmitd2d006.xmitp2d006.xmitd2p005.xmitp2p003
```

## Machine Support

The system supports multiple HPC platforms through shared configuration with regtests:

- **Perlmutter** (NERSC): Auto-detected via `$NERSC_HOST`
- **LC systems** (Dane, Matrix, Tuolumne): Auto-detected via `$LCHOST`
- **Linux workstations**: Specify with `--machine linux` or `--machine linux-gpu`

Machine-specific configurations (nodes, GPUs, MPI settings) are handled automatically.

## Workflow

### 1. Create Run Directories

```bash
./sweeps.py create --study recovery --case CA --machine dane
```

This creates:
- Run directories with parameter combinations
- Symlinks to input files and data
- Machine-specific run scripts

### 2. Run Parameter Sweep

```bash
./sweeps.py run --study recovery --case CA --machine dane --max-parallel 4
```

This:
- Submits jobs (batch mode) or runs in background (interactive)
- Manages parallel execution
- Skips already-completed runs

### 3. Check Status

```bash
./sweeps.py status --study recovery --case CA --machine dane
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

### 4. Generate Plots

```bash
./sweeps.py plot --study recovery --case CA --machine dane
# or
make plot STUDY=recovery CASE=CA MACHINE=dane
```

The plotting system generates:
- **Recovery study**: One plot per medical workers proportion showing:
  - Infections, hospitalizations, deaths over time
  - Overloaded hospitals and underserved patients
  - Baseline vs different patients-per-doctor values
  - Color-coded curves with markers

- **Hospital interactions study**: One plot per medical workers proportion showing:
  - Infections, hospitalizations, deaths
  - Sample of parameter combinations (transmission rates)
  - Multiple curves showing parameter space coverage

Output: `<study>/plots/<study>_<case>_<machine>_mwprop<XX>.png`

## Advanced Usage

### Using sweeps.py Directly

```bash
# Validate environment
./sweeps.py validate

# List available studies
./sweeps.py list-studies

# List available machines
./sweeps.py list-machines

# Create run directories
./sweeps.py create --study recovery --case CA

# Run with specific machine
./sweeps.py run --study hosp_interactions --case Bay --machine perlmutter

# Check status
./sweeps.py status --study recovery --case CA
```

### Makefile Shortcuts

```bash
# Study-specific shortcuts
make recovery-ca      # Create and run recovery/CA
make recovery-bay     # Create and run recovery/Bay
make hosp-ca          # Create and run hosp_interactions/CA
make hosp-bay         # Create and run hosp_interactions/Bay

# Clean up run directories
make clean STUDY=recovery
```

## Configuration Files

### config/studies.yaml

Defines parameter sweep studies:
- Study name and description
- Available cases
- Parameter ranges
- Baseline configuration
- Output metrics to track
- Data files required

### config/machines.yaml

Symlinked from regtests - defines machine configurations:
- Scheduler type (SLURM, Flux, none)
- Resource requirements (nodes, GPUs, MPI tasks)
- MPI launcher and flags
- Environment variables

## Output Files

Each run directory contains:
- `output.dat` - Main simulation output (standard ExaEpi format)
- `num_bad_hospitals.dat` - Hospital overloading data (recovery study only)
- `out.<machine>.log` - Simulation log
- `plt*` - Plot files (if enabled)

## Plotting

The plotting system (`plot_sweeps.py`) generates publication-ready figures:

### Recovery Study Plots

For each medical workers proportion value (3%, 6%, 9%), generates a 5-panel figure:
1. **Infections** - Total infectious individuals over time
2. **Hospitalizations** - Hospital census (non-ICU)
3. **Deaths** - Cumulative deaths
4. **Overloaded Hospitals** - Number of hospitals exceeding capacity (log scale)
5. **Underserved Patients** - Patients not receiving adequate care (log scale)

Each plot shows:
- Baseline (black solid line)
- Parameter sweep results for different patients-per-doctor values
- Color-coded curves with distinct markers
- Legend identifying each parameter combination

### Hospital Interactions Study Plots

For each medical workers proportion value, generates a 3-panel figure:
1. **Infections** - Total infectious individuals
2. **Hospitalizations** - Hospital census
3. **Deaths** - Cumulative deaths

Shows sample of transmission rate parameter combinations (up to 20 curves per plot) with varied colors and line styles.

### Output Format

- **Format**: PNG (configurable to EPS in config/studies.yaml)
- **Resolution**: 150 DPI (publication quality)
- **Location**: `<study>/plots/<study>_<case>_<machine>_mwprop<XX>.png`
- **Naming**: `recovery_CA_dane_mwprop03.png`, `hosp_interactions_Bay_matrix_mwprop06.png`

### Customization

Edit `config/studies.yaml` to customize:
```yaml
plot_config:
  figsize: [14, 10]  # Figure size in inches
  dpi: 150           # Resolution
  xrange: [0, 80]    # X-axis range (days)
  grid: true         # Show grid
  format: png        # Output format (png or eps)
```

## Migration from Old Scripts

### Old workflow (recovery):
```bash
CASE=CA ./scripts/run.sh -m run
```

### New workflow:
```bash
make create STUDY=recovery CASE=CA
make run STUDY=recovery CASE=CA
```

### Benefits:
- Centralized configuration
- Machine auto-detection
- Status tracking
- Automatic cleanup/restart of failed runs
- Python-based plotting
- Consistent interface across studies

## Troubleshooting

### Environment not validated

```bash
# Check environment variables
echo $EXAEPI_BUILD
echo $EXAEPI_DIR

# Verify paths exist
ls $EXAEPI_BUILD/bin/
ls $EXAEPI_DIR/
```

### Machine not auto-detected

```bash
# Check environment
echo $NERSC_HOST  # Should be set on NERSC systems
echo $LCHOST      # Should be set on LC systems

# Or specify explicitly
make run STUDY=recovery CASE=CA MACHINE=dane
```

### Runs not completing

```bash
# Check status
make status STUDY=recovery CASE=CA

# Check logs
tail -f recovery/.run_recovery.CA.dane.baseline/out.dane.log

# Rerun failed cases
make run STUDY=recovery CASE=CA  # Automatically skips completed
```

## Future Enhancements

- [x] Python-based plotting with matplotlib
- [ ] HTML report generation
- [ ] Automated comparison to baselines
- [ ] Parameter sensitivity analysis
- [ ] Batch job submission for SLURM/Flux
- [ ] Statistical analysis and confidence intervals
- [ ] Automated detection of optimal parameter combinations

## See Also

- `config/studies.yaml` - Study definitions
- `../regtests/README.md` - Regression testing framework
- `../regtests/config/machines.yaml` - Machine configurations
