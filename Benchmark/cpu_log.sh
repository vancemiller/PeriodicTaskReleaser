pid=$1
outfile=$2
pname=$3
echo "Timestamp, program, PID, %cpu %mem" > $outfile # erase the output file
while kill -0 $pid 2>/dev/null;
do
  echo -n "$(date +%s.%N), ${pname}, ${pid}, " >> $outfile
  stdbuf -oL ps --no-headers -p $pid -o %cpu,%mem | sed 's/^ *//g' | tr -s " " | cut --delimiter=" " --output-delimiter="," --fields=1,2 >> $outfile
  sleep 0.5
done
