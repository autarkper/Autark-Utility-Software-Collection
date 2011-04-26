#!/usr/bin/ruby -w

$:.push(File.split($0)[0])

require 'getoptlong'

require "SystemCommand"
require "ExifToolUtils"

options = [
    ["--help", "-h", GetoptLong::NO_ARGUMENT ],
    ["--source-dir", GetoptLong::REQUIRED_ARGUMENT ],
    ["--dry-run", GetoptLong::NO_ARGUMENT ],
    ["--no-exif", GetoptLong::NO_ARGUMENT ],
    ["--verbose", GetoptLong::NO_ARGUMENT ],
    ["--no-geotag", GetoptLong::NO_ARGUMENT ],
    ]

opts = GetoptLong.new()
opts.set_options(*options)

@@show_help = false
@@source_dir = []
@@dry_run = false
@@do_exif = true
@@verbose = false
@@no_geotag = false

opts.each {
    | opt, arg |
    if (opt == "--help")
        @@show_help = true
    elsif (opt == "--source-dir")
        @@source_dir.push(arg)
    elsif (opt == "--dry-run")
        @@dry_run = true
    elsif (opt == "--no-exif")
        @@do_exif = false
    elsif (opt == "--verbose")
        @@verbose = true
     elsif (opt == "--no-geotag")
        @@no_geotag = true
   end
}

@@source_dir.push(".") if @@source_dir.empty?

@@sysco = SystemCommand.new
@@sysco.setDryRun(@@dry_run)
@@sysco.setVerbose(true)

@@silent_sc =  @@sysco.dup
@@silent_sc.setVerbose(@@verbose)


if (ARGV.length < 1 || @@show_help)
    usage = "\nusage: #{File.basename($0)} [options] file-pattern"

    options_string = "Options:\n"
    options_array =[]
    options.each {
        |option|
        options_array.push(option[0])
    }
    options_string += options_array.join("\n")

    puts usage
    puts options_string
    exit
end

@@source_dir.each {
    |dir|
	if (!FileTest.exists?(dir))
	    fail "source-directory '#{dir}' does not exist"
	end

	outstat = File.stat(dir)
	if (not outstat.directory?)
	    fail "source-directory '#{dir}' not a directory"
	end
}

def puts_command(cmd, args)
    @@sysco.safeExec(cmd, args)
end

def do_touch(reference, target)
    @@silent_sc.safeExec("touch", ['--no-create', "--reference=#{reference}", target])
end

@@ambiguous = []

@@find_sc =  @@silent_sc.dup
@@find_sc.failSoft(true)
@@find_sc.setDryRun(false)

def find_file(dir, base, extlist, targetfile = nil)
    found = []

    candidates = []
    extlist.each_index {
        |index|
        candidates << "-o" unless (index == 0)
        candidates << '-name'
        candidates << base + '.' + extlist[index]
    }

    samefiletest = targetfile != nil ? ['-a', '!', '-samefile', targetfile] : []
    @@find_sc.execReadPipe('find', [dir, '(', candidates, ')', samefiletest, '-print0'].flatten) {
        |fh|
        fh.each_line("\0") {
            |f|
            f.chomp!("\0")
            found << f
        }
    }

    if (found.size > 1)
        @@ambiguous << [base, found]
       return nil
    end
    return found[0]
end

@@tmpdir = nil

def temp_dir()
    if (@@tmpdir == nil)
        tmpdir = File.split($0)[1] + '-' + $$.to_s + '-' + Time.now.to_i.to_s
        if (@@find_sc.safeExec('mkdir', ['-p', @@tmpdir = File.join('/dev/shm', tmpdir)]) > 0)
            @@silent_sc.safeExec('mkdir', ['-p', @@tmpdir = File.join('/tmp', tmpdir)])
        end
    end
    return @@tmpdir
end

