#!/usr/bin/env python3
"""
analyze_sensitivity.py - Analyze sensitivity analysis results for ExaEpi multi-disease paper.

Reads ensemble output from sensitivity runs and produces:
  1. Time-series plots: infection trajectories for each parameter value (overlaid)
  2. Summary bar/line plots: peak magnitude, peak timing, cumulative deaths,
     and number of recurrent waves as a function of the swept parameter
  3. Printed table of key metrics for inclusion in the paper

Usage:
    python3 analyze_sensitivity.py [--data-dir DIR] [--output-dir DIR] [--format pdf|png]

The script looks for ensemble results in:
    <data-dir>/.ensemble_<case>_tuolumne/   (or _matrix)
with per-run output files in run_NNN/output_<Disease>.dat

If ensemble directories are not found, it falls back to reading
pre-computed output_mean.dat and output_std.dat files.
"""

import argparse
import os
import sys
import glob
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter
from collections import OrderedDict

# ─── Configuration ───────────────────────────────────────────────────────────

# Column indices in output.dat (0-based)
COL_DAY   = 0
COL_SU    = 1
COL_NEWI  = 16
COL_D     = 15
COL_R     = 14
# Infected compartments: PS/PI(2) S/PI/NH(3) S/PI/H(4) PS/I(5) S/I/NH(6)
#   S/I/H(7) A/PI(8) A/I(9) H/NI(10) H/I(11)
INFECTED_COLS = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
HOSP_COLS = [10, 11, 12, 13]  # H/NI, H/I, ICU, V

# Sweep definitions
COIMM_SWEEP = OrderedDict([
    (0.50,  "CA_02D_Cov19S1S2_coimm050"),
    (0.70,  "CA_02D_Cov19S1S2_coimm070"),
    (0.85,  "CA_02D_Cov19S1S2_coimm085"),
    (0.925, "CA_02D_Cov19S1S2_coimm0925"),
    (1.00,  "CA_02D_Cov19S1S2_coimm100"),
])

COSUS_SWEEP = OrderedDict([
    (0.75, "CA_02D_Cov19S1_FluS1_cosus075"),
    (1.0,  "CA_02D_Cov19S1_FluS1_cosus100"),
    (1.5,  "CA_02D_Cov19S1_FluS1_cosus150"),
    (2.0,  "CA_02D_Cov19S1_FluS1_cosus200"),
    (3.0,  "CA_02D_Cov19S1_FluS1_cosus300"),
])

COIMM_DISEASES  = ["Cov19S1", "Cov19S2"]
COSUS_DISEASES  = ["Cov19S1", "FluS1"]

DISEASE_COLORS = {
    "Cov19S1": "#1f77b4",  # blue
    "Cov19S2": "#d62728",  # red
    "FluS1":   "#2ca02c",  # green
}

DISEASE_LABELS = {
    "Cov19S1": "Cov19-S1",
    "Cov19S2": "Cov19-S2",
    "FluS1":   "Flu-S1",
}

# ─── Data loading ────────────────────────────────────────────────────────────

def find_ensemble_dir(data_dir, case_name):
    """Find ensemble directory for a case, trying multiple platform suffixes."""
    for suffix in ["tuolumne", "matrix", "dane", "perlmutter"]:
        d = os.path.join(data_dir, f".ensemble_{case_name}_{suffix}")
        if os.path.isdir(d):
            return d
    # Also check without platform suffix (local sensitivity dir)
    d = os.path.join(data_dir, f".ensemble_{case_name}")
    if os.path.isdir(d):
        return d
    return None


def load_ensemble(ensemble_dir, disease_name, max_runs=200):
    """Load per-realization data for a disease from an ensemble directory.

    Returns: (days, stacked_data) where stacked_data has shape (n_runs, n_days, n_cols)
             or (None, None) if no data found.
    """
    if disease_name:
        fname = f"output_{disease_name}.dat"
    else:
        fname = "output.dat"

    all_data = []
    for i in range(1, max_runs + 1):
        fpath = os.path.join(ensemble_dir, f"run_{i:03d}", fname)
        if not os.path.isfile(fpath):
            continue
        try:
            data = np.loadtxt(fpath, skiprows=1)
            if data.ndim == 1:
                data = data.reshape(1, -1)
            all_data.append(data)
        except Exception:
            pass

    if not all_data:
        return None, None

    min_rows = min(d.shape[0] for d in all_data)
    stacked = np.stack([d[:min_rows, :] for d in all_data], axis=0)
    days = stacked[0, :, COL_DAY]
    return days, stacked


