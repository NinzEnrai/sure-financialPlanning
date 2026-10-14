require "test_helper"

class FinancialPlanning::SavingsRateTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @account = accounts(:depository)
    @period = Period.current_month_for(@family)

    clear_entries
    # The holdings fixtures sit on this family's investment account at dates
    # inside the period and carry no cost basis, so they'd contribute zero totals
    # that mask the holdings a test creates.
    Holding.where(account: accounts(:investment)).destroy_all
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

  test "separates investment contributions from actual spending" do
    create_transaction(amount: -4000, date: Date.current) # income
    create_transaction(amount: -1000, date: Date.current, kind: :investment_contribution)
    create_transaction(amount: 500, date: Date.current) # actual spending

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)

    assert_equal 4000, rate.income
    assert_equal 1000, rate.invested
    # The statement's 1500 expense total, less the contribution inside it.
    assert_equal 500, rate.expenses
    # Cash left in the accounts: income minus everything that left them.
    assert_equal 2500, rate.cash_savings
    # Cash left plus the money moved into investments.
    assert_equal 3500, rate.savings
    assert_equal 62.5, rate.percent
    assert_equal 87.5, rate.total_percent
  end

  test "a contribution counts as savings rather than spending" do
    create_transaction(amount: -4000, date: Date.current)
    create_transaction(amount: -1000, date: Date.current, kind: :investment_contribution)

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)

    assert_equal 1000, rate.invested
    assert_equal 0, rate.expenses
    assert_equal 3000, rate.cash_savings
    assert_equal 4000, rate.savings
    assert_equal 75.0, rate.percent
    assert_equal 100.0, rate.total_percent
  end

  test "both rates agree when nothing was invested" do
    create_transaction(amount: -4000, date: Date.current)
    create_transaction(amount: 1000, date: Date.current)
    create_transaction(amount: 1000, date: Date.current)

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)

    assert_equal 0, rate.invested
    assert_equal 2000, rate.expenses
    assert_equal 2000, rate.cash_savings
    assert_equal 2000, rate.savings
    assert_equal 50.0, rate.percent
    assert_equal 50.0, rate.total_percent
  end

  test "total savings rate is never below the cash savings rate" do
    create_transaction(amount: -4000, date: Date.current)
    create_transaction(amount: -1000, date: Date.current, kind: :investment_contribution)

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)

    assert_operator rate.total_percent, :>=, rate.percent
  end

  test "excludes contributions outside the period" do
    create_transaction(amount: -4000, date: 2.months.ago.to_date)
    create_transaction(amount: -1000, date: 2.months.ago.to_date, kind: :investment_contribution)

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)

    assert_equal 0, rate.invested
  end

  test "excludes pending contributions" do
    create_transaction(amount: -1000, date: Date.current, kind: :investment_contribution)

    # Pending lives in the provider `extra` blob, which create_transaction
    # doesn't forward to the transaction, so this entry is built by hand.
    Entry.create!(
      account: @account,
      name: "Pending SIP",
      date: Date.current,
      currency: "USD",
      amount: -1000,
      entryable: Transaction.new(
        kind: :investment_contribution, extra: { "plaid" => { "pending" => true } }
      )
    )

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)

    assert_equal 1000, rate.invested
  end

  test "monthly series splits contributions out of each month" do
    create_transaction(amount: -4000, date: Date.current)
    create_transaction(amount: -1000, date: Date.current, kind: :investment_contribution)
    create_transaction(amount: 500, date: Date.current)

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)
    current = rate.monthly_series(months: 1).last

    assert_equal 4000, current[:income]
    assert_equal 1000, current[:invested]
    assert_equal 500, current[:expenses]
    assert_equal 2500, current[:cash_savings]
    assert_equal 3500, current[:savings]
    assert_equal 62.5, current[:percent]
    assert_equal 87.5, current[:total_percent]
  end

  test "average monthly savings counts contributions as saved" do
    create_transaction(amount: -3000, date: 1.month.ago.to_date)
    create_transaction(amount: -1000, date: 1.month.ago.to_date, kind: :investment_contribution)
    create_transaction(amount: 1000, date: 1.month.ago.to_date) # spending, not saving

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)

    # That month kept 2000 -- 1000 unspent cash plus the 1000 invested -- over a
    # 3-month window. Spending the other 1000 is what keeps it at 2000 and not
    # 3000.
    assert_in_delta 666.67, rate.average_monthly_savings(months: 3), 0.01
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

  # A broker that syncs its own holdings never produces an
  # `investment_contribution` transaction, so a purchase has to register as
  # invested on the strength of the change in cost basis alone.
  test "holdings bought during the period count as invested" do
    create_transaction(amount: -4000, date: Date.current) # income
    create_transaction(amount: 500, date: Date.current) # actual spending
    create_holding(cost_basis: 1000, date: before_period)
    create_holding(cost_basis: 1500, date: in_period)

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)

    assert_equal 500, rate.invested
    # Buying a holding is not spending, so the 500 of real spending survives intact.
    assert_equal 500, rate.expenses
    # Only the 500 that left the accounts comes off the top of income.
    assert_equal 3500, rate.cash_savings
    # Cash left over plus the 500 now sitting in the brokerage account.
    assert_equal 4000, rate.savings
    assert_equal 87.5, rate.percent
    assert_equal 100.0, rate.total_percent
  end

  # The whole reason for measuring at cost: a market move changes what the
  # holdings are worth without any money having been invested.
  test "a price change alone is not counted as invested" do
    create_transaction(amount: -4000, date: Date.current)
    create_transaction(amount: 500, date: Date.current)
    create_holding(cost_basis: 1000, amount: 1000, price: 100, date: before_period)
    create_holding(cost_basis: 1000, amount: 3000, price: 300, date: in_period)

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)

    assert_equal 0, rate.invested
    assert_equal 500, rate.expenses
  end

  test "a sale is not counted as negative investing" do
    create_transaction(amount: -4000, date: Date.current)
    create_transaction(amount: 500, date: Date.current)
    create_holding(cost_basis: 2000, date: before_period)
    create_holding(cost_basis: 500, date: in_period)

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)

    assert_equal 0, rate.invested
    assert_equal 500, rate.expenses
  end

  # Syncing a portfolio for the first time reports everything the family ever
  # paid for, which can dwarf a single month's earnings. Capping at income keeps
  # the rate readable and leaves spending alone -- expenses are never inflated
  # or deflated by the size of the portfolio.
  test "invested is capped at the period's income" do
    create_transaction(amount: -4000, date: Date.current)
    create_transaction(amount: 500, date: Date.current)
    create_holding(cost_basis: 0, date: before_period)
    create_holding(cost_basis: 9999, date: in_period)

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)

    assert_equal 4000, rate.invested
    assert_equal 500, rate.expenses
  end

  # The income ceiling exists only to catch a first-sync artifact. Applying it to
  # a month with no income would erase the investing entirely -- and someone
  # living off last month's savings is exactly who most needs to see the number.
  test "investing during a period with no income still counts" do
    create_transaction(amount: -1000, date: Date.current, kind: :investment_contribution)

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)

    assert_equal 1000, rate.invested
    assert_equal 0, rate.expenses
    assert_equal(-1000, rate.cash_savings)
  end

  # A family that logs the bank -> brokerage transfer *and* has the broker sync
  # its holdings sees the same 1000 twice. Summing the measures would report
  # 2000 invested from 1000 of income.
  test "recorded contributions and holdings are not added together" do
    create_transaction(amount: -4000, date: Date.current)
    create_transaction(amount: -1000, date: Date.current, kind: :investment_contribution)
    create_transaction(amount: 500, date: Date.current)
    create_holding(cost_basis: 0, date: before_period)
    create_holding(cost_basis: 1000, date: in_period)

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)

    assert_equal 1000, rate.invested
    assert_equal 500, rate.expenses
  end

  test "holdings outside investment accounts are ignored" do
    create_transaction(amount: -4000, date: Date.current)
    create_transaction(amount: 500, date: Date.current)
    create_holding(cost_basis: 0, account: accounts(:depository), date: before_period)
    create_holding(cost_basis: 2500, account: accounts(:depository), date: in_period)

    rate = FinancialPlanning::SavingsRate.new(@family, period: @period, user: @user)

    assert_equal 0, rate.invested
  end

  private
    def clear_entries
      Entry.where(account: @family.accounts).destroy_all
    end

    # The last day before the period opens -- the baseline the period's gain is
    # measured against.
    def before_period
      @period.start_date - 1.day
    end

    # Comfortably inside the period, so a purchase lands in the bucket under test
    # rather than in a neighbouring month.
    def in_period
      @period.start_date + 1.day
    end

    def create_holding(cost_basis:, date:, account: accounts(:investment), amount: 1000, price: 100)
      Holding.create!(
        account: account,
        security: securities(:aapl),
        date: date,
        qty: 10,
        price: price,
        amount: amount,
        cost_basis: cost_basis,
        currency: account.currency
      )
    end
end
