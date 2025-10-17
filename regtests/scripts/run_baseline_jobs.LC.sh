#!/bin/bash

rootdir=$PWD
echo "Current directory is $rootdir."
baseline_dir="baselines"

sys_type=$LCHOST
run_prefix="run"

if [ -d "$baseline_dir" ]; then

    echo "\"baselines\" directory exists ..."

    for i in $baseline_dir/*.$sys_type; do
        echo "entering $i ..."
        cd $i
        if [ -f ".disabled" ]; then
            echo "    Skipping (disabled case)"
        else
            runscript=$(ls $run_prefix.*.$sys_type.sh)
            echo "    launching $runscript."
            ./$runscript > run.log &
        fi
        cd $rootdir
    done

    echo "waiting for processes to finish ..."
    jobs -l
    wait
    echo "done."

else
    echo "ERROR: no baselines directory!"
fi
