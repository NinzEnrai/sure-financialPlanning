# frozen_string_literal: true

module Provider
  module Kite
    # Handles the Kite Connect login handshake:
    #   1. #login_url            -> send the user here
    #   2. Zerodha redirects back to your registered redirect_url with ?request_token=...&status=success
    #   3. #exchange_request_token!(request_token) -> stores the day's access_token
    #
    # See https://kite.trade/docs/connect/v3/user/#login-flow for the authoritative spec --
    # verify checksum/field names against current docs before shipping, APIs do drift.
    class Authenticator
      LOGIN_BASE = "https://kite.zerodha.com/connect/login"
      TOKEN_PATH = "/session/token"

      def initialize(kite_item)
        @connection = kite_item
      end

      def login_url
        "#{LOGIN_BASE}?v=3&api_key=#{CGI.escape(connection.api_key)}"
      end

      # Call from the OAuth-style callback controller once Zerodha redirects back with
      # `request_token`. Raises Provider::Kite::Client::KiteApiError on failure.
      def exchange_request_token!(request_token)
        checksum = Digest::SHA256.hexdigest(
          "#{connection.api_key}#{request_token}#{connection.api_secret}"
        )

        client = Client.new(connection)
        response = client.post(Authenticator::TOKEN_PATH,
          api_key: connection.api_key,
          request_token: request_token,
          checksum: checksum)

        data = response["data"]
        connection.update!(
          access_token: data["access_token"],
          kite_user_id: data["user_id"],
          access_token_issued_at: Time.current,
          # Kite tokens die at the next day's ~6am IST login-window reset; store a conservative
          # same-day-midnight-IST expiry so we proactively prompt re-auth rather than discover
          # a 403 mid-sync. Adjust if Zerodha's docs specify an exact expiry you want to trust instead.
          access_token_expires_at: Time.current.in_time_zone("Asia/Kolkata").end_of_day.utc,
          status: "active",
          last_error: nil
        )
        connection
      end

      private

      attr_reader :connection
    end
  end
end
