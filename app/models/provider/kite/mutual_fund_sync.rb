# frozen_string_literal: true

class Provider
  module Kite
    class MutualFundSync
      def initialize(kite_item, kite_account)
        @kite_item = kite_item
        @kite_account = kite_account
        @client = kite_item.kite_client
      end

      def call
        account = kite_account.current_account
        return unless account

        # Same reason as HoldingsSync: provider-authored rows must carry the
        # AccountProvider link or the balance materializer treats them as
        # calculated rows and the unlinker cannot detach them.
        account_provider = account.account_providers.find_by(provider_type: "KiteAccount")
        return if account_provider.nil?

        as_of = Date.current

        mf_holdings.each do |row|
          security = find_or_create_fund(row)
          units = row["quantity"].to_d
          nav = row["last_price"].to_d

          holding = account.holdings.find_or_initialize_by(security: security, date: as_of, currency: "INR")
          next if holding.persisted? && holding.security_locked?

          holding.external_id = "kite_mf:#{row['folio']}:#{security.amfi_scheme_code}"
          holding.account_provider_id = account_provider.id
          holding.qty = units
          holding.price = nav
          holding.amount = (units * nav).round(2)
          holding.cost_basis = row["average_price"].to_d * units if row["average_price"] && !holding.cost_basis_locked?
          holding.save!
        end

        kite_account.upsert_holdings_snapshot!(mf_holdings)
        kite_item.record_sync!(kind: :mf)
      end

      private

        attr_reader :kite_item, :kite_account, :client

        def mf_holdings
          @mf_holdings ||= client.get("/mf/holdings")["data"] || []
        end

        def find_or_create_fund(row)
          scheme_code = row["tradingsymbol"] || row["fund"]
          Security.find_or_create_by!(amfi_scheme_code: scheme_code) do |sec|
            sec.ticker = scheme_code
            sec.name = row["fund"]
            sec.isin = row["isin"]
            sec.is_mutual_fund = true
            sec.country_code = "IN"
            # AMFI scheme codes are numeric MF identifiers, not exchange tickers:
            # sending one to a stock provider returns nothing. mfapi serves the
            # official AMFI daily NAV for exactly this code.
            sec.price_provider = "mfapi"
          end
        end
    end
  end
end
