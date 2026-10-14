# frozen_string_literal: true

module Kite
  # Zerodha redirects here after the daily login. This URL has to be registered
  # as the "Redirect URL" on the user's Kite Connect developer app.
  class CallbacksController < ApplicationController
    # Zerodha redirects the user's browser straight here, so there is no
    # signed-in session to rely on the way an in-app OAuth callback has one.
    # `request_token` is the only proof of the round trip, and Provider::Kite's
    # checksum exchange (api_key + request_token + api_secret) is what actually
    # validates it, so this action authenticates by possession of the registered
    # callback URL plus the shared secret -- not by cookie.
    skip_before_action :verify_authenticity_token, only: :show
    before_action :require_admin!

    def show
      # Find-or-create rather than find. Credentials now come from the
      # environment, so nothing creates the KiteItem before this point -- a
      # plain find left item nil and the callback dead on arrival.
      item = Current.family.kite_item || Current.family.create_kite_item!(name: "Zerodha")

      if params[:status] == "success" && params[:request_token].present?
        Provider::Kite::Authenticator.new(item).exchange_request_token!(params[:request_token])
        auto_provision_accounts!(item)
        Kite::SyncPortfolioJob.perform_later(item.id)
        redirect_to settings_providers_path, notice: t(".connected")
      else
        item.update(status: :requires_update, last_error: params[:message].presence || t(".cancelled"))
        redirect_to settings_providers_path, alert: t(".login_failed", message: params[:message])
      end
    rescue Provider::Kite::Client::KiteApiError => e
      redirect_to settings_providers_path, alert: t(".login_failed", message: e.message)
    end

    private
      # First-connect convenience: create the two Investment accounts a fresh
      # Zerodha connection needs, rather than making the user pre-create empty
      # ones. Both segments are hardcoded to Investment, so no accountable
      # constantize is involved here.
      #
      # Each create+link runs in its own transaction, matching
      # QuestradeItemsController: a failed ensure_account_provider! must roll the
      # account back rather than leave an orphan manual account behind.
      def auto_provision_accounts!(item)
        { "equity" => "Zerodha Equity", "mutual_fund" => "Zerodha Coin (Mutual Funds)" }.each do |segment, label|
          kite_account = item.kite_accounts.find_or_create_by!(segment: segment) { |a| a.name = label }
          next if kite_account.current_account.present?

          ActiveRecord::Base.transaction do
            account = Current.family.accounts.create!(
              name: label,
              balance: kite_account.current_balance || 0,
              currency: kite_account.currency || "INR",
              accountable: Investment.new
            )
            kite_account.ensure_account_provider!(account)
          end
        end
      end
  end
end
