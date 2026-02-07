# Multi-Disease Input Files

## Strains

- **S1**: Ancestral/wild-type SARS-CoV-2 (parameters from EpiCast)
- **S2**: Delta variant (B.1.617.2)

## Parameter Differences: S1 (Wild-Type) vs S2 (Delta)

| Parameter | S1 (wild-type) | S2 (Delta) | Rationale |
|---|---|---|---|
| `p_trans` | 0.20 | 0.35 | ~2x higher R0, driven by higher viral loads [1,8] |
| `p_asymp` | 0.30 | 0.15 | Lower asymptomatic fraction observed for Delta [5] |
| `latent_length_alpha` | 5.2 | 4.7 | Shorter latent period, proportional to shorter incubation [3] |
| `infectious_length_beta` | 0.23 | 0.27 | Longer culture-positive duration: ~7 vs ~4 days [4] |
| `incubation_length_alpha` | 7.5 | 4.43 | Gamma fit from contact tracing data [2] |
| `incubation_length_beta` | 0.65 | 1.01 | Gamma fit from contact tracing data [2] |
| `CHR` | 0.0104 0.0104 0.070 0.28 0.28 1.0 | 0.0201 0.0201 0.135 0.54 0.54 1.0 | HR ~1.93 for hospitalization [6] |
| `icuCVF` | 0 0 0 0 0 0.26 | 0 0 0 0 0 0.30 | Modestly higher mortality [6,7] |
| `ventCVF` | 0.20 0.20 0.20 0.45 0.45 1.0 | 0.25 0.25 0.25 0.55 0.55 1.0 | Modestly higher mortality [6,7] |

All other parameters (contact structure, immune period, CIC, CVE, etc.) are kept the same
due to insufficient variant-specific data or no statistically significant difference
between pre-Delta and Delta periods [7].

## References

1. Liu Y, Rocklov J (2021). The reproductive number of the Delta variant of SARS-CoV-2 is far higher compared to the ancestral SARS-CoV-2 virus. *J Travel Medicine* 28(7). [doi:10.1093/jtm/taab124](https://doi.org/10.1093/jtm/taab124)
2. Hart WS et al. (2022). Estimation of the incubation period and generation time of SARS-CoV-2 Alpha and Delta variants from contact tracing data. *Epidemics*. [PMC9837419](https://pmc.ncbi.nlm.nih.gov/articles/PMC9837419/)
3. Xin H et al. (2024). Latent and incubation periods of Delta, BA.1, and BA.2 variant cases and associated factors. *BMC Infect Dis*. [PMC10916204](https://pmc.ncbi.nlm.nih.gov/articles/PMC10916204/)
4. Pang Z et al. (2023). The differences in virus shedding time between the Delta variant and original SARS-CoV-2 infected patients. *Frontiers Public Health*. [PMC10408444](https://pmc.ncbi.nlm.nih.gov/articles/PMC10408444/)
5. Miyahara R et al. (2022). A low proportion of asymptomatic COVID-19 patients with the Delta variant infection by viral transmission through household contact. *Int J Environ Res Public Health*. [PMC9243404](https://pmc.ncbi.nlm.nih.gov/articles/PMC9243404/)
6. Fisman DN, Tuite AR (2021). Increased risk of hospitalisation and death with the delta variant in the USA. *Lancet Infect Dis*. [doi:10.1016/S1473-3099(21)00685-X](https://doi.org/10.1016/S1473-3099(21)00685-X)
7. Garg S et al. (2021). Severity of Disease Among Adults Hospitalized with Laboratory-Confirmed COVID-19 Before and During the Period of SARS-CoV-2 B.1.617.2 (Delta) Predominance. *MMWR* 70(43). [CDC](https://www.cdc.gov/mmwr/volumes/70/wr/mm7043e1.htm)
8. Allen H et al. (2022). Household secondary attack rates of SARS-CoV-2 by variant and vaccination status: an updated systematic review and meta-analysis. *JAMA Netw Open*. [PMC8764734](https://pmc.ncbi.nlm.nih.gov/articles/PMC8764734/)
