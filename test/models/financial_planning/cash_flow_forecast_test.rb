require "test_helper"

class FinancialPlanning::CashFlowForecastTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    stub_sources(cash: 1000, spending: 2000, income: 5000, debt: 300, premiums: 1200)
  end

  test "projects cash from the trailing monthly surplus" do
    forecast = build_forecast

    assert forecast.available?
    assert_in_delta 2600, forecast.net_monthly, 0.01
    assert_equal [ 30, 60, 90 ], forecast.points.map(&:days)
    assert_in_delta 3600, forecast.points[0].balance, 0.01
    assert_in_delta 6200, forecast.points[1].balance, 0.01
    assert_in_delta 8800, forecast.points[2].balance, 0.01
    assert_not forecast.shortfall?
  end

  test "warns when the projection crosses zero" do
    stub_sources(cash: 1000, spending: 5000, income: 5000, debt: 300, premiums: 1200)

    forecast = build_forecast

    assert forecast.shortfall?
    assert_equal 90, forecast.first_shortfall.days
    assert forecast.first_shortfall.negative?
  end

  test "runs without a recorded debt payment and flags the gap" do
    stub_sources(cash: 1000, spending: 2000, income: 5000, debt: nil, premiums: 1200)

    forecast = build_forecast

    assert_not forecast.debt_known?
    assert_in_delta 2900, forecast.net_monthly, 0.01
    assert forecast.available?
  end

  test "is unavailable without recorded income" do
    stub_sources(cash: 1000, spending: 2000, income: nil, debt: 300, premiums: 1200)

    forecast = build_forecast

    assert_not forecast.available?
    assert_empty forecast.points
    assert_nil forecast.net_monthly
  end

  private
    def build_forecast
      FinancialPlanning::CashFlowForecast.new(@family, user: @user)
    end

    def stub_sources(cash:, spending:, income:, debt:, premiums:)
      FinancialPlanning::EmergencyFund.any_instance.stubs(:liquid_balance).returns(cash)
      FinancialPlanning::EmergencyFund.any_instance.stubs(:monthly_expenses).returns(spending)
      FinancialPlanning::DebtSummary.any_instance.stubs(:monthly_income).returns(income)
      FinancialPlanning::DebtSummary.any_instance.stubs(:monthly_obligation).returns(debt)
      FinancialPlanning::ProtectionGap.any_instance.stubs(:annual_premium_total).returns(premiums)
    end
end
