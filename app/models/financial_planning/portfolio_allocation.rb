# How the invested money is split, and whether one position is large enough to
# decide the outcome on its own.
#
# The roll-up itself belongs to InvestmentStatement (one security per row across
# accounts, weights against the portfolio so cash is the residual). This class
# only adds the advisory framing: concentration bands, the cash share, and a
# grouping by asset class where the securities carry one.
#
# Thresholds are practitioner heuristics, not rules: a single position above
# 20% of the invested portfolio is commonly flagged as over-concentrated, and
# 10% is where a holding starts to be worth checking.
class FinancialPlanning::PortfolioAllocation
  CONCENTRATION_WATCH_PCT = 10
  CONCENTRATION_ATTENTION_PCT = 20

  AssetClass = Data.define(:key, :amount, :percent) do
    def amount_money(currency)
      Money.new(amount, currency)
    end
  end

  attr_reader :family, :user

  def initialize(family, user: nil)
    @family = family
    @user = user || Current.user
  end

  def allocation
    @allocation ||= investment_statement.allocation
  end

  def empty?
    allocation.empty?
  end

  def top_holdings(limit: 5)
    allocation.first(limit)
  end

  def largest_holding
    allocation.max_by(&:weight)
  end

  def largest_weight
    largest_holding&.weight
  end

  def concentration_status
    return :unknown if empty?

    weight = largest_weight.to_f
    return :attention if weight >= CONCENTRATION_ATTENTION_PCT
    return :watch if weight >= CONCENTRATION_WATCH_PCT

    :good
  end

  def invested_total
    @invested_total ||= allocation.sum { |row| row.amount.amount }.round(2)
  end

  def invested_total_money
    Money.new(invested_total, currency)
  end

  def portfolio_value
    investment_statement.portfolio_value
  end

  def cash_total
    @cash_total ||= [ portfolio_value - invested_total, 0 ].max.round(2)
  end

  def cash_total_money
    Money.new(cash_total, currency)
  end

  def cash_percent
    return nil unless portfolio_value.positive?

    @cash_percent ||= ((cash_total / portfolio_value) * 100).round(1)
  end

  # Grouped by the security's asset class; anything without one is grouped as
  # "unclassified" rather than being dropped, so the percentages still add up.
  def asset_classes
    return @asset_classes if defined?(@asset_classes)
    return @asset_classes = [] if invested_total.zero?

    @asset_classes = allocation
      .group_by { |row| row.security.asset_class.presence || "unclassified" }
      .map do |key, rows|
        amount = rows.sum { |row| row.amount.amount }.round(2)
        AssetClass.new(key: key, amount: amount, percent: ((amount / invested_total) * 100).round(1))
      end
      .sort_by { |group| -group.amount }
  end

  private
    def investment_statement
      @investment_statement ||= family.investment_statement(user: user)
    end

    def currency
      family.currency
    end
end
