require "test_helper"

class FinancialPlanning::BehaviouralNudgesTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
  end

  test "flags cash well beyond the household's own target" do
    stub_emergency(months: 10, target_months: 6, liquid: 5000, target_amount: 3000)
    stub_debt(high_interest: 0)
    stub_invested(0)

    coaching = build

    assert coaching.idle_cash?
    assert_in_delta 2000, coaching.idle_cash_amount, 0.01
    assert coaching.any?
  end

  test "does not flag a merely comfortable buffer" do
    stub_emergency(months: 8, target_months: 6, liquid: 4000, target_amount: 3000)
    stub_debt(high_interest: 0)
    stub_invested(0)

    assert_not build.idle_cash?
  end

  test "flags expensive debt held alongside investments" do
    stub_emergency(months: 4, target_months: 6, liquid: 4000, target_amount: 6000)
    stub_debt(high_interest: 5000)
    stub_invested(10_000)

    coaching = build

    assert coaching.expensive_debt_while_investing?
    assert coaching.any?
  end

  test "does not flag debt when nothing is invested" do
    stub_emergency(months: 4, target_months: 6, liquid: 4000, target_amount: 6000)
    stub_debt(high_interest: 5000)
    stub_invested(0)

    assert_not build.expensive_debt_while_investing?
  end

  test "is quiet when neither tension exists" do
    stub_emergency(months: 6, target_months: 6, liquid: 6000, target_amount: 6000)
    stub_debt(high_interest: 0)
    stub_invested(10_000)

    assert_not build.any?
  end

  private
    def build
      FinancialPlanning::BehaviouralNudges.new(@family, user: @user)
    end

    def stub_emergency(months:, target_months:, liquid:, target_amount:)
      FinancialPlanning::EmergencyFund.any_instance.stubs(:months).returns(months)
      FinancialPlanning::EmergencyFund.any_instance.stubs(:target_months).returns(target_months)
      FinancialPlanning::EmergencyFund.any_instance.stubs(:liquid_balance).returns(liquid)
      FinancialPlanning::EmergencyFund.any_instance.stubs(:target_amount).returns(target_amount)
    end

    def stub_debt(high_interest:)
      FinancialPlanning::DebtSummary.any_instance.stubs(:high_interest_debt).returns(high_interest)
    end

    def stub_invested(amount)
      FinancialPlanning::PortfolioAllocation.any_instance.stubs(:invested_total).returns(amount)
    end
end
