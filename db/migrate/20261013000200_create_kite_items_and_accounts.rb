# frozen_string_literal: true

# Phase 2: Zerodha Kite Connect, matching the `*_items` / `*_accounts` convention already used
# by plaid_items/plaid_accounts, snaptrade_items/snaptrade_accounts, mercury_items/mercury_accounts
# etc. in your schema -- a `kite_items` row per family (one set of Kite Connect API credentials +
# the daily session token), and `kite_accounts` rows underneath it (Zerodha's single login covers
# both equity/ETF holdings and Coin mutual funds, which we model as two logical sub-accounts since
# they map to two different `Account` records on your side -- one Investment account for equities,
# one for mutual funds -- same way snaptrade_accounts has one row per brokerage sub-account).
#
# CONFIRMED against db/schema.rb: `account_providers` has the (provider_type, provider_id,
# account_id) polymorphic columns plus a unique index on each pair, so KiteAccount links into
# `accounts` the same way SnaptradeAccount does. No change needed on that table -- KiteAccount
# only has to be a valid `provider_type` value, which is a Ruby-level concern (the model's
# class name), not a schema one.
#
# An earlier `kite_connections` migration was dropped: it stored the same api_key/api_secret/
# access_token as this table, and nothing referenced it. One credential store, not two.
class CreateKiteItemsAndAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :kite_items, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      # One item per family. The uniqueness is declared here rather than as a
      # separate add_index below, because t.references already emits an index
      # named index_kite_items_on_family_id -- a standalone add_index on the
      # same column would collide on that name.
      t.references :family, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.string   :name # user-facing label, e.g. "Zerodha" -- mirrors plaid_items.name / snaptrade_items.name

      # Deliberately NO api_key / api_secret columns. Those are deployment-wide,
      # long-lived and set once, so they live in the environment
      # (KITE_API_KEY / KITE_API_SECRET) and never touch the database. Anything
      # in a column ends up in pg_dump backups and in any restore onto another
      # machine; the daily session token below is the only secret persisted, and
      # it expires every trading day.
      #
      # access_token is encrypted via `encrypts` in the model when ActiveRecord
      # encryption is configured (plain `:text` column, no `encrypted_` prefix
      # needed). It falls back to plaintext when encryption is not configured,
      # which is acceptable only because of that day-scoped lifetime.
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
    add_index :kite_accounts, [ :kite_item_id, :segment ], unique: true
  end
end
