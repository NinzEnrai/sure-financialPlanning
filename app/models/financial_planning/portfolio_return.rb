# The portfolio's money-weighted return, as an advisory card rather than a
# report row: "what did the money I put in actually earn?"
#
# The calculation itself is not reimplemented here. InvestmentStatement owns
# the account scope and portfolio value, and Portfolio::MoneyWeightedReturn owns
# the flow series (buys in, sells out, closing value terminal) and the XIRR
# solve. This class only assembles them for one trailing year and states the
# assumption that produced the figure, because a return without its basis is a
# number a household cannot interpret.
#
# The basis is :trades, the same choice the reports page makes for a portfolio
# anchored from holdings. It is exact only when no cash sat idle between a
# deposit and the purchase it funded; the card says so rather than implying a
# precision the data does not have. When the solver reports ambiguity the card
# hedges instead of presenting one root as "the" return.
class FinancialPlanning::PortfolioReturn
  PERIOD_MONTHS = 12

  attr_reader :family, :user

  def initialize(family, user: nil)
    @family = family
    @user = user || Current.user
  end

  def empty?
    investment_statement.investment_accounts.empty?
  end

  def portfolio_value
    investment_statement.portfolio_value
  end

  def portfolio_value_money
    investment_statement.portfolio_value_money
  end

  # The flows the trailing year's totals are measured over. Kept separate from
  # the XIRR series, which necessarily runs from the very first flow.
  def period
    @period ||= Period.custom(
      start_date: Date.current.beginning_of_month - (PERIOD_MONTHS - 1).months,
      end_date: Date.current.end_of_month
    )
  end

  def weighted_return
    @weighted_return ||= Portfolio::MoneyWeightedReturn.new(
      account_ids: investment_statement.investment_accounts.pluck(:id),
      currency: family.currency,
      closing_value: portfolio_value,
      as_of: Date.current,
      basis: :trades
    )
  end

  def rate_percent
    return nil unless weighted_return.available?

    (weighted_return.rate * 100).round(2)
  end

  def available?
    weighted_return.available?
  end

  def ambiguous?
    weighted_return.ambiguous?
  end

  def since
    weighted_return.first_flow_on
  end

  def totals
    @totals ||= investment_statement.totals(period: period)
  end

  def contributions_money
    totals.contributions
  end

  def withdrawals_money
    totals.withdrawals
  end

  def income_money
    Money.new(totals.dividends.amount + totals.interest.amount, currency)
  end

  private
    def investment_statement
      @investment_statement ||= family.investment_statement(user: user)
    end

    def currency
      family.currency
    end
end
