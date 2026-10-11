# frozen_string_literal: true

module FinancialPlanning
  # Projects net worth growth year-by-year given current net worth, average monthly savings,
  # an expected nominal CAGR, and inflation -- and estimates years to Financial Independence
  # using the standard "FIRE number = annual expenses / safe withdrawal rate" definition.
  class FireSimulator
    FireResult = Struct.new(:years_to_fire, :fire_number, :projection, keyword_init: true)
    YearPoint = Struct.new(:year, :nominal_balance, :real_balance, keyword_init: true)

    def initialize(family, settings: nil)
      @family = family
      @settings = settings || family.planning_setting
      raise ArgumentError, "Family has no PlanningSetting" unless @settings
    end

    # current_net_worth / monthly_savings can be passed explicitly for what-if scenarios;
    # otherwise derived from the family's actual data.
    def simulate(current_net_worth: nil, monthly_savings: nil, max_years: 60)
      # Your schema has a `balances` table (accounts has_many :balances presumably, used for the
      # existing net-worth chart) -- net worth should be the latest balance snapshot summed across
      # accounts rather than a single `family.net_worth` method, unless that method already wraps
      # this query for you. Swap this line for whatever the real net-worth chart's query object is
      # once you share `app/models/account.rb` / wherever `balances` is used -- duplicating that
      # logic here would be a maintenance hazard if the two ever drift.
      net_worth = current_net_worth || family.net_worth
      monthly = monthly_savings || default_monthly_savings

      fire_number = annual_expenses * (100.0 / settings.fire_withdrawal_rate_pct)

      nominal_rate = settings.expected_annual_return_pct / 100.0
      inflation = settings.expected_inflation_pct / 100.0
      real_rate = ((1 + nominal_rate) / (1 + inflation)) - 1

      projection = []
      balance = net_worth.to_f
      years_to_fire = nil

      (0..max_years).each do |year|
        real_balance = balance / ((1 + inflation)**year)
        projection << YearPoint.new(year: Date.current.year + year, nominal_balance: balance.round(2),
                                     real_balance: real_balance.round(2))

        years_to_fire ||= year if real_balance >= fire_number

        balance = balance * (1 + nominal_rate) + (monthly * 12)
      end

      FireResult.new(years_to_fire: years_to_fire, fire_number: fire_number.round(2), projection: projection)
    end

    private

    attr_reader :family, :settings

    def annual_expenses
      settings.fire_annual_expenses.presence ||
        FinancialPlanning::SavingsRateCalculator.new(family).monthly_series(months: 12).sum { |m| m[:expenses] }
    end

    def default_monthly_savings
      FinancialPlanning::SavingsRateCalculator.new(family).rolling_rate(months: 12) ? average_monthly_savings : 0
    end

    def average_monthly_savings
      series = FinancialPlanning::SavingsRateCalculator.new(family).monthly_series(months: 12)
      series.sum { |m| m[:savings] } / series.size.to_f
    end
  end
end
