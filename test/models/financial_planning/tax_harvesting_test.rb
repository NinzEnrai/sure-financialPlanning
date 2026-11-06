require "test_helper"

class FinancialPlanning::TaxHarvestingTest < ActiveSupport::TestCase
  include PortfolioFlowTestHelper

  setup do
    @family = families(:empty)
    @user = users(:empty)
    @account = create_portfolio_account(@family, balance: 0)
    @account.update!(owner: @user)

    @loser = create_portfolio_security(ticker: "LOSE#{SecureRandom.hex(4)}")
    @winner = create_portfolio_security(ticker: "WIN#{SecureRandom.hex(4)}")

    buy(@loser, qty: 10, price: 200)
    buy(@winner, qty: 10, price: 100)

    Security::Price.create!(security: @loser, date: Date.current, price: 150, currency: "USD")
    Security::Price.create!(security: @winner, date: Date.current, price: 120, currency: "USD")
  end

  test "lists only the positions at an unrealised loss" do
    harvesting = build_harvesting

    assert_equal 1, harvesting.candidates.size
    candidate = harvesting.candidates.first

    assert_equal @loser, candidate.security
    assert_in_delta(-500, candidate.loss, 0.01)
    assert_in_delta 500, harvesting.total_loss_amount, 0.01
  end

  test "caps the offset at this year's estimated taxable gains" do
    sell(@winner, qty: 10, price: 300) # +2,000 realised, long/short depends on dates; both are close

    harvesting = build_harvesting

    assert_operator harvesting.taxable_gains, :>, 0
    assert_in_delta [ 500, harvesting.taxable_gains ].min, harvesting.offset_capacity, 0.01
  end

  test "flags a stale price and counts unpriced securities" do
    Security::Price.where(security: @loser).update_all(date: 30.days.ago.to_date)

    harvesting = build_harvesting
    assert harvesting.candidates.first.stale?

    unpriced = create_portfolio_security(ticker: "NOPRICE#{SecureRandom.hex(3)}")
    buy(unpriced, qty: 5, price: 100)

    assert_equal 1, build_harvesting.unpriced_count
  end

  test "is empty when nothing is at a loss" do
    Security::Price.where(security: @loser).update_all(price: 300)

    assert build_harvesting.empty?
    assert_in_delta 0, build_harvesting.total_loss_amount, 0.01
  end

  private
    def build_harvesting
      FinancialPlanning::TaxHarvesting.new(@family, user: @user)
    end

    def buy(security, qty:, price:)
      create_portfolio_trade(account: @account, security: security, qty: qty, price: price, date: 2.months.ago.to_date)
    end

    def sell(security, qty:, price:)
      create_portfolio_trade(account: @account, security: security, qty: -qty, price: price, date: 1.month.ago.to_date)
    end
end
