# (Income - Expenses) / Income for a period, plus the monthly series behind it.
#
# Income and expenses come from IncomeStatement so every figure obeys the same
# scoping stack as the dashboard: pending transactions, one-time rows, funds
# movements and credit-card payments excluded, amounts converted to the family
# currency, tax-advantaged accounts left out.
#
# Investment contributions are pulled back out of the expense total into their
# own `invested` bucket. Sure counts them as expenses by design -- net worth
# already holds the asset they bought, so dropping them from expenses outright
# would understate what was kept. Reporting them separately is what lets the
# widget show cash savings and total savings without conflating the two. There is
# no debt bucket: this family doesn't carry debt.
#
# `invested` is measured three independent ways -- recorded `investment_contribution`
# transfers, spending in categories the family mapped to the Savings bucket
# (a manual SIP or broker payment entered as a transaction), and the change in
# holdings cost basis -- and takes the larger. All three answer "how much money
# went into assets"; the first only sees transfers the family logged by hand,
# the second sees ordinary categorised payments, and the third sees a broker
# that syncs its own holdings (Kite). They are never summed, because a family
# that both logs the transfer and syncs the holdings would otherwise count the
# same money twice. Only the holdings measure is capped at period income,
# because a first sync reports everything ever paid; real transfers and
# categorised investments are not artifacts and are reported in full.
class FinancialPlanning::SavingsRate
  attr_reader :family, :period

  def initialize(family, period:, user: nil, income_statement: nil)
    @family = family
    @period = period
    @user = user || Current.user
    @income_statement = income_statement
  end

  def income
    @income ||= totals.income_money.amount
  end

  # Money moved into investments during the period, whichever way it was
  # measured -- see the class comment. Never above the period's income: a
  # portfolio synced for the first time reports everything the family ever paid
  # for, and dividing that by one month's earnings would print a savings rate of
  # several thousand percent.
  def invested
    @invested ||= invested_for(period)
  end

  # What was actually consumed: spending only.
  #
  # Recorded contributions are pulled back out because the statement already
  # counts them as expenses. Holdings-derived investment is not, and never was --
  # money that left a bank account and appeared as a Zerodha holding was never
  # entered as a transaction -- so subtracting it here would charge consumption
  # for something that was saved.
  def expenses
    @expenses ||= total_expenses - investment_expense_total
  end

  # Cash that stayed in the family's accounts: income less everything that left
  # them, contributions included, since those moved too. The headline figure --
  # what was left over before asking how it was held.
  def cash_savings
    @cash_savings ||= income - total_expenses
  end

  # Everything kept this period -- cash left over plus whatever was moved into
  # investments. Never below #cash_savings.
  def savings
    cash_savings + invested
  end

  # A zero-income window has no meaningful rate; nil says "can't compute" and
  # the view renders a placeholder rather than a confident 0%.
  def percent
    return nil unless income.positive?

    ((cash_savings / income) * 100).round(1)
  end

  # The same rate measured on everything kept, investments included. Higher
  # than or equal to #percent, by exactly the invested share.
  def total_percent
    return nil unless income.positive?

    ((savings / income) * 100).round(1)
  end

  def income_money
    Money.new(income, currency)
  end

  def expenses_money
    Money.new(expenses, currency)
  end

  def invested_money
    Money.new(invested, currency)
  end

  def savings_money
    Money.new(savings, currency)
  end

  def cash_savings_money
    Money.new(cash_savings, currency)
  end

  # Trailing months, oldest first, for the savings-rate sparkline. Reads them
  # through this instance's own IncomeStatement rather than building a rate
  # object per month -- `Family#income_statement` is not memoized, so a nested
  # instance per month would construct a dozen statements per request.
  def monthly_series(months: 12)
    (0...months).map do |offset|
      build_month(period.start_date.beginning_of_month - (months - 1 - offset).months)
    end
  end

  # Income-weighted average over a trailing window, measured on everything kept
  # so it agrees with #average_monthly_savings -- the two drive the same
  # projection and a rate that disagreed with its own contribution figure would
  # be worse than useless. Averaging monthly percentages would let a near-empty
  # month swing the result; weighting by income keeps a low-traffic month from
  # dominating.
  def trailing_rate(months: 6)
    window = trailing_window(months: months)
    return nil unless window[:income].positive?

    ((window[:savings] / window[:income]) * 100).round(1)
  end

  # Mean amount actually saved per month across the window, investments
  # included. Dividing by the month count rather than the months that had
  # activity, so a household that started saving this month doesn't report an
  # inflated pace.
  def average_monthly_savings(months: 6)
    trailing_window(months: months)[:savings] / months
  end

  private
    attr_reader :user

    def currency
      family.currency
    end

    def income_statement
      @income_statement ||= family.income_statement(user: user)
    end

    def totals
      @totals ||= income_statement.totals_for(period)
    end

    # The statement's own expense total, contributions and all. `expenses` is
    # this minus `invested`; the raw figure is kept so the split stays visible
    # in one place rather than being reconstructed at each call site.
    def total_expenses
      @total_expenses ||= total_expenses_for(period)
    end

    def total_expenses_for(scope_period)
      income_statement.totals_for(scope_period).expense_money.amount
    end

    # Three measures of "money went into investments", the larger winning. See
    # the class comment for why they are combined this way rather than added.
    def invested_for(scope_period)
      # Real cash movements: recorded transfers and savings-bucket spending.
      # These are actual money the household moved, so they are never capped.
      actual = [
        contributions_for(scope_period),
        savings_bucket_invested_for(scope_period)
      ].max
      actual = 0 if actual.negative?

      # A synced portfolio's first snapshot reports everything the family ever
      # paid for, which would dwarf one month's earnings. Only this measure gets
      # the income ceiling; capping a real SIP payment at a low-income month's
      # income would hide the investment the household actually made.
      holdings = holdings_invested_for(scope_period)
      holdings = 0 if holdings.negative?
      ceiling = income_for(scope_period)
      holdings = [ holdings, ceiling ].min if ceiling.positive?

      [ actual, holdings ].max.round(2)
    end

    def income_for(scope_period)
      income_statement.totals_for(scope_period).income_money.amount
    end

    def contribution_total
      @contribution_total ||= contributions_for(period)
    end

    # The part of the period's expense total that is really investment, not
    # consumption: transfers labelled as contributions, plus spending in the
    # categories the household mapped to the Savings bucket. max(), not a sum,
    # because a contribution can also carry a savings-bucket category and must
    # not be subtracted twice.
    def investment_expense_total
      @investment_expense_total ||= [
        contribution_total,
        savings_bucket_invested_for(period)
      ].max
    end

    def contributions_for(scope_period)
      income_statement.investment_contributions_total(scope_period)
    end

    def holdings_invested_for(scope_period)
      holdings_series.invested_between(
        start_date: scope_period.start_date,
        end_date: scope_period.end_date
      )
    end

    # Money paid to investments recorded as ordinary transactions: anything in
    # a category the family mapped to the Savings bucket in the 50/30/20
    # settings (by default "Savings & Investments" and "Other Investments",
    # including family overrides). This is how a manual SIP or broker payment
    # entered as a transaction becomes "invested" rather than consumption;
    # without it those payments read as spending and the card showed no
    # investment at all.
    def savings_bucket_invested_for(scope_period)
      @savings_bucket_invested ||= {}
      key = [ scope_period.start_date, scope_period.end_date ]
      return @savings_bucket_invested[key] if @savings_bucket_invested.key?(key)

      analyzer = FinancialPlanning::BudgetAnalyzer.new(
        family, period: scope_period, user: user, income_statement: income_statement
      )
      @savings_bucket_invested[key] =
        analyzer.buckets.find { |bucket| bucket.key == "savings" }&.amount.to_d.round(2)
    end

    # One series for the instance, not one per month: the sparkline differences
    # twelve of them and the constructor issues a single query.
    def holdings_series
      @holdings_series ||= FinancialPlanning::HoldingsCostBasisSeries.new(family)
    end

    def month_period(month)
      Period.custom(start_date: month.beginning_of_month, end_date: month.end_of_month)
    end

    # One month's row, built from the same statement so every figure on the
    # series obeys one definition of which transactions count.
    def build_month(month)
      scope_period = month_period(month)
      scope_totals = income_statement.totals_for(scope_period)

      month_income = scope_totals.income_money.amount
      month_total_expenses = scope_totals.expense_money.amount
      month_invested = invested_for(scope_period)
      month_expenses = month_total_expenses - [
        contributions_for(scope_period),
        savings_bucket_invested_for(scope_period)
      ].max
      month_cash_savings = month_income - month_total_expenses
      month_savings = month_cash_savings + month_invested

      {
        date: month,
        income: month_income,
        expenses: month_expenses,
        invested: month_invested,
        savings: month_savings,
        cash_savings: month_cash_savings,
        percent: percent_of(month_cash_savings, month_income),
        total_percent: percent_of(month_savings, month_income)
      }
    end

    # nil, not 0%, for a month with no income -- same "can't compute" contract
    # as #percent.
    def percent_of(amount, month_income)
      return nil unless month_income.positive?

      ((amount / month_income) * 100).round(1)
    end

    # Totals across the whole trailing window in one pass, so the rate and the
    # average monthly figure can never disagree about which months count.
    def trailing_window(months:)
      @trailing_windows ||= {}
      @trailing_windows[months] ||= months.times.reduce({ income: 0, savings: 0 }) do |totals, offset|
        row = build_month(period.start_date.beginning_of_month - offset.months)

        totals.merge(income: totals[:income] + row[:income], savings: totals[:savings] + row[:savings])
      end
    end
end
