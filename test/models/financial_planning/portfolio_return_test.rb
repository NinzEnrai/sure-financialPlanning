require "test_helper"

class FinancialPlanning::PortfolioReturnTest < ActiveSupport::TestCase
  include PortfolioFlowTestHelper

  setup do
    @family = families(:empty)
  end

  test "reports the money-weighted return and the money that produced it" do
    account = create_portfolio_account(@family, balance: 1200)
    create_portfolio_trade(account: account, qty: 10, price: 100, date: 6.months.ago.to_date)

    portfolio = FinancialPlanning::PortfolioReturn.new(@family, user: nil)
    expected = Portfolio::Xirr.rate(portfolio.weighted_return.flows).to_f * 100

    assert_not portfolio.empty?
    assert portfolio.available?
    assert_in_delta expected, portfolio.rate_percent.to_f, 0.01
    assert_in_delta 1000, portfolio.contributions_money.amount.to_f, 0.01
    assert_in_delta 0, portfolio.withdrawals_money.amount.to_f, 0.01
    assert_in_delta 1200, portfolio.portfolio_value.to_f, 0.01
  end

  test "an empty portfolio has no rate rather than a zero" do
    portfolio = FinancialPlanning::PortfolioReturn.new(@family, user: nil)

    assert portfolio.empty?
    assert_equal 0, portfolio.portfolio_value
    assert_not portfolio.available?
    assert_nil portfolio.rate_percent
    assert_in_delta 0, portfolio.income_money.amount.to_f, 0.01
  end

  test "states the date the series starts" do
    account = create_portfolio_account(@family, balance: 1100)
    first = 10.months.ago.to_date
    create_portfolio_trade(account: account, qty: 10, price: 100, date: first)

    portfolio = FinancialPlanning::PortfolioReturn.new(@family, user: nil)

    assert_equal first, portfolio.since
  end
end
