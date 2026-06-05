#!/bin/bash
#
# make_inputs.sh - generate the medical-worker experiment input decks (Bay Area).
#
# Each deck is self-contained: a shared COVID-19 Bay Area base (census init,
# disease parameters, hospitalization model) followed by an experiment-specific
# medical-worker / hospital-capacity block. Re-run after editing the base or a
# block. The decks map onto the paper's experiments (verification, H1, H2, H3,
# combined); see ../README.md.
#
# Disease/transmission parameters are copied from the multidisease Bay Area
# COVID-19-S1 deck. xmit_work = 0.0575; the in-hospital transmission defaults
# are 0.1x xmit_work (d2d, p2d, d2p) and 0.3x xmit_work (p2p).
#
set -e
cd "$(dirname "${BASH_SOURCE[0]}")"

# --- shared base (everything except the medical-worker block) -----------------
read -r -d '' BASE <<'EOF' || true
## Initialization and data files
agent.ic_type = "census"
agent.census_filename = "BayArea.dat"
agent.workerflow_filename = "BayArea-wf.bin"

## Simulation control
agent.nsteps = 120
agent.max_box_size = 16

## Output control
agent.plot_int = 5
agent.check_int = -1
agent.aggregated_diag_int = 1
agent.aggregated_diag_prefix = "cases"
diag.output_filename = "output.dat"
agent.air_travel_int = -1

## Symptomatic withdrawal compliance (by age group: U5, 5-17, 18-29, 30-49, 50-64, 65+)
agent.symptomatic_withdraw_compliance_day_0 = 0.3 0.3 0.3 0.3 0.3 0.3
agent.symptomatic_withdraw_compliance_day_1 = 0.8 0.7 0.5 0.5 0.5 0.5
agent.symptomatic_withdraw_compliance_day_2 = 0.9 0.8 0.7 0.7 0.7 0.7

## Single-disease COVID-19 setup
agent.number_of_diseases = 1
agent.disease_names = "Cov19S1"

## Initial infection (~3 per million Bay Area pop)
disease.initial_case_type = "random"
disease.num_initial_cases = 20

## Transmission probabilities (by age group: U5, 5-17, 18-29, 30-49, 50-64, 65+)
disease.p_trans = 0.20
disease.xmit_comm = 0.000015 0.000055 0.00015 0.00015 0.00015 0.00025
disease.xmit_hood = 0.000086 0.00025 0.00065 0.00065 0.00065 0.001
disease.xmit_hh_adult = 0.3 0.3 0.4 0.4 0.4 0.4
disease.xmit_hh_child = 0.6 0.6 0.3 0.3 0.3 0.3
disease.xmit_nc_adult = 0.0528 0.0528 0.066 0.066 0.066 0.066
disease.xmit_nc_child = 0.1 0.1 0.0528 0.0528 0.0528 0.0528
disease.xmit_work = 0.0575

## School transmission (by school type: none, college, high, middle, elementary, daycare)
disease.xmit_school = 0 0.0315 0.0315 0.0375 0.0435 0.15
disease.xmit_school_a2c = 0 0.0315 0.0315 0.0375 0.0435 0.15
disease.xmit_school_c2a = 0 0.0315 0.0315 0.0375 0.0435 0.15

## Disease characteristics
disease.p_asymp = 0.30
disease.asymp_relative_inf = 0.7
disease.vac_eff = 0.0
disease.child_compliance = 0.5
disease.child_hh_closure = 2.0

## Disease period distributions (gamma distribution: alpha, beta)
disease.latent_length_alpha = 5.2
disease.latent_length_beta = 0.75
disease.infectious_length_alpha = 26.2
disease.infectious_length_beta = 0.23
disease.incubation_length_alpha = 7.5
disease.incubation_length_beta = 0.65
disease.immune_length_alpha = 540.0
disease.immune_length_beta = 0.33

## Hospitalization delay distribution (gamma distribution: alpha, beta)
disease.hospital_delay_length_alpha = 1.0
disease.hospital_delay_length_beta = 1.0

