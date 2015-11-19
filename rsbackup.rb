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
    STDERR.puts usage
    exit
end

if (ARGV.length < 1)
    STDERR.puts usage
    exit
end

if (ARGV.length > 1)
    STDERR.puts "can only handle one source directory at a time"
    exit
end

if (!$init)
    if ($bDryRun)
        STDERR.puts %Q(\nDRY RUN! To perform a real backup, run with --wet-run.)
    elsif (!$dobackup)
        STDERR.puts %Q(\nPlease confirm no backup of old versions and deleted files by typing "No backup")
        input = STDIN.gets.chomp
        if (input != "No backup")
            exit 0
        end
    end
end

$errors = 0
def execute(command, source, target, argsin)
    logfileh = nil
    if (!$bDryRun)
        begin
            logfileh = File.open( $logfile, "w" )
        rescue Exception => e
            STDERR.puts('ERROR: could not create log file, "' + e + '"')
            exit(1)
        end
    end

    output = lambda {
        |line|
        STDOUT.puts line
        STDOUT.flush
        if (logfileh != nil)
            logfileh.puts(line)
            logfileh.flush()
        end
    }
    output.call "\nSource directory: " + source
    output.call "Target directory: " + target
    if ($dobackup)
        output.call "Backup directory: " + $backup_dir
    end
    output.call "Log file: " + $logfile
    dirs = [source, target]
    args = argsin + dirs
    output.call "Command:\nrsync " + args.join( ' ' )
    if (!$bBatchMode && STDERR.isatty)
        STDOUT.flush
        STDERR.flush
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

    poll_stderr = lambda {
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
            STDERR.puts e
        end
    }
    poll_stderr.call()
    if ($errors != 0) then output.call("There were warnings or errors: #{$errors}") end
    if (ret != 0) then output.call("\nrsync returned non-zero: " + ret.to_s) end

    logfileh.close()
end

dir = File.expand_path(ARGV[0])
stat = File.stat(dir)
if ( !stat.directory? )
    STDERR.puts dir + ": path is not a directory"
    exit 1
end
if ( !stat.owned? )
    STDERR.puts dir + ": you do not own this path"
    exit 1
end

reldir = dir[1, dir.length]
target_base = File.expand_path(File.join($target, '.versions', reldir.split('/').join('@@')))

if ($dobackup)
    if (!FileTest.exists?(target_base))
        if ($init)
            sc = SystemCommand.new
            sc.safeExec('mkdir', ['-p', target_base])
        else
            STDERR.puts "backup directory #{target_base} does not exist, run with --init if you wish to create it."
            exit
        end
    end
    if ( !File.stat(target_base).owned? )
        STDERR.puts "backup directory #{target_base} is not yours."
        exit 1
    end
    if (!FileTest.writable?(target_base))
        STDERR.puts "backup directory #{target_base} is not writable."
        exit 1
    end
end

backup_suffix = "#" + Time.now.strftime("%Y-%m-%d#%X")
$backup_dir = File.join(target_base, backup_suffix)
$logfile = File.expand_path(File.join($target, '.' + dir.split('/').join('@@'))) + "-log" + backup_suffix
$hardtarget = File.expand_path(File.join($target, reldir, ".."))

if (!FileTest.exists?($hardtarget))
    if ($init)
        sc = SystemCommand.new
        sc.safeExec('mkdir', ['-p', $hardtarget])
    else
        STDERR.puts "target directory (" + $hardtarget + ") must exist. Run with --init to create it."
        exit 1
    end
end
if (!FileTest.directory?($hardtarget))
    STDERR.puts "target directory (" + $hardtarget + ") is not a directory"
    exit
end

if ($init)
    STDERR.puts "will not backup in init mode"
    exit 0
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

execute( "rsync", dir, $hardtarget, base + options.keys )
