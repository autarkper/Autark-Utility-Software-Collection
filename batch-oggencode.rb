#!/usr/bin/ruby -w

$:.push(File.split($0)[0])

require "SystemCommand"
require "AutarkFileUtils"

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
    ["--lame", GetoptLong::NO_ARGUMENT ],
    ["--copy", GetoptLong::NO_ARGUMENT ],
    ["--tag", GetoptLong::NO_ARGUMENT ],
    ]

opts = GetoptLong.new()
opts.set_options(*options)

def getCpuCount()
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
    return count
end


@@show_help = false
@@out_dir = nil
@@dry_run = false
@@overwrite = false
@@max_threads = getCpuCount()
@@find_dir = []
@@find_pattern = '*.flac'
@@find_maxdepth = nil
@@find_mindepth = nil
@@find_prune = nil
@@flatten = false
@@quality = nil
@@verbose = false
@@lame = false
@@tag = false
@@copy = false

opts.each {
    | opt, arg |
    if (opt == "--help")
        @@show_help = true
    elsif (opt == "--target-dir")
        @@out_dir = arg
    elsif (opt == "--dry-run")
        @@dry_run = true
    elsif (opt == "--overwrite")
        @@overwrite = true
    elsif (opt == "--threads")
        @@max_threads = arg.to_i
    elsif (opt == "--find-dir")
        @@find_dir << arg
    elsif (opt == "--find-pattern")
        @@find_pattern = arg
    elsif (opt == "--find-maxdepth")
        @@find_maxdepth = arg
    elsif (opt == "--find-mindepth")
        @@find_mindepth = arg
    elsif (opt == "--find-prune")
        @@find_prune = arg
    elsif (opt == "--flatten")
        @@flatten = true
    elsif (opt == "--quality")
        @@quality = arg
    elsif (opt == "--verbose")
        @@verbose = true
    elsif (opt == "--lame")
        @@lame = true
    elsif (opt == "--copy")
        @@copy = true
    elsif (opt == "--tag")
        @@tag = true
    end
}


if (@@out_dir.nil? && ARGV.length > 0)
    @@out_dir = ARGV.pop
end

@@usage = <<END_USAGE
usage 1:
    #{File.basename($0)} [options] file-list target-directory
        Example: "#{File.basename($0)} *.flac /media/iPod/flac"
usage 2:
    #{File.basename($0)} [options] --target-dir directory file-pattern
        Example: "#{File.basename($0)} --target-dir /media/iPod/flac *.flac"
usage 3:
    #{File.basename($0)} [options] --target-dir directory [--find-dir directory-to-find-file-pattern-in] --find-pattern pattern-to-send-to-find
        Example: "#{File.basename($0)} --target-dir /media/iPod/flac --find-dir /tmp/flac --find-pattern '*.flac'"
END_USAGE

if ((ARGV.length < 1 && @@find_dir.length == 0) || @@show_help)

    options_string = "Options:\n"
    options_array =[]
    options.each {
        |option|
        options_array.push(option[0])
    }
    options_string += options_array.join("\n")

    puts @@usage
    puts options_string
    exit
end

if (ARGV.length > 0 && @@find_dir.length > 0)
    puts "Error: file list and --find-dir are mutually exclusive!"
    puts @@usage
    exit
end

if (@@copy && @@lame)
    puts "Error: --copy and --lame are mutually exclusive!"
    puts @@usage
    exit
end

@@sc = SystemCommand.new
@@sc.setVerbose(true)
@@sc.setDryRun(@@dry_run)

@@sc_silent = @@sc.dup
@@sc_silent.setVerbose(@@verbose)

def puts_command(cmd, args)
    return @@sc.safeExec(cmd, args)
end

