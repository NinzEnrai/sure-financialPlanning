require "test_helper"

class FinancialPlanning::TaxReadinessTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @account = accounts(:investment)

    Security::Price.delete_all
    Entry.where(entryable_type: "Trade").delete_all
    Trade.delete_all
    Holding.delete_all

    @security = Security.create!(ticker: "TAX#{SecureRandom.hex(4)}", name: "Tax test")
    Holding.create!(
      account: @account,
      security: @security,
      date: Date.current,
      qty: 1,
      price: 100,
      amount: 100,
      currency: "USD"
    )
  end

  test "flags a financial year with no trades" do
    readiness = build_readiness

    assert_equal :attention, check(readiness, :trades).status
    assert_equal 0, check(readiness, :trades).count
    assert_equal :attention, check(readiness, :purchase_dates).status
  end

  test "an excluded trade is not counted as tax data" do
    entry = create_trade(@security, account: @account, qty: 1, date: Date.current, price: 100)
    entry.update!(excluded: true)

    readiness = build_readiness

    assert_equal :attention, check(readiness, :trades).status
    assert_equal 0, check(readiness, :trades).count
  end

  test "clears the trade, price and purchase-date checks once they exist" do
    Security::Price.create!(security: @security, date: Date.current, price: 100, currency: "USD")
    create_trade(@security, account: @account, qty: 1, date: Date.current, price: 100)

    readiness = build_readiness

    assert_equal :good, check(readiness, :trades).status
    assert_equal :good, check(readiness, :trade_prices).status
    assert_equal :good, check(readiness, :purchase_dates).status
  end

  test "flags foreign securities for disclosure review" do
    foreign = Security.create!(ticker: "VOD#{SecureRandom.hex(4)}", name: "Vodafone", country_code: "GB")
    Holding.create!(
      account: @account,
      security: foreign,
      date: Date.current,
      qty: 1,
      price: 10,
      amount: 10,
      currency: "USD"
    )

    readiness = build_readiness

    assert_equal :watch, check(readiness, :foreign_assets).status
    assert_equal 1, check(readiness, :foreign_assets).count
  end

  test "uses the April-March financial year in India" do
    @family.update!(country: "IN")

    readiness = build_readiness
    expected_start_year = Date.current.month >= 4 ? Date.current.year : Date.current.year - 1

    assert_equal Date.new(expected_start_year, 4, 1), readiness.start_date
    assert_match(/FY \d{4}-\d{2}/, readiness.financial_year_label)
  end

  test "uses the calendar year elsewhere" do
    readiness = build_readiness

    assert_equal Date.current.beginning_of_year, readiness.start_date
    assert_equal Date.current.year.to_s, readiness.financial_year_label
  end

  private
    def build_readiness
      FinancialPlanning::TaxReadiness.new(@family, user: @user)
    end

    def check(readiness, key)
      readiness.checks.find { |candidate| candidate.key == key }
    end
end
