#!/usr/bin/ruby -w
$:.push(File.split($0)[0])

require "SystemCommand"

usage = <<ENDS
usage: #{$0}: dir [,dir] --target target-dir
required option:
        --target: the directory where the backup is stored
options:
        --wet-run: required to actually perform a backup (by default, only a dry-run is done)
        --checksum: perform a checksum comparison (very slow!)
        --batch: don't prompt for OK
        --detailed: invoke rsync with --itemize-changes
        --help: show this help text
ENDS

excludes = %w(
*.o
*~
) + ["#*"]

tmp = %w(
)

options = { 
    "--dry-run" => 1,
    "--perms" => 1,
    "--owner" => 1,
    "--group" => 1,
    "--stats" => 1,
}
require 'getoptlong'

opts = GetoptLong.new(
    [ "--help", "-h", GetoptLong::NO_ARGUMENT ],
    [ "--wet-run", GetoptLong::NO_ARGUMENT ],
    [ "--batch", GetoptLong::NO_ARGUMENT ],
    [ "--checksum", GetoptLong::NO_ARGUMENT ],
    [ "--target", GetoptLong::REQUIRED_ARGUMENT],
    [ "--detailed", GetoptLong::NO_ARGUMENT]
)

@@bBatchMode = false
@@bDryRun = true
@@logfile = ""
@@target = nil

opts.each {
    | opt, arg |
    if (opt == "--help")
        puts usage
        exit(0)
    elsif (opt == "--batch")
        @@bBatchMode = true
    elsif (opt == "--wet-run")
        @@bDryRun = false
        options.delete( "--dry-run" )
    elsif (opt == "--target")
        @@target = arg
    elsif (opt == "--checksum")
        options["--checksum"] = 1
    elsif (opt == "--detailed")
        options["--itemize-changes"] = 1
    end
}

@@bBatchMode = @@bDryRun || @@bBatchMode

if (@@target == nil)
    puts usage
    exit
end

if (!FileTest.exists?(@@target))
    puts "target directory (" + @@target + ") does not exist"
    exit
end
if (!FileTest.directory?(@@target))
    puts "target directory (" + @@target + ") is not a directory"
    exit
end

if (ARGV.length < 1)
    puts usage
    exit
end

if (@@bDryRun)
    puts "\nDRY RUN! To perform a real backup, run with --wet-run."
end

def execute(command, args)
    loglines = []
    
    output = proc {
        |line|
        loglines << line
        STDOUT.puts line
        STDOUT.flush
        }
    output.call "\nTarget directory: " + @@hardtarget
    output.call "Backup directory: " + @@backup_dir
    output.call "Log file: " + @@logfile
    output.call "Command:\nrsync" + args.join( ' ' )
    if (!@@bBatchMode && STDERR.isatty)
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
    ret = sh.execReadPipe(command, args) {
        | pipe |
        begin
            output.call "Run rsync .................................................."
            pipe.each_line {
                |line| 
                begin
                    output.call("    " + line )
                rescue Exception => e
                    STDERR.puts line
                end
            }
            output.call "...................................................rsync done"            
        rescue SignalException => e
        end
    }
    if (ret != 0) then output.call("\nrsync returned non-zero: " + ret.to_s) end

    if (!@@bDryRun)
        File.open( @@logfile, "w" ) {
            |logfileh|
            logfileh.puts( loglines)
        }
    end
end

dirs = {}

ARGV.each {
    | dir |
    if dirs.has_key?(File.expand_path(dir))
        puts "repeated directory: " + dir
        exit 
    end
    if ( dir.dup.chomp!("/") != nil )
        puts dir + ": give directory name only, without trailing '/'"
        exit
    end
    
    if ( dir[0,1] != "/" )
        puts dir + ": path must be absolute, not relative"
        exit
    end
    if ( ! File.stat(dir).directory? )
        puts dir + ": path is not a directory"
        exit
    end
    dirs[File.expand_path(dir)] = 1
}
ARGV.each {
    | dir |
    reldir = dir[1, dir.length]
    target_base = File.expand_path(File.join(@@target, '.versions', reldir))

    backup_suffix = "#" + Time.now.strftime("%Y-%m-%d#%X")
    @@backup_dir = target_base + backup_suffix
    @@logfile = File.expand_path(File.join(@@target, '.' + dir.split('/').join('_'))) + "-log" + backup_suffix
    @@hardtarget = File.expand_path(File.join(@@target, reldir, ".."))
    
    if (!FileTest.exists?(@@hardtarget))
        puts "target directory (" + @@hardtarget + ") must exist"
        exit
    end
    
    base = [
            "-F",
            "-h",
            "-av",
            "--backup",
            "--delete",
            "--delete-excluded",
            "--force",
            "--hard-links",
            "--backup-dir=" + @@backup_dir,
    ].compact + excludes.collect {
        |a|
        '--exclude=' + a
    }
    
    dirs = [
            dir,
            @@hardtarget
        ]
    
    execute( "rsync", base + options.keys + dirs )        
}

