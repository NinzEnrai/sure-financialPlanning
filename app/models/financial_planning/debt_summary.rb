# Debt, measured the way a planner measures it: the total, how much of it is
# expensive, and what carrying it costs every month.
#
# Balances and interest rates come from the account's own record (CreditCard#apr,
# Loan#interest_rate). An account without a rate is still included in the total;
# it simply drops out of the weighted-average and interest-cost figures rather
# than being guessed at. Every balance is converted to the family currency with
# one batched rate lookup, the same way the balance sheet does it.
class FinancialPlanning::DebtSummary
  # Above roughly this level, paying debt down usually beats investing the same
  # rupee: credit cards in particular run at 30%+ in India. It is a label, not a
  # verdict -- the view explains it in plain language.
  HIGH_INTEREST_THRESHOLD_PCT = 10

  # Cap the simulated payoff so pathological input (a payment smaller than the
  # monthly interest) cannot spin forever: 50 years is already beyond any
  # useful plan.
  MAX_PAYOFF_MONTHS = 600

  Debt = Data.define(:account, :balance, :rate_pct, :payment, :high_interest) do
    def balance_money(currency)
      Money.new(balance, currency)
    end

    def payment_money(currency)
      return nil if payment.nil?

      Money.new(payment, currency)
    end

    def rate?
      rate_pct.present?
    end
  end

  attr_reader :family, :user

  def initialize(family, user: nil)
    @family = family
    @user = user || Current.user
  end

  # Highest rate first: the order a planner would pay them in ("avalanche"),
  # because it minimises total interest. Rate-less debts sort after rated ones.
  def debts
    @debts ||= debt_accounts.map { |account| build_debt(account) }
      .reject { |debt| debt.balance <= 0 }
      .sort_by { |debt| [ -(debt.rate_pct || 0), -debt.balance ] }
  end

  def empty?
    debts.empty?
  end

  def total_debt
    @total_debt ||= debts.sum { |debt| debt.balance }.round(2)
  end

  def total_debt_money
    Money.new(total_debt, currency)
  end

  def high_interest_debt
    @high_interest_debt ||= debts.select(&:high_interest).sum { |debt| debt.balance }.round(2)
  end

  def high_interest_debt_money
    Money.new(high_interest_debt, currency)
  end

  def high_interest?
    high_interest_debt.positive?
  end

  # Interest-rate-weighted average across the debts that record a rate. Nil
  # rather than zero when none do: a family that has not entered rates is not
  # debt-free.
  def weighted_average_rate_pct
    return @weighted_average_rate_pct if defined?(@weighted_average_rate_pct)

    rated = debts.select(&:rate?)
    rated_total = rated.sum { |debt| debt.balance }
    @weighted_average_rate_pct = if rated_total.positive?
      ((rated.sum { |debt| debt.balance * debt.rate_pct } / rated_total)).round(1)
    end
  end

  # What the balances cost per month at their stated rates -- the figure that
  # makes a credit-card balance concrete. Nil when no debt records a rate.
  def monthly_interest_cost
    return @monthly_interest_cost if defined?(@monthly_interest_cost)

    rated = debts.select(&:rate?)
    @monthly_interest_cost = if rated.any?
      (rated.sum { |debt| debt.balance * debt.rate_pct / 100 / 12 }).round(2)
    end
  end

  def monthly_interest_cost_money
    return nil if monthly_interest_cost.nil?

    Money.new(monthly_interest_cost, currency)
  end

  # The monthly bill the debt book creates: card minimum payments plus fixed
  # loan instalments. Nil when no liability records a payment at all -- an
  # unknown obligation is not zero.
  def monthly_obligation
    return @monthly_obligation if defined?(@monthly_obligation)

    payments = debts.filter_map(&:payment)
    @monthly_obligation = payments.empty? ? nil : payments.sum.round(2)
  end

  def monthly_obligation_money
    return nil if monthly_obligation.nil?

    Money.new(monthly_obligation, currency)
  end

  # Average recorded income over the same trailing year as the expense figures.
  # Deliberately not this month's income: one freelance invoice would otherwise
  # swing every ratio computed from it.
  def monthly_income
    return @monthly_income if defined?(@monthly_income)

    total = income_statement.totals_for(history_period).income_money.amount
    @monthly_income = total.positive? ? (total / 12).round(2) : nil
  end

  def dti_percent
    return @dti_percent if defined?(@dti_percent)
    return @dti_percent = nil if monthly_obligation.nil? || monthly_income.nil?

    @dti_percent = ((monthly_obligation / monthly_income) * 100).round(1)
  end

  # Share of the cards' limits currently in use. Nil when no card records an
  # available-credit figure: a utilisation computed from half the limits would
  # read as a much bigger problem than it is.
  def credit_utilization_percent
    return @credit_utilization_percent if defined?(@credit_utilization_percent)

    cards = debt_accounts.select { |account| account.accountable_type == "CreditCard" }
    return @credit_utilization_percent = nil if cards.empty?
    return @credit_utilization_percent = nil if cards.any? { |card| card.accountable.available_credit.nil? }

    balances = cards.sum { |card| converted_balance_for(card) }
    limits = cards.sum { |card| converted_balance_for(card) + converted_available_credit_for(card) }
    @credit_utilization_percent = limits.positive? ? ((balances / limits) * 100).round(1) : nil
  end

  # Paying highest rate first minimises total interest; paying smallest balance
  # first closes accounts sooner. Both are shown because the behavioural answer
  # and the mathematical one are not always the same.
  def avalanche_order
    debts
  end

  def snowball_order
    debts.sort_by(&:balance)
  end

  # A month-by-month payoff simulation, pooled and applied avalanche-first.
  # Interest is accrued on the opening balance each month and the household's
  # stated payments plus any extra are thrown at the highest rate first, so a
  # repaid card's minimum naturally rolls on to the next debt.
  #
  # Returns nil when a debt has no stated payment or rate: inventing one would
  # turn an unknown into a plan.
  def payoff(extra_monthly: 0)
    return nil if debts.empty?
    return nil unless debts.all? { |debt| debt.payment.present? && debt.rate? }

    balances = debts.map { |debt| debt.balance.to_d }
    payments = debts.map { |debt| debt.payment.to_d }
    rates = debts.map { |debt| debt.rate_pct.to_d / 100 }
    order = balances.each_index.sort_by { |index| -rates[index] }
    extra = BigDecimal(extra_monthly.to_s)
    months = 0
    total_interest = BigDecimal("0")

    while balances.any?(&:positive?)
      return nil if months >= MAX_PAYOFF_MONTHS

      months += 1
      balances.each_index do |index|
        next unless balances[index].positive?

        interest = balances[index] * rates[index] / 12
        balances[index] += interest
        total_interest += interest
      end

      pool = payments.sum + extra
      order.each do |index|
        break if pool <= 0
        next unless balances[index].positive?

        payment = [ pool, balances[index] ].min
        balances[index] -= payment
        pool -= payment
      end
    end

    { months: months, total_interest: total_interest.round(2) }
  end

  # Current plan plus two what-ifs (+50% and double payments). Server-rendered:
  # three honest scenarios answer the question better than a slider asking the
  # household to guess its own capacity.
  def payoff_scenarios
    return @payoff_scenarios if defined?(@payoff_scenarios)
    return @payoff_scenarios = [] if monthly_obligation.nil?

    baseline = payoff(extra_monthly: 0)
    return @payoff_scenarios = [] if baseline.nil?

    [ 0, 0.5, 1.0 ].map do |multiplier|
      extra = (monthly_obligation * multiplier).round(2)
      result = payoff(extra_monthly: extra)
      {
        extra: extra,
        months: result && result[:months],
        total_interest: result && result[:total_interest]
      }
    end
  end

  # Share of assets financed by debt. 0 assets means the ratio is undefined
  # rather than infinite.
  def debt_to_assets_percent
    return @debt_to_assets_percent if defined?(@debt_to_assets_percent)

    assets_total = balance_sheet.assets.total
    @debt_to_assets_percent = if assets_total.positive?
      ((total_debt / assets_total) * 100).round(1)
    end
  end

  private
    def currency
      family.currency
    end

    def balance_sheet
      @balance_sheet ||= family.balance_sheet(user: user)
    end

    def debt_accounts
      family.accounts.visible
        .accessible_by(user)
        .select { |account| account.classification == "liability" && !account.exclude_from_reports? }
    end

    def build_debt(account)
      Debt.new(
        account: account,
        balance: converted_balance_for(account),
        rate_pct: rate_for(account),
        payment: converted_payment_for(account),
        high_interest: rate_for(account).present? && rate_for(account) >= HIGH_INTEREST_THRESHOLD_PCT
      )
    end

    def converted_payment_for(account)
      money = case account.accountable
      when CreditCard then account.accountable.minimum_payment_money
      when Loan then account.accountable.monthly_payment
      end
      return nil if money.nil?

      rate = account.currency == currency ? 1 : (exchange_rates[account.currency] || 1)
      money.amount * rate
    end

    def income_statement
      @income_statement ||= family.income_statement(user: user)
    end

    def history_period
      Period.custom(
        start_date: Date.current.beginning_of_month - 11.months,
        end_date: Date.current.end_of_month
      )
    end

    def rate_for(account)
      accountable = account.accountable
      rate = case accountable
      when CreditCard then accountable.apr
      when Loan then accountable.interest_rate
      end

      rate.present? ? BigDecimal(rate.to_s) : nil
    end

    def exchange_rates
      @exchange_rates ||= begin
        foreign = debt_accounts.filter_map { |account| account.currency if account.currency != currency }.uniq
        foreign.empty? ? {} : ExchangeRate.rates_for(foreign, to: currency, date: Date.current)
      end
    end

    def converted_balance_for(account)
      return account.balance if account.currency == currency

      account.balance * (exchange_rates[account.currency] || 1)
    end

    def converted_available_credit_for(account)
      credit = account.accountable.available_credit
      return 0 if credit.nil?

      rate = account.currency == currency ? 1 : (exchange_rates[account.currency] || 1)
      credit * rate
    end
end
