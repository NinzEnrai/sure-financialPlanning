require "test_helper"

class FinancialPlanning::HealthScorecardTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    Goal.stubs(:prepared_for).returns([])
  end

  test "marks a healthy household as on track with no next action" do
    stub_metrics(rate: 25.0, months: 7.0, dti: 10.0, high_interest: 0, debts: [ rated_debt(5) ])

    scorecard = build_scorecard
    statuses = statuses_by_key(scorecard)

    assert_equal :good, statuses[:savings_rate]
    assert_equal :good, statuses[:emergency_fund]
    assert_equal :good, statuses[:debt_to_income]
    assert_equal :good, statuses[:high_interest_debt]
    assert_equal :unknown, statuses[:goals]
    assert_equal :unknown, statuses[:protection]
    assert_equal 4, scorecard.good_count
    assert_equal 4, scorecard.known_count
    assert_nil scorecard.next_action_key
  end

  test "points at emergency cover first when it is short" do
    stub_metrics(rate: 25.0, months: 1.5, dti: 10.0, high_interest: 0, debts: [ rated_debt(5) ])

    scorecard = build_scorecard

    assert_equal :attention, statuses_by_key(scorecard)[:emergency_fund]
    assert_equal :emergency_fund, scorecard.next_action_key
  end

  test "expensive debt outranks a low savings rate as the next action" do
    stub_metrics(rate: 5.0, months: 7.0, dti: 10.0, high_interest: 5000, debts: [ rated_debt(36) ])

    scorecard = build_scorecard

    assert_equal :attention, statuses_by_key(scorecard)[:high_interest_debt]
    assert_equal :attention, statuses_by_key(scorecard)[:savings_rate]
    assert_equal :high_interest_debt, scorecard.next_action_key
  end

  test "missing inputs stay unknown rather than becoming failures" do
    stub_metrics(rate: nil, months: nil, dti: nil, high_interest: 0, debts: [])

    scorecard = build_scorecard
    statuses = statuses_by_key(scorecard)

    assert_equal :unknown, statuses[:savings_rate]
    assert_equal :unknown, statuses[:emergency_fund]
    assert_equal :unknown, statuses[:goals]
    assert_equal :unknown, statuses[:protection]
    assert_equal :good, statuses[:debt_to_income]
    assert_nil scorecard.next_action_key
  end

  test "counts dated goals that are behind pace" do
    on_track = fake_goal(behind: false)
    behind = fake_goal(behind: true)
    Goal.stubs(:prepared_for).returns([ on_track, behind ])

    stub_metrics(rate: 25.0, months: 7.0, dti: 10.0, high_interest: 0, debts: [])

    scorecard = build_scorecard
    goal_check = scorecard.checks.find { |check| check.key == :goals }

    assert_equal :attention, goal_check.status
    assert_equal 1, goal_check.value
    assert_equal 2, goal_check.total
  end

  test "ignores goals without a deadline" do
    undated = Goal.new(name: "Open-ended", target_amount: 1000, currency: "USD")
    undated.stubs(:target_date).returns(nil)
    undated.stubs(:maintained?).returns(false)
    Goal.stubs(:prepared_for).returns([ undated ])

    stub_metrics(rate: 25.0, months: 7.0, dti: 10.0, high_interest: 0, debts: [])

    goal_check = build_scorecard.checks.find { |check| check.key == :goals }

    assert_equal :unknown, goal_check.status
  end

  private
    def build_scorecard
      FinancialPlanning::HealthScorecard.new(@family, user: @user)
    end

    def statuses_by_key(scorecard)
      scorecard.checks.index_by(&:key).transform_values(&:status)
    end

    def stub_metrics(rate:, months:, dti:, high_interest:, debts:)
      FinancialPlanning::SavingsRate.any_instance.stubs(:trailing_rate).returns(rate)
      FinancialPlanning::EmergencyFund.any_instance.stubs(:months).returns(months)
      FinancialPlanning::DebtSummary.any_instance.stubs(:debts).returns(debts)
      FinancialPlanning::DebtSummary.any_instance.stubs(:dti_percent).returns(dti)
      FinancialPlanning::DebtSummary.any_instance.stubs(:high_interest_debt).returns(high_interest)
      FinancialPlanning::DebtSummary.any_instance.stubs(:high_interest?).returns(high_interest.positive?)
    end

    def rated_debt(rate)
      FinancialPlanning::DebtSummary::Debt.new(account: nil, balance: 0, rate_pct: rate, payment: nil, high_interest: rate >= 10)
    end

    def fake_goal(behind:)
      goal = Goal.new(name: "Goal", target_amount: 1000, currency: "USD")
      goal.stubs(:target_date).returns(Date.current + 1.month)
      goal.stubs(:maintained?).returns(false)
      goal.stubs(:behind_pace?).returns(behind)
      goal
    end
end
