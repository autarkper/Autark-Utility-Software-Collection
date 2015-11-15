#!/usr/bin/ruby -w

$:.push(File.split($0)[0])

require_relative "SystemCommand"

require 'getoptlong'
require 'thread'
require "tempfile"

options = [
#    ["--dry-run", GetoptLong::NO_ARGUMENT ],
    ]

opts = GetoptLong.new()
opts.set_options(*options)

$myprog = File.basename($0)

$dry_run = false



$sc = SystemCommand.new
$sc.setVerbose(true)

$sc.setDryRun($dry_run)

$tfconv = Tempfile.new($myprog)
$tfconv.close

def puts_command(cmd, args)
    return $sc.safeExec(cmd, args)
end

def process(source)
    puts_command("iconv", ['--verbose', '-f', 'iso88591', '-t', 'utf8', '-o', $tfconv.path, source])
    puts_command("chmod", ['--reference', source, $tfconv.path])
    # puts_command("mv", [source, source + ".bak-iconv"])
    puts_command("mv", [$tfconv.path, source])
end


ARGV.each {
    |f|
    bExists = FileTest.exists?(f)
    if (bExists)
        staten = File.stat(f)
        next if (staten.directory?)
        if (staten.size > 0)
            process( f )
        else
            $stderr.puts "'#{f}': zero-length file"
        end
    else
        fail "'#{f}': file not found"
    end
}


