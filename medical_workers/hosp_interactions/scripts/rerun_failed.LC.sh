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

if [[ "x$CASE" == "x" ]]; then
    echo "CASE not specified; running default..."
    CASE=CA
fi
echo "CASE is $CASE"

declare -a mwprop_vals=("0.00" "0.03" "0.06" "0.09")
declare -a xmit_hosp_d2d_vals=("0.000" "0.006" "0.012")
declare -a xmit_hosp_d2p_vals=("0.000" "0.005" "0.010")
declare -a xmit_hosp_p2d_vals=("0.000" "0.006" "0.012")
declare -a xmit_hosp_p2p_vals=("0.000" "0.003" "0.006")

runscript="run.${LCHOST}.$CASE.sh"

ntasks=""
runcmd=""
if [[ "x$LCHOST" == "xdane" ]]; then
    if [[ "x$CASE" == "xBay" ]]; then
        export OMP_NUM_THREADS=4
        ntasks=25
    else
        export OMP_NUM_THREADS=1
        ntasks=100
    fi
    nnodes=$(( (ntasks+111)/112 ))
    runcmd="srun -n $ntasks -N $nnodes -p pdebug"
elif [[ "x$LCHOST" == "xmatrix" ]]; then
    export OMP_NUM_THREADS=1
    if [[ "x$CASE" == "xBay" ]]; then
        ntasks=1
    else
        ntasks=4
    fi
    nnodes=$(( (ntasks+3)/4 ))
    runcmd="srun -p pdebug -n $ntasks -G $ntasks -N $nnodes"
elif [[ "x$LCHOST" == "xtuolumne" ]]; then
    export OMP_NUM_THREADS=1
    if [[ "x$CASE" == "xBay" ]]; then
        ntasks=1
    else
        ntasks=4
    fi
    nnodes=$(( (ntasks+3)/4 ))
    runcmd="flux run --exclusive --nodes=$nnodes --ntasks $ntasks -q=pdebug"
fi

INP_FILE=$rootdir/common/inputs.$CASE
outfile=out.${LCHOST}.log

EXEC=$(ls $EXAEPI_BUILD/bin/*agent*)
echo "Executable file is ${EXEC}."

numjobs=0
for mwprop in ${mwprop_vals[@]}; do
for xmitd2d in ${xmit_hosp_d2d_vals[@]}; do
for xmitd2p in ${xmit_hosp_d2p_vals[@]}; do
for xmitp2d in ${xmit_hosp_p2d_vals[@]}; do
for xmitp2p in ${xmit_hosp_p2p_vals[@]}; do
    echo ""
    dirname=".run_${CASE}.${LCHOST}.mwprop$(printf "%1.2f" $mwprop).xmitd2d$(printf "%1.3f" $xmitd2d).xmitp2d$(printf "%1.3f" $xmitp2d).xmitd2p$(printf "%1.3f" $xmitd2p).xmitp2p$(printf "%1.3f" $xmitp2p)"
    echo "Looking in $dirname"
    if [[ ! -d "$dirname" ]]; then
        echo "Directory doesn't exist; skipping"
        continue
    fi

    cd $dirname
    echo "  checking for run failure..."
    fail=0
    if [[ ! -f $outfile ]]; then
        echo "$outfile doesn't exist; run possibly failed."
        fail=1
    fi
    if [[ "$LCHOST" == "tuolumne" ]]; then
        hip_fail=$(cat $outfile |grep "hipErrorNoDevice")
        if [[ ! -z "$hip_fail" ]]; then
            echo "  encountered HIP device failure."
            fail=1
        fi
    fi

    if [[ $fail == 1 ]]; then
        echo "  re-running case ..."
        bash $runscript > run.log &
        ((numjobs++))
        echo "Number of jobs submitted: $numjobs"
    fi
    cd $rootdir

    if [[ $numjobs -ge 4 ]]; then
        echo "Waiting for submitted jobs to finish..."
        jobs -l
        wait
        numjobs=0
    fi
done
done
done
done
done

echo "waiting for processes to finish ..."
jobs -l
wait
echo "done."
