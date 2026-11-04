require "test_helper"

class FinancialPlanning::DataConfidenceTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @account = accounts(:investment)

    # The fixtures carry a priced, traded holding; remove it so each check is
    # driven by data this test sets up deliberately.
    Security::Price.delete_all
    Entry.where(entryable_type: "Trade").delete_all
    Trade.delete_all
    Holding.delete_all

    @security = Security.create!(ticker: "CONF#{SecureRandom.hex(4)}", name: "Confidence test")
    Holding.create!(
      account: @account,
      security: @security,
      date: Date.current,
      qty: 1,
      price: 100,
      amount: 100,
      currency: "USD"
    )
  end

  test "flags stale prices and missing purchase dates for held securities" do
    confidence = build_confidence

    assert_equal :watch, check(confidence, :price_history).status
    assert_equal 1, check(confidence, :price_history).count
    assert_equal :watch, check(confidence, :purchase_dates).status
    assert_equal 1, check(confidence, :purchase_dates).count
  end

  test "a fresh price and a recorded trade clear the price and purchase checks" do
    Security::Price.create!(security: @security, date: Date.current, price: 100, currency: "USD")
    create_trade(@security, account: @account, qty: 1, date: Date.current, price: 100)

    confidence = build_confidence

    assert_equal :good, check(confidence, :price_history).status
    assert_equal :good, check(confidence, :purchase_dates).status
  end

  test "a foreign account without today's rate needs attention" do
    @family.accounts.create!(
      name: "Euro cash",
      balance: 100,
      currency: "EUR",
      accountable: Depository.new,
      owner: @user,
      status: "active"
    )

    confidence = build_confidence

    assert_equal :attention, check(confidence, :exchange_rates).status
    assert_equal 1, check(confidence, :exchange_rates).count
    assert_equal 1, check(confidence, :exchange_rates).total

    ExchangeRate.create!(from_currency: "EUR", to_currency: @family.currency, date: Date.current, rate: 1.1)

    assert_equal :good, check(build_confidence, :exchange_rates).status
  end

  test "unclassified securities and excluded accounts are watch items" do
    confidence = build_confidence

    assert_equal :watch, check(confidence, :classification).status
    assert_equal 1, check(confidence, :classification).count
    assert_equal :good, check(confidence, :excluded_accounts).status

    @security.update!(asset_class: "equity", classification_source: "provider")
    accounts(:depository).update!(exclude_from_reports: true)

    confidence = build_confidence

    assert_equal :good, check(confidence, :classification).status
    assert_equal :watch, check(confidence, :excluded_accounts).status
    assert_equal 1, check(confidence, :excluded_accounts).count
  end

  test "is healthy only when every input is complete" do
    Security::Price.create!(security: @security, date: Date.current, price: 100, currency: "USD")
    create_trade(@security, account: @account, qty: 1, date: Date.current, price: 100)
    @security.update!(asset_class: "equity", classification_source: "provider")

    confidence = build_confidence

    assert confidence.healthy?
    assert_equal 0, confidence.issue_count
  end

  private
    def build_confidence
      FinancialPlanning::DataConfidence.new(@family, user: @user)
    end

    def check(confidence, key)
      confidence.checks.find { |candidate| candidate.key == key }
    end
end
