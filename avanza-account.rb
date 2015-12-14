#!/usr/bin/ruby -wE:utf-8

require 'getoptlong'
require 'bigdecimal'

SALE = "Sälj"
BUY = "Köp"
DIVIDEND = "Utd"
DEPOSIT = "Ins"
WITHDRAWAL = "Utt"
OTHER = "Övr"

options = [
    ]

opts = GetoptLong.new()
opts.set_options(*options)

$___ = "\t"
$file = nil
if (ARGV.length > 0)
    $file = ARGV[0]
end

if ($file == nil)
    print "no input file\n"
    exit(1)
end

if (!File.exists?($file))
    print "file does not exist\n"
    exit(1)
end

def round(num)
    return rounda(num, 1000)
end

def rounda(num, precision)
    return (num * precision).round/precision.to_f
end

$rows = []
$fh = File.new($file, "r")
$fh.set_encoding('iso-8859-1')
$fh.each_line {
    |line|
    cols = line.split(";")
    $rows << cols
}

$account = ""
$deposits = BigDecimal.new(0)
$withdrawn = BigDecimal.new(0)
$bought = BigDecimal.new(0)
$sold = BigDecimal.new(0)
$dividends = BigDecimal.new(0)
$prelskatt = BigDecimal.new(0)
$other = BigDecimal.new(0)
$pnl0 = BigDecimal.new(0)
$kassa = BigDecimal.new(0)

$Paper = Struct.new("Paper", :amount, :value, :dividends, :pnl, :highest)
$papers = {}

$Transaction = Struct.new("Transaction", :type, :paper, :date, :amount, :price, :acqp, :pnl, :value, :diff)
$Transactions = []

$rows.reverse.each {
    |cols|
    next if (cols[0] == "Datum")
    #p cols

    value_raw = BigDecimal.new(cols[6].sub(",", "."))
    value = value_raw.abs
    type = cols[2]
    papern = cols[3]
    amount_raw = BigDecimal.new(cols[4].sub(",", "."))
    amount = amount_raw.abs
    price = BigDecimal.new(cols[5].sub(",", "."))
    diff = (price * amount_raw) + value_raw

    $account = cols[1]
    if (type =~ /Ins.ttning/)
        $deposits += value
        $kassa += value
        $Transactions << $Transaction.new(DEPOSIT, nil, cols[0], 0, 0, 0, 0, value, diff)
    end
    if (type =~ /Uttag/)
        $withdrawn -= value
        $kassa -= value
        $Transactions << $Transaction.new(WITHDRAWAL, nil, cols[0], 0, 0, 0, 0, value, diff)
    end
    buy = false
    sell = false
    if (type =~ /, r.ttelse/)
        value = -value
        amount = -amount
    end

    if (type =~ /K.p/)
        buy = true
    elsif (type =~ /S.lj/)
        sell = true
    end

    if (type == "Prelskatt utdelningar")
        $prelskatt += value
        $kassa -= value
        next
    end
    if (buy || sell || amount != 0)
        value = value != 0 ? value : (amount * price).abs
        paper = $papers[papern] || $papers[papern] = $Paper.new(0, 0, 0, 0, 0)
    end
    
    if (type == "Utdelning")
        paper.dividends += value
        $dividends += value
        $kassa += value
        $Transactions << $Transaction.new(DIVIDEND, papern, cols[0], amount, price, 0, 0, value, 0)
    end

    if (type =~ /.vrigt/)
        if (papern == "Avkastningsskatt")
            $prelskatt += value_raw
        else
            $other += value_raw
        end
        $kassa -= value
        $Transactions << $Transaction.new(OTHER, papern, cols[0], 0, 0, 0, 0, value_raw, 0)
    end

    if (buy)
        $bought += value
        $kassa -= value
        paper.amount = paper.amount + amount
        paper.value += value
        paper.highest = [paper.highest, price].max
        acqp = paper.value/paper.amount
        $Transactions << $Transaction.new(BUY, papern, cols[0], amount, price, acqp, 0, value, diff)
    elsif (sell)
        $sold += value
        $kassa += value
        acqp = paper.amount == 0 ? 0 : paper.value/paper.amount
        acqv = acqp * amount
        paper.amount -= amount
        paper.value -= acqv
        pnl = value - acqv
        $pnl0 += pnl
        paper.pnl += pnl
        $Transactions << $Transaction.new(SALE, papern, cols[0], amount, price, acqp, pnl, value, diff)
    end
}
puts "Konto: #{$account}"
puts

