# Comparison of ExaEpi Cov19S1 parameters with Epicast 2.0

Reference: Alexander et al. (2025), "Epicast 2.0: A Large-Scale, Demographically
Detailed, Agent-Based Model for Simulating Respiratory Pathogen Spread in the
United States," arXiv:2504.03604v1.

## Transmission

| Parameter | Epicast 2.0 (paper) | ExaEpi Cov19S1 |
|-----------|---------------------|----------------|
| P_trans   | 0.06 -- 0.08        | 0.20           |

P_trans is 2.5--3.3x higher in ExaEpi. However, the transmission models differ:
Epicast 2.0 uses IISF-based venue contact intensities (Tables 6--7 in paper) that
are much larger than ExaEpi's `xmit_*` values, so the effective per-contact
transmission is scaled differently.

## Venue contact intensities (IISF vs xmit)

Age groups: Epicast 2.0 uses 5 (0-5, 6-17, 18-29, 30-64, 65+); ExaEpi uses 6
(U5, 5-17, 18-29, 30-49, 50-64, 65+), splitting 30-64 into two groups.

| Venue | Epicast 2.0 IISF | ExaEpi xmit | Ratio |
|-------|-------------------|-------------|-------|
| Household (child)    | 0.6, 0.6, 0.3, 0.3, 0.3               | 0.6, 0.6, 0.3, 0.3, 0.3, 0.3                   | identical       |
| Household (adult)    | 0.3, 0.3, 0.4, 0.4, 0.4               | 0.3, 0.3, 0.4, 0.4, 0.4, 0.4                   | identical       |
| HH-cluster (child)   | 0.2475, 0.2475, 0.132, 0.132, 0.132   | 0.1, 0.1, 0.0528, 0.0528, 0.0528, 0.0528       | ExaEpi = 0.4x  |
| HH-cluster (adult)   | 0.132, 0.132, 0.165, 0.165, 0.165     | 0.0528, 0.0528, 0.066, 0.066, 0.066, 0.066     | ExaEpi = 0.4x  |
| Neighborhood         | 0.000082..0.00099                      | 0.000086..0.001                                  | ~same           |
| Community            | 0.000021..0.000247                     | 0.000015..0.00025                                | ~same           |
| Work                 | 0.07475                                | 0.0575                                           | ExaEpi = 0.77x |
| School (high)        | 0.441                                  | 0.0315                                           | ExaEpi = 0.071x |
| School (middle)      | 0.525                                  | 0.0375                                           | ExaEpi = 0.071x |
| School (elementary)  | 0.609                                  | 0.0435                                           | ExaEpi = 0.071x |
| School (pre-k)       | 0.15                                   | 0.15                                             | identical       |

School IISF values differ by ~14x, but ExaEpi's higher P_trans partially
compensates. Effective school transmission (P_trans * IISF):
  - Paper (high school):  0.08 * 0.441  = 0.035
  - ExaEpi (high school): 0.20 * 0.0315 = 0.0063
Effective school transmission is still ~5.6x lower in ExaEpi.

## Disease natural history

| Parameter            | Epicast 2.0                         | ExaEpi Cov19S1                         |
|----------------------|-------------------------------------|----------------------------------------|
| Exposed (latent)     | 1--7 days (discrete CDF, Fig 6A)   | gamma(5.2, 0.75), mean 3.9 days       |
| Pre-symptomatic      | 1 day (all agents)                  | Part of incubation model               |
| Infectious duration  | 3--9 days (discrete CDF, Fig 6B)   | gamma(26.2, 0.23), mean 6.0 days      |
| Incubation           | Exposed + 1 day pre-symp            | gamma(7.5, 0.65), mean 4.9 days       |
| p_asymp              | user-defined (not stated for demos) | 0.30                                   |
| asymp_relative_inf   | shared w/ pre-symp shedding         | 0.7                                    |
| Immune period        | user-defined (reinfection optional) | gamma(540, 0.33), mean 178 days       |

## Hospitalization parameters (nearly identical)

| Parameter | Epicast 2.0 (Table 4)          | ExaEpi Cov19S1                    |
|-----------|-------------------------------|-----------------------------------|
| CHR       | 0.0104, 0.0104, 0.07, 0.28, 1.0       | 0.0104, 0.0104, 0.07, 0.28, 0.28, 1.0       |
| CIC       | 0.24, 0.24, 0.24, 0.36, 0.35          | 0.24, 0.24, 0.24, 0.36, 0.36, 0.35          |
| CVE       | 0.12, 0.12, 0.12, 0.22, 0.22          | 0.12, 0.12, 0.12, 0.22, 0.22, 0.22          |
| hospCVF   | 0, 0, 0, 0, 0                         | 0, 0, 0, 0, 0, 0                            |
| icuCVF    | 0, 0, 0, 0, 0.26                      | 0, 0, 0, 0, 0, 0.26                         |
| ventCVF   | 0.2, 0.2, 0.2, 0.45, 1.0              | 0.2, 0.2, 0.2, 0.45, 0.45, 1.0              |

Hospitalization parameters are essentially identical. ExaEpi splits the paper's
"Age 30-64" group into 30-49 and 50-64, duplicating the values.

## Withdrawal probabilities (identical)

|         | Day 0 | Day 1 | Day 2 |
|---------|-------|-------|-------|
| Age 0-5  | 0.3 | 0.8 | 0.9 |
| Age 6-17 | 0.3 | 0.7 | 0.8 |
| Age 18+  | 0.3 | 0.5 | 0.7 |

Both use the same Day 0/1/2 compliance values (Table 5 in paper).

## Key structural differences

1. **Age groups**: Paper uses 5 (0-5, 6-17, 18-29, 30-64, 65+); ExaEpi uses 6
   (splitting 30-64 into 30-49 and 50-64).
2. **Time step**: Paper uses 12-hour steps (day/night); ExaEpi uses daily steps.
3. **Initial immunity**: Paper supports it natively (Section 2.8.1, Table 8:
   per-county FIPS file with `# index cases` and `# immune` columns). ExaEpi
   does not currently support initializing agents as immune.

## Summary

The hospitalization cascade and withdrawal parameters are taken directly from
the paper. The main differences are in transmission: ExaEpi uses a higher P_trans
but much lower school and work IISF values, resulting in different effective
transmission rates across venues. The household-cluster values are systematically
0.4x the paper's values. The disease natural history distributions are similar in
mean but use different functional forms (gamma vs discrete CDF).
