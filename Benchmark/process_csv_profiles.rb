# This script parses CSV files generated by nvprof using the following command:
#     nvprof --csv -u ms --print-gpu-trace --log-file trace_gpu_1%p \
#         --profile-all-processes
# Specifically, this looks for any instances of kernel co-scheduling. For each
# log, it will print the percentage of kernels that had *some* overlap with
# another log.
require 'json'

# Returns a dict mapping file name -> array of kernel runs. The array of kernel
# runs consists of a list of times in the following order:
# [start time, duration, kernel name].
def load_trace_files(directory)
  trace_files = Dir[directory + "/trace_gpu_*"]
  to_return = {}
  trace_files.each do |filename|
    content = []
    File.open(filename, 'rb') {|f| content = f.read.split(/\n+/)}
    content.map! {|line| line.strip}
    content.delete_if {|line| line =~ /^==/}
    content.delete_if {|line| line =~ /^\s*$/}
    content.delete_if {|line| line =~ /^ms/}
    kernel_runs = []
    content.each do |line|
      # Get rid of argument lists, the commas in them break our simple parsing
      line.gsub!(/\([^)]*,[^)]*\)/, "()")
      # Get rid of the number in [...] after the kernel names.
      line.gsub!(/\) \[[^\]]*\]/, ") []")
      cols = line.split(/,/)
      next if cols.size < 3
      next if cols[0] =~ /"/
      name = cols[-1].gsub(/"/, "")
      # We'll ignore memcpy and memset times for now
      next if name =~ /\[CUDA/
      start_time = cols[0].to_f
      duration = cols[1].to_f
      kernel_runs << [start_time, duration, name]
    end
    next if kernel_runs.size == 0
    # Ensure each list is sorted by start time.
    to_return[filename] = kernel_runs.sort {|a, b| a[0] <=> b[0]}
  end
  to_return
end

# Takes a file's array of runtimes and returns a dict separating runtimes by
# kernel name.
def separate_trace_by_kernel(file_data)
  to_return = {}
  file_data.each do |d|
    to_return[d[2]] = [] if !to_return.include?(d[2])
    to_return[d[2]] << [d[0], d[1]]
  end
  to_return
end

# Takes the data returned by load_trace_files. For the given key, calculates
# the percentage of kernels which were overlapped by some kernel in one of the
# other logs. Returns a percentage, between 0.0 and 100.0.
def get_file_overlap_percentage(all_data, key)
  kernels = all_data[key]
  overlapped = 0
  kernels.each do |kernel|
    start_time = kernel[0]
    end_time = kernel[0] + kernel[1]
    all_data.each do |filename, values|
      # Make sure not to compare the key of interest to itself.
      next if filename == key
      overlap_found = false
      values.each do |value|
        # All values are in sorted order, so we can stop looking at this list
        # if we're at a time that starts after the key we care about.
        break if value[0] > end_time
        value_end_time = value[0] + value[1]
        next if value_end_time < start_time
        overlap_found = true
        break
      end
      if overlap_found
        # If we've already seen overlap with one kernel, don't look for another
        overlapped += 1
        break
      end
    end
  end
  ((overlapped.to_f) / kernels.size.to_f) * 100.0
end

# Identical to get_file_overlap_percentage, but returns overlap percentages for
# each unique kernel in the file. Returns a map: kernel name -> percentage.
def get_kernel_overlap_percentage(all_data, key)
  kernels = separate_trace_by_kernel(all_data[key])
  to_return = {}
  kernels.each do |kernel_name, kernel|
    overlapped = 0
    kernel.each do |interval|
      start_time = interval[0]
      end_time = interval[0] + interval[1]
      all_data.each do |filename, values|
        next if filename == key
        overlap_found = false
        values.each do |value|
          break if value[0] > end_time
          value_end_time = value[0] + value[1]
          next if value_end_time < start_time
          overlap_found = true
          break
        end
        if overlap_found
          overlapped += 1
          break
        end
      end
    end
    to_return[kernel_name] = (overlapped.to_f / kernel.size.to_f) * 100.0
  end
  to_return
end

# Takes an array containing start time and duration, returns a string of the
# interval.
def interval_to_string(a)
  "%.03f-%.03f" % [a[0], a[0] + a[1]]
end

# Takes 2 arrays of intervals and returns an array of intervals where both were
# overlapping.
def get_overlaps(a, b)
  to_return = []
  a_index = 0
  b_index = 0
  while a_index < a.size
    while b_index < b.size
      a_val = a[a_index]
      b_val = b[b_index]
      a_end = a_val[0] + a_val[1]
      # Move to the next a_val if we're at a b_val that starts after it.
      break if b_val[0] > a_end
      b_end = b_val[0] + b_val[1]
      # Move to the next b_val if we're below the start of the current a_val
      if b_end < a_val[0]
        b_index += 1
        next
      end
      # We know there's overlap now, so calculate the interval.
      a_starts_later = a_val[0] >= b_val[0]
      overlap_start = a_starts_later ? a_val[0] : b_val[0]
      overlap_end = a_end < b_end ? a_end : b_end
      kernel_names = a_val[2] + " + " + b_val[2]
      overlap_interval = [overlap_start, overlap_end - overlap_start,
        kernel_names]
      puts "Overlap of (%s) and (%s) = (%s)" % [interval_to_string(a_val),
        interval_to_string(b_val), interval_to_string(overlap_interval)]
      to_return << overlap_interval
      # Decide whether to advance a_index or b_index
      if a_index >= a.size - 1
        # Don't advance a_index if we're at the last one already.
        b_index += 1
        next
      end
      next_a_end_time = a[a_index + 1][0] + a[a_index + 1][1]
      if b_index >= b.size - 1
        # Don't advance b_index if we're at the last one already.
        break
      end
      next_b_end_time = b[b_index + 1][0] + b[b_index + 1][1]
      # We know that both a_index and b_index can be advanced, so we'll choose
      # the one with the earliest next end time so we won't miss any overlaps.
      break if next_a_end_time <= next_b_end_time
      b_index += 1
    end
    a_index += 1
  end
  to_return
end

# Returns all instances of overlapping kernels. This consists of 3 maps:
# [{2-overlap-names -> [array of intervals]}, {3 -> ...}, {4 -> ...}]. Does not
# consider cases of more than 4 overlapping kernels.
def get_all_overlap(all_data)
  single_overlaps = {}
  all_data.each_key do |k_a|
    all_data.each_key do |k_b|
      next if k_a == k_b
      overlaps_key = [k_a, k_b].sort
      next if single_overlaps.include?(overlaps_key)
      data_a = all_data[k_a]
      data_b = all_data[k_b]
      overlaps = get_overlaps(data_a, data_b)
      next if overlaps.size <= 0
      single_overlaps[overlaps_key] = overlaps
    end
  end
  double_overlaps = {}
  single_overlaps.each do |overlaps_key, values|
    all_data.each_key do |data_key|
      next if overlaps_key.include?(data_key)
      new_overlaps_key = overlaps_key + [data_key]
      new_overlaps_key.sort!
      next if double_overlaps.include?(new_overlaps_key)
      data_values = all_data[data_key]
      overlaps = get_overlaps(data_values, values)
      next if overlaps.size <= 0
      double_overlaps[new_overlaps_key] = overlaps
    end
  end
  triple_overlaps = {}
  double_overlaps.each do |overlaps_key, values|
    all_data.each_key do |data_key|
      next if overlaps_key.include?(data_key)
      new_overlaps_key = overlaps_key + [data_key]
      new_overlaps_key.sort!
      next if triple_overlaps.include?(new_overlaps_key)
      data_values = all_data[data_key]
      overlaps = get_overlaps(data_values, values)
      next if overlaps.size <= 0
      triple_overlaps[new_overlaps_key] = overlaps
    end
  end
  [single_overlaps, double_overlaps, triple_overlaps]
end

def print_overlapped_percentages(directory)
  data = load_trace_files(directory)
  data.each_key do |k|
    percentages = get_kernel_overlap_percentage(data, k)
    puts "In file #{k}:"
    percentages.each {|name, v| puts "  Kernel #{name}: #{v.to_s}% overlap."}
  end
end

# Combines overlap data into a simpler map: kernel names -> total overlap time
def combine_overlap_data(overlaps)
  to_return = {}
  to_return.default = 0.0
  overlaps.each do |interval|
    to_return[interval[2]] += interval[1]
  end
  to_return.sort {|a, b| b[1] <=> a[1]}
end

def print_specific_overlap_data(directory)
  data = load_trace_files(directory)
  overlap_by_file = get_all_overlap(data)
  overlap_by_file.each_with_index do |overlaps, i|
    overlap_count = i + 2
    puts "Instances of #{overlap_count.to_s} concurrent kernels:"
    overlaps.each do |file_names, data|
      puts "  Instances of overlap between #{file_names}:"
      combined_data = combine_overlap_data(data)
      combined_data.each_with_index do |interval, i|
        #if i > 20
        #  puts "    <More than 20 results. Omitting remainder.>"
        #  break
        #end
        puts "    #{interval[0]}: #{interval[1]}ms total overlap"
      end
    end
  end
end

def dump_trace_json(directory)
  data = load_trace_files(directory)
  to_print = "var all_data = "
  to_print += JSON.pretty_generate(data)
  to_print = to_print.chomp
  to_print += ";"
  puts to_print
end

if ARGV.size < 1
  puts "Usage: ruby #{__FILE__} <directory containing CSV nvprof files>"
  exit 1
end
directory = ARGV[0]

#print_specific_overlap_data(directory)
dump_trace_json(directory)
