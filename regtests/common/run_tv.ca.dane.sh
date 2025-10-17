#!/bin/bash

OUTFILE=out.${LCHOST}.log

EXEC=$(ls $EXAEPI_BUILD/bin/*agent*)
echo "Executable file is ${EXEC}."

INP=$(ls inputs*)
echo "Input file is ${INP}."

NNODE=1
NPROC=100
NOMP=1

export OMP_NUM_THREADS=$NOMP
rm -rf Backtrace* plt* cases* $OUTFILE *.core output.dat
totalview srun -a -N $NNODE -n $NPROC -p pdebug $EXEC $INP 2>&1 |tee $OUTFILE
