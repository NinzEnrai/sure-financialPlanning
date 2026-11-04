# Import a Zerodha Console tradebook CSV into an investment account.
#
# The Console tradebook is the only practical source of purchase dates for
# positions bought before the app saw the trades: Kite Connect's /trades
# endpoint returns just the current trading day's book. This service turns that
# CSV into ordinary Trade entries, so the FIFO lot engine and the capital-gains
# estimate can work from real dates.
#
# Deliberate choices:
#
#   * Idempotent. A row is skipped when an existing trade in the account already
#     matches its date, security, signed quantity and price; the Console trade id
#     is also stored on new trades for future matching. Running the same file
#     twice does not double the position.
#   * No security creation. An unknown ISIN/symbol is reported as unresolved
#     rather than inventing a security the price providers cannot price. Kite's
#     holdings sync normally creates them first.
#   * Dry run. The same parse can be previewed without writing anything; the
#     controller uses it before committing if it ever grows a confirm step.
#   * Fees are not in the tradebook. Trade fees stay zero, and the card says the
#     cost basis excludes brokerage; the Console capital-gains statement is the
#     reconciliation source.
class Portfolio::ConsoleTradebook
  REQUIRED_COLUMNS = %w[symbol isin trade_date trade_type quantity price].freeze

  Result = Data.define(:imported, :skipped, :unresolved, :errors) do
    def imported_count
      imported.size
    end

    def ok?
      errors.empty?
    end
  end

  attr_reader :family, :account, :csv, :dry_run

  def initialize(family:, account:, csv:, dry_run: false)
    @family = family
    @account = account
    @csv = csv
    @dry_run = dry_run
  end

  def call
    parsed = parse
    return parsed if parsed.is_a?(Result)

    imported = []
    skipped = 0
    unresolved = []
    errors = []

    parsed.each_with_index do |row, index|
      line = index + 2 # header is line 1

      trade_type = row["trade_type"].to_s.strip.downcase
      unless %w[buy sell].include?(trade_type)
        errors << "line #{line}: unknown trade type #{row['trade_type'].inspect}"
        next
      end

      qty = parse_decimal(row["quantity"])
      price = parse_decimal(row["price"])
      date = parse_date(row["trade_date"])
      if qty.nil? || qty.zero? || price.nil? || date.nil?
        errors << "line #{line}: quantity, price or date could not be read"
        next
      end

      security = resolve_security(row["isin"], row["symbol"])
      if security.nil?
        unresolved << row["symbol"].to_s.strip.presence || row["isin"].to_s.strip
        next
      end

      signed_qty = trade_type == "buy" ? qty : -qty
      if duplicate?(security, date, signed_qty, price)
        skipped += 1
        next
      end

      imported << { security: security, date: date, qty: signed_qty, price: price, type: trade_type }
      next if dry_run

      import_trade!(security, date, signed_qty, price, trade_type, row["trade_id"], errors, line)
    end

    Result.new(imported: imported, skipped: skipped, unresolved: unresolved.uniq, errors: errors)
  end

  private
    def parse
      content = csv.respond_to?(:read) ? csv.read : csv.to_s
      table = CSV.parse(content, headers: true)

      headers = table.headers.compact.map { |header| normalize_header(header) }
      missing = REQUIRED_COLUMNS - headers
      return Result.new(imported: [], skipped: 0, unresolved: [], errors: [ "missing columns: #{missing.join(', ')}" ]) if missing.any?

      table.map do |row|
        row.to_h.transform_keys { |key| normalize_header(key) }
      end
    rescue CSV::MalformedCSVError, ArgumentError => e
      Result.new(imported: [], skipped: 0, unresolved: [], errors: [ "could not read CSV: #{e.message}" ])
    end

    def normalize_header(header)
      header.to_s.strip.downcase.gsub(/[^a-z0-9]+/, "_").delete_prefix("_").delete_suffix("_")
    end

    def resolve_security(isin, symbol)
      isin = isin.to_s.strip.presence
      symbol = symbol.to_s.strip.presence

      if isin
        security = Security.find_by(isin: isin)
        return security if security
      end
      return nil if symbol.nil?

      family_scope = Security.where("UPPER(ticker) = ?", symbol.upcase)
      family_scope.where(country_code: "IN").first || family_scope.first
    end

    def duplicate?(security, date, signed_qty, price)
      Entry
        .joins("INNER JOIN trades ON trades.id = entries.entryable_id AND entries.entryable_type = 'Trade'")
        .where(account_id: account.id, date: date, excluded: false)
        .where(trades: { security_id: security.id, qty: signed_qty, price: price })
        .exists?
    end

    def import_trade!(security, date, signed_qty, price, trade_type, trade_id, errors, line)
      ActiveRecord::Base.transaction do
        trade = Trade.create!(
          security: security,
          qty: signed_qty,
          price: price,
          fee: 0,
          currency: account.currency,
          investment_activity_label: trade_type == "buy" ? "Buy" : "Sell",
          extra: { "console_trade_id" => trade_id.presence, "source" => "console_tradebook" }.compact
        )

        Entry.create!(
          account: account,
          entryable: trade,
          amount: (signed_qty * price).round(2),
          currency: account.currency,
          date: date,
          name: "#{trade_type == "buy" ? "Buy" : "Sell"} #{signed_qty.abs} #{security.ticker}"
        )
      end
    rescue ActiveRecord::RecordInvalid => e
      errors << "line #{line}: #{e.message}"
    end

    def parse_decimal(value)
      BigDecimal(value.to_s.strip)
    rescue ArgumentError
      nil
    end

    def parse_date(value)
      Date.parse(value.to_s.strip)
    rescue ArgumentError, TypeError
      nil
    end
end
