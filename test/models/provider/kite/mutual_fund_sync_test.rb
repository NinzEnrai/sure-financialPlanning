require "test_helper"
require "ostruct"

# An AMFI scheme code is a numeric fund identifier, not an exchange ticker:
# a stock provider returns nothing for it. mfapi serves the official AMFI daily
# NAV for exactly this code, so the security must say so.
class Provider::Kite::MutualFundSyncTest < ActiveSupport::TestCase
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
