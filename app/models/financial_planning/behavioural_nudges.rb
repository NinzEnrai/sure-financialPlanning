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

  attr_reader :family, :user

  def initialize(family, user: nil)
    @family = family
    @user = user || Current.user
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

  def any?
    idle_cash? || expensive_debt_while_investing?
  end

  private
    def currency
      family.currency
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
