# Will the household run short before payday? A deliberately simple 30/60/90
# day projection: cash on hand, plus the trailing monthly surplus (recorded
# income minus spending, debt service and insurance premiums), projected
# forward.
#
# It uses averages rather than a day-level cash calendar because Sure has no
# reliable bill-date budget for every household; the card says so rather than
# pretending to a precision the data does not support. Unknown debt payments are
# treated as zero only after flagging that they are missing, never silently.
class FinancialPlanning::CashFlowForecast
  HORIZONS = [ 30, 60, 90 ].freeze

  Point = Data.define(:days, :date, :balance, :negative) do
    def balance_money(currency)
      Money.new(balance, currency)
    end

    def negative?
      negative
    end
  end

  attr_reader :family, :user

  def initialize(family, user: nil)
    @family = family
    @user = user || Current.user
  end

  def start_cash
    @start_cash ||= emergency_fund.liquid_balance
  end

  def start_cash_money
    Money.new(start_cash, currency)
  end

  def monthly_income
    @monthly_income ||= debt_summary.monthly_income
  end

  def monthly_spending
    @monthly_spending ||= emergency_fund.monthly_expenses
  end

  # Nil when no liability records a payment: the forecast can still run, but the
  # card has to say the number excludes debt.
  def monthly_debt_service
    return @monthly_debt_service if defined?(@monthly_debt_service)

    @monthly_debt_service = debt_summary.monthly_obligation
  end

  def debt_known?
    !monthly_debt_service.nil?
  end

  def monthly_premiums
    @monthly_premiums ||= (protection_gap.annual_premium_total / 12).round(2)
  end

  def net_monthly
    return @net_monthly if defined?(@net_monthly)
    return @net_monthly = nil if monthly_income.blank?

    debt = (monthly_debt_service || 0).to_d
    @net_monthly = (monthly_income - monthly_spending - debt - monthly_premiums).round(2)
  end

  def net_monthly_money
    Money.new(net_monthly, currency)
  end

  def available?
    monthly_income.present? && monthly_income.positive?
  end

  def points
    return @points if defined?(@points)
    return @points = [] unless available?

    @points = HORIZONS.map do |days|
      balance = (start_cash + (net_monthly * BigDecimal(days) / 30)).round(2)
      Point.new(days: days, date: Date.current + days, balance: balance, negative: balance.negative?)
    end
  end

  def shortfall?
    points.any?(&:negative?)
  end

  def first_shortfall
    points.find(&:negative?)
  end

  private
    def currency
      family.currency
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
end
