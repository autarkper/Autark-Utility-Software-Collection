#!/usr/bin/ruby -w

$:.unshift(File.split($0)[0])

require "SystemCommand"
require "fileutils"

require 'getoptlong'

options = [
    ["--dry-run", GetoptLong::NO_ARGUMENT ],
    ["--overwrite", GetoptLong::NO_ARGUMENT ],
    ["--keep", GetoptLong::NO_ARGUMENT ],
    ["--song-before-artist", GetoptLong::NO_ARGUMENT ],
    ["--artist-before-song", GetoptLong::NO_ARGUMENT ],
    ["--verbose", GetoptLong::NO_ARGUMENT ],
    ["--no-recurse", GetoptLong::NO_ARGUMENT ],
    ["--strip", GetoptLong::NO_ARGUMENT ],
    ]

opts = GetoptLong.new()
opts.set_options(*options)

@@dry_run = false
@@overwrite = false
@@song_before_artist = false
@@keep = false
@@verbose = false
@@recurse = true
@@strip = false

opts.each {
    | opt, arg |
    if (opt == "--dry-run")
        @@dry_run = true
    elsif (opt == "--overwrite")
        @@overwrite = true
    elsif (opt == "--keep")
        @@keep = true
    elsif (opt == "--song-before-artist")
        @@song_before_artist = true
    elsif (opt == "--artist-before-song")
        @@song_before_artist = false
    elsif (opt == "--verbose")
        @@verbose = true
    elsif (opt == "--no-recurse")
        @@recurse = false
    elsif (opt == "--strip")
        @@strip = true
    end
}

@@sysc = SystemCommand.new
@@sysc.setVerbose(false)
@@sysc_ro = @@sysc.dup
@@sysc.setDryRun(@@dry_run)

@@has_comment = []
@@skipped = []
@@skipped_files = []
@@error = []

def do_it(path, data)
    comments = 0
    if (!@@overwrite)
        komments = {}
        @@sysc_ro.execReadPipe('metaflac', [path, '--list', '--block-type=VORBIS_COMMENT']) {
            |fd|
            fd.each_line {
                |line|
                line.chop!
                if line.match(/\s*comments:\s*(\d+)/)
                    comments = $1.to_i
                end
                if line.match(/\s*comment\[\d+\]:\s*(.+)/)
                    if $1.match(/(.*?)?=(.*)/)
                        komments[$1]=$2
                    end
                end
            }
        }
        if (true)
            verbose = @@verbose
            begin
                if (komments == data)
                    if (@@verbose)
                        puts("keep unchanged tags for '#{path}':")
                    end
                    return
                elsif (comments > 0)
                    if (@@keep)
                        puts("keep old tags for '#{path}':")
                        verbose = true
                        return
                    end
                    verbose = true
                    puts("old tags for '#{path}':")
                end
            ensure
                if (verbose)
                    puts(komments.inspect)
                end
            end
        end
    end

    entries = []
    data.keys.each {|key| entries << (key + "=" + data[key])}
    puts( (@@dry_run ? '#' : '') + "metaflac " + path + " [" + entries.join(", ") + "]" )

    if (!@@dry_run)
        @@sysc.execWritePipe('metaflac', [path, '--remove-all-tags', '--import-tags-from=-', '--preserve-modtime']) {
            |fd|
            entries.each {|entry| fd.puts(entry)}
        }
    end
    @@sysc.safeExec('touch', ['--reference', path, '-d', '+5 seconds', path])
end

@@seen = {}

def demangle(string)
    # "%3f" -> "?", etc
    string.gsub(/%((?:[0-9a-f]){1,2})/) {
        $1.hex.chr
    }
end

def recurse(entry__, staten)
    entry__ = File.expand_path(entry__)
    return if (!staten.directory?)
    
    return if (@@seen.has_key?(staten.ino))
    @@seen[staten.ino] = 1
    
    entry = demangle(entry__.split(%r|/|).pop)
    ok = true

    begin
        Dir.foreach(entry__) {
            |file|
            if (file.match(/inspelad.*CD/i))
                @@skipped.push("skipping directory: " + entry__)
                ok = false
                break
            end
        }
    rescue
        @@error.push("could not read directory '#{entry__}': #{$!}")
        return
    end
    return if (!ok)

    if (entry.match(%r|(.+?)\s+-\s+(.+)|))
        artist, album = $1, $2
    else
        artist, album = nil, entry
    end
    
    slash_re = %r/%2f/
    album.gsub!(slash_re, '/')
    track = 0
    Dir.entries(entry__).sort.each {
        |filexx|
        next if (!filexx.match(%r|\A\.+|).nil?)
        
        thisentry = File.join(entry__, filexx)
        staten2 = File.lstat(thisentry)
        if (staten2.directory?)
            if (@@recurse)
                recurse(thisentry, staten2)
            end
        else
            number, artisten, song = nil, nil, nil

            filexxx = demangle(filexx)

            if (filexxx.match(%r/(\A(\d|-)+)?\.?\s*(.*)\.flac/))
                number, bulk = $1, $3
                if (bulk.match(/(.+?)\s+-\s+(.+)/))
                    if (@@song_before_artist) then song, artisten =  $1, $2 else artisten, song = $1 , $2 end
                else
                    artisten, song = nil, bulk
                end
            elsif (filexxx.match(%r/(.*?)\.flac/))
                song = $1
            end

            if (song != nil)
                track += 1
                artiste = (artisten || artist)
                song.gsub!(slash_re, '/')
                data = {}
                if (!@@strip)
                    data["Title"] = song
                    data["Tracknumber"] = track.to_s unless number.nil?
                    data["Artist"] = artiste.gsub(slash_re, '/') if (artiste != nil)
                    data["Album"]= album if (album != nil)
                end
                do_it(File.join(entry__,filexx), data)
            end
        end
    }
end

ARGV.each {
    |arg|
    staten = File.lstat(arg)
    recurse(arg, staten)
}

@@has_comment.each {
    |entry|
    STDERR.puts entry
}

@@skipped.each {
    |entry|
    STDERR.puts entry
}

@@skipped_files.each {
    |entry|
    STDERR.puts entry
}

rv = 0
@@error.each {
    |entry|
    STDERR.puts entry
    rv = rv + 1
}

exit( rv )

