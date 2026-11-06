require "test_helper"

class FinancialPlanning::FeeAuditTest < ActiveSupport::TestCase
  include PortfolioFlowTestHelper

  setup do
    @family = families(:empty)
    @user = users(:family_admin)
    @account = create_portfolio_account(@family, balance: 10_000)
    @security = create_portfolio_security(ticker: "FEE#{SecureRandom.hex(4)}")
  end

  test "totals the fees paid on trades and compares them with the portfolio" do
    trade(qty: 10, price: 100, fee: 100)
    trade(qty: 5, price: 100, fee: 50)

    audit = build_audit

    assert_not audit.empty?
    assert_in_delta 150, audit.total_fees, 0.01
    assert_equal 2, audit.trade_count
    assert_in_delta 1.5, audit.fee_ratio_percent, 0.01
    assert_equal 1, audit.by_account.size
  end

  test "does not count fees on another member's unshared account" do
    family = families(:dylan_family)
    admin = users(:family_admin)
    unshared = family.accounts.create!(
      name: "Jakob's brokerage", balance: 1000, currency: "USD",
      accountable: Investment.new, owner: users(:family_member)
    )
    security = create_portfolio_security(ticker: "PRIV#{SecureRandom.hex(4)}")
    create_portfolio_trade(account: unshared, security: security, qty: 1, price: 100, fee: 10)

    audit = FinancialPlanning::FeeAudit.new(family, user: admin)

    assert_not audit.rows.any? { |row| row[:account] == unshared }
  end

  test "ignores trades without fees" do
    trade(qty: 10, price: 100, fee: 0)

    assert build_audit.empty?
  end

  test "counts fees it cannot convert instead of converting at one" do
    euro_account = create_portfolio_account(@family, currency: "EUR", balance: 0)
    trade(qty: 1, price: 100, fee: 10, account: euro_account)

    audit = build_audit

    assert_equal 1, audit.unconverted_count
    assert_in_delta 0, audit.total_fees, 0.01
  end

  private
    def build_audit
      FinancialPlanning::FeeAudit.new(@family, user: nil)
    end

    def trade(qty:, price:, fee:, account: @account)
      create_portfolio_trade(
        account: account, security: @security, qty: qty, price: price,
        fee: fee, date: 1.month.ago.to_date
      )
    end
end
