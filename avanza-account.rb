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
    return rounda(num, 1000)
end

def rounda(num, precision)
    return (num * precision.to_f).round/precision.to_f
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
        acqp = paper.value/paper.amount
        acqv = acqp * amount
        paper.amount = paper.amount - amount
        paper.value = paper.value - acqv
        paper.pnl = paper.pnl + value - acqv
    end
}
puts "Konto: #{@@account}"
puts "Insättningar: #{@@deposits}, Uttag: #{@@withdrawn}, netto: #{netdep = @@deposits - @@withdrawn}"
puts "Köpt: #{rounda(@@bought, 100)}, Sålt: #{rounda(@@sold, 100)}, netto: #{rounda(netbought = @@bought - @@sold, 100)}"
puts "Saldo: #{rounda(netdep - netbought, 100)}"

@@pnl = 0
@@value = 0
@@papers.sort{|a, b|
    boq = (b[1].amount == 0 ? 0 : 1)
    aaq = (a[1].amount == 0 ? 0 : 1)
    if (aaq != boq)
        (aaq <=> boq) * -1
    else
        a[0] <=> b[0]
    end
    }.each {
    |name, paper|
    @@pnl = @@pnl + paper.pnl
    pnl = paper.pnl == 0 ? "" : ", PnL: #{round(paper.pnl)}"
    if (paper.amount != 0)
        puts "Paper: \"#{name}\", Amount: #{round(paper.amount)}, Value: #{round(paper.value)}, Acq. price: #{round(paper.value/paper.amount)}" + pnl
        @@value = @@value + paper.value
    elsif (paper.pnl != 0)
        puts "Paper: \"#{name}\"" + pnl
    end
}
if (round(v2 = netbought + @@pnl) != round(@@value))
    raise [v2, @@value].inspect
end

puts "Total book value: #{rounda(@@value, 100)}, Total realized PnL: #{rounda(@@pnl, 100)}"
