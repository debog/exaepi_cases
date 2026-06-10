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

### Hospital data: now tract-level (discrete hospitals)

The HHS decks use `BayArea_hospitals_tract_2020.dat` (real hospital tracts +
patient/workforce routing), not the county apportionment. ExaEpi defaults to
tract-level when HHS data is used (commit `fa63f5f`), so **rebuild ExaEpi from the
latest `dg/medical_workers`** first. Three things changed from the county version,
all of which move the load regime:

- **Beds are complete.** The bed file was rebuilt on the 2000-vintage tracts that
  match `BayArea.dat`. All 10,876 staffed beds at 58 hospital tracts now place;
  the old 2020-vintage file lost a third of the beds (7,240 at 39 tracts) to tract
  splits. Capacity is higher than the earlier tract runs, so loads are lower.
- **Patient transfer is on.** A just-admitted patient whose nearest hospital is over
  capacity is sent to the lowest-load hospital in the same county (no transfer in a
  one-hospital county). This shaves the per-hospital peak load -- the worst-hospital
  tail (~45x without transfer) drops once the county's slack is used. Disable with
  `hospital_model.patient_transfer = 0` for the no-transfer comparison. Set
  `hospital_model.transfer_output_file = "transfers.dat"` to log the transfers
  (one line per day per source hospital: `day from_FIPS from_tract to_FIPS to_tract
  n_patients`), for reporting the transfer volume in the paper.
- **Medical workforce is grouped.** Each hospital's staff are split into workgroups
  of ~`workgroup_size` (default 20, set by `agent.workgroup_size` or override with
  `hospital_model.workgroup_size`), instead of one group per hospital. This bounds
  worker-to-worker (`xmit_hosp_d2d`) mixing to realistic team sizes, so it changes
  the H3 HCW hazard ratio for a given `xmit_hosp_d2d`.

### Re-tuning procedure (done -- redo only if the model or region changes)

The mitigation is now **data-anchored, not tuned to a load target.**
`shelter_compliance = 0.50` is the ~50% out-of-home mobility reduction in the Bay
Area after the March 2020 order (Google Community Mobility); the symptomatic-
withdrawal probabilities are the paper's Table 5, anchored to COVID isolation
surveys (~50% default / ~75-92% enhanced cumulative over three days), replacing the
inherited EpiCast/FluTE influenza values. The in-hospital weights remain calibrated
for the current model: `xmit_hosp_d2d = p2d = 0.0075` (HCW cumulative-hazard ratio
~3.4); method in
[calibration/calibrate_mitigation_xmit.md](calibration/calibrate_mitigation_xmit.md).
The peak load is then an **output**, not a target -- a single H1_mitigated
realization gives aggregate ~2.2x, median hospital ~2.3x (busiest ~17x), ~25k
deaths, ~57k patient-transfers. The Bay Area did not in fact overload (it avoided
LA/NY-style collapse through high compliance), so the model's overload is a
counterfactual the capacity response acts on. The score and `xmit_hosp` steps below
are kept for re-tuning after a model or region change; the mitigation is no longer
tuned.

1. **Validate one run.** Run a single `bay_H1_capacity` realization
   (`--mode=batch` without `--ensemble`); locally, 4 MPI ranks on the 9-county Bay
   Area finishes in a few minutes. Confirm it completes and check the init log:
   `58 hospitals`, `patient transfer: on`, `~20 staff` workgroups. In the
   `hospital_data_*` plotfiles, `staffed_bed_supply` sums to 10,876 over 58 cells
   and `baseline_frontline_medworkers` concentrates at the same 58 cells.
2. **Read the peak load with transfer on.** From the `hospital_data_*` plotfiles,
   take `hospital_load` (= `num_patients / patient_capacity`) per hospital at the
   peak step. The relevant numbers are the patient-weighted mean and the worst
   hospital; transfer flattens the spread, so re-read both -- do not reuse the
   pre-transfer 45x tail.
3. **Read the mitigated load (do not tune it).** The shelter (0.50) and withdrawal
   (Table 5) are data-anchored, so the mitigated H1 peak load is reported, not
   driven to a target. Only edit the `MITIGATION` block if the data anchors change.
4. **Re-run the score calibration.** If the admission mix or baseline mortality
   shifts, re-run `calibration/calibrate_treatment_score.py` and update
   `score_minimum` / `halfscore_load`.
