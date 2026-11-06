# What trading actually cost this year: the fees recorded on trades over a
# trailing twelve months, in the family currency, as an absolute and as a share
# of the portfolio.
#
# Scope is deliberately narrow and stated on the card: Sure only knows the fee
# field on a trade. Fund expense ratios, advisory fees and platform charges are
# not stored, and the Console tradebook import records zero fees because the
# tradebook does not carry them. This is the brokerage line, not the whole cost
# of investing.
#
# Fees are converted at each trade's own date; a trade whose currency has no
# recorded rate is counted and excluded rather than converted at 1.
class FinancialPlanning::FeeAudit
  PERIOD_MONTHS = 12

  attr_reader :family, :user

  def initialize(family, user: nil, investment_statement: nil)
    @family = family
    @user = user || Current.user
    @investment_statement = investment_statement
  end

  def period
    @period ||= Period.custom(
      start_date: Date.current.beginning_of_month - (PERIOD_MONTHS - 1).months,
      end_date: Date.current.end_of_month
    )
  end

  def rows
    return @rows if defined?(@rows)

    @unconverted_count = 0
    @rows = trades.filter_map do |trade|
      fee = convert(trade.fee.to_d, trade.currency, trade.entry.date)
      if fee.nil?
        @unconverted_count += 1
        next
      end

      { account: trade.entry.account, security: trade.security, date: trade.entry.date, fee: fee }
    end
  end

  def empty?
    rows.empty?
  end

  def total_fees
    rows.sum { |row| row[:fee] }.round(2)
  end

  def total_fees_money
    Money.new(total_fees, currency)
  end

  def trade_count
    rows.size
  end

  def unconverted_count
    rows
    @unconverted_count
  end

  def by_account
    rows.group_by { |row| row[:account] }
      .map { |account, account_rows| { account: account, fee: account_rows.sum { |row| row[:fee] }.round(2) } }
      .sort_by { |entry| -entry[:fee] }
  end

  def portfolio_value
    @portfolio_value ||= investment_statement.portfolio_value.to_d
  end

  def portfolio_value_money
    Money.new(portfolio_value, currency)
  end

  # Nil when there is no portfolio to compare against; a fee against zero is
  # not "0%", it is unanswerable.
  def fee_ratio_percent
    return nil unless portfolio_value.positive?

    @fee_ratio_percent ||= ((total_fees / portfolio_value) * 100).round(2)
  end

  private
    def currency
      family.currency
    end

    def investment_statement
      @investment_statement ||= family.investment_statement(user: user)
    end

    def account_ids
      @account_ids ||= begin
        scope = user ? family.accounts.visible.accessible_by(user) : family.accounts.visible
        scope.pluck(:id)
      end
    end

    def trades
      @trades ||= Trade
        .joins(:entry)
        .where(entries: { account_id: account_ids, date: period.start_date..period.end_date, excluded: false })
        .where("trades.fee > 0")
        .includes(:security, entry: :account)
    end

    def convert(amount, from_currency, date)
      return amount if from_currency == currency

      rate = ExchangeRate.find_by(from_currency: from_currency, to_currency: currency, date: date)&.rate
      return nil if rate.nil?

      (amount * rate).round(2)
    end
end
