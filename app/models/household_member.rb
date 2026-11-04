# A person the family plans for. Separate from User on purpose: a dependant
# child or a non-app-using parent still affects how much protection cover the
# earning members need and how far retirement money has to stretch.
#
# Dates of birth are optional because a family may add someone before they have
# the date to hand, but an age is what every downstream calculation uses, so
# the card shows a person without one plainly rather than guessing.
class HouseholdMember < ApplicationRecord
  belongs_to :family

  RELATIONSHIPS = %w[self spouse partner child parent sibling other].freeze

  # A sanity bound, not an actuarial one: 120 years is beyond any living person,
  # so a date outside it is a typo rather than a very old dependant.
  MAX_AGE_YEARS = 120

  validates :name, presence: true, length: { maximum: 100 }
  validates :relationship, inclusion: { in: RELATIONSHIPS }
  validate :date_of_birth_is_not_in_the_future
  validate :date_of_birth_is_plausible

  # Whole years old today, or nil when the date is unknown. Uses calendar
  # fields rather than dividing days so a leap-day birthday stays correct.
  def age
    return nil if date_of_birth.nil?

    today = Date.current
    had_birthday = today.month > date_of_birth.month ||
      (today.month == date_of_birth.month && today.day >= date_of_birth.day)
    today.year - date_of_birth.year - (had_birthday ? 0 : 1)
  end

  def adult?
    age.present? && age >= 18
  end

  private
    def date_of_birth_is_not_in_the_future
      return if date_of_birth.nil? || date_of_birth <= Date.current

      errors.add(:date_of_birth, "cannot be in the future")
    end

    def date_of_birth_is_plausible
      return if date_of_birth.nil? || date_of_birth >= (MAX_AGE_YEARS + 1).years.ago.to_date

      errors.add(:date_of_birth, "is not a plausible date of birth")
    end
end
