# frozen_string_literal: true

module Kite
  class SyncMutualFundsJob < ApplicationJob
    queue_as :integrations
    sidekiq_options retry: 5, queue: :integrations
    sidekiq_retry_in { |count, _e| 30 * (4**count) }
    discard_on ActiveRecord::RecordNotFound

    def perform(kite_item_id)
      connection = KiteItem.find(kite_item_id)
      return unless connection.status.in?(%w[active pending_auth])

      Provider::Kite::MutualFundSync.new(connection).call
    rescue Provider::Kite::Client::RateLimitExceeded
      connection.update!(status: "rate_limited")
      raise
    end
  end
end
