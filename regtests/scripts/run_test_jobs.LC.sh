#!/bin/bash

rootdir=$PWD
echo "Current directory is $rootdir."
test_dir="tests"

sys_type=$LCHOST
run_prefix="run"

if [ -d "$test_dir" ]; then

    echo "\"tests\" directory exists ..."

    for i in $test_dir/*.$sys_type; do
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

    echo "ERROR: no tests directory!"

fi
