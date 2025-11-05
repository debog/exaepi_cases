#!/bin/bash

# Usage: CASE=<casename> ./run.sh -m [*job*|run]
# When using "-m run", make sure you are on compute node.

clear
rootdir=$PWD
GPU_AWARE_MPI="amrex.use_gpu_aware_mpi=1"

MYCLUSTER=""
MYHOSTNAME=""
if [[ -z $LCHOST ]]; then
    if [[ ! -z $NERSC_HOST ]]; then
        echo "NERSC_HOST is $NERSC_HOST"
        MYCLUSTER="NERSC"
        MYHOSTNAME=$NERSC_HOST
    else
        echo "ERROR: on unknown cluster! LCHOST=$LCHOST, NERSC_HOST=$NERSC_HOST"
        exit 1
    fi
else
    echo "LCHOST is $LCHOST"
    MYCLUSTER="LC"
    MYHOSTNAME=$LCHOST
fi

if [[ -z $MYCLUSTER ]]; then
    echo "MYCLUSTER variable not defined!"
    exit 1
fi
echo "MYCLUSTER is $MYCLUSTER"

write_job () {

# argument 1: filename

arg=("$@")

if [[ "$MYCLUSTER" == "LC" ]]; then
    echo "  Note: job writing not implemented for LC"
elif [[ "$MYCLUSTER" == "NERSC" ]]; then
    /bin/cat <<EOM >${arg[1]}
#!/bin/bash

#SBATCH -t 00:10:00
#SBATCH -N 1
#SBATCH -J ExaEpi
#SBATCH -A m5071_g
#SBATCH -q regular
#SBATCH -C gpu
#SBATCH --exclusive
#SBATCH --cpus-per-task=32
#SBATCH --gpu-bind=none
#SBATCH --ntasks-per-node=1
#SBATCH --gpus-per-node=${ntasks}
#SBATCH -o ExaEpi.o%j
#SBATCH -e ExaEpi.e%j


export MPICH_OFI_NIC_POLICY=GPU
export OMP_NUM_THREADS=1

# CUDA visible devices are ordered inverse to local task IDs
#   Reference: nvidia-smi topo -m
srun --cpu-bind=cores bash -c "
    export CUDA_VISIBLE_DEVICES=\$((3-SLURM_LOCALID));
    ${EXEC} ${INP} ${ARGS} ${GPU_AWARE_MPI}" \
    2>&1 |tee $outfile

EOM
fi
}

write_run () {

# argument 1: filename

arg=("$@")

if [[ "$MYCLUSTER" == "LC" ]]; then

    runcmd=""
    if [[ "x$LCHOST" == "xdane" ]]; then
        runcmd="srun -n $ntasks -N $nnodes -p pdebug"
    elif [[ "x$LCHOST" == "xmatrix" ]]; then
        runcmd="srun -p pdebug -n $ntasks -G $ntasks -N $nnodes -t 00:05:00"
    elif [[ "x$LCHOST" == "xtuolumne" ]]; then
        runcmd="flux run --exclusive --nodes=$nnodes --ntasks $ntasks -q=pdebug -t 5"
    fi

    /bin/cat <<EOM >${arg[1]}
#!/bin/bash

rm -rf $outfile plt* cases* out* Backtrace* *.core
$runcmd $EXEC $INP $ARG 2>&1 |tee $outfile
EOM

elif [[ "$MYCLUSTER" == "NERSC" ]]; then

    /bin/cat <<EOM >${arg[1]}
#!/bin/bash

# CUDA visible devices are ordered inverse to local task IDs
#   Reference: nvidia-smi topo -m
srun --cpu-bind=cores -n $ntasks bash -c "
    export CUDA_VISIBLE_DEVICES=\\\$((3-SLURM_LOCALID));
    ${EXEC} ${INP} ${ARG} ${GPU_AWARE_MPI}" \
    2>&1 |tee $outfile
EOM

fi
}

mode="job"
while getopts m: flag
do
    case "${flag}" in
        m) mode=${OPTARG};;
    esac
