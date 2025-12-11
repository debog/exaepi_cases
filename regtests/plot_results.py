#!/usr/bin/env python3
"""
ExaEpi Regression Test Plotting Module

Generates comparison plots between baseline and test results using matplotlib.
Computes L1, L2, and L∞ norms of differences.
Replaces the old gnuplot scripts with a modern Python-based solution.

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
"""

import argparse
import sys
import re
from pathlib import Path
from typing import List, Dict, Optional, Tuple
import numpy as np

try:
    import matplotlib
    matplotlib.use('Agg')  # Non-interactive backend
    import matplotlib.pyplot as plt
    from matplotlib.gridspec import GridSpec
    MATPLOTLIB_AVAILABLE = True
except ImportError:
    MATPLOTLIB_AVAILABLE = False
    print("WARNING: matplotlib not available. Install with: pip install matplotlib")


class RegtestPlotter:
    """Generates comparison plots for regression test results"""

    def __init__(self, root_dir: Path = None):
        self.root_dir = root_dir or Path(__file__).parent.resolve()
        self.baseline_dir = self.root_dir / "baselines"
        self.test_dir = self.root_dir / "tests"
        self.plot_dir = self.root_dir / "plots"

        # Plot configuration
        self.plot_config = {
            'figsize': (16, 10),
            'dpi': 150,
            'baseline_style': {
                'color': 'black',
                'linestyle': '-',
                'linewidth': 2,
                'label': 'Baseline'
            },
            'test_style': {
                'color': 'blue',
                'marker': 'o',
                'markersize': 3,
                'linestyle': 'none',
                'label': 'Current'
            },
            'grid_style': {
                'color': 'gray',
                'linestyle': '--',
                'linewidth': 0.5,
                'alpha': 0.7
            }
        }

        # Metrics to plot (column indices in output.dat, 0-indexed after header skip)
        # Format: Day, Su, PS/PI, S/PI/NH, S/PI/H, PS/I, S/I/NH, S/I/H, A/PI, A/I, H/NI, H/I, ICU, V, R, D, NewS, NewH
        self.metrics = {
            'susceptible': {
                'columns': [1],  # Su
                'ylabel': 'Susceptible',
                'title': 'Susceptible',
                'combine': 'sum'
            },
            'total_infectious': {
                'columns': [5, 6, 7, 9, 11],  # PS/I, S/I/NH, S/I/H, A/I, H/I
                'ylabel': 'Total Infectious',
                'title': 'Total Infectious',
                'combine': 'sum'
            },
            'hospitalized': {
                'columns': [10, 11],  # H/NI, H/I
                'ylabel': 'Hospitalized',
                'title': 'Hospitalized (non-ICU)',
                'combine': 'sum'
            },
            'icu': {
                'columns': [12],  # ICU
                'ylabel': 'ICU Patients',
                'title': 'ICU Patients',
                'combine': 'sum'
            },
            'deaths': {
                'columns': [15],  # D
                'ylabel': 'Cumulative Deaths',
                'title': 'Deaths',
                'combine': 'sum'
            },
            'recovered': {
                'columns': [14],  # R
                'ylabel': 'Recovered',
                'title': 'Recovered',
                'combine': 'sum'
            }
        }

    def parse_disease_config(self, input_file: Path) -> Tuple[int, List[str]]:
        """Parse input file to detect number of diseases and disease names

        Returns:
            Tuple[int, List[str]]: (number_of_diseases, disease_names)
        """
        num_diseases = 1  # Default value
        disease_names = []

        try:
            with open(input_file, 'r') as f:
                content = f.read()

            # Look for agent.number_of_diseases
            match = re.search(r'agent\.number_of_diseases\s*=\s*(\d+)', content)
            if match:
                num_diseases = int(match.group(1))

            # Look for agent.disease_names
            match = re.search(r'agent\.disease_names\s*=\s*(.+)', content)
            if match:
                # Extract disease names from quoted strings
                names_str = match.group(1)
                disease_names = re.findall(r'"([^"]+)"', names_str)

            # If disease names not specified, generate default names
            if num_diseases > 1 and not disease_names:
                disease_names = [f"default{i:02d}" for i in range(num_diseases)]
            elif num_diseases == 1 and not disease_names:
                disease_names = []  # Single disease uses output.dat

            return num_diseases, disease_names

        except Exception as e:
            print(f"  WARNING: Failed to parse input file {input_file}: {str(e)}")
            return 1, []  # Default to single disease

    def load_output_data(self, filepath: Path) -> Tuple[Optional[np.ndarray], str]:
        """Load output.dat file

        Returns:
            Tuple[Optional[np.ndarray], str]: (data, error_message)
        """
        try:
            if not filepath.exists():
                error_msg = f"Output file not found: {filepath}"
                return None, error_msg

            # Skip header row if present
            data = np.loadtxt(filepath, skiprows=1)

            # Validate minimum column count (need at least 18 columns for all metrics)
            if data.shape[1] < 18:
                error_msg = f"Insufficient columns in output file (found {data.shape[1]}, need 18). Test may have failed or not completed."
                return None, error_msg

            # Validate data has rows
            if data.shape[0] == 0:
                error_msg = "Output file is empty (no data rows). Test may have failed."
                return None, error_msg

            return data, ""

        except ValueError as e:
            if "could not convert" in str(e):
                error_msg = f"Invalid data format in output file. File may be corrupted or test failed."
            else:
                error_msg = f"Data format error: {str(e)}"
            return None, error_msg
        except Exception as e:
            error_msg = f"Failed to read output file: {type(e).__name__}: {str(e)}"
            return None, error_msg

    def extract_metric(self, data: np.ndarray, metric_config: Dict) -> np.ndarray:
        """Extract and combine columns for a metric"""
        columns = metric_config['columns']

        if len(columns) == 1:
            return data[:, columns[0]]
        else:
            # Sum multiple columns
            result = np.zeros(data.shape[0])
            for col in columns:
                result += data[:, col]
            return result

    def compute_norms(self, baseline_values: np.ndarray, test_values: np.ndarray) -> Dict[str, float]:
        """Compute L1, L2, and L∞ norms of the difference"""
        diff = test_values - baseline_values

        # Absolute norms
        l1_abs = np.sum(np.abs(diff))
        l2_abs = np.sqrt(np.sum(diff**2))
        linf_abs = np.max(np.abs(diff))

        # Relative norms (normalized by baseline norm)
        baseline_l1 = np.sum(np.abs(baseline_values))
        baseline_l2 = np.sqrt(np.sum(baseline_values**2))
        baseline_linf = np.max(np.abs(baseline_values))

        l1_rel = l1_abs / baseline_l1 if baseline_l1 > 0 else 0.0
        l2_rel = l2_abs / baseline_l2 if baseline_l2 > 0 else 0.0
        linf_rel = linf_abs / baseline_linf if baseline_linf > 0 else 0.0

        return {
            'l1_abs': l1_abs,
            'l2_abs': l2_abs,
            'linf_abs': linf_abs,
            'l1_rel': l1_rel,
            'l2_rel': l2_rel,
            'linf_rel': linf_rel
        }

    def create_comparison_plot(
        self,
        baseline_data_list: List[np.ndarray],
        test_data_list: List[np.ndarray],
        disease_names: List[str],
        case_name: str,
        machine: str,
        output_file: Path
    ):
        """Create a single comparison plot with all metrics as subplots

        For multi-disease cases, all diseases are plotted on the same axes.

        Args:
            baseline_data_list: List of baseline data arrays (one per disease)
            test_data_list: List of test data arrays (one per disease)
            disease_names: List of disease names (empty for single disease)
            case_name: Test case name
            machine: Machine name
            output_file: Output file path
        """

        fig = plt.figure(figsize=self.plot_config['figsize'])
        gs = GridSpec(2, 3, figure=fig, hspace=0.35, wspace=0.3)

        # Define colors for multiple diseases (beyond baseline black and test blue)
        disease_colors = ['red', 'green', 'orange', 'purple', 'brown', 'pink']

        num_diseases = len(baseline_data_list)
        is_multi_disease = num_diseases > 1

        if is_multi_disease:
            print(f"\n  Metric comparison for {case_name}.{machine} ({num_diseases} diseases):")
        else:
            print(f"\n  Metric comparison for {case_name}.{machine}:")

        print(f"  {'Metric':<20} {'L1 (abs)':<12} {'L2 (abs)':<12} {'L∞ (abs)':<12} {'L1 (rel)':<12} {'L2 (rel)':<12} {'L∞ (rel)':<12}")
        print(f"  {'-'*20} {'-'*12} {'-'*12} {'-'*12} {'-'*12} {'-'*12} {'-'*12}")

        # Plot each metric
        for idx, (metric_name, metric) in enumerate(self.metrics.items()):
            row = idx // 3
            col = idx % 3
            ax = fig.add_subplot(gs[row, col])

            # Plot each disease
            for disease_idx, (baseline_data, test_data) in enumerate(zip(baseline_data_list, test_data_list)):
                # Extract time
                baseline_time = baseline_data[:, 0]
                test_time = test_data[:, 0]

                # Extract metric data
                baseline_values = self.extract_metric(baseline_data, metric)
                test_values = self.extract_metric(test_data, metric)

                # Compute norms (only print for first disease or single disease)
                norms = self.compute_norms(baseline_values, test_values)

                disease_label = f" ({disease_names[disease_idx]})" if is_multi_disease else ""
                if disease_idx == 0 or is_multi_disease:
                    print(f"  {metric['title']}{disease_label:<20} {norms['l1_abs']:<12.2e} {norms['l2_abs']:<12.2e} {norms['linf_abs']:<12.2e} {norms['l1_rel']:<12.2e} {norms['l2_rel']:<12.2e} {norms['linf_rel']:<12.2e}")

                # Plot with disease-specific styling
                if is_multi_disease:
                    # Multi-disease: use different colors for each disease
                    disease_name = disease_names[disease_idx]
                    color = disease_colors[disease_idx % len(disease_colors)]

                    # Baseline: solid line
                    ax.plot(baseline_time, baseline_values,
                           color=color, linestyle='-', linewidth=2,
                           label=f'{disease_name} Baseline')

                    # Test: markers
                    ax.plot(test_time, test_values,
                           color=color, marker='o', markersize=3, linestyle='none',
                           label=f'{disease_name} Current')
                else:
                    # Single disease: use standard black/blue styling
                    ax.plot(baseline_time, baseline_values, **self.plot_config['baseline_style'])
                    ax.plot(test_time, test_values, **self.plot_config['test_style'])

            # Formatting
            ax.set_xlabel('Days', fontsize=10)
            ax.set_ylabel(metric['ylabel'], fontsize=10)

            # Title (with norms from first disease for multi-disease)
            if is_multi_disease:
                title = f"{metric['title']} (all diseases)"
            else:
                # Recompute norms for single disease (we're outside the loop)
                baseline_values = self.extract_metric(baseline_data_list[0], metric)
                test_values = self.extract_metric(test_data_list[0], metric)
                norms = self.compute_norms(baseline_values, test_values)
                title = f"{metric['title']}\n"
                title += f"L1={norms['l1_rel']:.2e}, L2={norms['l2_rel']:.2e}, L∞={norms['linf_rel']:.2e}"

            ax.set_title(title, fontsize=10, fontweight='bold')
            ax.grid(True, **self.plot_config['grid_style'])

            # Legend placement
            if is_multi_disease:
                ax.legend(loc='best', fontsize=7, ncol=1)
            else:
                ax.legend(loc='best', fontsize=9)

            # Use scientific notation for y-axis if values are large
            max_val = max([self.extract_metric(bd, metric).max() for bd in baseline_data_list] +
                         [self.extract_metric(td, metric).max() for td in test_data_list])
            if max_val > 10000:
                ax.ticklabel_format(style='scientific', axis='y', scilimits=(0, 0))

        # Overall title
        if is_multi_disease:
            title_diseases = ', '.join(disease_names)
            fig.suptitle(
                f"{case_name.upper()} - Comparison ({machine})\nDiseases: {title_diseases}",
                fontsize=16,
                fontweight='bold',
                y=0.998
            )
        else:
            fig.suptitle(
                f"{case_name.upper()} - Comparison ({machine})",
                fontsize=16,
                fontweight='bold',
                y=0.995
            )

        # Save
        plt.savefig(output_file, dpi=self.plot_config['dpi'], bbox_inches='tight')
        plt.close()

        print(f"\n  Created: {output_file}")

    def plot_case(
        self,
        case_name: str,
        machine: str
    ) -> Tuple[bool, str]:
        """Generate plot for a specific test case and machine

        Returns:
            Tuple[bool, str]: (success, error_message)
        """

        test_dirname = f"{case_name}.{machine}"

        try:
            # Find the input file to detect multi-disease configuration
            baseline_dir_path = self.baseline_dir / test_dirname
            test_dir_path = self.test_dir / test_dirname

            # Look for input file in test directory (should be symlinked there)
            input_file = None
            for candidate in test_dir_path.glob("inputs*"):
                if candidate.is_file():
                    input_file = candidate
                    break

            # If not found in test dir, look in common/
            if input_file is None:
                # Try to find from config (need to load test_cases.yaml)
                import yaml
                config_file = self.root_dir / "config" / "test_cases.yaml"
                if config_file.exists():
                    with open(config_file, 'r') as f:
                        config = yaml.safe_load(f)
                    if case_name in config.get('test_cases', {}):
                        input_filename = config['test_cases'][case_name].get('input_file')
                        if input_filename:
                            input_file = self.root_dir / "common" / input_filename

            # Parse disease configuration
            num_diseases = 1
            disease_names = []
            if input_file and input_file.exists():
                num_diseases, disease_names = self.parse_disease_config(input_file)

            # Determine output files to load
            if num_diseases == 1:
                # Single disease case - use output.dat
                output_files = ["output.dat"]
            else:
                # Multi-disease case - use output_<disease>.dat for each disease
                output_files = [f"output_{disease}.dat" for disease in disease_names]
                print(f"\nDetected {num_diseases}-disease simulation: {', '.join(disease_names)}")

            print(f"\nGenerating plot for {case_name}.{machine}...")

            # Create plot output directory
            self.plot_dir.mkdir(parents=True, exist_ok=True)

            # Load data for all diseases
            baseline_data_list = []
            test_data_list = []
            error_messages = []

            for disease_idx, output_filename in enumerate(output_files):
                # Construct file paths
                baseline_output = baseline_dir_path / output_filename
                test_output = test_dir_path / output_filename

                disease_label = f" ({disease_names[disease_idx]})" if num_diseases > 1 else ""

                # Check if files exist
                if not baseline_output.exists():
                    error_msg = f"Baseline output not found{disease_label}: {baseline_output}"
                    print(f"  WARNING: {error_msg}")
                    error_messages.append(error_msg)
                    continue

                if not test_output.exists():
                    error_msg = f"Test output not found{disease_label}: {test_output}"
                    print(f"  WARNING: {error_msg}")
                    error_messages.append(error_msg)
                    continue

                # Load data
                baseline_data, baseline_error = self.load_output_data(baseline_output)
                test_data, test_error = self.load_output_data(test_output)

                if baseline_data is None:
                    error_msg = f"Baseline{disease_label}: {baseline_error}"
                    print(f"  ERROR: {error_msg}")
                    error_messages.append(error_msg)
                    continue

                if test_data is None:
                    error_msg = f"Test{disease_label}: {test_error}"
                    print(f"  ERROR: {error_msg}")
                    error_messages.append(error_msg)
                    continue

                # Validate data shapes match
                if baseline_data.shape != test_data.shape:
                    error_msg = f"Data shape mismatch{disease_label} (baseline: {baseline_data.shape[0]} rows × {baseline_data.shape[1]} cols, test: {test_data.shape[0]} rows × {test_data.shape[1]} cols). Tests may have run for different durations or with different outputs."
                    print(f"  ERROR: {error_msg}")
                    error_messages.append(error_msg)
                    continue

                # Add to lists
                baseline_data_list.append(baseline_data)
                test_data_list.append(test_data)

            # Check if we have any data to plot
            if not baseline_data_list or not test_data_list:
                combined_error = "; ".join(error_messages) if error_messages else "No data available to plot"
                return False, combined_error

            # Create comparison plot - save directly in plots/ directory
            output_file = self.plot_dir / f"{test_dirname}.png"
            try:
                self.create_comparison_plot(
                    baseline_data_list,
                    test_data_list,
                    disease_names,
                    case_name,
                    machine,
                    output_file
                )
                return True, ""
            except IndexError as e:
                error_msg = f"Data column access error. Output file may have incorrect format or missing columns. {str(e)}"
                print(f"  ERROR: {error_msg}")
                return False, error_msg
            except Exception as e:
                error_msg = f"Plot generation failed: {type(e).__name__}: {str(e)}"
                print(f"  ERROR: {error_msg}")
                import traceback
                traceback.print_exc()
                return False, error_msg

        except Exception as e:
            error_msg = f"Unexpected error: {type(e).__name__}: {str(e)}"
            print(f"  ERROR: {error_msg}")
            import traceback
            traceback.print_exc()
            return False, error_msg

    def find_test_directories(self, machine: Optional[str] = None) -> List[Tuple[str, str]]:
        """Find all test directories and extract case name and machine"""

        if not self.test_dir.exists():
            return []

        test_cases = []

        for test_dir in sorted(self.test_dir.iterdir()):
            if not test_dir.is_dir():
                continue

            # Parse directory name: case.machine
            parts = test_dir.name.rsplit('.', 1)
            if len(parts) != 2:
                continue

            case_name, dir_machine = parts

            # Filter by machine if specified
            if machine and dir_machine != machine:
                continue

            # Check if output.dat exists OR any output_*.dat files exist (multi-disease)
            has_output = (test_dir / "output.dat").exists()
            if not has_output:
                # Check for multi-disease output files
                has_output = len(list(test_dir.glob("output_*.dat"))) > 0

            if has_output:
                test_cases.append((case_name, dir_machine))

        return test_cases

    def plot_all(
        self,
        machine: Optional[str] = None,
        cases: Optional[List[str]] = None
    ):
        """Generate plots for all test cases"""

        if not MATPLOTLIB_AVAILABLE:
            print("ERROR: matplotlib is not installed")
            print("Install with: pip install matplotlib")
            return False

        # Find test cases
        test_cases = self.find_test_directories(machine)

        if not test_cases:
            print("No test cases found with output.dat files")
            return False

        # Filter by specific cases if requested
        if cases:
            test_cases = [(c, m) for c, m in test_cases if c in cases]

        if not test_cases:
            print("No matching test cases found")
            return False

        print(f"Found {len(test_cases)} test case(s) to plot")

        # Generate plots
        success_count = 0
        failed_cases = []

        for case_name, case_machine in test_cases:
            success, error_msg = self.plot_case(case_name, case_machine)
            if success:
                success_count += 1
            else:
                failed_cases.append((f"{case_name}.{case_machine}", error_msg))

        # Print summary
        print(f"\n{'='*80}")
        print(f"Plot Generation Summary:")
        print(f"  Successful: {success_count}/{len(test_cases)}")
        print(f"  Failed:     {len(failed_cases)}/{len(test_cases)}")

        if failed_cases:
            print(f"\nFailed cases:")
            for case_name, error_msg in failed_cases:
                print(f"  ✗ {case_name}")
                print(f"    Reason: {error_msg}")

        if success_count > 0:
            print(f"\nPlots saved in: {self.plot_dir}")

        print(f"{'='*80}")

        return success_count > 0


def main():
    parser = argparse.ArgumentParser(
        description='Generate comparison plots for ExaEpi regression tests',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Plot all test results
  %(prog)s

  # Plot specific test case
  %(prog)s --case ca --machine perlmutter

  # Plot all tests for a specific machine
  %(prog)s --machine dane

  # Plot multiple specific cases
  %(prog)s --case ca,bay --machine linux
        """
    )

    parser.add_argument(
        '--case', '--cases',
        type=str,
        help='Comma-separated list of test cases to plot (default: all)'
    )

    parser.add_argument(
        '--machine',
        type=str,
        help='Machine to plot results for (default: all machines)'
    )

    args = parser.parse_args()

    # Parse cases
    cases = args.case.split(',') if args.case else None

    # Create plotter
    plotter = RegtestPlotter()

    # Generate plots
    success = plotter.plot_all(
        machine=args.machine,
        cases=cases
    )

    return 0 if success else 1


if __name__ == '__main__':
    sys.exit(main())
