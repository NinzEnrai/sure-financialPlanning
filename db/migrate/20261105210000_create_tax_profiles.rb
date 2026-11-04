class CreateTaxProfiles < ActiveRecord::Migration[8.1]
  def change
    # Per-person tax inputs. Deliberately stores declarations only: no tax is
    # computed here, because current-year rates must be verified first. One
    # profile per person per family; tax is assessed per PAN, not per household.
    create_table :tax_profiles, id: :uuid do |t|
      t.references :family, type: :uuid, null: false, foreign_key: true, index: true
      t.references :user, type: :uuid, null: false, foreign_key: true, index: true

      t.string :regime
      t.decimal :deductions_80c, precision: 19, scale: 2, null: false, default: "0.0"
      t.decimal :deductions_80d, precision: 19, scale: 2, null: false, default: "0.0"
      t.decimal :deductions_nps, precision: 19, scale: 2, null: false, default: "0.0"
      t.decimal :hra_exemption, precision: 19, scale: 2, null: false, default: "0.0"
      t.decimal :home_loan_interest, precision: 19, scale: 2, null: false, default: "0.0"

      t.timestamps
    end

    add_index :tax_profiles, [ :family_id, :user_id ], unique: true

    add_check_constraint :tax_profiles,
      "regime IS NULL OR regime IN ('old', 'new')",
      name: "tax_profiles_regime_check"
    add_check_constraint :tax_profiles,
      "deductions_80c >= 0 AND deductions_80d >= 0 AND deductions_nps >= 0 AND hra_exemption >= 0 AND home_loan_interest >= 0",
      name: "tax_profiles_deductions_non_negative"
  end
end
