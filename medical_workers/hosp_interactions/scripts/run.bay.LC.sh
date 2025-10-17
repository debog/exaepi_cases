#!/bin/bash

clear
rootdir=$PWD

write_run () {

# argument 1: filename

arg=("$@")

/bin/cat <<EOM >${arg[1]}
#!/bin/bash

rm -rf $outfile plt* cases* out* Backtrace* *.core
$runcmd $EXEC $INP $ARG 2>&1 |tee $outfile
EOM
}

CASE=Bay
runscript="run.${LCHOST}.$CASE.sh"

ntasks=""
runcmd=""
if [[ "x$LCHOST" == "xdane" ]]; then
    export OMP_NUM_THREADS=4
    ntasks=25
    nnodes=$(( (ntasks+111)/112 ))
    runcmd="srun -n $ntasks -N $nnodes -p pdebug"
elif [[ "x$LCHOST" == "xmatrix" ]]; then
    export OMP_NUM_THREADS=1
    ntasks=1
    nnodes=$(( (ntasks+3)/4 ))
    runcmd="srun -p pdebug -n $ntasks -G $ntasks -N $nnodes"
elif [[ "x$LCHOST" == "xtuolumne" ]]; then
    export OMP_NUM_THREADS=1
    ntasks=1
    nnodes=$(( (ntasks+3)/4 ))
    runcmd="flux run --exclusive --nodes=$nnodes --ntasks $ntasks -q=pdebug"
fi

INP_FILE=$rootdir/common/inputs.$CASE
outfile=out.${LCHOST}.log

EXEC=$(ls $EXAEPI_BUILD/bin/*agent*)
echo "Executable file is ${EXEC}."

dirname=".run_${CASE}.${LCHOST}"
if [ -d "$dirname" ]; then
    echo "  deleting existing directory $dirname"
    rm -rf $dirname
fi
echo "  creating directory $dirname"
mkdir $dirname

cd $dirname
echo "  creating shortcut for input file"
ln -sf $INP_FILE .
INP=$(ls inputs.${CASE})
echo "  creating shortcut for data files"
ln -sf $rootdir/common/$CASE* .
ln -sf $rootdir/common/July4.cases .
echo "  writing run script"
write_run $# $runscript

echo "  running case ..."
bash $runscript
cd $rootdir
