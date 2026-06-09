#!/bin/bash
# Single-realization H2 workforce-size study (non-HHS option, beds scaled with the
# medical-worker fraction). 365 steps, 4 MPI ranks, matched seed=1 across cases.
set -e
PROJ=/home/ghosh/Runs/exaepi/medical_workers
AGENT=/home/ghosh/Codes/ExaEpi-build/bin/agent
DATA=/home/ghosh/Codes/ExaEpi/data/CensusData
cd "$PROJ"
for case in H2_mw08 H2_mw13 H2_mw20; do
  RUNDIR="$PROJ/.run_${case}_single"
  rm -rf "$RUNDIR"; mkdir -p "$RUNDIR"
  cp "inputs/inputs_bay_${case}" "$RUNDIR/"
  cp "$DATA/BayArea.dat" "$DATA/BayArea-wf.bin" "$RUNDIR/"
  cd "$RUNDIR"
  echo "=== $case started $(date) ==="
  mpirun -n 4 "$AGENT" "inputs_bay_${case}" agent.seed=1 > run.log 2>&1
  echo "=== $case done $(date): $(grep 'Cumulative deaths:' run.log | tail -1) ==="
  cd "$PROJ"
done
echo "=== H2 single-realization study complete ==="
for case in H2_mw08 H2_mw13 H2_mw20; do
  printf '%s  ' "$case"; grep 'Cumulative deaths:' "$PROJ/.run_${case}_single/run.log" | tail -1
done
