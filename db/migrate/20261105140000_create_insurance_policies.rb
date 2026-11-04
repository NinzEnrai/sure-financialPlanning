class CreateInsurancePolicies < ActiveRecord::Migration[8.1]
  def change
    # Protection cover is the part of a financial plan that cannot be
    # reconstructed from transactions: without it the advisor cannot answer
    # "what happens to this household if the earner dies or is hospitalised?".
    # Amounts are recorded in the family's currency.
    create_table :insurance_policies, id: :uuid do |t|
      t.references :family, type: :uuid, null: false, foreign_key: true, index: true
      t.references :household_member, type: :uuid, index: true

      t.string :policy_type, null: false
      t.string :provider, null: false
      t.string :policy_number
      t.decimal :cover_amount, precision: 19, scale: 4, null: false, default: "0.0"
      t.decimal :premium_amount, precision: 19, scale: 4, null: false, default: "0.0"
      t.string :premium_frequency, null: false, default: "yearly"
      t.date :renewal_date
      t.string :nominee
      t.text :notes

      t.timestamps
    end

    # Removing a person must not delete the policy record: the cover still
    # exists, it just stops being attached to a member.
    add_foreign_key :insurance_policies, :household_members, on_delete: :nullify

    add_check_constraint :insurance_policies,
      "policy_type IN ('term_life', 'whole_life', 'ulip', 'health', 'critical_illness', 'personal_accident', 'home', 'vehicle', 'other')",
      name: "insurance_policies_policy_type_check"
    add_check_constraint :insurance_policies,
      "premium_frequency IN ('monthly', 'quarterly', 'half_yearly', 'yearly')",
      name: "insurance_policies_premium_frequency_check"
    add_check_constraint :insurance_policies,
      "cover_amount >= 0 AND premium_amount >= 0",
      name: "insurance_policies_amounts_non_negative"
  end
end
