#!/usr/bin/ruby -w

$:.push(File.split($0)[0])

require 'getoptlong'

options = [
    ["--help", "-h", GetoptLong::NO_ARGUMENT ],
    ["--dry-run", GetoptLong::NO_ARGUMENT ],
    ["--D33", GetoptLong::NO_ARGUMENT ],
    ["--new-sample-rate", "-r", GetoptLong::REQUIRED_ARGUMENT ],
    ["--expected-rate", "-e", GetoptLong::REQUIRED_ARGUMENT ],
]

opts = GetoptLong.new()
opts.set_options(*options)

@@show_help = false
@@new_sample_rate = nil
@@dry_run = false
@@overwrite = false
@@expected_rate = nil

opts.each {
    | opt, arg |
    if (opt == "--help")
        @@show_help = true
    elsif (opt == "--expected-rate")
        @@expected_rate = arg.to_i
    elsif (opt == "--new-sample-rate")
        @@new_sample_rate = arg.to_i
    elsif (opt == "--D33")
        @@new_sample_rate = 43060 # just the right adjustment for recordings with Denon at nominal rate 44100
    elsif (opt == "--dry-run")
        @@dry_run = true
    end
}

@@myprog = File.basename($0)

if (ARGV.length < 1 || @@show_help || @@new_sample_rate.nil?)
    puts "Usage: #{@@myprog} [--new-sample-rate rate-in-hz] file-list"
    exit(1)
end

@@failures = 0

ARGV.each {
    |file|

    if (!File.exists?(file))
        STDERR.puts "#{@@myprog}: file '#{file}' does not exist"
        @@failures += 1
        next
    end
 
    File.open(file, File::RDWR) {
        |io|
        io.seek(24, IO::SEEK_SET)
        freq_raw = io.read(4)
        freq = freq_raw.unpack("I")[0]
        if (!@@expected_rate.nil? && freq != @@expected_rate)
            STDERR.puts "#{@@myprog}: original frequency: #{freq}, expected: #{@@expected_rate}"
            @@failures += 1
        elsif (freq == @@new_sample_rate)
            STDERR.puts "#{@@myprog}: frequency unchanged: #{freq}"
            @@failures += 1
        else
            io.seek(24, IO::SEEK_SET)
            num = io.write([@@new_sample_rate].pack("I"))
            if (num != 4)
                STDERR.puts "#{@@myprog}: failed to write to wave file, errno: #{$?}"
                @@failures += 1
            end
        end
    }
}
exit(@@failures)
