# frozen_string_literal: true

# Holds one family's Zerodha Kite Connect credentials + daily session state.
#
# ASSUMPTION TO VERIFY: `belongs_to :family`. If Sure's current provider connections
# (e.g. PlaidItem) hang off `User` instead of `Family`, mirror that instead for consistency.
class KiteConnection < ApplicationRecord
  belongs_to :family

  # Rails 7 ActiveRecord::Encryption. Requires `config/credentials.yml.enc` (or env vars) to
  # define active_record_encryption.primary_key / deterministic_key / key_derivation_salt --
  # generate via `bin/rails db:encryption:init` if not already present in this app.
  encrypts :api_key, :api_secret, :access_token

  STATUSES = %w[pending_auth active needs_reauth rate_limited error disabled].freeze
  validates :status, inclusion: { in: STATUSES }

  # Never allow these to leak into logs, error trackers, or `inspect` output.
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
end
