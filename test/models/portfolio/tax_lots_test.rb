require "test_helper"

class Portfolio::TaxLotsTest < ActiveSupport::TestCase
  include PortfolioFlowTestHelper

  setup do
    @family = families(:empty)
    @account = create_portfolio_account(@family, balance: 0)
    @security = create_portfolio_security(ticker: "LOT#{SecureRandom.hex(4)}")
  end

  test "consumes the oldest lots first and reports the realised gain" do
    buy(10, 100, Date.new(2025, 1, 10))
    buy(10, 120, Date.new(2025, 3, 1))
    sell(15, 150, Date.new(2025, 6, 1))

    engine = build_engine

    assert_equal 2, engine.realisations.size
    first, second = engine.realisations

    assert_equal 10, first.qty
    assert_equal 100, first.cost_per_unit
    assert_equal 500, first.gain
    assert_equal Date.new(2025, 1, 10), first.acquired_on

    assert_equal 5, second.qty
    assert_equal 120, second.cost_per_unit
    assert_equal 150, second.gain

    assert_equal 1, engine.lots.size
    assert_equal 5, engine.lots.first.qty
    assert_equal 120, engine.lots.first.cost_per_unit
  end

  test "capitalises the buy fee into the cost basis" do
    create_portfolio_trade(account: @account, security: @security, qty: 10, price: 100, fee: 10, date: Date.new(2025, 1, 10))

    lot = build_engine.lots.first

    assert_equal 10, lot.qty
    assert_in_delta 101, lot.cost_per_unit, 0.0001
    assert_in_delta 1010, lot.total_cost, 0.01
  end

  test "applies a split before the trades on its ex-date" do
    buy(10, 100, Date.new(2025, 1, 10))
    Security::Split.create!(
      security: @security,
      ex_date: Date.new(2025, 2, 1),
      numerator: 2,
      denominator: 1,
      source: "manual"
    )
    sell(20, 60, Date.new(2025, 3, 1))

    engine = build_engine
    realisation = engine.realisations.first

    assert_equal 20, realisation.qty
    assert_equal 50, realisation.cost_per_unit
    assert_equal 200, realisation.gain
    assert_empty engine.lots
  end

  test "flags a sale with no matching purchase rather than inventing a cost" do
    sell(5, 100, Date.new(2025, 3, 1))

    engine = build_engine
    realisation = engine.realisations.first

    assert realisation.unknown_origin
    assert_nil realisation.cost_per_unit
    assert_nil realisation.gain
    assert_equal 5, engine.unmatched_sales_qty
  end

  test "ignores internal movements between the caller's own accounts" do
    buy(10, 100, Date.new(2025, 1, 10))
    create_portfolio_trade(account: @account, security: @security, qty: -10, price: 100, label: "Transfer", date: Date.new(2025, 2, 1))

    engine = build_engine

    assert_empty engine.realisations
    assert_equal 10, engine.lots.sum(&:qty)
  end

  test "ignores trades after the as-of date" do
    buy(10, 100, Date.new(2025, 1, 10))
    sell(10, 150, Date.new(2025, 11, 1))

    engine = Portfolio::TaxLots.new(account_ids: [ @account.id ], as_of: Date.new(2025, 10, 1))

    assert_equal 10, engine.lots.sum(&:qty)
    assert_empty engine.realisations
  end

  private
    def build_engine
      Portfolio::TaxLots.new(account_ids: [ @account.id ], as_of: Date.new(2025, 12, 31))
    end

    def buy(qty, price, date)
      create_portfolio_trade(account: @account, security: @security, qty: qty, price: price, date: date)
    end

    def sell(qty, price, date)
      create_portfolio_trade(account: @account, security: @security, qty: -qty, price: price, date: date)
    end
end
