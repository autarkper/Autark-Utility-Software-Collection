#!/usr/bin/ruby -w

require 'getoptlong'
require_relative "SystemCommand"

options = [
    ["--verbose", GetoptLong::NO_ARGUMENT ],
    ]


$verbose = false

opts = GetoptLong.new()
opts.set_options(*options)
opts.each {
    | opt, arg |
}


$sc = SystemCommand.new
$sc.setVerbose(true)

$sc.execReadPipe("curl", ["https://downloads.tatoeba.org/exports/user_languages.tar.bz2"]) {
    |ofh|
    $sc.execReadPipe("tar", ["-xj"], ofh) {}
}