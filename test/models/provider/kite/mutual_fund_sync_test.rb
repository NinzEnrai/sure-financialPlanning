require "test_helper"
require "ostruct"

# An AMFI scheme code is a numeric fund identifier, not an exchange ticker:
# a stock provider returns nothing for it. mfapi serves the official AMFI daily
# NAV for exactly this code, so the security must say so.
class Provider::Kite::MutualFundSyncTest < ActiveSupport::TestCase
  # The ISIN -> scheme-code lookup downloads AMFI's daily file. Tests that do
  # not care about it must not reach the network, so default it to "unknown".
  setup { AmfiSchemeIndex.stubs(:scheme_code_for).returns(nil) }

  test "a fund named by ISIN resolves the numeric AMFI scheme code" do
    AmfiSchemeIndex.stubs(:scheme_code_for).with("INF959L01FX6").returns("149892")

    security = sync.send(:find_or_create_fund,
      { "tradingsymbol" => "INF959L01FX6", "fund" => "Navi Nifty Midcap 150 Index Fund",
        "isin" => nil, "quantity" => 1 }
    )

    assert_equal "149892", security.ticker, "the ticker is the symbol handed to mfapi"
    assert_equal "149892", security.amfi_scheme_code
    assert_equal "INF959L01FX6", security.isin, "the ISIN is kept for the next lookup"
  end

  # Funds imported before this mapping existed are keyed by ISIN. They have to be
  # corrected in place, or each sync would create a duplicate security and orphan
  # the holdings pointing at the original.
  test "a fund keyed by ISIN is corrected in place, not duplicated" do
    existing = Security.create!(
      ticker: "INF959L01FX6", amfi_scheme_code: "INF959L01FX6", isin: "INF959L01FX6",
      is_mutual_fund: true, country_code: "IN", price_provider: "mfapi"
    )
    AmfiSchemeIndex.stubs(:scheme_code_for).with("INF959L01FX6").returns("149892")

    security = sync.send(:find_or_create_fund,
      { "tradingsymbol" => "INF959L01FX6", "fund" => "Navi Nifty Midcap 150 Index Fund",
        "isin" => "INF959L01FX6", "quantity" => 1 }
    )

    assert_equal existing.id, security.id
    assert_equal "149892", security.reload.amfi_scheme_code
    assert_equal "149892", security.ticker
  end

  # An ISIN AMFI does not list still has to import: the holding is real even if
  # its NAV cannot be fetched yet.
  test "an unresolvable ISIN keeps the fund imported under its ISIN" do
    security = sync.send(:find_or_create_fund,
      { "tradingsymbol" => "INF000000001", "fund" => "Mystery Fund", "isin" => nil, "quantity" => 1 }
    )

    assert_equal "INF000000001", security.ticker
    assert_equal "INF000000001", security.amfi_scheme_code
    assert_equal "mfapi", security.price_provider
  end

  test "a Coin holding creates a fund priced by mfapi" do
    security = sync.send(:find_or_create_fund,
      { "tradingsymbol" => "125497", "fund" => "HDFC Flexi Cap Fund",
        "isin" => "INF179K01YV8", "quantity" => 10 }
    )

    assert_equal "mfapi", security.price_provider
    assert_equal "125497", security.amfi_scheme_code
    assert security.is_mutual_fund
    assert_equal "IN", security.country_code
  end

  # The ticker is the scheme code, which is what the AMFI lookup takes.
  test "the scheme code doubles as the ticker" do
    security = sync.send(:find_or_create_fund,
      { "tradingsymbol" => "118989", "fund" => "Nippon India Small Cap Fund",
        "isin" => nil, "quantity" => 5 }
    )

    assert_equal "118989", security.ticker
    assert_equal "118989", security.amfi_scheme_code
  end

  test "an existing fund keeps the provider it already had" do
    existing = Security.create!(
      ticker: "125497", amfi_scheme_code: "125497", name: "HDFC Flexi Cap Fund",
      is_mutual_fund: true, country_code: "IN", price_provider: nil
    )

    security = sync.send(:find_or_create_fund,
      { "tradingsymbol" => "125497", "fund" => "HDFC Flexi Cap Fund",
        "isin" => "INF179K01YV8", "quantity" => 10 }
    )

    assert_equal existing.id, security.id
  end

  private

    def sync
      @sync ||= Provider::Kite::MutualFundSync.new(OpenStruct.new(kite_client: nil), nil)
    end
end
