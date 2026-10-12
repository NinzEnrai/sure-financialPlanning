require "test_helper"

class FinancialPlanning::SavingsRateTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @account = accounts(:depository)
    @period = Period.current_month_for(@family)

    clear_entries
  end

  test "computes savings rate from income and expense entries" do
    create_transaction(amount: -4000, date: Date.current) # income (negative = inflow)
    create_transaction(amount: 1000, date: Date.current)
    create_transaction(amount: 1000, date: Date.current)

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)

    assert_equal 4000, rate.income
    assert_equal 2000, rate.expenses
    assert_equal 2000, rate.savings
    assert_equal 50.0, rate.percent
  end

  test "percent is nil without income" do
    create_transaction(amount: 500, date: Date.current)

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)

    assert_nil rate.percent
  end

  test "excludes entries outside the period" do
    create_transaction(amount: -4000, date: 2.months.ago.to_date)

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)

    assert_equal 0, rate.income
  end

  test "excludes credit card payments from income and expense" do
    create_transaction(amount: -4000, date: Date.current)
    create_transaction(amount: 500, date: Date.current, kind: :cc_payment)

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)

    assert_equal 4000, rate.income
    assert_equal 0, rate.expenses
  end

  test "counts investment contributions as an expense" do
    create_transaction(amount: -4000, date: Date.current)
    create_transaction(amount: -1000, date: Date.current, kind: :investment_contribution)

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)

    assert_equal 4000, rate.income
    assert_equal 1000, rate.expenses
    assert_equal 75.0, rate.percent
  end

  test "monthly series covers the requested window oldest first" do
    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)
    series = rate.monthly_series(months: 6)
    current_month = @period.start_date.beginning_of_month

    assert_equal 6, series.size
    # Oldest first, and the window ends on the month the rate was built for.
    assert_equal current_month - 5.months, series.first[:date]
    assert_equal current_month, series.last[:date]
  end

  test "trailing rate weights by income rather than averaging months" do
    # Big month: 9000 income, 8000 spent -> 11.1% saved.
    create_transaction(amount: -9000, date: 2.months.ago.to_date)
    create_transaction(amount: 8000, date: 2.months.ago.to_date)

    # Small month: 1000 income, nothing spent -> 100% saved.
    create_transaction(amount: -1000, date: 1.month.ago.to_date)

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)

    # Income-weighted: 2000 saved out of 10000 income = 20%. A plain mean of
    # the two monthly rates would report (11.1 + 100) / 2 = 55.6%.
    assert_equal 20.0, rate.trailing_rate(months: 3)
  end

  test "trailing rate is nil without income in the window" do
    create_transaction(amount: 500, date: Date.current)

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)

    assert_nil rate.trailing_rate(months: 3)
  end

  test "average monthly savings divides the trailing window by the month count" do
    create_transaction(amount: -3000, date: 2.months.ago.to_date)
    create_transaction(amount: 1000, date: 2.months.ago.to_date)
    create_transaction(amount: -3000, date: 1.month.ago.to_date)

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)

    # 2000 + 3000 saved over a 3-month window, including the empty current month.
    assert_in_delta 1666.67, rate.average_monthly_savings(months: 3), 0.01
  end

  private
    def clear_entries
      Entry.where(account: @family.accounts).destroy_all
    end
end