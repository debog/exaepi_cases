#!/bin/bash

sys_type=$NERSC_HOST

rootdir=$PWD
baseline_dir="baselines"
shell_dir="shell_directories"

echo "Current directory is $rootdir."

if [ -d "$baseline_dir" ]; then
    echo "\"baselines\" directory exists ..."
else
    echo "Creating \"baselines\" directory ..."
    mkdir $baseline_dir
fi

# copy over from shell directories
src=$rootdir/$shell_dir
dst=$baseline_dir

rsync -avzlh --delete --prune-empty-dirs $src/*.$sys_type $dst/
