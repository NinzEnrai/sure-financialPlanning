require "test_helper"

class FinancialPlanning::AnnualReviewTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
  end

  test "covers a rolling twelve months" do
    review = build_review

    assert_equal Date.current.beginning_of_month - 11.months, review.period.start_date
    assert_equal Date.current.end_of_month, review.period.end_date
    assert_match(/\d{4}/, review.period_label)
  end

  test "a review is due when it has never happened or is more than a year old" do
    assert build_review.review_due?

    setting = @family.planning_setting
    setting.update!(last_reviewed_on: Date.current)
    assert_not build_review.review_due?

    setting.update!(last_reviewed_on: 2.years.ago.to_date)
    assert build_review.review_due?
  end

  test "net worth change is measured against the start of the window" do
    review = build_review

    assert_in_delta review.net_worth_now, review.net_worth_start + review.net_worth_change, 0.01
    assert_equal review.net_worth_now, review.net_worth_now_money.amount
  end

  test "carries the planning page's own figures" do
    review = build_review

    assert_equal @family.balance_sheet.net_worth, review.net_worth_now
    assert_equal review.savings_rate.savings_money, review.savings_rate_money
    assert_kind_of Money, review.contributions_money
    assert_kind_of Hash, review.goal_summary
    assert_operator review.goals_count, :>=, 0
  end

  test "priorities are only the checks that need action" do
    review = build_review

    assert review.priorities.all? { |check| %i[attention watch].include?(check.status) }
  end

  private
    def build_review
      FinancialPlanning::AnnualReview.new(@family, user: @user)
    end
end
