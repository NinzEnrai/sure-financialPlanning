require "test_helper"

class FinancialPlanning::CapitalGainsEstimateTest < ActiveSupport::TestCase
  include PortfolioFlowTestHelper

  setup do
    @family = families(:dylan_family)
    @admin = users(:family_admin)
    @member = users(:family_member)
    @security = create_portfolio_security(ticker: "CG#{SecureRandom.hex(4)}")

    @admin_account = create_portfolio_account(@family, balance: 0)
    @admin_account.update!(owner: @admin)
    @member_account = create_portfolio_account(@family, balance: 0)
    @member_account.update!(owner: @member)
  end

  test "exempts long-term gains below the Indian threshold per person" do
    @family.update!(country: "IN")
    trade(account: @admin_account, qty: 10, price: 100, date: 2.years.ago.to_date)
    trade(account: @admin_account, qty: -10, price: 300, date: 1.month.ago.to_date)
    trade(account: @member_account, qty: 10, price: 100, date: 2.years.ago.to_date)
    trade(account: @member_account, qty: -10, price: 200, date: 1.month.ago.to_date)

    estimate = build_estimate
    admin = estimate.estimates.find { |person| person.owner == @admin }
    member = estimate.estimates.find { |person| person.owner == @member }

    assert_in_delta 2000, admin.long_term, 0.01
    assert_in_delta 2000, admin.exemption_used, 0.01
    assert_in_delta 0, admin.long_term_taxable, 0.01

    assert_in_delta 1000, member.exemption_used, 0.01
    assert_in_delta 0, estimate.total_taxable, 0.01
  end

  test "caps the exemption and leaves the excess taxable" do
    @family.update!(country: "IN")
    trade(account: @admin_account, qty: 100, price: 1000, date: 2.years.ago.to_date)
    trade(account: @admin_account, qty: -100, price: 3000, date: 1.month.ago.to_date)

    admin = build_estimate.estimates.find { |person| person.owner == @admin }

    assert_in_delta 200_000, admin.long_term, 0.01
    assert_in_delta 125_000, admin.exemption_used, 0.01
    assert_in_delta 75_000, admin.long_term_taxable, 0.01
  end

  test "offsets short-term losses against long-term gains before exempting" do
    @family.update!(country: "IN")
    short = create_portfolio_security(ticker: "ST#{SecureRandom.hex(4)}")
    long = create_portfolio_security(ticker: "LT#{SecureRandom.hex(4)}")

    trade(account: @admin_account, security: short, qty: 10, price: 100, date: 2.months.ago.to_date)
    trade(account: @admin_account, security: short, qty: -10, price: 50, date: 1.month.ago.to_date)
    trade(account: @admin_account, security: long, qty: 10, price: 100, date: 2.years.ago.to_date)
    trade(account: @admin_account, security: long, qty: -10, price: 200, date: 1.month.ago.to_date)

    admin = build_estimate.estimates.find { |person| person.owner == @admin }

    assert_in_delta(-500, admin.short_term, 0.01)
    assert_in_delta 1000, admin.long_term, 0.01
    # The loss reduces the long-term gain to 500, which the exemption covers.
    assert_in_delta 500, admin.exemption_used, 0.01
    assert_in_delta 0, admin.long_term_taxable, 0.01
  end

  test "carries long-term losses forward instead of netting them against short-term gains" do
    @family.update!(country: "IN")
    long = create_portfolio_security(ticker: "LL#{SecureRandom.hex(4)}")
    short = create_portfolio_security(ticker: "SS#{SecureRandom.hex(4)}")

    trade(account: @admin_account, security: long, qty: 10, price: 100, date: 2.years.ago.to_date)
    trade(account: @admin_account, security: long, qty: -10, price: 50, date: 1.month.ago.to_date)
    trade(account: @admin_account, security: short, qty: 10, price: 100, date: 2.months.ago.to_date)
    trade(account: @admin_account, security: short, qty: -10, price: 300, date: 1.month.ago.to_date)

    admin = build_estimate.estimates.find { |person| person.owner == @admin }

    assert_in_delta 2000, admin.short_term_taxable, 0.01
    assert_in_delta 0, admin.long_term_taxable, 0.01
    assert_in_delta 500, admin.carried_forward_loss, 0.01
  end

  test "keeps debt-fund gains slab-taxed and outside the exemption" do
    @family.update!(country: "IN")
    fund = Security.create!(ticker: "FUND#{SecureRandom.hex(4)}", name: "Debt fund", is_mutual_fund: true, asset_class: "fixed_income")
    trade(account: @admin_account, security: fund, qty: 10, price: 100, date: 2.years.ago.to_date)
    trade(account: @admin_account, security: fund, qty: -10, price: 200, date: 1.month.ago.to_date)

    admin = build_estimate.estimates.find { |person| person.owner == @admin }

    assert_in_delta 1000, admin.slab_gain, 0.01
    assert_in_delta 1000, admin.slab_taxable, 0.01
    assert_in_delta 0, admin.exemption_used, 0.01
    assert_in_delta 0, admin.long_term_taxable, 0.01
  end

  test "does not exempt non-Indian households" do
    trade(account: @admin_account, qty: 100, price: 1000, date: 2.years.ago.to_date)
    trade(account: @admin_account, qty: -100, price: 3000, date: 1.month.ago.to_date)

    admin = build_estimate.estimates.find { |person| person.owner == @admin }

    assert_not build_estimate.apply_exemption?
    assert_in_delta 0, admin.exemption_used, 0.01
    assert_in_delta 200_000, admin.long_term_taxable, 0.01
  end

  test "is empty when nothing has been sold" do
    trade(account: @admin_account, qty: 10, price: 100, date: 2.months.ago.to_date)

    assert_not build_estimate.any?
  end

  private
    def build_estimate
      FinancialPlanning::CapitalGainsEstimate.new(@family, user: @admin)
    end

    def trade(account:, qty:, price:, date:, security: @security)
      create_portfolio_trade(account: account, security: security, qty: qty, price: price, date: date)
    end
end
