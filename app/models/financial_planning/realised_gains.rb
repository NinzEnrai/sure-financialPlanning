# Realised gains for the current financial year, computed from FIFO lots.
#
# This is an estimate, not a tax calculation: it applies no exemption, no
# set-off, no surcharge and no rate. It exists so the household can see what it
# actually sold and what the sale realised, and so the tax-year readiness panel
# has a number behind its checklist.
#
# Everything is converted to the family currency at the transaction dates --
# proceeds at the sale date, cost at the purchase date -- because a foreign
# gain translated with today's rate is not the gain that was made.
#
# The long-term boundary is 365 days, the listed-equity rule for Indian
# residents. Unlisted and foreign shares use longer thresholds; those
# exceptions belong in the tax estimate that follows this engine, not here.
class FinancialPlanning::RealisedGains
  LONG_TERM_DAYS = 365

  Row = Data.define(:security, :acquired_on, :sold_on, :qty, :proceeds, :cost_basis, :gain) do
    def long_term?
      acquired_on.present? && (sold_on - acquired_on).to_i > LONG_TERM_DAYS
    end
  end

  attr_reader :family, :user, :as_of

  def initialize(family, user: nil, as_of: Date.current)
    @family = family
    @user = user || Current.user
    @as_of = as_of.to_date
  end

  def rows
    @rows ||= begin
      @unconverted_count = 0
      engine.realisations.filter_map do |realisation|
        next unless realisation.sold_on.between?(start_date, end_date)
        next if realisation.unknown_origin

        proceeds = convert(realisation.proceeds, realisation.currency, realisation.sold_on)
        cost = convert(realisation.cost_basis, realisation.currency, realisation.acquired_on)
        if proceeds.nil? || cost.nil?
          @unconverted_count += 1
          next
        end

        Row.new(
          security: realisation.security,
          acquired_on: realisation.acquired_on,
          sold_on: realisation.sold_on,
          qty: realisation.qty,
          proceeds: proceeds,
          cost_basis: cost,
          gain: (proceeds - cost).round(2)
        )
      end
    end
  end

  # Realisations whose gain could not be converted because no exchange rate was
  # recorded for their transaction dates. Excluded rather than converted at 1.
  def unconverted_count
    rows
    @unconverted_count
  end

  def unknown_count
    @unknown_count ||= engine.realisations.count do |realisation|
      realisation.sold_on.between?(start_date, end_date) && realisation.unknown_origin
    end
  end

  def total_gain
    rows.sum { |row| row.gain }.round(2)
  end

  def total_gain_money
    Money.new(total_gain, currency)
  end

  def short_term_gain
    rows.reject(&:long_term?).sum { |row| row.gain }.round(2)
  end

  def short_term_gain_money
    Money.new(short_term_gain, currency)
  end

  def long_term_gain
    rows.select(&:long_term?).sum { |row| row.gain }.round(2)
  end

  def long_term_gain_money
    Money.new(long_term_gain, currency)
  end

  def empty?
    rows.empty? && unknown_count.zero?
  end

  def financial_year_label
    readiness.financial_year_label
  end

  def start_date
    readiness.start_date
  end

  def end_date
    readiness.end_date
  end

  private
    def currency
      family.currency
    end

    def readiness
      @readiness ||= FinancialPlanning::TaxReadiness.new(family, user: user)
    end

    def engine
      @engine ||= Portfolio::TaxLots.new(account_ids: account_ids, as_of: as_of)
    end

    def account_ids
      @account_ids ||= family.accounts.visible.pluck(:id)
    end

    def convert(amount, from_currency, date)
      return amount if from_currency == currency

      rate = ExchangeRate.find_by(from_currency: from_currency, to_currency: currency, date: date)&.rate
      return nil if rate.nil?

      (amount.to_d * rate).round(2)
    end
end
