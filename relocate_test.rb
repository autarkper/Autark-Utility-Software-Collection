#!/usr/bin/ruby -w
$:.unshift(File.split($0)[0])

require "SystemCommand"

(@@basedir = File.join("/tmp", "relocate_test_tmpdir")).freeze

@@sc = SystemCommand.new
@@sc.setVerbose(false)

def safeExec(cmd, args)
    @@sc.safeExec(cmd, args)
end

def ls(path)
    lines = @@sc.execBackTick( "ls", ['-lQUR', path])
    lines2 = []
    lines.split(/\n/).sort.each {
        |line|
        line.chomp!
        if (line.sub!(%r/\A[^"]+/, ""))
            lines2.push(line)
        end
    }
    fail "empty" if (lines2.empty?)
    lines2
end

def ln(source, dest)
    safeExec("ln", ["-sf", source, dest])
end

@@relocate_cmd = "./relocate.rb --silent "

def relocate(args)
    safeExec "./relocate.rb", args + ["--silent"]
end

begin
    safeExec "rm", ['-rf', @@basedir]

    @@mydir = File.join(@@basedir, %q|År';'iginäl dire'& 'ct""Öry|)
    @@sub = File.join(@@mydir, %q|s'ubÅÄÖöäåèéñãẽ 1|)
    safeExec "mkdir", ["-p", @@sub2 = File.join(@@sub, %q|su'b?#$( 2|)]
    safeExec "touch", [@@test1 = File.join(@@mydir, %q|t)e"dåäöÄÖèéñãng"st 1.txt|)]
    ln(File.expand_path(@@test1), @@test1_sl2 = File.join(@@sub, %q(testÅÄÖåäöèéñã~ 1-sl2.txt)))
    ln(File.expand_path(@@test1), File.join(@@sub2, %q(test 1-sl 3.txt)))
    ln(File.expand_path(@@test1), @@test1_sl2_f = File.join(@@sub2, %q(test 1-sl 2_sl.txt)))
    ln(File.expand_path(@@test1), @@test1_sl2_sl_f = File.join(@@sub2, %q(test 1-sl 2_sl_sl.txt)))
    ln(@@mydir, File.join(@@sub, %q(alias sl 1)))
    ln(@@mydir, File.join(@@sub2, %q(alias sl 2)))
    ln(@@sub, File.join(@@sub, %q(self-alias-sl 1)))
    ln("/bin", @@sub)
    ln("/bin", @@sub2)
    ln("/tmp", File.join(@@sub, %q(super-sl1)))
    ln(@@mydir, File.join(@@sub, %q(thisdir-sl1)))
    original = ls_mydir_absolute = ls(@@mydir)

    relocate([@@mydir, "--dry-run"])
    fail "diff 2" if (ls_mydir_absolute != ls(@@mydir))

    relocate([@@mydir])
    fail "diff 3" if (ls_mydir_absolute == (original_relative = ls(@@mydir)))

    relocate([@@mydir, "--convert-to-absolute-link"])
    fail "diff 4" if (ls_mydir_absolute != ls(@@mydir))
    
    (1..4).each {
        relocate([@@mydir])
        fail "diff 3" if (ls_mydir_absolute == ls(@@mydir))
        
        relocate([@@mydir, '--convert-to-absolute-link'])
        fail "diff 4" if (ls_mydir_absolute != ls(@@mydir))
    }

    # make a symbolic-link chain
    ln(File.expand_path(@@test1_sl2), @@test1_sl2_f)
    ln(File.expand_path(@@test1_sl2_f), @@test1_sl2_sl_f)
    fail "diff" if (ls_mydir_absolute == (ls(@@mydir)))
    
    ls_mydir_absolute = ls(@@mydir)
    
    relocate [@@mydir, '--convert-to-absolute-link', '--no-follow']
    fail "diff" if (ls_mydir_absolute != ls(@@mydir))
    
    relocate [@@mydir, '--convert-to-absolute-link'] # resolve symbolic-link chain
    fail "diff" if (ls_mydir_absolute == ls(@@mydir))
    
    ls_mydir_absolute = ls(@@mydir)
    
    relocate [@@mydir]   # convert all symlinks to relative before copy
    fail "diff 3" if (ls_mydir_absolute == (ls_mydir_relative = ls(@@mydir)))

    safeExec "cp", ['-a', @@mydir, @@copy = File.join(@@basedir, "copy")]
    fail "diff 3" if (ls_mydir_relative != ls(@@copy))
    
    
    fail "diff 3" if (ls_mydir_relative != ls(@@copy))

    safeExec "mv", [@@mydir, @@old = File.join(@@basedir, "old")]

    # since "original" directory cannot be found, the following would fail
    # if there were any absolute references to it left in the copy
    (1..2).each {
        relocate [@@copy, '--convert-to-absolute-link']
        relocate [@@copy]
    }

    safeExec "mv", [@@copy, @@mydir]
    
    
    fail "diff" if (original_relative != ls(@@mydir))

    relocate [@@mydir, "--convert-to-absolute-link"]
    fail "diff" if (original != ls(@@mydir))
    
    
    puts "Success!"
rescue SystemExit => exc then
    p exc
end
