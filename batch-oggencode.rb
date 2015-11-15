#!/usr/bin/ruby -w

require_relative "SystemCommand"
require_relative "AutarkFileUtils"

require 'getoptlong'
require 'thread'

options = [
    ["--help", "-h", GetoptLong::NO_ARGUMENT ],
    ["--target-dir", GetoptLong::REQUIRED_ARGUMENT ],
    ["--dry-run", GetoptLong::NO_ARGUMENT ],
    ["--threads", GetoptLong::REQUIRED_ARGUMENT ],
    ["--overwrite", GetoptLong::NO_ARGUMENT ],
    ["--find-dir", GetoptLong::REQUIRED_ARGUMENT ],
    ["--find-pattern", GetoptLong::REQUIRED_ARGUMENT ],
    ["--find-maxdepth", GetoptLong::REQUIRED_ARGUMENT ],
    ["--find-mindepth", GetoptLong::REQUIRED_ARGUMENT ],
    ["--find-prune", GetoptLong::REQUIRED_ARGUMENT ],
    ["--flatten", GetoptLong::NO_ARGUMENT ],
    ["--quality", GetoptLong::REQUIRED_ARGUMENT ],
    ["--verbose", GetoptLong::NO_ARGUMENT ],
    ["--mp3", "--lame", GetoptLong::NO_ARGUMENT ],
    ["--toflac", "--to-flac", GetoptLong::NO_ARGUMENT ],
    ["--delete-after", GetoptLong::NO_ARGUMENT ],
    ["--utility", GetoptLong::REQUIRED_ARGUMENT ],
    ["--no-mangle-filename", GetoptLong::NO_ARGUMENT ],
    ["--tag", GetoptLong::NO_ARGUMENT ],
    ["--in-place", "--inplace", GetoptLong::NO_ARGUMENT ],
    ["--verify-flac", GetoptLong::NO_ARGUMENT ],
    ]

opts = GetoptLong.new()
opts.set_options(*options)

def calculateMaxThreads()
    count = 0
    begin
        file = File.open('/proc/cpuinfo')
        file.each_line {
            |line|
            if (line.match(%r|\Aprocessor\s*:|))
                count += 1
            end
        }
    rescue
        STDERR.puts("unable to open /proc/cpuinfo")
        count = 1
    end
    return [Integer(count/2), 1].max # avoid choking all the cpus
end


$show_help = false
$out_dir = nil
$dry_run = false
$overwrite = false
$max_threads = calculateMaxThreads()
$find_dir = []
$find_pattern = '*.flac'
$find_maxdepth = nil
$find_mindepth = nil
$find_prune = nil
$flatten = false
$quality = nil
$verbose = false
$lame = false
$tag = false
$copy = false
$diff = false
$utility = nil
$nomangle = false
$toflac = false
$delete = false
$inplace = false
$verify_flac = false

opts.each {
    | opt, arg |
    if (opt == "--help")
        $show_help = true
    elsif (opt == "--target-dir")
        $out_dir = arg
    elsif (opt == "--in-place")
        $inplace = true
    elsif (opt == "--dry-run")
        $dry_run = true
    elsif (opt == "--overwrite")
        $overwrite = true
    elsif (opt == "--threads")
        $max_threads = arg.to_i
    elsif (opt == "--find-dir")
        $find_dir << arg
    elsif (opt == "--find-pattern")
        $find_pattern = arg
    elsif (opt == "--find-maxdepth")
        $find_maxdepth = arg
    elsif (opt == "--find-mindepth")
        $find_mindepth = arg
    elsif (opt == "--find-prune")
        $find_prune = arg
    elsif (opt == "--flatten")
        $flatten = true
    elsif (opt == "--quality")
        $quality = arg
    elsif (opt == "--verbose")
        $verbose = true
    elsif (opt == "--mp3")
        $lame = true
    elsif (opt == "--toflac")
        $toflac = true
    elsif (opt == "--delete-after")
        $delete = true
    elsif (opt == "--utility")
        $utility = arg
    elsif (opt == "--tag")
        $tag = true
    elsif (opt == "--verify-flac")
        $verify_flac = true
    elsif (opt == "--no-mangle-filename")
        $nomangle = true
    end
}

if (!$out_dir.nil? && $inplace)
    puts "#{File.basename($0)}: --target-dir and --in-place are mutually exclusive"
    exit
