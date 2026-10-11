# frozen_string_literal: true

module Settings
  # Mirrors whatever `Settings::*Controller` pattern already exists for e.g. SnapTrade/Plaid
  # connections -- adjust `before_action`/auth filters to match ApplicationController.
  class KiteConnectionsController < ApplicationController
    before_action :set_item, only: %i[edit update destroy connect]

    def edit
      @item ||= current_family.build_kite_item
    end

    # Step 1: user submits their Kite Connect app's API key + secret.
    def update
      @item.assign_attributes(kite_item_params)
      @item.status = "pending_auth"
      if @item.save
        redirect_to settings_kite_connection_path, notice: "Credentials saved. Now connect your Zerodha account."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Step 2: redirect to Zerodha's login page.
    def connect
      redirect_to Provider::Kite::Authenticator.new(@item).login_url, allow_other_host: true
    end

    def destroy
      @item.destroy
      redirect_to settings_kite_connection_path, notice: "Zerodha connection removed."
    end

    private

    def set_item
      @item = current_family.kite_item
    end

    def kite_item_params
      params.require(:kite_item).permit(:api_key, :api_secret)
    end
  end
end
