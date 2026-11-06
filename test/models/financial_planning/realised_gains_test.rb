require "test_helper"

class FinancialPlanning::RealisedGainsTest < ActiveSupport::TestCase
  include PortfolioFlowTestHelper

  setup do
    @family = families(:empty)
    @user = users(:empty)
    @account = create_portfolio_account(@family, balance: 0)
    @account.update!(owner: @user)
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

  test "does not see another member's unshared account" do
    family = families(:dylan_family)
    admin = users(:family_admin)
    unshared = family.accounts.create!(
      name: "Jakob's brokerage", balance: 0, currency: "USD",
      accountable: Investment.new, owner: users(:family_member)
    )
    security = create_portfolio_security(ticker: "PRIVGAIN#{SecureRandom.hex(3)}")
    create_portfolio_trade(account: unshared, security: security, qty: 10, price: 100, date: 2.months.ago.to_date)
    create_portfolio_trade(account: unshared, security: security, qty: -10, price: 150, date: 1.month.ago.to_date)

    gains = FinancialPlanning::RealisedGains.new(family, user: admin)

    assert_not_includes gains.rows.map(&:security), security
  end

  test "treats debt funds as slab-taxed whatever the holding period" do
    fund = Security.create!(ticker: "FUND#{SecureRandom.hex(4)}", name: "Debt fund", is_mutual_fund: true, asset_class: "fixed_income")
    buy(10, 100, 2.years.ago.to_date, security: fund)
    sell(10, 150, 1.month.ago.to_date, security: fund)

    gains = build_gains
    row = gains.rows.first

    assert row.slab_taxed?
    assert_not row.long_term?
    assert_in_delta 500, gains.slab_gain, 0.01
    assert_in_delta 0, gains.short_term_gain, 0.01
    assert_in_delta 0, gains.long_term_gain, 0.01
  end

  test "uses a 730-day threshold for foreign shares" do
    foreign = Security.create!(ticker: "GB#{SecureRandom.hex(4)}", name: "Foreign", country_code: "GB")
    buy(10, 100, 500.days.ago.to_date, security: foreign)
    sell(10, 150, 1.month.ago.to_date, security: foreign)

    short = build_gains.rows.find { |row| row.security == foreign }
    assert_not short.long_term?

    foreign_long = Security.create!(ticker: "GB#{SecureRandom.hex(4)}", name: "Foreign long", country_code: "GB")
    buy(10, 100, 3.years.ago.to_date, security: foreign_long)
    sell(10, 150, 1.month.ago.to_date, security: foreign_long)

    long = build_gains.rows.find { |row| row.security == foreign_long }
    assert long.long_term?
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
