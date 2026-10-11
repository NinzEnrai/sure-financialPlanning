# frozen_string_literal: true

class KiteAccount < ApplicationRecord
  belongs_to :kite_item

  # Linking to core Sure accounts via the polymorphic AccountProvider join table
  has_one :account_provider, as: :provider, dependent: :destroy
  has_one :linked_account, through: :account_provider, source: :account

  validates :name, :segment, presence: true

  # Helper to resolve the linked core Sure account
  def current_account
    linked_account
  end

  # Safe, idempotent join table linker
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
end