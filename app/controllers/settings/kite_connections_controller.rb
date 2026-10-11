# frozen_string_literal: true

module Settings
  # Mirrors whatever `Settings::*Controller` pattern already exists for SnapTrade/Plaid --
  # adjust `before_action`/auth filters to match ApplicationController.
  #
  # ASSUMPTION: `current_family.kite_item` as a `has_one` (one Kite connection per family,
  # matching the unique index on `kite_items.family_id`). Add `has_one :kite_item` to
  # `app/models/family.rb` if it's not already inferred some other way.
  class KiteConnectionsController < ApplicationController
    before_action :set_item, only: %i[edit update destroy connect]

    def edit
      @item ||= current_family.build_kite_item
    end

    # Step 1: user submits their Kite Connect app's API key + secret. Status stays at its
    # "good" default here -- `fully_configured?`/`token_valid?` are what the view should check
    # to decide whether to prompt for Step 2, not `status` (status only distinguishes
    # "working" from "needs attention", same two-value enum as SnaptradeItem).
    def update
      @item.assign_attributes(kite_item_params)
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

    # Mirrors SnaptradeItem#destroy_later -- async cleanup rather than a synchronous destroy,
    # since DestroyJob presumably handles any external-API cleanup without blocking the request.
    def destroy
      @item.destroy_later
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
