# frozen_string_literal: true

# Phase 1: Indian market & currency support.
#
# CONFIRMED against your schema: `securities` already has `exchange_operating_mic` (MIC codes,
# e.g. "XNSE" for NSE, "XBOM" for BSE) with a unique index on upper(ticker)+exchange_operating_mic,
# so NSE/BSE tickers are already handled correctly once Kite's exchange codes are mapped to MIC
# codes (NSE -> XNSE, BSE -> XBOM). We only need to add ISIN and AMFI scheme code for mutual funds,
# which have no ticker/exchange in the traditional sense.
class AddIndianMarketSupport < ActiveRecord::Migration[7.1]
  def change
    change_table :securities, bulk: true do |t|
      t.string  :isin                      # e.g. "INE002A01018" -- also useful for equities (dedup across data vendors)
      t.string  :amfi_scheme_code           # Mutual fund scheme code, e.g. "120503"; used as `ticker` for MF securities
      t.boolean :is_mutual_fund, default: false, null: false
      # ^ lets market-data-fetch jobs (the ones that set failed_fetch_at/offline on securities)
      # skip mutual funds, since their NAV comes from Kite/Coin directly, not your existing price provider.
    end

    add_index :securities, :isin, unique: true, where: "isin IS NOT NULL"
    add_index :securities, :amfi_scheme_code, unique: true, where: "amfi_scheme_code IS NOT NULL"

    # Display-format preference, independent of base currency. INR as `families.currency` should
    # already work (standard ISO 4217 code) -- I didn't see the `families` table in what you
    # pasted so I can't confirm the column name; adjust if it's not `currency`.
    add_column :families, :number_format, :string, default: "western", null: false
    add_check_constraint :families, "number_format IN ('western', 'lakh_crore')",
                          name: "families_number_format_check"
  end
end
