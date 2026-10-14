# FIRE progress: how far the family's current net worth has travelled toward the
# number that would let spending continue indefinitely.
#
# Target = average annual expenses / withdrawal rate (25x at the 4% rule).
# Annual expenses are averaged over a trailing 12 months rather than taken from
# a single month, so one unusually large bill doesn't move the target.
class FinancialPlanning::FireProgress
  EXPENSE_HISTORY_MONTHS = 12

  attr_reader :family, :user

  def initialize(family, user: nil)
    @family = family
    @user = user || Current.user
  end

  def current_net_worth
    @current_net_worth ||= balance_sheet.net_worth
  end

  def current_net_worth_money
    Money.new(current_net_worth, currency)
  end

  # Averaged monthly spend over the trailing year, annualized.
  def average_annual_expenses
    @average_annual_expenses ||= (average_monthly_expenses * 12).round(2)
  end

  def average_monthly_expenses
    @average_monthly_expenses ||= begin
      monthly = trailing_expenses
      monthly.positive? ? monthly / EXPENSE_HISTORY_MONTHS : 0
    end
  end

  def average_annual_expenses_money
    Money.new(average_annual_expenses, currency)
  end

  def target
    @target ||= planning_setting.fire_target_money(average_annual_expenses).amount.to_f
  end

  def target_money
    Money.new(target, currency)
  end

  # Capped at 100 so the bar never overflows; `percent` stays uncapped because
  # "129% of FI" is a meaningful thing to tell someone.
  def percent
    return nil unless target.positive?

    ((current_net_worth / target) * 100).round(1)
  end

  def bar_percent
    [ percent || 0, 100 ].min
  end

  def remaining
    [ target - current_net_worth, 0 ].max.round(2)
  end

  def remaining_money
    Money.new(remaining, currency)
  end

  def achieved?
    target.positive? && current_net_worth >= target
  end

  # Net worth change per month at the current savings pace and the configured
  # growth rate. Nil when there is no tracking history to project from.
  def months_to_target
    return nil if remaining.zero?
    return nil unless target.positive?

    simulator.months_to_target(target)
  end

  def multiple
    planning_setting.fire_multiple
  end

  def withdrawal_rate_pct
    planning_setting.fire_withdrawal_rate_pct.to_f
  end

  # Coast FIRE is measured against a date rather than a multiple: the question is
  # not "when do I get there" but "will it be there by the year I picked".
  def coast_fire?
    planning_setting.coast_fire?
  end

  def target_year
    planning_setting.fire_target_year
  end

  # End of the target year, so a family gets all of it rather than being judged
  # against 1 January.
  def target_date
    return nil unless coast_fire? && target_year

    Date.new(target_year, 12, 31)
  end

  # Months to that date. Nil once the year has gone -- there is no horizon left
  # to measure against, and a negative month count would report a family as
  # "on track" for a date that has already passed.
  def months_until_target_date
    date = target_date
    return nil if date.nil?

    months = ((date.year - Date.current.year) * 12) + (date.month - Date.current.month)
    months.negative? ? nil : months
  end

  # What the projection says net worth will be by the target date.
  def projected_balance_at_target_date
    months = months_until_target_date
    return nil if months.nil?

    simulator.balance_after_months(months)
  end

  def projected_balance_at_target_date_money
    months = months_until_target_date
    return nil if months.nil?

    simulator.balance_after_months_money(months, currency)
  end

  # Nil when there's nothing to compare against: no target date, no horizon, or
  # no savings pace to project. The view renders a placeholder rather than
  # guessing -- "on track" against an unmeasurable date is worse than silence.
  def coast_on_track?
    projected = projected_balance_at_target_date
    return nil if projected.nil?

    projected >= target
  end

  private
    attr_reader :balance_sheet, :income_statement, :planning_setting

    def currency
      family.currency
    end

    def balance_sheet
      @balance_sheet ||= family.balance_sheet(user: user)
    end

    def income_statement
      @income_statement ||= family.income_statement(user: user)
    end

    # Average of what was actually saved each month rather than a share of
    # income, so a month that spent more than it earned doesn't silently
    # inflate the contribution used for the projection.
    def monthly_contribution
      @monthly_contribution ||= FinancialPlanning::SavingsRate.new(
        family, period: current_month_period, user: user
      ).average_monthly_savings
    end

    def current_month_period
      Period.current_month_for(family)
    end

    def planning_setting
      @planning_setting ||= family.planning_setting || family.build_planning_setting
    end

    def trailing_expenses
      period = Period.custom(
        start_date: Date.current.beginning_of_month - (EXPENSE_HISTORY_MONTHS - 1).months,
        end_date: Date.current.end_of_month
      )
      income_statement.totals_for(period).expense_money.amount
    end

    def simulator
      @simulator ||= FinancialPlanning::WealthProjector.new(
        family,
        user: user,
        opening_balance: current_net_worth,
        monthly_contribution: monthly_contribution
      )
    end
end
