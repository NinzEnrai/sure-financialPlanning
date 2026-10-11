# frozen_string_literal: true

class KiteItem < ApplicationRecord
  belongs_to :family
  has_many :kite_accounts, dependent: :destroy
  has_many :linked_accounts, through: :kite_accounts

  encrypts :api_key, :api_secret, :access_token

  STATUSES = %w[pending_auth active needs_reauth rate_limited error disabled].freeze
  validates :status, inclusion: { in: STATUSES }

  def self.filter_attributes
    super + %w[api_key api_secret access_token]
  end

  def token_valid?
    access_token.present? && access_token_expires_at.present? && access_token_expires_at.future?
  end

  def mark_needs_reauth!(reason: nil)
    update!(status: "needs_reauth", last_error: reason, access_token: nil, access_token_expires_at: nil)
  end

  def mark_active!
    update!(status: "active", last_error: nil)
  end

  def record_sync!(kind: :holdings)
    touch(kind == :mf ? :last_mf_synced_at : :last_synced_at)
  end

  def equity_account
    kite_accounts.find_or_create_by!(segment: "equity") { |a| a.name = "Zerodha Equity" }
  end

  def mutual_fund_account
    kite_accounts.find_or_create_by!(segment: "mutual_fund") { |a| a.name = "Zerodha Coin (Mutual Funds)" }
  end

  # Retrieve all active Sure accounts linked through this connection
  def accounts
    kite_accounts
      .includes(account_provider: :account)
      .filter_map(&:current_account)
      .uniq
  end

  # Check if at least one sub-account is linked to a Sure account
  def has_completed_initial_setup?
    accounts.any?
  end
end