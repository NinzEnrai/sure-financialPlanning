require "test_helper"

class GoalPriorityTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "accepts only the three priorities" do
    invalid = build_goal(priority: "urgent")
    invalid.valid?
    assert_includes invalid.errors[:priority], "is not included in the list"

    Goal::PRIORITIES.each do |priority|
      goal = build_goal(priority: priority)
      goal.valid?
      assert_empty goal.errors[:priority], "#{priority} should be accepted"
    end
  end

  test "existing goals default to medium and can be reprioritised" do
    goal = goals(:vacation_italy)

    assert_equal "medium", goal.priority

    goal.update!(priority: "high")
    assert_equal "high", goal.reload.priority
  end

  private
    def build_goal(**attrs)
      @family.goals.build(
        { name: "Priority test", target_amount: 1000, currency: "USD" }.merge(attrs)
      )
    end
end