done

if [[ "x$CASE" == "x" ]]; then
    echo "CASE not specified; running default..."
    CASE=CA
fi
echo "CASE is $CASE"

declare -a mwprop_baseline=("0.00")
declare -a nppd_baseline=("5000000")
declare -a mwprop_vals=("0.03" "0.06" "0.09")
declare -a nppd_vals=("5" "10" "20" "50" "100")

njobs_tot=0
for mwprop in ${mwprop_vals[@]}; do
for nppd in ${nppd_vals[@]}; do
    ((njobs_tot++))
done
done

jobscript="exaepi.${MYHOSTNAME}.$CASE.job"
runscript="run.${MYHOSTNAME}.$CASE.sh"

ntasks=""
nnodes="1"
if [[ "x$MYHOSTNAME" == "xperlmutter" ]]; then
    export OMP_NUM_THREADS=1
    if [[ "x$CASE" == "xBay" ]]; then
        ntasks=1
    else
        ntasks=4
    fi
    nnodes=$(( (ntasks+3)/4 ))
elif [[ "x$MYHOSTNAME" == "xdane" ]]; then
    if [[ "x$CASE" == "xBay" ]]; then
        export OMP_NUM_THREADS=4
        ntasks=25
    else
        export OMP_NUM_THREADS=1
        ntasks=100
    fi
    nnodes=$(( (ntasks+111)/112 ))
elif [[ "x$MYHOSTNAME" == "xmatrix" ]]; then
    export OMP_NUM_THREADS=1
    if [[ "x$CASE" == "xBay" ]]; then
        ntasks=1
    else
        ntasks=4
    fi
    nnodes=$(( (ntasks+3)/4 ))
elif [[ "x$MYHOSTNAME" == "xtuolumne" ]]; then
    export OMP_NUM_THREADS=1
    if [[ "x$CASE" == "xBay" ]]; then
        ntasks=1
    else
        ntasks=4
    fi
    nnodes=$(( (ntasks+3)/4 ))
fi

INP_FILE=$rootdir/common/inputs.$CASE
outfile=out.${MYHOSTNAME}.log

