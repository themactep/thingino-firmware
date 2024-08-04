#!/bin/ruby
# frozen_string_literal: true
#
# Firmware spitter
# Paul Philippov <paul@themactep.com>
#
# 2022-11-16: Initial version
# 2023-04-16: Support for dd older than v9.0
#             Use the last found mtdparts
# 2024-03-02: Extract an arbitrary range of addresses
# 2024-07-26: More strict search for mtdparts

require 'fileutils'

def show_usage_and_die(message = nil)
  puts message if message
  puts "Usage: #{$PROGRAM_NAME} <binary file> [<from address> <to address>]"
  puts ARGV.map.with_index {|x, idx| "#{idx} => #{x}"}.join("\n")
  exit 1
end

def input_file_name
  @input_file_name ||= ARGV[0]
end

def address_from
  unless ARGV[1]
    puts "Start address is not set"
    return
  end
  @address_from ||= ARGV[1]
  # FIXME: process suffix
  if @address_from.to_s.start_with?('0x')
    @address_from=@address_from.to_i(16)
  else
    @address_from=@address_from.to_i
  end
  @address_from
end

def address_till
  unless ARGV[2]
    puts "Finish address is not set. Constructing..."
  end
  @address_till ||= if ARGV[2]
    @address_till = ARGV[2]
    # FIXME: process suffix
    if @address_till.to_s.start_with?('0x')
      @address_till=@address_till.to_i(16)
    else
      @address_till=@address_till.to_i
    end
    @address_till
  else
    full_length
  end
end

def address_range_length
  @address_range_length ||= address_till - address_from
end

def full_length
  puts "Checking full file length"
  @full_length ||= File.size(input_file_name)
  #`stat -c%s #{input_file_name}`
  puts "-> #{@full_length}"
end

def extract_a_chunk
  puts "#{address_from} #{address_till}"
  output_file_name = format('0x%08X-0x%08X.bin', address_from, address_till)
  `dd if=#{input_file_name} of=#{output_file_name} skip=#{address_from}B bs=#{address_range_length} count=1`
end

def extract_all
  puts "Processing #{input_file_name} file."

  @text = `strings "#{input_file_name}" | grep mtdparts=.*_sfc:[0-9] | tail -1`
  if @text.eql?('')
    puts 'ERROR: mtdparts not found.'
    exit 2
  end

  puts "Found mtdparts: #{@text}"

  outdir = "#{input_file_name}_split"
  # if File.exist?(outdir)
  # puts "ERROR! Output directory #{outdir} exists!"
  # exit 3
  # end
  FileUtils.mkdir(outdir) unless File.directory?(outdir)

  offset = 0
  /mtdparts=\w+_sfc:\d{3,}[\w(),-@]+/.match(@text)[0].split(':')[1].split(',').each_with_index do |mtdpart, idx|
    puts "\nParsing #{mtdpart}"

    /(?<mtdpart_size>([\w@]+|-))\((?<mtdpart_name>\w+)\)/ =~ mtdpart
    puts "Name: #{mtdpart_name}"
    puts "Size: #{mtdpart_size}"

    if /@/.match?(mtdpart_size)
      puts "Size #{mtdpart_size} consists of size and offset. Extracting size per se."
      x = mtdpart_size.split('@', 2)
      mtdpart_size = x[0]
      offset = x[1] unless x[1].eql?('-')
      puts "Size: #{mtdpart_size}"
      puts "Offset: #{offset}"
    end

    if /^0x/.match?(mtdpart_size)
      puts "Size #{mtdpart_size} is in hexadecimal format. Converting to decimal."
      mtdpart_size = mtdpart_size.hex
      puts "Size: #{mtdpart_size}"
    end

    if /^0x/.match?(offset.to_s)
      puts "Offset #{offset} is in hexadecimal format. Converting to decimal."
      offset = offset.hex
      puts "Offset: #{offset}"
    end

    case mtdpart_size[-1]
    when 'K', 'k'
      puts "Size #{mtdpart_size} is in kilobytes. Converting to bytes."
      mtdpart_size = mtdpart_size.chop.to_i * 1024
    when 'M', 'm'
      puts "Size #{mtdpart_size} is in megabytes. Converting to bytes."
      mtdpart_size = mtdpart_size.chop.to_i * 1024 * 1024
    when '-'
      puts 'Size is not set. Calculating from filesize and pointer.'
      puts "Binary file size: #{full_length}"
      mtdpart_size = full_length - offset
    end

    case offset[-1]
    when 'K', 'k'
      puts "Size #{offset} is in kilobytes. Converting to bytes."
      offset = offset.chop.to_i * 1024
    when 'M', 'm'
      puts "Size #{offset} is in megabytes. Converting to bytes."
      offset = offset.chop.to_i * 1024 * 1024
    end

    puts "Size: #{mtdpart_size}"
    puts "Offset: #{offset}"

    fname = "#{input_file_name}_split/#{idx + 1}-#{mtdpart_name}.bin"
    puts "Extracting partition #{mtdpart_name} (#{mtdpart_size}) to #{fname}."
    if `dd --version|head -1|awk '{print $3}'`.to_f > 9.0
      `dd if="#{input_file_name}" of="#{fname}" bs=#{mtdpart_size} count=1 skip=#{offset}B status=progress`
    else
      `dd if="#{input_file_name}" of="#{fname}" bs=1 count=#{mtdpart_size} skip=#{offset} status=progress`
    end

    offset = offset.to_i + mtdpart_size
  end
end

show_usage_and_die "Please provide a file name" if ARGV.empty?

puts "input_file_name = #{input_file_name}"
puts "address_from = #{address_from}"
puts "address_till = #{address_till}"

if @address_from
  puts "Address range given. Extracting part."
  extract_a_chunk
else
  puts "No address range given. Extracting everything."
  extract_all
end

puts "\nDone."
exit 0
