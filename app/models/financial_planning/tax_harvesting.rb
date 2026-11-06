# Positions sitting at an unrealised loss, as candidates for tax-loss harvesting.
#
# India has no wash-sale rule: selling to book a loss and buying the same shares
# back is allowed, which is what makes harvesting a legitimate lever there. This
# card only surfaces the opportunity — it never trades, and it says plainly that
# a sale is real, carries costs, and takes the position out of the portfolio.
#
# Unrealised loss is measured against cost basis from the FIFO lots, at the
# latest recorded price in the lot's own currency. Securities without a price,
# or with a price the app cannot convert, are counted and excluded rather than
# guessed at. The offset note is capped at this year's estimated taxable gains;
# actual set-off follows the tax rules, not this card.
class FinancialPlanning::TaxHarvesting
  STALE_PRICE_DAYS = 7

  Candidate = Data.define(
    :security, :qty, :cost, :value, :loss, :currency, :price_date, :stale
  ) do
    def loss_money(currency)
      Money.new(loss, currency)
    end

    def stale?
      stale
    end
  end

  attr_reader :family, :user, :as_of

  def initialize(family, user: nil, as_of: Date.current, tax_lots: nil)
    @family = family
    @user = user || Current.user
    @as_of = as_of.to_date
    @tax_lots = tax_lots
  end

  def candidates
    return @candidates if defined?(@candidates)

    @unpriced_count = 0
    @unconverted_count = 0
    @candidates = lots.group_by { |lot| [ lot.security, lot.currency ] }
      .filter_map { |(security, _currency), security_lots| build_candidate(security, security_lots) }
      .reject { |candidate| candidate.loss >= 0 }
      .sort_by(&:loss)
  end

  def empty?
    candidates.empty?
  end

  def total_loss
    candidates.sum(&:loss).round(2)
  end

  def total_loss_amount
    -total_loss
  end

  def total_loss_money
    Money.new(total_loss_amount, currency)
  end

  # This year's estimated taxable gains, used only to frame how much a loss
  # could offset. Nil-safe when the estimate has nothing to say.
  def taxable_gains
    estimate.total_taxable
  end

  def taxable_gains_money
    Money.new([ taxable_gains, 0 ].max, currency)
  end

  def offset_capacity
    [ total_loss_amount, [ taxable_gains, 0 ].max ].min.round(2)
  end

  def offset_capacity_money
    Money.new(offset_capacity, currency)
  end

  def unpriced_count
    candidates
    @unpriced_count
  end

  def unconverted_count
    candidates
    @unconverted_count
  end

  private
    def currency
      family.currency
    end

    def lots
      @lots ||= engine.lots
    end

    def engine
      @engine ||= @tax_lots || Portfolio::TaxLots.new(account_ids: visible_account_ids, as_of: as_of)
    end

    def visible_account_ids
      scope = user ? family.accounts.visible.accessible_by(user) : family.accounts.visible
      scope.pluck(:id)
    end

    def estimate
      @estimate ||= FinancialPlanning::CapitalGainsEstimate.new(family, user: user, as_of: as_of)
    end

    def build_candidate(security, security_lots)
      price_record = latest_price(security, security_lots.first.currency)
      if price_record.nil?
        @unpriced_count += 1
        return nil
      end

      qty = security_lots.sum { |lot| lot.qty.to_d }
      cost = security_lots.sum { |lot| lot.qty.to_d * lot.cost_per_unit.to_d }.round(2)
      value = (qty * price_record.price.to_d).round(2)

      converted_cost = convert(cost, security_lots.first.currency, price_record.date)
      converted_value = convert(value, security_lots.first.currency, price_record.date)
      if converted_cost.nil? || converted_value.nil?
        @unconverted_count += 1
        return nil
      end

      Candidate.new(
        security: security,
        qty: qty,
        cost: converted_cost,
        value: converted_value,
        loss: (converted_value - converted_cost).round(2),
        currency: currency,
        price_date: price_record.date,
        stale: price_record.date < STALE_PRICE_DAYS.days.ago.to_date
      )
    end

    def latest_price(security, lot_currency)
      Security::Price
        .where(security_id: security.id, currency: lot_currency)
        .order(date: :desc)
        .first
    end

    def convert(amount, from_currency, date)
      return amount if from_currency == currency

      rate = ExchangeRate.find_by(from_currency: from_currency, to_currency: currency, date: date)&.rate
      return nil if rate.nil?

      (amount.to_d * rate).round(2)
    end
end