5. **Re-tune `xmit_hosp` for H3.** The workgroups change the d2d hazard, so retune
   `disease.xmit_hosp_{d2d,p2d,d2p,p2p}` against the target HCW hazard ratio
   (`aHR ~ 3.4`) from `medical_workers.dat` -- see the H3 section below.
6. **Decide the transfer comparison.** Run H1 with and without
   `hospital_model.patient_transfer` if the paper reports the transfer effect on
   the worst-hospital load; otherwise leave it on. Then run the full ensembles.

## 1. Verification (the model reduces to the baseline)

```bash
./scripts/run_exaepi.sh --case=bay_verify_off       --mode=batch --ensemble --ensemble-size=25
./scripts/run_exaepi.sh --case=bay_verify_ample     --mode=batch --ensemble --ensemble-size=25
./scripts/run_exaepi.sh --case=bay_verify_ample_mit --mode=batch --ensemble --ensemble-size=25
./scripts/run_exaepi.sh --case=bay_verify_match     --mode=batch --ensemble --ensemble-size=25
```

- `verify_off` must reproduce a `development` run of the same deck (the gate
  check; the regtests already cover this).
- `verify_ample` mortality must match the baseline — with ample beds, load
  stays below 1, treatment quality stays at 1. Its epidemic is slightly smaller
  than the baseline because medical workers leave the workplace mixing pool.
- `verify_ample_mit` is the no-strain reference for the *mitigated* capacity run
  (`H1_mitigated`): ample beds + the same mitigation, so its epidemic matches
  the mitigated one but with the score pinned at 1. The mitigated strain
  multiplier is `H1_mitigated` / `verify_ample_mit`. Fetch its summaries into
  `draft/figures/data/` as `verify_ample_mit_{mean,std}.dat`.
- `verify_match` is the control for that confound: ample beds, doctor-to-doctor
  transmission at the workplace rate, no patient channels. It should reproduce
  the baseline, proving the `verify_ample` gap is the reduced medical-worker
  transmission. Fetch its summaries into `draft/figures/data/` as
  `verify_match_{mean,std}.dat`; `plot_verification.py` then adds its curve.

## 2. H1 — viability and capacity → excess mortality (calibrate the score)

```bash
./scripts/run_exaepi.sh --case=bay_H1_capacity --mode=batch --ensemble --ensemble-size=25
```

- **Viability:** confirm peak hospital load exceeds 1 (from the
  `hospital_data_*` plotfiles, component `hospital_load`). An *unmitigated*
  Bay Area run overshoots badly — peak load ~25× the ~10.9k real beds, giving a
  ~12× mortality multiplier. Use `bay_H1_mitigated` for a realistic surge:

  ```bash
  ./scripts/run_exaepi.sh --case=bay_H1_mitigated --mode=batch --ensemble --ensemble-size=25
  ```

  It adds the data-anchored shelter window (0.50) and enhanced symptomatic
  withdrawal (Table 5). The resulting peak load (single realization: aggregate
  ~2.2×, median hospital ~2.3×, busiest ~17×) is read off the `hospital_data_*`
  plotfiles, not tuned to a target -- the mitigation is fixed by the data.
- Excess mortality = `H1_*` − the matching ample-bed baseline (same config and
  mitigation, real vs ample beds).
- **Patient-transfer effect.** `bay_H1_mitigated` has transfer on (the default)
  and logs the moves to `transfers.dat`. `bay_H1_mitigated_notransfer` is the same
  run with transfer off:

  ```bash
  ./scripts/run_exaepi.sh --case=bay_H1_mitigated_notransfer --mode=batch --ensemble --ensemble-size=25
  ```

  The pair isolates the transfer effect: compare the per-hospital load (worst
  hospital, overloaded count, from the `hospital_data_*` `hospital_load`) and the
  deaths, on vs off. `transfers.dat` gives the transfer volume (day, from/to
  hospital tract, patients).
- Tune `score_minimum` and `halfscore_load` so in-hospital mortality at peak
  load is ~2× the unstrained baseline. Edit `inputs/make_inputs.sh`, rerun
  `make_inputs.sh`, resubmit. Iterate.

## 3. H3 — in-hospital transmission → workforce depletion (calibrate xmit_hosp)

```bash
./scripts/run_exaepi.sh --case=bay_H3_hcw --mode=batch --ensemble --ensemble-size=25
```

- From `medical_workers.dat`, per day: `MW_*` (medical workers) and `OW_*`
  (other workers), each with total / susceptible / newly-infected.
