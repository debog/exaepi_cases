# STEPS — running the medical-worker simulations

A concrete runbook. `README.md` explains the design; this lists the order of
operations. Run from `medical_workers/` on an LC platform (examples assume
Matrix). The paper ensembles have 25 members each.

## 0. One-time setup

```bash
export EXAEPI_BUILD=/path/to/ExaEpi-build      # contains bin/agent
export EXAEPI_DIR=/path/to/ExaEpi              # source; census + hospital data
export LCHOST=matrix                           # or let it auto-detect on LC
```

- Build ExaEpi on the platform. The submitted paper used `fe7ebfa` (every paper
  ensemble logs it); the revision uses `archive/2026_medworkers_paper` (`ba03243`:
  `fe7ebfa` + the `development` merge + the issue #159 discharge fix). Pin AMReX to
  `9ed35ab0e584`, the version every paper ensemble logs: `-DAMReX_GIT_BRANCH=9ed35ab0e584`
  for a fresh build dir, or `-DFETCHCONTENT_UPDATES_DISCONNECTED_AMREX=ON` in an
  existing one already at that commit (the LC builds, 2026-10-16). `ba03243`
  reproduces the shelter-free paper runs bitwise; shelter-on runs diverge from
  day 42 (RNG stream shift; README, reproduction check). The build must
  include the `medical_workers.dat` diagnostic (the H3 calibration depends on it).
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
for the current model: `xmit_hosp_d2d = p2d = 0.0002` (end-of-wave HCW
cumulative-hazard ratio 3.07 in the Matrix ensemble; target 3.4); method in
[calibration/calibrate_mitigation_xmit.md](calibration/calibrate_mitigation_xmit.md).
The peak load is then an **output**, not a target -- the Matrix H1_mitigated
ensemble peaks at 1.6x aggregate (day 73) with 12,081 deaths; in `run_001` at day 75
the median hospital is at 1.6x and the busiest at 9.7x, and 48,925 patients are
transferred over the wave. The Bay Area did not in fact overload (it avoided
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
4. **The load-to-mortality map is data-anchored analytically** -- `mortality_multiplier_max`=3
   (ceiling) and `halfscore_load`=1.5 (M(2.5)=2x). The multiplier is risk-independent, so it
   does not depend on the admission mix or baseline mortality; no calibration run is needed
   (`calibration/calibrate_treatment_score.py` is superseded).
5. **Re-tune `xmit_hosp` for H3.** The workgroups change the d2d hazard, so retune
   `disease.xmit_hosp_{d2d,p2d,d2p,p2p}` against the target HCW hazard ratio
   (CHR ~3.4) from `medical_workers.dat` -- see the H3 section below.
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
  Bay Area run overshoots badly — peak load 6.8× the 10,876 real beds (ensemble
  mean, day 64), where the mortality multiplier is at its ceiling `M_max`=3×. Use `bay_H1_mitigated` for a realistic surge:

  ```bash
  ./scripts/run_exaepi.sh --case=bay_H1_mitigated --mode=batch --ensemble --ensemble-size=25
  ```

  It adds the data-anchored shelter window (0.50) and enhanced symptomatic
  withdrawal (Table 5). The resulting peak load (Matrix ensemble: aggregate 1.6×;
  `run_001` day 75: median hospital 1.6×, busiest 9.7×) is read off the
  `hospital_data_*` plotfiles, not tuned to a target -- the mitigation is fixed by
  the data.
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
- The load-to-mortality map is data-anchored analytically: `mortality_multiplier_max`=3
  (the ~2–3× ceiling at overwhelmed systems) and `halfscore_load`=1.5 (so the multiplier
  is 2× at a 2.5× peak load). The multiplier is risk-independent, so no tuning run is
  needed; `score_minimum` is dropped (set to 0 -- vestigial under the multiplicative form).

## 3. H3 — in-hospital transmission → workforce depletion (calibrate xmit_hosp)

```bash
./scripts/run_exaepi.sh --case=bay_H3_hcw --mode=batch --ensemble --ensemble-size=25
```

- From `medical_workers.dat`, per day: `MW_*` (medical workers) and `OW_*`
  (other workers), each with total / susceptible / newly-infected.
- HCW risk = end-of-wave cumulative-hazard ratio,
  `CHR = ln(MW_susc[0]/MW_susc[end]) / ln(OW_susc[0]/OW_susc[end])`; target ~3.4
  (Nguyen 2020). Unlike the attack-rate ratio it does not collapse when both groups
  saturate: in the Matrix `H3_hcw` mean it is ~2.9 from 5% to 50% cumulative
  incidence in other workers and 3.07 at the end of the wave.
- Tune `disease.xmit_hosp_{d2d,p2d}` to hit it (edit `make_inputs.sh`, regenerate,
  rerun). Contrast against `H1_mitigated` (no in-hospital transmission, CHR 1.10) to
  show the depletion feedback.

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
- Matrix ensemble: deaths 15,571 (8%) → 11,358 (13%) → 9,013 (20%), a 42% drop;
  peak aggregate load 1.65× → 0.98× → 0.60× (`run_001`, sum of patients over sum
  of capacity). The earlier single-realization local check (65,137 / 34,736 /
  18,046) predates the data-anchored mitigation.

## 5. Nosocomial (in-hospital cross-disease transmission)

Two co-circulating diseases are needed for the patient-receiving channels (`d2p`,
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
disclaimers in the paper's Section 5.6. Both diseases circulate together at full
strength with no cross-immunity and no vaccination; symptomatic withdrawal is one
shared agent-level flag (a flu symptom withdraws the agent from COVID exposure
too); the cosusceptibility coefficient is pinned at the formula floor `c_S = 1.0`
(neutral) because the multidisease infection-probability formula cannot represent
protective coupling `c_S < 1` (ExaEpi issue #153); and the co-circulating epidemic
peaks at 1.7× capacity (ensemble mean), against 1.6× for COVID alone.

- `w_noso` turns on all four in-hospital channels; `wo_noso` keeps the worker
  channels (`p2d`, `d2d`) but turns the patient-receiving channels off. Influenza CHR
  is the CDC-derived value (`disease_FluS1.CHR`); both runs use the same data-
  anchored mitigation.
- The diagnostic is the per-disease `hospital_acquired` plotfile field (cumulative
  nosocomial infections deposited at the hospital cell; needs the latest
  `dg/medical_workers` binary, which also carries the OOB and dual-hospitalization
  fixes the multi-disease hospital runs require). Net nosocomial = `w_noso` −
  `wo_noso` (the small `wo_noso` residual comes from household contact, which
  hospitalized agents keep); the mortality increment is the death difference
  `w_noso` − `wo_noso`.
- Do not use the summed `NewH` of the two `output_*.dat` as the admissions
  denominator. In a two-disease run, `NewH` for disease d also counts, on every day of
  the stay, hospitalized agents never infected with d: their per-disease counters are
  all zero, so `isNewlyHospitalized` matches 0 == 0 + 0. `run_001` sums to 514,151
  "admissions" (361,332 of them flu). Estimate admissions instead as
  Σ_age(new symptomatic `Symp*` × `CHR`) per disease (matches `NewH` within 2% in
  single-disease runs); see `calibration/calibrate_mitigation_xmit.md`.
- Per-route rates, Matrix `run_001`: ~10.7% of all admissions acquire the second
  disease; ~23% of flu admissions acquire COVID; ~8% of COVID admissions acquire flu.
- Matrix results: `run_001` hospital-acquired 5,079 COVID + 7,947 flu with the patient
  channels, 20 + 26 without; ensemble deaths 14,426 (σ 1,118) vs 14,254 (σ 1,166).
  The 172-death difference is well inside the ensemble spread.

## 6. Sensitivity and robustness (Section 6.1)

The parameters that are NOT fixed by data are the overload mortality ceiling `M_max`
and the half-score load `L_1/2` (pinned by the M(2.5)~=2x target), and the HCW
hazard-ratio target behind `xmit_hosp`. `med_workers_proportion` is data-anchored
(its effect is H2).

**S1 — load-to-mortality map (`M_max`, `L_1/2`).** These enter only the closed-form
mortality map, not the load trajectory, so re-score the saved H1/H3 runs without
re-running:

```bash
python3 scripts/rescore_sensitivity.py \
    /path/.ensemble_bay_H1_capacity_<platform>             # M_max x L_1/2 grid
python3 scripts/rescore_sensitivity.py \
    /path/.ensemble_bay_H1_mitigated_<platform> --target   # M_max x M(2.5) target
```

The re-scoring is validated at high uniform load but UNDERESTIMATES the
spatially-concentrated mitigated case, since the strain sits in the hardest-hit
hospitals. So anchor the mitigated
operating point with full re-runs at the corners:

```bash
for c in S1_mmax2 S1_mmax4 S1_lhalf10 S1_lhalf25; do
    ./scripts/run_exaepi.sh --case=bay_$c --mode=batch --ensemble --ensemble-size=25
done
```

Report the H1 multiplier over the grid; state which qualitative conclusion holds
(strain multiplies mortality) and that the magnitude is the calibration-sensitive part.

**S2 — in-hospital transmissivity (HCW hazard).** Bracket the calibrated H3
(`H3_hcw`, CHR 3.07) by scaling `xmit_hosp` down (`lo`) and up (`hi`):

```bash
for c in S2_hcw_lo S2_hcw_hi; do
    ./scripts/run_exaepi.sh --case=bay_$c --mode=batch --ensemble --ensemble-size=25
done
```

Read the achieved CHR from `medical_workers.dat` (H3 formula above) and report the
depletion mortality amplification against it. The Matrix ensembles give CHR 2.55
(`lo`) and 3.86 (`hi`).

## 7. Computational cost (Section 6.2)

Per-step overhead of the model vs baseline, plotfiles off, 120 steps, on Matrix
H100s. Time off / capacity-only / full on the same Bay Area scenario, as 25-member
ensembles at 1-4 MPI tasks (one GPU each); the paper reports the single-GPU
ensemble medians:

```bash
for n in 1 2 3 4; do
    for c in cost_off cost_on cost_on_full; do
        ./scripts/run_exaepi.sh --case=bay_$c --mode=batch --ensemble --ensemble-size=25 --ntasks=$n
    done
done
```

The run directories carry the task count (`.ensemble_bay_cost_on_matrix_n1`, ...).

- `cost_on` − `cost_off`: the capacity-model overhead (identical dynamics).
- `cost_on_full` − `cost_on`: the in-hospital-interaction cost.
- Break the overhead down by routine from the AMReX TinyProfiler table. **This needs a
  TinyProfiler build**: the default hardcodes `set(AMReX_TINY_PROFILE OFF)` in ExaEpi's
  `CMakeLists.txt`, which shadows any `-DAMReX_TINY_PROFILE=ON`, so set that line `ON` for
  the timing binary (ExaEpi PR #158, merged after the paper's code freeze, lets
  `-DAMReX_TINY_PROFILE=ON` work directly). The model routines are already `BL_PROFILE`-annotated
  (`AgentContainer::interactDay`, `...getMedicalWorkerCounts`, the `HospitalModel` /
  `HospitalData` regions), so the table names them directly; it prints to the run stdout
  (`exaepi_*.out`) at finalize. (Without it, the wall time from the run's
  `Job started`/`Job finished` lines gives only a coarse total that includes init and I/O.)
- The same cases also ran on Tuolumne (MI300A) and Dane (CPU); the paper reports only
  Matrix.

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
2. H1_capacity, H1_mitigated → check load > 1 (the score map is closed-form).
3. H3_hcw → calibrate xmit_hosp from `medical_workers.dat`.
4. H2_mw08 / H2_mw13 / H2_mw20 → workforce-size sweep.
5. covflu_{w,wo}_noso → in-hospital cross-disease (nosocomial) transmission.
6. S1 (rescore_sensitivity.py + S1_* corners), S2_hcw_{lo,hi} → sensitivity.
7. cost_{off,on,on_full} → computational-cost timing.
