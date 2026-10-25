require "test_helper"
require "ostruct"

# Kite supplies holdings and trades, never prices. Daily closes come from Yahoo,
# which serves .NS/.BO for the Indian exchanges — so the security Kite creates
# has to record that, or it falls back to whichever provider is enabled first.
class Provider::Kite::HoldingsSyncTest < ActiveSupport::TestCase
  test "an NSE holding creates a security priced by yahoo_finance" do
    security = sync.send(:find_or_create_security, 
      { "tradingsymbol" => "RELIANCE", "exchange" => "NSE", "isin" => "INE002A01018" }
    )

    assert_equal "yahoo_finance", security.price_provider
    assert_equal "XNSE", security.exchange_operating_mic
    assert_equal "IN", security.country_code
    assert_equal "INE002A01018", security.isin
  end

  test "a BSE holding maps to XBOM and still uses yahoo_finance" do
    security = sync.send(:find_or_create_security, 
      { "tradingsymbol" => "TATAPOWER", "exchange" => "BSE", "isin" => "INE245A01021" }
    )

    assert_equal "yahoo_finance", security.price_provider
    assert_equal "XBOM", security.exchange_operating_mic
  end

  # find_or_create_by! yields its block only on create, so a provider the owner
  # (or a reseed) already chose must not be overwritten by a later sync.
  test "an existing security keeps the provider it already had" do
    existing = Security.create!(
      ticker: "RELIANCE", exchange_operating_mic: "XNSE",
      name: "Reliance Industries", country_code: "IN", price_provider: "tiingo"
    )

    security = sync.send(:find_or_create_security, 
      { "tradingsymbol" => "RELIANCE", "exchange" => "NSE", "isin" => "INE002A01018" }
    )

    assert_equal existing.id, security.id
    assert_equal "tiingo", security.reload.price_provider
  end

  private

    # initialize only derives a client from the item; these tests exercise
    # security creation, which never touches the network.
    def sync
      @sync ||= Provider::Kite::HoldingsSync.new(OpenStruct.new(kite_client: nil), nil)
    end
end