end
if ($out_dir.nil? && !$verify_flac)
    begin 
        if (ARGV.length > 0 && File.stat(ARGV[ARGV.length - 1]).directory?)
            $out_dir = ARGV.pop
        end
    rescue
    end
    if ($out_dir.nil? && !$inplace)
        puts "#{File.basename($0)}: no target directory given, use --target-dir or --in-place"
        exit
    end
end

$usage = <<END_USAGE
usage 1:
    #{File.basename($0)} [options] file-list target-directory
        Example: "#{File.basename($0)} *.flac /media/iPod/flac"
usage 2:
    #{File.basename($0)} [options] --target-dir directory file-pattern
        Example: "#{File.basename($0)} --target-dir /media/iPod/flac *.flac"
usage 3:
    #{File.basename($0)} [options] --target-dir directory [--find-dir directory-to-find-file-pattern-in] --find-pattern pattern-to-send-to-find
        Example: "#{File.basename($0)} --target-dir /media/iPod/flac --find-dir /tmp/flac --find-pattern '*.flac'"

arguments to --utility:
    copy    copy the matching files to the target.
    diff    compare matching files with the same files in the target.

Potentially problematic characters in filenames are converted to a safe target representation; use the --no-mangle-filename option to disable this behavior.
END_USAGE

if ((ARGV.length < 1 && $find_dir.length == 0) || $show_help)

    options_string = "Options:\n"
    options_array =[]
    options.each {
        |option|
        options_array.push(option[0])
    }
    options_string += options_array.join("\n")

    puts $usage
    puts options_string
    exit
end

if (ARGV.length > 0 && $find_dir.length > 0)
    puts "Error: file list and --find-dir are mutually exclusive!"
    puts $usage
    exit 1
end

if ($utility != nil && $lame)
    puts "Error: --utility and --lame are mutually exclusive!"
    puts $usage
    exit 1
end

if ($utility != nil)
    if ($utility == "copy")
        $copy = true
    elsif ($utility == "diff" || $utility == "cmp")
        $diff = true
    else
        puts "invalid utility: " + $utility
        puts $usage
        exit 1
    end
end

$sc = SystemCommand.new
$sc.setVerbose(true)
$sc.setDryRun($dry_run)

$sc_silent = $sc.dup
$sc_silent.setVerbose($verbose)

def puts_command(cmd, args)
    return $sc.safeExec(cmd, args)
end

