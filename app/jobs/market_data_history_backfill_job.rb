# frozen_string_literal: true

# Tops up price history a few securities at a time.
#
# Yahoo throttles hard: a full 24-month backfill of 19 securities exhausts its
# quota after two or three requests, so a single pass cannot finish the job no
# matter how it is spaced. Rather than hammering it nightly, this walks the
# securities with the shallowest history, backfills a small batch, and lets the
# next night continue where it left off. XIRR and the tax features need a series
# reaching back to when a position was opened, and they get there within a week
# without ever being rate limited.
class MarketDataHistoryBackfillJob < ApplicationJob
  queue_as :scheduled

  # Small on purpose: three is roughly what Yahoo tolerates in one burst.
  BATCH_SIZE = 3
  LOOKBACK_MONTHS = 24
  # A series shorter than this is treated as still needing history.
  MEANINGFUL_HISTORY = 1.year

  def perform(batch_size = BATCH_SIZE)
    securities = shallowest(batch_size.to_i.clamp(1, 20))
    return if securities.empty?

    securities.each do |security|
      imported, error = security.import_provider_prices(
        start_date: LOOKBACK_MONTHS.months.ago.to_date,
        end_date: Date.current
      )

      if error.present?
        Rails.logger.warn(
          "[MarketDataHistoryBackfillJob] #{security.ticker}: #{imported} rows, provider error: #{error}"
        )
      else
        Rails.logger.info("[MarketDataHistoryBackfillJob] #{security.ticker}: #{imported} rows")
      end
    end
  end

  private

    # Oldest series first, securities with nothing at all before them. Grouped in
    # SQL because doing it in Ruby reads every price row for every security.
    # Materialized as records: on a grouped relation #size returns a count hash.
    def shallowest(limit)
      Security.online
              .left_joins(:prices)
              .group("securities.id")
              .select("securities.*, MIN(security_prices.date) AS oldest_price")
              .having("MIN(security_prices.date) IS NULL OR MIN(security_prices.date) > ?",
                      MEANINGFUL_HISTORY.ago.to_date)
              .order(Arel.sql("MIN(security_prices.date) ASC NULLS FIRST"))
              .limit(limit)
              .to_a
    end
end