## Hospital stay model
disease.hospital_stay_type = "constant"
disease.hospitalization_days = 3 3 3 3 8 7

## Hospital outcome probabilities (by age group: U5, 5-17, 18-29, 30-49, 50-64, 65+)
disease.CHR = 0.0181 0.0094 0.0260 0.0260 0.0720 0.2244
disease.CIC = 0.24 0.24 0.24 0.36 0.36 0.35
disease.CVE = 0.12 0.12 0.12 0.22 0.22 0.22
disease.hospCVF = 0 0 0 0 0 0
disease.icuCVF = 0 0 0 0 0 0.26
disease.ventCVF = 0.20 0.20 0.20 0.45 0.45 1.0
EOF

# In-hospital transmission blocks (on = defaults, off = isolate capacity from workforce loss)
read -r -d '' HOSP_XMIT_ON <<'EOF' || true
disease.xmit_hosp_d2d = 0.00575
disease.xmit_hosp_p2d = 0.00575
disease.xmit_hosp_d2p = 0.00575
disease.xmit_hosp_p2p = 0.01725
EOF

read -r -d '' HOSP_XMIT_OFF <<'EOF' || true
disease.xmit_hosp_d2d = 0.0
disease.xmit_hosp_p2d = 0.0
disease.xmit_hosp_d2p = 0.0
disease.xmit_hosp_p2p = 0.0
EOF

# Matched in-hospital transmission: doctor-to-doctor at the regular workplace
# rate (xmit_work = 0.0575), no patient channels. Medical workers keep their
# occupational transmission (now in the hospital workgroup), so a model-on run
# with ample beds should reproduce the baseline; the gap to verify_ample is then
# attributable to the reduced medical-worker transmission there.
read -r -d '' HOSP_XMIT_MATCH <<'EOF' || true
disease.xmit_hosp_d2d = 0.0575
disease.xmit_hosp_p2d = 0.0
disease.xmit_hosp_d2p = 0.0
disease.xmit_hosp_p2p = 0.0
EOF

# Mitigation block: a shelter-in-place window and a higher symptomatic-withdrawal
# compliance, to flatten the epidemic into a realistic surge (peak load ~2-3x,
# not the ~25x of an unmitigated run). The withdrawal lines override the base
# (ParmParse takes the last value). Tune the shelter strength/timing and the
# compliance to land the peak load in the target range.
read -r -d '' MITIGATION <<'EOF' || true

## --- Mitigation: shelter-in-place + symptomatic withdrawal ---
agent.shelter_start = 40
agent.shelter_length = 45
agent.shelter_compliance = 0.7
agent.symptomatic_withdraw_compliance_day_0 = 0.5 0.5 0.6 0.6 0.6 0.7
agent.symptomatic_withdraw_compliance_day_1 = 0.8 0.8 0.85 0.85 0.85 0.9
agent.symptomatic_withdraw_compliance_day_2 = 0.9 0.9 0.95 0.95 0.95 0.95
EOF

# Note: the COVID-19 disease.CHR set in BASE and BASE2D is the realistic US
# age-stratified hospitalization rate, P(hospitalized | symptomatic case),
# replacing the high EpiCast defaults (CHR=1.0 for 65+) that drove peak load ~25x.
# It is computed as estimated hospitalizations / symptomatic illnesses by age from
# Reese et al. 2021 (Clin Infect Dis 72(12):e1010; CDC, United States, Feb-Sep
# 2020), Table 3 over Table 4:
#   0-4   20719/1144532   = 0.0181
#   5-17  44321/4719785   = 0.0094
#   18-49 652741/25096725 = 0.0260   (ExaEpi 18-29 and 30-49 both take this)
#   50-64 642358/8926318  = 0.0720
#   >=65  1022295/4556384 = 0.2244

# --- two-disease base: COVID-19 (Cov19S1) + influenza A/H3N2 (FluS1) ----------
#     Flu parameters and the COVID+flu coupling follow the multidisease decks.
read -r -d '' BASE2D <<'EOF' || true
## Initialization and data files
agent.ic_type = "census"
agent.census_filename = "BayArea.dat"
agent.workerflow_filename = "BayArea-wf.bin"

