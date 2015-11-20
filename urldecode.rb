if ($_ != nil)
    $_.gsub!( /&#(x)?([a-fA-F0-9]+);/) { |m| ('%c' % ($1 == nil ? $2.to_i : $2.hex))}
    $_.gsub!( /%([a-fA-F0-9]+)/) { |m| ('%c' % $1.hex)}
end
