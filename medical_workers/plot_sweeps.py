#!/usr/bin/env python3
"""
ExaEpi Parameter Sweep Plotting Module

Generates comparison plots for parameter sweep studies using matplotlib.
Replaces old gnuplot scripts with modern Python-based solution.

Column definitions from ExaEpi src/main.cpp and src/AgentDefinitions.H:
  0: Day        - Simulation day
  1: Su         - Susceptible
  2: PS/PI      - Presymptomatic/Preinfectious
  3: S/PI/NH    - Symptomatic/Preinfectious/Non-Hospitalized
  4: S/PI/H     - Symptomatic/Preinfectious/Hospitalized
  5: PS/I       - Presymptomatic/Infectious
  6: S/I/NH     - Symptomatic/Infectious/Non-Hospitalized
  7: S/I/H      - Symptomatic/Infectious/Hospitalized
  8: A/PI       - Asymptomatic/Preinfectious
  9: A/I        - Asymptomatic/Infectious
 10: H/NI       - Hospitalized/Noninfectious
 11: H/I        - Hospitalized/Infectious
 12: ICU        - In ICU
 13: V          - On ventilator
 14: R          - Recovered
 15: D          - Dead
 16: NewS       - Became symptomatic this step
 17: NewH       - Became hospitalized this step

Hospital data file (num_bad_hospitals.dat):
  Parsed from log output: "Day X: Y hospitals over capacity, Z underserved hospitalized agents"
  Column 0: Day
  Column 1: Number of overloaded hospitals
  Column 2: Number of underserved patients
"""

import argparse
import sys
from pathlib import Path
from typing import List, Dict, Optional, Tuple
import numpy as np
import re

try:
    import yaml
    YAML_AVAILABLE = True
except ImportError:
    YAML_AVAILABLE = False
    print("WARNING: PyYAML not available. Install with: pip install pyyaml")

try:
    import matplotlib
    matplotlib.use('Agg')  # Non-interactive backend
    import matplotlib.pyplot as plt
    from matplotlib.gridspec import GridSpec
    MATPLOTLIB_AVAILABLE = True
except ImportError:
    MATPLOTLIB_AVAILABLE = False
    print("WARNING: matplotlib not available. Install with: pip install matplotlib")


