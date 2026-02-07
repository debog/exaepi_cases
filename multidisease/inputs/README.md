# Multi-Disease Input Files

## Diseases and Strains

### SARS-CoV-2 (COVID-19)
- **Cov19S1**: Ancestral/wild-type SARS-CoV-2 (parameters from EpiCast)
- **Cov19S2**: Delta variant (B.1.617.2)

### Influenza A
- **FluS1**: Seasonal H3N2 (typically dominant, most severe in elderly)
- **FluS2**: H1N1pdm09 (more severe in younger adults, less in elderly)

---

## COVID-19: Parameter Differences S1 (Wild-Type) vs S2 (Delta)

| Parameter                  | S1 (wild-type)                       | S2 (Delta)                           | Rationale                                                |
|----------------------------|--------------------------------------|--------------------------------------|----------------------------------------------------------|
| `p_trans`                  | 0.20                                 | 0.35                                 | ~2x higher R0, driven by higher viral loads [C1,C8]      |
| `p_asymp`                  | 0.30                                 | 0.15                                 | Lower asymptomatic fraction observed for Delta [C5]      |
| `latent_length_alpha`      | 5.2                                  | 4.7                                  | Shorter latent period, proportional to shorter incub [C3] |
| `infectious_length_beta`   | 0.23                                 | 0.27                                 | Longer culture-positive duration: ~7 vs ~4 days [C4]     |
| `incubation_length_alpha`  | 7.5                                  | 4.43                                 | Gamma fit from contact tracing data [C2]                  |
| `incubation_length_beta`   | 0.65                                 | 1.01                                 | Gamma fit from contact tracing data [C2]                  |
| `CHR`                      | 0.0104 0.0104 0.070 0.28 0.28 1.0   | 0.0201 0.0201 0.135 0.54 0.54 1.0   | HR ~1.93 for hospitalization [C6]                         |
| `icuCVF`                   | 0 0 0 0 0 0.26                       | 0 0 0 0 0 0.30                       | Modestly higher mortality [C6,C7]                         |
| `ventCVF`                  | 0.20 0.20 0.20 0.45 0.45 1.0        | 0.25 0.25 0.25 0.55 0.55 1.0        | Modestly higher mortality [C6,C7]                         |

All other parameters (contact structure, immune period, CIC, CVE, etc.) are kept the same
due to insufficient variant-specific data or no statistically significant difference
between pre-Delta and Delta periods [C7].

## Influenza: Parameter Differences S1 (H3N2) vs S2 (H1N1pdm09)

Both strains share the same transmission and disease period parameters (similar R0 ~1.3,
similar incubation ~2 days, similar infectious period ~4.5 days). They differ primarily in
severity profile and age distribution of outcomes.

| Parameter | S1 (H3N2)                            | S2 (H1N1pdm09)                      | Rationale                                                |
|-----------|--------------------------------------|--------------------------------------|----------------------------------------------------------|
| `p_asymp` | 0.16                                 | 0.12                                 | H1N1pdm09 slightly lower asymptomatic fraction [F4]      |
| `CHR`     | 0.009 0.004 0.006 0.008 0.023 0.15  | 0.012 0.008 0.012 0.015 0.020 0.06  | H1N1pdm09 more severe in young, less in elderly [F9,F10] |
| `CIC`     | 0.18 0.22 0.16 0.16 0.21 0.15       | 0.25 0.30 0.23 0.23 0.30 0.20       | Higher ICU admission (OR 1.42 vs H3N2) [F9]              |
| `CVE`     | 0.28 0.25 0.50 0.50 0.52 0.40       | 0.35 0.30 0.55 0.55 0.55 0.45       | Higher ventilation (OR 1.79 vs H3N2) [F9]                |
| `icuCVF`  | 0.02 0.02 0.03 0.03 0.05 0.10       | 0.02 0.03 0.04 0.04 0.06 0.08       | More deaths in younger groups [F8,F9]                     |
| `ventCVF` | 0.05 0.10 0.15 0.25 0.30 0.50       | 0.06 0.12 0.18 0.28 0.35 0.45       | CFR ~50% lower than H3N2 overall [F8]                     |

## Influenza vs COVID-19: Key Parameter Differences

