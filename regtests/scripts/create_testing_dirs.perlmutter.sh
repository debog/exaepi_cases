#!/bin/bash

sys_type=$NERSC_HOST

rootdir=$PWD
test_dir="tests"
shell_dir="shell_directories"

echo "Current directory is $rootdir."

if [ -d "$test_dir" ]; then
    echo "\"tests\" directory exists ..."
else
    echo "Creating \"tests\" directory ..."
    mkdir $test_dir
fi

# copy over from shell directories
src=$rootdir/$shell_dir
dst=$test_dir

rsync -avzlh --delete --prune-empty-dirs $src/*.$sys_type $dst/
