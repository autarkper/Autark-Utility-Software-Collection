#!/usr/bin/ruby -w

require 'getoptlong'
require_relative "SystemCommand"

options = [
    ["--verbose", GetoptLong::NO_ARGUMENT ],
    ["--lang", GetoptLong::REQUIRED_ARGUMENT ],
    ]


$verbose = false

$langs = []
opts = GetoptLong.new()
opts.set_options(*options)
opts.each {
    | opt, arg |
    if (opt == "--lang")
        $langs.push(arg)
    end
}



Base = "https://downloads.tatoeba.org/exports/"

def downloadAndUnpack(file)
    if (File.exist?(file + ".csv"))
        $stderr.puts("skip file: " + file)
        return
    end
    sc = SystemCommand.new
    sc.setVerbose(true)
        sc.execReadPipe("curl", [Base + file + ".tar.bz2"]) {
        |ofh|
        sc.execReadPipe("tar", ["-xj"], ofh) {}
    }
end

downloadAndUnpack("user_languages")
downloadAndUnpack("sentences_base")

$langs.each {
    |lang|
    sc = SystemCommand.new
    sc.setVerbose(true)
    langfile = lang + "_sentences_detailed.tsv"
    if (File.exist?(langfile))
        $stderr.puts("skip file: " + langfile)
        next
    end
    sc.execReadPipe("curl", [Base + "per_language/" + lang + "/" + langfile + ".bz2"]) {
        |ofh|
        sc.execReadPipe("bunzip2", ["-c"], ofh) {
            |ofh2|
            File.open(langfile, "w+") {
                |fff|
                ofh2.each_line() {
                    |line|
                    fff.write(line)
                }
            }
        }
    }
}
