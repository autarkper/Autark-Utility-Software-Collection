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
@@dividends = 0
@@prelskatt = 0
@@other = 0

@@Paper = Struct.new("Paper", :amount, :value, :dividends, :pnl, :highest)
@@papers = {}

@@Sale = Struct.new("Sale", :paper, :date, :amount, :price, :acqp, :pnl)
@@Sales = []

@@rows.reverse.each {
    |cols|
    next if (cols[0] == "Datum")
    #p cols

    value_raw = cols[6].sub(",", ".").to_f
    value = value_raw.abs
    type = cols[2]
    papern = cols[3]
    amount = cols[4].sub(",", ".").to_f.abs
    price = cols[5].sub(",", ".").to_f

    @@account = cols[1]
    if (type =~ /Ins.ttning/)
        @@deposits += value.to_f
    end
    if (type =~ /Uttag/)
        @@withdrawn -= value.to_f
    end
    buy = false
    sell = false
    if (type =~ /K.p/)
        buy = true
    end
    if (type =~ /S.lj/)
        sell = true
    end

    if (type == "Prelskatt utdelningar")
        @@prelskatt += value
        next
    end
    if (buy || sell || amount != 0)
        value = value != 0 ? value : (amount * price).abs
        paper = @@papers[papern] || @@papers[papern] = @@Paper.new(0, 0, 0, 0, 0)
    end
    
    if (type == "Utdelning")
        paper.dividends = paper.dividends + value
        @@dividends += value
    end

    if (type =~ /.vrigt/)
        @@other += value_raw
    end

    if (buy)
        @@bought += value
        paper.amount = paper.amount + amount
        paper.value += value
        paper.highest = [paper.highest, price].max
    end
    if (sell)
        @@sold += value
        acqp = paper.amount == 0 ? 0 : paper.value/paper.amount
        acqv = acqp * amount
        paper.amount -= amount
        paper.value -= acqv
        pnl = value - acqv
        paper.pnl += pnl
        @@Sales << @@Sale.new(papern, cols[0], amount, price, acqp, pnl)
    end
}
puts "Konto: #{@@account}"
puts "Insättningar: #{@@deposits}, Uttag: #{@@withdrawn}, netto: #{netdep = @@deposits - @@withdrawn}"
puts "Köpt: #{rounda(@@bought, 100)}, Sålt: #{rounda(@@sold, 100)}"
puts "Utdelningar: #{@@dividends}, Prelskatt: #{@@prelskatt}"
puts "Övrigt: #{@@other}"

netbought = @@bought - @@sold
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
        puts "Papper: \"#{name}\", Antal: #{round(paper.amount)}, Värde: #{round(paper.value)}, Ansk.pris: #{round(paper.value/paper.amount)}, Högsta: #{rounda(paper.highest, 100)}" + pnl
        @@value = @@value + paper.value
    end
}
if (round(v2 = netbought + @@pnl) != round(@@value))
    raise [v2, @@value].inspect
end

@@Sales.each {
    |sale|
    puts "[Försäljning] Datum: #{sale.date}, Papper: \"#{sale.paper}\", Antal: #{round(sale.amount)}, Pris: #{round(sale.price)}, Ansk.pris: #{round(sale.acqp)}, PnL: #{round(sale.pnl)}"
}

@@pnlpercent = @@deposits != 0 ? @@pnl / @@deposits * 100 : 0
puts "Totalt investerat: #{rounda(@@value, 100)}, Totalt realiserat resultat: #{rounda(@@pnl, 100)} (#{rounda(@@pnlpercent, 10)}% av insättningar)"
puts "Kassa: #{rounda(cash = netdep - netbought + @@dividends - @@prelskatt + @@other, 100)}"
puts "Kassa + investerat: #{rounda(@@value + cash, 100)}"
