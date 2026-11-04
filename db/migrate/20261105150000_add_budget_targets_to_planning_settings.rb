class AddBudgetTargetsToPlanningSettings < ActiveRecord::Migration[8.1]
  def change
    # The 50/30/20 split is a starting point, not a law. These columns let a
    # household set its own shares; the model requires them to total 100, and
    # the analyzer scores each bucket against whatever is stored.
    add_column :planning_settings, :needs_target_pct, :integer, default: 50, null: false
    add_column :planning_settings, :wants_target_pct, :integer, default: 30, null: false
    add_column :planning_settings, :savings_target_pct, :integer, default: 20, null: false

    add_check_constraint :planning_settings,
      "needs_target_pct BETWEEN 0 AND 100 AND wants_target_pct BETWEEN 0 AND 100 AND savings_target_pct BETWEEN 0 AND 100",
      name: "planning_settings_budget_targets_range"
  end
end
