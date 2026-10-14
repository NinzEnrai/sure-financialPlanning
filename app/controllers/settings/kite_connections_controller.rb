# frozen_string_literal: true

module Settings
  # Zerodha Kite Connect for the signed-in family.
  #
  # There is no credential form here on purpose. The app's api_key/api_secret are
  # deployment-wide, long-lived secrets read from the environment
  # (KITE_API_KEY / KITE_API_SECRET) rather than stored per family -- see the
  # KiteItem class comment for why. This controller's whole job is the daily
  # login hand-off; the token comes back at Kite::CallbacksController.
  class KiteConnectionsController < ApplicationController
    # Admin-only, matching Settings::ProvidersController. Note it is
    # `require_admin!` (defined on ApplicationController), not `ensure_admin`
    # -- the latter is a private method each provider controller defines for
    # itself and is NOT inherited.
    before_action :require_admin!
    before_action :set_item

    def show
    end

    # Step 2: hand off to Zerodha's login page. allow_other_host is required --
    # this is the one redirect that deliberately leaves the app.
    def connect
      unless @item.credentials_configured?
        return redirect_to settings_providers_path, alert: t(".credentials_missing")
      end

      redirect_to Provider::Kite::Authenticator.new(@item).login_url, allow_other_host: true
    end

    # Async cleanup rather than a synchronous destroy, mirroring
    # SnaptradeItemsController: the item owns external state and holdings links.
    def destroy
      @item.destroy_later
      redirect_to settings_providers_path, notice: t(".removed")
    end

    private
      # One item per family (unique index on kite_items.family_id), built rather
      # than found so a family's first visit renders a page instead of 404ing
      # before any login has happened.
      def set_item
        @item = Current.family.kite_item || Current.family.build_kite_item(name: "Zerodha")
      end
  end
end
