require "test_helper"

class KiteAccountTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @item = KiteItem.create!(family: @family, name: "Zerodha")
    @item.update!(access_token: "tok", access_token_expires_at: 1.hour.from_now)
    @kite_account = @item.equity_kite_account
    @account = @family.accounts.first
  end

  test "requires a known segment" do
    assert_not KiteAccount.new(kite_item: @item, name: "x", currency: "INR", segment: "crypto").valid?
    assert KiteAccount.new(kite_item: @item, name: "x", currency: "INR", segment: "equity").valid?
  end

  test "ensure_account_provider! links a Sure account idempotently" do
    link = @kite_account.ensure_account_provider!(@account)

    assert link.persisted?
    assert_equal @account.id, link.account_id
    assert_equal "KiteAccount", link.provider_type
    assert_equal @kite_account.id, link.provider_id
    assert_equal @account, @kite_account.reload.current_account

    # A second call returns the same link rather than creating a duplicate.
    assert_equal link.id, @kite_account.ensure_account_provider!(@account).id
    assert_equal 1, AccountProvider.where(provider_type: "KiteAccount", provider_id: @kite_account.id).count
  end

  test "ensure_account_provider! returns nil when there is no account to link" do
    assert_nil @kite_account.ensure_account_provider!
    assert_nil @kite_account.current_account
  end

  test "item accounts exposes the linked Sure accounts" do
    assert_empty @item.accounts

    @kite_account.ensure_account_provider!(@account)
    assert_equal [ @account ], @item.reload.accounts
  end

  test "unlink_all! detaches holdings and destroys provider links" do
    @kite_account.ensure_account_provider!(@account)
    link_id = @kite_account.account_provider.id

    holding = @account.holdings.create!(
      security: securities(:aapl),
      date: Date.current,
      qty: 1,
      price: 100,
      amount: 100,
      currency: "USD"
    )
    holding.update!(account_provider_id: link_id)

    results = @item.unlink_all!

    assert_equal 1, results.size
    assert_equal @kite_account.id, results.first[:provider_account_id]

    assert_equal 0, AccountProvider.where(provider_type: "KiteAccount", provider_id: @kite_account.id).count
    # The holding survives, detached -- it is family-owned data, not provider state.
    assert_nil holding.reload.account_provider_id
    assert_nothing_raised { @account.reload }
  end

  test "unlink_all! leaves the Sure accounts themselves in place" do
    @kite_account.ensure_account_provider!(@account)

    assert_no_difference -> { Account.count } do
      @item.unlink_all!
    end

    assert_equal @account.id, @account.reload.id
  end

  test "unlink_all! is a dry run when asked" do
    @kite_account.ensure_account_provider!(@account)

    assert_no_difference -> { AccountProvider.count } do
      @item.unlink_all!(dry_run: true)
    end
  end

  test "unlink_all! is idempotent" do
    @kite_account.ensure_account_provider!(@account)

    assert_nothing_raised do
      @item.unlink_all!
      @item.unlink_all!
    end
  end
end
