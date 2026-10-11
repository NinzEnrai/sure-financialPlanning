# frozen_string_literal: true

class FinancialGoal < ApplicationRecord
  belongs_to :family
  belongs_to :linked_account, class_name: "Account", optional: true

  GOAL_TYPES = %w[emergency_fund house_down_payment retirement education vehicle custom].freeze

  validates :name, presence: true
  validates :goal_type, inclusion: { in: GOAL_TYPES }
  validates :target_amount, numericality: { greater_than: 0 }
  validates :target_date, presence: true
  validate :target_date_in_future, on: :create

  def current_amount
    current_amount_override || linked_account&.balance || 0
  end

  def progress_pct
    return 100.0 if target_amount.zero?

    [(current_amount / target_amount * 100).round(1), 100.0].min
  end

  def months_remaining
    ((target_date.to_time - Time.current) / 1.month).to_i.clamp(0, Float::INFINITY).to_i
  end

  private

  def target_date_in_future
    errors.add(:target_date, "must be in the future") if target_date.present? && target_date <= Date.current
  end
end
