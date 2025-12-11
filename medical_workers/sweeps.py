#!/usr/bin/env python3
"""
ExaEpi Parameter Sweep Orchestration Tool

Unified tool for managing parameter sweep studies across multiple HPC systems.
Replaces scattered bash scripts with configuration-driven approach.

Usage:
  ./sweeps.py validate                          # Validate environment
  ./sweeps.py list-studies                      # List available studies
  ./sweeps.py create --study recovery           # Create run directories
  ./sweeps.py run --study recovery --machine dane   # Run parameter sweep
  ./sweeps.py status --study recovery           # Check completion status
  ./sweeps.py plot --study recovery             # Generate plots

Examples:
  # Run recovery study on auto-detected machine
  ./sweeps.py create --study recovery --case CA
  ./sweeps.py run --study recovery --case CA

  # Run hosp_interactions study on specific machine
  ./sweeps.py run --study hosp_interactions --case CA --machine matrix
"""

import argparse
import os
import sys
import shutil
import subprocess
from pathlib import Path
from typing import List, Dict, Optional, Tuple
import itertools

try:
    import yaml
    YAML_AVAILABLE = True
except ImportError:
    YAML_AVAILABLE = False
    print("ERROR: PyYAML not installed. Install with: pip install pyyaml")
    sys.exit(1)


