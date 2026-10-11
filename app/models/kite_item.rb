# frozen_string_literal: true

# Mirrors SnaptradeItem's shape closely -- SnapTrade is the closest existing analog (a live
# brokerage-holdings provider, not a bank-account aggregator like Plaid/SimpleFin).
#
# GAP (reduced, not eliminated): `include Syncable, Provided, Unlinking` below is a best-effort
# guess at the concern names based on SnaptradeItem using exactly that line. I don't have their
# source, so I can't confirm the exact method names `Syncable` expects the including class to
# implement (likely something like `perform_sync(sync)`, given the `syncs` table's `syncable_type`/
# `syncable_id` polymorphic columns + `parent_id`/`window_start_date`/`window_end_date`/`sync_stats`).
# `import_latest_kite_data` below is written to be a plausible `perform_sync` body -- share
# `app/models/concerns/syncable.rb` (+ `provided.rb`, `unlinking.rb`, `encryptable.rb`,
# `currency_normalizable.rb`) and I'll wire the method signature exactly instead of guessing.
class KiteItem < ApplicationRecord
  include Syncable, Provided, Unlinking

  enum :status, { good: "good", requires_update: "requires_update" }, default: :good

  def self.encryption_ready?
    creds_ready = Rails.application.credentials.active_record_encryption.present?
    env_ready = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].present? &&
                ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].present? &&
                ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].present?
    creds_ready || env_ready
  end

  # api_key/api_secret: deterministic (Kite's checksum exchange needs to read them back as
  # plaintext-comparable values, same reasoning as SnaptradeItem's client_id/consumer_key).
  # access_token: non-deterministic -- it's a pure secret, never queried by value.
  if encryption_ready?
    encrypts :api_key, deterministic: true
    encrypts :api_secret, deterministic: true
    encrypts :access_token
  end

  validates :name, presence: true
  validates :api_key, :api_secret, presence: true, on: :create
  # kite_user_id / access_token are populated after the Zerodha login redirect, not on create.

  belongs_to :family
  has_one_attached :logo, dependent: :purge_later

  has_many :kite_accounts, dependent: :destroy
  has_many :linked_accounts, through: :kite_accounts

  scope :active, -> { where(scheduled_for_deletion: false) }
  scope :syncable, -> { active.good.where.not(access_token: [nil, ""]) }
  scope :ordered, -> { order(created_at: :desc) }
  scope :needs_update, -> { where(status: :requires_update) }

  def destroy_later
    update!(scheduled_for_deletion: true)
    DestroyJob.perform_later(self)
  end

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

  def credentials_configured?
    api_key.present? && api_secret.present?
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
      I18n.t("kite_item.sync_status.no_accounts")
    elsif linked == total
      I18n.t("kite_item.sync_status.synced", count: linked)
    else
      I18n.t("kite_item.sync_status.synced_with_setup", linked: linked, unlinked: total - linked)
    end
  end
end
