# frozen_string_literal: true

# Kite's provider layer: the daily login handshake and the thin HTTP client.
#
# Deliberately different from SnaptradeItem::Provided. Kite Connect has no
# long-lived OAuth grant to manage -- Zerodha hands back a single-day session
# token via a redirect, and the app's api_key/api_secret never leave the family
# that entered them. So there is no `before_destroy` token revocation here the way
# SnaptradeItem::Provided has; unlinking is handled by KiteItem::Unlinking
# instead.
module KiteItem::Provided
  extend ActiveSupport::Concern

  # URL to send the user to for the daily Zerodha login.
  def login_url
    kite_authenticator.login_url
  end

  # Exchange the `request_token` from Zerodha's redirect for the day's access
  # token. The Authenticator persists the token and its expiry; this marks the
  # item usable on the way out so a successful login never leaves the item
  # sitting in `requires_update`.
  def complete_request_token_exchange!(request_token:)
    kite_authenticator.exchange_request_token!(request_token)
    mark_active!
    self
  end

  # Nil when the item has no credentials yet, so callers can skip the request
  # rather than send one that would come back 401.
  def kite_provider
    return nil unless credentials_configured?

    kite_client
  end

  # Raw equity holdings payload. Returns a Hash as Kite sends it.
  def fetch_holdings
    require_provider!("equity holdings")
    kite_client.get("/portfolio/holdings")
  rescue Provider::Kite::Client::KiteApiError => e
    Rails.logger.error "KiteItem #{id} - Failed to fetch holdings: #{e.message}"
    raise
  end

  # Raw Zerodha Coin mutual fund holdings payload.
  def fetch_mutual_fund_holdings
    require_provider!("mutual fund holdings")
    kite_client.get("/mf/holdings")
  rescue Provider::Kite::Client::KiteApiError => e
    Rails.logger.error "KiteItem #{id} - Failed to fetch mutual fund holdings: #{e.message}"
    raise
  end

  private
    def kite_authenticator
      @kite_authenticator ||= Provider::Kite::Authenticator.new(self)
    end

    # Fails loudly rather than letting Kite return a confusing 401 with an
    # "invalid api_key" message when the real problem is an unset credential.
    def require_provider!(what)
      raise StandardError, "Kite credentials are not configured (cannot fetch #{what})" unless kite_provider
    end
end
