#!/usr/bin/ruby -w

$:.push(File.split($0)[0])

require "SystemCommand"
require "AutarkFileUtils"
require "ExifToolUtils"

require 'getoptlong'
require 'thread'

options = [
    ["--help", "-h", GetoptLong::NO_ARGUMENT ],
    ["--target-dir", GetoptLong::REQUIRED_ARGUMENT ],
    ["--dry-run", GetoptLong::NO_ARGUMENT ],
    ["--ppi", GetoptLong::REQUIRED_ARGUMENT ],
    ["--threads", GetoptLong::REQUIRED_ARGUMENT ],
    ["--pixels", GetoptLong::NO_ARGUMENT ],
    ["--mm", GetoptLong::NO_ARGUMENT ],
    ["--height", GetoptLong::REQUIRED_ARGUMENT ],
    ["--width", GetoptLong::REQUIRED_ARGUMENT ],
    ["--quality", GetoptLong::REQUIRED_ARGUMENT ],
    ["--overwrite", GetoptLong::NO_ARGUMENT ],
    ["--find-dir", GetoptLong::REQUIRED_ARGUMENT ],
    ["--find-pattern", GetoptLong::REQUIRED_ARGUMENT ],
    ["--find-maxdepth", GetoptLong::REQUIRED_ARGUMENT ],
    ["--unsharp-amount", GetoptLong::REQUIRED_ARGUMENT ],
    ["--unsharp-threshold", GetoptLong::REQUIRED_ARGUMENT ],
    ["--unsharp-radius", GetoptLong::REQUIRED_ARGUMENT ],
    ["--unsharp-sigma", GetoptLong::REQUIRED_ARGUMENT ],
    ["--no-unsharp-mask", GetoptLong::NO_ARGUMENT ],
    ["--input-profile", GetoptLong::REQUIRED_ARGUMENT ],
    ["--profile", GetoptLong::REQUIRED_ARGUMENT ],
    ["--suffix", GetoptLong::REQUIRED_ARGUMENT ],
    ["--target-type", GetoptLong::REQUIRED_ARGUMENT ],
    ["--verbose", GetoptLong::NO_ARGUMENT ],
    ["--no-exif-copy", GetoptLong::NO_ARGUMENT ],
    ["--straight-conversion", GetoptLong::NO_ARGUMENT ],
    ["--update-existing-only", GetoptLong::NO_ARGUMENT ],
    ["--flatten-output-directories", GetoptLong::NO_ARGUMENT ],
    ["--frame-dim", GetoptLong::REQUIRED_ARGUMENT ],
    ["--frame-color", GetoptLong::REQUIRED_ARGUMENT ],
    ["--no-suffix", GetoptLong::NO_ARGUMENT ],
    ["--newer-than-epoch", GetoptLong::REQUIRED_ARGUMENT ],
    ["--image-type", GetoptLong::REQUIRED_ARGUMENT ],
    ["--extra-parameters", GetoptLong::REQUIRED_ARGUMENT ],
    ["--only-if-resize", GetoptLong::NO_ARGUMENT ],
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
@@do_exif = true
@@keep_generated = false
@@ppi = 300
@@height = nil
@@width = nil
@@overwrite = false
@@max_threads = getCpuCount()
@@user_pixels = false
@@quality = 96;
@@find_dir = "."
@@find_pattern = ""
@@find_maxdepth = nil
@@USM_amount = "1.0"
@@USM_threshold = "0.01"
@@USM_radius = nil
@@USM_sigma = nil
@@input_profile = nil
@@profile = nil
@@suffix = nil
@@no_suffix = false
@@target_type = 'jpg'
@@verbose = false
@@exif_copy = true
@@straight = false
@@update = false
@@flatten = false
@@frame_dim = 0
@@frame_color = "#ffffff"
@@no_sharpening = false
@@newer_than = 0
@@image_type = 'TrueColor'
@@extra_parameters = []
@@only_if_resize = false

opts.each {
    | opt, arg |
    if (opt == "--help")
        @@show_help = true
    elsif (opt == "--target-dir")
        @@out_dir = arg
    elsif (opt == "--dry-run")
        @@dry_run = true
    elsif (opt == "--pixels")
        @@user_pixels = true
    elsif (opt == "--mm")
        @@user_pixels = false
    elsif (opt == "--ppi")
        @@ppi = arg.to_i
    elsif (opt == "--height")
        @@height = arg.to_i
    elsif (opt == "--width")
        @@width = arg.to_i
    elsif (opt == "--overwrite")
        @@overwrite = true
    elsif (opt == "--threads")
        @@max_threads = arg.to_i
    elsif (opt == "--quality")
        @@quality = arg.to_i
    elsif (opt == "--find-dir")
        @@find_dir = arg
    elsif (opt == "--find-pattern")
        @@find_pattern = arg
    elsif (opt == "--find-maxdepth")
        @@find_maxdepth = arg
    elsif (opt == "--unsharp-amount")
        @@USM_amount = "%1.1f" % (arg.to_i / 100.0)
    elsif (opt == "--unsharp-threshold")
        @@USM_threshold = "%1.2f" % (arg.to_i / 100.0)
    elsif (opt == "--input-profile")
        @@input_profile = arg
    elsif (opt == "--profile")
        @@profile = arg
    elsif (opt == "--suffix")
        @@suffix = arg
    elsif (opt == "--target-type")
        @@target_type = arg
    elsif (opt == "--verbose")
        @@verbose = true
    elsif (opt == "--no-exif-copy")
        @@exif_copy = false
    elsif (opt == "--straight-conversion")
        @@straight = true
    elsif (opt == "--update-existing-only")
        @@update = true
    elsif (opt == "--flatten-output-directories")
        @@flatten = true
    elsif (opt == "--no-suffix")
        @@no_suffix = true
    elsif (opt == "--frame-dim")
        @@frame_dim = arg.to_i
    elsif (opt == "--frame-color")
        @@frame_color = arg
    elsif (opt == "--no-unsharp-mask")
        @@no_sharpening = true
    elsif (opt == "--unsharp-radius")
        @@USM_radius = arg.to_f
    elsif (opt == "--unsharp-sigma")
        @@USM_sigma = arg.to_f
    elsif (opt == "--newer-than-epoch")
        @@newer_than = arg.to_i
    elsif (opt == "--image-type")
        @@image_type = arg
    elsif (opt == "--extra-parameters")
        @@extra_parameters << arg.split(/\s+/)
    elsif (opt == "--only-if-resize")
        @@only_if_resize = true
    end
}


if (@@out_dir.nil? && ARGV.length > 0)
    @@out_dir = ARGV.pop
end

if (@@height == nil && @@width == nil)
    @@height = 100
    @@user_pixels = false
end

@@usage = <<END_USAGE
usage 1:
    #{File.basename($0)} [options] file-list target-directory
    Example: #{File.basename($0)} /tmp/*.png /media/usb1
usage 2:
    #{File.basename($0)} [options] --target-dir directory file-pattern
    Example: #{File.basename($0)} --target-dir /media/usb1 /tmp/*.png
usage 3:
    #{File.basename($0)} [options] --target-dir directory --find-dir --find-pattern
    Example: #{File.basename($0)} --target-dir /media/usb1 --find-dir /tmp/ --find-pattern '*.png'
END_USAGE

if ((ARGV.length < 1 && @@find_pattern.length == 0) || @@show_help)

    options_string = "Options:\n"
    options_array =[]
    options.each {
        |option|
        options_array.push(option[0])
    }
    options_string += options_array.join("\n")

    puts @@usage
    puts options_string
    exit 1
end

if (ARGV.length > 0 && @@find_pattern.length > 0)
    puts "Error: Cannot mix --find-pattern and file list"
    puts @@usage
    exit 1
end

if (@@ppi < 1 && !@@user_pixels)
    puts "Error: Cannot mix 0 ppi and mm dimensions"
    exit 1
end


@@scVerbose = SystemCommand.new
@@scVerbose.setVerbose(true)
@@scVerbose.setDryRun(@@dry_run)

@@sc = SystemCommand.new
@@sc.setVerbose(@@verbose)
@@sc.setDryRun(@@dry_run)

def puts_command(cmd, args)
    return @@sc.safeExec(cmd, args)
end

@@created_dir_mutex = Mutex.new
@@created_dirs = {}

def join_dirs(sourcen, reldir)
    source = @@flatten ? sourcen: AutarkFileUtils::make_relative(sourcen, reldir)

    fi = File.split(source)
    source_dir = fi[0]

    @@created_dir_mutex.synchronize {
        cached_dir = @@created_dirs[source_dir]
        if (cached_dir != nil) then return cached_dir end

        target_dir = \
        if (@@flatten)
            @@out_dir # produce a flat target directory structure
        else
            File.join(@@out_dir, source_dir)
        end

        if (!FileTest.exists?(target_dir))
            puts_command("mkdir", ['-p', target_dir])
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
    puts_command("touch", ['--no-create', "--reference=#{reference}", target])
end

def calcPixels(arg)
    if (arg.nil?) then return arg end
    if (@@user_pixels) then return arg end
    return ((arg * @@ppi) / 25.4).to_i
end

@@height_pixels = calcPixels(@@height)
@@width_pixels = calcPixels(@@width)

@@frame_px = calcPixels(@@frame_dim)
@@width_pixels -= (@@frame_px * 2) if (@@width_pixels != nil)
@@height_pixels -= (@@frame_px * 2) if (@@height_pixels != nil)

if (@@ppi != 0)
    @@USMrf = @@USM_radius || (@@ppi / 160.0)

    @@USMs = @@USM_sigma || ("%1.1f" % ((@@USMrf > 1.0) ? Math.sqrt(@@USMrf) : @@USMrf))
    @@USMr = "%1.1f" % @@USMrf
end

def identify(source)
    extension = source.scan(/\.([^.]+)\Z/)[0][0]
    if (extension.upcase == 'PNG')
        id = @@sc.execBackTick('file', ['--dereference', source])
        return id.scan(/\s+(\d+)\s+x\s+(\d+)/)[0]
    else
        id = @@sc.execBackTick('identify', [source])
        return id.scan(/\s+(\d+)x(\d+)/)[0]
    end
end

=begin
Mike Southern, http://studio.imagemagick.org/pipermail/magick-users/2005-June/015594.html

If your cmyk image has an ICM profile, then you can use:
 convert cmyk.tiff -profile AdobeRGB1998.icm rgb.tiff

If your cmyk image doesn't have an ICM profile, then you can use:
 convert cmyk.tiff -profile CMYK.icm -profile AdobeRGB1998.icm rgb.tiff

There is also a command that always works. Here is what the command line
that I use to convert from CMYK to RGB:
 convert cmyk.tiff +profile icm -profile CMYK.icm -profile AdobeRGB1998.icm
rgb.tiff

This command always works, whether the CMYK image has an ICM profile or not.
What happens is: you remove the ICM profile, then you apply the CMYK input
profile (CMYK.icm) and then you apply the RGB output profile
(AdobeRGB1998.icm). For me, this always results in perfect color.


These are the rules that should be followed:
- The profile-switches need to be between the input and output file
- The "+profile" needs "icm" as argument to remove the icc-profile
- The argument of the first "-profile" is the input profile
- The argument of the second "-profile" is the output profile

If there is no embedded profile then the argument of "-profile" is the input
profile. If I use "-profile" a second time, then it defines the output
profile.
If there is an embedded profile then the argument of "-profile" is the
output profile.
=end

def process__(source, reldir = nil)
    base = File.basename(source).sub(/(.+)\.[^.]*/, '\1')
    target_dir = join_dirs(source, reldir)
    suffix = @@no_suffix ? nil: (@@suffix.nil? && !@@straight ? [@@ppi.to_s, @@height.to_s] : @@suffix)
    target = File.join(target_dir, [base, suffix].compact.flatten.join('-') + "." + @@target_type)

    if (@@newer_than != 0 && File.stat(source).mtime < Time.at(@@newer_than))
        # p [File.stat(source).mtime, Time.at(@@newer_than)]
        if (@@verbose)
            puts "#{source}: unchanged since last run (incremental)" 
        end
        return false
    end

    bExists = FileTest.exists?(target)
    
    if (@@update and !bExists)
        if (@@verbose)
            puts "#{source}: target does not exist (update)" 
        end
        return false
    end
    
    bTargetOlder = bExists && File.stat(target).mtime < File.stat(source).mtime

    if (bExists && (!bTargetOlder and !@@overwrite))
        if (@@verbose)
            puts "#{source}: target newer than source (not overwrite)" 
        end
        return false
    end

    input_profile_arg = !@@input_profile.nil? ? ['+profile', '*.ic?', '-profile', @@input_profile] : []
    profile_arg = !@@profile.nil? ? [input_profile_arg, '-profile', @@profile] : []
    image_type_arg = ['-type', @@image_type]
    frame_arg = resize_arg = density_arg = quality_arg = unsharp_arg = nil
    if (!@@straight)
        dims = identify(source)
        if (@@only_if_resize)
            dims2 = dims.collect {|i|i.to_i}
            puts "#{source}: #{dims2[0]}x#{dims2[1]} px"
            dims_max = dims2.max
            target_max = [@@height_pixels.to_i, @@width_pixels.to_i].max
            if (dims_max <= target_max)
                puts "#{source}: no resize (#{dims_max} vs #{target_max} px)"
                return false
            end
        end
        resize_args = if (dims[0].to_i < dims[1].to_i) then "#{@@height_pixels}x#{@@width_pixels or ''}>" else "#{@@width_pixels or ''}x#{@@height_pixels}>" end
        resize_arg = ['-filter', 'Lanczos', '-resize', resize_args]
        if (@@ppi != 0)
            density_arg = ['-density', "#{@@ppi}x#{@@ppi}"]
            if (!@@no_sharpening)
                unsharp_arg = ['-unsharp', "#{@@USMr}x#{@@USMs}+#{@@USM_amount}+#{@@USM_threshold}"]
            end
        end
        quality_arg = ['-quality', @@quality.to_s] unless (@@quality == 0)
        frame_arg = (@@frame_dim != 0) ? ['-mattecolor', @@frame_color, '-frame', "#{@@frame_px}x#{@@frame_px}"] : nil
    end

    @@scVerbose.safeExec("convert", [source, resize_arg, density_arg, image_type_arg, quality_arg, profile_arg, unsharp_arg, frame_arg, @@extra_parameters, target].flatten.compact)

    if (@@exif_copy)
        ExifToolUtils.copyExif(@@sc, source, target)
    end
    do_touch(source, target)
    return true
end

@@thread_count = 0
@@thread_mutex = Mutex.new
@@thread_condition = ConditionVariable.new
@@jobs_done = 0
@@jobs_skipped = 0
@@jobs_failed = []
@@jobs_started = 0
@@jobs_total = 0
@@all_jobs_started = false
@@job_queue = []

if (@@max_threads < 1)
    @@max_threads = 1
end

def no_more_jobs()
    return @@all_jobs_started && @@jobs_total == @@jobs_done
end

def process(*args)
    @@thread_mutex.synchronize {
        @@job_queue.push(args)
        @@thread_condition.signal

        if (@@thread_count < @@max_threads)
            @@thread_count += 1
            Thread.new {
                begin
                    while (true)
                        job_number = 0
                        arguments = nil
                        @@thread_mutex.synchronize {
                            while (@@job_queue.size == 0 && !no_more_jobs())
                                @@thread_condition.wait(@@thread_mutex)
                            end
                            if (!no_more_jobs())
                                arguments = @@job_queue.shift
                                job_number = @@jobs_started += 1
                                puts "Starting job #{job_number}/#{@@jobs_total}: #{arguments[0]}" # if (@@verbose)
                            end
                        } # synch
                        break if (job_number == 0)

                        skipped = false
                        failed = false
                        begin
                            skipped = !process__(*arguments)
                        rescue Exception => obj
                            p obj
                            failed = true
                        ensure
                            @@thread_mutex.synchronize {
                                if (@@verbose)
                                  puts "Finished job #{job_number}#{skipped ? ' (skipped)':''}"
                                end
                                @@jobs_done += 1
                                @@jobs_skipped += 1 if (skipped)
                                @@jobs_failed << arguments[0] if (failed)
                            }
                        end
                    end # while
                ensure
                    @@thread_mutex.synchronize {@@thread_count -= 1;@@thread_condition.broadcast}
                end
            }.run
        end # end
        }
end

@@found_count = 0

def process_filename(f, reldir = nil)
    bExists = FileTest.exists?(f)
    if (bExists)
        staten = File.stat(f)
        next if (staten.directory?)
        if (staten.size > 0)
            @@found_count += 1
            process( f, reldir )
        else
            $stderr.puts "'#{f}': zero-length file"
        end
    else
        fail "'#{f}': file not found"
    end
end

if (@@find_pattern.length > 0)
    sc = SystemCommand.new
    sc.setVerbose
    sc.failSoft(true)
    list = []
    depth_args = @@find_maxdepth.nil? ? [] : ['-maxdepth', @@find_maxdepth]
    sc.execReadPipe('find', [@@find_dir, depth_args, '-name', @@find_pattern, '-print0'].flatten) {
        |fh|
        fh.each_line("\0") {
            |f|
            f.chomp!("\0")
            list << f
        }
    }
    @@jobs_total = list.size
    list.each {
        |f|
        process_filename(f, @@find_dir)
    }
else
    @@jobs_total = ARGV.size
    ARGV.each {
        |f|
        process_filename(f, @@out_dir)
    }
end

raise "strange" if (@@found_count != @@jobs_total)

@@thread_mutex.synchronize {
    @@all_jobs_started = true
    while (@@jobs_total > @@jobs_done)
        @@thread_condition.wait(@@thread_mutex)
    end

    Thread.list {|thread| thread.join}
}

really_processed = @@jobs_done - @@jobs_skipped
puts "\n#{File.basename($0)}: #{if (@@dry_run) then ' (DRY RUN) ' end}Processed #{really_processed} image#{if (really_processed != 1) then 's' end}#{if (@@jobs_skipped>0) then ' (skipped ' + @@jobs_skipped.to_s + ')' end}."
if (@@jobs_failed.length>0)
    puts 'FAILED ' + @@jobs_failed.length.to_s + ':'
    @@jobs_failed.each {
        |arg| puts arg
    }
end
exit(really_processed > 0 ? @@jobs_failed.length : -1)
