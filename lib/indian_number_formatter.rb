# frozen_string_literal: true

# Formats numbers using the Indian digit-grouping convention (lakh/crore):
#   1234567      -> "12,34,567"
#   123456789.5  -> "12,34,56,789.50"
#
# Usage:
#   IndianNumberFormatter.format(1_234_567)                 # => "12,34,567"
#   IndianNumberFormatter.format(1_234_567, symbol: "\u20B9") # => "\u20B912,34,567"
#   IndianNumberFormatter.format(12_34_56_789, compact: true) # => "1.23 Cr"
#
# Wire this into wherever Sure currently formats Money for display (likely a
# `Money#format` call or a `number_to_currency` helper) behind the family's
# `number_format == "lakh_crore"` preference.
module IndianNumberFormatter
  LAKH  = 100_000
  CRORE = 10_000_000

  module_function

  def format(amount, symbol: nil, decimals: 2)
    negative = amount.negative?
    whole, fraction = amount.abs.round(decimals).to_s.split(".")

    grouped = group_indian(whole)
    formatted = fraction && decimals.positive? ? "#{grouped}.#{fraction.ljust(decimals, '0')}" : grouped
    formatted = "-#{formatted}" if negative
    symbol ? "#{symbol}#{formatted}" : formatted
  end

  # Compact form for dashboards/cards: "1.23 Cr", "45.00 L", "8,200"
  def compact(amount, symbol: nil)
    abs = amount.abs
    value, suffix =
      if abs >= CRORE
        [amount / CRORE.to_f, "Cr"]
      elsif abs >= LAKH
        [amount / LAKH.to_f, "L"]
      else
        return format(amount, symbol: symbol, decimals: 0)
      end

    text = "#{format('%.2f', value)} #{suffix}"
    symbol ? "#{symbol}#{text}" : text
  end

  # Indian grouping: last 3 digits together, then groups of 2 going left.
  def group_indian(whole_digits)
    return whole_digits if whole_digits.length <= 3

    last_three = whole_digits[-3..]
    remainder = whole_digits[0..-4]
    remainder = remainder.reverse.scan(/\d{1,2}/).join(",").reverse
    "#{remainder},#{last_three}"
  end
end
