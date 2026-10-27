require "test_helper"

# Portfolio::MoneyWeightedReturn decides WHAT the XIRR series is; Portfolio::Xirr
# decides what rate solves it. Portfolio::Xirr's own tests cover the arithmetic,
# so these tests are about the choice of flows: which entries are money moving
# between the owner and the portfolio, which are not, and what the caller is told
# when no rate exists. One test per rule stated in the class header.
class Portfolio::MoneyWeightedReturnTest < ActiveSupport::TestCase
  include PortfolioFlowTestHelper

  setup do
    @family = families(:empty)
    @brokerage = create_portfolio_account(@family, name: "Brokerage")
  end

  def money_weighted_return(closing_value:, as_of: Date.current, basis: :trades, account_ids: [ @brokerage.id ])
    Portfolio::MoneyWeightedReturn.new(
      account_ids: account_ids,
      currency: @brokerage.currency,
      closing_value: closing_value,
      as_of: as_of,
      basis: basis
    )
  end

  test "a buy is money in and a sell is money out, with the closing value last" do
    bought_on = 2.years.ago.to_date
    sold_on = 1.year.ago.to_date
    create_portfolio_trade(account: @brokerage, qty: 10, price: 100, date: bought_on)
    create_portfolio_trade(account: @brokerage, qty: -5, price: 150, date: sold_on)

    subject = money_weighted_return(closing_value: 1200, as_of: Date.current)

    assert_equal [ bought_on, -1000.to_d ], [ subject.flows.first[0], subject.flows.first[1] ]
    assert_equal [ sold_on, 750.to_d ], [ subject.flows[1][0], subject.flows[1][1] ]
    assert_equal [ Date.current, 1200.to_d ], [ subject.flows.last[0], subject.flows.last[1] ]
    assert_equal 3, subject.flows.size
  end

  test "the rate is the rate Xirr gives for the same series" do
    create_portfolio_trade(account: @brokerage, qty: 10, price: 100, date: 2.years.ago.to_date)
    create_portfolio_trade(account: @brokerage, qty: -5, price: 150, date: 1.year.ago.to_date)

    subject = money_weighted_return(closing_value: 1200)

    assert subject.available?
    assert_in_delta Portfolio::Xirr.rate(subject.flows).to_f, subject.rate.to_f, 1e-9
    assert_operator subject.rate.to_f, :>, 0
  end

  test "dividends, fees and internal movements are not cash flows" do
    create_portfolio_trade(account: @brokerage, qty: 10, price: 100, date: 1.year.ago.to_date)
    create_income_trade(account: @brokerage, label: "Dividend", amount: 50, date: 300.days.ago.to_date)
    create_income_trade(account: @brokerage, label: "Fee", amount: 5, date: 200.days.ago.to_date)
    create_portfolio_trade(account: @brokerage, qty: -10, price: 100, label: "Transfer", date: 100.days.ago.to_date)

    subject = money_weighted_return(closing_value: 1000)

    assert_equal 1, subject.flows.count { |_, amount| amount.negative? },
      "only the buy is money in; a dividend, a fee and a transfer move nothing from outside"
    assert_equal 2, subject.flows.size, "one buy plus the closing value"
  end

  test "an excluded entry never reaches the series" do
    create_portfolio_trade(account: @brokerage, qty: 10, price: 100, date: 1.year.ago.to_date)
    create_portfolio_trade(account: @brokerage, qty: -10, price: 100, date: 100.days.ago.to_date, excluded: true)

    subject = money_weighted_return(closing_value: 1000)

    assert_equal 2, subject.flows.size
  end

  test "no flows means no rate rather than a fabricated one" do
    subject = money_weighted_return(closing_value: 0)

    assert_not subject.available?
    assert_nil subject.rate
  end

  test "a zero closing value leaves money going one way, so there is no rate" do
    create_portfolio_trade(account: @brokerage, qty: 10, price: 100, date: 1.year.ago.to_date)

    subject = money_weighted_return(closing_value: 0)

    assert_not subject.available?
    assert_nil subject.rate, "money only ever went in: NoSignChangeError, reported as nil"
  end

  test "the external basis counts contributions and withdrawals and ignores trades" do
    checking = @family.accounts.create!(name: "Checking", balance: 5000, currency: "USD", accountable: Depository.new)
    create_linked_transfer(family: @family, from: checking, to: @brokerage, amount: 1000, date: 1.year.ago.to_date)
    create_portfolio_trade(account: @brokerage, qty: 10, price: 100, date: 1.year.ago.to_date)

    subject = money_weighted_return(closing_value: 1100, basis: :external)

    assert_equal 2, subject.flows.size, "the contribution plus the closing value; the buy is internal"
    assert_equal -1000.to_d, subject.flows.first[1]
    assert subject.available?
  end

  test "an ambiguous series is reported as ambiguous rather than as the rate" do
    create_portfolio_trade(account: @brokerage, qty: 10, price: 100, date: 3.years.ago.to_date)
    create_portfolio_trade(account: @brokerage, qty: -10, price: 300, label: "Sell", date: 2.years.ago.to_date)
    create_portfolio_trade(account: @brokerage, qty: 10, price: 250, date: 1.year.ago.to_date)

    subject = money_weighted_return(closing_value: 100)

    assert subject.ambiguous?, "three direction changes; the caller must hedge the figure"
  end

  test "an unknown basis is refused at construction" do
    assert_raises(ArgumentError) { money_weighted_return(closing_value: 1, basis: :guessed) }
  end
end
