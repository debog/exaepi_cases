# Strong-scaling study (CA and US)

## Last revised
2026-04-29 — initial setup, in response to internal review comment
(Nugent, 2026-04-25, minor issue 13).

## Motivation

The kernel-cost figure in the multi-disease paper (Figure 14) is a
single-GPU measurement on the Bay Area population, but the paper's
scaling claim extends to 32 GPUs (8 nodes) for the US run. The
reviewer asked for a strong- (or weak-) scaling characterization and
for the per-step cost to be split into compute vs. MPI components.

The AMReX TinyProfiler output already classifies kernels by name in
the job's `.out` file at the end of each run; no new instrumentation
is needed. This study runs the same input at varying GPU counts and
parses the profiler output to report compute vs. MPI vs. I/O costs.

## Configurations

50-day simulations (enough for representative TinyProfiler statistics,
short enough to keep compute bounded). Plot output disabled.

| Scenario | Population | GPUs (= MPI ranks) | Nodes (4 GPU/node) |
|----------|-----------:|-------------------:|-------------------:|
| CA 3-disease | 33.9M  | 2, 4, 8, 16        | 1, 1, 2, 4         |
| US 4-disease | 281M   | 32, 64, 128        | 8, 16, 32          |

CA baseline in the paper is 4 GPUs / 1 node; US baseline is 32 GPUs /
8 nodes. The sweeps span 1/2x to 4x the baseline GPU count for each.

Lower-GPU configurations (CA at 1 GPU; US at 8 and 16 GPUs) were
dropped because the per-GPU memory footprint exceeds device limits
and the runs out-of-memory at agent initialization. The corresponding
points were replaced by larger-GPU configurations on the high end.

## Files

- `inputs/inputs_CA_03D_scale` — CA 3-disease, 50 days
- `inputs/inputs_US_04D_scale` — US 4-disease, 50 days
- `run_scaling.sh` — generates one job script per (case, GPUs) and submits
- `monitor_scaling.sh` — watches running scaling jobs for the current platform
- `analyze_scaling.py` — parses TinyProfiler output and classifies kernels

`run_scaling.sh` stages each scaling run in
`.scaling_study/run_<case>_<N>gpu_<platform>/`, copies the input file in,
symlinks the population data files (`CA.dat` etc.), writes a Flux/SLURM
job script, and submits. Walltimes are estimated from the paper's
per-step cost numbers and given a generous buffer.

## Usage

```bash
# Default: submit both CA and US sweeps (8 jobs total)
./run_scaling.sh

# Only CA, dry-run (generate scripts but do not submit)
./run_scaling.sh --scenario=CA --dry-run

# Only US
./run_scaling.sh --scenario=US

# Monitor progress
./monitor_scaling.sh
```

## Analysis

Once jobs complete, parse the TinyProfiler tables in each job's
`scale_*.out`:

```bash
# Tabular summary (auto-detects rundirs in ../.scaling_study/)
./analyze_scaling.py

# Write CSV and a stacked-bar plot
./analyze_scaling.py --csv summary.csv --plot scaling.png
```

The classifier groups kernels by name:

- **compute** — `fastInteract*`, `HospitalModel::interactAgents`,
  `DiseaseStatus::updateAgents`, `AgentContainer::infectAgents`,
  `AgentContainer::interactDay/Night`, `getNewStatusByAge`, `getTotals`,
  `AgentContainer::generateCellData`, `AgentContainer::updateStatus`.
- **mpi** — `amrex::communicateParticles{Start,Finish}`,
  `amrex::unpackRemotes`, `amrex::unpackBuffer`,
  `ParticleCopyPlan::doHandShake`, `ParticleCopyPlan::buildMPI{Start,Finish}`,
  `ParticleCopyPlan::build`, `Redistribute_partition`,
  `ParticleContainer::RedistributeGPU`.
- **io** — `WriteBinaryParticleData`, `WriteMultiLevelPlotfile`,
  `VisMF::Write`, `ParticleContainer::Write{Particles,PlotFile}`.
- **other** — everything else (e.g., `REG::Evolution`,
  `AgentContainer::moveAgents*`, `runAgent`).

The per-kernel exclusive average time (over MPI ranks) sums to the
TinyProfiler total. Strong-scaling efficiency for each category can
be read off the resulting CSV.

## Reference data

For comparison, the paper's existing US 4-disease 730-day run on
32 GPUs (Tuolumne) has the following profiler breakdown:

| Category | Excl. avg time (s) | Fraction |
|----------|-------------------:|---------:|
| compute  | 346                | 22%      |
| MPI      | 535                | 34%      |
| I/O      | 516                | 32%      |
| other    | 196                | 12%      |
| **total**| **1595**           | 100%     |

I/O is large because the production run wrote 74 plotfiles. The
scaling-study runs disable plot output, so I/O drops to negligible
and the compute/MPI split is sharper.
