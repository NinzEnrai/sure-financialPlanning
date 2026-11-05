# Can this household afford all of its goals at once? The goals index shows one
# goal at a time; this rolls the dated ones up into the monthly number the
# household has to keep saving, compares it with the pace it is actually
# saving, and reports the gap.
#
# All per-goal maths comes from Goal itself -- monthly_target_amount, pace,
# status and behind_pace? -- so the card cannot disagree with the goals page.
# Goals in another currency are listed but left out of the totals, because
# adding rupees to dollars is the one arithmetic that is always wrong.
class FinancialPlanning::GoalFunding
  Row = Data.define(:goal, :required_monthly, :pace, :gap, :priority, :inflated) do
    def priority_rank
      Goal::PRIORITY_RANK.fetch(priority, Goal::PRIORITY_RANK.fetch(Goal::DEFAULT_PRIORITY))
    end
  end

  attr_reader :family, :user

  def initialize(family, user: nil, goals: nil)
    @family = family
    @user = user || Current.user
    @goals = goals
  end

  def goals
    @goals ||= Goal.active_prepared_for(family)
  end

  def empty?
    goals.empty?
  end

  # Only goals with a deadline have a monthly requirement. An open-ended goal
  # (or a maintained reserve) has no pace to be behind, so it is listed but not
  # summed.
  def rows
    @rows ||= goals.select { |goal| goal.target_date.present? && !goal.paused? && !goal.maintained? && goal.currency == currency }
      .map do |goal|
        # The plan uses the future-rupee figure when the goal carries an
        # inflation assumption; the goals page keeps the nominal target.
        required = goal.inflation_adjusted_monthly_target_amount.to_d
        # A negative pace means money left the linked accounts over the window.
        # That is not a contribution, so the plan treats it as no pace at all
        # rather than subtracting it from the requirement.
        pace = [ goal.pace.to_d, 0 ].max
        Row.new(
          goal: goal,
          required_monthly: required,
          pace: pace,
          gap: [ required - pace, 0 ].max,
          priority: goal.priority.presence || Goal::DEFAULT_PRIORITY,
          inflated: goal.inflation_pct.present?
        )
      end
      .sort_by { |row| [ row.priority_rank, -row.gap ] }
  end

  def high_priority_count
    rows.count { |row| row.priority == "high" }
  end

  def dated_goals
    rows.map(&:goal)
  end

  def behind_count
    goals.count(&:behind_pace?)
  end

  def total_required_monthly
    rows.sum(&:required_monthly).round(2)
  end

  def total_required_monthly_money
    Money.new(total_required_monthly, currency)
  end

  def total_pace
    rows.sum(&:pace).round(2)
  end

  def total_pace_money
    Money.new(total_pace, currency)
  end

  # The monthly shortfall across every dated goal. Zero means the current pace
  # covers them all -- which is a genuinely good result, not a missing input.
  def total_gap
    rows.sum(&:gap).round(2)
  end

  def total_gap_money
    Money.new(total_gap, currency)
  end

  def on_track?
    total_gap.zero?
  end

  private
    def currency
      family.currency
    end
end