class SweepOrchestrator:
    """Orchestrates parameter sweep studies across HPC systems"""

    def __init__(self, root_dir: Path = None):
        self.root_dir = root_dir or Path(__file__).parent.resolve()
        self.config_dir = self.root_dir / "config"

        # Load configurations
        self.studies = self._load_yaml(self.config_dir / "studies.yaml")
        self.machines = self._load_yaml(self.config_dir / "machines.yaml")

        # Environment
        self.exaepi_build = os.getenv('EXAEPI_BUILD')
        self.exaepi_dir = os.getenv('EXAEPI_DIR')

    def _load_yaml(self, filepath: Path) -> dict:
        """Load YAML configuration file"""
        try:
            with open(filepath, 'r') as f:
                return yaml.safe_load(f)
        except Exception as e:
            print(f"ERROR: Failed to load {filepath}: {str(e)}")
            sys.exit(1)

    def detect_machine(self) -> Optional[str]:
        """Auto-detect current machine from environment variables"""
        # Check NERSC
        nersc_host = os.getenv('NERSC_HOST')
        if nersc_host:
            if nersc_host in self.machines['machines']:
                return nersc_host

        # Check LC
        lc_host = os.getenv('LCHOST')
        if lc_host:
            if lc_host in self.machines['machines']:
                return lc_host

        return None

    def validate_environment(self) -> bool:
        """Validate environment setup"""
        print("Validating environment...")

        valid = True

        # Check EXAEPI_BUILD
        if not self.exaepi_build:
            print("  ✗ EXAEPI_BUILD not set")
            valid = False
        else:
            build_path = Path(self.exaepi_build)
            if not build_path.exists():
                print(f"  ✗ EXAEPI_BUILD path does not exist: {self.exaepi_build}")
                valid = False
            else:
                print(f"  ✓ EXAEPI_BUILD: {self.exaepi_build}")

        # Check EXAEPI_DIR
        if not self.exaepi_dir:
            print("  ✗ EXAEPI_DIR not set")
            valid = False
        else:
            dir_path = Path(self.exaepi_dir)
            if not dir_path.exists():
                print(f"  ✗ EXAEPI_DIR path does not exist: {self.exaepi_dir}")
                valid = False
            else:
                print(f"  ✓ EXAEPI_DIR: {self.exaepi_dir}")

        # Check machine detection
        machine = self.detect_machine()
        if machine:
            print(f"  ✓ Detected machine: {machine}")
        else:
            print("  ℹ No machine auto-detected (NERSC_HOST and LCHOST not set)")
            print("    You can specify machine explicitly with --machine flag")

        # Check PyYAML
        if YAML_AVAILABLE:
            print("  ✓ PyYAML installed")
        else:
            print("  ✗ PyYAML not installed")
            valid = False

        if valid:
            print("\n✓ Environment validation successful")
        else:
            print("\n✗ Environment validation failed")

        return valid

    def list_studies(self):
        """List available parameter sweep studies"""
        print("\nAvailable parameter sweep studies:\n")

        for study_name, study_config in self.studies['studies'].items():
            print(f"  {study_name}")
            print(f"    Name: {study_config['name']}")
            print(f"    Description: {study_config['description']}")
            print(f"    Cases: {', '.join(study_config['cases'])}")

            # Count parameter combinations
            params = study_config['parameters']
            param_names = list(params.keys())
            combinations = 1
            for values in params.values():
                combinations *= len(values)

            if study_config.get('baseline'):
                print(f"    Runs: {combinations} parameter combinations + 1 baseline")
            else:
                print(f"    Runs: {combinations} parameter combinations")
            print()

    def list_machines(self):
        """List available machines"""
        print("\nAvailable machines:\n")

        for machine_name, machine_config in self.machines['machines'].items():
            display_name = machine_config.get('display_name', machine_name)
            scheduler = machine_config.get('scheduler', 'none')
            print(f"  {machine_name:<15} {display_name} ({scheduler})")

    def _find_executable(self, machine: str) -> Optional[Path]:
        """Find ExaEpi executable in build directory"""
        build_path = Path(self.exaepi_build)

        # Try machine-specific subdirectory first
        machine_exec = build_path / machine / "bin"
        if machine_exec.exists():
            for exec_file in machine_exec.glob("*agent*"):
                if exec_file.is_file() and os.access(exec_file, os.X_OK):
                    return exec_file

        # Try direct bin directory
        direct_exec = build_path / "bin"
        if direct_exec.exists():
            for exec_file in direct_exec.glob("*agent*"):
                if exec_file.is_file() and os.access(exec_file, os.X_OK):
                    return exec_file

        return None

    def _generate_parameter_combinations(self, study_config: dict) -> List[Dict[str, any]]:
        """Generate all parameter combinations for a study"""
        params = study_config['parameters']
        param_names = list(params.keys())
        param_values = [params[name] for name in param_names]

        combinations = []
        for values in itertools.product(*param_values):
            param_dict = dict(zip(param_names, values))
            combinations.append(param_dict)

        return combinations

    def _format_dirname(self, study_name: str, case: str, machine: str, params: dict, is_baseline: bool = False) -> str:
        """Generate directory name for parameter combination"""
        if is_baseline:
            return f".run_{study_name}.{case}.{machine}.baseline"

        # Format parameter values in directory name
        param_str = ""
        for key, value in params.items():
            # Abbreviate parameter names
            abbrev_map = {
                'med_workers_proportion': 'mwprop',
                'num_patients_per_doctor': 'nppd',
                'xmit_hosp_d2d': 'xmitd2d',
                'xmit_hosp_d2p': 'xmitd2p',
                'xmit_hosp_p2d': 'xmitp2d',
                'xmit_hosp_p2p': 'xmitp2p',
                'write_pltfiles': 'plt'
            }

            abbrev = abbrev_map.get(key, key)

            # Format value
            if isinstance(value, float):
                if 'mwprop' in abbrev or 'xmit' in abbrev:
                    val_str = f"{value:.3f}".replace('.', '')
                else:
                    val_str = f"{value:.2f}".replace('.', '')
            elif isinstance(value, bool):
                continue  # Skip boolean parameters in dirname
            else:
                val_str = f"{value:03d}" if isinstance(value, int) and value < 1000 else str(value)

            param_str += f".{abbrev}{val_str}"

        return f".run_{study_name}.{case}.{machine}{param_str}"

    def _create_run_script(self, study_name: str, case: str, machine: str, params: dict,
                          run_dir: Path, is_baseline: bool = False):
        """Create machine-specific run script"""
        machine_config = self.machines['machines'][machine]
        study_config = self.studies['studies'][study_name]

        # Find executable
        exec_path = self._find_executable(machine)
        if not exec_path:
            raise FileNotFoundError(f"Could not find ExaEpi executable for machine {machine}")

        # Input file
        input_file = f"inputs.{case}"

        # Output file
        outfile = f"out.{machine}.log"

        # Build argument string
        args = []
        for key, value in params.items():
            if key == 'med_workers_proportion':
                args.append(f"agent.med_workers_proportion={value}")
            elif key == 'num_patients_per_doctor':
                args.append(f"hospital_model.num_patients_per_doctor={value}")
            elif key == 'write_pltfiles':
                args.append(f"hospital_model.write_pltfiles={'true' if value else 'false'}")
            elif key.startswith('xmit_hosp_'):
                args.append(f"disease.{key}={value}")

        arg_str = " ".join(args)

        # Get resource requirements
        tasks = machine_config.get('tasks', 4)
        nodes = machine_config.get('nodes', 1)
        gpus = machine_config.get('gpus', 0)

        # Case-specific overrides
        if case == 'Bay':
            if machine in ['perlmutter', 'matrix', 'tuolumne', 'linux-gpu']:
                tasks = 1
                gpus = 1 if gpus > 0 else 0
            elif machine == 'dane':
                tasks = 25

        # Create run script
        script_path = run_dir / f"run.{machine}.sh"

        lines = ["#!/bin/bash", ""]

        # Set environment variables
        if 'env_setup' in machine_config:
            for env_var, value in machine_config['env_setup'].items():
                lines.append(f"export {env_var}={value}")
            lines.append("")

        # Clean up old files
        lines.append("rm -rf $outfile plt* cases* out* Backtrace* *.core")
        lines.append("")

        # Build run command based on scheduler
        scheduler = machine_config.get('scheduler', 'none')

        if scheduler == 'none':
            # Direct execution for Linux
            mpi_launcher = machine_config.get('mpi_launcher', 'mpirun')
            mpi_flags = machine_config.get('mpi_flags', '')

            if gpus > 0:
                gpu_flag = machine_config.get('gpu_aware_mpi', 'amrex.use_gpu_aware_mpi=0')
                run_cmd = f"{mpi_launcher} {mpi_flags} -n {tasks} {exec_path} {input_file} {arg_str} {gpu_flag} 2>&1 | tee {outfile}"
            else:
                run_cmd = f"{mpi_launcher} {mpi_flags} -n {tasks} {exec_path} {input_file} {arg_str} 2>&1 | tee {outfile}"

            lines.append(run_cmd)

        elif scheduler == 'slurm':
            # SLURM (Perlmutter, Dane, Matrix)
            if machine == 'perlmutter':
                # GPU-based
                lines.extend([
                    f"srun --cpu-bind=cores -n {tasks} bash -c \"",
                    f"    export CUDA_VISIBLE_DEVICES=\\$((3-SLURM_LOCALID));",
                    f"    {exec_path} {input_file} {arg_str} amrex.use_gpu_aware_mpi=1\" \\",
                    f"    2>&1 | tee {outfile}"
                ])
            elif machine == 'dane':
                # CPU-based
                lines.append(f"srun -n {tasks} -N {nodes} -p pdebug {exec_path} {input_file} {arg_str} 2>&1 | tee {outfile}")
            elif machine == 'matrix':
                # GPU-based
                lines.append(f"srun -p pdebug -n {tasks} -G {tasks} -N {nodes} -t 00:05:00 {exec_path} {input_file} {arg_str} 2>&1 | tee {outfile}")

        elif scheduler == 'flux':
            # Flux (Tuolumne)
            if gpus > 0:
                lines.append(f"flux run --exclusive --nodes={nodes} --ntasks {tasks} --gpus-per-task 1 -q=pdebug -t 5 {exec_path} {input_file} {arg_str} 2>&1 | tee {outfile}")
            else:
                lines.append(f"flux run --exclusive --nodes={nodes} --ntasks {tasks} -q=pdebug -t 5 {exec_path} {input_file} {arg_str} 2>&1 | tee {outfile}")

        # Write script
        with open(script_path, 'w') as f:
            f.write('\n'.join(lines) + '\n')

        # Make executable
        script_path.chmod(0o755)

        return script_path

    def create_runs(self, study_name: str, case: str, machine: str):
        """Create run directories for parameter sweep"""
        if study_name not in self.studies['studies']:
            print(f"ERROR: Unknown study '{study_name}'")
            return False

        study_config = self.studies['studies'][study_name]

        if case not in study_config['cases']:
            print(f"ERROR: Case '{case}' not available for study '{study_name}'")
            print(f"Available cases: {', '.join(study_config['cases'])}")
            return False

        print(f"\nCreating run directories for {study_name} study, case {case}, machine {machine}...")

        # Get study directory
        study_dir = self.root_dir / study_name
        common_dir = study_dir / "common"

        if not common_dir.exists():
            print(f"ERROR: Common directory not found: {common_dir}")
            return False

        # Create baseline if specified
        baseline_config = study_config.get('baseline')
        if baseline_config:
            print("\nCreating baseline run...")
            dirname = self._format_dirname(study_name, case, machine, baseline_config, is_baseline=True)
            run_dir = study_dir / dirname

            if run_dir.exists():
                print(f"  Directory exists: {dirname}")
            else:
                run_dir.mkdir(parents=True, exist_ok=True)
                print(f"  Created: {dirname}")

                # Create symlinks to input and data files
                input_file = common_dir / f"inputs.{case}"
                if input_file.exists():
                    (run_dir / input_file.name).symlink_to(input_file)

                # Link data files
                data_files = study_config['data_files'].get(case, [])
                for data_file in data_files:
                    src = common_dir / data_file
                    if src.exists():
                        (run_dir / data_file).symlink_to(src)

                # Create run script
                self._create_run_script(study_name, case, machine, baseline_config, run_dir, is_baseline=True)

        # Generate parameter combinations
        combinations = self._generate_parameter_combinations(study_config)
        print(f"\nCreating {len(combinations)} parameter combination runs...")

        created_count = 0
        skipped_count = 0

        for params in combinations:
            dirname = self._format_dirname(study_name, case, machine, params)
            run_dir = study_dir / dirname

            if run_dir.exists():
                skipped_count += 1
                continue

            run_dir.mkdir(parents=True, exist_ok=True)
            created_count += 1

            # Create symlinks to input and data files
            input_file = common_dir / f"inputs.{case}"
            if input_file.exists():
                (run_dir / input_file.name).symlink_to(input_file)

            # Link data files
            data_files = study_config['data_files'].get(case, [])
            for data_file in data_files:
                src = common_dir / data_file
                if src.exists():
                    (run_dir / data_file).symlink_to(src)

            # Create run script
            self._create_run_script(study_name, case, machine, params, run_dir)

        print(f"\n  Created: {created_count}")
        print(f"  Skipped (already exist): {skipped_count}")
        print(f"  Total: {created_count + skipped_count}")

        return True

    def run_sweeps(self, study_name: str, case: str, machine: str, max_parallel: int = 4):
        """Run parameter sweep jobs"""
        if study_name not in self.studies['studies']:
            print(f"ERROR: Unknown study '{study_name}'")
            return False

        study_config = self.studies['studies'][study_name]
        study_dir = self.root_dir / study_name

        machine_config = self.machines['machines'][machine]
        batch_mode = machine_config.get('batch_mode', False)

        # Find all run directories for this study/case/machine
        pattern = f".run_{study_name}.{case}.{machine}*"
        run_dirs = sorted(study_dir.glob(pattern))

        if not run_dirs:
            print(f"No run directories found matching: {pattern}")
            print("Run './sweeps.py create' first")
            return False

        # Count jobs that need to run
        jobs_to_run = []
        skipped = 0

        for run_dir in run_dirs:
            # Check if already completed
            outfile = run_dir / f"out.{machine}.log"
            already_done = False
            if outfile.exists():
                try:
                    with open(outfile, 'r') as f:
                        lines = f.readlines()
                        if lines:
                            last_line = lines[-1]
                            if "finalized" in last_line:
                                already_done = True
                                skipped += 1
                except Exception:
                    pass

            if not already_done:
                run_script = run_dir / f"run.{machine}.sh"
                if run_script.exists():
                    jobs_to_run.append((run_dir, run_script))

        total_jobs = len(jobs_to_run)
        total_runs = len(run_dirs)

        print(f"\nFound {total_runs} run directories")
        print(f"  Already completed: {skipped}")
        print(f"  To run: {total_jobs}")
        print(f"Batch mode: {batch_mode}")
        print(f"Max parallel jobs: {max_parallel if not batch_mode else 'N/A'}")

        if total_jobs == 0:
            print("\n✓ All jobs already completed")
            return True

        # Run jobs
        running_jobs = []
        completed = 0

        for idx, (run_dir, run_script) in enumerate(jobs_to_run, 1):
            print(f"\nStarting job {idx}/{total_jobs}: {run_dir.name}")

            if batch_mode:
                # Submit batch job (SLURM/Flux)
                # TODO: Implement batch submission
                print("  Batch mode not yet implemented")
            else:
                # Run directly in background
                proc = subprocess.Popen(
                    ['bash', str(run_script)],
                    cwd=run_dir,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )
                running_jobs.append(proc)

                # Wait if max parallel reached
                if len(running_jobs) >= max_parallel:
                    print(f"  Waiting for {len(running_jobs)} jobs to complete...")
                    for proc in running_jobs:
                        proc.wait()
                    completed += len(running_jobs)
                    running_jobs = []
                    remaining = total_jobs - completed
                    print(f"  Progress: {completed}/{total_jobs} completed, {remaining} remaining")

        # Wait for remaining jobs
        if running_jobs:
            print(f"\nWaiting for final {len(running_jobs)} jobs to complete...")
            for proc in running_jobs:
                proc.wait()
            completed += len(running_jobs)

        print(f"\n✓ Completed {completed} jobs")
        if skipped > 0:
            print(f"  Skipped (already completed): {skipped}")

        return True

    def check_status(self, study_name: str, case: str, machine: str):
        """Check completion status of parameter sweep"""
        if study_name not in self.studies['studies']:
            print(f"ERROR: Unknown study '{study_name}'")
            return False

        study_dir = self.root_dir / study_name
        pattern = f".run_{study_name}.{case}.{machine}*"
        run_dirs = sorted(study_dir.glob(pattern))

        if not run_dirs:
            print(f"No run directories found for {study_name}/{case}/{machine}")
            return False

        completed = 0
        failed = 0
        running = 0
        not_started = 0

        for run_dir in run_dirs:
            outfile = run_dir / f"out.{machine}.log"

            if not outfile.exists():
                not_started += 1
            else:
                try:
                    with open(outfile, 'r') as f:
                        lines = f.readlines()
                        if lines and "finalized" in lines[-1]:
                            completed += 1
                        else:
                            running += 1
                except:
                    failed += 1

        total = len(run_dirs)

        print(f"\nStatus for {study_name}/{case}/{machine}:")
        print(f"  Total runs:    {total}")
        print(f"  Completed:     {completed} ({100*completed//total if total > 0 else 0}%)")
        print(f"  Running:       {running}")
        print(f"  Not started:   {not_started}")
        print(f"  Failed:        {failed}")

        return True

    def generate_plots(self, study_name: str, case: str, machine: str):
        """Generate plots for parameter sweep results"""
        if study_name not in self.studies['studies']:
            print(f"ERROR: Unknown study '{study_name}'")
            return False

        # Call plot_sweeps.py
        plot_script = self.root_dir / "plot_sweeps.py"
        if not plot_script.exists():
            print(f"ERROR: Plotting script not found: {plot_script}")
            return False

        print(f"Generating plots for {study_name}/{case}/{machine}...")

        # Run plotting script
        result = subprocess.run(
            [sys.executable, str(plot_script),
             '--study', study_name,
             '--case', case,
             '--machine', machine],
            capture_output=False
        )

        return result.returncode == 0