## Simulation control
agent.nsteps = 120
agent.max_box_size = 16

## Output control
agent.plot_int = 5
agent.check_int = -1
agent.aggregated_diag_int = 1
agent.aggregated_diag_prefix = "cases"
diag.output_filename = "output_Cov19S1.dat" "output_FluS1.dat"
agent.air_travel_int = -1

## Symptomatic withdrawal compliance (by age group: U5, 5-17, 18-29, 30-49, 50-64, 65+)
agent.symptomatic_withdraw_compliance_day_0 = 0.3 0.3 0.3 0.3 0.3 0.3
agent.symptomatic_withdraw_compliance_day_1 = 0.8 0.7 0.5 0.5 0.5 0.5
agent.symptomatic_withdraw_compliance_day_2 = 0.9 0.8 0.7 0.7 0.7 0.7

## Two co-circulating diseases
agent.number_of_diseases = 2
agent.disease_names = "Cov19S1" "FluS1"

## Disease coupling (2x2, row-major): no cross-immunity; moderate co-susceptibility
disease_coupling.coimmunity_matrix = \
    1.0  0.0 \
    0.0  1.0
disease_coupling.cosusceptibility_matrix = \
    1.0  1.5 \
    1.5  1.0

## Default disease parameters (Cov19S1: wild-type COVID-19)
disease.initial_case_type = "random"
disease.num_initial_cases = 20
disease.p_trans = 0.20
disease.xmit_comm = 0.000015 0.000055 0.00015 0.00015 0.00015 0.00025
disease.xmit_hood = 0.000086 0.00025 0.00065 0.00065 0.00065 0.001
disease.xmit_hh_adult = 0.3 0.3 0.4 0.4 0.4 0.4
disease.xmit_hh_child = 0.6 0.6 0.3 0.3 0.3 0.3
disease.xmit_nc_adult = 0.0528 0.0528 0.066 0.066 0.066 0.066
disease.xmit_nc_child = 0.1 0.1 0.0528 0.0528 0.0528 0.0528
disease.xmit_work = 0.0575
disease.xmit_school = 0 0.0315 0.0315 0.0375 0.0435 0.15
disease.xmit_school_a2c = 0 0.0315 0.0315 0.0375 0.0435 0.15
disease.xmit_school_c2a = 0 0.0315 0.0315 0.0375 0.0435 0.15
disease.p_asymp = 0.30
disease.asymp_relative_inf = 0.7
disease.vac_eff = 0.0
disease.child_compliance = 0.5
disease.child_hh_closure = 2.0
disease.latent_length_alpha = 5.2
disease.latent_length_beta = 0.75
disease.infectious_length_alpha = 26.2
disease.infectious_length_beta = 0.23
disease.incubation_length_alpha = 7.5
disease.incubation_length_beta = 0.65
disease.immune_length_alpha = 540.0
disease.immune_length_beta = 0.33
disease.hospital_delay_length_alpha = 1.0
disease.hospital_delay_length_beta = 1.0
disease.hospital_stay_type = "constant"
disease.hospitalization_days = 3 3 3 3 8 7
disease.CHR = 0.0181 0.0094 0.0260 0.0260 0.0720 0.2244
disease.CIC = 0.24 0.24 0.24 0.36 0.36 0.35
disease.CVE = 0.12 0.12 0.12 0.22 0.22 0.22
disease.hospCVF = 0 0 0 0 0 0
disease.icuCVF = 0 0 0 0 0 0.26
disease.ventCVF = 0.20 0.20 0.20 0.45 0.45 1.0