| Parameter                | COVID-19 S1   | Influenza S1 (H3N2) | Notes                                                |
|--------------------------|---------------|----------------------|------------------------------------------------------|
| `p_trans`                | 0.20          | 0.15                 | COVID R0 ~2.5 vs flu R0 ~1.3 [C1,F1]                |
| `p_asymp`                | 0.30          | 0.16                 | COVID has higher asymptomatic fraction [C5,F4]       |
| `asymp_relative_inf`     | 0.7           | 0.5                  | COVID asymptomatics relatively more infectious [F5]  |
| `latent_length` (mean)   | 3.9 days      | 1.5 days             | Flu has much shorter latent period [C3,F3]           |
| `infectious_length` (mn) | 6.0 days      | 4.5 days             | Flu has shorter infectious period [C4,F3]            |
| `incubation_length` (mn) | 4.9 days      | 2.0 days             | Flu incubation roughly half of COVID [C2,F2]         |
| `immune_length` (mean)   | 178 days      | 270 days             | Flu immunity somewhat longer [C7,F7]                 |
| `CHR` (65+)              | 1.0           | 0.15                 | COVID far more severe in elderly                     |
| `hospitalization_days`   | 3 3 3 3 8 7   | 2 2 3 3 5 5          | Flu hospital stays shorter [F6]                      |

## Disease Coupling Matrices

The multi-disease input files use coimmunity and cosusceptibility matrices to model
cross-disease interactions. Values are derived from published literature.

### Coimmunity (protection from prior infection with one disease against another)

|              | Cov19S1 | Cov19S2 | FluS1 |
|--------------|---------|---------|-------|
| **Cov19S1**  | 1.0     | 0.85    | 0.0   |
| **Cov19S2**  | 0.85    | 1.0     | 0.0   |
| **FluS1**    | 0.0     | 0.0     | 1.0   |

- **COVID S1-S2 (0.85)**: Prior wild-type infection provides 85.4% (95% CI: 80.0-89.3%)
  protection against Delta reinfection [M1]. Neutralization titers are reduced 3-5 fold [M2],
  but clinical protection against severe disease remains ~90% at 40 weeks [M3].
- **COVID-Flu (0.0)**: Different virus families; no cross-immunity.

### Cosusceptibility (change in susceptibility during active co-infection)

|              | Cov19S1 | Cov19S2 | FluS1 |
|--------------|---------|---------|-------|
| **Cov19S1**  | 1.0     | 1.0     | 1.5   |
| **Cov19S2**  | 1.0     | 1.0     | 1.5   |
| **FluS1**    | 1.5     | 1.5     | 1.0   |

- **COVID S1-S2 (1.0)**: No clear evidence for enhanced susceptibility to one COVID
  variant during active infection with another. Set to neutral.
- **COVID-Flu (1.5)**: Meta-analyses show COVID+flu co-infection significantly increases
  ICU admission (OR = 2.09, 95% CI: 1.64-2.68) and mechanical ventilation
  (OR = 2.31, 95% CI: 1.10-4.85) [M4]. For influenza A specifically, ventilation
  OR = 2.73 (1.46-5.10) [M5]. Viral interference through IFN response partially
  suppresses co-infection, but concurrent infection lowers the IFN response compared
  to single infection [M6]. The value of 1.5 is a moderate estimate reflecting the
  net effect of these competing mechanisms.

---

## COVID-19 References

