#!/usr/bin/ruby -w

require_relative "SystemCommand"

usage = <<ENDS
usage: #{$0}: dir [,dir] --target target-dir
required option:
        --target: the directory where the backup is stored
options:
        --wet-run: required to actually perform a backup (by default, only a dry-run is done)
        --checksum: perform a checksum comparison (very slow!)
        --batch: don't prompt for OK
        --detailed: invoke rsync with --itemize-changes
        --no-backup: don't save backup copies of old versions and deleted files
        --init: initialize target and backup directories (cannot be combined with a backup run)
        --help: show this help text
ENDS

excludes = %w(
*.o
*~
) + ["#*"]

options = { 
    "--dry-run" => 1,
    "--perms" => 1,
    "--owner" => 1,
    "--group" => 1,
    "--stats" => 1,
    "-F" => 1,
    "-h" => 1,
    "-av" => 1,
    "--delete" => 1,
    "--delete-excluded" => 1,
    "--force" => 1,
    "--hard-links" => 1,
}
require 'getoptlong'

opts = GetoptLong.new(
    [ "--help", "-h", GetoptLong::NO_ARGUMENT ],
    [ "--wet-run", GetoptLong::NO_ARGUMENT ],
    [ "--batch", GetoptLong::NO_ARGUMENT ],
    [ "--no-backup", GetoptLong::NO_ARGUMENT ],
    [ "--checksum", GetoptLong::NO_ARGUMENT ],
    [ "--target", GetoptLong::REQUIRED_ARGUMENT],
    [ "--detailed", GetoptLong::NO_ARGUMENT],
    [ "--init", GetoptLong::NO_ARGUMENT],
)

$bBatchMode = false
$bDryRun = true
$logfile = ""
$target = nil
$dobackup = true
$init = false

opts.each {
    | opt, arg |
    if (opt == "--help")
        puts usage
        exit(0)
    elsif (opt == "--batch")
        $bBatchMode = true
    elsif (opt == "--wet-run")
        $bDryRun = false
        options.delete( "--dry-run" )
    elsif (opt == "--target")
        $target = arg
    elsif (opt == "--no-backup")
        $dobackup = false
    elsif (opt == "--checksum")
        options["--checksum"] = 1
    elsif (opt == "--detailed")
        options["--itemize-changes"] = 1
    elsif (opt == "--init")
        $init = true
    end
}

$bBatchMode = $bDryRun || $bBatchMode

if ($target == nil)
    puts usage
    exit
end

if (ARGV.length < 1)
    puts usage
    exit
end

if (!$init)
    if ($bDryRun)
        puts %Q(\nDRY RUN! To perform a real backup, run with --wet-run.)
    elsif (!$dobackup)
        puts %Q(\nPlease confirm no backup of old versions and deleted files by typing "No backup")
        input = STDIN.gets.chomp
        if (input != "No backup")
            exit 0
        end
    end
end

$errors = 0
def execute(command, args)
    
    logfileh = nil
    if (!$bDryRun)
        begin
            logfileh = File.open( $logfile, "w" )
        rescue Exception => e
            STDERR.puts('ERROR: could not create log file, "' + e + '"')
            exit(1)
        end
    end

    output = proc {
        |line|
        STDOUT.puts line
        STDOUT.flush
        if (logfileh != nil)
            logfileh.puts(line)
            logfileh.flush()
        end
        }
    output.call "\nTarget directory: " + $hardtarget
    output.call "Backup directory: " + $backup_dir
    output.call "Log file: " + $logfile
    output.call "Command:\nrsync " + args.join( ' ' )
    if (!$bBatchMode && STDERR.isatty)
        STDOUT.flush
        STDERR.puts "\nOK? (Press CTRL+C to abort.)"
        begin        
            STDIN.gets
        rescue SignalException => e
            STDERR.puts "\nAborted."
            exit(1)
        end
    end

    sh = SystemCommand.new
    sh.setVerbose(false)
    sh.failSoft(true)

    rd, wr = IO.pipe
    STDERR.reopen(wr)

    poll_stderr = proc {
        while ((fhs = select([rd], nil, nil, 0)) != nil && fhs[0] != nil)
            line2 = rd.gets()
            $errors = $errors + 1;
            output.call("STDERR: " + line2)
        end
    }

    now = Time.new.to_i
    ret = sh.execReadPipe(command, args) {
        | pipe |
        begin
            output.call "Run rsync .................................................."
            pipe.each_line {
                |line|
                output.call("    " + line )
                poll_stderr.call()
            }
            output.call "...................................................rsync done"
            later = Time.new.to_i
            seconds = later - now
            output.call "Execution time: #{seconds} seconds"
        rescue Exception => e
            puts e
        end
    }
    poll_stderr.call()
    if ($errors != 0) then output.call("There were warnings or errors: #{$errors}") end
    if (ret != 0) then output.call("\nrsync returned non-zero: " + ret.to_s) end

    logfileh.close()
end

dirs = {}

ARGV.each {
    | dir |
    if dirs.has_key?(File.expand_path(dir))
        puts "repeated directory: " + dir
        exit 1
    end
    if ( dir.dup.chomp!("/") != nil )
        puts dir + ": give directory name only, without trailing '/'"
        exit 1
    end
    
    if ( dir[0,1] != "/" )
        puts dir + ": path must be absolute, not relative"
        exit 1
    end
    if ( ! File.stat(dir).directory? )
        puts dir + ": path is not a directory"
        exit 1
    end
    dirs[File.expand_path(dir)] = 1
}
ARGV.each {
    | dir |
    reldir = dir[1, dir.length]
    target_base = File.expand_path(File.join($target, '.versions', reldir))

    version_dir = File.split(target_base)[0]
    if (!FileTest.exists?(version_dir))
        if ($init)
            sc = SystemCommand.new
            sc.safeExec('mkdir', ['-p', version_dir])
        else
            puts "directory #{version_dir} does not exist, run with --init if you wish to create it"
            exit
        end
    end
    backup_suffix = "#" + Time.now.strftime("%Y-%m-%d#%X")
    $backup_dir = target_base + backup_suffix
    $logfile = File.expand_path(File.join($target, '.' + dir.split('/').join('_'))) + "-log" + backup_suffix
    $hardtarget = File.expand_path(File.join($target, reldir, ".."))
    
    if (!FileTest.exists?($hardtarget))
        if ($init)
            sc = SystemCommand.new
            sc.safeExec('mkdir', ['-p', $hardtarget])
        else
            puts "target directory (" + $hardtarget + ") must exist. Run with --init to create it."
            exit 1
        end
    end
    if (!FileTest.directory?($hardtarget))
        puts "target directory (" + $hardtarget + ") is not a directory"
        exit
    end
    
    if ($init)
        puts "will not backup in init mode"
        next
    end

    base = [
    ]
    if ($dobackup)
        base  = base + [
                "--backup",
                "--backup-dir=" + $backup_dir,
        ]
    end

    base = base + excludes.collect {
        |a|
        '--exclude=' + a
    }

    dirs = [
            dir,
            $hardtarget
        ]
    
    execute( "rsync", base + options.keys + dirs )        
}
