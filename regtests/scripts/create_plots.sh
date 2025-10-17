#!/bin/bash

rootdir=$PWD
echo "Current directory is $rootdir."

cd $rootdir/plots
rm -rf *.eps
for i in *.p; do
    echo "Generating plots with ${i} ..."
    gnuplot ${i}
done
cd $rootdir
