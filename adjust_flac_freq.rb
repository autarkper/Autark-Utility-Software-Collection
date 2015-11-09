#!/usr/bin/ruby -w

$:.unshift(File.split($0)[0])

require "SystemCommand"
require "AutarkFileUtils"
require "fileutils"

require "tempfile"
require 'getoptlong'

options = [
    ["--help", "-h", GetoptLong::NO_ARGUMENT ],
    ["--D33", GetoptLong::NO_ARGUMENT ],
    ["--Q", "-Q", GetoptLong::NO_ARGUMENT ],
    ["--new-sample-rate", "-r", GetoptLong::REQUIRED_ARGUMENT ],
    ["--expected-rate", "-e", GetoptLong::REQUIRED_ARGUMENT ],
    ["--output-dir", "-o", GetoptLong::REQUIRED_ARGUMENT ],
    ["--overwrite", GetoptLong::NO_ARGUMENT ],
    ["--replace", "--inplace", GetoptLong::NO_ARGUMENT ],
    ["--nobackup", GetoptLong::NO_ARGUMENT ],
    ["--keep-backup", GetoptLong::NO_ARGUMENT ],
    ["--notouch", GetoptLong::NO_ARGUMENT ],
    ["--verbose", GetoptLong::NO_ARGUMENT ],
    ["--silent", GetoptLong::NO_ARGUMENT ],
    ["--dry-run", GetoptLong::NO_ARGUMENT ],
]

opts = GetoptLong.new()
opts.set_options(*options)

$show_help = false
$new_sample_rate = nil
$out_dir = nil
$overwrite = false
$expected_rate = nil
$replace = false
$verbose = false
$no_backup = true
$do_touch = true
$dry_run = false
$silent = false

opts.each {
    | opt, arg |
    if (opt == "--help")
        $show_help = true
    elsif (opt == "--new-sample-rate")
        $new_sample_rate = arg.to_i
    elsif (opt == "--expected-rate")
        $expected_rate = arg.to_i
    elsif (opt == "--Q")
        $new_sample_rate = 47740
        $expected_rate = 48080
    elsif (opt == "--D33")
        $new_sample_rate = 43060 # just the right adjustment for recordings with Denon at nominal rate 44100
    elsif (opt == "--output-dir")
        $out_dir = arg
    elsif (opt == "--overwrite")
        $overwrite = true
    elsif (opt == "--replace")
        $replace = true
        $overwrite = true
    elsif (opt == "--verbose")
        $verbose = true
        $silent = false
    elsif (opt == "--silent")
        $verbose = false
        $silent = true
    elsif (opt == "--keep-backup")
        $no_backup = false
    elsif (opt == "--nobackup")
        $no_backup = true
    elsif (opt == "--notouch")
        $do_touch = false
    elsif (opt == "--dry-run")
        $dry_run = true
    end
}
    
$myprog = File.basename($0)

if (ARGV.length < 1 || $show_help || $new_sample_rate.nil?)
    puts "Usage: #{$myprog} [--new-sample-rate rate-in-hz] file-list"
    exit(1)
end

if ($new_sample_rate == 44)
    $new_sample_rate = 44100
elsif ($new_sample_rate < 100)
    $new_sample_rate *= 1000
end

$sysc = SystemCommand.new
$sysc.setVerbose($verbose)
$sysc.setDryRun($dry_run)

if (!$out_dir.nil?)
    if ($replace)
        abort "#{$myprog}: options --out-dir and --replace conflict\n"
    end
    
    if (!File.exists?($out_dir))
        $sysc.safeExec('mkdir', ['-p', $out_dir])
    end

    stat = File.stat($out_dir)
    if (!stat.directory?)
        abort "#{$myprog}: output dir '#{$out_dir}' is not a directory\n"
    end
else
    $overwrite = true
    $replace = true
end


def moveFile(syscommand, source, target)
    return syscommand.safeExec('mv', [source, target])
end

$failures = 0

