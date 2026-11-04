require "test_helper"

class FinancialPlanning::EmergencyFundTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @checking = accounts(:depository)

    clear_entries
    # Fixture balances are shared across tests; start from zero cash and set only
    # what each test needs. This keeps the numbers independent of the deposit
    # account fixture data.
    @family.accounts.update_all(balance: 0)
    # update_all goes around the instance loaded above; reload so a later
    # update!(balance:) is not skipped as "unchanged".
    @checking.reload
  end

  test "counts depository balances as the liquid buffer" do
    @checking.update!(balance: 6000)
    accounts(:credit_card).update!(balance: 1000)
    accounts(:investment).update!(balance: 10_000)
    accounts(:loan).update!(balance: 500_000)

    fund = build_fund

    assert_equal 6000, fund.liquid_balance
    assert_includes fund.liquid_accounts, @checking
    assert_not_includes fund.liquid_accounts, accounts(:credit_card)
    assert_not_includes fund.liquid_accounts, accounts(:investment)
  end

  test "averages spending over the trailing twelve months" do
    12.times do |offset|
      create_transaction(amount: 1000, date: Date.current.beginning_of_month - offset.months + 1.day)
    end
    # Outside the trailing-year window, so it must not move the average.
    create_transaction(amount: 50_000, date: Date.current.beginning_of_month - 13.months)

    fund = build_fund

    assert_equal 1000, fund.monthly_expenses
  end

  test "coverage is liquid cash divided by average monthly spending" do
    12.times do |offset|
      create_transaction(amount: 1000, date: Date.current.beginning_of_month - offset.months + 1.day)
    end
    @checking.update!(balance: 3000)

    fund = build_fund

    assert_equal 3.0, fund.months
    assert_equal :building, fund.status
    assert_equal 6000, fund.target_amount
    assert_equal 3000, fund.shortfall
    assert_equal 50.0, fund.coverage_percent
    assert_equal 50.0, fund.bar_percent
  end

  test "status bands mark too little and enough cover" do
    12.times do |offset|
      create_transaction(amount: 1000, date: Date.current.beginning_of_month - offset.months + 1.day)
    end

    @checking.update!(balance: 1500)
    assert_equal :critical, build_fund.status

    @checking.update!(balance: 9000)
    funded = build_fund
    assert_equal :funded, funded.status
    assert_equal 3000, funded.surplus
    assert_equal 0, funded.shortfall
    assert_equal 100.0, funded.bar_percent
  end

  test "months are unavailable without spending history" do
    @checking.update!(balance: 5000)

    fund = build_fund

    assert_nil fund.months
    assert_equal :unknown, fund.status
    assert_nil fund.coverage_percent
    assert_nil fund.bar_percent
    assert_equal 0, fund.shortfall
    assert_equal 5000, fund.liquid_balance
  end

  test "uses the family's configured target months" do
    12.times do |offset|
      create_transaction(amount: 1000, date: Date.current.beginning_of_month - offset.months + 1.day)
    end
    # Seven months of cover would be "funded" at the default six-month target.
    @checking.update!(balance: 7000)

    setting = @family.planning_setting || @family.create_planning_setting
    setting.update!(emergency_target_months: 12)

    fund = build_fund

    assert_equal 12, fund.target_months
    assert_equal 12_000, fund.target_amount
    assert_equal 7.0, fund.months
    # Seven months is inside the minimum band but short of a twelve-month
    # target, so it stays in "building" rather than turning green.
    assert_equal :building, fund.status
    assert_not fund.funded?
  end

  test "the target months setting accepts one to twenty-four only" do
    setting = @family.planning_setting || @family.create_planning_setting

    setting.emergency_target_months = 0
    assert_not setting.valid?

    setting.emergency_target_months = 12
    assert setting.valid?

    setting.emergency_target_months = 25
    assert_not setting.valid?
  end

  test "converts foreign-currency cash at today's rate" do
    @family.accounts.create!(
      name: "Euro savings",
      balance: 1000,
      currency: "EUR",
      accountable: Depository.new,
      owner: @user,
      status: "active"
    )
    ExchangeRate.stubs(:rates_for).returns({ "EUR" => BigDecimal("1.5") })

    fund = build_fund

    assert_equal 1500, fund.liquid_balance
  end

  private
    def build_fund
      FinancialPlanning::EmergencyFund.new(@family, user: @user)
    end

    def clear_entries
      Entry.where(account: @family.accounts).destroy_all
    end
end
