# frozen_string_literal: true

# Drives one Kite sync. `Syncable` resolves this via `self.class::Syncer` and
# calls `#perform_sync(sync)`, which is why KiteItem itself does NOT define a
# `perform_sync` -- its `import_latest_kite_data` is the import half of this
# sequence, called from here rather than by the sync machinery directly.
#
# Mirrors SnaptradeItem::Syncer's phase structure, minus the per-account balance
# scheduling: Kite holdings land as Holdings rather than transactions, so there
# are no account balances to recompute from a sync window.
class KiteItem::Syncer
  include SyncStats::Collector

  attr_reader :kite_item

  def initialize(kite_item)
    @kite_item = kite_item
  end

  def perform_sync(sync)
    Rails.logger.info "KiteItem::Syncer - Starting sync for item #{kite_item.id}"

    # A token that has already gone stale is reported as needing a re-login
    # rather than retried -- Kite's 403 on an expired session is a deliberate
    # answer, not a transient fault, so backing off would just burn the window.
    unless kite_item.credentials_configured?
      raise StandardError, "Kite credentials are not configured"
    end

    # Phase 1: Import holdings, Coin funds and trade history from Kite
    sync.update!(status_text: "Importing portfolio from Zerodha...") if sync.respond_to?(:status_text)
    kite_item.import_latest_kite_data(sync: sync)

    # Phase 2: Collect setup statistics
    finalize_setup_counts(sync)

    # Phase 3: Collect transaction, trades and holdings statistics
    linked_kite_accounts = kite_item.linked_kite_accounts.includes(account_provider: :account)
    if linked_kite_accounts.any?
      account_ids = linked_kite_accounts.filter_map { |ka| ka.current_account&.id }
      collect_transaction_stats(sync, account_ids: account_ids, source: "kite")
      collect_trades_stats(sync, account_ids: account_ids, source: "kite")
      collect_holdings_stats(sync, holdings_count: count_holdings, label: "processed")
    end

    # Phase 4: Mark sync health
    kite_item.update!(status: :good) if kite_item.requires_update?
    collect_health_stats(sync, errors: nil)
  rescue Provider::Kite::Client::AuthenticationExpired => e
    # KiteItem was already flipped to requires_update inside the client.
    collect_health_stats(sync, errors: [ { message: e.message, category: "auth_error" } ])
    raise
  rescue Provider::Kite::Client::RateLimitExceeded => e
    # Transient: let the job retry with its backoff.
    collect_health_stats(sync, errors: [ { message: e.message, category: "rate_limited" } ], rate_limited: true)
    raise
  rescue => e
    collect_health_stats(sync, errors: [ { message: e.message, category: "sync_error" } ])
    raise
  end

  # Public: called by Sync after finalization
  def perform_post_sync
    # no-op
  end

  private
    def count_holdings
      kite_item.kite_accounts.sum { |ka| Array(ka.raw_holdings_payload).size }
    end

    def finalize_setup_counts(sync)
      sync.update!(status_text: "Checking account configuration...") if sync.respond_to?(:status_text)

      # KiteAccount#current_account is what collect_setup_stats probes by
      # default, so no linked_check override is needed here.
      collect_setup_stats(sync, provider_accounts: kite_item.kite_accounts)

      unlinked_count = kite_item.kite_accounts.count - kite_item.linked_kite_accounts.count
      return unless unlinked_count.positive?

      sync.update!(status_text: "#{unlinked_count} accounts need setup...") if sync.respond_to?(:status_text)
    end
end
