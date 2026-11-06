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
# Holding-period rules differ by asset, so the row carries the rule that
# applies: 365 days for domestic listed equity, 730 for foreign and unlisted
# shares, and no long-term treatment at all for debt funds (taxed at slab).
# Unclassified securities are treated as listed equity and the card says so.
class FinancialPlanning::RealisedGains
  LISTED_EQUITY_LONG_TERM_DAYS = 365
  OTHER_LONG_TERM_DAYS = 730

  Row = Data.define(
    :security, :acquired_on, :sold_on, :qty, :proceeds, :cost_basis, :gain,
    :category, :holding_days, :long_term_days, :slab_taxed
  ) do
    def slab_taxed?
      slab_taxed
    end

    def long_term?
      return false if slab_taxed?

      holding_days.present? && long_term_days.present? && holding_days > long_term_days
    end

    def short_term?
      !slab_taxed? && !long_term?
    end
  end

  attr_reader :family, :user, :as_of

  # `account_ids:` scopes the engine to one owner's accounts; nil means every
  # visible account in the family (the family-wide view).
  def initialize(family, user: nil, as_of: Date.current, account_ids: nil, tax_lots: nil)
    @family = family
    @user = user || Current.user
    @as_of = as_of.to_date
    @account_ids_override = account_ids
    @tax_lots = tax_lots
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

        category = category_for(realisation.security)
        holding_days = (realisation.sold_on - realisation.acquired_on).to_i
        Row.new(
          security: realisation.security,
          acquired_on: realisation.acquired_on,
          sold_on: realisation.sold_on,
          qty: realisation.qty,
          proceeds: proceeds,
          cost_basis: cost,
          gain: (proceeds - cost).round(2),
          category: category,
          holding_days: holding_days,
          long_term_days: long_term_days_for(category),
          slab_taxed: category == :debt_fund
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
    rows.select(&:short_term?).sum { |row| row.gain }.round(2)
  end

  def short_term_gain_money
    Money.new(short_term_gain, currency)
  end

  def long_term_gain
    rows.select(&:long_term?).sum { |row| row.gain }.round(2)
  end

  # Debt funds: taxed at the holder's slab rate whenever sold. They never get
  # long-term treatment, so they are kept in their own bucket rather than being
  # folded into "short term", where the label would imply a rate that does not
  # apply.
  def slab_gain
    rows.select(&:slab_taxed?).sum { |row| row.gain }.round(2)
  end

  def slab_gain_money
    Money.new(slab_gain, currency)
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

    def home_country
      (family.country.presence || "US").to_s.upcase
    end

    # A deliberately small rule table over the security metadata Sure stores.
    # Anything unclassified falls back to listed equity, which the card states.
    def category_for(security)
      if security.is_mutual_fund? && security.asset_class == "fixed_income"
        :debt_fund
      elsif security.country_code.present? && security.country_code.to_s.upcase != home_country
        :foreign
      elsif security.asset_class == "equity" || security.asset_class.blank?
        :listed_equity
      else
        :other
      end
    end

    def long_term_days_for(category)
      case category
      when :debt_fund then nil
      when :listed_equity then LISTED_EQUITY_LONG_TERM_DAYS
      else OTHER_LONG_TERM_DAYS
      end
    end

    def readiness
      @readiness ||= FinancialPlanning::TaxReadiness.new(family, user: user)
    end

    def engine
      @engine ||= @tax_lots || Portfolio::TaxLots.new(account_ids: account_ids, as_of: as_of)
    end

    def account_ids
      @account_ids ||= if @account_ids_override.nil?
        visible_accounts.pluck(:id)
      else
        Array(@account_ids_override)
      end
    end

    def visible_accounts
      user ? family.accounts.visible.accessible_by(user) : family.accounts.visible
    end

    def convert(amount, from_currency, date)
      return amount if from_currency == currency

      rate = ExchangeRate.find_by(from_currency: from_currency, to_currency: currency, date: date)&.rate
      return nil if rate.nil?

      (amount.to_d * rate).round(2)
    end
end