- [C1] Liu Y, Rocklov J (2021). The reproductive number of the Delta variant of SARS-CoV-2 is far higher compared to the ancestral SARS-CoV-2 virus. *J Travel Medicine* 28(7). [doi:10.1093/jtm/taab124](https://doi.org/10.1093/jtm/taab124)
- [C2] Hart WS et al. (2022). Estimation of the incubation period and generation time of SARS-CoV-2 Alpha and Delta variants from contact tracing data. *Epidemics*. [PMC9837419](https://pmc.ncbi.nlm.nih.gov/articles/PMC9837419/)
- [C3] Xin H et al. (2024). Latent and incubation periods of Delta, BA.1, and BA.2 variant cases and associated factors. *BMC Infect Dis*. [PMC10916204](https://pmc.ncbi.nlm.nih.gov/articles/PMC10916204/)
- [C4] Pang Z et al. (2023). The differences in virus shedding time between the Delta variant and original SARS-CoV-2 infected patients. *Frontiers Public Health*. [PMC10408444](https://pmc.ncbi.nlm.nih.gov/articles/PMC10408444/)
- [C5] Miyahara R et al. (2022). A low proportion of asymptomatic COVID-19 patients with the Delta variant infection by viral transmission through household contact. *Int J Environ Res Public Health*. [PMC9243404](https://pmc.ncbi.nlm.nih.gov/articles/PMC9243404/)
- [C6] Fisman DN, Tuite AR (2021). Increased risk of hospitalisation and death with the delta variant in the USA. *Lancet Infect Dis*. [doi:10.1016/S1473-3099(21)00685-X](https://doi.org/10.1016/S1473-3099(21)00685-X)
- [C7] Garg S et al. (2021). Severity of Disease Among Adults Hospitalized with Laboratory-Confirmed COVID-19 Before and During the Period of SARS-CoV-2 B.1.617.2 (Delta) Predominance. *MMWR* 70(43). [CDC](https://www.cdc.gov/mmwr/volumes/70/wr/mm7043e1.htm)
- [C8] Allen H et al. (2022). Household secondary attack rates of SARS-CoV-2 by variant and vaccination status: an updated systematic review and meta-analysis. *JAMA Netw Open*. [PMC8764734](https://pmc.ncbi.nlm.nih.gov/articles/PMC8764734/)

## Influenza References

- [F1] Biggerstaff M et al. (2014). Estimates of the reproduction number for seasonal, pandemic, and zoonotic influenza: a systematic review of the literature. *BMC Infect Dis*. [PMC4169819](https://pmc.ncbi.nlm.nih.gov/articles/PMC4169819/)
- [F2] Lessler J et al. (2009). Incubation periods of acute respiratory viral infections: a systematic review. *Lancet Infect Dis*. [PMC4327893](https://pmc.ncbi.nlm.nih.gov/articles/PMC4327893/)
- [F3] Carrat F et al. (2008). Time lines of infection and disease in human influenza: a review of volunteer challenge studies. *Am J Epidemiol* 167(7):775-785. [doi:10.1093/aje/kwm375](https://doi.org/10.1093/aje/kwm375)
- [F4] Leung NHL et al. (2015). The fraction of influenza virus infections that are asymptomatic: a systematic review and meta-analysis. *Epidemiology*. [PMC4586318](https://pmc.ncbi.nlm.nih.gov/articles/PMC4586318/)
- [F5] Tsang TK et al. (2023). Reconstructing household transmission dynamics to estimate the infectiousness of asymptomatic influenza virus infections. *PNAS*. [doi:10.1073/pnas.2304750120](https://doi.org/10.1073/pnas.2304750120)
- [F6] CDC FluSurv-NET (2024). Laboratory-Confirmed Influenza-Associated Hospitalizations Among Children and Adults, United States, 2010-2023. *MMWR Surveill Summ* 73(SS-6). [CDC](https://www.cdc.gov/mmwr/volumes/73/ss/ss7306a1.htm)
- [F7] Sridhar S et al. (2015). Longevity and determinants of protective humoral immunity after pandemic influenza infection. *Am J Respir Crit Care Med*. [PMC4351579](https://pmc.ncbi.nlm.nih.gov/articles/PMC4351579/)
- [F8] Koh YS et al. (2023). Inference of age-dependent case-fatality ratios for seasonal influenza virus subtypes A(H3N2) and A(H1N1)pdm09 and B lineages. *Influenza Other Respir Viruses*. [PMC10279999](https://pmc.ncbi.nlm.nih.gov/articles/PMC10279999/)
- [F9] Writing Committee of the WHO Consultation on Clinical Aspects of Pandemic (H1N1) 2009 Influenza (2010). Clinical aspects of pandemic 2009 influenza A (H1N1) virus infection. *NEJM* 362:1708-1719. [doi:10.1056/NEJMra1000449](https://doi.org/10.1056/NEJMra1000449)
- [F10] CDC (2019). 2009 H1N1 Pandemic summary. [CDC](https://archive.cdc.gov/www_cdc_gov/flu/pandemic-resources/2009-h1n1-pandemic.html)

## Disease Coupling References

- [M1] Goldberg Y et al. (2021). Duration of SARS-CoV-2 natural immunity and protection against the Delta variant: a retrospective cohort study. *JAMA Intern Med*. [PMC8690283](https://pmc.ncbi.nlm.nih.gov/articles/PMC8690283/)
- [M2] Planas D et al. (2021). Reduced sensitivity of SARS-CoV-2 variant Delta to antibody neutralization. *Nature*. [doi:10.1038/s41586-021-03777-9](https://doi.org/10.1038/s41586-021-03777-9)
- [M3] Bobrovitz N et al. (2023). Past SARS-CoV-2 infection protection against re-infection: a systematic review and meta-analysis. *Lancet*. [doi:10.1016/S0140-6736(22)02465-5](https://doi.org/10.1016/S0140-6736(22)02465-5)
- [M4] Zheng J et al. (2022). The role of respiratory co-infection with influenza or RSV in the clinical severity of COVID-19 patients: a systematic review and meta-analysis. *J Glob Health*. [doi:10.7189/jogh.12.05040](https://doi.org/10.7189/jogh.12.05040)
- [M5] Gao YD et al. (2023). Prevalence and associated outcomes of coinfection between SARS-CoV-2 and influenza: a systematic review and meta-analysis. *Int J Infect Dis*. [doi:10.1016/j.ijid.2023.08.009](https://doi.org/10.1016/j.ijid.2023.08.009)
- [M6] Dee K et al. (2024). Viral interference between SARS-CoV-2 and influenza A viruses. *PLoS Pathog*. [doi:10.1371/journal.ppat.1012017](https://doi.org/10.1371/journal.ppat.1012017)
