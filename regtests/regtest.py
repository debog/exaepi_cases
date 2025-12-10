#!/usr/bin/env python3
"""
ExaEpi Regression Test Orchestration Tool

Unified script to manage regression tests across multiple machines and test cases.
Replaces scattered bash scripts with a configuration-driven approach.
"""

import argparse
import os
import sys
import subprocess
import shutil
from pathlib import Path
from typing import List, Dict, Optional, Set
import yaml
import json
from datetime import datetime


class RegtestOrchestrator:
    """Main orchestration class for ExaEpi regression tests"""

    def __init__(self, config_dir: Path = None):
        self.root_dir = Path(__file__).parent.resolve()
        self.config_dir = config_dir or self.root_dir / "config"
        self.common_dir = self.root_dir / "common"
        self.shell_dir = self.root_dir / "shell_directories"

        # Load configurations
        self.machines = self._load_yaml(self.config_dir / "machines.yaml")
        self.test_cases = self._load_yaml(self.config_dir / "test_cases.yaml")

        # Detect current machine
        self.current_machine = self._detect_machine()

    def _load_yaml(self, filepath: Path) -> Dict:
        """Load YAML configuration file"""
        try:
            with open(filepath, 'r') as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            print(f"ERROR: Configuration file not found: {filepath}")
            sys.exit(1)
        except yaml.YAMLError as e:
            print(f"ERROR: Failed to parse YAML file {filepath}: {e}")
            sys.exit(1)

    def _detect_machine(self) -> Optional[str]:
        """Auto-detect which machine we're running on"""
        for machine, config in self.machines['machines'].items():
            env_var = config.get('env_var')
            if env_var and env_var in os.environ:
                env_value = os.environ[env_var]
                if env_value == machine or machine in env_value.lower():
                    return machine
        return None

    def _find_build_dir(self, machine: str = None) -> Optional[Path]:
        """
        Find the build directory, checking for machine-specific subdirectories.

        EXAEPI_BUILD can be structured in two ways:
        1. Direct build: $EXAEPI_BUILD/bin/agent
        2. Machine subdirectories: $EXAEPI_BUILD/<machine>/bin/agent

        Returns the appropriate build directory path, or None if not found.
        """
        if 'EXAEPI_BUILD' not in os.environ:
            return None

        base_build_dir = Path(os.environ['EXAEPI_BUILD'])

        # First, check for direct build (PC/workstation case)
        direct_bin = base_build_dir / "bin"
        if direct_bin.exists() and list(direct_bin.glob("*agent*")):
            return base_build_dir

        # If machine is specified, check for machine-specific subdirectory
        if machine:
            machine_build_dir = base_build_dir / machine
            machine_bin = machine_build_dir / "bin"
            if machine_bin.exists() and list(machine_bin.glob("*agent*")):
                return machine_build_dir

            # Also check with current machine if different
            if self.current_machine and self.current_machine != machine:
                current_machine_dir = base_build_dir / self.current_machine
                current_bin = current_machine_dir / "bin"
                if current_bin.exists() and list(current_bin.glob("*agent*")):
                    return current_machine_dir

        # Check for any machine subdirectories
        if self.current_machine:
            current_machine_dir = base_build_dir / self.current_machine
            current_bin = current_machine_dir / "bin"
            if current_bin.exists() and list(current_bin.glob("*agent*")):
                return current_machine_dir

        return None

    def validate_environment(self, machine: str = None) -> bool:
        """Validate required environment variables and paths"""
        errors = []

        # Check for EXAEPI_BUILD
        if 'EXAEPI_BUILD' not in os.environ:
            errors.append("EXAEPI_BUILD environment variable not set")
        else:
            build_dir = self._find_build_dir(machine)
            if build_dir is None:
                base_dir = Path(os.environ['EXAEPI_BUILD'])
                machine_name = machine or self.current_machine or '<machine>'
                errors.append(
                    f"No valid build found. Checked:\n"
                    f"      - Direct build: {base_dir}/bin/\n"
                    f"      - Machine subdirectory: {base_dir}/{machine_name}/bin/"
                )

        # Check for EXAEPI_DIR (needed for comparison tool)
        if 'EXAEPI_DIR' not in os.environ:
            errors.append("EXAEPI_DIR environment variable not set")
        else:
            exaepi_dir = Path(os.environ['EXAEPI_DIR'])
            chkdiff = exaepi_dir / "utilities" / "tests" / "chkdiff.sh"
            if not chkdiff.exists():
                errors.append(f"Comparison tool not found: {chkdiff}")

        # Check common directory exists
        if not self.common_dir.exists():
            errors.append(f"Common directory not found: {self.common_dir}")

        if errors:
            print("Environment validation failed:")
            for error in errors:
                print(f"  - {error}")
            return False

        return True

    def resolve_test_cases(self, cases: List[str]) -> Set[str]:
        """Resolve test case names, handling groups and wildcards"""
        resolved = set()

        for case in cases:
            if case == 'all':
                # Add all test cases
                resolved.update(self.test_cases['test_cases'].keys())
            elif case in self.test_cases.get('test_groups', {}):
                # Add test group
                resolved.update(self.test_cases['test_groups'][case])
            elif case in self.test_cases['test_cases']:
                # Add individual test case
                resolved.add(case)
            else:
                print(f"WARNING: Unknown test case or group: {case}")

        return resolved

    def resolve_machines(self, machines: List[str]) -> Set[str]:
        """Resolve machine names, handling groups"""
        resolved = set()

        for machine in machines:
            if machine == 'current':
                if self.current_machine:
                    resolved.add(self.current_machine)
                else:
                    print("ERROR: Could not auto-detect current machine")
                    sys.exit(1)
            elif machine in self.machines.get('machine_groups', {}):
                resolved.update(self.machines['machine_groups'][machine])
            elif machine in self.machines['machines']:
                resolved.add(machine)
            else:
                print(f"WARNING: Unknown machine or group: {machine}")

        return resolved

    def create_test_directory(self, case_name: str, machine: str, target_dir: Path) -> Path:
        """Create a test directory with proper symlinks"""
        case_config = self.test_cases['test_cases'][case_name]

        # Create directory name: case.machine
        dir_name = f"{case_name}.{machine}"
        test_dir = target_dir / dir_name

        # Create directory
        test_dir.mkdir(parents=True, exist_ok=True)

        # Create symlinks to common data files
        data_files = case_config.get('data_files', [])
        for data_file in data_files:
            src = self.common_dir / data_file
            dst = test_dir / data_file

            if not src.exists():
                print(f"  WARNING: Data file not found: {src}")
                continue

            # Remove existing symlink if present
            if dst.is_symlink() or dst.exists():
                dst.unlink()

            # Create relative symlink
            rel_src = os.path.relpath(src, test_dir)
            dst.symlink_to(rel_src)

        # Symlink input file
        input_file = case_config['input_file']
        src = self.common_dir / input_file
        dst = test_dir / input_file

        if src.exists():
            if dst.is_symlink() or dst.exists():
                dst.unlink()
            rel_src = os.path.relpath(src, test_dir)
            dst.symlink_to(rel_src)
        else:
            print(f"  WARNING: Input file not found: {src}")

        # Create run script
        self._create_run_script(case_name, machine, test_dir)

        # Create job script if batch mode
        machine_config = self.machines['machines'][machine]
        if machine_config.get('batch_mode', False):
            self._create_job_script(case_name, machine, test_dir)

        return test_dir

    def _create_run_script(self, case_name: str, machine: str, test_dir: Path):
        """Create machine-specific run script"""
        machine_config = self.machines['machines'][machine]
        case_config = self.test_cases['test_cases'][case_name]

        # Determine script name based on machine
        script_name = f"run.{case_name}.{machine}.sh"
        script_path = test_dir / script_name

        # Build run script content
        lines = [
            "#!/bin/bash",
            "",
        ]

        # Add environment setup
        env_setup = machine_config.get('env_setup', {})
        for key, value in env_setup.items():
            lines.append(f"export {key}={value}")

        if env_setup:
            lines.append("")

        # Determine output file name
        env_var = machine_config.get('env_var', 'HOSTNAME')
        if machine in ['dane', 'matrix', 'tuolumne']:
            lines.append(f'OUTFILE=out.${{LCHOST}}.log')
        elif machine in ['linux', 'linux-gpu']:
            lines.append(f'OUTFILE=out.{machine}.log')
        else:
            lines.append(f'OUTFILE=out.${{NERSC_HOST}}.log')

        lines.extend([
            "",
            '# Find ExaEpi executable (check direct build or machine subdirectory)',
            'if [ -d "$EXAEPI_BUILD/bin" ] && ls $EXAEPI_BUILD/bin/*agent* &> /dev/null; then',
            '    # Direct build',
            '    EXEC=$(ls $EXAEPI_BUILD/bin/*agent*)',
        ])

        # Add machine-specific subdirectory checks
        if machine in ['dane', 'matrix', 'tuolumne']:
            lines.extend([
                'elif [ -d "$EXAEPI_BUILD/$LCHOST/bin" ] && ls $EXAEPI_BUILD/$LCHOST/bin/*agent* &> /dev/null; then',
                '    # Machine-specific subdirectory',
                '    EXEC=$(ls $EXAEPI_BUILD/$LCHOST/bin/*agent*)',
            ])
        elif machine == 'perlmutter':
            lines.extend([
                'elif [ -d "$EXAEPI_BUILD/$NERSC_HOST/bin" ] && ls $EXAEPI_BUILD/$NERSC_HOST/bin/*agent* &> /dev/null; then',
                '    # Machine-specific subdirectory',
                '    EXEC=$(ls $EXAEPI_BUILD/$NERSC_HOST/bin/*agent*)',
            ])
        elif machine in ['linux', 'linux-gpu']:
            lines.extend([
                f'elif [ -d "$EXAEPI_BUILD/{machine}/bin" ] && ls $EXAEPI_BUILD/{machine}/bin/*agent* &> /dev/null; then',
                '    # Machine-specific subdirectory',
                f'    EXEC=$(ls $EXAEPI_BUILD/{machine}/bin/*agent*)',
            ])

        lines.extend([
            'else',
            '    echo "ERROR: ExaEpi executable not found in $EXAEPI_BUILD/bin/ or machine subdirectories"',
            '    exit 1',
            'fi',
            'echo "Executable file is ${EXEC}."',
            "",
            'INP=$(ls inputs*)',
            'echo "Input file is ${INP}."',
            "",
        ])

        # Add machine-specific configuration
        if machine == 'perlmutter':
            lines.extend([
                "NGPU=4",
                "",
                '# pin to closest NIC to GPU',
                'export MPICH_OFI_NIC_POLICY=GPU',
                'export OMP_NUM_THREADS=1',
                'GPU_AWARE_MPI="amrex.use_gpu_aware_mpi=1"',
                "",
                'rm -rf Backtrace* plt* cases* $OUTFILE output.dat *.core',
                'echo "  running ExaEpi with input file $INP"',
                '# CUDA visible devices are ordered inverse to local task IDs',
                '#   Reference: nvidia-smi topo -m',
                'srun --cpu-bind=cores -n $NGPU bash -c "',
                '    export CUDA_VISIBLE_DEVICES=$((3-SLURM_LOCALID));',
                '    ${EXEC} ${INP} ${GPU_AWARE_MPI}" \\',
                '    2>&1 |tee $OUTFILE',
            ])
        elif machine == 'matrix':
            lines.extend([
                "NNODE=1",
                "NGPU=4",
                "NOMP=1",
                "",
                "export OMP_NUM_THREADS=$NOMP",
                "rm -rf Backtrace* plt* cases* $OUTFILE output.dat *.core",
                "srun -n $NGPU -G $NGPU -N $NNODE -p pdebug $EXEC $INP 2>&1 > $OUTFILE",
            ])
        elif machine == 'dane':
            lines.extend([
                "NNODE=1",
                "NPROC=100",
                "NOMP=1",
                "",
                "export OMP_NUM_THREADS=$NOMP",
                "rm -rf Backtrace* plt* cases* $OUTFILE *.core output.dat",
                "srun -N $NNODE -n $NPROC -p pdebug $EXEC $INP 2>&1 > $OUTFILE",
            ])
        elif machine == 'tuolumne':
            lines.extend([
                "NNODE=1",
                "NGPU=4",
                "NOMP=1",
                "",
                "export OMP_NUM_THREADS=$NOMP",
                "export MPICH_GPU_SUPPORT_ENABLED=1",
                "rm -rf Backtrace* plt* cases* $OUTFILE *.core output.dat",
                "flux run --exclusive --nodes=$NNODE --ntasks $NGPU --gpus-per-task 1 -q=pdebug $EXEC $INP 2>&1 > $OUTFILE",
            ])
        elif machine == 'linux':
            # Standard Linux with MPI (MPICH/OpenMPI)
            ntasks = machine_config.get('tasks', 4)
            mpi_launcher = machine_config.get('mpi_launcher', 'auto')
            mpi_flags = machine_config.get('mpi_flags', '')

            lines.extend([
                f"NTASKS={ntasks}",
                "",
                "rm -rf Backtrace* plt* cases* $OUTFILE output.dat *.core",
                "",
                "# Determine MPI launcher",
            ])

            if mpi_launcher == 'auto':
                lines.extend([
                    'if command -v mpirun &> /dev/null; then',
                    '    MPI_LAUNCHER="mpirun"',
                    'elif command -v mpiexec &> /dev/null; then',
                    '    MPI_LAUNCHER="mpiexec"',
                    'else',
                    '    echo "ERROR: No MPI launcher found (mpirun or mpiexec)"',
                    '    exit 1',
                    'fi',
                    'echo "Using MPI launcher: $MPI_LAUNCHER"',
                    "",
                ])
            else:
                lines.append(f'MPI_LAUNCHER="{mpi_launcher}"')
                lines.append("")

            mpi_cmd = f'$MPI_LAUNCHER -n $NTASKS {mpi_flags} $EXEC $INP 2>&1 | tee $OUTFILE'
            lines.append(mpi_cmd)

        elif machine == 'linux-gpu':
            # Linux workstation with CUDA GPUs
            ngpus = machine_config.get('gpus', 1)
            ntasks = machine_config.get('tasks', 1)
            mpi_launcher = machine_config.get('mpi_launcher', 'auto')
            mpi_flags = machine_config.get('mpi_flags', '')
            gpu_aware_mpi = machine_config.get('gpu_aware_mpi', '')

            lines.extend([
                f"NGPUS={ngpus}",
                f"NTASKS={ntasks}",
                "",
                "rm -rf Backtrace* plt* cases* $OUTFILE output.dat *.core",
                "",
                "# Determine MPI launcher",
            ])

            if mpi_launcher == 'auto':
                lines.extend([
                    'if command -v mpirun &> /dev/null; then',
                    '    MPI_LAUNCHER="mpirun"',
                    'elif command -v mpiexec &> /dev/null; then',
                    '    MPI_LAUNCHER="mpiexec"',
                    'else',
                    '    echo "ERROR: No MPI launcher found (mpirun or mpiexec)"',
                    '    exit 1',
                    'fi',
                    'echo "Using MPI launcher: $MPI_LAUNCHER"',
                    "",
                ])
            else:
                lines.append(f'MPI_LAUNCHER="{mpi_launcher}"')
                lines.append("")

            # Set CUDA visible devices for multi-GPU
            if ngpus > 1:
                lines.extend([
                    '# Set CUDA_VISIBLE_DEVICES for multiple GPUs',
                    f'export CUDA_VISIBLE_DEVICES=$(seq -s, 0 $((NGPUS-1)))',
                    "",
                ])

            if gpu_aware_mpi:
                mpi_cmd = f'$MPI_LAUNCHER -n $NTASKS {mpi_flags} $EXEC $INP {gpu_aware_mpi} 2>&1 | tee $OUTFILE'
            else:
                mpi_cmd = f'$MPI_LAUNCHER -n $NTASKS {mpi_flags} $EXEC $INP 2>&1 | tee $OUTFILE'

            lines.append(mpi_cmd)

        lines.append("")

        # Write script
        with open(script_path, 'w') as f:
            f.write('\n'.join(lines))

        # Make executable
        script_path.chmod(0o755)

    def _create_job_script(self, case_name: str, machine: str, test_dir: Path):
        """Create batch job script for machines that use job submission"""
        machine_config = self.machines['machines'][machine]

        script_name = f"exaepi.{case_name}.{machine}.job"
        script_path = test_dir / script_name

        lines = ["#!/bin/bash -l", ""]

        # Add SBATCH directives
        if machine == 'perlmutter':
            lines.extend([
                f"#SBATCH -t {machine_config['time_limit']}",
                f"#SBATCH -N {machine_config['nodes']}",
                "#SBATCH -J ExaEpi",
                f"#SBATCH -A {machine_config['account']}",
                f"#SBATCH -q {machine_config['queue']}",
                f"#SBATCH -C {machine_config['constraints']}",
                "#SBATCH --exclusive",
                f"#SBATCH --cpus-per-task={machine_config['cpus_per_task']}",
                f"#SBATCH --gpu-bind={machine_config['gpu_bind']}",
                f"#SBATCH --ntasks-per-node={machine_config['tasks_per_node']}",
                f"#SBATCH --gpus-per-node={machine_config['gpus_per_node']}",
                "#SBATCH -o ExaEpi.o%j",
                "#SBATCH -e ExaEpi.e%j",
                "",
                "",
                'OUTFILE=out.${NERSC_HOST}.log',
                "",
                'INP=$(ls inputs*)',
                'echo "Input file is ${INP}."',
                "",
                '# Find ExaEpi executable (check direct build or machine subdirectory)',
                'if [ -d "$EXAEPI_BUILD/bin" ] && ls $EXAEPI_BUILD/bin/*agent* &> /dev/null; then',
                '    EXEC=$(ls $EXAEPI_BUILD/bin/*agent*)',
                'elif [ -d "$EXAEPI_BUILD/$NERSC_HOST/bin" ] && ls $EXAEPI_BUILD/$NERSC_HOST/bin/*agent* &> /dev/null; then',
                '    EXEC=$(ls $EXAEPI_BUILD/$NERSC_HOST/bin/*agent*)',
                'else',
                '    echo "ERROR: ExaEpi executable not found"',
                '    exit 1',
                'fi',
                'echo "Executable file is ${EXEC}."',
                "",
                '# pin to closest NIC to GPU',
                'export MPICH_OFI_NIC_POLICY=GPU',
                'export OMP_NUM_THREADS=1',
                'GPU_AWARE_MPI="amrex.use_gpu_aware_mpi=1"',
                "",
                '# CUDA visible devices are ordered inverse to local task IDs',
                '#   Reference: nvidia-smi topo -m',
                'rm -rf Backtrace* plt* cases* $OUTFILE output.dat *.core',
                'srun --cpu-bind=cores bash -c "',
                '    export CUDA_VISIBLE_DEVICES=$((3-SLURM_LOCALID));',
                '    ${EXEC} ${INP} ${GPU_AWARE_MPI}" \\',
                '    2>&1 |tee $OUTFILE',
                "",
            ])

        # Write script
        with open(script_path, 'w') as f:
            f.write('\n'.join(lines))

        # Make executable
        script_path.chmod(0o755)

    def create_baselines(self, cases: List[str], machine: str = None):
        """Create baseline test directories"""
        if machine is None:
            machine = self.current_machine

        if machine is None:
            print("ERROR: Machine not specified and could not be auto-detected")
            sys.exit(1)

        baseline_dir = self.root_dir / "baselines"
        baseline_dir.mkdir(exist_ok=True)

        resolved_cases = self.resolve_test_cases(cases)

        print(f"Creating baseline directories for machine: {machine}")
        print(f"Test cases: {', '.join(sorted(resolved_cases))}")
        print()

        for case in sorted(resolved_cases):
            print(f"Creating baseline directory for {case}.{machine}...")
            self.create_test_directory(case, machine, baseline_dir)

        print(f"\nBaseline directories created in: {baseline_dir}")

    def create_tests(self, cases: List[str], machine: str = None):
        """Create test directories"""
        if machine is None:
            machine = self.current_machine

        if machine is None:
            print("ERROR: Machine not specified and could not be auto-detected")
            sys.exit(1)

        test_dir = self.root_dir / "tests"
        test_dir.mkdir(exist_ok=True)

        resolved_cases = self.resolve_test_cases(cases)

        print(f"Creating test directories for machine: {machine}")
        print(f"Test cases: {', '.join(sorted(resolved_cases))}")
        print()

        for case in sorted(resolved_cases):
            print(f"Creating test directory for {case}.{machine}...")
            self.create_test_directory(case, machine, test_dir)

        print(f"\nTest directories created in: {test_dir}")

    def run_baselines(self, cases: List[str] = None, machine: str = None):
        """Run baseline tests"""
        if machine is None:
            machine = self.current_machine

        if machine is None:
            print("ERROR: Machine not specified and could not be auto-detected")
            sys.exit(1)

        baseline_dir = self.root_dir / "baselines"

        if not baseline_dir.exists():
            print(f"ERROR: Baseline directory not found: {baseline_dir}")
            sys.exit(1)

        machine_config = self.machines['machines'][machine]
        batch_mode = machine_config.get('batch_mode', False)

        # Find baseline directories for this machine
        pattern = f"*.{machine}"
        baseline_dirs = sorted(baseline_dir.glob(pattern))

        if not baseline_dirs:
            print(f"No baseline directories found for machine: {machine}")
            return

        # Filter by cases if specified
        if cases:
            resolved_cases = self.resolve_test_cases(cases)
            baseline_dirs = [d for d in baseline_dirs
                           if any(d.name.startswith(f"{c}.") for c in resolved_cases)]

        print(f"Running baselines for machine: {machine}")
        print(f"Batch mode: {batch_mode}")
        print()

        for test_dir in baseline_dirs:
            print(f"Processing {test_dir.name}...")

            # Check for disabled marker
            if (test_dir / ".disabled").exists():
                print("  Skipping (disabled case)")
                continue

            if batch_mode:
                # Submit job
                job_scripts = list(test_dir.glob(f"exaepi.*.{machine}.job"))
                if not job_scripts:
                    print(f"  WARNING: No job script found")
                    continue

                job_script = job_scripts[0]
                print(f"  Submitting {job_script.name}")
                subprocess.run(['sbatch', job_script.name], cwd=test_dir)
            else:
                # Run directly in background
                run_scripts = list(test_dir.glob(f"run.*.{machine}.sh"))
                if not run_scripts:
                    print(f"  WARNING: No run script found")
                    continue

                run_script = run_scripts[0]
                print(f"  Launching {run_script.name}")
                log_file = test_dir / "run.log"
                with open(log_file, 'w') as log:
                    subprocess.Popen([f'./{run_script.name}'],
                                   cwd=test_dir,
                                   stdout=log,
                                   stderr=subprocess.STDOUT)

        if not batch_mode:
            print("\nWaiting for processes to finish...")
            print("(You may need to monitor jobs manually)")

    def run_tests(self, cases: List[str] = None, machine: str = None):
        """Run test cases"""
        if machine is None:
            machine = self.current_machine

        if machine is None:
            print("ERROR: Machine not specified and could not be auto-detected")
            sys.exit(1)

        test_dir = self.root_dir / "tests"

        if not test_dir.exists():
            print(f"ERROR: Test directory not found: {test_dir}")
            sys.exit(1)

        machine_config = self.machines['machines'][machine]
        batch_mode = machine_config.get('batch_mode', False)

        # Find test directories for this machine
        pattern = f"*.{machine}"
        test_dirs = sorted(test_dir.glob(pattern))

        if not test_dirs:
            print(f"No test directories found for machine: {machine}")
            return

        # Filter by cases if specified
        if cases:
            resolved_cases = self.resolve_test_cases(cases)
            test_dirs = [d for d in test_dirs
                        if any(d.name.startswith(f"{c}.") for c in resolved_cases)]

        print(f"Running tests for machine: {machine}")
        print(f"Batch mode: {batch_mode}")
        print()

        for tdir in test_dirs:
            print(f"Processing {tdir.name}...")

            # Check for disabled marker
            if (tdir / ".disabled").exists():
                print("  Skipping (disabled case)")
                continue

            if batch_mode:
                # Submit job
                job_scripts = list(tdir.glob(f"exaepi.*.{machine}.job"))
                if not job_scripts:
                    print(f"  WARNING: No job script found")
                    continue

                job_script = job_scripts[0]
                print(f"  Submitting {job_script.name}")
                subprocess.run(['sbatch', job_script.name], cwd=tdir)
            else:
                # Run directly in background
                run_scripts = list(tdir.glob(f"run.*.{machine}.sh"))
                if not run_scripts:
                    print(f"  WARNING: No run script found")
                    continue

                run_script = run_scripts[0]
                print(f"  Launching {run_script.name}")
                log_file = tdir / "run.log"
                with open(log_file, 'w') as log:
                    subprocess.Popen([f'./{run_script.name}'],
                                   cwd=tdir,
                                   stdout=log,
                                   stderr=subprocess.STDOUT)

        if not batch_mode:
            print("\nWaiting for processes to finish...")
            print("(You may need to monitor jobs manually)")

    def compare_results(self, machine: str = None):
        """Compare test results against baselines"""
        if machine is None:
            machine = self.current_machine

        if machine is None:
            print("ERROR: Machine not specified and could not be auto-detected")
            sys.exit(1)

        baseline_dir = self.root_dir / "baselines"
        test_dir = self.root_dir / "tests"

        if not baseline_dir.exists():
            print(f"ERROR: Baseline directory not found: {baseline_dir}")
            sys.exit(1)

        if not test_dir.exists():
            print(f"ERROR: Test directory not found: {test_dir}")
            sys.exit(1)

        # Get comparison tool
        exaepi_dir = Path(os.environ.get('EXAEPI_DIR', ''))
        chkdiff = exaepi_dir / "utilities" / "tests" / "chkdiff.sh"

        if not chkdiff.exists():
            print(f"ERROR: Comparison tool not found: {chkdiff}")
            sys.exit(1)

        # Determine run command for comparison tool
        machine_config = self.machines['machines'][machine]
        compare_cmd = machine_config.get('compare_command', '')

        # Find baseline directories for this machine
        pattern = f"*.{machine}"
        baseline_dirs = sorted(baseline_dir.glob(pattern))

        if not baseline_dirs:
            print(f"No baseline directories found for machine: {machine}")
            return

        print(f"Comparing results for machine: {machine}")
        print()

        passed = 0
        failed = 0
        skipped = 0

        for bdir in baseline_dirs:
            case_name = bdir.name
            tdir = test_dir / case_name

            if not tdir.exists():
                print(f"ERROR: Test directory not found for {case_name}")
                continue

            print(f"Comparing {case_name}...")

            # Check for disabled marker
            if (tdir / ".disabled").exists():
                print("  Skipping (disabled case)")
                skipped += 1
                continue

            # Run comparison
            if compare_cmd:
                cmd = f"{compare_cmd} {chkdiff} -r {bdir}"
            else:
                cmd = f"{chkdiff} -r {bdir}"

            result = subprocess.run(
                cmd,
                shell=True,
                cwd=tdir,
                capture_output=True,
                text=True
            )

            # Check for "fail" in output
            if "fail" in result.stdout.lower() or "fail" in result.stderr.lower():
                print("  FAILED")
                failed += 1
            else:
                print("  passed")
                passed += 1

        print()
        print(f"Results: {passed} passed, {failed} failed, {skipped} skipped")

    def list_cases(self):
        """List available test cases"""
        print("Available test cases:")
        print()

        for case_name, config in sorted(self.test_cases['test_cases'].items()):
            name = config.get('name', case_name)
            desc = config.get('description', '')
            tags = ', '.join(config.get('tags', []))
            print(f"  {case_name:15} - {name}")
            if desc:
                print(f"                    {desc}")
            if tags:
                print(f"                    Tags: {tags}")
            print()

        if 'test_groups' in self.test_cases:
            print("\nTest groups:")
            for group_name, cases in sorted(self.test_cases['test_groups'].items()):
                print(f"  {group_name:15} - {', '.join(cases)}")

    def list_machines(self):
        """List available machines"""
        print("Available machines:")
        print()

        for machine_name, config in sorted(self.machines['machines'].items()):
            display = config.get('display_name', machine_name)
            scheduler = config.get('scheduler', 'unknown')
            batch = "batch" if config.get('batch_mode', False) else "interactive"
            current = " (current)" if machine_name == self.current_machine else ""
            print(f"  {machine_name:15} - {display} [{scheduler}, {batch}]{current}")

        if 'machine_groups' in self.machines:
            print("\nMachine groups:")
            for group_name, machines in sorted(self.machines['machine_groups'].items()):
                print(f"  {group_name:15} - {', '.join(machines)}")

    def generate_plots(self, cases: List[str] = None, machine: str = None):
        """Generate comparison plots using plot_results.py"""

        # Resolve machine
        machine = machine or self.current_machine
        if not machine:
            print("ERROR: Cannot determine machine. Use --machine to specify.")
            return

        print(f"Generating plots for machine: {machine}")
        print()

        # Build plot_results.py command
        plot_script = self.root_dir / "plot_results.py"

        if not plot_script.exists():
            print(f"ERROR: Plot script not found: {plot_script}")
            return

        cmd = [str(plot_script), "--machine", machine]

        # Add case filter if specified
        if cases and cases != ['all']:
            # Resolve test case groups
            resolved_cases = self.resolve_test_cases(cases)
            if resolved_cases:
                cmd.extend(["--case", ",".join(sorted(resolved_cases))])

        # Run plot generation
        print(f"Running: {' '.join(cmd)}")
        print()

        result = subprocess.run(cmd)

        if result.returncode == 0:
            print("\nPlot generation completed successfully!")
        else:
            print(f"\nPlot generation failed with exit code {result.returncode}")


