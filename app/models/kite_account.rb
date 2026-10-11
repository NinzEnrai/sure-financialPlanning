# frozen_string_literal: true

# Mirrors SnaptradeAccount: links to a Sure `Account` via the generic `account_providers`
# polymorphic join (provider_type: "KiteAccount", provider_id: id, account_id: <Account>).
class KiteAccount < ApplicationRecord
  include CurrencyNormalizable, Encryptable

  if encryption_ready?
    encrypts :raw_payload
    encrypts :raw_holdings_payload
  end

  belongs_to :kite_item
  has_one :family, through: :kite_item

  has_one :account_provider, as: :provider, dependent: :destroy
  has_one :linked_account, through: :account_provider, source: :account

  SEGMENTS = %w[equity mutual_fund].freeze
  validates :segment, inclusion: { in: SEGMENTS }
  validates :name, :currency, presence: true

  def current_account
    linked_account
  end

  # Same idempotent ensure-link pattern as SnaptradeAccount#ensure_account_provider!.
  def ensure_account_provider!(account = nil)
    if account_provider.present?
      account_provider.update!(account: account) if account && account_provider.account_id != account.id
      return account_provider
    end

    acct = account || current_account
    return nil unless acct

    provider = AccountProvider
      .find_or_initialize_by(provider_type: "KiteAccount", provider_id: id)
      .tap do |p|
        p.account = acct
        p.save!
      end

    reload_account_provider
    provider
  rescue => e
    Rails.logger.warn("KiteAccount##{id}: failed to ensure AccountProvider link: #{e.class} - #{e.message}")
    nil
  end

  def upsert_from_kite!(margins_or_profile_data)
    update!(
      current_balance: margins_or_profile_data["net"],
      currency: "INR",
      account_status: "active",
      raw_payload: margins_or_profile_data
    )
  end

  def upsert_holdings_snapshot!(holdings_data)
    update!(raw_holdings_payload: holdings_data, last_holdings_sync: Time.current)
  end

  def kite_client
    kite_item.kite_client
  end
end
