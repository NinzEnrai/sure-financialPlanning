# frozen_string_literal: true

class CreateFinancialPlanningTables < ActiveRecord::Migration[7.1]
  def change
    create_table :financial_goals, id: :uuid do |t|
      t.references :family, type: :uuid, null: false, foreign_key: true

      t.string   :name, null: false
      t.string   :goal_type, null: false, default: "custom"
      # emergency_fund | house_down_payment | retirement | education | vehicle | custom

      t.decimal  :target_amount, precision: 19, scale: 4, null: false
      t.date     :target_date, null: false
      t.decimal  :current_amount_override, precision: 19, scale: 4
      # If set, overrides auto-calculating "current progress" from linked_account; useful for
      # goals not represented by a single account (e.g. "retirement" spanning several accounts).

      t.references :linked_account, type: :uuid, foreign_key: { to_table: :accounts }
      t.integer  :priority, default: 0
      t.boolean  :achieved, default: false, null: false

      t.timestamps
    end

    create_table :planning_settings, id: :uuid do |t|
      t.references :family, type: :uuid, null: false, foreign_key: true, index: { unique: true }

      t.decimal :expected_annual_return_pct, precision: 5, scale: 2, default: 10.0   # CAGR assumption, e.g. 10% for Indian equity-heavy portfolios
      t.decimal :expected_inflation_pct, precision: 5, scale: 2, default: 6.0        # long-run India CPI assumption
      t.decimal :fire_annual_expenses, precision: 19, scale: 4                       # if blank, derive from trailing 12mo spending
      t.decimal :fire_withdrawal_rate_pct, precision: 5, scale: 2, default: 4.0      # "safe withdrawal rate" (the 4% rule; editable since views differ, esp. for India's higher assumed return/inflation)

      t.jsonb :target_allocation, default: {}
      # e.g. {"equity": 60, "debt": 25, "gold": 10, "cash": 5} -- weights should sum to 100,
      # validated in the model rather than the DB.

      t.timestamps
    end
  end
end
