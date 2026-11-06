# Is the data behind an Indian capital-gains figure actually there?
#
# This deliberately computes no tax. It checks the inputs a chartered accountant
# would ask for -- recorded trades, purchase dates, prices, foreign assets and
# tax-advantaged accounts -- and says plainly which ones are missing, so the app
# never grows a tax number it cannot support. The financial year follows the
# family's country: April-March for India, the calendar year otherwise.
class FinancialPlanning::TaxReadiness
  Check = Data.define(:key, :status, :count, :total)

  CACHE_TTL = 2.minutes

  attr_reader :family, :user

  def initialize(family, user: nil, data_confidence: nil)
    @family = family
    @user = user || Current.user
    @data_confidence = data_confidence
  end

  def checks
    @checks ||= Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      [
        trades_check,
        trade_price_check,
        purchase_date_check,
        foreign_assets_check,
        tax_advantaged_check
      ]
    end
  end

  # Used by the card to surface the Schedule FA disclosure for foreign holdings.
  def foreign_assets_count
    checks.find { |check| check.key == :foreign_assets }&.count.to_i
  end

  def financial_year_label
    if indian?
      "FY #{start_date.year}-#{format("%02d", (start_date.year + 1) % 100)}"
    else
      start_date.year.to_s
    end
  end

  def start_date
    @start_date ||= if indian?
      year = Date.current.month >= 4 ? Date.current.year : Date.current.year - 1
      Date.new(year, 4, 1)
    else
      Date.current.beginning_of_year
    end
  end

  def end_date
    @end_date ||= indian? ? start_date + 1.year - 1.day : Date.current.end_of_year
  end

  private
    def trades_check
      count = period_entries.where(entryable_type: "Trade").count
      status = count.positive? ? :good : :attention

      Check.new(key: :trades, status: status, count: count, total: nil)
    end

    def trade_price_check
      security_ids = Trade
        .where(id: period_entries.where(entryable_type: "Trade").select(:entryable_id))
        .distinct.pluck(:security_id)
      return Check.new(key: :trade_prices, status: :good, count: 0, total: 0) if security_ids.empty?

      priced = Security::Price.where(security_id: security_ids).distinct.pluck(:security_id)
      missing = security_ids - priced

      Check.new(
        key: :trade_prices,
        status: missing.empty? ? :good : :attention,
        count: missing.size,
        total: security_ids.size
      )
    end

    def purchase_date_check
      coverage = data_confidence.checks.find { |check| check.key == :purchase_dates }
      return Check.new(key: :purchase_dates, status: :good, count: 0, total: 0) if coverage.total.to_i.zero?

      Check.new(
        key: :purchase_dates,
        status: coverage.count.positive? ? :attention : :good,
        count: coverage.count,
        total: coverage.total
      )
    end

    def foreign_assets_check
      home = family.country.presence || "US"
      ids = data_confidence.held_security_ids
      return Check.new(key: :foreign_assets, status: :good, count: 0, total: 0) if ids.empty?

      foreign = Security.where(id: ids).where.not(country_code: [ nil, "", home ]).count

      Check.new(
        key: :foreign_assets,
        status: foreign.zero? ? :good : :watch,
        count: foreign,
        total: ids.size
      )
    end

    def tax_advantaged_check
      count = Account.where(id: data_confidence.account_ids).to_a.count { |account| account.tax_treatment.present? }

      Check.new(key: :tax_advantaged, status: :good, count: count, total: nil)
    end

    def period_entries
      @period_entries ||= Entry.where(
        account_id: data_confidence.account_ids,
        date: start_date..end_date,
        excluded: false
      )
    end

    def data_confidence
      @data_confidence ||= FinancialPlanning::DataConfidence.new(family, user: user)
    end

    # Shares the two-minute diagnostics cache with the confidence panel; the
    # family versions are in the key so a change to the ledger or accounts still
    # recomputes immediately.
    def cache_key
      [
        "financial_planning", "tax_readiness", "v1",
        family.id, user&.id, start_date, end_date,
        family.entries_cache_version,
        family.accounts_status_version,
        Security.maximum(:updated_at)&.to_i,
        Security::Price.maximum(:updated_at)&.to_i,
        Holding.maximum(:updated_at)&.to_i,
        ExchangeRate.maximum(:updated_at)&.to_i
      ]
    end

    def indian?
      family.country.to_s.upcase == "IN"
    end
end
