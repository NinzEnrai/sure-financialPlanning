class AddLastReviewedOnToPlanningSettings < ActiveRecord::Migration[8.1]
  def change
    # When the household last sat down for an annual review. Nullable: a family
    # that has never reviewed has not "reviewed in 1970".
    add_column :planning_settings, :last_reviewed_on, :date
  end
end
