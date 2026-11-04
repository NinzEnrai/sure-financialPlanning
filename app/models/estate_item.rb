# One line of the succession checklist: a will, a nomination, an executor, a
# guardian or a stored document. Sure records whether it is in place and when it
# was last reviewed; it does not draft legal documents and gives no legal advice.
class EstateItem < ApplicationRecord
  KINDS = %w[will nomination executor guardian document].freeze
  STATUSES = %w[pending in_place not_applicable].freeze

  belongs_to :family
  belongs_to :household_member, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :title, presence: true, length: { maximum: 200 }

  def in_place?
    status == "in_place"
  end

  def pending?
    status == "pending"
  end

  # A review date in the past is a nudge, not a failure: life changes and the
  # document needs re-checking.
  def review_overdue?(as_of: Date.current)
    review_on.present? && review_on < as_of
  end
end