def load_mean_std(ensemble_dir, disease_name):
    """Fallback: load pre-computed mean/std files."""
    if disease_name:
        base = f"output_{disease_name}"
    else:
        base = "output"

    mean_file = os.path.join(ensemble_dir, f"{base}_mean.dat")
    std_file  = os.path.join(ensemble_dir, f"{base}_std.dat")

    if not os.path.isfile(mean_file):
        return None, None, None

    mean_data = np.loadtxt(mean_file, skiprows=1)
    std_data  = np.loadtxt(std_file, skiprows=1) if os.path.isfile(std_file) else np.zeros_like(mean_data)
    days = mean_data[:, COL_DAY]
    return days, mean_data, std_data


def compute_total_infected(data):
    """Compute total infected from raw output columns. data shape: (..., n_cols)"""
    return np.sum(data[..., INFECTED_COLS], axis=-1)


# ─── Metric extraction ──────────────────────────────────────────────────────

def extract_metrics(days, stacked):
    """Extract key metrics from ensemble data.

    Args:
        days: (n_days,)
        stacked: (n_runs, n_days, n_cols)

    Returns dict with:
        peak_mag_mean, peak_mag_std: peak total infected (ensemble mean/std)
        peak_day_mean, peak_day_std: day of peak (ensemble mean/std)
        cum_deaths_mean, cum_deaths_std: cumulative deaths at end
        n_waves_mean, n_waves_std: number of infection waves
    """
    total_inf = compute_total_infected(stacked)  # (n_runs, n_days)
    n_runs = total_inf.shape[0]

    peak_mags = np.max(total_inf, axis=1)
    peak_days = np.array([days[np.argmax(total_inf[r, :])] for r in range(n_runs)])
    cum_deaths = stacked[:, -1, COL_D]

    # Count waves: local maxima in smoothed total_infected above 1% of peak
    n_waves = []
    for r in range(n_runs):
        curve = total_inf[r, :]
        # Smooth with 14-day moving average
        kernel = np.ones(14) / 14
        if len(curve) > 14:
            smoothed = np.convolve(curve, kernel, mode='same')
        else:
            smoothed = curve
        threshold = 0.01 * np.max(smoothed)
        # Find peaks: local maxima above threshold
        peaks = 0
        for t in range(1, len(smoothed) - 1):
            if (smoothed[t] > smoothed[t-1] and smoothed[t] > smoothed[t+1]
                    and smoothed[t] > threshold):
                peaks += 1
        n_waves.append(max(peaks, 1))  # at least 1 wave

    return {
        'peak_mag_mean':   np.mean(peak_mags),
        'peak_mag_std':    np.std(peak_mags, ddof=1),
        'peak_day_mean':   np.mean(peak_days),
        'peak_day_std':    np.std(peak_days, ddof=1),
        'cum_deaths_mean': np.mean(cum_deaths),
        'cum_deaths_std':  np.std(cum_deaths, ddof=1),
        'n_waves_mean':    np.mean(n_waves),
        'n_waves_std':     np.std(n_waves, ddof=1),
    }


# ─── Plotting ────────────────────────────────────────────────────────────────

def millions_formatter(x, pos):
    return f'{x/1e6:.1f}M'


def plot_timeseries_sweep(sweep_dict, diseases, data_dir, output_dir, fmt,
                          sweep_name, param_label):
    """Plot overlaid time-series for each parameter value in a sweep.

    One subplot per disease, lines colored by parameter value.
    """
    param_vals = list(sweep_dict.keys())
    cmap = plt.cm.viridis
    norm = plt.Normalize(vmin=min(param_vals), vmax=max(param_vals))

    fig, axes = plt.subplots(1, len(diseases), figsize=(7 * len(diseases), 5),
                             squeeze=False)

    for di, disease in enumerate(diseases):
        ax = axes[0, di]
        for pval, case_name in sweep_dict.items():
            ens_dir = find_ensemble_dir(data_dir, case_name)
            if ens_dir is None:
                print(f"  WARNING: No data for {case_name}")
                continue

            days, stacked = load_ensemble(ens_dir, disease)
            if days is None:
                days, mean_data, std_data = load_mean_std(ens_dir, disease)
                if days is None:
                    continue
                total_inf_mean = compute_total_infected(mean_data)
                total_inf_std = compute_total_infected(std_data)
            else:
                total_inf = compute_total_infected(stacked)
                total_inf_mean = np.mean(total_inf, axis=0)
                total_inf_std  = np.std(total_inf, axis=0)

            color = cmap(norm(pval))
            is_baseline = (pval == 0.85 and 'coimm' in sweep_name) or \
                          (pval == 1.5 and 'cosus' in sweep_name)
            lw = 2.5 if is_baseline else 1.5
            ls = '-' if is_baseline else '--'

            ax.plot(days, total_inf_mean, color=color, linewidth=lw,
                    linestyle=ls, label=f'{param_label} = {pval}')
            ax.fill_between(days,
                            total_inf_mean - total_inf_std,
                            total_inf_mean + total_inf_std,
                            color=color, alpha=0.12)

        ax.set_xlabel('Day')
        ax.set_ylabel('Total infected')
        ax.set_title(DISEASE_LABELS.get(disease, disease))
        ax.yaxis.set_major_formatter(FuncFormatter(millions_formatter))
        ax.legend(fontsize=8, loc='upper right')
        ax.set_xlim(0, None)
        ax.set_ylim(0, None)

    fig.suptitle(f'Sensitivity to {param_label} (California, 730 days)', fontsize=13)
    fig.tight_layout(rect=[0, 0, 1, 0.95])

    for ext in (['pdf', 'png'] if fmt == 'both' else [fmt]):
        outpath = os.path.join(output_dir, f'sensitivity_{sweep_name}_timeseries.{ext}')
        fig.savefig(outpath, dpi=200, bbox_inches='tight')
        print(f'  Saved: {outpath}')
    plt.close(fig)