class SweepPlotter:
    """Generates comparison plots for parameter sweep results"""

    def __init__(self, root_dir: Path = None):
        self.root_dir = root_dir or Path(__file__).parent.resolve()
        self.config_dir = self.root_dir / "config"

        # Load configuration
        if YAML_AVAILABLE:
            self.studies = self._load_yaml(self.config_dir / "studies.yaml")
            self.plot_config = self.studies.get('plot_config', {})
        else:
            self.studies = {}
            self.plot_config = {}

        # Default plot configuration
        self.default_config = {
            'figsize': self.plot_config.get('figsize', [14, 10]),
            'dpi': self.plot_config.get('dpi', 150),
            'xrange': self.plot_config.get('xrange', [0, 80]),
            'grid': self.plot_config.get('grid', True),
            'format': self.plot_config.get('format', 'png')
        }

        # Color and marker schemes for different parameter values
        self.colors = ['blue', 'red', 'green', 'orange', 'purple', 'brown', 'pink', 'gray']
        self.markers = ['o', 's', '^', 'v', 'D', 'p', '*', 'h']
        self.linestyles = ['-', '--', '-.', ':']

    def _load_yaml(self, filepath: Path) -> dict:
        """Load YAML configuration file"""
        try:
            with open(filepath, 'r') as f:
                return yaml.safe_load(f)
        except Exception as e:
            print(f"WARNING: Failed to load {filepath}: {str(e)}")
            return {}

    def load_output_data(self, filepath: Path) -> Tuple[Optional[np.ndarray], str]:
        """Load output.dat file

        Returns:
            Tuple[Optional[np.ndarray], str]: (data, error_message)
        """
        try:
            if not filepath.exists():
                return None, f"File not found: {filepath}"

            # Skip header row if present
            data = np.loadtxt(filepath, skiprows=1)

            # Validate minimum column count
            if data.shape[1] < 18:
                return None, f"Insufficient columns (found {data.shape[1]}, need 18)"

            if data.shape[0] == 0:
                return None, "Empty data file"

            return data, ""

        except Exception as e:
            return None, f"Error loading file: {str(e)}"

    def load_hospital_data(self, filepath: Path) -> Tuple[Optional[np.ndarray], str]:
        """Load num_bad_hospitals.dat file"""
        try:
            if not filepath.exists():
                return None, f"File not found: {filepath}"

            data = np.loadtxt(filepath)

            if data.shape[0] == 0:
                return None, "Empty data file"

            return data, ""

        except Exception as e:
            return None, f"Error loading file: {str(e)}"

    def extract_metric(self, data: np.ndarray, columns: List[int]) -> np.ndarray:
        """Extract and sum columns for a metric"""
        if len(columns) == 1:
            return data[:, columns[0]]
        else:
            result = np.zeros(data.shape[0])
            for col in columns:
                result += data[:, col]
            return result

    def parse_dirname(self, dirname: str, study_name: str) -> Optional[Dict[str, any]]:
        """Parse parameter values from directory name"""
        # Pattern: .run_<study>.<case>.<machine>.<params>
        params = {}

        # Extract medical workers proportion
        match = re.search(r'mwprop(\d{3})', dirname)
        if match:
            params['med_workers_proportion'] = float(match.group(1)) / 100.0

        # Extract patients per doctor
        match = re.search(r'nppd(\d+)', dirname)
        if match:
            params['num_patients_per_doctor'] = int(match.group(1))

        # Extract transmission rates
        for xmit_type in ['xmitd2d', 'xmitd2p', 'xmitp2d', 'xmitp2p']:
            match = re.search(rf'{xmit_type}(\d{{3}})', dirname)
            if match:
                params[xmit_type.replace('xmit', 'xmit_hosp_')] = float(match.group(1)) / 1000.0

        # Check if baseline
        if 'baseline' in dirname:
            params['is_baseline'] = True

        return params if params else None

    def find_run_directories(self, study_name: str, case: str, machine: str) -> List[Tuple[Path, Dict]]:
        """Find all run directories for a study/case/machine and parse parameters"""
        study_dir = self.root_dir / study_name
        pattern = f".run_{study_name}.{case}.{machine}*"

        run_dirs = []
        for run_dir in sorted(study_dir.glob(pattern)):
            if not run_dir.is_dir():
                continue

            # Check if output.dat exists
            output_file = run_dir / "output.dat"
            if not output_file.exists():
                continue

            # Parse parameters from directory name
            params = self.parse_dirname(run_dir.name, study_name)
            if params:
                run_dirs.append((run_dir, params))

        return run_dirs

    def plot_recovery_study(self, case: str, machine: str, output_dir: Path):
        """Generate plots for recovery study"""
        study_name = "recovery"
        study_config = self.studies['studies'][study_name]

        # Find all run directories
        run_dirs = self.find_run_directories(study_name, case, machine)
        if not run_dirs:
            print(f"No completed runs found for {study_name}/{case}/{machine}")
            return False

        # Load baseline data
        baseline_dir = None
        baseline_data = None
        baseline_hosp_data = None

        for run_dir, params in run_dirs:
            if params.get('is_baseline', False):
                baseline_dir = run_dir
                baseline_data, _ = self.load_output_data(run_dir / "output.dat")
                baseline_hosp_data, _ = self.load_hospital_data(run_dir / "num_bad_hospitals.dat")
                break

        if baseline_data is None:
            print("WARNING: Baseline data not found")

        # Group runs by medical workers proportion
        mwprop_groups = {}
        for run_dir, params in run_dirs:
            if params.get('is_baseline', False):
                continue

            mwprop = params.get('med_workers_proportion', 0.0)
            if mwprop not in mwprop_groups:
                mwprop_groups[mwprop] = []

            mwprop_groups[mwprop].append((run_dir, params))

        # Define metrics
        metrics = [
            ('Infections', [3, 4, 5, 6, 7, 8], 0, 0, False),
            ('Hospitalizations', [10, 11], 0, 1, False),
            ('Deaths', [15], 1, 0, False),
            ('Overloaded Hospitals', None, 1, 1, True),  # From hospital data
            ('Underserved Patients', None, 2, 0, True)   # From hospital data
        ]

        # Determine global y-axis limits by scanning all data
        print("\nDetermining global axis limits...")
        global_limits = {}

        for metric_name, columns, row, col, is_hospital_metric in metrics:
            all_values = []

            # Include baseline data
            if baseline_data is not None and not is_hospital_metric:
                values = self.extract_metric(baseline_data, columns)
                all_values.extend(values)
            elif baseline_hosp_data is not None and is_hospital_metric:
                if metric_name == 'Overloaded Hospitals':
                    values = baseline_hosp_data[:, 1]
                else:
                    values = baseline_hosp_data[:, 2]
                all_values.extend(values)

            # Include all parameter sweep data
            for mwprop, runs in mwprop_groups.items():
                for run_dir, params in runs:
                    if not is_hospital_metric:
                        data, _ = self.load_output_data(run_dir / "output.dat")
                        if data is not None:
                            values = self.extract_metric(data, columns)
                            all_values.extend(values)
                    else:
                        data, _ = self.load_hospital_data(run_dir / "num_bad_hospitals.dat")
                        if data is not None:
                            if metric_name == 'Overloaded Hospitals':
                                values = data[:, 1]
                            else:
                                values = data[:, 2]
                            all_values.extend(values)

            # Calculate limits
            if all_values:
                min_val = np.min(all_values)
                max_val = np.max(all_values)

                if is_hospital_metric:
                    # For log scale, ensure minimum is at least 1
                    min_val = 1
                    # Add some headroom (10% in log space)
                    max_val = max_val * 1.1 if max_val > 0 else 10
                else:
                    # For linear scale, start from 0
                    min_val = 0
                    # Add 10% headroom
                    max_val = max_val * 1.1

                global_limits[metric_name] = (min_val, max_val)
            else:
                # Default limits if no data
                global_limits[metric_name] = (0, 100) if not is_hospital_metric else (1, 100)

        # Generate plots for each medical workers proportion
        for mwprop in sorted(mwprop_groups.keys()):
            print(f"\nGenerating plots for medical workers proportion: {mwprop:.2f}")

            # Create figure with 5 subplots
            fig, axes = plt.subplots(3, 2, figsize=(14, 12))
            fig.suptitle(f"{case.upper()}: Medical Workers Proportion = {int(mwprop*100)}%\n{machine}",
                        fontsize=16, fontweight='bold')

            # Plot baseline if available
            if baseline_data is not None:
                time_baseline = baseline_data[:, 0]

            for metric_name, columns, row, col, is_hospital_metric in metrics:
                ax = axes[row, col]

                # Plot baseline
                if baseline_data is not None and not is_hospital_metric:
                    values = self.extract_metric(baseline_data, columns)
                    ax.plot(time_baseline, values, 'k-', linewidth=2, label='Baseline')
                elif baseline_hosp_data is not None and is_hospital_metric:
                    time_hosp = baseline_hosp_data[:, 0]  # Column 0 is day
                    if metric_name == 'Overloaded Hospitals':
                        values = baseline_hosp_data[:, 1]  # Column 1
                    else:  # Underserved Patients
                        values = baseline_hosp_data[:, 2]  # Column 2
                    ax.plot(time_hosp, values, 'k-', linewidth=2, label='Baseline')

                # Plot parameter sweep results
                runs = mwprop_groups[mwprop]
                for idx, (run_dir, params) in enumerate(sorted(runs, key=lambda x: x[1].get('num_patients_per_doctor', 0))):
                    nppd = params.get('num_patients_per_doctor', 0)

                    # Load data
                    if not is_hospital_metric:
                        data, error = self.load_output_data(run_dir / "output.dat")
                        if data is None:
                            continue
                        time = data[:, 0]
                        values = self.extract_metric(data, columns)
                    else:
                        data, error = self.load_hospital_data(run_dir / "num_bad_hospitals.dat")
                        if data is None:
                            continue
                        time = data[:, 0]
                        if metric_name == 'Overloaded Hospitals':
                            values = data[:, 1]
                        else:
                            values = data[:, 2]

                    # Plot with unique color/marker
                    color = self.colors[idx % len(self.colors)]
                    marker = self.markers[idx % len(self.markers)]
                    linestyle = '--'

                    ax.plot(time, values, color=color, linestyle=linestyle, linewidth=1.5,
                           marker=marker, markersize=3, markevery=max(1, len(time)//10),
                           label=f'nppd={nppd}')

                # Formatting
                ax.set_xlabel('Days', fontsize=10)
                ax.set_ylabel(metric_name, fontsize=10)
                ax.set_title(metric_name, fontsize=11, fontweight='bold')
                ax.grid(True, alpha=0.3)
                ax.legend(loc='best', fontsize=8)

                # Use log scale for hospital metrics, linear for others
                if is_hospital_metric:
                    ax.set_yscale('log')

                # Apply global y-axis limits
                if metric_name in global_limits:
                    ax.set_ylim(global_limits[metric_name])

                # Set x-range
                ax.set_xlim(self.default_config['xrange'])

            # Remove unused subplot
            fig.delaxes(axes[2, 1])

            # Save figure
            output_file = output_dir / f"{study_name}_{case}_{machine}_mwprop{int(mwprop*100):02d}.{self.default_config['format']}"
            plt.tight_layout()
            plt.savefig(output_file, dpi=self.default_config['dpi'], bbox_inches='tight')
            plt.close()

            print(f"  Created: {output_file}")

        return True

    def plot_hosp_interactions_study(self, case: str, machine: str, output_dir: Path):
        """Generate plots for hospital interactions study"""
        study_name = "hosp_interactions"
        study_config = self.studies['studies'][study_name]

        # Find all run directories
        run_dirs = self.find_run_directories(study_name, case, machine)
        if not run_dirs:
            print(f"No completed runs found for {study_name}/{case}/{machine}")
            return False

        print(f"\nFound {len(run_dirs)} completed runs")

        # Group by medical workers proportion
        mwprop_groups = {}
        for run_dir, params in run_dirs:
            mwprop = params.get('med_workers_proportion', 0.0)
            if mwprop not in mwprop_groups:
                mwprop_groups[mwprop] = []
            mwprop_groups[mwprop].append((run_dir, params))

        # Define metrics
        metrics = [
            ('Infections', [3, 4, 5, 6, 7, 8], 0),
            ('Hospitalizations', [10, 11], 1),
            ('Deaths', [15], 2)
        ]

        # Determine global y-axis limits by scanning all data
        print("\nDetermining global axis limits...")
        global_limits = {}

        for metric_name, columns, idx in metrics:
            all_values = []

            # Include all parameter sweep data
            for mwprop, runs in mwprop_groups.items():
                for run_dir, params in runs:
                    data, _ = self.load_output_data(run_dir / "output.dat")
                    if data is not None:
                        values = self.extract_metric(data, columns)
                        all_values.extend(values)

            # Calculate limits
            if all_values:
                min_val = 0  # Linear scale
                max_val = np.max(all_values) * 1.1  # Add 10% headroom
                global_limits[metric_name] = (min_val, max_val)
            else:
                global_limits[metric_name] = (0, 100)

        # For each medical workers proportion, create a summary plot
        for mwprop in sorted(mwprop_groups.keys()):
            print(f"\nGenerating plots for medical workers proportion: {mwprop:.2f}")

            # Create figure with 3 subplots (one per metric)
            fig, axes = plt.subplots(1, 3, figsize=(16, 5))
            fig.suptitle(f"{case.upper()}: Hospital Interactions - Medical Workers = {int(mwprop*100)}%\n{machine}",
                        fontsize=16, fontweight='bold')

            # Plot a sample of parameter combinations
            runs = mwprop_groups[mwprop]
            print(f"  Plotting {min(len(runs), 20)} of {len(runs)} parameter combinations")

            for metric_name, columns, idx in metrics:
                ax = axes[idx]

                # Plot subset of runs (limit to avoid overcrowding)
                for run_idx, (run_dir, params) in enumerate(runs[:20]):  # Limit to 20 curves
                    data, error = self.load_output_data(run_dir / "output.dat")
                    if data is None:
                        continue

                    time = data[:, 0]
                    values = self.extract_metric(data, columns)

                    # Use varied colors/styles
                    color = self.colors[run_idx % len(self.colors)]
                    linestyle = self.linestyles[run_idx % len(self.linestyles)]

                    # Create label with transmission parameters
                    d2d = params.get('xmit_hosp_d2d', 0.0)
                    d2p = params.get('xmit_hosp_d2p', 0.0)
                    p2d = params.get('xmit_hosp_p2d', 0.0)
                    p2p = params.get('xmit_hosp_p2p', 0.0)

                    label = f"{d2d:.3f},{d2p:.3f},{p2d:.3f},{p2p:.3f}"

                    ax.plot(time, values, color=color, linestyle=linestyle,
                           linewidth=1, alpha=0.7, label=label if run_idx < 10 else None)

                # Formatting
                ax.set_xlabel('Days', fontsize=10)
                ax.set_ylabel(metric_name, fontsize=10)
                ax.set_title(metric_name, fontsize=11, fontweight='bold')
                ax.grid(True, alpha=0.3)
                if idx == 2:  # Only show legend on last plot
                    ax.legend(loc='best', fontsize=6, title='d2d,d2p,p2d,p2p', ncol=2)
                ax.set_xlim(self.default_config['xrange'])

                # Apply global y-axis limits
                if metric_name in global_limits:
                    ax.set_ylim(global_limits[metric_name])

            # Save figure
            output_file = output_dir / f"{study_name}_{case}_{machine}_mwprop{int(mwprop*100):02d}.{self.default_config['format']}"
            plt.tight_layout()
            plt.savefig(output_file, dpi=self.default_config['dpi'], bbox_inches='tight')
            plt.close()

            print(f"  Created: {output_file}")

        return True

    def plot_study(self, study_name: str, case: str, machine: str):
        """Generate plots for a study"""
        if not MATPLOTLIB_AVAILABLE:
            print("ERROR: matplotlib is not installed")
            print("Install with: pip install matplotlib")
            return False

        if study_name not in self.studies.get('studies', {}):
            print(f"ERROR: Unknown study '{study_name}'")
            return False

        # Create output directory
        study_dir = self.root_dir / study_name
        output_dir = study_dir / "plots"
        output_dir.mkdir(exist_ok=True)

        print(f"\nGenerating plots for {study_name}/{case}/{machine}...")
        print(f"Output directory: {output_dir}")

        # Call study-specific plotting function
        if study_name == "recovery":
            success = self.plot_recovery_study(case, machine, output_dir)
        elif study_name == "hosp_interactions":
            success = self.plot_hosp_interactions_study(case, machine, output_dir)
        else:
            print(f"ERROR: Plotting not implemented for study '{study_name}'")
            return False

        if success:
            print(f"\n✓ Plots saved to: {output_dir}")
        else:
            print(f"\n✗ Plot generation failed")

        return success


def main():
    parser = argparse.ArgumentParser(
        description='Generate comparison plots for ExaEpi parameter sweep studies',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Plot recovery study results
  %(prog)s --study recovery --case CA --machine dane

  # Plot hospital interactions study
  %(prog)s --study hosp_interactions --case Bay --machine perlmutter
        """
    )

    parser.add_argument(
        '--study',
        type=str,
        required=True,
        help='Study name (recovery, hosp_interactions)'
    )

    parser.add_argument(
        '--case',
        type=str,
        required=True,
        help='Case name (CA, Bay)'
    )

    parser.add_argument(
        '--machine',
        type=str,
        required=True,
        help='Machine name'
    )

    args = parser.parse_args()

    # Create plotter
    plotter = SweepPlotter()

    # Generate plots
    success = plotter.plot_study(args.study, args.case, args.machine)

    return 0 if success else 1


if __name__ == '__main__':
    sys.exit(main())
