# frozen_string_literal: true

namespace :market_data do
  # Backfills daily closing prices for every online security.
  #
  # The daily ImportMarketDataJob only fetches the window its holdings need, so a
  # freshly connected provider starts with a couple of days of history. XIRR, the
  # holdings chart and the tax features all need a series that reaches back to
  # when a position was opened, which is what a one-off backfill provides.
  #
  #   bin/rails "market_data:backfill_prices[24]"
  #
  # Per-request caps differ by provider (Yahoo validates a five-year range), so a
  # longer window is clamped rather than rejected. One security failing is logged
  # and skipped: a partly filled series still beats an aborted run.
  desc "Backfill daily price history for every online security (months, default 24)"
  task :backfill_prices, [ :months ] => :environment do |_task, args|
    months = (args[:months].presence || ENV["MONTHS"]).to_i
    months = 24 if months <= 0

    start_date = [ months.months.ago.to_date, MAX_BACKFILL_YEARS.years.ago.to_date ].max
    end_date = Date.current

    securities = Security.online.order(:ticker)
    puts "Backfilling #{securities.count} securities, #{start_date} to #{end_date}"

    written = 0
    failures = []

    securities.each do |security|
      provider = security.price_data_provider

      if provider.nil?
        puts "  #{security.ticker}: no provider configured, skipped"
        next
      end

      imported, error = security.import_provider_prices(start_date: start_date, end_date: end_date)
      written += imported.to_i

      if error.present?
        failures << [ security.ticker, error ]
        puts "  #{security.ticker}: #{imported} rows, error: #{error.to_s[0, 120]}"
      else
        puts "  #{security.ticker}: #{imported} rows"
      end
    end

    puts "Done. #{written} price rows written, #{failures.size} securities reported an error."
    failures.each { |ticker, error| puts "  FAILED #{ticker}: #{error}" }
  end

  # Yahoo rejects a range wider than five years in one request, so the backfill
  # stops there regardless of what the caller asked for.
  MAX_BACKFILL_YEARS = 5
end