def stripIllegal(filename)
    stripped = filename.gsub(/["*:<>?\\\|]/) {|ch| '%%%x' % ch.getbyte(0)}
    legal = filename == stripped
    stripped.gsub!(/./) {
        |ch| 
        chr = ch.getbyte(0)
        (chr >= 32 && chr != 127 ) ? ch : ('%%%x' % chr)
    }
    return [stripped, legal]
end

$created_dir_mutex = Mutex.new
$created_dirs = {}
$temp_files = {}
$targets = {}

def make_dirs(sourcen, reldir = nil)
    source = reldir.nil? ? sourcen: AutarkFileUtils::make_relative(sourcen, reldir)

    fi = File.split(source)
    source_dir = fi[0]

    if ($flatten || (source_dir[0..0] == '/' && reldir.nil?))
        source_dir = (dirs = source_dir.split('/')).empty? ? '' : dirs.last
    end

    $created_dir_mutex.synchronize {
        cached_dir = $created_dirs[source_dir]
        if (cached_dir != nil) then return cached_dir end

        relative = AutarkFileUtils::make_relative($out_dir,source_dir)
        target_dir = relative[0..0] == '/' ? relative : File.join($out_dir, relative)

        if (!FileTest.exists?(target_dir))
            $sc_silent.safeExec("mkdir", ['-p', target_dir])
        end

        file_exists = FileTest.exists?(target_dir)
        if (not file_exists and not $dry_run)
            fail "target-directory '#{target_dir}' does not exist"
        end

        if (file_exists)
            outstat = File.stat(target_dir)
            if (not outstat.directory?)
                fail "target-directory '#{target_dir}' not a directory"
            end
        end

        $created_dirs[source_dir] = target_dir
        return target_dir
    }
end

$sc_touch = $sc_silent.dup
$sc_touch.failSoft(true)

def do_touch(reference, target)
    $sc_touch.safeExec("touch", ['--no-create', "--reference=#{reference}", target])
end

$exists = 0
$converted = 0
$badnames = []

def process__(job, source, *args)
    if ($verify_flac)
        args = ['-t', '-s', source]
        puts_command("flac", args)
        $thread_mutex.synchronize {$converted += 1}
        return
    end
    stripped = stripIllegal(source)
    safesource = stripped[0]
    if ($nomangle && !stripped[1])
        $badnames << source
        safesource = source
    end
    
    if ($inplace)
        $out_dir = File.split(source)[0]
    end

    File.basename(safesource).match(/(.+)(\.[^.]*)/)
    base = $1
    target_dir = make_dirs(safesource, *args)

    target = File.join(target_dir, $utility != nil ? File.basename(safesource) : base + ($lame ? ".mp3" : ($toflac ? ".flac" : ".ogg")))
    target = File.expand_path(target)

    exists = FileTest.exists?(target)
    instat = File.stat(source)
    outstat = exists ? File.stat(target) : nil
    overwrite = $overwrite
    if (exists && (instat.ino == outstat.ino))
        STDERR.puts("input and output files are the same file")
        overwrite = false
    end

    if (not exists or (overwrite or $diff) or (outstat.mtime + 2) < instat.mtime)     # the "+ 2" is to compensate for minor time differences on some file systems
        p [outstat.mtime, instat.mtime] if exists
        $thread_mutex.synchronize {$targets[job] = target}

        can_delete = false
        if ($diff)
            args = [source, target]
            puts_command("cmp", args)
        elsif ($copy)
            args = ["-ptog", source, target]
            args.unshift('-v') if ($verbose)
            puts_command("rsync", args)
            can_delete = true
        else
            target_tmp = target + ".tmp" # work on a temporary file
            $created_dir_mutex.synchronize {$temp_files[target_tmp] = 1}
            if ($lame)
                mf_args = [source, '--export-tags-to=-']
                tag_args = []
                $sc_silent.execReadPipe("metaflac", mf_args) {
                    |fh|
                    fh.each_line {
                        |line|
                        line.match(%r{\A(.*?)=(.*)})
                        tag, value = $1, $2
                        case tag
                            when "Title" then tag_args << ['--tt', value]
                            when "Album" then tag_args << ['--tl', value]
                            when "Artist" then tag_args << ['--ta', value]
                            when "Tracknumber" then tag_args << ['--tn', value]
                        end
                    }
                }

                lame_args = ['-q', ($quality || '2'), tag_args, "-", target_tmp]
                lame_args << '--quiet' if (!$verbose)

                $sc.execReadPipe("flac", ["-s", "-c", "-d", source]) {
                    |outpipe|
                    $sc.execReadPipe("lame", lame_args.flatten, outpipe) {
                    }
                }
            elsif ($toflac)
                args = [source, '-f', '--preserve-modtime', '-o', target_tmp, '-s', ('-' + ($quality || '-best'))]

                puts_command("flac", args)
                can_delete = true
            else
                ogg_args = [source, '-o', target_tmp, '-q', ($quality || '5')]
                ogg_args << '--quiet' if (!$verbose)

                puts_command("oggenc", ogg_args)
            end
            do_touch(source, target_tmp)
            puts_command("mv", [target_tmp, target]) # now is the time to commit the change
            $created_dir_mutex.synchronize {$temp_files.delete(target_tmp)}
        end
        if ($delete && can_delete)
            puts_command("rm", [source])
        end
        
        $thread_mutex.synchronize {
            $converted += 1
            $targets.delete(job)
        }
    else
        puts "don't overwrite: " + target
        $thread_mutex.synchronize {$exists += 1}
    end
end
$target_count = 0

$thread_count = 0
$thread_mutex = Mutex.new
$thread_condition = ConditionVariable.new
$jobs_done = 0
$jobs_ok = 0
$jobs_total = 0

if ($max_threads < 1)
    $max_threads = 1
end

$interrupted = false
trap("INT") { $interrupted = true }

class MyExc < Exception
end

def process(source, *args)
    $thread_mutex.synchronize {
        $jobs_total += 1
        job = $jobs_total

        while ($thread_count >= $max_threads)
            $thread_condition.wait($thread_mutex)
            raise MyExc.new if $interrupted
        end
        
        $thread_count += 1
        puts "Job #{job}/#{$target_count} start..."

        Thread.new {
            success = false;
            begin
                process__(job, source, *args)
                success = true;
            ensure
                $thread_mutex.synchronize {
                    $jobs_ok +=1 if (success)
                    $jobs_done += 1; $thread_count -= 1;
                    puts "Job #{job} finished, #{$target_count - $jobs_done}/#{$target_count} remaining."
                    $thread_condition.signal
                }
            end
            }.run
        }
end

def process_filename(f, *args)
    bExists = FileTest.exists?(f)
    if (bExists)
        staten = File.stat(f)
        return if (staten.directory?)
        if (staten.size == 0)
            $stderr.puts "'#{f}': zero-length file"
        end
        process(f, *args)
    else
        fail "'#{f}': file not found"
    end
end

if ($find_dir.empty?)
    $find_dir << ['.']
end

begin
    file_list = nil

    if (ARGV.length > 0)
        file_list = ARGV.collect {
            |f| [f, '.']
        }
    elsif ($find_pattern.length > 0)
        sc = SystemCommand.new
        sc.setVerbose
        
        file_list = []

        $find_dir.each {
            |dir|
            if ($tag)
                sc.safeExec('batch-tag-flac.rb', [dir, ($dry_run ? '--dry-run' : nil)].compact)
            end
            find_args = [dir]
            if (!$find_maxdepth.nil?)
                find_args.concat(['-maxdepth', $find_maxdepth])
            end
            if (!$find_mindepth.nil?)
                find_args.concat(['-mindepth', $find_mindepth])
            end
            prune_arg = (!$find_prune.nil?) ? ['-name', $find_prune, '-prune', '-o'] : []

            base_dir = dir

            # the following is to provide for rsync-like directory semantics, with trailing '/' being significant:
            # trailing '/' means "don't include directory name in target path"
            if (dir[-1,1] != '/')
                (base_dir = File.split(dir.dup)).pop
                base_dir = File.join(base_dir)
            end

            find_args.concat [prune_arg, '-xtype', 'f', '-name', $find_pattern, '-print0']
            sc2 = sc.dup
            sc2.failSoft(true) # we want to handle all files we can, even though some directories may not be readable
            sc2.execReadPipe('find', find_args.flatten) {
                |fh|
                fh.each_line("\0") {
                    |f|
                    f.chomp!("\0")
                    file_list << [f, base_dir]
                }
            }
        }
    else
        puts "\nArgument/option mis-match"
    end

    if (file_list.size <= 0)
        puts "\nNo files matching search criteria"
        return
    else
        puts("\nNumber of files found: #{file_list.size}")
    end

    if ($delete)
        file_list.each {
            |f|
            puts f[0].inspect
        }
        puts "\nPlease confirm deletion of source files after processing by typing \"Delete\""
        input = STDIN.gets.chomp
        if (input.chomp != "Delete")
            exit 0
        end
    end

    $target_count = file_list.size
    file_list.each {
        |f|
        process_filename(*f)
    }


    if ($max_threads > 0)
        $thread_mutex.synchronize {
            while ($jobs_total > $jobs_done)
                $thread_condition.wait($thread_mutex)
                raise MyExc.new if $interrupted
            end
        }

        Thread.list {|thread| thread.join}
    end
rescue Exception
    $created_dir_mutex.synchronize {
        $temp_files.each_key {
            |filename| puts_command("rm", [filename])
        }
    }
    exit 1
end

if ($exists > 0)
    puts "\n#{File.basename($0)}: Not overwritten: #{$exists}"
end
if ($converted > 0)
    puts "\n#{File.basename($0)}: Sucessfully processed #{$converted} file#{if ($converted != 1) then 's' end}#{if ($dry_run) then ' (DRY RUN)' end}."
end

failure_count = $jobs_total - $jobs_ok;
if (failure_count > 0)
    puts "\n#{File.basename($0)}: Number of failures: #{failure_count}"
end

STDOUT.flush

$targets.keys.sort.each {
    |failed_job| STDERR.puts "FAILED: " + $targets[failed_job]
}

$badnames.each {
    |badname| STDERR.puts "BAD FILENAME: " + badname
}
