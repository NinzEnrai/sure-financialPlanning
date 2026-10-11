# frozen_string_literal: true

module Kite
  # Thin wrapper job -- the real orchestration now lives in KiteItem#import_latest_kite_data /
  # KiteItem::Importer, matching SnaptradeItem's shape. If `Syncable` (see KiteItem's class
  # comment) turns out to drive sync scheduling generically the way `account.sync_later` does for
  # Account, this job may become unnecessary -- kept for now since enqueueing per-item work
  # explicitly is still a reasonable fallback, and it's where the Sidekiq-level retry/backoff for
  # whole-job failures lives (distinct from the client's own per-request 429 backoff).
  class SyncPortfolioJob < ApplicationJob
    queue_as :integrations
    sidekiq_options retry: 5, queue: :integrations
    sidekiq_retry_in { |count, _e| 30 * (4**count) }
    discard_on ActiveRecord::RecordNotFound

    def perform(kite_item_id)
      kite_item = KiteItem.find(kite_item_id)
      return if kite_item.scheduled_for_deletion?

      kite_item.import_latest_kite_data
    rescue Provider::Kite::Client::RateLimitExceeded
      raise # let Sidekiq's backoff handle the re-run
    end
  end
end