## FluS1 overrides (influenza A/H3N2)
disease_FluS1.initial_case_type = "random"
disease_FluS1.num_initial_cases = 25
disease_FluS1.p_trans = 0.16
disease_FluS1.p_asymp = 0.16
disease_FluS1.asymp_relative_inf = 0.5
disease_FluS1.latent_length_alpha = 4.0
disease_FluS1.latent_length_beta = 0.5
disease_FluS1.infectious_length_alpha = 15.0
disease_FluS1.infectious_length_beta = 0.3
disease_FluS1.incubation_length_alpha = 4.0
disease_FluS1.incubation_length_beta = 0.5
disease_FluS1.immune_length_alpha = 180.0
disease_FluS1.immune_length_beta = 1.5
disease_FluS1.hospitalization_days = 2 2 3 3 5 5
disease_FluS1.CHR = 0.009 0.004 0.006 0.008 0.023 0.15
disease_FluS1.CIC = 0.18 0.22 0.16 0.16 0.21 0.15
disease_FluS1.CVE = 0.28 0.25 0.50 0.50 0.52 0.40
disease_FluS1.hospCVF = 0 0 0 0 0 0
disease_FluS1.icuCVF = 0.02 0.02 0.03 0.03 0.05 0.10
disease_FluS1.ventCVF = 0.05 0.10 0.15 0.25 0.30 0.50
EOF

# --- writer: $1 = name, $2 = medical-worker block, $3 = base deck (default 1-disease) ---
write_case () {
    local name="$1"
    local block="$2"
    local base="${3:-$BASE}"
    {
        echo "$base"
        echo ""
        echo "## ===== Medical-worker / hospital-capacity model ====="
        echo "$block"
    } > "inputs_bay_${name}"
    echo "  wrote inputs_bay_${name}"
}

# --- verification: gate off (must reproduce development exactly) --------------
write_case "verify_off" "agent.model_medical_workers = false"

# --- verification: model on, ample beds + no in-hospital transmission ---------
#     load stays well below 1 -> treatment quality stays 1 -> baseline mortality
write_case "verify_ample" "agent.model_medical_workers = true
agent.med_workers_proportion = 0.13
hospital_model.use_HHS_data = false
hospital_model.staffed_beds_per_1000 = 100.0
hospital_model.score_minimum = 0.1
hospital_model.halfscore_load = 5
hospital_model.write_pltfiles = true
${HOSP_XMIT_OFF}"

# --- verification: matched control -- model on, ample beds, doctor-to-doctor at
#     the workplace rate, no patient channels. Restores medical-worker
#     transmission so this should reproduce the baseline (verify_off); the gap
#     from verify_ample is then attributable to reduced medical-worker mixing.
write_case "verify_match" "agent.model_medical_workers = true
agent.med_workers_proportion = 0.13
hospital_model.use_HHS_data = false
hospital_model.staffed_beds_per_1000 = 100.0
hospital_model.score_minimum = 0.1
hospital_model.halfscore_load = 5
hospital_model.write_pltfiles = true
${HOSP_XMIT_MATCH}"

# --- H1: hospital load -> excess mortality, workforce held ~fixed -------------
#     real county beds; no in-hospital transmission so capacity ~ bed supply.
#     Calibrate score_minimum / halfscore_load here (mortality ~2x at peak strain).
write_case "H1_capacity" "agent.model_medical_workers = true
agent.med_workers_proportion = 0.13
hospital_model.use_HHS_data = true
hospital_model.hospital_data_file = \"BayArea_hospitals_2020.dat\"
hospital_model.score_minimum = 0.1
hospital_model.halfscore_load = 5
hospital_model.write_pltfiles = true
${HOSP_XMIT_OFF}"

# --- H1 (mitigated): realistic surge via shelter-in-place + withdrawal ---------
#     Same as H1_capacity but with mitigation, to pull the peak load into a
#     realistic ~2-3x range (the unmitigated run overwhelms the ~10.9k real beds
#     ~25x). Check the resulting peak load, tune the mitigation, then calibrate
#     score_minimum / halfscore_load for the ~2x mortality target.
write_case "H1_mitigated" "agent.model_medical_workers = true
agent.med_workers_proportion = 0.13
hospital_model.use_HHS_data = true
hospital_model.hospital_data_file = \"BayArea_hospitals_2020.dat\"
hospital_model.score_minimum = 0.1
hospital_model.halfscore_load = 5
hospital_model.write_pltfiles = true
${HOSP_XMIT_OFF}
${MITIGATION}"