def exif_file(fulltarget)
    target = File.split(fulltarget)[1]


    if (%r{\A(\w+?\d+[^-._]+)}.match(target))
        base = $1 # DSC007490-100-300.jpg -> DSC007490
    elsif (%r{\A(img_\d+[^-._]+)}i.match(target))
        base = $1 # img_002-100-300.jpg -> img_002
    elsif (%r{\A([^-._]+)}i.match(target))
        base = $1 # 'a nice pic.jpg' -> 'a nice pic'
    else
        return nil
    end
    file_info = nil

    if (file_info.nil?)
        f = find_file(@@source_dir, base, %w(arw ARW), fulltarget)
        if (f != nil)
            file_info = [f, false]
        end
    end

    if (file_info.nil?)
        f = find_file(@@source_dir, base, %w(crw CRW))
        if (f != nil)
            # This will use dcraw to extract the hidden thumbnail, which will
            # hopefully contain the needed exif info.
            # In order to avoid polluting the source directory with thumb files,
            # we create a symbolic link in a temporary directory.
            # This relies on dcraw's current behavior, namely:
            # with '/dir/raw.ext' as input, produce '/dir/raw.thumb.jpg'
            
            tmpdir = temp_dir()
            raw_alias = File.join(tmpdir, 'raw.ext')
            @@silent_sc.safeExec('ln', ['-sfn', f, raw_alias] )
            puts_command("dcraw", ['-e', raw_alias]) # will produce a .thumb.jpg file in tempdir

            fthumb = File.join(tmpdir, 'raw.thumb.jpg')
            if (FileTest.exists?(fthumb))
                do_touch(f, fthumb)
                file_info = [fthumb, true]
            end
        end
    end

    if (file_info.nil?)
        f = find_file(@@source_dir, base, %w(thm THM jpg JPG), fulltarget)
        if (f != nil)
            file_info = [f, false]
        end
    end


    return file_info
end

@@failures = []

@@processed_count = 0
@@attempted_count = 0

@@drift_lookup = {}
@@gpx_lookup = {}

def process(target)
    bMod = true
    bExists = FileTest.exists?(target) && File.stat(target).size > 0

    @@attempted_count += 1

    exif = exif_file(target)
    if (exif.nil?)
        @@failures.push(target)
        return
    end
    

    if (@@do_exif)
        source_dir = File::split(exif[0])[0]

        bMod = false
        ExifToolUtils.copyExif(@@sysco, exif[0], target)
        bMod = true

        drift_args = @@drift_lookup[source_dir]
        if (drift_args == nil)
            drift_file = File::join(source_dir, 'drift.txt')
            drift_args = []
            if (File.exists?(drift_file))
                File.open(drift_file) {
                    |fh|
                    fh.lines.each {
                        |line|
                        line.chomp!
                        if (line.match(/\s*([+-])\s*(\d\d:\d\d:\d\d)\s*/))
                            drift_sign = $1; drift_val = $2;
                            drift_correction = (drift_sign == '-' ? '+=' : '-=') + drift_val
                            drift_args = ['-createdate' + drift_correction, '-DateTimeOriginal' + drift_correction]
                            break #done
                        elsif (line.match(/\s*#.*/))
                            #a comment line
                        else
                            puts "bad line in " + drift_file
                            break
                        end                                        
                        }
                    }
            end
            @@drift_lookup[source_dir] = drift_args
        end
        if (!drift_args.empty?)
            @@sysco.safeExec("exiftool", [drift_args, '-overwrite_original', target].flatten, true)
        end

        unless (@@no_geotag)
            geotag_args = @@gpx_lookup[source_dir]
            if (geotag_args == nil)
                geotag_args = []
                geotag_file = File::join(source_dir, '*.gpx')
                if (!Dir.glob(geotag_file).empty?)
                    geotag_args = ['-geotag', geotag_file]
                end
            end
            if (!geotag_args.empty?)
                @@sysco.safeExec("exiftool", [geotag_args, '-overwrite_original', target].flatten, true)
            end
            @@gpx_lookup[source_dir] = geotag_args
        end
        
        @@processed_count += 1
    end

    if (bMod)
        do_touch(exif[0], target)
    end

    if (exif[1])
        # now that we have a temp dir, not needed: File.unlink(exif[0])
    end 
end

def cleanup()
    if (@@tmpdir != nil)
        puts_command('rm', ['-rf', @@tmpdir])
        @@tmpdir = nil
    end
end

trap("INT") { cleanup() }

ARGV.each {
    |f|
    bExists = FileTest.exists?(f) && File.stat(f).size > 0
    if (bExists)
        process( f )
    else
        fail "'#{f}': file not found"
    end

}

END {
    @@failures.each {
        |failure|
        $stderr.puts "Warning: Source file not found for '#{failure}'"
    }

    @@ambiguous.each {
        |ambigs|
        target, files = *ambigs
        $stderr.puts "Warning: More than one source file found for '#{target}': #{files.inspect}"
    }

    cleanup()

    puts "\nProcessed #{@@processed_count}/#{@@attempted_count} files"
}

