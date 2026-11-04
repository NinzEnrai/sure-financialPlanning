# The protection question a planner asks before any investing question: if the
# earning member died or was hospitalised tomorrow, what would the household
# actually get?
#
# Compute what is checkable. Recorded life cover is compared with a rough guide
# of ten times recorded annual income -- a practitioner heuristic, not a
# regulation, and the card says so. Health cover is reported as a total rather
# than a pass/fail because a "right" number depends on city, family size and
# employer cover, none of which Sure knows. When no policies are recorded the
# answer is :unknown, not a reassuring zero.
class FinancialPlanning::ProtectionGap
  # A term-cover rule of thumb: enough to replace the earner's income for about
  # a decade. Deliberately conservative and stated as a guide on screen.
  INCOME_MULTIPLE = 10

  EXPENSE_HISTORY_MONTHS = 12

  # Premiums are only affordable relative to income. Under 5% is comfortable;
  # 5-10% is worth reviewing; above 10% the household is likely over-insured
  # for its income. Practitioner heuristics, stated as such on screen.
  AFFORDABILITY_COMFORT_PCT = 5
  AFFORDABILITY_WATCH_PCT = 10

  attr_reader :family, :user

  def initialize(family, user: nil)
    @family = family
    @user = user || Current.user
  end

  def policies
    @policies ||= family.insurance_policies.to_a
  end

  def empty?
    policies.empty?
  end

  def life_policies
    policies.select(&:life?)
  end

  def health_policies
    policies.select(&:health?)
  end

  def life_cover_total
    @life_cover_total ||= life_policies.sum { |policy| policy.cover_amount.to_d }.round(2)
  end

  def life_cover_total_money
    Money.new(life_cover_total, currency)
  end

  def health_cover_total
    @health_cover_total ||= health_policies.sum { |policy| policy.cover_amount.to_d }.round(2)
  end

  def health_cover_total_money
    Money.new(health_cover_total, currency)
  end

  def annual_premium_total
    @annual_premium_total ||= policies.sum { |policy| policy.annual_premium }.round(2)
  end

  def annual_premium_total_money
    Money.new(annual_premium_total, currency)
  end

  # Recorded income over the trailing year. Nil when the household has not
  # recorded any -- which makes every ratio below unknowable rather than zero.
  def annual_income
    return @annual_income if defined?(@annual_income)

    total = income_statement.totals_for(history_period).income_money.amount
    @annual_income = total.positive? ? total.round(2) : nil
  end

  def recommended_life_cover
    return nil if annual_income.nil?

    @recommended_life_cover ||= (annual_income * INCOME_MULTIPLE).round(2)
  end

  def life_cover_gap
    return nil if recommended_life_cover.nil?

    @life_cover_gap ||= [ recommended_life_cover - life_cover_total, 0 ].max.round(2)
  end

  def dependants_count
    @dependants_count ||= family.household_members.where(dependent: true).count
  end

  def members_count
    @members_count ||= family.household_members.count
  end

  def renewing_soon
    @renewing_soon ||= policies.select(&:renewing_soon?)
  end

  def health_recorded?
    health_policies.any?
  end

  # Annual premium as a share of recorded income. Nil without income -- a
  # premium has no affordability without something to afford it from.
  def premium_affordability_percent
    return @premium_affordability_percent if defined?(@premium_affordability_percent)
    return @premium_affordability_percent = nil if annual_income.nil? || annual_income.zero?

    @premium_affordability_percent = ((annual_premium_total / annual_income) * 100).round(1)
  end

  def premium_affordability_status
    return :unknown if premium_affordability_percent.nil?
    return :attention if premium_affordability_percent > AFFORDABILITY_WATCH_PCT
    return :watch if premium_affordability_percent > AFFORDABILITY_COMFORT_PCT

    :good
  end

  def status
    return :unknown if empty? || annual_income.nil?

    life_cover_gap.positive? ? :attention : :good
  end

  private
    def currency
      family.currency
    end

    def income_statement
      @income_statement ||= family.income_statement(user: user)
    end

    def history_period
      Period.custom(
        start_date: Date.current.beginning_of_month - (EXPENSE_HISTORY_MONTHS - 1).months,
        end_date: Date.current.end_of_month
      )
    end
end
