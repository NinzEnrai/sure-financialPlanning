require "test_helper"

# Zerodha identifies a fund by ISIN, the AMFI NAV feed by scheme code. This
# index is the bridge; everything about fund pricing depends on it.
class AmfiSchemeIndexTest < ActiveSupport::TestCase
  BODY = <<~TXT
    Scheme Code;ISIN Div Payout/ ISIN Growth;ISIN Div Reinvestment;Scheme Name;Plan;Option;Net Asset Value;Date

    Open Ended Schemes(Childrens Fund)

    Axis Mutual Fund

    135762;INF846K01WO1;-;Axis Children's Fund;Direct Plan;Growth Option;28.6173;23-Oct-2026
    119551;INF209KA12Z1;INF209KA13Z9;Aditya Birla Sun Life Banking;Direct Plan;IDCW-Re-investment;106.4956;23-Oct-2026
  TXT

  test "maps both ISIN columns to the one scheme code" do
    map = AmfiSchemeIndex.parse(BODY)

    assert_equal "135762", map["INF846K01WO1"]
    assert_equal "119551", map["INF209KA12Z1"], "payout/growth ISIN"
    assert_equal "119551", map["INF209KA13Z9"], "reinvestment ISIN shares the code"
  end

  test "ignores section headings, blank lines and placeholder dashes" do
    map = AmfiSchemeIndex.parse(BODY)

    assert_equal 3, map.size
    assert_not map.key?("-")
    assert_not map.key?("")
  end

  test "an empty body parses to an empty map rather than raising" do
    assert_equal({}, AmfiSchemeIndex.parse(""))
    assert_equal({}, AmfiSchemeIndex.parse(nil))
  end

  test "isin? tells an ISIN from a scheme code" do
    assert AmfiSchemeIndex.isin?("INF959L01FX6")
    assert AmfiSchemeIndex.isin?("inf959l01fx6"), "case does not matter"
    assert_not AmfiSchemeIndex.isin?("125497")
    assert_not AmfiSchemeIndex.isin?("")
    assert_not AmfiSchemeIndex.isin?(nil)
  end

  # A scheme code is already the answer. Looking it up in the feed would be a
  # wasted 1.5MB download on every fund that already resolves.
  test "scheme_code_for short-circuits on a non-ISIN without loading the feed" do
    AmfiSchemeIndex.expects(:index).never

    assert_nil AmfiSchemeIndex.scheme_code_for("125497")
  end

  test "scheme_code_for normalises case and whitespace" do
    AmfiSchemeIndex.stubs(:index).returns({ "INF959L01FX6" => "149892" })

    assert_equal "149892", AmfiSchemeIndex.scheme_code_for(" inf959l01fx6 ")
  end

  test "scheme_code_for returns nil for an ISIN the feed does not list" do
    AmfiSchemeIndex.stubs(:index).returns({})

    assert_nil AmfiSchemeIndex.scheme_code_for("INF000000001")
  end
end
