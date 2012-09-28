#!/usr/bin/ruby -w

$:.push(File.split($0)[0])

require "SystemCommand"
require "AutarkFileUtils"
require "ftools"

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
    ["--notouch", GetoptLong::NO_ARGUMENT ],
    ["--verbose", GetoptLong::NO_ARGUMENT ],
    ["--dry-run", GetoptLong::NO_ARGUMENT ],
]

opts = GetoptLong.new()
opts.set_options(*options)

@@show_help = false
@@new_sample_rate = nil
@@out_dir = nil
@@overwrite = false
@@expected_rate = nil
@@replace = false
@@verbose = false
@@do_backup = true
@@do_touch = true
@@dry_run = false

opts.each {
    | opt, arg |
    if (opt == "--help")
        @@show_help = true
    elsif (opt == "--new-sample-rate")
        @@new_sample_rate = arg.to_i
    elsif (opt == "--expected-rate")
        @@expected_rate = arg.to_i
    elsif (opt == "--Q")
        @@new_sample_rate = 47740
        @@expected_rate = 48080
    elsif (opt == "--D33")
        @@new_sample_rate = 43060 # just the right adjustment for recordings with Denon at nominal rate 44100
    elsif (opt == "--output-dir")
        @@out_dir = arg
    elsif (opt == "--overwrite")
        @@overwrite = true
    elsif (opt == "--replace")
        @@replace = true
        @@overwrite = true
    elsif (opt == "--verbose")
        @@verbose = true
    elsif (opt == "--nobackup")
        @@do_backup = false
    elsif (opt == "--notouch")
        @@do_touch = false
    elsif (opt == "--dry-run")
        @@dry_run = true
    end
}

@@myprog = File.basename($0)

if (ARGV.length < 1 || @@show_help || @@new_sample_rate.nil?)
    puts "Usage: #{@@myprog} [--new-sample-rate rate-in-hz] file-list"
    exit(1)
end

@@sysc = SystemCommand.new
@@sysc.setVerbose(@@verbose)
@@sysc.setDryRun(@@dry_run)

if (!@@out_dir.nil?)
    if (@@replace)
        abort "#{@@myprog}: options --out-dir and --replace conflict\n"
    end
    
    if (!File.exists?(@@out_dir))
        @@sysc.safeExec('mkdir', ['-p', @@out_dir])
    end

    stat = File.stat(@@out_dir)
    if (!stat.directory?)
        abort "#{@@myprog}: output dir '#{@@out_dir}' is not a directory\n"
    end
else
    if (!@@replace)
        abort "#{@@myprog}: must state either --output-dir or --replace\n"
    end
end

tmp = '/var/tmp'
tfwav = Tempfile.new(@@myprog, tmp)
tfwav.close

tfflac = Tempfile.new(@@myprog, tmp)
tfflac.close

tfmetadata = Tempfile.new(@@myprog, tmp)
tfmetadata.close

def moveFile(syscommand, source, target)
    return syscommand.safeExec('mv', [source, target])
end

@@failures = 0

ARGV.each {
    |file|

    @@failures += 1 # will be reset on success
    
    if (!File.exists?(file))
        STDERR.puts "#{@@myprog}: file '#{file}' does not exist"
        next
    end
    
    outfile = if (@@replace)
        if (!File.stat(file).writable?)
            STDERR.puts "#{@@myprog}: cannot replace read-only file '#{file}'"
            next
        end
        file
    else
#if handling files in our own sub-tree, make short output paths, else make long paths
        reldir = File.split(AutarkFileUtils.make_relative(File.expand_path(file), File.expand_path('.')))[0]
        reldir.sub!(%r|^\.+/+|, '') # strip relative component from path
        newdir = File.join(@@out_dir, reldir)
        if (!File.exists?(newdir))
            @@sysc.safeExec('mkdir', ['-p', newdir])
        end
        File.join(newdir, File.basename(file))
    end

    
    if (File.exists?(outfile) && !@@overwrite)
        puts "#{@@myprog}: cannot overwrite existing output file '#{outfile}'"
        next
    end

    if (!@@verbose)
        # this is actually rather terse, compared to the verbose output
        puts "'#{file}' -> '#{outfile}'"
    end
    
    wav_tempfile = tfwav.path

    sysco = @@sysc.dup
    sysco.failSoft(true)
    
    if (@@expected_rate != nil)
        flac_sample_rate = sysco.execBackTick('metaflac', ['--show-sample-rate', file]).to_i
        if (flac_sample_rate != @@expected_rate)
            STDERR.puts "#{@@myprog}: skipping '#{file}' - sample rate '#{flac_sample_rate}'"
            next
        end
    end
    
    if (0 != sysco.safeExec('flac', ['--decode', '--silent', '--force', file, '-o' , wav_tempfile]))
        next
    end
    
    File.chmod(0644, wav_tempfile)
    if (0 != sysco.safeExec(File.join(File.split($0)[0], 'adjust_wav_freq.rb'),
        (@@expected_rate.nil? ? [] : ['--expected-rate', @@expected_rate.to_s]) +
        ['--new-sample-rate', @@new_sample_rate.to_s , wav_tempfile]))
        next
    end
    
    silent = @@verbose ? nil : "--silent"
    
    flac_tmpfile = tfflac.path
    if (0 != sysco.safeExec('flac', ["--best", silent, "--sample-rate=#{@@new_sample_rate}", "--force", "-o", flac_tmpfile, wav_tempfile].compact))
        next
    end

    if (0 == sysco.safeExec('metaflac', ["--export-tags-to=#{tfmetadata.path}", file]))
        if (0 != sysco.safeExec('metaflac', ["--import-tags-from=#{tfmetadata.path}", flac_tmpfile]))
            STDERR.puts "#{@@myprog}: failed to copy metadata from  '#{file}' to '#{outfile}'"
        end
    end

    if (@@do_touch)
        mtime = File.stat(file).mtime
        mtime += 1 # bump the modification time by just one second - should still be enough for rsync to easily discover the change
        
        if (0 != sysco.safeExec('touch', ['-m', '-d', mtime.to_s, '--no-create', flac_tmpfile]))
            STDERR.puts "#{@@myprog}: failed to touch '#{outfile}'"
            next
        end
    end

    if (0 != sysco.safeExec('chmod', ['--reference', file, flac_tmpfile]))
        STDERR.puts "#{@@myprog}: failed to copy file mode from  '#{file}' to '#{outfile}'"
        next
    end

    if (@@replace)
        if (@@do_backup)
            file_fc = File.split(file)
            bakfile = File.join(file_fc[0], "bak." + file_fc[1])
            if (0 != moveFile(sysco, file, bakfile))
                STDERR.puts "#{@@myprog}: failed to create backup file '#{bakfile}'"
                next
            end
        end
    end
    
    if (0 != moveFile(sysco, flac_tmpfile, outfile))
        STDERR.puts "#{@@myprog}: failed to copy #{flac_tmpfile} to '#{outfile}'"
    end

    @@failures -= 1 # reset
}

exit(@@failures)