$diff = BigDecimal.new(0)
$Transactions.each {
    |trans|
    if (trans.paper != nil)
        pnl = trans.pnl == 0 ? "" : "#{$___}PnL: #{round(trans.pnl)}"
        acqp = (trans.acqp == 0) ? "" : "#{$___}Ansk.pris: #{rounda(trans.acqp, 100)}"
        puts "[#{trans.type}] Datum: #{trans.date}#{$___}Papper: \"#{trans.paper}\"#{$___}Antal: #{rounda(trans.amount, 10000)}#{$___}Pris: #{round(trans.price)}#{$___}Belopp: #{round(trans.value)}#{acqp}#{pnl}"
        $diff += trans.diff
#        p $diff.to_f
    else
        puts "[#{trans.type}] Datum: #{trans.date}#{$___}Belopp: #{round(trans.value)}#{acqp}#{pnl}"
    end
}
# puts "Differens: #{$diff.to_f}"
puts

netbought = $bought - $sold
$pnl = BigDecimal.new(0)
$value = BigDecimal.new(0)
$vikt = BigDecimal.new(0)
holdings = []
soldoff = []

$papers.sort{|a, b|
    boq = (b[1].amount == 0 ? 0 : 1)
    aaq = (a[1].amount == 0 ? 0 : 1)
    if (aaq != boq)
        (aaq <=> boq) * -1
    else
        a[0].upcase <=> b[0].upcase
    end
    }.each {
    |name, paper|
    $pnl = $pnl + paper.pnl
    pnl = (paper.pnl == 0) ? "" : "#{$___}PnL: #{round(paper.pnl)}"
    divpercent = paper.amount == 0 ? "" : " (#{round(paper.dividends/paper.value * 100.0)}%)"
    dividends = (paper.dividends == 0) ? "" : "#{$___}Utdelningar: #{round(paper.dividends)}" + divpercent
    if (paper.amount != 0)
        vikt = paper.value/(netbought + $pnl0) * 100
        $vikt += vikt
        holdings << "Innehav: \"#{name}\"#{$___}Antal: #{rounda(paper.amount, 10000)}#{$___}Investerat: #{rounda(paper.value, 100)}#{$___}Vikt: #{rounda(vikt, 100)}%#{$___}Ansk.pris: #{rounda((paper.amount == 0 ? 0 : paper.value/paper.amount), 100)}#{$___}Högsta: #{rounda(paper.highest, 100)}#{pnl}#{dividends}"
        $value = $value + paper.value
    else
        soldoff << "Avslutat innehav: \"#{name}\"#{pnl}#{dividends}"
    end
}
soldoff.each {|entry| puts entry}
puts
holdings.each {|entry| puts entry}
puts

puts "Insättningar: #{$deposits.to_f}#{$___}Uttag: #{$withdrawn.to_f}#{$___}netto: #{(netdep = $deposits - $withdrawn).to_f}"
puts "Köpt: #{rounda($bought, 100)}#{$___}Sålt: #{rounda($sold, 100)}#{$___}netto: #{rounda($bought - $sold, 100)}"
puts "Utdelningar: #{$dividends.to_f}#{$___}Prelskatt: #{$prelskatt.to_f}"
puts "Övrigt: #{$other.to_f}"
if (round($vikt) != round(100))
    raise [$vikt, 100.0].inspect
end
if (round($pnl) != round($pnl0))
    raise [$pnl0, $value].inspect
end
if (round(v2 = netbought + $pnl) != round($value))
    raise [v2, $value].inspect
end

cash = netdep - netbought + $dividends + $prelskatt + $other
if (cash != $kassa)
    raise [cash, $kassa].inspect
end

$pnlpercent = $deposits != 0 ? $pnl / $deposits * 100 : 0
$invpercent = netdep != 0 ? $value / netdep * 100 : 0
$cashpercent = $value != 0 ? $kassa / $value * 100 : 0
puts
puts "Totalt investerat: #{rounda($value, 100)} (#{rounda($invpercent, 10)}% av nettoinsättningar), Totalt realiserat resultat: #{rounda($pnl, 100)} (#{rounda($pnlpercent, 10)}% av insättningar)"
puts "Kassa: #{rounda($kassa, 100)} (#{rounda($cashpercent, 10)}% av investerat)"
