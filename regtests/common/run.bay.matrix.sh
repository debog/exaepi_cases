#!/bin/bash

OUTFILE=out.${LCHOST}.log

EXEC=$(ls $EXAEPI_BUILD/bin/*agent*)
echo "Executable file is ${EXEC}."

INP=$(ls inputs*)
echo "Input file is ${INP}."

NNODE=1
NGPU=1
NOMP=1

export OMP_NUM_THREADS=$NOMP
rm -rf Backtrace* plt* cases* $OUTFILE output.dat *.core
srun -n $NGPU -G $NGPU -N $NNODE -p pdebug $EXEC $INP 2>&1 > $OUTFILE
