# Investment holdings valued at cost, as of any date, for the savings split to
# difference over time.
#
# Cost basis is the right basis for "money went into investments" because it only
# moves when a position is bought or sold. A price change leaves it untouched, so
# a falling market can't read as negative investing -- which is exactly what
# `Holding#amount` (market value) would report.
#
# Each account is read at *its own* most recent date at or before the one asked
# for, not at a single shared date. Holdings are forward-calculated per account
# as each provider syncs, so a brokerage last refreshed yesterday and one refreshed
# this morning have holdings on different dates; taking the latest date across the
# whole family would silently discard every position on the account that hadn't
# refreshed that day -- an omission that reads as "you hold nothing".
#
# Holdings are converted to the family currency with ExchangeRate.rates_for --
# the same batch lookup the balance sheet uses to convert account balances, so
# this figure can't disagree with net worth. Filtering to family-currency
# holdings instead would report zero for a family that invests in the currency it
# lives in while its base currency is something else.
#
# rates_for falls back to the nearest recent rate, then the rate provider, and
# finally 1 with a logged warning, so a currency the family never fetched a rate
# for degrades rather than raising and taking the whole savings split down with
# it.
#
# Scope is otherwise narrow and deliberate: draft/archived accounts and anything
# flagged `exclude_from_reports` are skipped, matching the scoping the balance
# sheet and income statement already apply.
class FinancialPlanning::HoldingsCostBasisSeries
  # The `accountable_type` values Account#balance_type maps to :investment.
  # Spelled out because balance_type is an instance method with no class-level
  # counterpart to borrow the list from.
  INVESTMENT_ACCOUNTABLE_TYPES = %w[Investment Crypto].freeze

  def initialize(family, currency: family.currency)
    @family = family
    @currency = currency
  end

  # Total cost basis held as of +as_of+, in the family currency. Zero when the
  # family has never held an investment.
  def total(as_of:)
    # Per date rather than one figure for the whole series: converting needs an
    # exchange rate lookup per date, and the caller asks about two dates per
    # period, not all 1100 the family has on record.
    @converted_totals ||= {}
    @converted_totals[as_of] ||= convert(cost_basis_by_currency(as_of), as_of)
  end

  # Money that went into investments during a period: cost basis gained. A sale,
  # or a sync that dropped a closed position, drives this negative; callers clamp
  # at zero because money leaving investments is not new spending.
  def invested_between(start_date:, end_date:)
    (total(as_of: end_date) - total(as_of: start_date - 1.day)).round(2)
  end

  private
    attr_reader :family, :currency

    def convert(by_currency, as_of)
      return 0.to_d if by_currency.empty?

      foreign = by_currency.keys - [ currency ]
      rates = foreign.any? ? ExchangeRate.rates_for(foreign, to: currency, date: as_of) : {}

      by_currency.sum do |holding_currency, amount|
        holding_currency == currency ? amount : amount * rates.fetch(holding_currency, 1)
      end
    end

    # Cost basis summed per currency, each account contributing the figure from
    # its own latest date at or before +as_of+.
    #
    # The two CTEs do the work: the inner one collapses each account's positions
    # into a per-day total (so a 20-holding brokerage is one row, not twenty),
    # and the outer picks each account's newest such day. Doing the "latest" pick
    # after collapsing is what keeps a partially-synced account from being read
    # at a date where it happens to have fewer positions.
    def cost_basis_by_currency(as_of)
      rows = ActiveRecord::Base.connection.select_all(
        ActiveRecord::Base.sanitize_sql_array([ cost_basis_sql, as_of: as_of, family_id: family.id ])
      )

      rows.each_with_object(Hash.new(0)) do |row, totals|
        totals[row["holding_currency"]] += row["cost_basis"].to_d
      end
    end

    def cost_basis_sql
      <<~SQL
        WITH per_account_day AS (
          SELECT h.account_id, h.date, h.currency AS holding_currency,
                 COALESCE(SUM(h.cost_basis), 0) AS cost_basis
          FROM holdings h
          INNER JOIN accounts a ON a.id = h.account_id
          WHERE a.family_id = :family_id
            AND a.status IN ('draft', 'active')
            AND a.exclude_from_reports = false
            AND a.accountable_type IN ('Investment', 'Crypto')
            AND h.date <= :as_of
          GROUP BY h.account_id, h.date, h.currency
        ),
        latest_per_account AS (
          SELECT DISTINCT ON (account_id, holding_currency)
                 account_id, holding_currency, cost_basis
          FROM per_account_day
          ORDER BY account_id, holding_currency, date DESC
        )
        SELECT holding_currency, cost_basis FROM latest_per_account
      SQL
    end
end
