require "test_helper"

# Indian digit grouping: the last three digits stand alone, then groups of two
# going left. An Indian reader parses 1,00,00,000 as one crore; 10,000,000 in
# western grouping is the same number, but the eye has to count from the wrong
# end to see it.
class IndianNumberFormatterTest < ActiveSupport::TestCase
  test "groups the last three digits alone and then in twos" do
    assert_equal "123", IndianNumberFormatter.format(123, decimals: 0)
    assert_equal "1,234", IndianNumberFormatter.format(1234, decimals: 0)
    assert_equal "12,345", IndianNumberFormatter.format(12_345, decimals: 0)
    assert_equal "1,23,456", IndianNumberFormatter.format(1_23_456, decimals: 0)
    assert_equal "12,34,567", IndianNumberFormatter.format(12_34_567, decimals: 0)
    assert_equal "1,23,45,678", IndianNumberFormatter.format(1_23_45_678, decimals: 0)
    assert_equal "12,34,56,789", IndianNumberFormatter.format(12_34_56_789, decimals: 0)
  end

  # The number the owner named: one crore is 1,00,00,000, not 10,000,000.
  test "one crore reads as 1,00,00,000" do
    assert_equal "1,00,00,000", IndianNumberFormatter.format(10_000_000, decimals: 0)
    assert_equal "₹1,00,00,000.00", IndianNumberFormatter.format(10_000_000, symbol: "₹")
  end

  test "keeps two decimals by default and pads them" do
    assert_equal "12,34,567.00", IndianNumberFormatter.format(12_34_567)
    assert_equal "12,34,567.50", IndianNumberFormatter.format(12_34_567.5)
    assert_equal "12,34,567.90", IndianNumberFormatter.format(12_34_567.895)
  end

  test "accepts a decimal string or BigDecimal as bigdecimal rides through" do
    assert_equal "1,00,00,000.00", IndianNumberFormatter.format(BigDecimal("10000000"))
    assert_equal "12,34,567.12", IndianNumberFormatter.format("1234567.12")
  end

  # Matches the app's western negative convention (number_to_currency's own
  # negative_format), so a sign reads the same in either grouping.
  test "a sign sits before the symbol, as Money#format puts it" do
    assert_equal "-12,34,567.00", IndianNumberFormatter.format(-12_34_567)
    assert_equal "-₹12,34,567.00", IndianNumberFormatter.format(-12_34_567, symbol: "₹")
  end

  test "a supplied symbol is prefixed with no space" do
    assert_equal "₹12,34,567.00", IndianNumberFormatter.format(12_34_567, symbol: "₹")
  end

  test "zero and sub-thousand amounts are ungrouped" do
    assert_equal "0.00", IndianNumberFormatter.format(0)
    assert_equal "999.00", IndianNumberFormatter.format(999)
  end

  test "compact picks crores, then lakhs, then plain digits" do
    assert_equal "1.23 Cr", IndianNumberFormatter.compact(1_23_45_678)
    assert_equal "10.00 Cr", IndianNumberFormatter.compact(10_00_00_000)
    assert_equal "1.00 L", IndianNumberFormatter.compact(1_00_000)
    assert_equal "45.00 L", IndianNumberFormatter.compact(45_00_000)
    # Below a lakh the compact form falls back to grouped digits with no decimals
    assert_equal "99,999", IndianNumberFormatter.compact(99_999)
  end

  test "compact keeps the sign and accepts a symbol" do
    assert_equal "-1.23 Cr", IndianNumberFormatter.compact(-1_23_45_678)
    assert_equal "₹1.23 Cr", IndianNumberFormatter.compact(1_23_45_678, symbol: "₹")
  end

  # Money#format reaches number_to_currency with delimiter_pattern, so the
  # helper and this formatter must agree on the same grouping.
  test "agrees with number_to_currency's delimiter_pattern grouping" do
    helper = Object.new.extend(ActionView::Helpers::NumberHelper)

    [ 0, 999, 1000, 12_345, 1_23_456, 12_34_567, 1_00_00_000, 12_34_56_789 ].each do |amount|
      currency = helper.number_to_currency(
        amount,
        unit: "", precision: 0, delimiter: ",", separator: ".",
        delimiter_pattern: ApplicationHelper::INDIAN_DELIMITER_PATTERN
      )

      assert_equal IndianNumberFormatter.format(amount, decimals: 0), currency, "grouping drifted at #{amount}"
    end
  end
end
