#!/usr/bin/ruby -w

require_relative "SystemCommand"
require "fileutils"

$sysc = SystemCommand.new
$sysc.setDryRun(false)
$sysc.setVerbose(false)

def recurse(dir)
    Dir.foreach(dir) {
        |entry__|
        entry = File.join(dir, entry__)
        next if (!File.lstat(entry).directory?)
        next if (!entry__.match(%r|\A\.+|).nil?)
        ok = true
        Dir.foreach(entry) {
            |file|
            if (file.match(/saktad/i) or file.match(/inspelad/i))
                ok = false
                break
            end
        }
        if (ok)
            files = []
            Dir.foreach(entry) {
                |filexx|
                files.push(File.join(entry, filexx)) if (filexx.match(%r|\.flac\Z|))
            } 
            if (!files.empty?)
                $sysc.safeExec(File.join(File.split(File.expand_path($0))[0], 'adjust_flac_freq.rb'), ['--D33', '-e', '44100', '--replace', '--nobackup'] + files)
                $sysc.safeExec('touch', [File.join(entry, 'Saktad i batch')])
            end
        end
    }
end

ARGV.each {
    |arg|
    recurse(arg)
}
