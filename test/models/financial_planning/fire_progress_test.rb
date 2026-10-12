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

  private
    def fire_progress
      FinancialPlanning::FireProgress.new(@family, user: @user)
    end
end