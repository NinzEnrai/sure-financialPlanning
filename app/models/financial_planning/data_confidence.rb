# What is missing behind the numbers on this page? An advisory figure is only
# as trustworthy as its inputs, and a confident-looking return built on a stale
# price or a missing exchange rate is worse than no figure at all.
#
# Each check names the input, how many items are affected, and how many there
# were in total. The statuses are about trust, not performance: :attention for
# something that actively distorts a figure (a missing FX rate), :watch for a
# gap that limits what can be computed (no purchase dates, stale prices), and
# :good when there is nothing to report. Nothing here changes a number; the
# panel exists so the household can see the edge of what Sure knows.
class FinancialPlanning::DataConfidence
  Check = Data.define(:key, :status, :count, :total)

  # The nightly price job keeps trading days fresh; a week allows for a long
  # weekend plus a missed run before a price is called stale.
  STALE_PRICE_DAYS = 7

  attr_reader :family, :user

  def initialize(family, user: nil)
    @family = family
    @user = user || Current.user
  end

  def checks
    @checks ||= [
      exchange_rate_check,
      price_history_check,
      purchase_date_check,
      classification_check,
      excluded_accounts_check
    ]
  end

  def issue_count
    checks.count { |check| check.status != :good }
  end

  def attention_count
    checks.count { |check| check.status == :attention }
  end

  def healthy?
    issue_count.zero?
  end

  def held_security_ids
    @held_security_ids ||= Holding.where(account_id: account_ids).distinct.pluck(:security_id)
  end

  def account_ids
    @account_ids ||= family.accounts.visible.pluck(:id)
  end

  private
    def exchange_rate_check
      foreign = accounts.map(&:currency).uniq.reject { |code| code == family.currency }
      return Check.new(key: :exchange_rates, status: :good, count: 0, total: 0) if foreign.empty?

      known = ExchangeRate
        .where(from_currency: foreign, to_currency: family.currency, date: Date.current)
        .distinct.pluck(:from_currency)
      missing = foreign - known

      Check.new(
        key: :exchange_rates,
        status: missing.any? ? :attention : :good,
        count: missing.size,
        total: foreign.size
      )
    end

    def price_history_check
      ids = held_security_ids
      return Check.new(key: :price_history, status: :good, count: 0, total: 0) if ids.empty?

      cutoff = STALE_PRICE_DAYS.days.ago.to_date
      latest = Security::Price.where(security_id: ids).group(:security_id).maximum(:date)
      stale = ids.count { |security_id| latest[security_id].nil? || latest[security_id] < cutoff }

      Check.new(
        key: :price_history,
        status: stale.zero? ? :good : :watch,
        count: stale,
        total: ids.size
      )
    end

    def purchase_date_check
      ids = held_security_ids
      return Check.new(key: :purchase_dates, status: :good, count: 0, total: 0) if ids.empty?

      traded = Trade
        .where(id: Entry.where(account_id: account_ids, entryable_type: "Trade").select(:entryable_id))
        .distinct.pluck(:security_id)
      missing = ids - traded

      Check.new(
        key: :purchase_dates,
        status: missing.empty? ? :good : :watch,
        count: missing.size,
        total: ids.size
      )
    end

    def classification_check
      ids = held_security_ids
      return Check.new(key: :classification, status: :good, count: 0, total: 0) if ids.empty?

      unclassified = Security.where(id: ids)
        .where("asset_class IS NULL OR asset_class = '' OR classification_source IS NULL OR classification_source = ''")
        .count

      Check.new(
        key: :classification,
        status: unclassified.zero? ? :good : :watch,
        count: unclassified,
        total: ids.size
      )
    end

    def excluded_accounts_check
      excluded = family.accounts.visible.where(exclude_from_reports: true).count

      Check.new(
        key: :excluded_accounts,
        status: excluded.zero? ? :good : :watch,
        count: excluded,
        total: nil
      )
    end

    def accounts
      @accounts ||= family.accounts.visible.to_a
    end
end
