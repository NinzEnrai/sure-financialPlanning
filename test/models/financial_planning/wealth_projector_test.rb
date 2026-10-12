require "test_helper"

class FinancialPlanning::WealthProjectorTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    planning_settings(:active_family)
  end

  test "projects one point per year starting at today's net worth" do
    projector = FinancialPlanning::WealthProjector.new(
      @family, user: @user, years: 10, opening_balance: 1000, monthly_contribution: 100
    )

    points = projector.points

    assert_equal 11, points.size
    assert_equal Date.current.year, points.first.year
    assert_equal Date.current.year + 10, points.last.year
    assert_equal 1000, points.first.balance, "year 0 is the balance actually held today"
  end

  test "balance grows with the monthly contribution and growth rate" do
    projector = FinancialPlanning::WealthProjector.new(
      @family, user: @user, years: 1, opening_balance: 1000, monthly_contribution: 100
    )

    # One year: 1000 compounded at 7% plus 100/mo for 12 months.
    expected = (1000 * 1.07) + 1200
    assert_in_delta expected, projector.points.last.balance, 0.01
  end

  test "projection increases monotonically with no contribution" do
    projector = FinancialPlanning::WealthProjector.new(
      @family, user: @user, years: 10, opening_balance: 1000, monthly_contribution: 0
    )

    balances = projector.points.map(&:balance)

    assert_equal balances.sort, balances
  end

  test "growth rate comes from the family setting" do
    assert_equal 7.0, projector.growth_rate_pct

    # Through the association, not the fixture accessor: `family.planning_setting`
    # is memoized on @family, so updating the raw fixture row behind it leaves a
    # stale object and the assertion below would read the old rate.
    @family.planning_setting.update!(annual_growth_rate_pct: 9.0)

    assert_equal 9.0, FinancialPlanning::WealthProjector.new(@family, user: @user).growth_rate_pct
  end

  test "months to target is nil without a positive contribution" do
    projector = FinancialPlanning::WealthProjector.new(
      @family, user: @user, opening_balance: 1000, monthly_contribution: 0
    )

    assert_nil projector.months_to_target(10_000_000)
  end

  test "months to target is zero when the balance already exceeds it" do
    projector = FinancialPlanning::WealthProjector.new(
      @family, user: @user, opening_balance: 10_000, monthly_contribution: 500
    )

    assert_equal 0, projector.months_to_target(5_000)
  end

  test "months to target inverts the projection curve" do
    projector = FinancialPlanning::WealthProjector.new(
      @family, user: @user, opening_balance: 1000, monthly_contribution: 100
    )
    # A target the 10-year curve actually crosses -- a bigger one would resolve
    # to years past the end of `points` and prove nothing.
    target = 10_000

    months = projector.months_to_target(target)

    assert_not_nil months
    years = (months / 12.0).ceil
    assert_operator years, :<=, projector.points.size - 1
    assert_operator projector.points[years - 1].balance, :<, target
    assert_operator projector.points[years].balance, :>=, target
  end

  private
    def projector
      FinancialPlanning::WealthProjector.new(@family, user: @user)
    end
end