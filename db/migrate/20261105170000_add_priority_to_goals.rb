class AddPriorityToGoals < ActiveRecord::Migration[8.1]
  def change
    # Which goal wins when there is not enough money for all of them. Existing
    # goals get "medium" so nothing changes until the household says otherwise.
    add_column :goals, :priority, :string, null: false, default: "medium"

    add_check_constraint :goals,
      "priority IN ('high', 'medium', 'low')",
      name: "goals_priority_check"
  end
end
