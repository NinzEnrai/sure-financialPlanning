# frozen_string_literal: true

module Kite
  # Registered as the "Redirect URL" in the user's Kite Connect developer app, e.g.
  # https://yourdomain.com/kite/callback
  class CallbacksController < ApplicationController
    def show
      item = current_family.kite_item

      if params[:status] == "success" && params[:request_token].present?
        Provider::Kite::Authenticator.new(item).exchange_request_token!(params[:request_token])
        auto_provision_accounts!(item)
        Kite::SyncPortfolioJob.perform_later(item.id)
        redirect_to settings_kite_connection_path, notice: "Zerodha connected! Your portfolio is syncing now."
      else
        item&.update(status: :requires_update, last_error: params[:message] || "Login was cancelled or failed")
        redirect_to settings_kite_connection_path, alert: "Couldn't connect to Zerodha: #{params[:message]}"
      end
    rescue Provider::Kite::Client::KiteApiError => e
      redirect_to settings_kite_connection_path, alert: "Zerodha rejected the connection: #{e.message}"
    end

    private

    # First-connect convenience: auto-create the two Investment accounts a fresh Kite connection
    # needs, same way Plaid/SnapTrade presumably auto-provision accounts on first link rather than
    # making the user pre-create empty ones. ASSUMPTION TO VERIFY: `Account.create!` shape here --
    # I don't have `app/models/account.rb` so I'm guessing at required attributes (`name`,
    # `currency`, `accountable: Investment.new`, `family:`). If accounts need a `balance` or
    # `classification` set at creation, or go through an `Account::Creator` service object instead
    # of a bare `.create!` (common in apps with this many account types), swap this out for that.
    def auto_provision_accounts!(item)
      { "equity" => "Zerodha Equity", "mutual_fund" => "Zerodha Coin (Mutual Funds)" }.each do |segment, label|
        kite_account = item.kite_accounts.find_or_create_by!(segment: segment) { |a| a.name = label }
        next if kite_account.current_account

        account = current_family.accounts.create!(name: label, currency: "INR", accountable: Investment.new)
        kite_account.ensure_account_provider!(account)
      end
    end
  end
end
