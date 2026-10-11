# frozen_string_literal: true

class PlanningSetting < ApplicationRecord
  belongs_to :family

  validates :expected_annual_return_pct, :expected_inflation_pct, :fire_withdrawal_rate_pct,
            numericality: { greater_than: 0 }
  validate :target_allocation_sums_to_100, if: -> { target_allocation.present? }

  def real_return_pct
    # Fisher approximation is fine here, exact compounding isn't necessary at this precision
    expected_annual_return_pct - expected_inflation_pct
  end

  private

  def target_allocation_sums_to_100
    total = target_allocation.values.sum(&:to_f)
    return if total.zero? # allow blank/unset

    errors.add(:target_allocation, "weights must sum to 100 (currently #{total})") unless total.between?(99.5, 100.5)
  end
end
