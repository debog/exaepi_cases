#!/usr/bin/env python3
"""Parse the AMReX TinyProfiler output from each scaling run and report
per-kernel time, classified into compute, MPI, I/O, and other.  Produces
a CSV summary and a quick-look stacked-bar plot for each scenario.

Usage:
    ./analyze_scaling.py              # auto-detect rundirs in ../.scaling_study/
    ./analyze_scaling.py PATH ...     # parse explicit job-output files
"""
import os
import re
import sys
import glob
import argparse
import csv

# Kernel classification.  Match by substring on the TinyProfiler kernel name
# (the first whitespace-delimited token of each row in the Excl. table).
COMPUTE_PATTERNS = (
    'fastInteract',                  # household / school / work / neighborhood / hh-cluster
    'HospitalModel::interactAgents',
    'DiseaseStatus::updateAgents',
    'AgentContainer::infectAgents',
    'AgentContainer::updateStatus',
    'getNewStatusByAge',
    'getTotals',
    'AgentContainer::interactDay',
    'AgentContainer::interactNight',
    'AgentContainer::generateCellData',
)
MPI_PATTERNS = (
    'amrex::communicateParticlesStart',
    'amrex::communicateParticlesFinish',
    'amrex::unpackRemotes',
    'amrex::unpackBuffer',
    'ParticleCopyPlan::doHandShake',
    'ParticleCopyPlan::buildMPIStart',
    'ParticleCopyPlan::buildMPIFinish',
    'Redistribute_partition',
    'ParticleContainer::RedistributeGPU()',
    'ParticleCopyPlan::build',
)
IO_PATTERNS = (
    'WriteBinaryParticleData',
    'WriteMultiLevelPlotfile',
    'VisMF::Write',
    'ParticleContainer::WriteParticles',
    'ParticleContainer::WritePlotFile',
)


def classify(name):
    for p in MPI_PATTERNS:
        if p in name:
            return 'mpi'
    for p in IO_PATTERNS:
        if p in name:
            return 'io'
    for p in COMPUTE_PATTERNS:
        if p in name:
            return 'compute'
    return 'other'


# Detect the boundary lines of a TinyProfiler exclusive table:
#   Name                                         NCalls  Excl. Min  Excl. Avg  Excl. Max   Max %
TABLE_START = re.compile(
    r'^Name\s+NCalls\s+Excl\.\s*Min\s+Excl\.\s*Avg\s+Excl\.\s*Max\s+Max\s*%')
HBAR = re.compile(r'^-+\s*$')


def parse_excl_table(path):
    """Return list of (name, ncalls, excl_min, excl_avg, excl_max, max_pct).
    Reads only the first Excl. table in the file (later tables are duplicates
    or per-region breakdowns)."""
    rows = []
    with open(path) as f:
        in_table = False
        seen_header = False
        for line in f:
            if not seen_header and TABLE_START.match(line):
                seen_header = True
                in_table = False  # need to skip the next ----- line first
                continue
            if seen_header and HBAR.match(line):
                in_table = not in_table
                if not in_table and rows:
                    return rows
                continue
            if in_table:
                # The kernel name may contain spaces (e.g., "REG::Evolution"
                # or "amrex::ParticleToMesh").  Tokenize from the right:
                # last 5 tokens are the numeric columns, everything before is
                # the name.
                parts = line.rstrip().split()
                if len(parts) < 6:
                    continue
                try:
                    max_pct = float(parts[-1].rstrip('%'))
                    excl_max = float(parts[-2])
                    excl_avg = float(parts[-3])
                    excl_min = float(parts[-4])
                    ncalls = int(parts[-5])
                except ValueError:
                    continue
                name = ' '.join(parts[:-5])
                rows.append((name, ncalls, excl_min, excl_avg, excl_max, max_pct))
    return rows


def parse_total_time(path):
    """Return the 'TinyProfiler total time across processes' max value."""
    rgx = re.compile(r'TinyProfiler total time across processes\s*'
                     r'\[min\.\.\.avg\.\.\.max\]:\s*\S+\s*\.\.\.\s*\S+\s*\.\.\.\s*(\S+)')
    with open(path) as f:
        for line in f:
            m = rgx.search(line)
            if m:
                try: return float(m.group(1))
                except ValueError: return None
    return None


def parse_mpi_count(path):
    """Return the number of MPI processes from the agent's startup banner."""
    rgx = re.compile(r'MPI initialized with (\d+)\s+MPI processes')
    with open(path) as f:
        for line in f:
            m = rgx.search(line)
            if m: return int(m.group(1))
    return None


def summarize(path):
    """Return a dict summarizing one job's profiler output."""
    rows = parse_excl_table(path)
    total = parse_total_time(path)
    nmpi = parse_mpi_count(path)
    classes = {'compute': 0.0, 'mpi': 0.0, 'io': 0.0, 'other': 0.0}
    by_kernel = {}
    for name, ncalls, _, excl_avg, _, _ in rows:
        cls = classify(name)
        classes[cls] += excl_avg
        by_kernel[name] = (cls, ncalls, excl_avg)
    return dict(path=path, total=total, mpi_ranks=nmpi,
                compute=classes['compute'], mpi=classes['mpi'],
                io=classes['io'], other=classes['other'],
                by_kernel=by_kernel)


