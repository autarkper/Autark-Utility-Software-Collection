#!/usr/bin/ruby -w

require 'getoptlong'

options = [
    ["--max-words", GetoptLong::REQUIRED_ARGUMENT ],
    ["--min-words", GetoptLong::REQUIRED_ARGUMENT ],
    ["--words", GetoptLong::REQUIRED_ARGUMENT ],
    ["--verbose", GetoptLong::NO_ARGUMENT ],
    ]


$wordsmax = 50
$wordsmin = 1
$verbose = false

opts = GetoptLong.new()
opts.set_options(*options)
opts.each {
    | opt, arg |
    if (opt == "--max-words")
        $wordsmax = arg.to_i
    end
    if (opt == "--min-words")
        $wordsmin = arg.to_i
    end
    if (opt == "--words")
        $wordsmin = $wordsmax = arg.to_i
    end
    if (opt == "--verbose")
        $verbose = true
    end
}

if ($wordsmin > $wordsmax)
    $stderr.puts("min-words bigger than max-words")
    exit 1
end

$count = 0
$too_long = 0
$too_short = 0

$stdin.each {
    |line|
    id0, orig, id2, trans = line.chomp.split(/\t/)
    length = orig.count(" ") + 1;
    if ($wordsmax > 0 && length > $wordsmax)
        $stderr.puts("discarding (too long (#{length})): #{orig}") if $verbose
        $too_long += 1
        next
    end
    if (length < $wordsmin)
        $stderr.puts("discarding (too short (#{length})): #{orig}") if $verbose
        $too_short += 1
        next
    end

    if (orig.match(/[()]/))
        $stderr.puts("discarding, due to parentheses: " + orig)
        next
    end

    cloze = orig.gsub(/\A([[:punct:]])/){ # leading punctuation (Spanish)
        ""
    }.gsub(/([[:punct:]])\Z/){ # trailing punctuation
        ""
    }

    if ($count == 0)
        id0.gsub!(/\D/, "") # remove magic byte (encoding?)
    end
    print [orig, trans, cloze, "https://tatoeba.org/sentences/show/#{id0}", ""].join("\t") + "\r\n"
    $count += 1
}

$stderr.puts("created #{$count} records (too long: #{$too_long}, too short: #{$too_short})")
