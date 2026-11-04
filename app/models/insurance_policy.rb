# One policy of protection cover the household holds. Amounts are in the
# family's currency (the form says so), and premiums are stored with their
# payment frequency so the card can annualise them.
#
# A policy can name the household member it covers, or nobody for something
# that protects the whole household (home, vehicle). Removing a member never
# removes the policy -- the cover still exists.
class InsurancePolicy < ApplicationRecord
  belongs_to :family
  belongs_to :household_member, optional: true

  POLICY_TYPES = %w[
    term_life whole_life ulip health critical_illness personal_accident home vehicle other
  ].freeze

  # Multiplier from the payment frequency to a yearly premium.
  PREMIUM_FREQUENCIES = {
    "monthly" => 12,
    "quarterly" => 4,
    "half_yearly" => 2,
    "yearly" => 1
  }.freeze

  # How far ahead a renewal starts being called out on the card.
  RENEWAL_WARNING_DAYS = 30

  validates :policy_type, inclusion: { in: POLICY_TYPES }
  validates :premium_frequency, inclusion: { in: PREMIUM_FREQUENCIES.keys }
  validates :provider, presence: true, length: { maximum: 120 }
  validates :cover_amount, :premium_amount,
            numericality: { greater_than_or_equal_to: 0 }

  def annual_premium
    (premium_amount.to_d * PREMIUM_FREQUENCIES.fetch(premium_frequency)).round(2)
  end

  # Policies that pay out on death. A ULIP is included because it carries a
  # life cover component even though it is also an investment.
  def life?
    %w[term_life whole_life ulip].include?(policy_type)
  end

  def health?
    policy_type == "health"
  end

  def renewing_soon?(as_of: Date.current, days: RENEWAL_WARNING_DAYS)
    return false if renewal_date.nil?

    renewal_date.between?(as_of, as_of + days.days)
  end

  def renewal_overdue?(as_of: Date.current)
    renewal_date.present? && renewal_date < as_of
  end
end
