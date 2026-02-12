# Initial Case Data Files

Initial infection seed files for US-scale ExaEpi simulations. Each file specifies
per-county case counts using FIPS codes, representing geographically clustered
outbreak origins consistent with historical emergence patterns.

## File Format

Plain text, two columns per line:
```
FIPS_code  num_cases
```
where `FIPS_code` is a 4- or 5-digit county FIPS code and `num_cases` is the
number of initially infected agents assigned to that county.

Used with the input file parameters:
```
disease.initial_case_type = "file"
disease.case_filename = "<filename>"
```

## Files

### Jan1_Cov19S1.cases — SARS-CoV-2 Ancestral/Wild-Type

- **Total cases**: 1,000 across 23 counties (~3 per million US pop)
- **Geographic cluster**: Northeast US (NY metro area)
- **Rationale**: ~1,000 confirmed cases at community-spread onset (early March 2020).
  Cases concentrated in New York City (Manhattan 180, Brooklyn 150, Queens 120,
  Bronx 90), surrounding NJ counties, CT, and a secondary cluster in WA (Seattle).
- **References**: [S1] Li et al. (2020), NEJM; [S2] CDC COVID Data Tracker

### Jan1_Cov19S2.cases — SARS-CoV-2 Delta Variant (B.1.617.2)

- **Total cases**: 250 across 17 counties (~0.7 per million US pop)
- **Geographic cluster**: Texas / Gulf South
- **Rationale**: Delta emerged as a small fraction (~1-5%) of sequenced cases,
  with early clusters in Texas. Cases concentrated in Houston (Harris Co. 45,
  Dallas Co. 35), with secondary spread across TX counties and Louisiana.
- **References**: [S5] Dougherty et al. (2021), MMWR; [S6] outbreak.info variant tracker

### Jan1_FluS1.cases — Seasonal Influenza A/H3N2

- **Total cases**: 759 across 29 counties (~2.3 per million US pop)
- **Geographic cluster**: Southeast US (Georgia / Carolinas)
- **Rationale**: Seasonal flu seeds via multiple independent introductions.
  H3N2 seasons often begin in the Southeast. Cases concentrated in Atlanta
  metro (Fulton Co. 85, DeKalb Co. 60, Gwinnett Co. 55), Charlotte-Raleigh
  corridor in NC, and upstate SC.
- **References**: [S4] CDC FluView regional data; [S7] Garten et al. (2018)

### Jan1_FluS2.cases — Influenza A/H1N1pdm09

- **Total cases**: 710 across 23 counties (~2.2 per million US pop)
- **Geographic cluster**: Southwest US (Southern California / Arizona)
- **Rationale**: H1N1pdm09 first identified in Southern California (April 2009).
  Cases concentrated in Los Angeles Co. (130), Orange Co. (65), San Diego Co. (55),
  Maricopa Co. AZ (85), with secondary spread across the Inland Empire,
  Central Valley, and southern NV/NM.
- **References**: [S8] CDC (2019), 2009 H1N1 Pandemic summary; [S9] Fraser et al. (2009), Science
