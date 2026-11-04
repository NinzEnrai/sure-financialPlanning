require "test_helper"

class FinancialPlanning::RetirementStressTestTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    stub_inputs
  end

  test "models a plan with an age and spending" do
    stress = build

    assert stress.available?
    assert_not_nil stress.result
    assert_includes 0..100, stress.result.success_percent
    assert_operator stress.result.median_corpus, :>, 0
  end

  test "a very large corpus makes the plan nearly certain" do
    stub_inputs(net_worth: 100_000_000, expenses: 300_000)

    assert_equal 100, build.result.success_percent
  end

  test "an empty corpus with large spending fails every path" do
    stub_inputs(net_worth: 0, savings: 0, expenses: 5_000_000)

    assert_equal 0, build.result.success_percent
  end

  test "is deterministic for a given seed" do
    first = build(seed: 42).result
    second = build(seed: 42).result

    assert_equal first.success_percent, second.success_percent
    assert_in_delta first.median_corpus, second.median_corpus, 0.01
  end

  test "is unavailable without an age" do
    FinancialPlanning::RetirementStressTest.any_instance.stubs(:current_age).returns(nil)

    assert_nil build.result
  end

  test "is unavailable without recorded spending" do
    stub_inputs(expenses: 0)

    assert_nil build.result
  end

  private
    def build(seed: 7)
      FinancialPlanning::RetirementStressTest.new(@family, user: @user, trials: 40, seed: seed)
    end

    def stub_inputs(net_worth: 2_000_000, expenses: 600_000, savings: 300_000)
      klass = FinancialPlanning::RetirementStressTest
      klass.any_instance.stubs(:current_age).returns(40)
      klass.any_instance.stubs(:retirement_age).returns(60)
      klass.any_instance.stubs(:current_net_worth).returns(net_worth)
      klass.any_instance.stubs(:annual_expenses).returns(expenses)
      klass.any_instance.stubs(:annual_savings).returns(savings)
      klass.any_instance.stubs(:mean_return_pct).returns(7.0)
      klass.any_instance.stubs(:inflation_pct).returns(6.0)
    end
end
