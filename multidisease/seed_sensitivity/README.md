# Seed-sensitivity sweep

## Last revised
2026-04-29 — initial setup, in response to internal review comment
(Nugent, 2026-04-25, major issue 10).

## Motivation

The two-disease Cov19-S1 + Cov19-S2 scenario in the multi-disease
paper uses asymmetric initial seed counts in each geography
(Bay Area: Cov19-S1 = 20, Cov19-S2 = 5; California: 100/25;
US: 1000/250). The internal review flagged this within-scenario
4× asymmetry as a possible confound for cross-disease peak-timing
and peak-magnitude comparisons in §4.3 of the paper.

The paper currently argues that the dominant driver of early-wave
dynamics is `R_0`, not seed count, since the early growth phase is
exponential. The seed counts only set a small time-zero offset.
This sweep tests that argument quantitatively on the smallest
geography (Bay Area), where stochastic-extinction risk is highest
and the sensitivity to seed count should be largest.

## Cases

All cases use the Bay Area population (~6.78M agents) on 1 GPU,
730 simulated days, full coupling (cross-immunity 0.85, neutral
co-susceptibility), and 100 ensemble realizations by default.

| Case          | Cov19-S1 seed | Cov19-S2 seed | Ratio | Notes                                |
|---------------|---------------|---------------|-------|--------------------------------------|
| `seed_equal`  | 20            | 20            | 1.0×  | Equal seeds. Eliminates asymmetry.   |
| `seed_half`   | 10            | 3             | ~3.3× | Baseline halved, ratio approx kept.  |
| `seed_double` | 40            | 10            | 4.0×  | Baseline doubled, ratio kept.        |

The paper baseline (Cov19-S1 = 20, Cov19-S2 = 5; ratio 4×)
already exists in `.ensemble_*` directories from the main run and
serves as the reference.

## Files

- `inputs/inputs_bay_02D_Cov19S1S2_seed_equal`
- `inputs/inputs_bay_02D_Cov19S1S2_seed_half`
- `inputs/inputs_bay_02D_Cov19S1S2_seed_double`
- `run_seed_sensitivity.sh` — submits all three cases as ensembles
- `monitor_seed_sensitivity.sh` — watches running ensembles for the current platform

The runner symlinks the input files into the main `inputs/`
directory (matching `sensitivity/run_sensitivity.sh`'s convention)
and creates ensemble run directories under `.seed_sensitivity/`
in the project root.

## Usage

```bash
# Default: 100-realization ensembles, 730 days, batch submission
./run_seed_sensitivity.sh

# Quick smoke test: small ensembles, short runs, dry-run
./run_seed_sensitivity.sh --ensemble-size=10 --max-step=200 --dry-run

# Verbose
./run_seed_sensitivity.sh --verbose
```

## Monitoring

```bash
# Watch ensembles in .seed_sensitivity/ for the current platform.
# Refreshes every 2 minutes; Ctrl+C to exit.
./monitor_seed_sensitivity.sh
```

Per-case states: `✓ Completed` (output statistics present), or
in-progress with the SLURM status (read from `job_id.txt`) and the
last 3 `Run` lines from the ensemble `.out` file.

## Analysis

Once the ensembles complete, compare the ensemble-mean Cov19-S1
and Cov19-S2 trajectories across the four datasets (paper
baseline, `seed_equal`, `seed_half`, `seed_double`). The relevant
metrics are:

- Peak timing of each disease (day of maximum active infections)
- Peak magnitude of each disease
- Cumulative deaths over the 730-day window

If the within-scenario seed asymmetry materially changes the
Cov19-S2 dominance, the `seed_equal` case will show a
qualitatively different early outbreak from the paper baseline.
The argument made in the paper predicts only a small shift.
