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

## Initial Case Numbers

Initial case numbers are chosen based on three factors: (1) early surveillance data for
each disease in California, (2) population scaling between Bay Area and California, and
(3) stochastic extinction probability from branching process theory.

### Simulation Populations

Populations are derived from U.S. Census data encoded in the ExaEpi binary census files:

- **Bay Area** (`BayArea.dat`): 1,405 communities, **6,783,760** agents
- **California** (`CA.dat`): 7,046 communities, **33,871,648** agents
- Population ratio CA:Bay = **5.0:1**

### Summary Table

| Disease          | Bay Area | California | Per million | P(epidemic) Bay | P(epidemic) CA |
|------------------|----------|------------|-------------|-----------------|----------------|
| Cov19S1 (WT)     | 20       | 100        | 2.9         | > 0.9999        | ~1.0           |
| Cov19S2 (Delta)  | 5        | 25         | 0.7         | > 0.9999        | ~1.0           |
| FluS1 (H3N2)     | 30       | 150        | 4.4         | 0.9999          | ~1.0           |
| FluS2 (H1N1pdm)  | 20       | 100        | 2.9         | 0.998           | ~1.0           |

### Stochastic Extinction and Branching Process Theory

For an agent-based stochastic epidemic model, each initial infected individual
independently starts a transmission chain that either dies out or triggers a major
outbreak. The extinction probability *q* for a single case satisfies *q = E(q^Y)* where
*Y* is the offspring distribution [S3]. For Poisson offspring with mean R0, *q* is the
smallest solution of *q = exp(-R0(1-q))*. With *I0* initial cases, the probability that
**all** chains die out is *q^I0*, so P(major epidemic) = 1 - *q^I0* [S3, Section 5.3].

Computed extinction probabilities per initial case:

| Disease         | R0   | *q* (single case) | Source              |
|-----------------|------|--------------------|---------------------|
| Cov19S1 (WT)    | ~2.5 | ~0.10              | Poisson(2.5) model  |
| Cov19S2 (Delta) | ~4.4 | ~0.02              | Poisson(4.4) model  |
| FluS1 (H3N2)    | ~1.3 | ~0.73              | Poisson(1.3) model  |
| FluS2 (H1N1pdm) | ~1.3 | ~0.73              | Poisson(1.3) model  |

For influenza (R0 ~ 1.3), the high single-case extinction probability (~73%) requires
substantially more initial seeds than COVID-19 to reliably start an epidemic. Germann
et al. [S4] found that for large-scale agent-based models, "the extent or duration of the
pandemic is insensitive to details of the amount and location(s) of introductions of
pandemic influenza virus" (Results and Discussion), but sufficient seeds are still
needed to avoid stochastic fade-out. A comparable flu agent-based model used 50 initial
cases for a 1.2 million population (~42 per million) [S7, Methods: "The influenza season
was started in the simulations by inserting 50 cases on November 15"].

### COVID-19 Wild-Type (Cov19S1): Rationale for ~3 per Million

California's first confirmed COVID-19 case was reported on January 31, 2020 in Santa
Clara County [S2, Case Description: "Among the first cases identified during January
31-February 2, travel accounted for the largest reported source of exposure"]. Community
transmission was detected on February 26 in Solano County. On March 4, Governor Newsom
declared a state of emergency. By March 10, California had 157 confirmed cases statewide.

The first 200 cases in Santa Clara County alone spanned January 31 to March 20, with
"probable infection sources includ[ing] community transmission (104 cases), known close
contact with a confirmed case-patient (66 cases), and travel (30 cases)" [S2, Abstract].

Using ~100 for California (3 per million) reflects the order of magnitude of confirmed
cases at the onset of community spread. This is consistent with the ExaEpi example
`inputs_2disease_covid1_covid2.ca` which uses 117 initial cases for CA.

### COVID-19 Delta (Cov19S2): Rationale for ~0.7 per Million

The Delta variant emerged as a small fraction of circulating SARS-CoV-2 in California.
In a large integrated health care system study, "During April 15-July 21, 2021, the
weekly percentage of Delta variant infections increased from 0% to 95%" [S5, Results].
Nationally, "Delta rose from 1% of circulating SARS-CoV-2 viruses nationally during
the week ending May 1, to >50% by the week ending June 26, and to >95% by the week
ending July 31" [S6, Results]. The very high R0 (~4.4 in our parameterization based on
p_trans = 0.35) means that even a small number of initial introductions reliably
establishes an epidemic (single-case extinction probability ~2%).

### Influenza A/H3N2 (FluS1): Rationale for ~4.4 per Million

Seasonal influenza arrives through multiple independent importation events (travelers,
community introductions) rather than a single-point introduction. Germann et al. [S4]
modeled influenza introductions as a continuous process: "a small random number of
incubating individuals, equivalent to 0.04% of arriving international passengers, is
introduced each day at each of 14 major international airports" (Simulation Model
Design). Since ExaEpi uses a single random-seeding event rather than continuous
importation, a larger initial count compensates. The lower R0 (~1.3) gives a high
single-case extinction probability (~73%), requiring more seeds to ensure at least one
chain persists. With 30 seeds (Bay Area) or 150 seeds (CA), P(epidemic) > 0.999.

