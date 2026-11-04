require "test_helper"

class FinancialPlanning::DebtSummaryTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)

    # Fixture balances are shared state; start from zero and set only what each
    # test needs. Reload because update_all bypasses the loaded instances.
    @family.accounts.update_all(balance: 0)
    @card = accounts(:credit_card).reload
    @loan = accounts(:loan).reload
    @other_liability = accounts(:other_liability).reload
    @depository = accounts(:depository).reload

    @card.update!(balance: 5000)
    @card.accountable.update!(apr: 36)
    @loan.update!(balance: 100_000)
    @loan.accountable.update!(interest_rate: 9)
    @depository.update!(balance: 200_000)
  end

  test "sums liability balances into total debt and ignores assets" do
    summary = build_summary

    assert_not summary.empty?
    assert_equal 105_000, summary.total_debt
  end

  test "weights the average rate by balance and reports the monthly interest cost" do
    summary = build_summary

    # (5,000 x 36% + 100,000 x 9%) / 105,000 = 10.29%
    assert_in_delta 10.3, summary.weighted_average_rate_pct.to_f, 0.05
    # 5,000 x 36% / 12 = 150; 100,000 x 9% / 12 = 750.
    assert_in_delta 900, summary.monthly_interest_cost.to_f, 0.01
  end

  test "separates the expensive, high-interest portion" do
    summary = build_summary

    assert_in_delta 5000, summary.high_interest_debt.to_f, 0.01
    assert summary.high_interest?
  end

  test "orders debts by rate so the priciest comes first" do
    summary = build_summary

    assert_equal @card, summary.debts.first.account
  end

  test "reports debt as a share of assets" do
    summary = build_summary

    assert_in_delta 52.5, summary.debt_to_assets_percent.to_f, 0.05
  end

  test "a liability without a recorded rate counts in the total but not the average" do
    @other_liability.update!(balance: 200)

    summary = build_summary

    assert_equal 105_200, summary.total_debt
    assert_in_delta 10.3, summary.weighted_average_rate_pct.to_f, 0.05
    assert_in_delta 900, summary.monthly_interest_cost.to_f, 0.01
  end

  test "an empty debt book reports zeros, not a confident average" do
    @family.accounts.liabilities.update_all(status: "disabled")

    summary = build_summary

    assert summary.empty?
    assert_equal 0, summary.total_debt
    assert_nil summary.weighted_average_rate_pct
    assert_nil summary.monthly_interest_cost
    assert_in_delta 0.0, summary.debt_to_assets_percent.to_f, 0.01
  end

  private
    def build_summary
      FinancialPlanning::DebtSummary.new(@family, user: @user)
    end
end
