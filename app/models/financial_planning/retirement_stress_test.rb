# A Monte Carlo stress test for the retirement plan: not one projected line,
# but the share of plausible market paths in which the money lasts.
#
# Model, stated plainly:
#
#   * accumulation runs monthly from today to the household's retirement age,
#     adding the trailing average monthly saving and sampling an annual return
#     of mean = the planning setting's growth rate, standard deviation 12%.
#   * retirement runs thirty annual withdrawals, starting from today's spending
#     inflated to the retirement date, with withdrawals rising with inflation.
#   * the "bad decade" scenario keeps the same accumulation but forces every
#     return in the first ten retirement years to -10%.
#   * returns are independent draws; real markets are not that kind, so this is
#     a shape of the risk, not a prediction.
#
# It says nothing when the household has no age (the "self" member's date of
# birth) or no recorded spending: a probability invented from missing inputs
# would be worse than silence.
class FinancialPlanning::RetirementStressTest
  TRIALS = 500
  VOLATILITY_PCT = 12.0
  RETIREMENT_YEARS = 30
  BAD_DECADE_YEARS = 10
  BAD_DECADE_RETURN_PCT = -10.0
  INDIAN_INFLATION_PCT = 6.0
  DEFAULT_INFLATION_PCT = 3.0

  Result = Data.define(:success_percent, :bad_decade_percent, :median_corpus) do
    def median_corpus_money(currency)
      Money.new(median_corpus.round(2), currency)
    end
  end

  attr_reader :family, :user, :trials, :seed

  def initialize(family, user: nil, trials: TRIALS, seed: nil, fire_progress: nil, savings_rate: nil, balance_sheet: nil)
    @family = family
    @user = user || Current.user
    @trials = trials
    @seed = seed
    @fire_progress = fire_progress
    @savings_rate = savings_rate
    @balance_sheet = balance_sheet
  end

  def available?
    current_age.present? && annual_expenses.positive? && retirement_age.present?
  end

  def current_age
    @current_age ||= self_member&.age
  end

  def retirement_age
    planning_setting.retirement_age
  end

  def current_net_worth
    @current_net_worth ||= balance_sheet.net_worth.to_f
  end

  def annual_expenses
    @annual_expenses ||= fire_progress.average_annual_expenses.to_f
  end

  def annual_savings
    @annual_savings ||= [ savings_rate.average_monthly_savings.to_f * 12, 0 ].max
  end

  def mean_return_pct
    planning_setting.annual_growth_rate_pct.to_f
  end

  def inflation_pct
    indian? ? INDIAN_INFLATION_PCT : DEFAULT_INFLATION_PCT
  end

  def years_to_retirement
    [ retirement_age - current_age, 0 ].max
  end

  def result
    return nil unless available?

    @result ||= simulate
  end

  private
    def indian?
      family.country.to_s.upcase == "IN"
    end

    def self_member
      @self_member ||= family.household_members.where(relationship: "self").order(:created_at).first
    end

    def planning_setting
      @planning_setting ||= family.planning_setting || family.build_planning_setting
    end

    def balance_sheet
      @balance_sheet ||= family.balance_sheet(user: user)
    end

    def fire_progress
      @fire_progress ||= FinancialPlanning::FireProgress.new(family, user: user)
    end

    def savings_rate
      @savings_rate ||= FinancialPlanning::SavingsRate.new(
        family, period: Period.current_month_for(family), user: user
      )
    end

    def simulate
      rng = Random.new(seed || Random.new_seed)
      successes = 0
      bad_decade_successes = 0
      corpora = []

      trials.times do
        corpus = project_to_retirement(rng)
        corpora << corpus
        successes += 1 if survives_retirement?(corpus, rng, bad_decade: false)
        bad_decade_successes += 1 if survives_retirement?(corpus, rng, bad_decade: true)
      end

      Result.new(
        success_percent: percent(successes),
        bad_decade_percent: percent(bad_decade_successes),
        median_corpus: median(corpora)
      )
    end

    def project_to_retirement(rng)
      balance = current_net_worth
      contribution = annual_savings / 12.0

      (years_to_retirement * 12).times do
        balance += contribution
        balance *= 1 + (sample_return(rng, monthly: true) / 100.0)
        balance = 0 if balance.negative?
      end

      balance
    end

    def survives_retirement?(corpus, rng, bad_decade:)
      balance = corpus
      withdrawal = annual_expenses * ((1 + (inflation_pct / 100.0)) ** years_to_retirement)

      RETIREMENT_YEARS.times do |year|
        balance -= withdrawal
        return false if balance <= 0

        rate = if bad_decade && year < BAD_DECADE_YEARS
          BAD_DECADE_RETURN_PCT
        else
          sample_return(rng)
        end
        balance *= 1 + (rate / 100.0)
        withdrawal *= 1 + (inflation_pct / 100.0)
      end

      true
    end

    def sample_return(rng, monthly: false)
      mean = monthly ? mean_return_pct / 12.0 : mean_return_pct
      deviation = monthly ? VOLATILITY_PCT / Math.sqrt(12) : VOLATILITY_PCT
      u1 = [ rng.rand, 1e-12 ].max
      u2 = rng.rand
      z = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math::PI * u2)
      mean + (deviation * z)
    end

    def percent(count)
      (count.to_f / trials * 100).round
    end

    def median(values)
      sorted = values.sort
      return 0.0 if sorted.empty?

      middle = sorted.size / 2
      if sorted.size.odd?
        sorted[middle]
      else
        (sorted[middle - 1] + sorted[middle]) / 2.0
      end
    end
end