def main():
    parser = argparse.ArgumentParser(
        description='ExaEpi Parameter Sweep Orchestration Tool',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )

    parser.add_argument(
        'action',
        choices=['validate', 'list-studies', 'list-machines', 'create', 'run', 'status', 'plot'],
        help='Action to perform'
    )

    parser.add_argument(
        '--study',
        type=str,
        help='Study name (recovery, hosp_interactions)'
    )

    parser.add_argument(
        '--case',
        type=str,
        help='Case name (CA, Bay)'
    )

    parser.add_argument(
        '--machine',
        type=str,
        default='current',
        help='Machine to run on (auto-detected if not specified)'
    )

    parser.add_argument(
        '--max-parallel',
        type=int,
        default=4,
        help='Maximum parallel jobs (default: 4)'
    )

    args = parser.parse_args()

    # Create orchestrator
    orch = SweepOrchestrator()

    # Handle actions
    if args.action == 'validate':
        success = orch.validate_environment()
        return 0 if success else 1

    elif args.action == 'list-studies':
        orch.list_studies()
        return 0

    elif args.action == 'list-machines':
        orch.list_machines()
        return 0

    # Actions requiring study and case
    if not args.study:
        print("ERROR: --study required for this action")
        return 1

    if not args.case:
        print("ERROR: --case required for this action")
        return 1

    # Resolve machine
    machine = None if args.machine == 'current' else args.machine
    if machine is None:
        machine = orch.detect_machine()
        if machine is None:
            print("ERROR: Could not auto-detect machine. Specify with --machine")
            return 1

    # Validate environment
    if not orch.validate_environment():
        return 1

    if args.action == 'create':
        success = orch.create_runs(args.study, args.case, machine)
        return 0 if success else 1

    elif args.action == 'run':
        success = orch.run_sweeps(args.study, args.case, machine, args.max_parallel)
        return 0 if success else 1

    elif args.action == 'status':
        success = orch.check_status(args.study, args.case, machine)
        return 0 if success else 1

    elif args.action == 'plot':
        success = orch.generate_plots(args.study, args.case, machine)
        return 0 if success else 1

    return 0


if __name__ == '__main__':
    sys.exit(main())