EXEC=$(ls $EXAEPI_BUILD/bin/*agent*)
echo "Executable file is ${EXEC}."

numjobs=0

# run baseline case
for mwprop in ${mwprop_baseline[@]}; do
for nppd in ${nppd_baseline[@]}; do
    echo ""
    echo "Running baseline job ..."
    echo "  Medical workers proportion: $mwprop, Num. patients/doctor: $nppd"
    dirname=".run_${CASE}.${MYHOSTNAME}.baseline"
    if [ -d "$dirname" ]; then
        echo "  directory $dirname exists; checking for job completion"
        cd $dirname
        fail=0
        if [[ ! -f $outfile ]]; then
            echo "    $outfile doesn't exist; run possibly failed."
            fail=1
        else
            run_complete=$(tail -n 1 $outfile |grep "finalized")
            if [[ -z $run_complete ]]; then
                echo "    run may not have completed."
                fail=1
            fi
        fi
        cd ..
        if [[ $fail == 1 ]]; then
            echo "  last simulation failed; deleting existing directory..."
            rm -rf $dirname
        else
            echo "  simulation already completed; skipping"
            continue
        fi
    fi
    echo "  creating directory $dirname"
    mkdir $dirname

    ARG=""
    ARG+=" agent.med_workers_proportion=$mwprop"
    ARG+=" hospital_model.num_patients_per_doctor=$nppd"
    ARG+=" hospital_model.write_pltfiles=true"

    cd $dirname
    echo "  creating shortcut for input file"
    ln -sf $INP_FILE .
    INP=$(ls inputs.${CASE})
    echo "  creating shortcut for data files"
    if [[ "x$CASE" == "xCA"* ]]; then
        ln -sf $rootdir/common/CA* .
    elif [[ "x$CASE" == "xBay"* ]]; then
        ln -sf $rootdir/common/BayArea* .
    fi
    ln -sf $rootdir/common/July4.cases .
    echo "  writing job script"
    write_job $# $jobscript
    echo "  writing run script"
    write_run $# $runscript

    if [[ "x$mode" == "xjob" ]]; then
        if [[ -f $jobscript ]]; then
            echo "  submitting job ..."
            sbatch $jobscript
        fi
    else
        if [[ -f $runscript ]]; then
            echo "  running job ..."
            if [[ "$MYCLUSTER" == "LC" ]]; then
                ((numjobs++))
                bash $runscript > run.log &
            else
                bash $runscript > run.log
            fi
        fi
    fi
    cd $rootdir

    if [[ "$MYCLUSTER" == "LC" ]]; then
        if [[ "x$mode" == "xrun" ]]; then
            if [[ $numjobs -ge 4 ]]; then
                echo "Waiting for submitted jobs to finish..."
                jobs -l
                wait
                numjobs=0
            fi
        fi
    fi
done
done

# run other cases
njobs_done=0
for mwprop in ${mwprop_vals[@]}; do
for nppd in ${nppd_vals[@]}; do
    ((njobs_done++))
    echo ""
    echo "Running job $njobs_done of $njobs_tot..."
    echo "  Medical workers proportion: $mwprop, Num. patients/doctor: $nppd"
    dirname=".run_${CASE}.${MYHOSTNAME}.mwprop$(printf "%1.2f" $mwprop).nppd$(printf "%03d" $nppd)"
    if [ -d "$dirname" ]; then
        echo "  directory $dirname exists; checking for job completion"
        cd $dirname
        fail=0
        if [[ ! -f $outfile ]]; then
            echo "    $outfile doesn't exist; run possibly failed."
            fail=1
        else
            run_complete=$(tail -n 1 $outfile |grep "finalized")
            if [[ -z $run_complete ]]; then
                echo "    run may not have completed."
                fail=1
            fi
        fi
        cd ..
        if [[ $fail == 1 ]]; then
            echo "  last simulation failed; deleting existing directory..."
            rm -rf $dirname
        else
            echo "  simulation already completed; skipping"
            continue
        fi
    fi
    echo "  creating directory $dirname"
    mkdir $dirname

    ARG=""
    ARG+=" agent.med_workers_proportion=$mwprop"
    ARG+=" hospital_model.num_patients_per_doctor=$nppd"
    ARG+=" hospital_model.write_pltfiles=true"

    cd $dirname
    echo "  creating shortcut for input file"
    ln -sf $INP_FILE .
    INP=$(ls inputs.${CASE})
    echo "  creating shortcut for data files"
    if [[ "x$CASE" == "xCA"* ]]; then
        ln -sf $rootdir/common/CA* .
    elif [[ "x$CASE" == "xBay"* ]]; then
        ln -sf $rootdir/common/BayArea* .
    fi
    ln -sf $rootdir/common/July4.cases .
    echo "  writing job script"
    write_job $# $jobscript
    echo "  writing run script"
    write_run $# $runscript

    if [[ "x$mode" == "xjob" ]]; then
        if [[ -f $jobscript ]]; then
            echo "  submitting job ..."
            sbatch $jobscript
        fi
    else
        if [[ -f $runscript ]]; then
            echo "  running job ..."
            if [[ "$MYCLUSTER" == "LC" ]]; then
                ((numjobs++))
                bash $runscript > run.log &
            else
                bash $runscript > run.log
            fi
        fi
    fi
    cd $rootdir

    if [[ "$MYCLUSTER" == "LC" ]]; then
        if [[ "x$mode" == "xrun" ]]; then
            if [[ $numjobs -ge 4 ]]; then
                echo "Waiting for submitted jobs to finish..."
                jobs -l
                wait
                numjobs=0
            fi
        fi
    fi
done
done

if [[ "$MYCLUSTER" == "LC" ]]; then
    echo "waiting for processes to finish ..."
    jobs -l
    wait
fi

echo "done."
exit 0
