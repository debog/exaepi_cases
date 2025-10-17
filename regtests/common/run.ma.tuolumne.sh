#!/bin/bash

OUTFILE=out.${LCHOST}.log

EXEC=$(ls $EXAEPI_BUILD/bin/*agent*)
echo "Executable file is ${EXEC}."

INP=$(ls inputs*)
echo "Input file is ${INP}."

NNODE=1
NPROC=4

rm -rf Backtrace* plt* cases* $OUTFILE output.dat *.core
flux run --exclusive --nodes=$NNODE --ntasks $NPROC --verbose --setopt=mpibind=verbose:1 -q=pdebug $EXEC $INP 2>&1 > $OUTFILE
