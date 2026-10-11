# frozen_string_literal: true

module FinancialPlanning
  # For a given FinancialGoal, computes the monthly contribution required to hit the target
  # by the target date, given an assumed rate of return (future-value-of-annuity-due math).
  class GoalProjector
    def initialize(goal, annual_return_pct: nil)
      @goal = goal
      @annual_return_pct = annual_return_pct || goal.family.planning_setting&.expected_annual_return_pct || 10.0
    end

    # Monthly contribution needed so that:
    #   current_amount * (1+r)^n + contribution * [((1+r)^n - 1) / r] * (1+r) = target_amount
    # (annuity-due: contributions assumed at the start of each month)
    def required_monthly_contribution
      n = goal.months_remaining
      return nil if n.zero?

      r = monthly_rate
      fv_current = goal.current_amount.to_f * ((1 + r)**n)
      remaining_fv_needed = goal.target_amount.to_f - fv_current

      return 0.0 if remaining_fv_needed <= 0 # goal already funded given current trajectory

      if r.zero?
        (remaining_fv_needed / n).round(2)
      else
        annuity_factor = (((1 + r)**n - 1) / r) * (1 + r)
        (remaining_fv_needed / annuity_factor).round(2)
      end
    end

    # Projected balance at target_date if the family contributes a given monthly amount
    # (defaults to the required contribution, i.e. should land exactly on target_amount --
    # useful for "what if I only save X/month instead" what-if scenarios).
    def projected_balance(monthly_contribution: nil)
      n = goal.months_remaining
      r = monthly_rate
      contribution = monthly_contribution || required_monthly_contribution || 0

      fv_current = goal.current_amount.to_f * ((1 + r)**n)
      fv_contributions =
        if r.zero?
          contribution * n
        else
          contribution * (((1 + r)**n - 1) / r) * (1 + r)
        end

      (fv_current + fv_contributions).round(2)
    end

    private

    attr_reader :goal, :annual_return_pct

    def monthly_rate
      ((1 + annual_return_pct / 100.0)**(1.0 / 12)) - 1
    end
  end
end
