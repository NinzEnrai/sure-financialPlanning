# frozen_string_literal: true

# Orchestrates one full Kite sync for an item: holdings, positions, MF holdings, and trade
# history. Mirrors the role `SnaptradeItem::Importer` plays for `import_latest_snaptrade_data`.
#
# `sync:` is accepted and threaded through so this plugs into the existing `Sync` record
# (status/stats/window dates) if `Syncable` expects importers to report progress onto it --
# exact interface TBD pending `syncable.rb` (see KiteItem's class comment).
class KiteItem::Importer
  def initialize(kite_item, sync: nil)
    @kite_item = kite_item
    @sync = sync
  end

  def import
    equity_account = kite_item.equity_kite_account
    mf_account = kite_item.mutual_fund_kite_account

    Provider::Kite::HoldingsSync.new(kite_item, equity_account).call
    Provider::Kite::TradeImporter.new(kite_item, equity_account).call
    Provider::Kite::MutualFundSync.new(kite_item, mf_account).call

    kite_item.mark_active!
  rescue Provider::Kite::Client::AuthenticationExpired
    # KiteItem already moved to requires_update inside the client; nothing further to do.
  rescue Provider::Kite::Client::RateLimitExceeded => e
    Rails.logger.warn("KiteItem::Importer##{kite_item.id} rate limited: #{e.message}")
    raise # let the job-level retry/backoff handle it
  end

  private

  attr_reader :kite_item, :sync
end
