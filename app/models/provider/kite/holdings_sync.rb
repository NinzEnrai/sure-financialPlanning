# frozen_string_literal: true

class Provider
  module Kite
    # Pulls equity/ETF holdings + open positions from Kite and reconciles them against
    # `securities`/`holdings`. `kite_account.current_account` resolves through the confirmed
    # `account_providers` polymorphic join (see KiteAccount#ensure_account_provider!) -- if no
    # Sure Account has been linked yet (user hasn't completed that one-time step during connect),
    # this is a no-op rather than an error, since Kite credentials can legitimately be configured
    # before the user picks which Account the holdings should land in.
    class HoldingsSync
      EXCHANGE_TO_MIC = { "NSE" => "XNSE", "BSE" => "XBOM" }.freeze

      def initialize(kite_item, kite_account)
        @kite_item = kite_item
        @kite_account = kite_account
        @client = kite_item.kite_client
      end

      def call
        account = kite_account.current_account
        return unless account

        # Provider-authored rows must carry the AccountProvider link. Without it
        # the balance materializer treats them as calculated rows it may purge,
        # Account::Syncer's anchor-gap check skips them, and KiteItem::Unlinking
        # cannot detach holdings from the provider link it destroys.
        account_provider = account.account_providers.find_by(provider_type: "KiteAccount")
        return if account_provider.nil?

        sync_rows(holdings_data, account, account_provider)
        sync_rows(positions_data, account, account_provider)

        kite_account.upsert_holdings_snapshot!(holdings_data)
        kite_item.record_sync!(kind: :holdings)
      end

      private

        attr_reader :kite_item, :kite_account, :client

        def holdings_data
          @holdings_data ||= client.get("/portfolio/holdings")["data"] || []
        end

        def positions_data
          (client.get("/portfolio/positions")["data"] || {})["net"] || []
        end

        def sync_rows(rows, account, account_provider)
          as_of = Date.current

          rows.each do |row|
            qty = row["quantity"].to_i
            next if qty.zero?

            security = find_or_create_security(row)
            external_id = "kite:#{row['tradingsymbol']}:#{row['exchange']}"

            holding = account.holdings.find_or_initialize_by(security: security, date: as_of, currency: "INR")
            next if holding.persisted? && holding.security_locked?

            holding.external_id = external_id
            holding.account_provider_id = account_provider.id
            holding.qty = qty
            holding.price = row["last_price"].to_d
            holding.amount = (row["last_price"].to_d * qty).round(2)
            holding.cost_basis = row["average_price"].to_d * qty if row["average_price"] && !holding.cost_basis_locked?
            holding.save!
          end
        end

        def find_or_create_security(row)
          mic = EXCHANGE_TO_MIC[row["exchange"]] || row["exchange"]

          Security.find_or_create_by!(ticker: row["tradingsymbol"], exchange_operating_mic: mic) do |sec|
            sec.name = row["tradingsymbol"]
            sec.isin = row["isin"]
            sec.country_code = "IN"
          end
        end
    end
  end
end
