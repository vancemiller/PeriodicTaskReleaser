#!/bin/bash

# Runs a benchmark program with random sleep and writes output to outfile.
# Logs CPU and memory usage and writes to output file.

# Argument 1: program to run.
# Argument 2: duration.
# Argument 3: input size.
# Argument 4: output file name.
# Argument 5: random sleep flag (--randsleep).
# Argument 6: CPU core to assign (--randsleep).

program=$1
duration=$2
size=$3
outfile=$4 # ignored
randsleep=$5
if [ -n "$6" ]
then
  taskset -c -p $6 $$
fi

${program} $randsleep --duration ${duration} --size ${size} $cpu_core &>/dev/null &
pid=$!
wait ${pid}

