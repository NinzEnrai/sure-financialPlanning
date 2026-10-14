require "test_helper"

class FinancialPlanning::FireProgressTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @setting = planning_settings(:active_family)

    Entry.where(account: @family.accounts).destroy_all
  end

  test "target is 25x average annual expenses at the 4% rule" do
    12.times { |m| create_transaction(amount: 1000, date: m.months.ago.to_date) }

    fire = fire_progress

    assert_equal 12000, fire.average_annual_expenses
    assert_equal 300000, fire.target
    assert_equal 25, fire.multiple
    assert_equal 4.0, fire.withdrawal_rate_pct
  end

  test "annual expenses average the trailing year rather than reading one month" do
    12.times { |m| create_transaction(amount: 1000, date: m.months.ago.to_date) }
    create_transaction(amount: 5000, date: 13.months.ago.to_date) # outside the 12-month window

    assert_equal 12000, fire_progress.average_annual_expenses
  end

  test "percent is nil and the bar empty when there is no target" do
    assert_nil fire_progress.percent
    assert_equal 0, fire_progress.bar_percent
    assert_not fire_progress.achieved?
  end

  test "percent measures net worth against the target and the bar caps at 100" do
    create_transaction(amount: 12000, date: Date.current) # 12k annual -> 300k target

    fire = fire_progress
    fire.stubs(:current_net_worth).returns(150000)

    assert_equal 50.0, fire.percent
    assert_equal 50.0, fire.bar_percent
    assert_not fire.achieved?

    fire.stubs(:current_net_worth).returns(450000)

    assert_equal 150.0, fire.percent, "percent is not clamped -- 150% of FI is meaningful"
    assert_equal 100, fire.bar_percent, "the bar itself must not overflow"
    assert fire.achieved?
  end

  test "remaining is the shortfall and never negative" do
    create_transaction(amount: 12000, date: Date.current)

    fire = fire_progress
    fire.stubs(:current_net_worth).returns(100000)
    assert_equal 200000, fire.remaining

    fire.stubs(:current_net_worth).returns(500000)
    assert_equal 0, fire.remaining
  end

  test "a custom withdrawal rate changes the target" do
    create_transaction(amount: 12000, date: Date.current)
    assert_equal 300000, fire_progress.target

    # Through the association: `family.planning_setting` is memoized on @family,
    # so updating the raw fixture row would leave a stale object behind.
    @family.planning_setting.update!(fire_withdrawal_rate_pct: 3.0)

    assert_equal 400000, fire_progress.target
  end

  test "months to target is nil when nothing is being saved" do
    create_transaction(amount: 12000, date: Date.current)
    fire = fire_progress
    fire.stubs(:current_net_worth).returns(0)
    fire.stubs(:monthly_contribution).returns(0)

    assert_nil fire.months_to_target
  end

  test "coast fire measures against the target year rather than a countdown" do
    create_transaction(amount: 12000, date: Date.current)
    @family.planning_setting.update!(fire_variant: "coast", fire_target_year: Date.current.year + 10)

    fire = fire_progress

    assert fire.coast_fire?
    assert_equal Date.current.year + 10, fire.target_year
    # End of the target year, so the family is given all of it.
    assert_equal 12, fire.target_date.month
    assert_operator fire.months_until_target_date, :>, 100
    assert fire.projected_balance_at_target_date.present?
  end

  test "coast fire treats this year as a horizon inside the year rather than a past date" do
    create_transaction(amount: -20000, date: Date.current) # income
    create_transaction(amount: 12000, date: Date.current)
    @family.planning_setting.update!(fire_variant: "coast", fire_target_year: Date.current.year)

    fire = fire_progress

    # The horizon runs out to December, so "this year" is a couple of months
    # rather than zero -- and, crucially, still a future date rather than a
    # negative one.
    assert_equal Date.current.year, fire.target_date.year
    assert_operator fire.months_until_target_date, :>=, 0
    assert_operator fire.months_until_target_date, :<=, 12
  end

  test "coast fire reports no horizon at all once the target year has passed" do
    create_transaction(amount: 12000, date: Date.current)
    @family.planning_setting.update!(fire_variant: "coast", fire_target_year: Date.current.year)

    # A year already gone cannot be stored -- the model refuses one in the past --
    # so this is stubbed rather than written as an invalid row.
    fire = fire_progress
    fire.stubs(:target_date).returns(Date.current - 12.months)

    assert_nil fire.months_until_target_date
    assert_nil fire.coast_on_track?
    assert_nil fire.projected_balance_at_target_date
  end

  test "coast on track compares the projection at the target year against the target" do
    # Income, so there is a positive pace to project -- without it both horizons
    # are short and the comparison proves nothing.
    create_transaction(amount: -20000, date: Date.current)
    create_transaction(amount: 12000, date: Date.current)

    # Same pace, two horizons. Only the long one can clear the target, so the two
    # answers have to differ.
    @family.planning_setting.update!(fire_variant: "coast", fire_target_year: Date.current.year + 1)
    near = fire_progress.coast_on_track?

    @family.planning_setting.update!(fire_variant: "coast", fire_target_year: Date.current.year + 60)
    far = fire_progress.coast_on_track?

    refute_equal near, far
    assert_equal true, far
  end

  test "non-coast variants measure against a multiple, not a date" do
    create_transaction(amount: 12000, date: Date.current)
    @family.planning_setting.update!(fire_variant: "standard")

    fire = fire_progress

    assert_not fire.coast_fire?
    assert_nil fire.target_date
    assert_nil fire.months_until_target_date
    assert_nil fire.coast_on_track?
    assert_equal 300000, fire.target
  end

  private
    def fire_progress
      FinancialPlanning::FireProgress.new(@family, user: @user)
    end
end