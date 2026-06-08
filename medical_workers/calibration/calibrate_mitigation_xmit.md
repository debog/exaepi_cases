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
- **HCW hazard ratio (aHR)** = ratio of cumulative infection hazards of medical
  vs other workers, `ln(MW_S0/MW_Send) / ln(OW_S0/OW_Send)` from
  `medical_workers.dat`. The cumulative-hazard ratio is robust to the closed-
  population saturation that compresses a raw attack-rate ratio and to the
  day-to-day noise of an incidence-rate ratio. Target ~3.4, the adjusted risk
  reported for front-line health-care workers (Nguyen et al. 2020).

## Mitigation (H1_mitigated, in-hospital channels off)

Target a realistic mitigated peak load of ~2.5x capacity (the load at which the
treatment-score calibration sets ~2x in-hospital mortality). Sweep
`agent.shelter_compliance` with the rest of the `MITIGATION` block fixed
(`shelter_start = 40`, `shelter_length = 280`, age-tiered symptomatic withdrawal):

| shelter_compliance | peak load | over-cap days | final deaths |
|--------------------|-----------|---------------|--------------|
| 0.40               | 1.86x     | 33            | 31\,994      |
| 0.32               | 2.47x     | 36            | 46\,991      |
| 0.25               | 3.07x     | 38            | 59\,976      |

**Chosen: `shelter_compliance = 0.32`** (peak load 2.47x, single broad peak,
no rebound). Lower compliance (0.40) gives the previous over-mitigated tuning;
0.25 is the upper end of the realistic 2--3x range.

## In-hospital transmission (H3_hcw, channels on, compliance = 0.32)

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

**Chosen: `xmit_hosp_d2d = xmit_hosp_p2d = 0.0075`** (~0.13x p_work; aHR 3.50).
`d2p` is set to the same worker-channel value and `p2p = 0.3 x p_work = 0.01725`,
both carried into the multidisease decks (inert with a single disease). Note the
H3 peak load (3.8x) sits well above the channels-off H1 reference (2.47x): the
in-hospital transmission infects the workforce, cutting capacity -- the H3
workforce-depletion effect, not a mitigation miss. The closed single-wave
epidemic saturates the higher-hazard medical workers (~99% infected); the
calibrated quantity is the hazard *ratio*, not the absolute level.

## Apply

Edit `inputs/make_inputs.sh`: `MITIGATION` block compliance, and the
`HOSP_XMIT_ON` block; regenerate the decks; commit. Then rebuild ExaEpi on the
platform and re-run verifications, H1, and H3 (all model-on runs change).
