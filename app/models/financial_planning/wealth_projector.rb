# Year-by-year net worth projection: the opening balance compounded at the
# configured growth rate, plus the monthly savings contribution each year.
#
# Contributions are applied at the end of each year rather than compounded
# alongside the balance, so the curve doesn't imply the year's savings were
# invested for a full year. Deliberately simple -- it answers "roughly when",
# not "exactly how much".
class FinancialPlanning::WealthProjector
  DEFAULT_YEARS = 10
  SAVINGS_HISTORY_MONTHS = 6

  Point = Data.define(:year, :date, :balance) do
    def balance_money(currency)
      Money.new(balance, currency)
    end
  end

  attr_reader :family, :years, :opening_balance, :monthly_contribution

  def initialize(family, user: nil, years: DEFAULT_YEARS, opening_balance: nil, monthly_contribution: nil, growth_rate: nil)
    @family = family
    @user = user || Current.user
    @years = years
    @opening_balance = opening_balance
    @monthly_contribution = monthly_contribution
    @growth_rate = growth_rate
  end

  def opening_balance
    @opening_balance ||= balance_sheet.net_worth
  end

  def monthly_contribution
    @monthly_contribution ||= savings_rate.average_monthly_savings(months: SAVINGS_HISTORY_MONTHS)
  end

  # Trailing 6-month income-weighted savings rate, the input the widget shows
  # above the chart so the projection's contribution assumption is visible
  # rather than implicit.
  def savings_rate_percent
    savings_rate.trailing_rate(months: SAVINGS_HISTORY_MONTHS)
  end

  def growth_rate_pct
    # Through #growth_rate rather than planning_setting directly, so the
    # calculator's override is reflected in the displayed rate too -- not just in
    # the projected balances.
    (growth_rate * 100).round(2)
  end

  # Year 0 is today, so the chart starts from the net worth the family actually
  # has rather than jumping to a year-end figure.
  def points
    @points ||= (0..years).map do |offset|
      Point.new(
        year: Date.current.year + offset,
        date: Date.current.beginning_of_year.advance(years: offset),
        balance: projected_balance(offset)
      )
    end
  end

  def final_balance
    points.last.balance
  end

  # Currency-wrapped accessors for the views. The projector works in bare
  # numbers so the maths stays exact; formatting is the view's job.
  def final_balance_money(currency = family.currency)
    Money.new(final_balance, currency)
  end

  def monthly_contribution_money(currency = family.currency)
    Money.new(monthly_contribution, currency)
  end

  def months_to_target(target)
    return 0 if opening_balance >= target
    # No contribution means there's no saving behaviour to project; growth
    # alone reaching a target would answer a question nobody asked.
    return nil unless monthly_contribution.positive?

    # Inverts the same recurrence #projected_balance draws:
    #   B(n) = opening(1+g)^n + annual((1+g)^n - 1)/g = target
    # rearranged to  (1+g)^n = (target*g + annual) / (opening*g + annual).
    # The gap therefore closes geometrically, not at a flat monthly rate.
    annual = monthly_contribution * 12
    ratio = ((target * growth_rate) + annual) / ((opening_balance * growth_rate) + annual)

    return nil unless ratio.finite? && ratio > 1

    years_needed = Math.log(ratio) / Math.log(1 + growth_rate)
    return nil unless years_needed.finite? && years_needed.positive?

    (years_needed * 12).ceil
  end

  # Balance the projection reaches +months+ from now, at the current savings
  # pace and growth rate. Coast FIRE needs a balance at a *date* rather than a
  # date at which the number is hit, and the annual `points` series can't answer
  # "what will this be at age 42".
  def balance_after_months(months)
    projected_balance(months / 12.0)
  end

  def balance_after_months_money(months, currency = family.currency)
    Money.new(balance_after_months(months), currency)
  end

  private
    attr_reader :user

    # One instance for the whole object: #monthly_contribution and
    # #savings_rate_percent read the same trailing window, and each call would
    # otherwise re-run it.
    def savings_rate
      @savings_rate ||= FinancialPlanning::SavingsRate.new(
        family, period: Period.current_month_for(family), user: user
      )
    end

    # A caller-supplied rate wins, so the compound calculator can explore a rate
    # without persisting it. Falls back to the family's saved assumption.
    def growth_rate
      @growth_rate || planning_setting.growth_rate
    end

    def balance_sheet
      @balance_sheet ||= family.balance_sheet(user: user)
    end

    def planning_setting
      @planning_setting ||= family.planning_setting || family.build_planning_setting
    end

    # At offset 0 the closed form collapses to exactly the opening balance
    # ((1+g)^0 == 1, so the contribution term is zero) — no special case
    # needed, and adding one previously reported year 0 as zero.
    def projected_balance(offset)
      annual = monthly_contribution * 12
      factor = (1 + growth_rate)**offset

      compounded = opening_balance * factor
      # The annuity term is a division by g, so at a zero growth rate it is 0/0
      # rather than a number. Reachable: the compound calculator's growth slider
      # bottoms out at 0%, and the NaN would silently blank the whole chart.
      contributions = if growth_rate.zero?
        annual * offset
      else
        annual * ((factor - 1) / growth_rate)
      end

      (compounded + contributions).round(2)
    end
end
