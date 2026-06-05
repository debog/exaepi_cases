# Data

This directory is intentionally (almost) empty. The decks pull their data
from the ExaEpi source tree at run time — the runner finds files by name
under `$EXAEPI_DIR/data` and copies them into each run directory. Nothing
large is duplicated here.

Files each deck references (all under `$EXAEPI_DIR/data/`):

| File | Location | Used by |
|---|---|---|
| `BayArea.dat` | `CensusData/` | all decks (census population) |
| `BayArea-wf.bin` | `CensusData/` | all decks (worker flow) |
| `BayArea_hospitals_2020.dat` | `HospitalData/` | `H1`, `H2`, `H3` (county beds) |
| `BayArea_hospitals_tract_2020.dat` | `HospitalData/` | `combined` (tract beds + routing) |

The hospital data files are HHS staffed-bed counts for the week of
2020-09-27 (a non-surge baseline), built by
`$EXAEPI_DIR/utilities/build_hospital_data.py`. Regenerate for a different
week or region with that script.

To pin a specific data file locally, drop it in this directory — the runner
searches here first.
