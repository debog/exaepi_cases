#!/usr/bin/env python3
"""
ExaEpi Regression Test Plotting Module

Generates comparison plots between baseline and test results using matplotlib.
Replaces the old gnuplot scripts with a modern Python-based solution.
"""

import argparse
import sys
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
            'figsize': (12, 8),
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
                'markersize': 4,
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

        # Metrics to plot (column indices in output.dat)
        # Format: Day, Su, PS/PI, S/PI/NH, S/PI/H, PS/I, S/I/NH, S/I/H, A/PI, A/I, H/NI, H/I, ICU, V, R, D, NewS, NewH
        # Column indices are 0-based after header row is skipped
        self.metrics = {
            'total_infected': {
                'column': 9,  # A/I - Asymptomatic/Infected (column 10 in 1-indexed)
                'ylabel': 'Number of Infected (Asymptomatic)',
                'title_suffix': 'Asymptomatic Infected',
                'legend_loc': 'upper right'
            },
            'deaths': {
                'column': 15,  # D - Deaths (column 16 in 1-indexed)
                'ylabel': 'Cumulative Deaths',
                'title_suffix': 'Deaths',
                'legend_loc': 'upper left'
            },
            'hospitalizations': {
                'column': 17,  # NewH - New Hospitalizations (column 18 in 1-indexed)
                'ylabel': 'New Hospitalizations',
                'title_suffix': 'Hospitalizations',
                'legend_loc': 'upper right'
            }
        }

    def load_output_data(self, filepath: Path) -> Optional[np.ndarray]:
        """Load output.dat file"""
        try:
            if not filepath.exists():
                print(f"WARNING: Output file not found: {filepath}")
                return None

            # Skip header row if present
            data = np.loadtxt(filepath, skiprows=1)
            return data
        except Exception as e:
            print(f"ERROR loading {filepath}: {e}")
            return None

    def create_comparison_plot(
        self,
        baseline_data: np.ndarray,
        test_data: np.ndarray,
        metric_name: str,
        case_name: str,
        machine: str,
        output_file: Path
    ):
        """Create a comparison plot for a single metric"""

        metric = self.metrics[metric_name]

        fig, ax = plt.subplots(figsize=self.plot_config['figsize'])

        # Extract time and metric columns
        baseline_time = baseline_data[:, 0]
        baseline_values = baseline_data[:, metric['column']]

        test_time = test_data[:, 0]
        test_values = test_data[:, metric['column']]

        # Plot baseline (solid line)
        ax.plot(baseline_time, baseline_values, **self.plot_config['baseline_style'])

        # Plot test results (points)
        ax.plot(test_time, test_values, **self.plot_config['test_style'])

        # Formatting
        ax.set_xlabel('Days', fontsize=14, fontweight='bold')
        ax.set_ylabel(metric['ylabel'], fontsize=14, fontweight='bold')
        ax.set_title(
            f"{case_name.upper()} - {metric['title_suffix']} ({machine})",
            fontsize=16,
            fontweight='bold'
        )

        ax.grid(True, **self.plot_config['grid_style'])
        ax.legend(loc=metric['legend_loc'], fontsize=12, framealpha=0.9)

        # Use scientific notation for y-axis if values are large
        if baseline_values.max() > 10000 or test_values.max() > 10000:
            ax.ticklabel_format(style='scientific', axis='y', scilimits=(0, 0))

        plt.tight_layout()

        # Save plot
        output_file.parent.mkdir(parents=True, exist_ok=True)
        plt.savefig(output_file, dpi=self.plot_config['dpi'], bbox_inches='tight')
        plt.close()

        print(f"  Created: {output_file.name}")

    def create_combined_plot(
        self,
        baseline_data: np.ndarray,
        test_data: np.ndarray,
        case_name: str,
        machine: str,
        output_file: Path
    ):
        """Create a combined plot with all metrics"""

        fig = plt.figure(figsize=(14, 10))
        gs = GridSpec(2, 2, figure=fig, hspace=0.3, wspace=0.3)

        # Plot each metric
        for idx, (metric_name, metric) in enumerate(self.metrics.items()):
            if idx >= 3:  # Only plot first 3 metrics
                break

            ax = fig.add_subplot(gs[idx // 2, idx % 2])

            # Extract data
            baseline_time = baseline_data[:, 0]
            baseline_values = baseline_data[:, metric['column']]

            test_time = test_data[:, 0]
            test_values = test_data[:, metric['column']]

            # Plot
            ax.plot(baseline_time, baseline_values, **self.plot_config['baseline_style'])
            ax.plot(test_time, test_values, **self.plot_config['test_style'])

            # Formatting
            ax.set_xlabel('Days', fontsize=11)
            ax.set_ylabel(metric['ylabel'], fontsize=11)
            ax.set_title(metric['title_suffix'], fontsize=12, fontweight='bold')
            ax.grid(True, **self.plot_config['grid_style'])
            ax.legend(loc=metric['legend_loc'], fontsize=10)

            if baseline_values.max() > 10000 or test_values.max() > 10000:
                ax.ticklabel_format(style='scientific', axis='y', scilimits=(0, 0))

        # Overall title
        fig.suptitle(
            f"{case_name.upper()} - All Metrics ({machine})",
            fontsize=16,
            fontweight='bold',
            y=0.995
        )

        # Save
        output_file.parent.mkdir(parents=True, exist_ok=True)
        plt.savefig(output_file, dpi=self.plot_config['dpi'], bbox_inches='tight')
        plt.close()

        print(f"  Created: {output_file.name}")

    def plot_case(
        self,
        case_name: str,
        machine: str,
        create_individual: bool = True,
        create_combined: bool = True
    ) -> bool:
        """Generate plots for a specific test case and machine"""

        # Construct directory names
        test_dirname = f"{case_name}.{machine}"

        baseline_output = self.baseline_dir / test_dirname / "output.dat"
        test_output = self.test_dir / test_dirname / "output.dat"

        # Check if files exist
        if not baseline_output.exists():
            print(f"WARNING: Baseline output not found: {baseline_output}")
            return False

        if not test_output.exists():
            print(f"WARNING: Test output not found: {test_output}")
            return False

        print(f"\nGenerating plots for {case_name}.{machine}...")

        # Load data
        baseline_data = self.load_output_data(baseline_output)
        test_data = self.load_output_data(test_output)

        if baseline_data is None or test_data is None:
            return False

        # Create plot output directory
        plot_output_dir = self.plot_dir / test_dirname
        plot_output_dir.mkdir(parents=True, exist_ok=True)

        success = True

        # Create individual metric plots
        if create_individual:
            for metric_name in self.metrics.keys():
                output_file = plot_output_dir / f"{metric_name}.png"
                try:
                    self.create_comparison_plot(
                        baseline_data,
                        test_data,
                        metric_name,
                        case_name,
                        machine,
                        output_file
                    )
                except Exception as e:
                    print(f"  ERROR creating {metric_name} plot: {e}")
                    success = False

        # Create combined plot
        if create_combined:
            output_file = plot_output_dir / "all_metrics.png"
            try:
                self.create_combined_plot(
                    baseline_data,
                    test_data,
                    case_name,
                    machine,
                    output_file
                )
            except Exception as e:
                print(f"  ERROR creating combined plot: {e}")
                success = False

        return success

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

            # Check if output.dat exists
            if (test_dir / "output.dat").exists():
                test_cases.append((case_name, dir_machine))

        return test_cases

    def plot_all(
        self,
        machine: Optional[str] = None,
        cases: Optional[List[str]] = None,
        individual: bool = True,
        combined: bool = True
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
        for case_name, case_machine in test_cases:
            if self.plot_case(case_name, case_machine, individual, combined):
                success_count += 1

        print(f"\nSuccessfully generated plots for {success_count}/{len(test_cases)} test cases")
        print(f"Plots saved in: {self.plot_dir}")

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

  # Only create combined plots (faster)
  %(prog)s --no-individual
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

    parser.add_argument(
        '--no-individual',
        action='store_true',
        help='Skip individual metric plots, only create combined plots'
    )

    parser.add_argument(
        '--no-combined',
        action='store_true',
        help='Skip combined plots, only create individual metric plots'
    )

    args = parser.parse_args()

    # Parse cases
    cases = args.case.split(',') if args.case else None

    # Create plotter
    plotter = RegtestPlotter()

    # Generate plots
    success = plotter.plot_all(
        machine=args.machine,
        cases=cases,
        individual=not args.no_individual,
        combined=not args.no_combined
    )

    return 0 if success else 1


if __name__ == '__main__':
    sys.exit(main())
