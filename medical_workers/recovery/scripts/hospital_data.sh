#!/bin/bash

rootdir=$PWD

for i in .run*; do
    echo "Entering $i ..."
    cd $i
    echo "Extracting hospital data ..."
    cat out.*.log |grep "hospitals over capacity" > num_bad_hospitals.dat
    echo "Done ..."
    cd $rootdir
done
