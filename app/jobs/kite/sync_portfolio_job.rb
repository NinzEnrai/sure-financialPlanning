# frozen_string_literal: true

module Kite
  class SyncPortfolioJob < ApplicationJob
    queue_as :integrations

    # Sidekiq-native retry with exponential backoff; on top of the client's own in-request
    # backoff for 429s, this handles whole-job failures (e.g. transient network issues,
    # Sidekiq process restarts mid-sync).
    sidekiq_options retry: 5, queue: :integrations

    sidekiq_retry_in do |count, _exception|
      # 30s, 2min, 8min, 32min, 128min -- plenty of room for a transient Kite outage to clear
      30 * (4**count)
    end

    discard_on ActiveRecord::RecordNotFound

    def perform(kite_item_id)
      connection = KiteItem.find(kite_item_id)
      return unless connection.status.in?(%w[active pending_auth])

      Provider::Kite::HoldingsSync.new(connection).call
      Provider::Kite::TradeImporter.new(connection).call
    rescue Provider::Kite::Client::RateLimitExceeded
      connection.update!(status: "rate_limited")
      raise # let Sidekiq's backoff handle the re-run
    end
  end
end
