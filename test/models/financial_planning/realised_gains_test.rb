require "test_helper"

class FinancialPlanning::RealisedGainsTest < ActiveSupport::TestCase
  include PortfolioFlowTestHelper

  setup do
    @family = families(:empty)
    @user = users(:family_admin)
    @account = create_portfolio_account(@family, balance: 0)
    @security = create_portfolio_security(ticker: "GAIN#{SecureRandom.hex(4)}")
  end

  test "splits realised gains into short and long term for the year" do
    buy(10, 100, 2.months.ago.to_date)
    sell(10, 150, 1.month.ago.to_date)

    older = create_portfolio_security(ticker: "OLD#{SecureRandom.hex(4)}")
    buy(10, 100, 2.years.ago.to_date, security: older)
    sell(10, 120, 1.month.ago.to_date, security: older)

    gains = build_gains

    assert_in_delta 700, gains.total_gain, 0.01
    assert_in_delta 500, gains.short_term_gain, 0.01
    assert_in_delta 200, gains.long_term_gain, 0.01
    assert_equal 2, gains.rows.size
    assert_not gains.empty?
  end

  test "excludes a sale with no purchase date and counts it" do
    sell(5, 100, 1.month.ago.to_date)

    gains = build_gains

    assert_equal 1, gains.unknown_count
    assert_equal 0, gains.total_gain
    assert_not gains.empty?
  end

  test "is empty when nothing was sold" do
    buy(10, 100, 2.months.ago.to_date)

    assert build_gains.empty?
  end

  private
    def build_gains
      FinancialPlanning::RealisedGains.new(@family, user: @user)
    end

    def buy(qty, price, date, security: @security)
      create_portfolio_trade(account: @account, security: security, qty: qty, price: price, date: date)
    end

    def sell(qty, price, date, security: @security)
      create_portfolio_trade(account: @account, security: security, qty: -qty, price: price, date: date)
    end
end
