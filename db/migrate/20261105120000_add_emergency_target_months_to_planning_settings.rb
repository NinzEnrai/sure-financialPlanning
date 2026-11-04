class AddEmergencyTargetMonthsToPlanningSettings < ActiveRecord::Migration[8.1]
  def change
    # How many months of spending the household wants its cash buffer to cover.
    # Six is the common starting point, but a single-income household may want
    # nine or twelve, and a dual-income one may be comfortable at three. The
    # column is the household's target; the card's health bands stay in code.
    add_column :planning_settings, :emergency_target_months, :integer, default: 6, null: false

    # Static range so this can be a check constraint; the model validates the
    # same bounds, and the form offers 1-12.
    add_check_constraint :planning_settings,
      "emergency_target_months BETWEEN 1 AND 24",
      name: "planning_settings_emergency_target_months_range"
  end
end
