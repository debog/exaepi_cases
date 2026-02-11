# ExaEpi Plotting Scripts

## plot_infections_map.py

Plots infection counts from ExaEpi simulation runs on a US county choropleth map.

### Setup

```bash
pip install -r requirements.txt
```

### Usage

```bash
# Plot every 10th day (default):
./plot_infections_map.py <run_directory>

# Plot specific days:
./plot_infections_map.py .run_US_01D_Cov19S1_perlmutter --steps 0 10 30 50 70

# Consistent color scale across all frames:
./plot_infections_map.py .run_US_01D_Cov19S1_perlmutter --global-vmax

# Custom output directory (default: ../plots/):
./plot_infections_map.py .run_US_01D_Cov19S1_perlmutter --outdir my_plots
```

Output PNGs are saved to `../plots/` by default. The US county shapefile is downloaded from the Census Bureau on first run and cached locally in `scripts/`.
