# frozen_string_literal: true

# Renamed from 20261012120000 after upstream published its own migration with
# that version: Rails rejects two migration files sharing a version. Databases
# that ran the original migration already recorded 20261012120000, so this file
# can be pending while the table already exists -- hence if_not_exists.
class CreatePlanningSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :planning_settings, id: :uuid, if_not_exists: true do |t|
      t.references :family, type: :uuid, null: false, foreign_key: true, index: { unique: true }

      # Safe withdrawal rate for the FIRE target. Defaults to the 4% rule, which
      # is the figure the widget's 25x multiplier is derived from.
      t.decimal :fire_withdrawal_rate_pct, precision: 5, scale: 2, null: false, default: 4.0

      # Nominal annual return used by the 10-year wealth projection. Conservative
      # by default; a family saving for a specific horizon can raise it.
      t.decimal :annual_growth_rate_pct, precision: 5, scale: 2, null: false, default: 7.0

      # Per-category overrides for the 50/30/20 analyzer, keyed by category id
      # and valued "needs" / "wants" / "savings". Only categories the family has
      # overridden are stored; everything else falls back to the default mapping.
      t.jsonb :category_buckets, null: false, default: {}

      t.timestamps
    end
  end
end
