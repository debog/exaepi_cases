# STEPS — running the medical-worker simulations

A concrete runbook. `README.md` explains the design; this lists the order of
operations. Run from `medical_workers/` on an LC platform (examples assume
Matrix). Ensemble size 10 is a starting point — raise it once a configuration
is settled.

## 0. One-time setup

```bash
export EXAEPI_BUILD=/path/to/ExaEpi-build      # contains bin/agent
export EXAEPI_DIR=/path/to/ExaEpi              # source; census + hospital data
export LCHOST=matrix                           # or let it auto-detect on LC
```

- Build ExaEpi on the platform from the latest `dg/medical_workers`. It must
  include the `medical_workers.dat` diagnostic (the H3 calibration depends on
  it).
- Regenerate the decks if you edit the matrix: `./inputs/make_inputs.sh`.
- Sanity check: `./scripts/run_exaepi.sh --list-cases`.

## 1. Verification (the model reduces to the baseline)

```bash
./scripts/run_exaepi.sh --case=bay_verify_off    --mode=batch --ensemble --ensemble-size=10
./scripts/run_exaepi.sh --case=bay_verify_ample  --mode=batch --ensemble --ensemble-size=10
```

- `verify_off` must reproduce a `development` run of the same deck (the gate
  check; the regtests already cover this).
- `verify_ample` mortality must match the baseline — with ample beds, load
  stays below 1, treatment quality stays at 1.

## 2. H1 — viability and capacity → excess mortality (calibrate the score)

```bash
./scripts/run_exaepi.sh --case=bay_H1_capacity --mode=batch --ensemble --ensemble-size=10
```

- **Viability:** confirm peak hospital load exceeds 1 (from the
  `hospital_data_*` plotfiles, component `hospital_load`). If it never does,
  the mechanism never engages — lengthen the run (`agent.nsteps`) or raise
  transmission, then rerun.
- Excess mortality = `H1_capacity` − `verify_ample` (same config, real vs
  ample beds).
- Tune `score_minimum` and `halfscore_load` so in-hospital mortality at peak
  load is ~2× the unstrained baseline. Edit `inputs/make_inputs.sh`, rerun
  `make_inputs.sh`, resubmit. Iterate.

## 3. H3 — in-hospital transmission → workforce depletion (calibrate xmit_hosp)

```bash
./scripts/run_exaepi.sh --case=bay_H3_hcw --mode=batch --ensemble --ensemble-size=10
```

- From `medical_workers.dat`, per day: `MW_*` (medical workers) and `OW_*`
  (other workers), each with total / susceptible / newly-infected.
- HCW hazard ratio over the wave:
  `aHR ≈ mean( (MW_newinf/MW_susc) / (OW_newinf/OW_susc) )`; target ~3.4.
- Tune `disease.xmit_hosp_{d2d,p2d,d2p,p2p}` to hit it (edit `make_inputs.sh`,
  regenerate, rerun). Contrast against `H1_capacity` (channels off) to show the
  depletion feedback.

## 4. H2 — workforce-size sweep

```bash
for c in H2_mw08 H3_hcw H2_mw20; do
    ./scripts/run_exaepi.sh --case=bay_$c --mode=batch --ensemble --ensemble-size=10
done
```

- `H3_hcw` is the central point (proportion 0.13). Report load, overloaded
  communities, and deaths against workforce size.

## 5. Combined (all mechanisms, real placement + routing)

```bash
./scripts/run_exaepi.sh --case=bay_combined --mode=batch --ensemble --ensemble-size=10
```

## Monitor and restart (any time)

```bash
./scripts/monitor.sh                  # live view of all ensembles
./scripts/restart_ensemble.sh         # resubmit any incomplete ensemble
./scripts/restart_ensemble.sh bay_H3  # only matching
```

## Where the outputs are

- Per replicate (`.ensemble_bay_<case>_<platform>/run_NNN/`):
  - `output.dat` — daily disease/hospitalization/death counts.
  - `medical_workers.dat` — daily medical- vs other-worker infection counts.
  - `hospital_data_*` — per-community load, capacity, available workforce
    (series and maps); kept after the ensemble cleanup.
- Per ensemble (the runner averages across replicates):
  `output_*_{mean,std,min,max}.dat` and
  `medical_workers_*_{mean,std,min,max}.dat` (same stats on the HCW counts),
  plus `output_*_summary_{mean,std,min,max}.dat` (derived disease totals).
  For the HCW hazard ratio, compute it per replicate (`run_NNN/`) and average,
  or read it off the mean counts — the two differ slightly.

## Order summary

1. verify_off, verify_ample → check baseline recovery.
2. H1_capacity → check load > 1, calibrate score.
3. H3_hcw → calibrate xmit_hosp from `medical_workers.dat`.
4. H2_mw08 / H3_hcw / H2_mw20 → workforce-size sweep.
5. combined → realistic showcase.