# --- H3: in-hospital transmission -> workforce depletion feedback -------------
#     same as H1 but the patient-coupled channels are on. Calibrate xmit_hosp_*
#     here (HCW infection risk). Central workforce size (0.13).
write_case "H3_hcw" "agent.model_medical_workers = true
agent.med_workers_proportion = 0.13
hospital_model.use_HHS_data = true
hospital_model.hospital_data_file = \"BayArea_hospitals_2020.dat\"
hospital_model.score_minimum = 0.1
hospital_model.halfscore_load = 5
hospital_model.write_pltfiles = true
${HOSP_XMIT_ON}"

# --- H2: workforce-size sweep (depletion on; size sets capacity fragility) ----
#     central value 0.13 is the H3_hcw run; here the low/high ends.
write_case "H2_mw08" "agent.model_medical_workers = true
agent.med_workers_proportion = 0.08
hospital_model.use_HHS_data = true
hospital_model.hospital_data_file = \"BayArea_hospitals_2020.dat\"
hospital_model.score_minimum = 0.1
hospital_model.halfscore_load = 5
hospital_model.write_pltfiles = true
${HOSP_XMIT_ON}"

write_case "H2_mw20" "agent.model_medical_workers = true
agent.med_workers_proportion = 0.20
hospital_model.use_HHS_data = true
hospital_model.hospital_data_file = \"BayArea_hospitals_2020.dat\"
hospital_model.score_minimum = 0.1
hospital_model.halfscore_load = 5
hospital_model.write_pltfiles = true
${HOSP_XMIT_ON}"

# --- combined: all mechanisms, tract-level real placement + patient routing ---
write_case "combined" "agent.model_medical_workers = true
agent.med_workers_proportion = 0.13
hospital_model.use_HHS_data = true
hospital_model.hospital_data_file = \"BayArea_hospitals_tract_2020.dat\"
hospital_model.score_minimum = 0.1
hospital_model.halfscore_load = 5
hospital_model.write_pltfiles = true
${HOSP_XMIT_ON}"

# --- multidisease (COVID + influenza): in-hospital cross-disease transmission --
#     Two co-circulating diseases let the patient-coupled channels act: a patient
#     admitted for one disease can acquire the other in the hospital. md_combined
#     turns on all four in-hospital channels; md_nonoso keeps the worker channels
#     (p2d, d2d) but turns the patient-coupled channels (d2p, p2p) off. The
#     difference isolates hospital-acquired (nosocomial) co-infection.
write_case "md_combined" "agent.model_medical_workers = true
agent.med_workers_proportion = 0.13
hospital_model.use_HHS_data = true
hospital_model.hospital_data_file = \"BayArea_hospitals_2020.dat\"
hospital_model.score_minimum = 0.1
hospital_model.halfscore_load = 5
hospital_model.write_pltfiles = true
disease.xmit_hosp_d2d = 0.00575
disease.xmit_hosp_p2d = 0.00575
disease.xmit_hosp_d2p = 0.00575
disease.xmit_hosp_p2p = 0.01725
disease_FluS1.xmit_hosp_d2d = 0.00575
disease_FluS1.xmit_hosp_p2d = 0.00575
disease_FluS1.xmit_hosp_d2p = 0.00575
disease_FluS1.xmit_hosp_p2p = 0.01725" "$BASE2D"

write_case "md_nonoso" "agent.model_medical_workers = true
agent.med_workers_proportion = 0.13
hospital_model.use_HHS_data = true
hospital_model.hospital_data_file = \"BayArea_hospitals_2020.dat\"
hospital_model.score_minimum = 0.1
hospital_model.halfscore_load = 5
hospital_model.write_pltfiles = true
disease.xmit_hosp_d2d = 0.00575
disease.xmit_hosp_p2d = 0.00575
disease.xmit_hosp_d2p = 0.0
disease.xmit_hosp_p2p = 0.0
disease_FluS1.xmit_hosp_d2d = 0.00575
disease_FluS1.xmit_hosp_p2d = 0.00575
disease_FluS1.xmit_hosp_d2p = 0.0
disease_FluS1.xmit_hosp_p2p = 0.0" "$BASE2D"

echo "done."
