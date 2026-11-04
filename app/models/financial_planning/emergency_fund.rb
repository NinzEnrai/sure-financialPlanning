# Emergency fund coverage: how many months of current spending the family's
# cash on hand would cover if income stopped.
#
# The long-standing guidance is three to six months of essential expenses. Sure
# cannot tell essential spending from discretionary, so this uses the same
# trailing-twelve-month average as the FIRE target: the number the family would
# actually have to replace, and a deliberately conservative stand-in for
# "essentials". Only depository (bank/cash) accounts count as the buffer --
# brokerage holdings are not money you can spend in an emergency without selling
# at whatever the market happens to be paying that day.
class FinancialPlanning::EmergencyFund
  TARGET_MONTHS = 6
  MINIMUM_MONTHS = 3
  EXPENSE_HISTORY_MONTHS = 12

  attr_reader :family, :user

  def initialize(family, user: nil)
    @family = family
    @user = user || Current.user
  end

  # Bank and cash accounts the user can see, minus anything deliberately kept
  # out of reports. Provider-linked accounts are included: a bank balance is
  # spendable whether it was typed in or imported.
  def liquid_accounts
    @liquid_accounts ||= family.accounts.visible
      .accessible_by(user)
      .select { |account| account.accountable_type == "Depository" && !account.exclude_from_reports? }
  end

  def liquid_balance
    @liquid_balance ||= liquid_accounts.sum { |account| converted_balance_for(account) }.round(2)
  end

  def liquid_balance_money
    Money.new(liquid_balance, currency)
  end

  # Averaged over the trailing year rather than the current month, so a single
  # large annual bill does not make the family look temporarily safe (or
  # temporarily ruined) when the milestone is a yearly one.
  def monthly_expenses
    @monthly_expenses ||= begin
      total = trailing_expenses
      total.positive? ? (total / EXPENSE_HISTORY_MONTHS).round(2) : BigDecimal("0")
    end
  end

  def monthly_expenses_money
    Money.new(monthly_expenses, currency)
  end

  # Nil -- not zero -- when there is no spending history to divide by: a family
  # with no recorded expenses has not "run out of buffer", it has nothing to
  # measure yet.
  def months
    return nil unless monthly_expenses.positive?

    @months ||= (liquid_balance / monthly_expenses).round(1).to_f
  end

  def target_months
    TARGET_MONTHS
  end

  def target_amount
    @target_amount ||= (monthly_expenses * TARGET_MONTHS).round(2)
  end

  def target_amount_money
    Money.new(target_amount, currency)
  end

  # Share of the six-month target already covered. Uncapped so the view can say
  # "112% of the aim"; #bar_percent is the capped value the bar needs.
  def coverage_percent
    return nil unless target_amount.positive?

    @coverage_percent ||= ((liquid_balance / target_amount) * 100).round(1)
  end

  def bar_percent
    percent = coverage_percent
    return nil if percent.nil?

    [ [ percent.to_f, 0 ].max, 100 ].min
  end

  def shortfall
    return 0 if months.nil?

    [ target_amount - liquid_balance, 0 ].max.round(2)
  end

  def shortfall_money
    Money.new(shortfall, currency)
  end

  def surplus
    return 0 if months.nil?

    [ liquid_balance - target_amount, 0 ].max.round(2)
  end

  def surplus_money
    Money.new(surplus, currency)
  end

  def status
    return :unknown if months.nil?
    return :funded if months >= TARGET_MONTHS
    return :building if months >= MINIMUM_MONTHS

    :critical
  end

  def funded?
    status == :funded
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

    def trailing_expenses
      income_statement.totals_for(history_period).expense_money.amount
    end

    # Same batch lookup the balance sheet uses: one rate per foreign currency
    # present, rather than asking per account. Missing rates fall back to the
    # stored 1.0 with a logged warning (see ExchangeRate#rates_for).
    def exchange_rates
      @exchange_rates ||= begin
        foreign = liquid_accounts.filter_map { |account| account.currency if account.currency != currency }.uniq
        foreign.empty? ? {} : ExchangeRate.rates_for(foreign, to: currency, date: Date.current)
      end
    end

    def converted_balance_for(account)
      return account.balance if account.currency == currency

      account.balance * (exchange_rates[account.currency] || 1)
    end
end
