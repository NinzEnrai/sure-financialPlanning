require "test_helper"

class FinancialPlanning::HoldingsCostBasisSeriesTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    # The holdings fixtures share this account with dates inside the window and
    # carry no cost basis, so they would contribute zero totals that shadow the
    # rows a test creates. Clearing them keeps each assertion about the series
    # and nothing else.
    Holding.where(account: accounts(:investment)).destroy_all
    @series = FinancialPlanning::HoldingsCostBasisSeries.new(@family)
  end

  test "a family with no holdings totals zero" do
    assert_equal 0, @series.total(as_of: Date.current).to_f
  end

  # Holdings arrive on the day the provider syncs, so the answer to "what did we
  # hold then" has to come from the nearest earlier day, not an exact match.
  test "total reads the most recent date at or before the one asked for" do
    create_holding(cost_basis: 1000, date: 3.days.ago.to_date)
    create_holding(cost_basis: 2500, date: 1.day.ago.to_date)

    assert_equal 1000, @series.total(as_of: 3.days.ago.to_date).to_f
    assert_equal 2500, @series.total(as_of: 1.day.ago.to_date).to_f
    # No holdings on these dates; the earlier known value carries forward.
    assert_equal 2500, @series.total(as_of: Date.current).to_f
    assert_equal 0, @series.total(as_of: 10.days.ago.to_date).to_f
  end

  test "summing the day totals across every position" do
    create_holding(cost_basis: 1000, date: Date.current)
    create_holding(cost_basis: 400, date: Date.current, security: securities(:msft))

    assert_equal 1400, @series.total(as_of: Date.current).to_f
  end

  test "holds bought during the range are the invested amount" do
    create_holding(cost_basis: 1000, date: 2.months.ago.to_date)
    create_holding(cost_basis: 1750, date: Date.current)

    assert_equal 750, @series.invested_between(start_date: 1.month.ago.to_date, end_date: Date.current)
  end

  test "a sale inside the range reports a negative change" do
    create_holding(cost_basis: 2000, date: 2.months.ago.to_date)
    create_holding(cost_basis: 750, date: Date.current)

    assert_equal(-1250, @series.invested_between(start_date: 1.month.ago.to_date, end_date: Date.current))
  end

  # A family that invests in the currency it lives in while its base currency is
  # something else must still be counted. Filtering to family-currency holdings
  # instead reported a confident zero, which reads as "you didn't invest".
  # (EUR -> GBP is the only rate the fixtures define.)
  test "holdings in another currency are converted rather than dropped" do
    create_holding(cost_basis: 500, date: Date.current, currency: "EUR")

    series = FinancialPlanning::HoldingsCostBasisSeries.new(@family, currency: "GBP")

    assert_in_delta 500 * 1.0986, series.total(as_of: Date.current).to_f, 0.01
  end

  test "the family's own currency needs no conversion" do
    create_holding(cost_basis: 750, date: Date.current)

    assert_equal 750, @series.total(as_of: Date.current).to_f
  end

  # Holdings are forward-calculated per account as each provider syncs, so a
  # brokerage last refreshed yesterday and one refreshed this morning hold rows
  # on different dates. Reading a single shared date -- the newest anywhere in the
  # family -- would drop every position on whichever account lagged, and the
  # family would appear to hold nothing in it.
  test "each account is read at its own latest date" do
    stale = accounts(:investment)
    fresh = Account.create!(
      family: @family, name: "Second Brokerage", currency: "USD", balance: 0,
      status: "active", accountable_type: "Investment", accountable: stale.accountable
    )

    create_holding(cost_basis: 1000, date: 1.day.ago.to_date, account: stale)
    create_holding(cost_basis: 500, date: Date.current, account: fresh)

    assert_equal 1500, @series.total(as_of: Date.current).to_f
  end

  # The stale account must also not carry its old figure forward once it does
  # refresh, or a closed position would keep counting forever.
  test "an account that refreshes stops contributing its previous total" do
    account = accounts(:investment)
    create_holding(cost_basis: 1000, date: 1.day.ago.to_date, account: account)
    create_holding(cost_basis: 250, date: Date.current, account: account)

    assert_equal 250, @series.total(as_of: Date.current).to_f
  end

  test "archived accounts are excluded" do
    # update_column rather than update!, because archiving an account normally
    # cascades to its entries and holdings. What is under test is the query's own
    # status filter, not the archiving behaviour.
    create_holding(cost_basis: 1000, date: Date.current)
    accounts(:investment).update_column(:status, "archived")

    assert_equal 0, FinancialPlanning::HoldingsCostBasisSeries.new(@family).total(as_of: Date.current).to_f
  end

  test "accounts excluded from reports are ignored" do
    create_holding(cost_basis: 1000, date: Date.current)
    accounts(:investment).update_column(:exclude_from_reports, true)

    assert_equal 0, FinancialPlanning::HoldingsCostBasisSeries.new(@family).total(as_of: Date.current).to_f
  end

  private
    def create_holding(cost_basis:, date:, account: accounts(:investment), security: securities(:aapl),
                       currency: account.currency)
      Holding.create!(
        account: account,
        security: security,
        date: date,
        qty: 10,
        price: 100,
        amount: 1000,
        cost_basis: cost_basis,
        currency: currency
      )
    end
end
