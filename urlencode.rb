#!/usr/bin/ruby -w

ARGV.each {
    |arg|
    str = ''
    arg.each_byte{ |b| str << ('%%%x' % b) }
    puts str
    }
