# frozen_string_literal: true

# Phase 1: Indian market & currency support.
#
# CONFIRMED against db/schema.rb: `securities` already has `exchange_operating_mic` (MIC
# codes, e.g. "XNSE" for NSE, "XBOM" for BSE) with a unique index on
# upper(ticker)+COALESCE(upper(exchange_operating_mic),''), so NSE/BSE tickers are already
# handled correctly once Kite's exchange codes are mapped to MIC codes. Mutual funds need
# more: they have no ticker/exchange in the traditional sense, so we key them on ISIN and
# AMFI scheme code instead.
class AddIndianMarketSupport < ActiveRecord::Migration[8.1]
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

    # Display-format preference, independent of base currency. INR as `families.currency`
    # already works (standard ISO 4217 code); CONFIRMED `families.currency` exists and
    # defaults to "USD". Sits alongside the existing `families.date_format` column, which
    # is the same kind of per-family display preference.
    add_column :families, :number_format, :string, default: "western", null: false
    add_check_constraint :families, "number_format IN ('western', 'lakh_crore')",
                          name: "families_number_format_check"
  end
end
