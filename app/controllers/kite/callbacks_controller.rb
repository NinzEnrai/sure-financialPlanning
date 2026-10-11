# frozen_string_literal: true

module Kite
  # Registered as the "Redirect URL" in the user's Kite Connect developer app, e.g.
  # https://yourdomain.com/kite/callback
  class CallbacksController < ApplicationController
    def show
      item = current_family.kite_item

      if params[:status] == "success" && params[:request_token].present?
        Provider::Kite::Authenticator.new(item).exchange_request_token!(params[:request_token])
        Kite::SyncPortfolioJob.perform_later(item.id)
        Kite::SyncMutualFundsJob.perform_later(item.id)
        redirect_to settings_kite_connection_path, notice: "Zerodha connected! Your portfolio is syncing now."
      else
        item&.update(status: "error", last_error: params[:message] || "Login was cancelled or failed")
        redirect_to settings_kite_connection_path, alert: "Couldn't connect to Zerodha: #{params[:message]}"
      end
    rescue Provider::Kite::Client::KiteApiError => e
      redirect_to settings_kite_connection_path, alert: "Zerodha rejected the connection: #{e.message}"
    end
  end
end
