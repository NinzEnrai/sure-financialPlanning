# frozen_string_literal: true

module Kite
  # Runs frequently (every 15-30 min suggested) and proactively flips any connection whose
  # access_token has passed its stored expiry into `needs_reauth`, so the UI can show a
  # "reconnect Zerodha" prompt *before* the next scheduled sync fails with a 403 -- better UX
  # than discovering it reactively.
  class CheckTokenExpiryJob < ApplicationJob
    queue_as :integrations

    def perform
      KiteItem.where(status: "active")
                     .where("access_token_expires_at < ?", Time.current)
                     .find_each do |connection|
        connection.mark_needs_reauth!(reason: "Daily Kite session expired")
        # Hook into whatever notification system Sure already has (e.g. an in-app Notification
        # model, or a mailer) here -- left as a TODO since I don't know that system's interface.
      end
    end
  end
end

# Small fan-out helpers referenced by the schedule above -- enqueue one SyncPortfolioJob /
# SyncMutualFundsJob per active connection rather than looping inline, so one slow/stuck
# sync doesn't block the others and Sidekiq's own concurrency controls apply per-connection.
module Kite
  class BulkSyncSchedulerJob < ApplicationJob
    queue_as :integrations
    def perform
      KiteItem.where(status: "active").find_each do |c|
        Kite::SyncPortfolioJob.perform_later(c.id)
      end
    end
  end

  class BulkMfSyncSchedulerJob < ApplicationJob
    queue_as :integrations
    def perform
      KiteItem.where(status: "active").find_each do |c|
        Kite::SyncMutualFundsJob.perform_later(c.id)
      end
    end
  end
end
