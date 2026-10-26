require "test_helper"
require "ostruct"

# A Zerodha account with no balance anchor materializes to 0.00: the reverse
# calculator derives cash as the negative of the holdings and the two cancel.
class Provider::Kite::BalanceSyncTest < ActiveSupport::TestCase
  test "anchors the account to holdings market value plus reported cash" do
    account, kite_account, kite_item = build_linked_account
    create_holding(account, qty: 10, price: 100) # 1,000
    stub_margins(kite_item, net: 250)

    Provider::Kite::BalanceSync.new(kite_item, kite_account).call

    assert_equal BigDecimal("1250"), account.reload.balance
    assert account.has_current_anchor?
    assert_equal BigDecimal("1250"), account.current_anchor_balance
  end

  # A delivery portfolio leaves /user/margins at zero, which is the normal case
  # and must still anchor -- otherwise nothing changes for most Kite users.
  test "anchors to the holdings alone when Kite reports no cash" do
    account, kite_account, kite_item = build_linked_account
    create_holding(account, qty: 4, price: 25) # 100
    stub_margins(kite_item, net: 0)

    Provider::Kite::BalanceSync.new(kite_item, kite_account).call

    assert_equal BigDecimal("100"), account.reload.balance
  end

  # Holdings carry one row per date; summing every date would count yesterday's
  # position again on top of today's.
  test "counts only the latest holdings snapshot" do
    account, kite_account, kite_item = build_linked_account
    security = create_security
    account.holdings.create!(security: security, date: Date.current - 1, qty: 10, price: 50,
                             amount: 500, currency: "INR")
    account.holdings.create!(security: security, date: Date.current, qty: 10, price: 60,
                             amount: 600, currency: "INR")
    stub_margins(kite_item, net: 0)

    Provider::Kite::BalanceSync.new(kite_item, kite_account).call

    assert_equal BigDecimal("600"), account.reload.balance
  end

  test "a mutual fund account has no margin segment and anchors to holdings" do
    account, kite_account, kite_item = build_linked_account(segment: "mutual_fund")
    create_holding(account, qty: 2_000, price: 20) # 40,000

    Provider::Kite::BalanceSync.new(kite_item, kite_account).call

    assert_equal BigDecimal("40000"), account.reload.balance
  end

  test "leaves the account untouched when nothing is held yet" do
    account, kite_account, kite_item = build_linked_account
    stub_margins(kite_item, net: 0)

    Provider::Kite::BalanceSync.new(kite_item, kite_account).call

    assert_equal BigDecimal("0"), account.reload.balance
    assert_not account.has_current_anchor?
  end

  private

    def build_linked_account(segment: "equity")
      family = families(:dylan_family)
      kite_item = family.create_kite_item!(name: "Zerodha")
      kite_account = kite_item.kite_accounts.create!(segment: segment, name: "Zerodha", currency: "INR")
      account = family.accounts.create!(name: "Zerodha #{segment}", balance: 0, currency: "INR",
                                        accountable: Investment.new)
      kite_account.ensure_account_provider!(account)
      [ account.reload, kite_account, kite_item ]
    end

    def create_security
      Security.create!(
        ticker: "AAVAS", exchange_operating_mic: "XNSE", country_code: "IN"
      )
    end

    def create_holding(account, qty:, price:)
      account.holdings.create!(
        security: create_security, date: Date.current,
        qty: qty, price: price, amount: qty * price, currency: "INR"
      )
    end

    def stub_margins(kite_item, net:)
      client = mock("kite_client")
      client.stubs(:get).with("/user/margins").returns({ "data" => { "equity" => { "net" => net } } })
      kite_item.stubs(:kite_client).returns(client)
    end
end
