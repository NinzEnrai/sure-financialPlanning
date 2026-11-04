class CreateHouseholdMembers < ActiveRecord::Migration[8.1]
  def change
    # The people an advice plan is for. Sure already knows the users who can
    # sign in; this is deliberately separate: a dependant child or a parent who
    # does not use the app still shapes protection cover, retirement income and
    # goal horizons.
    create_table :household_members, id: :uuid do |t|
      t.references :family, type: :uuid, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.string :relationship, null: false
      t.date :date_of_birth
      t.boolean :dependent, null: false, default: false

      t.timestamps
    end

    add_check_constraint :household_members,
      "relationship IN ('self', 'spouse', 'partner', 'child', 'parent', 'sibling', 'other')",
      name: "household_members_relationship_check"
  end
end
