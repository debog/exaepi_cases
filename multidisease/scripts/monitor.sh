#!/bin/bash

for j in {1..1000000}; do
    clear
    for i in .ensemble_bay*_${LCHOST}; do
        echo $i
        cat $i/*.out |grep "Run" |tail -n 6
    done
    echo ""
    for i in .ensemble_CA*_${LCHOST}; do
        echo $i
        cat $i/*.out |grep "Run" |tail -n 6
    done
    sleep 2m
done
