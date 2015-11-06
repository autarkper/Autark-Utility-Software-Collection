#!/usr/bin/ruby -w

$:.unshift(File.split($0)[0])
require "AutarkFileUtils"

def tester(test_sources, target)
    test_sources.each {
        |source|
        result = AutarkFileUtils.make_relative(source[0], target)
        fail "'#{result}', '#{source[1]}'" if (result != source[1])
        result = AutarkFileUtils.make_relative(source[0], target + "/")
        fail "'#{result}', '#{source[1]}'" if (result != source[1])
    }
end

def Test_make_relative
    target = "/home/kalle/test/sub"
    test_sources = [
        ["/home/kalle/dsc02448-300-100.jpg", "../../dsc02448-300-100.jpg"],
        ]
    tester(test_sources, target)

    target = "/home/kalle/test/sub/sub/sub/sub/"
    test_sources = [
        ["/home/kalle/dsc02448-300-100.jpg", "../../../../../dsc02448-300-100.jpg"],
        ]
    tester(test_sources, target)

    target = "/home/kalle/test"
    test_sources = [
        ["/home/pelle/kalkyl.txt", "../../pelle/kalkyl.txt"],
        ["//home//pelle//kalkyl.txt", "../../pelle/kalkyl.txt"],
        ["/home/pelle/kalkyler/aber/dolly.txt", "../../pelle/kalkyler/aber/dolly.txt"],
        ["/away/pelle/kalkyl.txt", "/away/pelle/kalkyl.txt"],
        ["/kalkyl.txt", "/kalkyl.txt"],
        ["/home/olle/bin", "../../olle/bin"],
        ["/home/olle/bin/", "../../olle/bin"],
        ["/bin/ls", "/bin/ls"],
        ["/bin", "/bin"],
        ["/home/kalle/kalkyl.txt", "../kalkyl.txt"],
        ["/home/kalle/dsc02448-300-100.jpg", "../dsc02448-300-100.jpg"],
        ["../bunt.exe", "../bunt.exe"],
        ["../bunt/stroch.exe", "../bunt/stroch.exe"],
        ["../../bunt/stroch.exe", "../../bunt/stroch.exe"],
        ]
    tester(test_sources, target)
end

Test_make_relative()
