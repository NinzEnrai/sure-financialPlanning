# frozen_string_literal: true

# Merge into config/routes.rb inside the existing `Rails.application.routes.draw do ... end`
# block, nested wherever Sure currently nests `authenticated :user do ... end` or similar
# auth-scoped routes for the dashboard/settings.

# --- Phase 2: Zerodha Kite Connect ---
# Route helper names stay `kite_connection` for readability even though the model is `KiteItem`
# (matches `resource :kite_connection, controller: "kite_connections"` idiom).
namespace :settings do
  resource :kite_connection, only: %i[edit update destroy], controller: "kite_connections" do
    get :connect, on: :member   # redirects to Zerodha login
  end
end
namespace :kite do
  get "callback", to: "callbacks#show"   # register as Kite Connect app's Redirect URL
end

# --- Phase 3: Financial Planning tab ---
resource :financial_planning, only: [:index], controller: "financial_planning" do
  get  :savings_rate
  get  :fire_simulator
  get  "goals/:id/projection", action: :goal_projection, as: :goal_projection
  post :create_goal
end
