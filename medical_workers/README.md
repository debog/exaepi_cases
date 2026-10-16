# Medical-worker / hospital-capacity experiments

Run setups for the ExaEpi medical-worker paper. Each deck isolates one
mechanism of the hospital-capacity model. The structure mirrors `../multidisease`: a generic runner copies data and
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

## Paper results (IDM submission, IDM-S-26-00436)

- Code: every submitted-paper ensemble logs `ExaEpi version 25.04-110-gfe7ebfa`
  and AMReX `26.06-11-g9ed35ab0e584`. The branch `archive/2026_medworkers_paper`
  now holds the revision code, `ba03243` (`fe7ebfa` + the `development` merge with
  PRs #158 and #161-#163 + the issue #159 discharge fix). The merge only touches
  UrbanPop, weather, travel, and the build, none of which these decks use. The
  discharge fix changes the epidemic only in the two-disease `covflu_*` decks,
  since in single-disease runs a discharged agent is immune. Build with AMReX
  pinned to `9ed35ab0e584`.
- Reproduction check (Matrix job 441327, 2026-10-16): `ba03243` re-ran `run_001`
  (`agent.seed=1`) of three decks, in `.run_bay_revcheck_matrix`.
  - `H1_capacity` (no shelter): `output.dat` and `medical_workers.dat` are
    bit-identical to the paper's `run_001`.
  - `H1_mitigated` and `covflu_w_noso` match up to day 41 and diverge from day 42,
    the first discharges after the day-40 shelter order: the discharge kernel now
    draws a random number, which shifts the RNG stream. For `H1_mitigated` this is
    the only effect (immunity is permanent, `immune_length_loc` = 10000 d).
  - Deaths: `H1_mitigated` 12,243 (paper `run_001` 12,146; ensemble 12,082 ± 502);
    `covflu_w_noso` 13,443 (13,977; 14,426 ± 1,118). Peak load 1.66x vs 1.61x and
    1.73x vs 1.74x.
  - The paper's shelter-on ensembles therefore cannot be reproduced bitwise from
    `ba03243`; `fe7ebfa` still reproduces them.
- Runs: the Matrix ensembles `.ensemble_bay_<case>_matrix` (25 members, one H100
  each), in `/p/vast1/ghosh5/exaepi/medical_workers` and the workstation mirror.
  The committed decks are byte-identical to the decks those ensembles ran. The
  `*_tuolumne` ensembles are the earlier set, superseded by Matrix and not used in
  the paper.
- Headline values (ensemble means; per-hospital values from `run_001`):

| Case | Deaths (σ) | Peak load (aggregate) | Other |
|---|---|---|---|
| `verify_off` / `verify_ample` | 22,743 (163) / 22,433 (112) | — (ample beds) | peak infected 3.5M / 3.2M |
| `H1_capacity` | 58,216 (253) | 6.8× (day 64) | day 60: 56 of 58 hospitals over capacity, median 6.5×, busiest 98× |
| `verify_ample_mit` / `H1_mitigated` | 8,290 (107) / 12,081 (503) | — / 1.6× (day 73) | day 75: 42 of 58 over capacity, median 1.6×, busiest 9.7×; 48,925 transfers |
| `H1_mitigated_notransfer` | 13,337 (517) | 1.6× | |
| `H3_hcw` | 14,819 (847) | 1.8× | CHR 3.07; ever infected: MW 94%, OW 61%; MW deaths 457 → 824 |
| `H2_mw08` / `mw13` / `mw20` | 15,571 (261) / 11,358 (205) / 9,013 (135) | 1.65× / 0.98× / 0.60× | fallback beds, aggregate load from `hospital_data` |
| `covflu_wo_noso` / `w_noso` | 14,254 (1,166) / 14,426 (1,118) | 1.7× (day 68) | `run_001` hospital-acquired: 20 + 26 / 5,079 + 7,947 (COVID + flu) |
| `S2_hcw_lo` / `S2_hcw_hi` | | | CHR 2.55 / 3.86 |

  Peak load = peak hospitalized ÷ 10,876 staffed beds (HHS cases).
  CHR = `ln(S0/Send)` of medical workers ÷ that of other workers, from
  `medical_workers_mean.dat`.

## Experiment matrix

All decks are Bay Area, census init, up to one year (nsteps 365; the cost decks stop at 120). Most use a single COVID-19
strain; the two `covflu_*` decks add co-circulating influenza. They are generated
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
| `covflu_w_noso` | **Nosocomial** (COVID+flu): all in-hospital channels | on | real, tract | on (all 4) |
| `covflu_wo_noso` | COVID+flu, patient channels off | on | real, tract | worker only |
| `S1_mmax2`/`S1_mmax4` | **S1** (sensitivity): overload mortality ceiling `M_max`=2 / 4 (mitigated) | on | real, tract | off |
| `S1_lhalf10`/`S1_lhalf25` | **S1**: half-score load `L_1/2`=1.0 / 2.5 (mitigated) | on | real, tract | off |
| `S2_hcw_lo`/`S2_hcw_hi` | **S2**: in-hospital xmit scaled ~0.67× / 1.6× (HCW-hazard sweep) | on | real, tract | on (scaled) |
| `cost_off`/`cost_on`/`cost_on_full` | **Cost**: timing, model off / capacity-only / full (plotfiles off) | off/on | real, tract | off / off / on |

**Sensitivity and cost (paper Sections 6.1–6.2).** The load-to-mortality map
(`M_max`, `L_1/2`) sensitivity is mostly post-processing:
`scripts/rescore_sensitivity.py` re-scores the saved H1/H3 load trajectories over an
(`M_max`, `L_1/2`) grid (validated at high uniform load; underestimates the
spatially-concentrated mitigated case). The `S1_*` full runs anchor the mitigated
operating point. `S2_hcw_{lo,hi}` bracket the calibrated HCW hazard ratio — tune the
xmit scaling from `medical_workers.dat`. The `cost_*` runs time the per-step overhead
(off vs on) on one to four H100s (`.ensemble_bay_cost_*_matrix_n{1..4}`); the
paper reports one GPU.

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
- **Nosocomial co-infection:** `covflu_{w,wo}_noso` (COVID+flu). `w_noso` −
  `wo_noso` isolates the patient-receiving in-hospital channels (`d2p`, `p2p`): the
  second-disease infections acquired in the hospital (the `hospital_acquired`
  diagnostic) and their excess mortality. This is an artificial stress test (shared
  symptomatic withdrawal, no cross-immunity or vaccination, cosusceptibility pinned
  at the formula floor `c_S = 1.0`, peak hospital load 1.7× against 1.6× for
  COVID alone), so the channel difference is a near-upper-bound; see the paper's
  Section 5.6 disclaimers.

## Calibration

Capacity magnitude is pinned by the real HHS bed data. The score model is set in
closed form by `~/Documents/Work_Docs/2026_Infect_Dis_Model/calibration/`; the mitigation and the
in-hospital weights are set empirically with local 4-rank runs, documented in
[calibration/calibrate_mitigation_xmit.md](calibration/calibrate_mitigation_xmit.md)
(current values: `shelter_compliance = 0.50` data-anchored, `xmit_hosp_d2d = p2d = 0.0002`, `d2p = 0.0001`, `p2p = 0.0003`):

- `halfscore_load = 1.5`, `mortality_multiplier_max = 3.0` (`score_minimum`=0, dropped) — from **H1**: in-hospital
  mortality ~2× the unstrained baseline at a 2.5× peak load (the score model's
  dose-response, independent of the mitigation).
- `shelter_compliance = 0.50` and the symptomatic-withdrawal probabilities —
  **data-anchored** (Bay Area mobility and COVID isolation surveys), not tuned to a
  load target; the mitigated peak load is then an output (1.6× aggregate).
- `disease.xmit_hosp_{d2d,p2d}` — from **H3**: tune to the HCW hazard target
  (cumulative-hazard ratio ~3.4; achieved 3.07). The metric is robust to
  closed-population saturation; the raw attack-rate ratio is not.
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
for c in verify_off verify_ample H1_capacity H3_hcw H2_mw08 H2_mw13 H2_mw20 covflu_w_noso covflu_wo_noso; do
    ./scripts/run_exaepi.sh --case=bay_$c --mode=batch --ensemble --ensemble-size=25
done

# dry run to inspect commands without submitting
./scripts/run_exaepi.sh --case=bay_H3_hcw --mode=batch --ensemble --dry-run
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
for the `covflu_*` decks) whenever the model is on: totals, susceptible, newly
infected, and cumulative deaths (`MW_dead`/`OW_dead`) for each group. The ensemble
step averages these alongside `output.dat`. Per-community grid fields
(`hospital_data_*`) and the per-agent treatment quality are written when
`hospital_model.write_pltfiles` is set. Setting
`hospital_model.transfer_output_file` logs each day's patient transfers (day,
from/to hospital FIPS+tract, count).
