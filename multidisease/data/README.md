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

- **Total cases**: 1,085 across 48 counties (~3.3 per million US pop)
- **Geographic clusters**:
  - **Primary — Southeast US (GA/NC/SC/TN)**: Atlanta metro (Fulton Co. 85,
    DeKalb Co. 60, Gwinnett Co. 55), Charlotte-Raleigh corridor in NC, upstate SC,
    Nashville and Knoxville TN
  - **Florida**: Miami-Dade (30), Broward (20), Tampa (15), Orlando (15), Jacksonville (10)
  - **Midwest**: Chicago (Cook Co. 40, DuPage 15), Detroit (Wayne 20, Oakland 12),
    Minneapolis (Hennepin 18, Ramsey 10), Indianapolis (15), Columbus (15), Cleveland (12)
  - **Northeast**: Philadelphia (25), Boston (Suffolk 15, Middlesex 12), Pittsburgh (12)
- **Rationale**: Seasonal flu seeds via multiple independent introductions across
  major metro areas. H3N2 seasons often begin in the Southeast.
- **References**: [S4] CDC FluView regional data; [S7] Garten et al. (2018)

### Jan1_FluS2.cases — Influenza A/H1N1pdm09

- **Total cases**: 977 across 41 counties (~3.0 per million US pop)
- **Geographic clusters**:
  - **Primary — Southwest US (SoCal/AZ)**: Los Angeles Co. (130), Maricopa Co. AZ (85),
    Orange Co. (65), San Diego (55), Inland Empire, Central Valley, southern NV/NM
  - **Bay Area**: Alameda (20), Santa Clara (18), San Francisco (15), Sacramento (15)
  - **Pacific Northwest**: Seattle (King Co. 25, Pierce 10, Snohomish 8),
    Portland (Multnomah 15, Washington Co. 10)
  - **Colorado**: Denver (18), Arapahoe (10), Jefferson (8)
  - **Utah**: Salt Lake (15), Utah Co. (8)
  - **Texas**: Houston (Harris 25), Dallas (20), San Antonio (Bexar 15), Austin (Travis 12)
- **Rationale**: H1N1pdm09 first identified in Southern California (April 2009),
  with subsequent spread to western US metro areas and Texas.
- **References**: [S8] CDC (2019), 2009 H1N1 Pandemic summary; [S9] Fraser et al. (2009), Science