def find_runs(parent):
    """Find all run_*/scale_*.out files under .scaling_study/."""
    out = []
    for d in sorted(glob.glob(os.path.join(parent, 'run_*'))):
        for fn in sorted(glob.glob(os.path.join(d, 'scale_*.out'))):
            out.append(fn)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('paths', nargs='*',
                    help='Specific job .out files to parse (default: auto-detect).')
    ap.add_argument('--parent', default=None,
                    help='Override the scaling-study parent directory '
                         '(default: ../.scaling_study/ relative to this script).')
    ap.add_argument('--csv', default=None,
                    help='Write CSV summary to this path.')
    ap.add_argument('--plot', default=None,
                    help='Write a stacked-bar plot of compute / MPI / I/O / other '
                         'time vs. MPI-rank count to this path (matplotlib).')
    args = ap.parse_args()

    if args.paths:
        files = args.paths
    else:
        if args.parent is None:
            here = os.path.dirname(os.path.abspath(__file__))
            args.parent = os.path.normpath(os.path.join(here, '..', '.scaling_study'))
        files = find_runs(args.parent)

    if not files:
        print('No job-output files found.  Pass paths explicitly or check '
              '--parent.', file=sys.stderr)
        sys.exit(1)

    summaries = []
    for f in files:
        s = summarize(f)
        if s['total'] is None:
            print(f'WARN: no TinyProfiler section in {f}', file=sys.stderr)
            continue
        summaries.append(s)

    if not summaries:
        print('No parseable summaries.', file=sys.stderr); sys.exit(1)

    summaries.sort(key=lambda s: (os.path.dirname(s['path']), s['mpi_ranks'] or 0))

    # Tabular output
    print(f"{'run':<50s} {'ranks':>6s} {'total':>10s} "
          f"{'compute':>10s} {'mpi':>10s} {'io':>10s} {'other':>10s}")
    for s in summaries:
        run = os.path.basename(os.path.dirname(s['path']))
        print(f"{run:<50s} {s['mpi_ranks'] or '-':>6} "
              f"{s['total']:>10.2f} {s['compute']:>10.2f} "
              f"{s['mpi']:>10.2f} {s['io']:>10.2f} {s['other']:>10.2f}")

    if args.csv:
        with open(args.csv, 'w', newline='') as f:
            w = csv.writer(f)
            w.writerow(['run', 'mpi_ranks', 'total_s',
                        'compute_s', 'mpi_s', 'io_s', 'other_s'])
            for s in summaries:
                run = os.path.basename(os.path.dirname(s['path']))
                w.writerow([run, s['mpi_ranks'], s['total'],
                            s['compute'], s['mpi'], s['io'], s['other']])
        print(f"\nWrote CSV: {args.csv}")

    if args.plot:
        try:
            import numpy as np
            import matplotlib
            matplotlib.use('Agg')
            import matplotlib.pyplot as plt
        except ImportError as e:
            print(f'plot requires numpy + matplotlib: {e}', file=sys.stderr)
            sys.exit(1)

        # Group by scenario (run-dir prefix before _Ngpu)
        groups = {}
        for s in summaries:
            run = os.path.basename(os.path.dirname(s['path']))
            # run_CA_03D_scale_4gpu_tuolumne -> scenario: run_CA_03D_scale; ranks from name or banner
            m = re.match(r'(run_.+?_scale)_(\d+)gpu', run)
            if not m: continue
            scen = m.group(1)
            groups.setdefault(scen, []).append(s)

        n_groups = len(groups)
        if n_groups == 0:
            print('No identifiable scenarios for plotting.', file=sys.stderr)
            sys.exit(1)

        fig, axes = plt.subplots(1, n_groups, figsize=(6*n_groups, 5),
                                 squeeze=False)
        for ax, (scen, lst) in zip(axes[0], sorted(groups.items())):
            lst.sort(key=lambda s: s['mpi_ranks'] or 0)
            ranks = [s['mpi_ranks'] for s in lst]
            comp = [s['compute'] for s in lst]
            mpi  = [s['mpi'] for s in lst]
            io_  = [s['io'] for s in lst]
            oth  = [s['other'] for s in lst]
            x = np.arange(len(ranks))
            ax.bar(x, comp, label='compute', color='#3a7ca5')
            ax.bar(x, mpi,  bottom=comp, label='MPI', color='#d97706')
            ax.bar(x, io_,  bottom=[c+m for c,m in zip(comp,mpi)],
                   label='I/O', color='#5e8c61')
            ax.bar(x, oth,  bottom=[c+m+i for c,m,i in zip(comp,mpi,io_)],
                   label='other', color='#999999')
            ax.set_xticks(x); ax.set_xticklabels([str(r) for r in ranks])
            ax.set_xlabel('GPUs (= MPI ranks)')
            ax.set_ylabel('Excl. avg time per kernel category (s)')
            ax.set_title(scen)
            ax.legend(loc='upper right', fontsize=10)
            ax.grid(True, axis='y', alpha=0.3)
        plt.tight_layout()
        plt.savefig(args.plot, dpi=120, bbox_inches='tight')
        print(f"Wrote plot: {args.plot}")


if __name__ == '__main__':
    main()
