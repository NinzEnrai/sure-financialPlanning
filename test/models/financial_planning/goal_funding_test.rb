require "test_helper"

class FinancialPlanning::GoalFundingTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
  end

  test "rolls dated goals into the monthly requirement, pace and gap" do
    stub_goals([ fake_goal(required: 100, pace: 40, behind: true) ])

    funding = build_funding

    assert_equal 1, funding.rows.size
    assert_in_delta 100, funding.total_required_monthly.to_f, 0.01
    assert_in_delta 40, funding.total_pace.to_f, 0.01
    assert_in_delta 60, funding.total_gap.to_f, 0.01
    assert_equal 1, funding.behind_count
    assert_not funding.on_track?
  end

  test "presents high-priority goals first" do
    stub_goals([
      fake_goal(required: 100, pace: 0, behind: true, priority: "low"),
      fake_goal(required: 100, pace: 0, behind: true, priority: "high"),
      fake_goal(required: 100, pace: 0, behind: true, priority: "medium")
    ])

    funding = build_funding

    assert_equal %w[high medium low], funding.rows.map(&:priority)
    assert_equal 1, funding.high_priority_count
  end

  test "no gap when the pace covers every dated goal" do
    stub_goals([ fake_goal(required: 100, pace: 120, behind: false) ])

    funding = build_funding

    assert funding.on_track?
    assert_equal 0, funding.total_gap
  end

  test "undated, maintained and paused goals are listed but not summed" do
    undated = fake_goal(required: 100, pace: 0, behind: false, target_date: nil)
    paused = fake_goal(required: 100, pace: 0, behind: false, paused: true)
    maintained = fake_goal(required: 100, pace: 0, behind: false, maintained: true)
    stub_goals([ undated, paused, maintained ])

    funding = build_funding

    assert_equal 3, funding.goals.size
    assert_empty funding.rows
    assert_equal 0, funding.total_required_monthly
  end

  test "a household without goals is empty rather than on track" do
    stub_goals([])

    funding = build_funding

    assert funding.empty?
    assert_equal 0, funding.total_required_monthly
    assert_equal 0, funding.total_gap
  end

  private
    def build_funding
      FinancialPlanning::GoalFunding.new(@family, user: @user)
    end

    def stub_goals(goals)
      Goal.stubs(:active_prepared_for).returns(goals)
    end

    def fake_goal(required:, pace:, behind:, priority: "medium", target_date: Date.current + 1.year, paused: false, maintained: false)
      goal = Goal.new(name: "Goal", target_amount: 1200, currency: @family.currency)
      goal.stubs(:priority).returns(priority)
      goal.stubs(:target_date).returns(target_date)
      goal.stubs(:monthly_target_amount).returns(BigDecimal(required.to_s))
      goal.stubs(:inflation_adjusted_monthly_target_amount).returns(BigDecimal(required.to_s))
      goal.stubs(:inflation_pct).returns(nil)
      goal.stubs(:pace).returns(BigDecimal(pace.to_s))
      goal.stubs(:behind_pace?).returns(behind)
      goal.stubs(:paused?).returns(paused)
      goal.stubs(:maintained?).returns(maintained)
      goal
    end
end
