# frozen_string_literal: true

# Registers Kite's recurring jobs with sidekiq-cron, following the same shape as
# AutoSyncScheduler (see config/initializers/sidekiq.rb, which calls .sync! on
# Sidekiq startup).
#
# Upserted rather than defined in config/schedule.yml because the portfolio sync
# is useless -- and should not run at all -- until a family has completed the
# daily Zerodha login and holds a live session token. The job entries are static,
# but the work they enqueue is gated by KiteItem.syncable, so registering them
# unconditionally is safe and avoids a boot-order dependency on user data.
class Kite::SyncScheduler
  PORTFOLIO_JOB = "kite_sync_portfolio"
  TOKEN_EXPIRY_JOB = "kite_check_token_expiry"

  # Kite allows ~3 req/sec per key and Client self-throttles below that, so these
  # intervals are about not burning quota against other integrations on the same
  # process, not about Kite's limits.
  PORTFOLIO_CRON = "*/20 * * * *"
  TOKEN_EXPIRY_CRON = "*/15 * * * *"

  def self.sync!
    upsert_job(
      name: PORTFOLIO_JOB,
      cron: PORTFOLIO_CRON,
      job_class: "Kite::BulkSyncSchedulerJob",
      description: "Sync Zerodha holdings, Coin MF and trades for all syncable Kite items"
    )

    upsert_job(
      name: TOKEN_EXPIRY_JOB,
      cron: TOKEN_EXPIRY_CRON,
      job_class: "Kite::CheckTokenExpiryJob",
      description: "Proactively flag expired Kite sessions as requires_update"
    )
  end

  # `job_class`, not `class`: a keyword parameter named `class` can't be
  # referenced as a bare identifier (`class: class` parses the value as the
  # `class` keyword), so naming it that is a syntax error. The keyword passed on
  # to Sidekiq::Cron::Job.create is still `class:`.
  def self.upsert_job(name:, cron:, job_class:, description:)
    job = Sidekiq::Cron::Job.create(
      name: name,
      cron: cron,
      class: job_class,
      active_job: true,
      queue: "scheduled",
      description: description
    )

    if job.nil? || (job.respond_to?(:valid?) && !job.valid?)
      error_msg = job.respond_to?(:errors) ? job.errors.to_a.join(", ") : "unknown error"
      Rails.logger.error("[Kite::SyncScheduler] Failed to create cron job #{name}: #{error_msg}")
      raise StandardError, "Failed to create Kite sync schedule #{name}: #{error_msg}"
    end

    Rails.logger.info("[Kite::SyncScheduler] Created cron job #{name} with schedule: #{cron}")
    job
  end
  private_class_method :upsert_job
end
