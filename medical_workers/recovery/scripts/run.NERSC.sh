#!/bin/bash

# Usage: CASE=<casename> ./run.NERSC.sh -m [*job*|run]
# When using "-m run", make sure you are on compute node.

clear
rootdir=$PWD
GPU_AWARE_MPI="amrex.use_gpu_aware_mpi=1"

write_job () {

# argument 1: filename

arg=("$@")

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
}

write_run () {

# argument 1: filename

arg=("$@")

/bin/cat <<EOM >${arg[1]}
#!/bin/bash

# CUDA visible devices are ordered inverse to local task IDs
#   Reference: nvidia-smi topo -m
srun --cpu-bind=cores -n $ntasks bash -c "
    export CUDA_VISIBLE_DEVICES=\\\$((3-SLURM_LOCALID));
    ${EXEC} ${INP} ${ARG} ${GPU_AWARE_MPI}" \
    2>&1 |tee $outfile
EOM
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

#declare -a mwprop_vals=("0.00" "0.03" "0.06" "0.09")
declare -a mwprop_vals=("0.06")

njobs_tot=0
for mwprop in ${mwprop_vals[@]}; do
    ((njobs_tot++))
done

jobscript="exaepi.${NERSC_HOST}.$CASE.job"
runscript="run.${NERSC_HOST}.$CASE.sh"

ntasks=""
nnodes="1"
if [[ "x$NERSC_HOST" == "xperlmutter" ]]; then
    export OMP_NUM_THREADS=1
    if [[ "x$CASE" == "xBay" ]]; then
        ntasks=1
    else
        ntasks=4
    fi
    nnodes=$(( (ntasks+3)/4 ))
fi

INP_FILE=$rootdir/common/inputs.$CASE
outfile=out.${NERSC_HOST}.log

EXEC=$(ls $EXAEPI_BUILD/bin/*agent*)
echo "Executable file is ${EXEC}."

njobs_done=0
for mwprop in ${mwprop_vals[@]}; do
    ((njobs_done++))
    echo ""
    echo "Running job $njobs_done of $njobs_tot..."
    echo "  Medical workers proportion: $mwprop"
    dirname=".run_${CASE}.${NERSC_HOST}.mwprop$(printf "%1.2f" $mwprop)"
    if [ -d "$dirname" ]; then
        echo "  directory $dirname exists; checking for job completion"
        cd $dirname
        fail=0
        if [[ ! -f $outfile ]]; then
            echo "    $outfile doesn't exist; run possibly failed."
            fail=1
        else
            run_complete=$(tail -n 1 $outfile |grep "finalized")
            if [[ -z "run_complete" ]]; then
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
    ARG+=" hospital_model.num_patients_per_doctor=50000000"

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
        echo "  submitting job ..."
        sbatch $jobscript
    else
        echo "  running job ..."
        bash $runscript > run.log
    fi
    cd $rootdir
done

echo "done."
