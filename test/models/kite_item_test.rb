require "test_helper"

class KiteItemTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @family = families(:dylan_family)
    @item = KiteItem.create!(family: @family, name: "Zerodha")
  end

  test "requires a name" do
    item = KiteItem.new(family: @family)

    assert_not item.valid?
    assert_includes item.errors[:name], "can't be blank"
  end

  test "api credentials come from the environment, not the database" do
    # Deliberately NOT columns on the record: pg_dump captures every column, and
    # these are long-lived deployment secrets. See the KiteItem class comment.
    assert_not KiteItem.column_names.include?("api_key")
    assert_not KiteItem.column_names.include?("api_secret")

    original_key = ENV["KITE_API_KEY"]
    original_secret = ENV["KITE_API_SECRET"]

    ENV["KITE_API_KEY"] = "from_env_key"
    ENV["KITE_API_SECRET"] = "from_env_secret"
    assert_equal "from_env_key", KiteItem.api_key
    assert_equal "from_env_secret", KiteItem.api_secret
    assert_equal "from_env_key", @item.api_key
    assert @item.credentials_configured?

    ENV.delete("KITE_API_KEY")
    assert_not @item.credentials_configured?
  ensure
    ENV["KITE_API_KEY"] = original_key
    ENV["KITE_API_SECRET"] = original_secret
  end

  test "credentials_configured? is false when only one half is set" do
    original_key = ENV["KITE_API_KEY"]
    original_secret = ENV["KITE_API_SECRET"]

    ENV["KITE_API_KEY"] = "only_key"
    ENV.delete("KITE_API_SECRET")
    assert_not @item.credentials_configured?
  ensure
    ENV["KITE_API_KEY"] = original_key
    ENV["KITE_API_SECRET"] = original_secret
  end

  test "token_valid? requires an unexpired token" do
    assert_not @item.token_valid?, "no token yet"

    @item.update!(access_token: "tok", access_token_expires_at: 1.hour.from_now)
    assert @item.token_valid?

    @item.update!(access_token_expires_at: 1.hour.ago)
    assert_not @item.token_valid?
  end

  test "mark_needs_reauth! clears the token and records the reason" do
    @item.update!(access_token: "tok", access_token_expires_at: 1.hour.from_now)

    @item.mark_needs_reauth!(reason: "expired")

    assert @item.requires_update?
    assert_equal "expired", @item.last_error
    # The dead token is dropped rather than left to fail every later request.
    assert_nil @item.access_token
    assert_nil @item.access_token_expires_at
  end

  test "syncable requires active status, good health and a live token" do
    assert_not KiteItem.syncable.include?(@item), "no token yet"

    @item.update!(access_token: "tok", access_token_expires_at: 1.hour.from_now)
    assert KiteItem.syncable.include?(@item)

    @item.update!(scheduled_for_deletion: true)
    assert_not KiteItem.syncable.include?(@item)
  end

  test "destroy_later schedules deletion instead of removing the row" do
    assert_difference -> { KiteItem.count }, 0 do
      @item.destroy_later
    end

    @item.reload
    assert @item.scheduled_for_deletion?
    assert_not KiteItem.active.include?(@item)
  end

  test "family exposes exactly one kite item" do
    assert_equal :has_one, Family.reflect_on_association(:kite_item).macro
    assert_equal @item, @family.kite_item
  end

  test "does not include Syncable, so last_synced_at reads the column" do
    # Kite syncs are cron-scheduled, not Syncable-scheduled, so Syncable was
    # dropped. It also shadowed the last_synced_at column with a method that
    # returned nil forever (no Sync is ever created for a KiteItem), which made
    # record_sync! write a timestamp nothing could read.
    refute_includes KiteItem.ancestors, Syncable

    @item.record_sync!(kind: :holdings)
    assert_not_nil @item.reload.last_synced_at
  end

  test "equity and mutual fund sub-accounts are created once each" do
    equity = @item.equity_kite_account
    mf = @item.mutual_fund_kite_account

    assert_equal "equity", equity.segment
    assert_equal "mutual_fund", mf.segment
    assert_equal 2, @item.kite_accounts.reload.count

    # Idempotent -- a second call must not try to violate the unique index.
    assert_equal equity.id, @item.equity_kite_account.id
    assert_equal 2, @item.kite_accounts.reload.count
  end

  test "sync_status_summary reports no accounts before any are created" do
    assert_equal I18n.t("models.kite_item.sync_status.no_accounts"), @item.sync_status_summary
  end

  test "sync_status_summary counts unlinked sub-accounts" do
    @item.equity_kite_account
    assert_equal I18n.t("models.kite_item.sync_status.synced_with_setup", linked: 0, unlinked: 1), @item.sync_status_summary

    @item.mutual_fund_kite_account
    @item.equity_kite_account.ensure_account_provider!(@family.accounts.first)

    assert_equal I18n.t("models.kite_item.sync_status.synced_with_setup", linked: 1, unlinked: 1), @item.sync_status_summary
  end

  test "sync_status_summary reports synced once every sub-account is linked" do
    @item.equity_kite_account.ensure_account_provider!(@family.accounts.first)
    @item.mutual_fund_kite_account.ensure_account_provider!(@family.accounts.last)

    assert_equal I18n.t("models.kite_item.sync_status.synced", count: 2), @item.sync_status_summary
  end
end
