# frozen_string_literal: true

# Phase 2: Zerodha Kite Connect, matching the `*_items` / `*_accounts` convention already used
# by plaid_items/plaid_accounts, snaptrade_items/snaptrade_accounts, mercury_items/mercury_accounts
# etc. in your schema -- a `kite_items` row per family (one set of Kite Connect API credentials +
# the daily session token), and `kite_accounts` rows underneath it (Zerodha's single login covers
# both equity/ETF holdings and Coin mutual funds, which we model as two logical sub-accounts since
# they map to two different `Account` records on your side -- one Investment account for equities,
# one for mutual funds -- same way snaptrade_accounts has one row per brokerage sub-account).
#
# GAP: I don't have your `account_providers` table definition (it's referenced by
# `holdings.account_provider_id` but wasn't in the schema excerpt you shared, since the paste
# started at `family_documents` alphabetically -- `account_providers` sorts earlier). The newer
# providers in your app (SnapTrade, Mercury, etc.) appear to link into `accounts` through
# `account_providers` rather than a direct FK column on `accounts` itself (only plaid_accounts and
# simplefin_accounts get a direct FK per your `add_foreign_key "accounts", ...` list). Once you
# share `account_providers`' columns (and ideally the SnapTrade model, since it's architecturally
# closest to Kite -- both are brokerage-holdings providers), I'll wire `kite_accounts` into it the
# same way rather than leaving that connection unspecified.
class CreateKiteItemsAndAccounts < ActiveRecord::Migration[7.1]
  def change
    create_table :kite_items, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :family, type: :uuid, null: false, foreign_key: true
      t.string   :name # user-facing label, e.g. "Zerodha" -- mirrors plaid_items.name / snaptrade_items.name

      # Rails ActiveRecord::Encryption via `encrypts` in the model, same pattern your
      # plaid_items.access_token / snaptrade_items.snaptrade_user_secret already use
      # (plain `string`/`text` columns, no `encrypted_` prefix needed).
      t.string   :api_key
      t.string   :api_secret
      t.text     :access_token
      t.string   :kite_user_id

      t.datetime :access_token_issued_at
      t.datetime :access_token_expires_at
      # CONFIRMED: matches plaid_items/snaptrade_items' `status` convention exactly --
      # string column, enum in the model, default "good". "requires_update" covers both
      # "needs Zerodha re-login" and "something's wrong, needs attention" -- Kite's daily
      # token expiry doesn't need its own DB-level status beyond that, `last_error` carries detail.
      t.string   :status, null: false, default: "good"
      t.boolean  :scheduled_for_deletion, default: false
      t.date     :sync_start_date
      t.datetime :last_synced_at
      t.datetime :last_mf_synced_at
      t.text     :last_error
      t.jsonb    :raw_payload, default: {}

      t.timestamps
    end
    add_check_constraint :kite_items, "status IN ('good','requires_update')", name: "kite_items_status_check"
    add_index :kite_items, :family_id, unique: true

    create_table :kite_accounts, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :kite_item, type: :uuid, null: false, foreign_key: true
      t.string  :name
      t.string  :segment, null: false # "equity" | "mutual_fund"
      t.string  :account_status, default: "active"
      t.decimal :current_balance, precision: 19, scale: 4
      t.string  :currency, default: "INR"
      t.jsonb   :raw_payload, default: {}
      t.jsonb   :raw_holdings_payload, default: {}
      t.datetime :last_holdings_sync
      t.timestamps
    end
    add_index :kite_accounts, [:kite_item_id, :segment], unique: true

    # `account_providers` already supports this polymorphic linkage (provider_type: "KiteAccount",
    # provider_id: kite_accounts.id, account_id: <Account>) per SnaptradeAccount's identical use --
    # no new migration needed on that table, KiteAccount just needs to be a valid `provider_type`
    # value, which is a Ruby-level concern (the model's class name), not a schema one.
  end
end
