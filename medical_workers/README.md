# Medical-worker / hospital-capacity experiments

Run setups for the ExaEpi medical-worker paper. Each deck isolates one
mechanism of the hospital-capacity model; a final deck combines them. The
structure mirrors `../multidisease`: a generic runner copies data and
submits jobs, run/ensemble directories are `.run_*/` and `.ensemble_*/`
(git-ignored).

**[STEPS.md](STEPS.md)** is the step-by-step runbook (what to run, in what
order). This README covers the design and the experiment matrix.

## Prerequisites

- `EXAEPI_BUILD` — ExaEpi build directory (contains `bin/agent`).
- `EXAEPI_DIR` — ExaEpi source; census and hospital data are found here
  (`data/CensusData/`, `data/HospitalData/`). Not duplicated in this tree.
- `LCHOST` — platform (`matrix`, `dane`, `tuolumne`, ...); auto-detected on LC.
- The implementation is gated by `agent.model_medical_workers` (default
  `false`). With it off, a run reproduces `development` exactly.

## Experiment matrix

All decks are Bay Area, census init, up to one year (nsteps 365). Most use a single COVID-19
strain; the two `md_*` decks add co-circulating influenza. They are generated
by `inputs/make_inputs.sh` (edit it to change the matrix). Each deck = a shared
disease base + a medical-worker block.

| Deck (`inputs_bay_*`) | Purpose | Model | Beds | In-hospital transmission |
|---|---|---|---|---|
| `verify_off` | Baseline; must match `development` | off | — | — |
| `verify_ample` | Model on, no strain → recovers baseline mortality | on | ample (per-capita ×100) | off |
| `verify_match` | Control: matched transmission → should match baseline | on | ample (per-capita ×100) | d2d=work, rest off |
| `H1_capacity` | **H1**: load → excess mortality, workforce ~fixed (unmitigated) | on | real, tract | off |
| `H1_mitigated` | **H1**: realistic surge (mitigation); transfer on, logs transfers | on | real, tract | off |
| `H1_mitigated_notransfer` | **H1**: same with patient transfer off (transfer comparison) | on | real, tract | off |
| `H3_hcw` | **H3**: in-hospital transmission → workforce depletion | on | real, tract | on |
| `H2_mw08` | **H2**: small workforce (8%), bed supply scaled down | on | fallback, beds∝workforce | off |
| `H2_mw13` | **H2**: reference workforce (13%) | on | fallback, beds∝workforce | off |
| `H2_mw20` | **H2**: large workforce (20%), bed supply scaled up | on | fallback, beds∝workforce | off |
| `combined` | All mechanisms, real hospital placement + routing | on | real, **tract** | on |
| `covflu_w_noso` | **Nosocomial** (COVID+flu): all in-hospital channels | on | real, tract | on (all 4) |
| `covflu_wo_noso` | COVID+flu, patient channels off | on | real, tract | worker only |
| `cov2_w_noso` | **Nosocomial** (2 COVID strains, wild-type+Delta): all channels | on | real, tract | on (all 4) |
| `cov2_wo_noso` | 2 COVID strains, patient channels off | on | real, tract | worker only |

H2 uses the per-community (fallback) bed model so the staffed-bed supply scales
with the medical-worker fraction (2.4 × frac/0.13 beds per 1000 residents),
making capacity proportional to the workforce; the central point is `H2_mw13`.
In-hospital transmission is off in H2, so the workforce acts only through capacity
(the H3 depletion feedback is isolated out). Hospital
plotfiles (`write_pltfiles = true`, named `hospital_data_*`) give per-community
time series and maps of load, capacity, and available workforce; the ensemble
cleanup removes the agent `plt*` but keeps these.

## Comparisons (counterfactuals)

Each effect is a difference between two runs that share everything but one
feature, so the mechanism is isolated:

- **Reproduces `development`:** `verify_off` vs a `development` run of the same
  deck (the gate check; the regtests already cover this).
- **No-strain limit:** `verify_ample` — model on but beds ample, so treatment
  quality stays 1 and mortality matches the baseline (its epidemic is slightly
  smaller, as medical workers leave the workplace mixing pool).
- **Matched control:** `verify_match` — like `verify_ample` but doctor-to-doctor
  transmission at the workplace rate restores medical-worker mixing; it should
  reproduce `verify_off`, so `verify_off` − `verify_ample` is provably the
  reduced medical-worker transmission.
- **H1 (excess mortality from capacity):** `H1_capacity` − `verify_ample`
  (unmitigated) and `H1_mitigated` − `verify_ample_mit` (realistic surge); the
  only difference in each pair is real vs ample beds.
- **Patient transfer:** `H1_mitigated` − `H1_mitigated_notransfer` — same surge,
  transfer on vs off; isolates the same-county transfer effect.
