class AddRetirementAgeToPlanningSettings < ActiveRecord::Migration[8.1]
  def change
    # The age the household plans to stop working. Used by the retirement
    # stress test; the FIRE target itself does not depend on it.
    add_column :planning_settings, :retirement_age, :integer, default: 60, null: false

    add_check_constraint :planning_settings,
      "retirement_age BETWEEN 30 AND 90",
      name: "planning_settings_retirement_age_range"
  end
end
