# frozen_string_literal: true

# Mirrors SnaptradeItem's shape closely -- SnapTrade is the closest existing analog (a live
# brokerage-holdings provider, not a bank-account aggregator like Plaid/SimpleFin).
#
# `Syncable` resolves `perform_sync` through `KiteItem::Syncer`, which in turn calls
# `import_latest_kite_data` below. This model deliberately does NOT define
# `perform_sync` itself -- doing so would shadow the concern's delegation to the
# syncer and silently skip the setup/holdings stats collection.
#
# The per-provider concerns (`Provided`, `Unlinking`, `Syncer`) and
# `SyncCompleteEvent` all ship alongside this file. `kite_items` is one row per
# family, holding only the day's Zerodha session token; the single Zerodha login
# covers both equity and Coin mutual funds, which split into two KiteAccounts
# because they map to two separate Sure Investment accounts.
#
# CREDENTIAL STORAGE. The app's api_key/api_secret are deployment-wide, long-lived
# and set once, so they come from the environment (KITE_API_KEY / KITE_API_SECRET)
# and are never written to the database. The reason is backup surface, not
# paranoia: `pg_dump` copies every column, so anything persisted lands in
# /root/sure-backup/*.dump and in any future restore onto another machine, whereas
# /etc/sure/.env does not. They are also long-lived, so a leaked copy stays valid
# indefinitely, unlike the session token.
#
# The daily access_token does live here, because the Sidekiq sync jobs have to
# read it across processes and it is rotated by the browser login every day.
# `Syncable` is deliberately NOT included. Kite syncs are scheduled by sidekiq-cron
# (Kite::SyncScheduler), not by Syncable's sync_later, so its perform_sync /
# broadcast_sync_complete / sync_stats machinery was never on the live path. It
# also shadowed the `last_synced_at` column with a method returning
# latest_completed_sync_record&.completed_at -- which is nil forever here, since
# no Sync is ever created for a KiteItem -- so KiteItem#record_sync! wrote a
# timestamp nothing could read back.
#
# A working Syncer and SyncCompleteEvent are parked in wip/kite/parked/ if a
# future Kite-adjacent provider (or a move back to Syncable scheduling) wants
# them; restore them and re-add `include Syncable` together, since Syncable
# resolves both via self.class::.
class KiteItem < ApplicationRecord
  include Provided, Unlinking, Encryptable, DestroyableLater

  enum :status, { good: "good", requires_update: "requires_update" }, default: :good

  # Never persisted, so nothing to encrypt and no columns to declare. Read
  # through the class so the Client/Authenticator keep calling item.api_key.
  def self.api_key
    ENV["KITE_API_KEY"].presence
  end

  def self.api_secret
    ENV["KITE_API_SECRET"].presence
  end

  def self.credentials_configured?
    api_key.present? && api_secret.present?
  end

  def api_key
    self.class.api_key
  end

  def api_secret
    self.class.api_secret
  end

  # Only the session token is stored, and only non-deterministically -- it is
  # never queried by value, unlike an api_key/api_secret pair.
  if encryption_ready?
    encrypts :access_token
  end

  # The access_token is a live bearer credential: anyone holding it can call the
  # Kite REST API as this user, and the Personal app type carries trading
  # permissions. Rails only filters :password by default, so without this an
  # exception message, an ActiveRecord log line or a console inspect() of the
  # record would print the token in cleartext. Filtering is not encryption --
  # it just keeps the secret out of logs and error trackers.
  def self.filter_attributes
    super + %w[access_token]
  end

  validates :name, presence: true
  # No api_key/api_secret validation: they are not attributes on this record.
  # access_token / kite_user_id are populated after the Zerodha login redirect.

  belongs_to :family
  has_one_attached :logo, dependent: :purge_later

  has_many :kite_accounts, dependent: :destroy
  has_many :linked_accounts, through: :kite_accounts

  scope :active, -> { where(scheduled_for_deletion: false) }
  scope :syncable, -> { active.good.where.not(access_token: [ nil, "" ]) }
  scope :ordered, -> { order(created_at: :desc) }
  scope :needs_update, -> { where(status: :requires_update) }

  def import_latest_kite_data(sync: nil)
    unless token_valid?
      Rails.logger.error "KiteItem #{id} - Cannot import: access token missing or expired"
      mark_needs_reauth!(reason: "Access token missing or expired") unless requires_update?
      raise StandardError, "Kite access token is not valid"
    end

    KiteItem::Importer.new(self, sync: sync).import
  rescue => e
    Rails.logger.error "KiteItem #{id} - Failed to import data: #{e.message}"
    raise
  end

  def kite_client
    @kite_client ||= Provider::Kite::Client.new(self)
  end

  def token_valid?
    access_token.present? && access_token_expires_at.present? && access_token_expires_at.future?
  end

  def mark_needs_reauth!(reason: nil)
    update!(status: :requires_update, last_error: reason, access_token: nil, access_token_expires_at: nil)
  end

  def mark_active!
    update!(status: :good, last_error: nil)
  end

  def record_sync!(kind: :holdings)
    touch(kind == :mf ? :last_mf_synced_at : :last_synced_at)
  end

  # Reads through to the class, so credentials_configured? reflects the
  # environment rather than anything stored on the record.
  def credentials_configured?
    self.class.credentials_configured?
  end

  def fully_configured?
    credentials_configured? && token_valid?
  end

  # Get Sure accounts linked to this Kite item via account_providers (same pattern as
  # SnaptradeItem#accounts).
  def accounts
    kite_accounts
      .includes(account_provider: :account)
      .filter_map { |ka| ka.current_account }
      .uniq
  end

  def linked_kite_accounts
    kite_accounts.joins(:account_provider)
  end

  def equity_kite_account
    kite_accounts.find_or_create_by!(segment: "equity") { |a| a.name = "Zerodha Equity" }
  end

  def mutual_fund_kite_account
    kite_accounts.find_or_create_by!(segment: "mutual_fund") { |a| a.name = "Zerodha Coin (Mutual Funds)" }
  end

  def sync_status_summary
    linked = linked_kite_accounts.count
    total = kite_accounts.count

    if total.zero?
      I18n.t("models.kite_item.sync_status.no_accounts")
    elsif linked == total
      I18n.t("models.kite_item.sync_status.synced", count: linked)
    else
      I18n.t("models.kite_item.sync_status.synced_with_setup", linked: linked, unlinked: total - linked)
    end
  end
end
