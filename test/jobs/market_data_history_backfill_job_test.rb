require "test_helper"

class MarketDataHistoryBackfillJobTest < ActiveJob::TestCase
  test "picks the securities with the shallowest history first" do
    shallow = build_security("NEWCO") # no prices at all
    deep = build_security("OLDCO")
    deep.prices.create!(date: 2.years.ago.to_date, price: 100, currency: "INR")

    picked = job.send(:shallowest, 5).map(&:ticker)

    assert_includes picked, shallow.ticker, "a security with no history is the most urgent"
    assert_not_includes picked, deep.ticker, "two years of history is enough"
  end

  test "picks at most the batch size" do
    build_security("AAAA")
    build_security("BBBB")
    build_security("CCCC")

    assert_equal 2, job.send(:shallowest, 2).size
  end

  # A provider that refuses must not take the whole nightly run down: the next
  # night simply picks the same securities again.
  test "a failing provider does not raise" do
    build_security("FAILCO")
    Security.any_instance.stubs(:import_provider_prices).returns([ 0, "Yahoo Finance rate limit exceeded" ])

    assert_nothing_raised { MarketDataHistoryBackfillJob.perform_now(1) }
  end

  test "a successful batch is imported" do
    build_security("GOODCO")
    import = Security.any_instance.stubs(:import_provider_prices).returns([ 731, nil ])

    MarketDataHistoryBackfillJob.perform_now(1)

    assert import.at_least_once
  end

  private

    def job
      @job ||= MarketDataHistoryBackfillJob.new
    end

    def build_security(ticker)
      Security.create!(ticker: ticker, exchange_operating_mic: "XNSE", country_code: "IN",
                       price_provider: "yahoo_finance")
    end
end
