# Mitigation and in-hospital-transmission calibration (tract-level model)

Empirical calibration of the H1 mitigation and the in-hospital transmission
weights, done with local 4-MPI-rank Bay Area runs (a single realization each,
~3 min for 150 days). This complements the closed-form treatment-score
calibration in `calibrate_treatment_score.py`.

## Why this was redone

Two changes to the tract-level model moved the operating point and forced a
recalibration:

- **Work-neighborhood fix** (ExaEpi `d4b137f`). Medical workers were excluded
  from the workplace model but not from the work-neighborhood model. With
  tract routing every hospital's whole workforce shares one work cell and
  `work_nborhood = 0`, so they mixed as a single neighborhood group and were
  over-infected (~94% even with the in-hospital channels off), which silently
  depleted capacity. After the fix, medical workers have no generic daytime
  mixing; their only daytime contacts are the hospital model.
- **Tract concentration.** Patients and staff now aggregate at ~58 hospitals
  instead of being spread over ~5000 communities, so a given in-hospital weight
  produces a much higher per-worker hazard than in the county-apportioned model.

## Metrics

- **Peak hospital load** = max over the run of (total hospitalized) / (staffed
  beds, 10\,876), from `output.dat` columns H/NI + H/I + ICU + V.
- **HCW cumulative-hazard ratio (CHR)** = ratio of cumulative infection hazards of
  medical vs other workers, `ln(MW_S0/MW_Send) / ln(OW_S0/OW_Send)` from
  `medical_workers.dat`, read at the **end of the wave** (the paper's metric). Target
  ~3.4, the adjusted risk reported for front-line health-care workers (Nguyen et al.
  2020). The CHR does not collapse when both groups saturate; the attack-rate ratio
  does. In the Matrix `H3_hcw` ensemble mean the running CHR is 3.8 at 2%
  cumulative incidence in other workers (small counts), ~2.9 from 5% to 50%, and
  3.07 at the end. An earlier version of this note said the full-run ratio
  collapses toward 1 and must be read at a low-incidence window; that was wrong.

## Mitigation (data-anchored; superseded the load-target tuning)

The mitigation is now **data-anchored, not tuned to a load target.**
`shelter_compliance = 0.50` is the ~50% out-of-home mobility reduction observed in
the Bay Area after the March 2020 order (Google Community Mobility), and the
symptomatic-withdrawal probabilities are anchored to COVID isolation surveys (~50%
default / ~75-92% enhanced cumulative), replacing the inherited EpiCast/FluTE
influenza values. The mitigated peak load is then an **output**: the Matrix
H1_mitigated ensemble peaks at 1.6x aggregate (day 73) with 12,081 deaths; in
`run_001` at day 75 the median hospital is at 1.6x and the busiest at 9.7x, with
48,925 patient transfers over the wave. The Bay Area did not in fact overload
(it avoided LA/NY-style collapse through high compliance), so the model's overload
is a counterfactual the capacity response acts on.

The earlier sweep below tuned `shelter_compliance` to a ~2.5x peak-load target with
the *old EpiCast withdrawal*; it is kept for reference only and is superseded by
the data anchoring above.

| shelter_compliance | peak load | over-cap days | final deaths |
|--------------------|-----------|---------------|--------------|
| 0.40               | 1.86x     | 33            | 31\,994      |
| 0.32 (old chosen)  | 2.47x     | 36            | 46\,991      |
| 0.25               | 3.07x     | 38            | 59\,976      |

## In-hospital transmission (H3_hcw, channels on)

> Historical: the sweep below was run at the old `0.32` shelter, before the
> shelter-flag fix and the bounded multiplier (`fe7ebfa`). The final value is
> `0.0002` (end of this section).

Worker-infecting weights set equal (`xmit_hosp_d2d = xmit_hosp_p2d`), both
reduced from the workplace weight by infection-control precautions; the patient-
infecting weights (`d2p`, `p2p`) are inert with a single disease. Sweep the
common value to hit aHR ~3.4:

| xmit_hosp_d2d = p2d | aHR (cumhaz) | MW infected | OW infected | H3 peak load |
|---------------------|--------------|-------------|-------------|--------------|
| 0.003               | 2.18         | 94.8%       | 74.2%       | 2.87x        |
| 0.005               | 2.62         | 97.4%       | 75.2%       | 3.20x        |
| 0.0075              | 3.50         | 99.4%       | 77.0%       | 3.81x        |
| 0.008               | 3.54         | 99.5%       | 77.2%       | 3.92x        |

**Superseded (2026-06-13).** The worker weight was recalibrated to
**`xmit_hosp_d2d = xmit_hosp_p2d = 0.0002`** (~0.0035x p_work), read at the time over
a low-incidence window (community ~2%). With the final code (`fe7ebfa`) and the
data-anchored mitigation, the Matrix `H3_hcw` ensemble at `0.0002` gives an
end-of-wave CHR of 3.07 (the paper's 3.1), with MW 94% and OW 61% ever infected.
The patient-infecting weights are no longer carried at the worker value -- they are
calibrated separately (next section).

## Patient-channel (nosocomial) calibration (2026-06-13)

The patient-infecting weights (`d2p`, `p2p`) drive cross-disease nosocomial infection of
admitted patients and are inert with a single disease, so they are calibrated in the
two-disease covflu nosocomial experiment, not the H3 single-disease run. Target: the
**in-hospital nosocomial incidence** -- the fraction of admissions that acquire the
*second* disease in hospital -- of order ~2% (Wolfensberger 7.4% of COVID inpatients;
Zhou ~2%). This is an overall incidence, NOT a per-exposure secondary attack rate.

Diagnostic: domain-sum of `<disease>_hospital_acquired` (cumulative, in the `plt*` mesh,
not `output.dat` or `hospital_data_*`) over both diseases, divided by total admissions
(sum of `NewH`, column 19, over both `output_*.dat`). Use a **fixed `agent.seed`** --
unseeded realizations swing total admissions by ~50%. The household-leak floor (with
`d2p=p2p=0`, hospitalized patients still infected via their household) is ~0.01%,
negligible, so `hospital_acquired` is effectively all channel-driven.

| d2p | p2p (= 3 d2p) | nosocomial incidence |
|-----|---------------|----------------------|
| 0.0    | 0.0        | 0.01% (floor)        |
| 0.0001 | 0.0003     | 2.40%                |
| 0.0075 | 0.01725    | ~27% (old, ~14x too high) |

**Chosen: `d2p = 0.0001`, `p2p = 0.0003`** (held 1:3; nosocomial incidence 2.4%).

**Denominator caveat (found 2026-10-16).** The summed `NewH` over-counts admissions
in a two-disease run. `NewH` for disease d also counts, on every day of the stay,
each hospitalized agent never infected with d: its per-disease counters are all zero,
so `isNewlyHospitalized` matches 0 == 0 + 0. The 2.4% above therefore understates the
per-admission rate. In the Matrix `covflu_w_noso` `run_001`, the 13,026
hospital-acquired infections over a summed `NewH` of 514,151 (361,332 of it flu)
also give 2.5%.

**Correct denominator.** Expected admissions per disease = Σ over age groups of
(new symptomatic agents, the `Symp*` columns of `output_<disease>.dat`) ×
P(hosp | symptomatic) of that age group, from the deck's `CHR`. This mirrors the
admission rule (`DiseaseStatus.H`: a symptomatic agent not already in hospital is
admitted with probability `CHR[age]` on day incubation + delay). The `NewS` predicate
checks the infection status, so these columns are clean. In three single-disease
Matrix `run_001`s (`H1_capacity`, `H1_mitigated`, `H3_hcw`), where `NewH` is correct,
`NewH` is 0.98 of this estimate (cause not checked), so the rates below may be
~2% (relative) low.

Hospital-acquired counts are kept only for `run_001` (the `plt` files of the other
members were pruned). Both available realizations (`calibration/nosocomial_rates.py`,
reads the workstation mirror):

| | Tuolumne `run_001` | Matrix `run_001` |
|---|---|---|
| COVID acquired in hospital (by flu admissions) | 3,700 | 5,079 |
| Flu acquired in hospital (by COVID admissions) | 12,144 | 7,947 |
| `NewH` sum, COVID file / flu file | 141,397 / 407,707 | 152,819 / 361,332 |
| Estimated admissions, COVID / flu | 100,551 / 20,785 | 99,475 / 22,107 |
| `NewH` excess (non-admission days), COVID / flu | 40,846 / 386,922 | 53,344 / 339,225 |
| Any admission acquires the second disease | 13.1% | 10.7% |
| Flu admission acquires COVID | 17.8% | 23.0% |
| COVID admission acquires flu | 12.1% | 8.0% |
| (calibration metric: total HA / summed `NewH`) | 2.9% | 2.5% |

The ensemble-mean admissions are nearly the same on both platforms (~100k COVID,
~21k flu), so the spread in the rates comes from the hospital-acquired counts, i.e.
from realization noise in two single runs.

The paper's "~11%" and "~2.5%" were computed as 15,844/146,837 and 3,700/146,837:
the Tuolumne `run_001` hospital-acquired counts over the Tuolumne ensemble-mean
summed `NewH` of the COVID file alone (146,837). With the correct denominators the
same Tuolumne counts give 13.1% and 17.8%. The "~11%" is in the right range
(10.7-13.1%); the flu→COVID rate is ~18-23%, not 2.5%.

**Consequence for the calibration above.** The 2.4% target value was measured as
total HA / summed `NewH` (both files), the contaminated metric. At the chosen
`d2p = 0.0001`, `p2p = 0.0003` the per-admission incidence is ~11-13%, about five
times the intended ~2%. The submitted paper reports the 11% and calls it "in the
reported range", so it is consistent with the chosen values, but the
`calibrate_mitigation_xmit` record of a ~2% target is not. The 2.4% is not a share
of all infections either: admissions are ~1.65% of all infections (121.6k of 7.4M in
Matrix `run_001`), so no per-infection rate can reach 2.4%; at the chosen values the
hospital-acquired share of all infections is 0.18% (paper: 0.12% COVID, 0.25% flu).

## Apply

Edit `inputs/make_inputs.sh`: `MITIGATION` block compliance, and the
`HOSP_XMIT_ON` block; regenerate the decks; commit. Then rebuild ExaEpi on the
platform and re-run verifications, H1, and H3 (all model-on runs change).