def plot_summary_metrics(sweep_dict, diseases, data_dir, output_dir, fmt,
                         sweep_name, param_label):
    """Plot summary metrics as a function of the swept parameter.

    4 subplots: peak magnitude, peak timing, cumulative deaths, number of waves.
    One line per disease.
    """
    param_vals = list(sweep_dict.keys())
    metrics_by_disease = {d: [] for d in diseases}

    for pval, case_name in sweep_dict.items():
        ens_dir = find_ensemble_dir(data_dir, case_name)
        if ens_dir is None:
            for d in diseases:
                metrics_by_disease[d].append(None)
            continue

        for disease in diseases:
            days, stacked = load_ensemble(ens_dir, disease)
            if days is not None:
                m = extract_metrics(days, stacked)
            else:
                m = None
            metrics_by_disease[disease].append(m)

    # Create figure
    fig, axes = plt.subplots(2, 2, figsize=(12, 9))
    metric_keys = [
        ('peak_mag',   'Peak total infected', millions_formatter),
        ('peak_day',   'Day of peak',         None),
        ('cum_deaths', 'Cumulative deaths',   millions_formatter),
        ('n_waves',    'Number of waves',     None),
    ]

    for idx, (key, ylabel, yfmt) in enumerate(metric_keys):
        ax = axes[idx // 2, idx % 2]
        for disease in diseases:
            means = []
            stds  = []
            vals  = []
            for i, pval in enumerate(param_vals):
                m = metrics_by_disease[disease][i]
                if m is not None:
                    means.append(m[f'{key}_mean'])
                    stds.append(m[f'{key}_std'])
                    vals.append(pval)

            if not vals:
                continue

            means = np.array(means)
            stds  = np.array(stds)
            vals  = np.array(vals)
            color = DISEASE_COLORS.get(disease, 'black')
            label = DISEASE_LABELS.get(disease, disease)

            ax.errorbar(vals, means, yerr=stds, color=color, marker='o',
                        capsize=4, linewidth=1.5, markersize=6, label=label)

        ax.set_xlabel(param_label)
        ax.set_ylabel(ylabel)
        if yfmt:
            ax.yaxis.set_major_formatter(FuncFormatter(yfmt))
        ax.legend(fontsize=9)
        ax.set_xlim(min(param_vals) - 0.05 * (max(param_vals) - min(param_vals)),
                    max(param_vals) + 0.05 * (max(param_vals) - min(param_vals)))

        # Mark baseline
        baseline = 0.85 if 'coimm' in sweep_name else 1.5
        ax.axvline(baseline, color='gray', linestyle=':', alpha=0.5, linewidth=1)

    fig.suptitle(f'Sensitivity to {param_label} (California, 100 ensembles, 730 days)',
                 fontsize=13)
    fig.tight_layout(rect=[0, 0, 1, 0.95])

    for ext in (['pdf', 'png'] if fmt == 'both' else [fmt]):
        outpath = os.path.join(output_dir, f'sensitivity_{sweep_name}_summary.{ext}')
        fig.savefig(outpath, dpi=200, bbox_inches='tight')
        print(f'  Saved: {outpath}')
    plt.close(fig)


def print_metrics_table(sweep_dict, diseases, data_dir, sweep_name, param_label):
    """Print a formatted table of key metrics for paper inclusion."""
    param_vals = list(sweep_dict.keys())

    print(f"\n{'='*80}")
    print(f"  {sweep_name}: {param_label} sensitivity")
    print(f"{'='*80}")

    for disease in diseases:
        dlabel = DISEASE_LABELS.get(disease, disease)
        print(f"\n  {dlabel}:")
        print(f"  {'Param':>8s}  {'Peak Mag':>14s}  {'Peak Day':>12s}  "
              f"{'Cum Deaths':>14s}  {'Waves':>8s}")
        print(f"  {'':->8s}  {'':->14s}  {'':->12s}  {'':->14s}  {'':->8s}")

        for pval, case_name in sweep_dict.items():
            ens_dir = find_ensemble_dir(data_dir, case_name)
            if ens_dir is None:
                print(f"  {pval:8.3f}  {'(no data)':>14s}")
                continue

            days, stacked = load_ensemble(ens_dir, disease)
            if days is None:
                print(f"  {pval:8.3f}  {'(no data)':>14s}")
                continue

            m = extract_metrics(days, stacked)
            marker = " *" if ((pval == 0.85 and 'coimm' in sweep_name) or
                              (pval == 1.5 and 'cosus' in sweep_name)) else ""
            print(f"  {pval:8.3f}  "
                  f"{m['peak_mag_mean']:10.0f} +/- {m['peak_mag_std']:7.0f}  "
                  f"{m['peak_day_mean']:6.1f} +/- {m['peak_day_std']:4.1f}  "
                  f"{m['cum_deaths_mean']:10.0f} +/- {m['cum_deaths_std']:7.0f}  "
                  f"{m['n_waves_mean']:4.1f} +/- {m['n_waves_std']:2.1f}"
                  f"{marker}")

    print()


# ─── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description='Analyze ExaEpi sensitivity results')
    parser.add_argument('--data-dir', default=None,
                        help='Directory containing .ensemble_* dirs '
                             '(default: look in remote results and local sensitivity)')
    parser.add_argument('--output-dir', default=None,
                        help='Directory for output plots (default: sensitivity/plots)')
    parser.add_argument('--format', default='both', choices=['pdf', 'png', 'both'],
                        help='Output format (default: both)')
    parser.add_argument('--no-plots', action='store_true',
                        help='Only print metrics table, skip plots')
    args = parser.parse_args()

    # Determine data directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    if args.data_dir:
        data_dirs = [args.data_dir]
    else:
        # Search in both the remote results dir and local sensitivity dir
        data_dirs = [
            os.path.expanduser("~/Runs/remote/ExaEpi_LC/multidisease"),
            os.path.join(script_dir, ".."),  # project dir (for .ensemble_ dirs)
            script_dir,                       # sensitivity dir itself
        ]

    # Find first data_dir that has at least one matching ensemble
    data_dir = None
    for d in data_dirs:
        if not os.path.isdir(d):
            continue
        # Check if any sensitivity ensemble exists here
        for case_name in list(COIMM_SWEEP.values()) + list(COSUS_SWEEP.values()):
            if find_ensemble_dir(d, case_name) is not None:
                data_dir = d
                break
        if data_dir:
            break

    if data_dir is None:
        print("ERROR: No sensitivity ensemble data found.", file=sys.stderr)
        print("Searched in:", file=sys.stderr)
        for d in data_dirs:
            print(f"  {d}", file=sys.stderr)
        print("\nRun the sensitivity ensembles first, then sync results.", file=sys.stderr)
        sys.exit(1)

    print(f"Data directory: {data_dir}")

    # Output directory
    output_dir = args.output_dir or os.path.join(script_dir, "plots")
    os.makedirs(output_dir, exist_ok=True)

    # ── Co-immunity sweep ────────────────────────────────────────────────
    print("\n── Co-immunity sweep (Cov19-S1 + Cov19-S2) ──")
    print_metrics_table(COIMM_SWEEP, COIMM_DISEASES, data_dir,
                        "coimm", "Co-immunity")

    if not args.no_plots:
        print("Generating co-immunity plots...")
        plot_timeseries_sweep(COIMM_SWEEP, COIMM_DISEASES, data_dir,
                              output_dir, args.format, "coimm", "Co-immunity")
        plot_summary_metrics(COIMM_SWEEP, COIMM_DISEASES, data_dir,
                             output_dir, args.format, "coimm", "Co-immunity")

    # ── Co-susceptibility sweep ──────────────────────────────────────────
    print("\n── Co-susceptibility sweep (Cov19-S1 + Flu-S1) ──")
    print_metrics_table(COSUS_SWEEP, COSUS_DISEASES, data_dir,
                        "cosus", "Co-susceptibility")

    if not args.no_plots:
        print("Generating co-susceptibility plots...")
        plot_timeseries_sweep(COSUS_SWEEP, COSUS_DISEASES, data_dir,
                              output_dir, args.format, "cosus", "Co-susceptibility")
        plot_summary_metrics(COSUS_SWEEP, COSUS_DISEASES, data_dir,
                             output_dir, args.format, "cosus", "Co-susceptibility")

    print("\nDone.")


if __name__ == '__main__':
    main()
