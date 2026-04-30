# Joint cross-immunity x co-susceptibility sweep

## Last revised
2026-04-29 — initial setup, in response to internal review comment
(Nugent, 2026-04-25, minor issue 12).

## Motivation

The two one-at-a-time sensitivity sweeps in `sensitivity/` vary
cross-immunity (between Cov19-S1 and Cov19-S2) and co-susceptibility
(between Cov19-S1 and Flu-S1) independently. The reviewer flagged that
interactions between the two coupling mechanisms could be nontrivial
and asked for a 3x3 joint sweep.

## Scenario

3-disease California simulation (Cov19-S1, Cov19-S2, Flu-S1) on
33.9M agents using 4 GPUs / 1 node, 730 simulated days, 100 ensemble
realizations per case.

## Cases

| Cross-imm (Cov-Cov) | Co-sus (Cov-Flu) | Case name                                         |
|---------------------|------------------|---------------------------------------------------|
| 0.50                | 1.00             | `CA_03D_Cov19S1S2_FluS1_coimm050_cosus100`        |
| 0.50                | 1.50             | `CA_03D_Cov19S1S2_FluS1_coimm050_cosus150`        |
| 0.50                | 3.00             | `CA_03D_Cov19S1S2_FluS1_coimm050_cosus300`        |
| 0.85 (baseline)     | 1.00             | `CA_03D_Cov19S1S2_FluS1_coimm085_cosus100`        |
| 0.85 (baseline)     | 1.50 (baseline)  | `CA_03D_Cov19S1S2_FluS1_coimm085_cosus150`        |
| 0.85 (baseline)     | 3.00             | `CA_03D_Cov19S1S2_FluS1_coimm085_cosus300`        |
| 1.00                | 1.00             | `CA_03D_Cov19S1S2_FluS1_coimm100_cosus100`        |
| 1.00                | 1.50             | `CA_03D_Cov19S1S2_FluS1_coimm100_cosus150`        |
| 1.00                | 3.00             | `CA_03D_Cov19S1S2_FluS1_coimm100_cosus300`        |

The cross-immunity values match those used in the existing
co-immunity sweep in `sensitivity/` (low/baseline/high subset). The
co-susceptibility values match those used in the existing
co-susceptibility sweep (low-neutral/baseline/high).

## Files

- `inputs/inputs_CA_03D_Cov19S1S2_FluS1_coimm<XXX>_cosus<XXX>` — 9 input files
- `run_joint_sensitivity.sh` — submits all 9 cases as ensembles
- `monitor_joint_sensitivity.sh` — watches running ensembles for the current platform

The runner symlinks the input files into the main `inputs/` directory and
creates ensemble run directories under `.joint_sensitivity/` in the project root.

## Usage

```bash
# Default: 100-realization ensembles, 730 days, batch submission
./run_joint_sensitivity.sh

# Quick smoke test: small ensembles, dry-run
./run_joint_sensitivity.sh --ensemble-size=10 --max-step=200 --dry-run

# Monitor:
./monitor_joint_sensitivity.sh
```

## Analysis

Once ensembles complete, compare ensemble-mean trajectories across
the 9 cases. Key metrics:

- Cov19-S1 peak magnitude and timing as a function of (cross-imm, co-sus)
- Cov19-S2 peak magnitude and timing
- Flu-S1 peak magnitude and timing (the main amplification signal)
- Cumulative deaths over 730 days

A 3x3 contour or heatmap plot of each metric shows whether the
two coupling mechanisms interact, or whether their effects are
approximately additive.