for_each_file = proc {
    |file|
    
    if (!File.exists?(file))
        STDERR.puts "#{$myprog}: file '#{file}' does not exist"
        exit(1)
    end
    
    stat = File.stat(file)
    if (stat.directory?)
        abort "#{$myprog}: input file '#{file}' is a directory\n"
    end

    outfile = if ($replace)
        if (!File.stat(file).writable?)
            STDERR.puts "#{$myprog}: cannot replace read-only file '#{file}'"
            exit(1)
        end
        file
    else
#if handling files in our own sub-tree, make short output paths, else make long paths
        reldir = File.split(AutarkFileUtils.make_relative(File.expand_path(file), File.expand_path('.')))[0]
        reldir.sub!(%r|^\.+/+|, '') # strip relative component from path
        newdir = File.join($out_dir, reldir)
        if (!File.exists?(newdir))
            $sysc.safeExec('mkdir', ['-p', newdir])
        end
        File.join(newdir, File.basename(file))
    end

    
    if (File.exists?(outfile) && !$overwrite)
        puts "#{$myprog}: cannot overwrite existing output file '#{outfile}'"
        exit(1)
    end

    sysco = $sysc.dup
    sysco.failSoft(true)
    
    flac_sample_rate = sysco.execBackTick('metaflac', ['--show-sample-rate', file]).to_i
    if (!$silent)
        # this is actually rather terse, compared to the verbose output
        puts "'#{file}' (#{flac_sample_rate}) -> '#{outfile}' (#{$new_sample_rate})"
    end
    
    if ($new_sample_rate == flac_sample_rate)
        STDERR.puts "#{$myprog}: frequency unchanged: #{flac_sample_rate}"
        exit(1)
    end
    if ($expected_rate != nil)
        if (flac_sample_rate != $expected_rate)
            STDERR.puts "#{$myprog}: skipping '#{file}' - sample rate '#{flac_sample_rate}' - expected '#{$expected_rate}'"
            exit(1)
        end
    end

    target_dir = File.split(outfile)[0]
    tfflac = Tempfile.new($myprog, target_dir)
    tfflac.close

    silent = $verbose ? nil : "--silent"
    flac_tmpfile = tfflac.path

    class MyException < RuntimeError
    end
    begin 
        process_flac = proc {
            |rd|
            buf = rd.read(24)
            freq_raw = rd.read(4)
            freq = freq_raw.unpack("I")[0]
            if (!$expected_rate.nil? && freq != $expected_rate)
                STDERR.puts "#{$myprog}: original frequency: #{freq}, expected: #{$expected_rate}"
                raise MyException.new               
            elsif (freq == $new_sample_rate)
                STDERR.puts "#{$myprog}: frequency unchanged: #{freq}"
                raise MyException.new               
            end
            buf += [$new_sample_rate].pack("I")
            
            sh = $sysc.dup
            sh.execWritePipe('flac', ["--best", silent, "--sample-rate=#{$new_sample_rate}", "--force", "-o", flac_tmpfile, "-"].compact) {
                |wr|

                while buf
                    wr.write(buf)
                    buf = rd.read(16000)
                end
            }
        }

        sh = $sysc.dup
        sh.execReadPipe('flac', ['--decode', '--silent', '--force', file, '-o', '-']) {
            |rd|
            process_flac.call(rd)
        }
    rescue MyException => exception
        exit(1)
    end

    metadata = nil
    if (0 != sysco.execReadPipe('metaflac', ["--export-tags-to=-", file]) {
        |rd|
        metadata = rd.read
        })
        STDERR.puts "#{$myprog}: failed to read metadata from  '#{file}'"
    end

    if (metadata && metadata.length > 0 && 0 != sysco.execWritePipe('metaflac', ["--import-tags-from=-", flac_tmpfile]) {
        |wr|
        wr.write(metadata)
        })
        STDERR.puts "#{$myprog}: failed to write metadata to '#{flac_tmpfile}'"
    end

    if ($do_touch)
        mtime = File.stat(file).mtime
        mtime += 1 # bump the modification time by just one second - should still be enough for rsync to easily discover the change
        
        if (0 != sysco.safeExec('touch', ['-m', '-d', mtime.to_s, '--no-create', flac_tmpfile]))
            STDERR.puts "#{$myprog}: failed to touch '#{outfile}'"
            exit(1)
        end
    end

    if (0 != sysco.safeExec('chmod', ['--reference', file, flac_tmpfile]))
        STDERR.puts "#{$myprog}: failed to copy file mode from  '#{file}' to '#{outfile}'"
        exit(1)
    end

    bakfile = nil
    if ($replace)
        file_fc = File.split(file)
        bakfile = File.join(file_fc[0], "bak." + file_fc[1])
        if (0 != moveFile(sysco, file, bakfile))
            STDERR.puts "#{$myprog}: failed to create backup file '#{bakfile}'"
            exit(1)
        end
    end
    
    if (0 != moveFile(sysco, flac_tmpfile, outfile))
        STDERR.puts "#{$myprog}: failed to copy #{flac_tmpfile} to '#{outfile}'"
        exit(1)
    end

    if ($replace && $no_backup && bakfile)
        if (0 != sysco.safeExec('rm', [bakfile]))
            STDERR.puts "#{$myprog}: failed to remove backup file '#{bakfile}'"
        end
    end
}

$processed_count = 0
ARGV.each {
    |file|
    $failures += 1 # will be reset on success
    $processed_count += 1
    pid = fork
    if (!pid)
        for_each_file.call(file)
        exit(0)
    else
        ec = Process.waitpid2(pid,0)[1]
        if (ec == 0) 
            $failures -= 1 # reset
        end
        next
    end
}
if ($verbose)
    puts "#{$myprog}: Files processed : #{$processed_count}"
end
if ($failures != 0)
    STDERR.puts "#{$myprog}: Failure count: #{$failures}"
end
exit($failures)
