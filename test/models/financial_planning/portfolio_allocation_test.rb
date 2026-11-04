require "test_helper"

class FinancialPlanning::PortfolioAllocationTest < ActiveSupport::TestCase
  include PortfolioFlowTestHelper

  setup do
    @family = families(:empty)
    @account = create_portfolio_account(@family, balance: 1000)
    @equity = Security.create!(ticker: "ALC#{SecureRandom.hex(4)}", name: "Big position", asset_class: "equity")
    @other = Security.create!(ticker: "ALC#{SecureRandom.hex(4)}", name: "Small position")

    hold(@equity, amount: 400)
    hold(@other, amount: 100)
  end

  test "reports invested, cash and the largest position" do
    allocation = build_allocation

    assert_not allocation.empty?
    assert_equal 500, allocation.invested_total
    assert_equal 500, allocation.cash_total
    assert_equal 50.0, allocation.cash_percent
    assert_equal 40.0, allocation.largest_weight
    assert_equal @equity, allocation.largest_holding.security
  end

  test "flags a portfolio dominated by one holding" do
    assert_equal :attention, build_allocation.concentration_status
  end

  test "warns before a position dominates" do
    holdings_of(@equity).update!(amount: 150, qty: 15, price: 10)

    assert_equal :watch, build_allocation.concentration_status
  end

  test "is comfortable when no position is large" do
    holdings_of(@equity).update!(amount: 80, qty: 8, price: 10)
    holdings_of(@other).update!(amount: 50, qty: 5, price: 10)

    assert_equal :good, build_allocation.concentration_status
  end

  test "groups holdings into asset classes, keeping unclassified ones" do
    groups = build_allocation.asset_classes

    assert_equal %w[equity unclassified], groups.map(&:key)
    assert_equal [ 80.0, 20.0 ], groups.map(&:percent)
    assert_equal [ 400, 100 ], groups.map(&:amount)
  end

  test "compares the equity share with the risk profile range" do
    setting = @family.planning_setting || @family.create_planning_setting

    setting.update!(risk_profile: "moderate") # 50-70%; portfolio holds 80%
    assert_equal :watch, build_allocation.equity_status

    setting.update!(risk_profile: "aggressive") # 70-90%
    assert_equal :good, build_allocation.equity_status

    setting.update!(risk_profile: "conservative") # 20-40%
    assert_equal :attention, build_allocation.equity_status
  end

  test "plans a shift back to the middle of the band" do
    setting = @family.planning_setting || @family.create_planning_setting
    setting.update!(risk_profile: "moderate") # 50-70%, middle 60%; portfolio holds 80% equity

    allocation = build_allocation

    assert_in_delta 60.0, allocation.risk_target_equity_percent, 0.05
    assert_in_delta 20.0, allocation.equity_drift_percent, 0.05
    assert_equal :trim_equity, allocation.rebalance_direction
    assert_in_delta 100.0, allocation.rebalance_amount, 0.01
    assert allocation.rebalance_plan?
  end

  test "plans adding to equity when the mix is under the band" do
    holdings_of(@equity).update!(amount: 50, qty: 5, price: 10)
    setting = @family.planning_setting || @family.create_planning_setting
    setting.update!(risk_profile: "aggressive") # 70-90%, middle 80%

    allocation = build_allocation

    assert_equal :add_equity, allocation.rebalance_direction
    assert_operator allocation.rebalance_amount, :>, 0
    assert allocation.rebalance_plan?
  end

  test "no rebalancing plan inside the band or without a profile" do
    setting = @family.planning_setting || @family.create_planning_setting
    setting.update!(risk_profile: "aggressive") # middle 80 equals the current 80%

    assert_not build_allocation.rebalance_plan?
    assert_equal :good, build_allocation.equity_status

    setting.update!(risk_profile: nil)

    assert_not build_allocation.rebalance_plan?
    assert_nil build_allocation.rebalance_amount
  end

  test "risk comparison is unknown without a profile" do
    setting = @family.planning_setting || @family.create_planning_setting
    setting.update!(risk_profile: nil)

    allocation = build_allocation

    assert_nil allocation.equity_target_range
    assert_equal :unknown, allocation.equity_status
    assert_in_delta 80.0, allocation.equity_percent, 0.05
  end

  test "an empty portfolio is unknown rather than comfortable" do
    Holding.delete_all

    allocation = build_allocation

    assert allocation.empty?
    assert_equal :unknown, allocation.concentration_status
    assert_equal 1000, allocation.cash_total
    assert_equal 100.0, allocation.cash_percent
    assert_empty allocation.asset_classes
  end

  private
    def build_allocation
      FinancialPlanning::PortfolioAllocation.new(@family, user: nil)
    end

    def hold(security, amount:)
      Holding.create!(
        account: @account,
        security: security,
        date: Date.current,
        qty: 10,
        price: amount / 10.0,
        amount: amount,
        currency: "USD"
      )
    end

    def holdings_of(security)
      Holding.where(account: @account, security: security)
    end
end
