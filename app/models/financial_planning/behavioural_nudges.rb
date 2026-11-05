# A small coaching layer over the planning page. These are observations the
# household can act on, not scores and not orders: each names a tension the
# numbers already show and links the user back to the card that explains it.
#
# Two rules only, deliberately:
#
#   * cash beyond the buffer target is not doing a job -- an observation, never
#     a command to invest it;
#   * carrying expensive debt while holding investments is a tension, because
#     clearing high-interest debt is a guaranteed return while investing is not.
#
# Judgement-heavy nudges (lifestyle inflation, windfall rules) need definitions
# the app does not yet own, so they are not invented here.
class FinancialPlanning::BehaviouralNudges
  # How far past the buffer target counts as "more than a cushion". Two or three
  # months of extra cushion is reasonable; this flags the clearly idle excess.
  IDLE_CASH_MONTHS_OVER = 3

  # Spending may outpace income by a few percent without meaning anything (a
  # one-off repair, a new baby). This flags a gap of more than five percentage
  # points over a full year, which is a trend rather than noise.
  LIFESTYLE_GAP_PCT = 5

  EXPENSE_HISTORY_MONTHS = 12

  attr_reader :family, :user

  def initialize(family, user: nil, emergency_fund: nil, debt_summary: nil, allocation: nil, income_statement: nil)
    @family = family
    @user = user || Current.user
    @emergency_fund = emergency_fund
    @debt_summary = debt_summary
    @allocation = allocation
    @income_statement = income_statement
  end

  def idle_cash?
    months = emergency_fund.months
    return false if months.nil?

    months > emergency_fund.target_months + IDLE_CASH_MONTHS_OVER
  end

  # The amount above the household's own target, not above the six-month
  # default: the target is the household's decision.
  def idle_cash_amount
    return 0 unless idle_cash?

    [ emergency_fund.liquid_balance - emergency_fund.target_amount, 0 ].max.round(2)
  end

  def idle_cash_excess_money
    Money.new(idle_cash_amount, currency)
  end

  def expensive_debt_while_investing?
    debt_summary.high_interest_debt.positive? && allocation.invested_total.positive?
  end

  def expensive_debt_amount_money
    debt_summary.high_interest_debt_money
  end

  # Trailing-year spending versus income growth. Deliberately compares two
  # equal six-month windows so a seasonal month cannot swing it.
  def recent_monthly_expenses
    @recent_monthly_expenses ||= monthly_average(expense_total(recent_window), 6)
  end

  def prior_monthly_expenses
    @prior_monthly_expenses ||= monthly_average(expense_total(prior_window), 6)
  end

  def recent_monthly_income
    @recent_monthly_income ||= monthly_average(income_total(recent_window), 6)
  end

  def prior_monthly_income
    @prior_monthly_income ||= monthly_average(income_total(prior_window), 6)
  end

  def expense_growth_pct
    recent = recent_monthly_expenses.to_d
    prior = prior_monthly_expenses.to_d
    return nil unless prior.positive?

    (((recent - prior) / prior) * 100).round(1)
  end

  def income_growth_pct
    recent = recent_monthly_income.to_d
    prior = prior_monthly_income.to_d
    return nil unless prior.positive?

    (((recent - prior) / prior) * 100).round(1)
  end

  def lifestyle_inflation?
    return false if expense_growth_pct.nil? || income_growth_pct.nil?

    expense_growth_pct.positive? && expense_growth_pct > income_growth_pct + LIFESTYLE_GAP_PCT
  end

  def expense_increase_money
    increase = [ recent_monthly_expenses.to_d - prior_monthly_expenses.to_d, 0 ].max
    Money.new(increase.round(2), currency)
  end

  def any?
    idle_cash? || expensive_debt_while_investing? || lifestyle_inflation?
  end

  private
    def currency
      family.currency
    end

    def recent_window
      @recent_window ||= Period.custom(
        start_date: Date.current.beginning_of_month - 5.months,
        end_date: Date.current.end_of_month
      )
    end

    def prior_window
      @prior_window ||= Period.custom(
        start_date: Date.current.beginning_of_month - 11.months,
        end_date: Date.current.beginning_of_month - 6.months - 1.day
      )
    end

    def expense_total(period)
      income_statement.totals_for(period).expense_money.amount
    end

    def income_total(period)
      income_statement.totals_for(period).income_money.amount
    end

    def monthly_average(total, months)
      (total.to_d / months).round(2)
    end

    def income_statement
      @income_statement ||= family.income_statement(user: user)
    end

    def emergency_fund
      @emergency_fund ||= FinancialPlanning::EmergencyFund.new(family, user: user)
    end

    def debt_summary
      @debt_summary ||= FinancialPlanning::DebtSummary.new(family, user: user)
    end

    def allocation
      @allocation ||= FinancialPlanning::PortfolioAllocation.new(family, user: user)
    end
end
