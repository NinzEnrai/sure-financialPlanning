# The artefact a planner hands a household once a year: what changed, what is
# protected, whether the goals are moving, and what to do next.
#
# Everything here is assembled from the same POROs the planning page uses, so
# the review cannot disagree with the dashboard. Net-worth movement comes from
# the balance sheet's own series (the same one the reports chart reads).
class FinancialPlanning::AnnualReview
  REVIEW_MONTHS = 12

  attr_reader :family, :user

  def initialize(family, user: nil)
    @family = family
    @user = user || Current.user
  end

  def period
    @period ||= Period.custom(
      start_date: Date.current.beginning_of_month - (REVIEW_MONTHS - 1).months,
      end_date: Date.current.end_of_month
    )
  end

  def period_label
    "#{I18n.l(period.start_date, format: "%b %Y")} – #{I18n.l(period.end_date, format: "%b %Y")}"
  end

  def last_reviewed_on
    planning_setting.last_reviewed_on
  end

  # A review is due when it has never been done, or when the last one is more
  # than a year old. A stale review is a nudge, not a failure.
  def review_due?
    last_reviewed_on.nil? || last_reviewed_on < 1.year.ago.to_date
  end

  def net_worth_now
    @net_worth_now ||= balance_sheet.net_worth
  end

  def net_worth_now_money
    Money.new(net_worth_now, currency)
  end

  def net_worth_start
    return @net_worth_start if defined?(@net_worth_start)

    first = net_worth_series.values.first
    @net_worth_start = first ? first.value.amount : net_worth_now
  end

  def net_worth_start_money
    Money.new(net_worth_start, currency)
  end

  def net_worth_change
    @net_worth_change ||= (net_worth_now - net_worth_start).round(2)
  end

  def net_worth_change_money
    Money.new(net_worth_change, currency)
  end

  def net_worth_change_percent
    return nil unless net_worth_start.positive?

    @net_worth_change_percent ||= ((net_worth_change / net_worth_start) * 100).round(1)
  end

  def savings_rate
    @savings_rate ||= FinancialPlanning::SavingsRate.new(family, period: period, user: user)
  end

  def savings_rate_percent
    @savings_rate_percent ||= savings_rate.total_percent
  end

  def savings_rate_money
    savings_rate.savings_money
  end

  def income_money
    savings_rate.income_money
  end

  def expenses_money
    savings_rate.expenses_money
  end

  def investment_totals
    @investment_totals ||= investment_statement.totals(period: period)
  end

  def contributions_money
    investment_totals.contributions
  end

  def withdrawals_money
    investment_totals.withdrawals
  end

  def investment_income_money
    Money.new(investment_totals.dividends.amount + investment_totals.interest.amount, currency)
  end

  def goal_summary
    @goal_summary ||= Goal.summary_for(
      Goal.prepared_for(family, scope: family.goals.where(state: "active")),
      currency: currency
    )
  end

  def goals_count
    @goals_count ||= family.goals.where(state: "active").count
  end

  def protection
    @protection ||= FinancialPlanning::ProtectionGap.new(family, user: user)
  end

  def scorecard
    @scorecard ||= FinancialPlanning::HealthScorecard.new(family, user: user)
  end

  def tax_readiness
    @tax_readiness ||= FinancialPlanning::TaxReadiness.new(family, user: user)
  end

  # The rows worth carrying into next year, in advisor order. Unknown checks
  # are excluded: they are data gaps, not actions the household can take today.
  def priorities
    @priorities ||= scorecard.checks.select { |check| %i[attention watch].include?(check.status) }
  end

  private
    def currency
      family.currency
    end

    def planning_setting
      @planning_setting ||= family.planning_setting || family.build_planning_setting
    end

    def balance_sheet
      @balance_sheet ||= family.balance_sheet(user: user)
    end

    def net_worth_series
      @net_worth_series ||= balance_sheet.net_worth_series(period: period)
    end

    def investment_statement
      @investment_statement ||= family.investment_statement(user: user)
    end
end
