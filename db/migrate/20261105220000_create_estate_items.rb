class CreateEstateItems < ActiveRecord::Migration[8.1]
  def change
    # The succession checklist a planner runs: will, nominations, executor,
    # guardian and the documents that record them. Status only -- this is not
    # legal advice and Sure does not draft anything.
    create_table :estate_items, id: :uuid do |t|
      t.references :family, type: :uuid, null: false, foreign_key: true, index: true
      t.references :household_member, type: :uuid, index: true

      t.string :kind, null: false
      t.string :title, null: false
      t.string :nominee
      t.string :status, null: false, default: "pending"
      t.date :review_on
      t.text :notes

      t.timestamps
    end

    add_foreign_key :estate_items, :household_members, on_delete: :nullify

    add_check_constraint :estate_items,
      "kind IN ('will', 'nomination', 'executor', 'guardian', 'document')",
      name: "estate_items_kind_check"
    add_check_constraint :estate_items,
      "status IN ('pending', 'in_place', 'not_applicable')",
      name: "estate_items_status_check"
  end
end
