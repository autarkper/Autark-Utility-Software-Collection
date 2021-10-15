#!/usr/bin/ruby -w

require_relative "AutarkFileUtils"
require_relative "SystemCommand"

require 'getoptlong'

options = [
    ["--dry-run", GetoptLong::NO_ARGUMENT ],
    ["--help", GetoptLong::NO_ARGUMENT ],
    ["--convert-to-absolute-link", GetoptLong::NO_ARGUMENT ],
    ["--allow-bad-link", GetoptLong::NO_ARGUMENT ],
    ["--no-follow", GetoptLong::NO_ARGUMENT ],
    ["--no-recursive", GetoptLong::NO_ARGUMENT ],
    ["--verbose", GetoptLong::NO_ARGUMENT ],
    ["--silent", GetoptLong::NO_ARGUMENT ],
    ["--summary", GetoptLong::NO_ARGUMENT ],
    ["--target-directory", GetoptLong::REQUIRED_ARGUMENT ],
]

opts = GetoptLong.new()
opts.set_options(*options)

$dry_run = false
$show_help = false
$allow_bad_link = false
$verbosity = 1
$convert_to_absolute = false
$no_follow = false
$recursive = true
$force_summary = false

opts.each {
    | opt, arg |
    if (opt == "--help")
        $show_help = true
    elsif (opt == "--dry-run")
        $dry_run = true
    elsif (opt == "--allow-bad-link")
        $allow_bad_link = true
    elsif (opt == "--no-follow")
        $no_follow = true
    elsif (opt == "--no-recursive")
        $recursive = false
    elsif (opt == "--verbose")
        $verbosity = 2
    elsif (opt == "--silent")
        $verbosity = 0
    elsif (opt == "--summary")
        $force_summary = true
    elsif (opt == "--convert-to-absolute-link")
        $convert_to_absolute = true
    end}

$my_name = File.basename($0)

$req_args = 1
if ($show_help || ARGV.length() < $req_args)
    usage = <<END_USAGE
\nusage:
    #{$my_name} [options] directory-1 [directory-2 ... directory-n]
Relocates symbolic links (default: convert absolute to relative) and optionally resolves link chains.
END_USAGE

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

$system_command = SystemCommand.new
$system_command.setDryRun($dry_run)
$system_command.setVerbose($verbosity > 0)

$dont_do_it = false

$relocated_count = 0
$skipped_count = 0
$bad_count = 0

class Relocator
    def followLink(linky)
        path = File.split(linky)[0]
        link = File.readlink(linky)
        is_relative = link[0..0] != '/'
        if (is_relative) # relative link
            link = File.join(path, link)
        end
        absolute_link = File.expand_path(link)
        if (not File.exist?(absolute_link))
            STDERR.puts("#{$my_name}: '#{absolute_link}' (alias '#{linky}') does not exist")
            if (not $allow_bad_link)
                $dont_do_it = true
            end
            $bad_count += 1
        else
            if (!$no_follow && File.lstat(absolute_link).symlink?)
                return followLink(absolute_link)
            end
        end

        return absolute_link
    end
    
    def process_dir(path, a_stat)
        begin putc(".") ; STDOUT.flush end if $verbosity > 1
        
        if (@seen.has_key?(a_stat.ino))
            return
        end
        @seen[a_stat.ino] = 1

        Dir.foreach(path) {
            |entry|
            fullentry = File.join(path, entry)

            stat = File.lstat(fullentry)
            if (stat.directory? && $recursive)
                if (entry != '..')
                    process_dir(fullentry, stat)
                end
            end

            if (stat.symlink?)
                origlink = File.readlink(fullentry)
                link = followLink(fullentry)
                @newlinks.fetch(path){|key|@newlinks[key] = [] }.push([entry, link, origlink])
            end
        }
    end

    def work(sourcedir)
        @seen = {}
        @newlinks = {}

        process_dir(sourcedir, File.lstat(sourcedir))
        puts if $verbosity > 1

        commands = []
        $dont_do_it = false
        
        @newlinks.each{ 
            |path, links|
            links.each {
                |sourcelink|
                name, source, origlink = sourcelink
                targetpath = File.expand_path(path)
                adjusted_source = !$convert_to_absolute \
                    ? AutarkFileUtils.make_relative(source, targetpath) \
                    : source
                target = File.join(path, name)
                
                if (adjusted_source == origlink)
                    puts "skipping: '#{target}' -> '#{adjusted_source}' (unchanged)" if $verbosity > 1
                    $skipped_count += 1
                else
                    if (adjusted_source.empty?)
                        adjusted_source = "."
                    end
                    commands.push([adjusted_source, target])
                end
            }
        }

        unless ($dont_do_it)
            commands.each {
                |command|
                source, target = command
    # -s, --symbolic
    #         make symbolic links instead of hard links
    # -f, --force
    #         remove existing destination files
    # -n, --no-dereference
    #         treat destination that is a symlink to a directory as if it were a normal file

                fail "target empty" if (target.empty?)
                $system_command.safeExec("ln", ["-sfn", source, target])
                $relocated_count += 1
            }
        end
    end

end

ARGV.each {
    |source|
    
    if (!FileTest.exist?(source))
        fail "source-directory '#{source}' does not exist"
    end

    outstat = File.stat(source)
    if (not outstat.directory?)
        fail "source-directory '#{source}' not a directory"
    end

    Relocator.new.work(source)
}
if ($verbosity > 0 or $force_summary)
    if ($dry_run)
        puts "#{$my_name}: Dry run. Would relocate: #{$relocated_count}, would skip: #{$skipped_count}."
    else
        puts "#{$my_name}: Relocated: #{$relocated_count}, skipped: #{$skipped_count}."
    end
end

if ($bad_count > 0) then STDERR.puts "Bad links: #{$bad_count}!" end

exit 1 if ($dont_do_it)
