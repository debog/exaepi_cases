#!/bin/bash

for j in {1..1000000}; do
    clear
    for k in bay CA US; do
        for i in .ensemble_${k}*_${LCHOST}; do
            echo $i
            cat $i/*.out |grep "Run" |tail -n 3
        done
        echo ""
    done
    sleep 2m
done