def main():
    parser = argparse.ArgumentParser(
        description='ExaEpi Regression Test Orchestration Tool',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Create baseline directories for current machine
  %(prog)s create-baseline --cases standard

  # Run baselines for specific cases
  %(prog)s run-baseline --cases ca,bay --machine perlmutter

  # Create and run tests
  %(prog)s create-test --cases all
  %(prog)s run-test --cases all

  # Compare results
  %(prog)s compare

  # List available test cases and machines
  %(prog)s list-cases
  %(prog)s list-machines
        """
    )

    parser.add_argument(
        'action',
        choices=['create-baseline', 'run-baseline', 'create-test', 'run-test',
                'compare', 'plot', 'list-cases', 'list-machines', 'validate'],
        help='Action to perform'
    )

    parser.add_argument(
        '--cases',
        type=str,
        help='Comma-separated list of test cases or groups (default: all for current machine)'
    )

    parser.add_argument(
        '--machine',
        type=str,
        help='Target machine (default: auto-detect)'
    )

    parser.add_argument(
        '--config-dir',
        type=Path,
        help='Path to configuration directory (default: ./config)'
    )

    args = parser.parse_args()

    # Initialize orchestrator
    orch = RegtestOrchestrator(config_dir=args.config_dir)

    # Handle actions
    if args.action == 'validate':
        print("Validating environment...")
        if orch.validate_environment():
            print("Environment validation successful!")
            if orch.current_machine:
                print(f"Detected machine: {orch.current_machine}")
            return 0
        else:
            return 1

    elif args.action == 'list-cases':
        orch.list_cases()
        return 0

    elif args.action == 'list-machines':
        orch.list_machines()
        return 0

    # Resolve machine parameter - convert "current" to None for auto-detection
    machine = None if args.machine == 'current' else args.machine

    # Plot action doesn't require full environment validation (only reads existing data)
    if args.action == 'plot':
        cases = args.cases.split(',') if args.cases else ['all']
        orch.generate_plots(cases, machine)
        return 0

    # Validate environment for other actions
    # Pass the machine to validation if available
    if not orch.validate_environment(machine):
        print("\nPlease fix environment issues before proceeding.")
        return 1

    # Parse cases
    cases = args.cases.split(',') if args.cases else ['all']

    if args.action == 'create-baseline':
        orch.create_baselines(cases, machine)

    elif args.action == 'run-baseline':
        orch.run_baselines(cases, machine)

    elif args.action == 'create-test':
        orch.create_tests(cases, machine)

    elif args.action == 'run-test':
        orch.run_tests(cases, machine)

    elif args.action == 'compare':
        orch.compare_results(machine)

    return 0


if __name__ == '__main__':
    sys.exit(main())
