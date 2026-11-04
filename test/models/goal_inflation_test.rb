require "test_helper"

class GoalInflationTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @goal = goals(:vacation_italy)
  end

  test "no assumption leaves the nominal target and requirement untouched" do
    assert_nil @goal.inflation_pct
    assert_equal @goal.monthly_target_amount, @goal.inflation_adjusted_monthly_target_amount
    assert_equal @goal.target_amount.to_d, @goal.inflation_adjusted_target_amount
  end

  test "an assumption raises the future target and the monthly requirement" do
    # The vacation fixture is already fully funded, so its monthly requirement
    # is zero either way; the car goal still has money left to save.
    goal = goals(:car_paydown)
    goal.update!(inflation_pct: 10)

    assert_operator goal.inflation_factor, :>, 1
    assert_operator goal.inflation_adjusted_target_amount, :>, goal.target_amount.to_d
    assert_operator goal.monthly_target_amount, :>, 0
    assert_operator goal.inflation_adjusted_monthly_target_amount, :>, goal.monthly_target_amount
  end

  test "an undated goal cannot be inflated" do
    undated = goals(:emergency_fund)
    undated.update!(inflation_pct: 6)

    assert_equal undated.target_amount.to_d, undated.inflation_adjusted_target_amount
    assert_equal undated.monthly_target_amount, undated.inflation_adjusted_monthly_target_amount
  end
end