- HCW hazard ratio over the wave:
  `aHR ≈ mean( (MW_newinf/MW_susc) / (OW_newinf/OW_susc) )`; target ~3.4.
- Tune `disease.xmit_hosp_{d2d,p2d,d2p,p2p}` to hit it (edit `make_inputs.sh`,
  regenerate, rerun). Contrast against `H1_capacity` (channels off) to show the
  depletion feedback.

## 4. H2 — workforce-size sweep

Non-HHS (per-community) bed model so the staffed-bed supply scales with the
medical-worker fraction (2.4 × frac/0.13 beds per 1000), making capacity
proportional to the workforce. In-hospital transmission is off, so the workforce
acts only through capacity (the H3 depletion feedback is isolated out).

```bash
for c in H2_mw08 H2_mw13 H2_mw20; do
    ./scripts/run_exaepi.sh --case=bay_$c --mode=batch --ensemble --ensemble-size=25
done
```

- `H2_mw13` is the central point (proportion 0.13). Report load, overloaded
  communities, and deaths against workforce size.
- Single-realization local check (seed 1, transmission off): deaths 65,137 (8%) →
  34,736 (13%) → 18,046 (20%) — capacity only, a ~72% drop across the sweep. With
  transmission on the same trend runs ~5-10% higher (68,298 / 38,677 / 20,131).

## 5. Combined (all mechanisms, real placement + routing)

```bash
./scripts/run_exaepi.sh --case=bay_combined --mode=batch --ensemble --ensemble-size=25
```

## 6. Nosocomial (in-hospital cross-disease transmission)

Two co-circulating diseases are needed for the patient-coupled channels (`d2p`,
`p2p`) to act: a patient admitted for one disease can acquire the other in the
hospital. With a single disease these channels are inert. The scenario is
COVID-19 + influenza, run with the patient channels on (`w_noso`) and off
(`wo_noso`):

```bash
for c in covflu_w_noso covflu_wo_noso; do
    ./scripts/run_exaepi.sh --case=bay_$c --mode=batch --ensemble --ensemble-size=25
done
```

This is an artificial stress test, not a calibrated forecast -- read the
disclaimers in the paper's Section 4.6. Both diseases circulate together at full
strength with no cross-immunity and no vaccination; symptomatic withdrawal is one
shared agent-level flag (a flu symptom withdraws the agent from COVID exposure
too); the cosusceptibility coefficient is pinned at the formula floor `c_S = 1.0`
(neutral) because the multidisease infection-probability formula cannot represent
protective coupling `c_S < 1` (ExaEpi issue #153); and the co-circulating epidemic
runs the hospitals at roughly double the single-COVID peak load, so wards saturate
and a patient acquires the second disease almost regardless of the patient
channels.

- `w_noso` turns on all four in-hospital channels; `wo_noso` keeps the worker
  channels (`p2d`, `d2d`) but turns the patient-coupled channels off. Influenza CHR
  is the CDC-derived value (`disease_FluS1.CHR`); both runs use the same data-
  anchored mitigation.
- The diagnostic is the per-disease `hospital_acquired` plotfile field (cumulative
  nosocomial infections deposited at the hospital cell; needs the latest
  `dg/medical_workers` binary, which also carries the OOB and dual-hospitalization
  fixes the multi-disease hospital runs require). Net nosocomial = `w_noso` −
  `wo_noso` (the small `wo_noso` residual is community infection on the admission
  day); the mortality increment is the death difference `w_noso` − `wo_noso`.
- Single-realization check (data-anchored mitigation, `c_S = 1.0`, CDC flu CHR):
  deaths 89,717 (`w_noso`) vs 88,761 (`wo_noso`), +956 (+1.08%); nosocomial
  18,589 COVID + 68,281 flu. Patient cross-infection is a minor mortality channel
  next to the H3 worker depletion. The peak load is aggregate ~5.2x, median
  hospital ~5.7x, busiest ~28x -- the saturated regime that makes the channel
  comparison a near-upper-bound, not a typical value.

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
  - `plt?????` — full plotfiles (per-cell `total` agent count etc.); deleted
    after each run to save space, **except for `run_001`**, which is kept for
    the per-tract maps (excess mortality and infections need one representative
    realization). Fetch `run_001/plt00000` and a resolved late plotfile.
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
4. H2_mw08 / H2_mw13 / H2_mw20 → workforce-size sweep.
5. combined → realistic showcase.
6. covflu_{w,wo}_noso → in-hospital cross-disease (nosocomial) transmission.
