class AddInflationPctToGoals < ActiveRecord::Migration[8.1]
  def change
    # Optional inflation assumption for a goal. Null means "plan in today's
    # money", which is the right default: a goal with no assumption should not
    # silently grow.
    add_column :goals, :inflation_pct, :decimal, precision: 5, scale: 2

    add_check_constraint :goals,
      "inflation_pct IS NULL OR inflation_pct BETWEEN 0 AND 50",
      name: "goals_inflation_pct_range"
  end
end
