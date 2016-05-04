#!/bin/bash

iterations=10000
#Samples are sd, sf, fastHog
for sample in sd_c sf_c fastHog_c sd_zc sf_zc
do
  all_out="SCHED_OTHER/${sample}/"
  mkdir -p $all_out 
  stdbuf -oL ./benchmark_${sample} -n${iterations} --all > $all_out/results.csv
done

