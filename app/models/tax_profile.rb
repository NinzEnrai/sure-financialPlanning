# Declared per-person tax inputs: regime and the deductions a household has
# already made. This is a record for the household and its chartered
# accountant, not a tax engine: no rate, slab or liability is computed here
# while current-year rules are unverified.
#
# One profile per person per family. The tax unit is a person (PAN), not the
# household, so nothing here sums across people into a single liability.
class TaxProfile < ApplicationRecord
  REGIMES = %w[old new].freeze

  DEDUCTION_ATTRIBUTES = %i[
    deductions_80c deductions_80d deductions_nps hra_exemption home_loan_interest
  ].freeze

  belongs_to :family
  belongs_to :user

  validates :regime, inclusion: { in: REGIMES }, allow_nil: true
  validates(*DEDUCTION_ATTRIBUTES, numericality: { greater_than_or_equal_to: 0 })
  validate :user_belongs_to_family

  def total_declared_deductions
    DEDUCTION_ATTRIBUTES.sum { |attribute| public_send(attribute).to_d }.round(2)
  end

  def total_declared_deductions_money
    Money.new(total_declared_deductions, family.currency)
  end

  private
    def user_belongs_to_family
      return if user.nil? || family.nil? || user.family_id == family_id

      errors.add(:user, "must belong to this family")
    end
end
