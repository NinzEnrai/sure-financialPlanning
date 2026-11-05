# The first page of a financial plan: the checks a planner runs before
# recommending anything, each with an honest status and one thing to do next.
#
# This is deliberately not a score out of 100. A number hides which input is
# missing and invites a household to optimise the number instead of the
# problem. Each check therefore reports one of four states:
#
#   :good      the figure is inside the usual range
#   :watch     outside the range but not urgent
#   :attention clearly outside the range
#   :unknown   the app cannot compute it yet (and says what is missing)
#
# The thresholds are practitioner heuristics, not regulation, and each check's
# detail line says what it measures. The underlying figures live in the existing
# POROs (SavingsRate, EmergencyFund, DebtSummary, Goal) so the card can never
# disagree with the card that computes the same number.
class FinancialPlanning::HealthScorecard
  Check = Data.define(:key, :status, :value, :unit, :total)

  # Advisor order of redress: protect against the shock first, then kill the
  # most expensive debt, then widen the margin, then raise the saving pace.
  ACTION_PRIORITY = %i[emergency_fund high_interest_debt debt_to_income savings_rate goals].freeze

  attr_reader :family, :user

  def initialize(family, user: nil, savings_rate: nil, emergency_fund: nil, debt_summary: nil, protection_gap: nil, goals: nil)
    @family = family
    @user = user || Current.user
    @savings_rate = savings_rate
    @emergency_fund = emergency_fund
    @debt_summary = debt_summary
    @protection_gap = protection_gap
    @active_goals = goals
  end

  def checks
    @checks ||= [
      savings_rate_check,
      emergency_fund_check,
      debt_to_income_check,
      high_interest_check,
      goals_check,
      protection_check
    ]
  end

  def good_count
    checks.count { |check| check.status == :good }
  end

  def known_count
    checks.count { |check| check.status != :unknown }
  end

  # The one row the page should point at. Attention beats watch, and ties are
  # broken by ACTION_PRIORITY rather than by the visual order of the rows.
  def next_action_key
    indexed = checks.index_by(&:key)

    ACTION_PRIORITY.each do |key|
      check = indexed[key]
      return key if check && %i[attention watch].include?(check.status)
    end

    nil
  end

  private
    def savings_rate_check
      rate = savings_rate.trailing_rate(months: 6)
      status = if rate.nil?
        :unknown
      elsif rate >= 20
        :good
      elsif rate >= 10
        :watch
      else
        :attention
      end

      Check.new(key: :savings_rate, status: status, value: rate, unit: :percent, total: nil)
    end

    def emergency_fund_check
      months = emergency_fund.months
      status = if months.nil?
        :unknown
      elsif months >= emergency_fund.target_months
        :good
      elsif months >= FinancialPlanning::EmergencyFund::MINIMUM_MONTHS
        :watch
      else
        :attention
      end

      Check.new(key: :emergency_fund, status: status, value: months, unit: :months, total: nil)
    end

    def debt_to_income_check
      return Check.new(key: :debt_to_income, status: :good, value: 0.0, unit: :percent, total: nil) if debt_summary.debts.empty?

      dti = debt_summary.dti_percent
      status = if dti.nil?
        :unknown
      elsif dti <= 36
        :good
      elsif dti <= 50
        :watch
      else
        :attention
      end

      Check.new(key: :debt_to_income, status: status, value: dti, unit: :percent, total: nil)
    end

    def high_interest_check
      return Check.new(key: :high_interest_debt, status: :good, value: 0, unit: :money, total: nil) if debt_summary.debts.empty?
      return Check.new(key: :high_interest_debt, status: :unknown, value: nil, unit: :money, total: nil) unless debt_summary.debts.any?(&:rate?)

      status = debt_summary.high_interest? ? :attention : :good
      Check.new(key: :high_interest_debt, status: status, value: debt_summary.high_interest_debt, unit: :money, total: nil)
    end

    def goals_check
      # A goal with no date has no pace to be behind, and a maintained reserve
      # is a floor rather than a finish line; both are excluded from the check.
      dated = active_goals.select { |goal| goal.target_date.present? && !goal.maintained? }
      return Check.new(key: :goals, status: :unknown, value: nil, unit: :goals, total: 0) if dated.empty?

      behind = dated.count(&:behind_pace?)
      status = behind.positive? ? :attention : :good
      Check.new(key: :goals, status: status, value: dated.size - behind, unit: :goals, total: dated.size)
    end

    # Checkable only once the household has recorded cover and income to size it
    # against. Until then it stays an honest unknown rather than a green light
    # nobody earned.
    def protection_check
      gap = protection_gap
      return Check.new(key: :protection, status: :unknown, value: nil, unit: :none, total: nil) if gap.empty?
      return Check.new(key: :protection, status: :unknown, value: nil, unit: :none, total: nil) if gap.annual_income.nil?

      status = gap.life_cover_gap.positive? ? :attention : :good
      Check.new(key: :protection, status: status, value: gap.life_cover_total, unit: :money, total: nil)
    end

    def savings_rate
      @savings_rate ||= FinancialPlanning::SavingsRate.new(
        family, period: Period.current_month_for(family), user: user
      )
    end

    def emergency_fund
      @emergency_fund ||= FinancialPlanning::EmergencyFund.new(family, user: user)
    end

    def debt_summary
      @debt_summary ||= FinancialPlanning::DebtSummary.new(family, user: user)
    end

    def protection_gap
      @protection_gap ||= FinancialPlanning::ProtectionGap.new(family, user: user)
    end

    def active_goals
      @active_goals ||= Goal.prepared_for(family, scope: family.goals.where(state: "active"))
    end
end