def stripIllegal(filename)
    stripped = filename.gsub(/["*:<>?\\\|]/) {|ch| '%%%x' % ch[0]}
    stripped.gsub!(/./) {
        |ch| 
        chr = ch[0]
        #p chr
        (chr >= 32 && chr != 127 ) ? ch : ('%%%x' % chr)
    }
    return stripped
end

@@created_dir_mutex = Mutex.new
@@created_dirs = {}
@@temp_files = {}
@@targets = {}

def make_dirs(sourcen, reldir = nil)
    source = reldir.nil? ? sourcen: AutarkFileUtils::make_relative(sourcen, reldir)

    fi = File.split(source)
    source_dir = fi[0]

    if (@@flatten || (source_dir[0..0] == '/' && reldir.nil?))
        source_dir = (dirs = source_dir.split('/')).empty? ? '' : dirs.last
    end

    @@created_dir_mutex.synchronize {
        cached_dir = @@created_dirs[source_dir]
        if (cached_dir != nil) then return cached_dir end

        target_dir = File.join(@@out_dir, source_dir)

        if (!FileTest.exists?(target_dir))
            @@sc_silent.safeExec("mkdir", ['-p', target_dir])
        end

        file_exists = FileTest.exists?(target_dir)
        if (not file_exists and not @@dry_run)
            fail "target-directory '#{target_dir}' does not exist"
        end

        if (file_exists)
            outstat = File.stat(target_dir)
            if (not outstat.directory?)
                fail "target-directory '#{target_dir}' not a directory"
            end
        end

        @@created_dirs[source_dir] = target_dir
        return target_dir
    }
end


def do_touch(reference, target)
    @@sc_silent.safeExec("touch", ['--no-create', "--reference=#{reference}", target])
end

@@exists = 0
@@converted = 0

def process__(job, source, *args)
    safesource = stripIllegal(source)
    
    base = File.basename(safesource).sub(/(.+)\.[^.]*/, '\1')
    target_dir = make_dirs(safesource, *args)
    target = File.join(target_dir, @@copy ? File.basename(safesource) : base + (@@lame ? ".mp3" : ".ogg"))
    
    exists = FileTest.exists?(target)
    # the "+ 2" is to compensate for minor time differences on some file systems
    if (not  exists or @@overwrite or (File.stat(target).mtime + 2) < File.stat(source).mtime)
        p [File.stat(target).mtime, File.stat(source).mtime] if exists
        @@thread_mutex.synchronize {@@targets[job] = target}

        if (@@copy)
            args = [source, target]
            args.unshift('-v') if (@@verbose)
            puts_command("cp", args)
        else
            target_tmp = target + ".tmp" # work on a temporary file
            @@created_dir_mutex.synchronize {@@temp_files[target_tmp] = 1}
            if (@@lame)
                mf_args = [source, '--export-tags-to=-']
                tag_args = []
                @@sc_silent.execReadPipe("metaflac", mf_args) {
                    |fh|
                    tags = {}
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

                lame_args = ['-q', (@@quality || '2'), tag_args, "-", target_tmp]
                lame_args << '--quiet' if (!@@verbose)

                @@sc.execReadPipe("flac", ["-s", "-c", "-d", source]) {
                    |outpipe|
                    @@sc.execReadPipe("lame", lame_args.flatten, outpipe) {
                    }
                }
            else
                ogg_args = [source, '-o', target_tmp, '-q', (@@quality || '5')]
                ogg_args << '--quiet' if (!@@verbose)

                puts_command("oggenc", ogg_args)
            end
            do_touch(source, target_tmp)
            puts_command("mv", [target_tmp, target]) # now is the time to commit the change
            @@created_dir_mutex.synchronize {@@temp_files.delete(target_tmp)}
        end
        
        @@thread_mutex.synchronize {
            @@converted += 1
            @@targets.delete(job)
        }
    else
        puts "don't overwrite: " + target
        @@thread_mutex.synchronize {@@exists += 1}
    end
end
@@target_count = 0

@@thread_count = 0
@@thread_mutex = Mutex.new
@@thread_condition = ConditionVariable.new
@@jobs_done = 0
@@jobs_ok = 0
@@jobs_total = 0

if (@@max_threads < 1)
    @@max_threads = 1
end

@@interrupted = false
trap("INT") { @@interrupted = true }

class MyExc < Exception
end

def process(source, *args)
    @@thread_mutex.synchronize {
        @@jobs_total += 1

        while (@@thread_count >= @@max_threads)
            @@thread_condition.wait(@@thread_mutex)
            raise MyExc.new if @@interrupted
        end
        
        Thread.new {
            job = nil
            @@thread_mutex.synchronize {
                @@thread_count += 1
                job = @@jobs_total
                puts "Job #{job}/#{@@target_count} start..."
            }
            begin
                process__(job, source, *args)
                @@thread_mutex.synchronize {@@jobs_ok +=1;}
            ensure
                @@thread_mutex.synchronize {
                    @@jobs_done += 1; @@thread_count -= 1; @@thread_condition.signal
                    puts "Job #{job} finished, #{@@target_count - @@jobs_done}/#{@@target_count} remaining."
                }
            end
            }.run
        }
end

@@once = false

def process_filename(f, *args)
    bExists = FileTest.exists?(f)
    if (bExists)
        staten = File.stat(f)
        next if (staten.directory?)
        if (staten.size > 0)
#            make_dirs("dummy") if (!@@once) # test that directories are alright
            @@once = true
            process(f, *args)
        else
            $stderr.puts "'#{f}': zero-length file"
        end
    else
        fail "'#{f}': file not found"
    end
end

if (@@find_dir.empty?)
    @@find_dir << ['.']
end

begin
    file_list = nil

    if (@@find_pattern.length > 0)
        sc = SystemCommand.new
        sc.setVerbose
        
        file_list = []

        @@find_dir.each {
            |dir|
            if (@@tag)
                sc.safeExec('batch-tag-flac.rb', [dir, (@@dry_run ? '--dry-run' : nil)].compact)
            end
            find_args = [dir]
            if (!@@find_maxdepth.nil?)
                find_args.concat(['-maxdepth', @@find_maxdepth])
            end
            if (!@@find_mindepth.nil?)
                find_args.concat(['-mindepth', @@find_mindepth])
            end
            prune_arg = (!@@find_prune.nil?) ? ['-name', @@find_prune, '-prune', '-o'] : []

            base_dir = dir

            # the following is to provide for rsync-like directory semantics, with trailing '/' being significant:
            # trailing '/' means "don't include directory name in target path"
            if (dir[-1,1] != '/')
                (base_dir = File.split(dir.dup)).pop
                base_dir = File.join(base_dir)
            end

            find_args.concat [prune_arg, '-name', @@find_pattern, '-print0']
            sc.execReadPipe('find', find_args.flatten) {
                |fh|
                fh.each_line("\0") {
                    |f|
                    f.chomp!("\0")
                    file_list << [f, base_dir]
                }
            }
        }
    else
        file_list = ARGV
    end

    @@target_count = file_list.size
    file_list.each {
        |f|
        process_filename(*f)
    }


    if (@@max_threads > 0)
        @@thread_mutex.synchronize {
            while (@@jobs_total > @@jobs_done)
                @@thread_condition.wait(@@thread_mutex)
                raise MyExc.new if @@interrupted
            end
        }

        Thread.list {|thread| thread.join}
    end
rescue Exception
    @@created_dir_mutex.synchronize {
        @@temp_files.each_key {
            |filename| puts_command("rm", [filename])
        }
    }
    exit 1
end

if (@@exists > 0)
    puts "\n#{File.basename($0)}: Not overwritten: #{@@exists}"
end
puts "\n#{File.basename($0)}: Converted #{@@converted} file#{if (@@converted != 1) then 's' end}#{if (@@dry_run) then ' (DRY RUN)' end}."

failure_count = @@jobs_total - @@jobs_ok;
if (failure_count > 0)
    puts "\n#{File.basename($0)}: Number of failures: #{failure_count}"
end
@@targets.keys.sort.each {
    |failed_job| puts "FAILED: " + @@targets[failed_job]
}