- **H3 (workforce-depletion feedback):** `H3_hcw` − `H1_mitigated` (both
  mitigated); the only difference is the in-hospital transmission channels.
- **H2 (workforce size):** `H2_mw08` / `H2_mw13` / `H2_mw20` — sweep of
  `med_workers_proportion` with the bed supply scaled to match (fallback option),
  in-hospital transmission off so the workforce acts only through capacity.
- **Nosocomial co-infection:** `covflu_{w,wo}_noso` and `cov2_{w,wo}_noso` (two
  scenarios: COVID+flu, and two COVID strains, wild-type+Delta). `w_noso` −
  `wo_noso` isolates the patient-coupled in-hospital channels (`d2p`, `p2p`): the
  second-disease infections acquired in the hospital (the `hospital_acquired`
  diagnostic) and their excess mortality.

## Calibration

Capacity magnitude is pinned by the real HHS bed data. The score model is set in
closed form by `../../2026_MedicalWorkers/calibration/`; the mitigation and the
in-hospital weights are set empirically with local 4-rank runs, documented in
[calibration/calibrate_mitigation_xmit.md](calibration/calibrate_mitigation_xmit.md)
(current values: `shelter_compliance = 0.50` data-anchored, `xmit_hosp_d2d = p2d = 0.0075`):

- `score_minimum = 0.1`, `halfscore_load = 3.13` — from **H1**: in-hospital
  mortality ~2× the unstrained baseline at a 2.5× peak load (the score model's
  dose-response, independent of the mitigation).
- `shelter_compliance = 0.50` and the symptomatic-withdrawal probabilities —
  **data-anchored** (Bay Area mobility and COVID isolation surveys), not tuned to a
  load target; the mitigated peak load is then an output (~2.2× aggregate).
- `disease.xmit_hosp_{d2d,p2d}` — from **H3**: tune to the HCW hazard target
  (cumulative-hazard ratio ~3.4). The metric is robust to closed-population
  saturation; the raw attack-rate ratio is not.
- `agent.med_workers_proportion` — pinned at ~0.13 (NAICS 62); H2 characterizes
  the sensitivity to it.

**Viability check first.** Confirm the disease drives peak load above 1
against the real beds (`H1_capacity`), else the capacity mechanism never
engages. If it does not, lengthen the run, raise transmission, or pick a more
severe region.

## Running

From this directory:

```bash
# list cases / platforms
./scripts/run_exaepi.sh --list-cases
./scripts/run_exaepi.sh --list-platforms

# single run (batch), e.g. the H1 calibration run
./scripts/run_exaepi.sh --case=bay_H1_capacity --mode=batch

# ensemble of replicates (different seeds), e.g. 10 for H3
./scripts/run_exaepi.sh --case=bay_H3_hcw --mode=batch --ensemble --ensemble-size=25

# all cases as ensembles
for c in verify_off verify_ample H1_capacity H3_hcw H2_mw08 H2_mw13 H2_mw20 combined covflu_w_noso covflu_wo_noso cov2_w_noso cov2_wo_noso; do
    ./scripts/run_exaepi.sh --case=bay_$c --mode=batch --ensemble --ensemble-size=25
done

# dry run to inspect commands without submitting
./scripts/run_exaepi.sh --case=bay_combined --mode=batch --ensemble --dry-run
```

Run directories: `.run_bay_<case>_<platform>/` (single) and
`.ensemble_bay_<case>_<platform>/` (ensembles, with `run_001/ ...`).

## Monitoring and restarting

```bash
./scripts/monitor.sh              # live view of all ensembles
./scripts/monitor.sh bay_H1       # only matching ensembles

./scripts/restart_ensemble.sh           # resubmit any incomplete ensemble
./scripts/restart_ensemble.sh bay_H3    # only matching
./scripts/restart_ensemble.sh --force   # resubmit even if a job looks active
```

The ensemble job skips finished replicates and re-runs incomplete ones, so a
restart is just a resubmit. Both scripts work on Slurm (Matrix, Dane) and Flux
(Tuolumne) — the job-state check (`scripts/job_lib.sh`) falls back from
`squeue` to `flux jobs`. When the scheduler cannot be queried,
`restart_ensemble.sh` errs on the safe side and skips; resubmit with `--force`.

## Diagnostics

The per-day medical-worker vs other-worker counts that the `xmit_hosp_*`
calibration (H3) needs are written to `medical_workers.dat` (one file per disease
for the `md_*` decks) whenever the model is on: totals, susceptible, newly
infected, and cumulative deaths (`MW_dead`/`OW_dead`) for each group. The ensemble
step averages these alongside `output.dat`. Per-community grid fields
(`hospital_data_*`) and the per-agent treatment quality are written when
`hospital_model.write_pltfiles` is set. Setting
`hospital_model.transfer_output_file` logs each day's patient transfers (day,
from/to hospital FIPS+tract, count).
