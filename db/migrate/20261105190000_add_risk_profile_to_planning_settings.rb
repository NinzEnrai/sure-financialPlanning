class AddRiskProfileToPlanningSettings < ActiveRecord::Migration[8.1]
  def change
    # Optional: a household that has not answered has not been forced into a
    # profile. The value guides the allocation card's equity range only; it is
    # never used to place a trade.
    add_column :planning_settings, :risk_profile, :string

    add_check_constraint :planning_settings,
      "risk_profile IS NULL OR risk_profile IN ('conservative', 'moderate', 'aggressive')",
      name: "planning_settings_risk_profile_check"
  end
end
