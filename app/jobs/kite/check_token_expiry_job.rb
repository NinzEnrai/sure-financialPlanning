# frozen_string_literal: true

module Kite
  # Proactively flips any KiteItem whose access_token has passed its stored expiry into
  # `requires_update`, so the UI can show a "reconnect Zerodha" prompt before the next
  # scheduled sync fails on a 403.
  class CheckTokenExpiryJob < ApplicationJob
    queue_as :integrations

    def perform
      KiteItem.good
              .where("access_token_expires_at < ?", Time.current)
              .find_each do |item|
        item.mark_needs_reauth!(reason: "Daily Kite session expired")
        # Hook into whatever notification system Sure already has here.
      end
    end
  end

  # Fans out one SyncPortfolioJob per syncable item, rather than looping inline, so one
  # slow/stuck sync doesn't block the others.
  class BulkSyncSchedulerJob < ApplicationJob
    queue_as :integrations
    def perform
      KiteItem.syncable.find_each { |item| Kite::SyncPortfolioJob.perform_later(item.id) }
    end
  end
end
