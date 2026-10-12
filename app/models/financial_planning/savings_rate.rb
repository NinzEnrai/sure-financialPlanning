# (Income - Expenses) / Income for a period, plus the monthly series behind it.
#
# All figures come from IncomeStatement so the savings rate obeys the same
# scoping stack as every other number on the dashboard: pending transactions,
# one-time rows, funds movements and credit-card payments excluded, amounts
# converted to the family currency, tax-advantaged accounts left out.
class FinancialPlanning::SavingsRate
  attr_reader :family, :period

  def initialize(family, period:, user: nil)
    @family = family
    @period = period
    @user = user || Current.user
  end

  def income
    @income ||= totals.income_money.amount
  end

  def expenses
    @expenses ||= totals.expense_money.amount
  end

  def savings
    income - expenses
  end

  # A zero-income window has no meaningful rate; nil says "can't compute" and
  # the view renders a placeholder rather than a confident 0%.
  def percent
    return nil unless income.positive?

    ((savings / income) * 100).round(1)
  end

  def income_money
    Money.new(income, currency)
  end

  def expenses_money
    Money.new(expenses, currency)
  end

  def savings_money
    Money.new(savings, currency)
  end

  # Trailing months, oldest first, for the savings-rate sparkline. Reads them
  # through this instance's own IncomeStatement rather than building a rate
  # object per month — `Family#income_statement` is not memoized, so a nested
  # instance per month would construct a dozen statements per request.
  def monthly_series(months: 12)
    (0...months).map do |offset|
      build_month(period.start_date.beginning_of_month - (months - 1 - offset).months)
    end
  end

  # Income-weighted average over a trailing window. Averaging monthly
  # percentages would let a near-empty month swing the result; weighting by
  # income keeps a low-traffic month from dominating.
  def trailing_rate(months: 6)
    window = trailing_window(months: months)
    return nil unless window[:income].positive?

    ((window[:savings] / window[:income]) * 100).round(1)
  end

  # Mean amount actually saved per month across the window. Dividing by the
  # month count rather than the months that had activity, so a household that
  # started saving this month doesn't report an inflated pace.
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

    def month_period(month)
      Period.custom(start_date: month.beginning_of_month, end_date: month.end_of_month)
    end

    # One month's row, built from the same statement so every figure on the
    # series obeys one definition of which transactions count.
    def build_month(month)
      scope_totals = income_statement.totals_for(month_period(month))
      month_income = scope_totals.income_money.amount
      month_expenses = scope_totals.expense_money.amount
      month_savings = month_income - month_expenses

      {
        date: month,
        income: month_income,
        expenses: month_expenses,
        savings: month_savings,
        percent: month_income.positive? ? ((month_savings / month_income) * 100).round(1) : nil
      }
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