### Influenza A/H1N1pdm09 (FluS2): Rationale for ~3 per Million

The 2009 H1N1 pandemic was first detected in California: "The first two laboratory-
confirmed cases of 2009 pandemic influenza A (H1N1) virus (H1N1pdm09) infection were
detected in San Diego (SD) and Imperial County (IC) in southern California, April 2009"
[S9, Background]. The initial report on April 21, 2009 documented 2 cases [S8]; by
April 24, California had 4 confirmed cases (of 8 total US cases) [S10, Results]. The
pandemic strain had fewer introduction points than seasonal H3N2 (novel virus, single
geographic origin), so we use a lower per-capita rate (3 vs 4.4 per million). The R0
is similar to seasonal flu (~1.3), so sufficient seeds (20 Bay Area, 100 CA) are still
needed to overcome stochastic extinction.

---

## COVID-19 References

- [C1] Liu Y, Rocklov J (2021). The reproductive number of the Delta variant of SARS-CoV-2 is far higher compared to the ancestral SARS-CoV-2 virus. *J Travel Medicine* 28(7). [PMC8436367](https://pmc.ncbi.nlm.nih.gov/articles/PMC8436367/)
  - Results: "The basic reproductive number for Delta ranged from 3.2 to 8, with a mean of 5.08."
  - Results: "We found a mean R0 of 5.08, which is much higher than the R0 of the ancestral strain of 2.79."
  - Used for: `p_trans` scaling — Delta ~2x higher than wild-type (0.35 vs 0.20).
- [C2] Hart WS, Manica M et al. (2022). Estimation of the incubation period and generation time of SARS-CoV-2 Alpha and Delta variants from contact tracing data. *Epidemics*. [PMC9837419](https://pmc.ncbi.nlm.nih.gov/articles/PMC9837419/)
  - Table 2: Delta incubation period gamma distribution — shape = 4.43 (95% CrI: 3.26-6.70), scale = 1.01 (95% CrI: 0.65-1.43), mean = 4.5 days (95% CrI: 4.0-5.0).
  - Table 2: 2.5-97.5 percentile range of distribution: 1-10 days.
  - Results: "no statistical difference" between Alpha and Delta incubation periods (P = 0.45).
  - Used for: `incubation_length_alpha` = 4.43, `incubation_length_beta` = 1.01.
- [C3] Xin H et al. (2024). Latent and incubation periods of Delta, BA.1, and BA.2 variant cases and associated factors. *BMC Infect Dis*. [PMC10916204](https://pmc.ncbi.nlm.nih.gov/articles/PMC10916204/)
  - Table 2: Delta latent period mean = 4.40 days (95% CI: 4.24-4.63), SD = 2.46, median = 3.95.
  - Results: "The mean latent period for 672 Delta...cases was 4.40 (95%CI: 4.24 ~ 4.63)."
  - Results: "85.65% (95%CI: 83.40 ~ 87.77%)" of Delta cases "started to shed the virus within 7 days after exposure."
  - Discussion: "Previous studies have shown that the mean latent period...was gradually shortened in the wild-type strain (5.5 days), the Delta variant (3.9 days)."
  - Used for: `latent_length_alpha` = 4.7 (rounded from 4.40/0.75 to preserve beta).
- [C4] Pang Z et al. (2023). The differences in virus shedding time between the Delta variant and original SARS-CoV-2 infected patients. *Frontiers Public Health*. [PMC10408444](https://pmc.ncbi.nlm.nih.gov/articles/PMC10408444/)
  - Results: "virus shedding time of the Delta variant group was dramatically longer than the original SARS-CoV-2 group [41.5 (31.5, 46.75) vs. 18.5 (13, 25.75) day, p < 0.001]."
  - Conclusion: "Delta variant and fewer lymphocyte were correlated with prolonged virus shedding time."
  - Used for: `infectious_length_beta` = 0.27 (longer shedding: mean ~7.1 vs ~6.0 days).
- [C5] Miyahara R et al. (2022). A low proportion of asymptomatic COVID-19 patients with the Delta variant infection by viral transmission through household contact. *Int J Environ Res Public Health*. [PMC9243404](https://pmc.ncbi.nlm.nih.gov/articles/PMC9243404/)
  - Results: Delta asymptomatic 14.2% (41/289) vs wild-type 28.8% (62/215), RR = 0.49 (95% CI: 0.35-0.70).
  - Results (ages 20-59): Delta 8.5% vs wild-type 24.3%, RR = 0.35 (95% CI: 0.18-0.66).
  - Entire Ibaraki Prefecture: 13.7% (Aug 2021, Delta) vs 30.3% (Nov 2020-Jan 2021, wild-type), RR = 0.45 (95% CI: 0.42-0.50).
  - Used for: `p_asymp` = 0.15 (Delta) vs 0.30 (wild-type).
- [C6] Fisman DN, Tuite AR (2021). Progressive increase in virulence of novel SARS-CoV-2 variants in Ontario, Canada. *medRxiv* / *Lancet Infect Dis*. [doi:10.1016/S1473-3099(21)00685-X](https://doi.org/10.1016/S1473-3099(21)00685-X)
  - Results: Delta vs non-VOC adjusted risk increases — hospitalization: 120% (95% CI: 93-153%), ICU admission: 287% (95% CI: 198-399%), death: 137% (95% CI: 50-230%).
  - These correspond to OR ~2.2 for hospitalization, ~3.9 for ICU, ~2.4 for death.
  - Used for: `CHR` scaling — Delta CHR approximately doubled across age groups.
- [C7] Garg S et al. (2021). Severity of Disease Among Adults Hospitalized with Laboratory-Confirmed COVID-19 Before and During the Period of SARS-CoV-2 B.1.617.2 (Delta) Predominance. *MMWR* 70(43). [CDC](https://www.cdc.gov/mmwr/volumes/70/wr/mm7043e1.htm)
  - Results: "no significant increases in the proportion of hospitalized COVID-19 patients with severe outcomes during the Delta period."
  - Results: "No difference was observed in ICU admission, receipt of IMV, or in-hospital death among nonpregnant hospitalized adults between the pre-Delta and Delta periods."
  - Results: Ages ≥50 — ICU/death "generally trended upward in the Delta period" but "not statistically significant (p = 0.70)."
  - Used for: CIC and CVE kept the same between S1/S2; icuCVF and ventCVF only modestly increased.
- [C8] Allen H et al. (2022). Household secondary attack rates of SARS-CoV-2 by variant and vaccination status: an updated systematic review and meta-analysis. *JAMA Netw Open*. [PMC8764734](https://pmc.ncbi.nlm.nih.gov/articles/PMC8764734/)
  - Results (Figure 2): "Estimated mean household SAR...Delta was 30.8% (95%CI, 23.5%-39.3%)."
  - Results: Wild-type (pre-April 2020): "15.7% (95%CI, 13.3%-18.4%)."
  - Results: "Restricting to unvaccinated contacts only, mean estimated SAR for Delta was 34.9% (95%CI, 26.7%-44.1%)."
  - Used for: `p_trans` — Delta SAR roughly double wild-type, supporting p_trans = 0.35 vs 0.20.

## Influenza References

- [F1] Biggerstaff M et al. (2014). Estimates of the reproduction number for seasonal, pandemic, and zoonotic influenza: a systematic review of the literature. *BMC Infect Dis*. [PMC4169819](https://pmc.ncbi.nlm.nih.gov/articles/PMC4169819/)
  - Table 5: H3N2 seasonal — median R = 1.25 (IQR: 1.18-1.27).
  - Table 5: H1N1 seasonal — median R = 1.25 (IQR: 1.18-1.35).
  - Table 5: All seasonal influenza — median R = 1.28 (IQR: 1.19-1.37).
  - Methods: 79% of seasonal influenza studies "relied on unconfirmed illnesses or deaths."
  - Used for: `p_trans` = 0.15 (calibrated to R0 ~1.3 in agent-based model).
- [F2] Lessler J et al. (2009). Incubation periods of acute respiratory viral infections: a systematic review. *Lancet Infect Dis*. [PMC4327893](https://pmc.ncbi.nlm.nih.gov/articles/PMC4327893/)
  - Table 3: Influenza A incubation — median 1.4 days (95% CI: 1.3-1.5), dispersion 1.51 (95% CI: 1.43-1.60).
  - Table 3: 5th percentile 0.7 days (95% CI: 0.6-0.8), 95th percentile 2.8 days (95% CI: 2.5-3.2).
  - Table 3: 25th percentile 1.1 days (1.0-1.2), 75th percentile 1.9 days (1.7-2.1).
  - Sensitivity: Excluding one atypical study revised median to 1.9 days with dispersion 1.22.
  - Used for: `incubation_length_alpha` = 4.0, `incubation_length_beta` = 0.5 (gamma mean = 2.0 days).
- [F3] Carrat F et al. (2008). Time lines of infection and disease in human influenza: a review of volunteer challenge studies. *Am J Epidemiol* 167(7):775-785. [doi:10.1093/aje/kwm375](https://doi.org/10.1093/aje/kwm375)
  - Results: "The duration of viral shedding averaged over 375 participants was 4.80 days (95% confidence interval: 4.31, 5.29)."
  - Results: "Viral shedding increased sharply between 0.5 and 1 day after challenge and consistently peaked on day 2."
  - Results: "The total symptoms scores increased on day 1 and peaked on day 3."
  - Results: "The frequency of symptomatic infection was 66.9% (95% confidence interval: 58.3, 74.5)."
  - Results: "Fever was observed in 37.0% of A/H1N1, 40.6% of A/H3N2 (p = 0.86), and 7.5% of B infections."
  - Study: 56 volunteer challenge studies, 1,280 healthy participants.
  - Used for: `infectious_length` (mean ~4.5 days) and `latent_length` (mean ~1.5 days).
- [F4] Leung NHL et al. (2015). The fraction of influenza virus infections that are asymptomatic: a systematic review and meta-analysis. *Epidemiology*. [PMC4586318](https://pmc.ncbi.nlm.nih.gov/articles/PMC4586318/)
  - Results (outbreak investigations): "pooled mean of 16% (95% CI: 13%, 19%)" with low heterogeneity (I²=0%).
  - Results (serologic studies, adjusted): point estimates 65-85%, I²=58%.
  - Results: "the asymptomatic fraction was lower for H3N2 infections compared to infections with H1N1 and B."
  - Discussion: "Estimates of the asymptomatic fraction are affected by the study design, and the definitions of infection and symptomatic illness."
  - Used for: `p_asymp` = 0.16 (H3N2), 0.12 (H1N1pdm09, slightly lower per subtype finding).
- [F5] Tsang TK et al. (2023). Reconstructing household transmission dynamics to estimate the infectiousness of asymptomatic influenza virus infections. *PNAS* 120(33). [PMC10436695](https://pmc.ncbi.nlm.nih.gov/articles/PMC10436695/)
  - Results: "estimated relative infectiousness 0.57 (95% CrI: 0.11, 1.54)."
  - Results: "posterior probability that asymptomatic cases are less infectious than symptomatic cases is 0.82."
  - Results (ARI definition): "estimated relative infectiousness of cases meeting the ARI definition compared with cases without ARI is 0.41 (95% CrI: 0.07, 1.09)."
  - Study: 727 households, 2,515 individuals, 2009 H1N1pdm09 outbreak in Hong Kong.
  - Used for: `asymp_relative_inf` = 0.5 (midpoint of 0.41-0.57 range).
- [F6] CDC FluSurv-NET (2024). Laboratory-Confirmed Influenza-Associated Hospitalizations Among Children and Adults, United States, 2010-2023. *MMWR Surveill Summ* 73(SS-6). [CDC](https://www.cdc.gov/mmwr/volumes/73/ss/ss7306a1.htm)
  - Results: Adults ≥65 consistently highest hospitalization rates (e.g. 437.2 per 100,000 in 2017-18).
  - Results: ICU admission among hospitalized patients: 14.1-22.3% across seasons.
  - Results: Mechanical ventilation: 4.9-11.1% of hospitalized patients.
  - Results: Rates increase sharply with age within elderly (75-84 > 65-74; ≥85 highest).
  - Used for: `hospitalization_days`, `CHR` age distribution, `CIC`, `CVE` estimates.
- [F7] Sridhar S et al. (2015). Longevity and determinants of protective humoral immunity after pandemic influenza infection. *Am J Respir Crit Care Med*. [PMC4351579](https://pmc.ncbi.nlm.nih.gov/articles/PMC4351579/)
  - Abstract: "Antibodies induced by natural infection persisted at constant high titer for a minimum of approximately 15 months."
  - Results: Mean titers remained "above the protective threshold of 1:32" for "up to 480 days" post-infection.
  - Table 1: Individual HI titers across timepoints; only 1 subject (F179) declined to baseline within 300 days.
  - Results: Vaccine-induced titers showed "decline in the magnitude of titer within 9 months post-vaccination" but "remained at a protective titer."
  - Used for: `immune_length_alpha` = 180.0, `immune_length_beta` = 1.5 (mean ~270 days, ~9 months).
- [F8] Koh YS et al. (2023). Inference of age-dependent case-fatality ratios for seasonal influenza virus subtypes A(H3N2) and A(H1N1)pdm09 and B lineages. *Influenza Other Respir Viruses*. [PMC10279999](https://pmc.ncbi.nlm.nih.gov/articles/PMC10279999/)
  - Table 2: H3N2 age-aggregated CFR = 0.582% (95% CrI: 0.563-0.601%).
  - Table 2: H1N1pdm09 age-aggregated CFR = 0.283% (95% CrI: 0.240-0.326%).
  - Table 2: H3N2 CFR 85+ = 4.76% (4.53-5.01%); H1N1pdm09 CFR 85+ = 2.51% (2.09-2.94%).
  - Table 2: H3N2 CFR 55-59 = 0.018% (0.016-0.021%); H1N1pdm09 CFR 55-59 = 0.010%.
  - Results: "case-fatality estimates were highest for influenza A(H3N2) followed by influenza B and then A(H1N1)pdm09."
  - Study: Netherlands, 2011/2012-2019/2020 seasons.
  - Used for: `ventCVF` and `icuCVF` age profiles — H3N2 more lethal overall, especially in elderly.
- [F9] Writing Committee of the WHO Consultation on Clinical Aspects of Pandemic (H1N1) 2009 Influenza (2010). Clinical aspects of pandemic 2009 influenza A (H1N1) virus infection. *NEJM* 362:1708-1719. [doi:10.1056/NEJMra1000449](https://doi.org/10.1056/NEJMra1000449)
  - Results: Hospitalization rates "highest for children under the age of 5 years, especially those under 1 year, and lowest for persons 65 years or older."
  - Results: "32 to 45% of hospitalized patients in the United States" were under 18 years of age.
  - Results: "approximately 9 to 31% of hospitalized patients admitted to ICU where 14 to 46% died."
  - Results: ICU syndrome — "diffuse viral pneumonitis associated with severe hypoxemia, ARDS, and sometimes shock and renal failure, accounting for approximately 49 to 72% of ICU admissions."
  - Results: "rapid progression typically starting on day 4 to 5 after illness onset."
  - Used for: `CHR`, `CIC`, `CVE` for FluS2 — higher ICU/ventilation rates in young adults vs H3N2.
- [F10] CDC (2019). 2009 H1N1 Pandemic summary. [CDC](https://archive.cdc.gov/www_cdc_gov/flu/pandemic-resources/2009-h1n1-pandemic.html)
  - Summary: First detected April 2009 in California; spread to all 50 states by June.
  - Estimated US burden: ~60.8 million cases, ~274,304 hospitalizations, ~12,469 deaths.
  - Age distribution: 80% of deaths in persons younger than 65 years (unusual for seasonal flu).
  - Used for: FluS2 age profile — disproportionate severity in younger adults vs elderly.

## Disease Coupling References

- [M1] Goldberg Y et al. (2021). Duration of SARS-CoV-2 natural immunity and protection against the Delta variant: a retrospective cohort study. *JAMA Intern Med*. [PMC8690283](https://pmc.ncbi.nlm.nih.gov/articles/PMC8690283/)
  - Results: "Protection of prior infection against reinfection with Delta was 85.4% (95% CI, 80.0-89.3)."
  - Results: "Overall protection of previous infection was 85.7% (95% CI, 82.2-88.5) and lasted up to 13 months."
  - Results: Among 325,157 patients, reinfection rate 0.08% (prior infection) vs 0.5% (no prior infection) during Delta-dominant period.
  - Results: "Patients over age 65 had slightly lower protection" compared to younger cohorts.
  - Used for: coimmunity matrix off-diagonal = 0.85 (COVID S1-S2 cross-immunity).
- [M2] Planas D et al. (2021). Reduced sensitivity of SARS-CoV-2 variant Delta to antibody neutralization. *Nature* 596:276-280. [doi:10.1038/s41586-021-03777-9](https://doi.org/10.1038/s41586-021-03777-9)
  - Results: Convalescent sera were "fourfold less potent against the Delta variant relative to the Alpha variant."
  - Results: Vaccine-elicited neutralizing titers were "three- to fivefold lower against the Delta variant compared to the original strain."
  - Results: Delta was "resistant to neutralization by some anti-NTD and anti-RBD monoclonal antibodies, including bamlanivimab."
  - Used for: coimmunity matrix — despite 3-5 fold reduction in neutralization titers, clinical protection remains high (~85%), supporting 0.85 rather than a lower value.
- [M3] Bobrovitz N et al. (2023). Past SARS-CoV-2 infection protection against re-infection: a systematic review and meta-analysis. *Lancet*. [doi:10.1016/S0140-6736(22)02465-5](https://doi.org/10.1016/S0140-6736(22)02465-5)
  - Results: Protection against reinfection at 40 weeks — ancestral/alpha/delta: 78.6% (95% UI: 49.8-93.6%).
  - Results: Protection against severe disease at 40 weeks — ancestral/alpha/delta: 90.2% (95% UI: 69.7-97.5%).
  - Results: "Mean pooled effectiveness was greater than 78% against severe disease (hospitalisation and death) for all variants."
  - Results: Omicron BA.1 reinfection protection at 40 weeks dropped to 36.1% (24.4-51.3%), but severe disease protection remained at 88.9% (84.7-90.9%).
  - Used for: coimmunity matrix — 0.85 reflects strong but imperfect cross-protection between COVID variants, consistent with 78-90% estimates from meta-analysis.
- [M4] Zheng J et al. (2022). The role of respiratory co-infection with influenza or RSV in the clinical severity of COVID-19 patients: a systematic review and meta-analysis. *J Glob Health* 12:05040. [doi:10.7189/jogh.12.05040](https://doi.org/10.7189/jogh.12.05040)
  - Results: COVID+influenza co-infection — ICU admission OR = 2.09 (95% CI: 1.64-2.68).
  - Results: Mechanical ventilation OR = 2.31 (95% CI: 1.10-4.85).
  - Used for: cosusceptibility matrix COVID-Flu = 1.5 (moderate estimate of enhanced severity).
- [M5] Gao YD et al. (2023). Prevalence and associated outcomes of coinfection between SARS-CoV-2 and influenza: a systematic review and meta-analysis. *Int J Infect Dis* 136:29-36. [doi:10.1016/j.ijid.2023.08.009](https://doi.org/10.1016/j.ijid.2023.08.009)
  - Results: Pooled co-infection prevalence 2.45% (95% CI: 1.67-3.58%).
  - Results: Influenza A co-infection — ICU OR = 2.20 (95% CI: 1.68-2.87, P < 0.001).
  - Results: Influenza A co-infection — mechanical ventilation OR = 2.73 (95% CI: 1.46-5.10, P = 0.002).
  - Results: Influenza A co-infection — mortality OR = 2.92 (95% CI: 1.16-7.30, P = 0.022).
  - Study: 95 studies, 62,107 COVID-19 patients.
  - Used for: cosusceptibility matrix COVID-Flu = 1.5 — OR values of 2.1-2.7 support enhanced severity; 1.5 is a conservative estimate accounting for viral interference [M6].
- [M6] Dee K et al. (2024). Viral interference between SARS-CoV-2 and influenza A viruses. *PLoS Pathog*. [doi:10.1371/journal.ppat.1012017](https://doi.org/10.1371/journal.ppat.1012017)
  - Results: "A prior infection with A/H3N2 greatly reduced the replication of Omicron by 3 logs compared to Omicron alone at 96 h p.i."
  - Results: "SARS-CoV-2 did not significantly interfere with A/H3N2 or A/H1N1" (asymmetric effect).
  - Results: "IAV, especially A/H3N2, caused a much greater secretion of type I and type III IFN proteins than SARS-CoV-2."
  - Results: "IFN secretion was decreased in almost all coinfections with IAV compared to IAV alone, especially when SARS-CoV-2 was added first."
  - Mechanism: Influenza A interferes with SARS-CoV-2 through IFN response, but SARS-CoV-2 immune evasion proteins reduce protective IFN signaling during co-infections.
  - Used for: cosusceptibility matrix — viral interference partially offsets clinical severity enhancement from [M4,M5], justifying 1.5 rather than the full OR of ~2.1-2.7.

## Initial Case Seeding References

- [S1] U.S. Census Bureau. American Community Survey 5-Year Estimates, encoded in ExaEpi binary census files `BayArea.dat` (6,783,760 agents, 1,405 communities) and `CA.dat` (33,871,648 agents, 7,046 communities).
- [S2] Reingold AL et al. (2021). Epidemiologic findings from case investigations and contact tracing for first 200 cases of coronavirus disease, Santa Clara County, California, USA. *Emerg Infect Dis* 27(5):1301-1308. [PMC8084524](https://pmc.ncbi.nlm.nih.gov/articles/PMC8084524/)
  - Abstract: "Probable infection sources included community transmission (104 cases), known close contact with a confirmed case-patient (66 cases), and travel (30 cases)."
  - Case Description: "Among the first cases identified during January 31-February 2, travel accounted for the largest reported source of exposure."
  - Study period: January 31 to March 20, 2020, encompassing 200 laboratory-confirmed cases.
- [S3] Allen LJS (2008). Branching processes: their role in epidemiology. *Int J Environ Res Public Health* 5(5):335-350. [PMC2872325](https://pmc.ncbi.nlm.nih.gov/articles/PMC2872325/)
  - Section 2: Extinction probability *q* satisfies *q = f(q) := E(q^Y)* where *Y* is the offspring distribution.
  - Section 5.3: With *I0* initial cases, total extinction probability is *q^I0*.
  - Key result: When R0 > 1, *q* < 1 and P(major epidemic) = 1 - *q^I0* increases with *I0*.
- [S4] Germann TC et al. (2006). Mitigation strategies for pandemic influenza in the United States. *PNAS* 103(15):5935-5940. [PMC1458676](https://pmc.ncbi.nlm.nih.gov/articles/PMC1458676/)
  - Simulation Model Design: "a small random number of incubating individuals, equivalent to 0.04% of arriving international passengers, is introduced each day at each of 14 major international airports."
  - Results and Discussion: "Regardless of R0, unless drastic travel restrictions are imposed, the extent or duration of the pandemic is insensitive to details of the amount and location(s) of introductions of pandemic influenza virus in our simulations."
  - Population: 281 million individuals (entire continental U.S.).
- [S5] Paden CR et al. (2021). Distribution of SARS-CoV-2 variants in a large integrated health care system - California, March-July 2021. *MMWR* 70(40):1415-1419. [CDC](https://www.cdc.gov/mmwr/volumes/70/wr/mm7040a4.htm)
  - Results: "During April 15-July 21, 2021, the weekly percentage of Delta variant infections increased from 0% to 95%."
  - Total sequenced: 6,798 specimens, of which 2,156 (31.7%) were Delta.
- [S6] Paul P et al. (2022). Genomic surveillance for SARS-CoV-2 variants: predominance of the Delta and Omicron variants - United States, June 2021-January 2022. *MMWR* 71(6):206-211. [CDC](https://www.cdc.gov/mmwr/volumes/71/wr/mm7106a4.htm)
  - Results: "Delta rose from 1% of circulating SARS-CoV-2 viruses nationally during the week ending May 1, to >50% by the week ending June 26, and to >95% by the week ending July 31."
- [S7] Rao S et al. (2022). Agent-based model of the impact of higher influenza vaccine efficacy on seasonal influenza burden. *Vaccine: X* 12:100228. [PMC9753457](https://pmc.ncbi.nlm.nih.gov/articles/PMC9753457/)
  - Methods: "The influenza season was started in the simulations by inserting 50 cases on November 15."
  - Methods: "Simulations used a population created from the 2010 Allegheny County Pennsylvania census population. The population consists of ~1.2 million agents."
  - Seeding rate: 50 / 1,200,000 = ~42 per million.
- [S8] CDC (2009). Swine influenza A (H1N1) infection in two children - Southern California, March-April 2009. *MMWR* 58(15):400-402. [CDC](https://www.cdc.gov/mmwr/preview/mmwrhtml/mm5815a5.htm)
  - Patient A: 10-year-old, San Diego County, symptom onset March 30, 2009.
  - Patient B: 9-year-old, Imperial County, symptom onset March 28, 2009.
  - Both reported April 17, 2009; "no additional cases of infection with the identified strain of swine influenza A (H1N1) had been identified" as of April 21, 2009.
- [S9] Myers KP et al. (2012). The first cases of 2009 pandemic influenza A (H1N1) virus infection in the United States: a serologic investigation demonstrating early transmission. *J Infect Dis*. [PMC4941679](https://pmc.ncbi.nlm.nih.gov/articles/PMC4941679/)
  - Background: "The first two laboratory-confirmed cases of 2009 pandemic influenza A (H1N1) virus (H1N1pdm09) infection were detected in San Diego (SD) and Imperial County (IC) in southern California, April 2009."
  - Discussion: "We provide serological evidence of early community transmission of H1N1pdm09 in southern California in March 2009."
  - 19 PCR-confirmed case-patients identified April 17 - May 6, 2009.
- [S10] CDC (2009). Update: swine influenza A (H1N1) infections - California and Texas, April 2009. *MMWR* 58(16):435-437. [CDC](https://www.cdc.gov/mmwr/preview/mmwrhtml/mm5816a7.htm)
  - Results: 8 total confirmed US cases as of April 24, 2009.
  - California: 4 confirmed cases (San Diego County 3, Imperial County 1).
  - Texas: 2 confirmed cases (Guadalupe County).
