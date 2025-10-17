#!/bin/bash

NGPU=4
OUTFILE=out.${NERSC_HOST}.log

EXEC=$(ls $EXAEPI_BUILD/bin/*agent*)
echo "Executable file is ${EXEC}."

INP=$(ls inputs*)
echo "Input file is ${INP}."

rm -rf Backtrace* plt* cases* $OUTFILE output.dat *.core
echo "  running ExaEpi with input file $INP"
# CUDA visible devices are ordered inverse to local task IDs
#   Reference: nvidia-smi topo -m
srun --cpu-bind=cores -n $NGPU bash -c "
    export CUDA_VISIBLE_DEVICES=\$((3-SLURM_LOCALID));
    ${EXEC} ${INP} ${GPU_AWARE_MPI}" \
    2>&1 |tee $outfile
