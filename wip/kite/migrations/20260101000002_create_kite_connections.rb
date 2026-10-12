# frozen_string_literal: true

# Phase 2: Zerodha Kite Connect credentials + connection state.
#
# One connection per Family (adjust to `belongs_to :user` if credentials should be
# per-user rather than per-household in your schema).
class CreateKiteConnections < ActiveRecord::Migration[7.1]
  def change
    create_table :kite_connections, id: :uuid do |t|
      t.references :family, type: :uuid, null: false, foreign_key: true, index: { unique: true }

      # Encrypted via ActiveRecord::Encryption (`encrypts` in the model) -> stored as ciphertext,
      # so these are deliberately plain `:string`/`:text` columns, no `encrypted_` prefix needed,
      # Rails handles it transparently. Never select/log these outside the model.
      t.string :api_key                 # Kite Connect app's public API key (still sensitive-ish; encrypt anyway)
      t.string :api_secret               # Kite Connect app's secret - MUST be encrypted
      t.text   :access_token             # Day-scoped session token - MUST be encrypted
      t.string :kite_user_id             # Zerodha client id (e.g. "AB1234"), for display/debugging only

      t.datetime :access_token_issued_at
      t.datetime :access_token_expires_at   # Kite tokens expire ~ next trading day; we store Zerodha's stated expiry
      t.string   :status, null: false, default: "pending_auth"
      # pending_auth | active | needs_reauth | rate_limited | error | disabled

      t.text     :last_error
      t.datetime :last_synced_at
      t.datetime :last_mf_synced_at

      t.timestamps
    end

    add_check_constraint :kite_connections,
      "status IN ('pending_auth','active','needs_reauth','rate_limited','error','disabled')",
      name: "kite_connections_status_check"
  end
end
