class AddFireVariantToPlanningSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :planning_settings, :fire_variant, :string, default: "standard", null: false

    # A target *year*, not an age. Turning an age into a date needs the family's
    # birth date, which Sure does not record, and an age would also drift --
    # "40" saved in 2026 is 41 in 2027, quietly moving the goalposts every year.
    # A year is absolute, so it means the same thing whenever it is read.
    add_column :planning_settings, :fire_target_year, :integer

    # A static range rather than one relative to the current year, so the
    # constraint stays valid as a check constraint. The meaningful bounds --
    # not in the past, not absurdly far out -- are enforced by the model, which
    # can read the current date.
    add_check_constraint :planning_settings,
      "fire_target_year IS NULL OR fire_target_year BETWEEN 2000 AND 2200",
      name: "planning_settings_fire_target_year_range"
  end
end
