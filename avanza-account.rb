#!/usr/bin/ruby -w

$:.push(File.split($0)[0])

require 'getoptlong'

options = [
    ]

opts = GetoptLong.new()
opts.set_options(*options)

@@file = nil
if (ARGV.length > 0)
    @@file = ARGV[0]
end

if (@@file == nil)
    print "no input file\n"
    exit(1)
end

if (!File.exists?(@@file))
    print "file does not exist\n"
    exit(1)
end

def round(num)
    return (num * 1000).round/1000.0
end

@@rows = []
@@fh = File.new(@@file, "r")
@@fh.each_line {
    |line|
    cols = line.split(";")
    @@rows << cols
}

@@account = ""
@@deposits = 0
@@withdrawn = 0
@@bought = 0
@@sold = 0

@@Paper = Struct.new("Paper", :amount, :value, :pnl)

@@papers = {}

@@rows.reverse.each {
    |cols|
    next if (cols[0] == "Datum")
    # p cols

    value = cols[6].sub(",", ".").to_f.abs
    type = cols[2]
    papern = cols[3]
    amount = cols[4].sub(",", ".").to_f.abs
    price = cols[5].sub(",", ".").to_f

    @@account = cols[1]
    if (type =~ /Ins.ttning/)
        @@deposits = @@deposits + value.to_f
    end
    if (type =~ /Uttag/)
        @@withdrawn = @@withdrawn - value.to_f
    end
    buy = false
    sell = false
    if (type =~ /K.p/)
        buy = true
    end
    if (type =~ /S.lj/)
        sell = true
    end

    if (buy || sell)
        value = value != 0 ? value : (amount * price).abs
        paper = @@papers[papern] || @@papers[papern] = @@Paper.new(0, 0, 0)
    end
    
    if (buy)
        @@bought = @@bought + value
        paper.amount = paper.amount + amount
        paper.value = paper.value + value
    end
    if (sell)
        @@sold = @@sold + value
        acqv = paper.value/paper.amount
        paper.amount = paper.amount - amount
        paper.value = paper.value - value
        paper.pnl = paper.pnl + value - (amount * acqv)
    end
}
puts "Konto: #{@@account}"
puts "Insättningar: #{@@deposits}, Uttag: #{@@withdrawn}, netto: #{netdep = @@deposits - @@withdrawn}"
puts "Köpt: #{@@bought}, Sålt: #{@@sold}, netto: #{netbought = @@bought - @@sold}"
puts "Saldo: #{netdep - netbought}"

@@pnl = 0
@@papers.keys.sort.each {
    |name|
    paper = @@papers[name]
    @@pnl = @@pnl + paper.pnl
    if (paper.amount != 0)
        puts "Paper: \"#{name}\", Amount: #{paper.amount}, Value: #{paper.value}, Acq. value: #{round(paper.value/paper.amount)}, PnL: #{paper.pnl}"
    else
        puts "Paper: \"#{name}\", PnL: #{round(paper.pnl)}"
    end
}
puts "Total realized PnL: #{round(@@pnl)}"
