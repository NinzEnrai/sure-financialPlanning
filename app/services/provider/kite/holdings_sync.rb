# frozen_string_literal: true

module Provider
  module Kite
    class HoldingsSync
      EXCHANGE_TO_MIC = { "NSE" => "XNSE", "BSE" => "XBOM" }.freeze

      def initialize(kite_item)
        @kite_item = kite_item
        @client = Client.new(kite_item)
      end

      def call
        return unless kite_item.token_valid?

        kite_account = kite_item.equity_account
        account = kite_account.current_account
        
        # Guard against unlinked or deleted accounts
        return unless account && !account.pending_deletion? && !account.disabled?

        sync_rows(holdings_data, account)
        sync_rows(positions_data, account)

        kite_item.record_sync!(kind: :holdings)
        kite_item.mark_active!
      rescue Client::AuthenticationExpired
        # Handled in Client
      end

      private

      attr_reader :kite_item, :client

      def holdings_data
        client.get("/portfolio/holdings")["data"] || []
      end

      def positions_data
        (client.get("/portfolio/positions")["data"] || {})["net"] || []
      end

      def sync_rows(rows, account)
        as_of = Date.current

        rows.each do |row|
          qty = row["quantity"].to_i
          next if qty.zero?

          security = find_or_create_security(row)
          external_id = "kite:#{row['tradingsymbol']}:#{row['exchange']}"

          holding = account.holdings.find_or_initialize_by(security: security, date: as_of, currency: "INR")
          next if holding.persisted? && holding.security_locked?

          holding.external_id = external_id
          holding.qty = qty
          holding.price = row["last_price"].to_d
          holding.amount = (row["last_price"].to_d * qty).round(2)
          holding.cost_basis = row["average_price"].to_d * qty if row["average_price"] && !holding.cost_basis_locked?
          holding.cost_basis_source = "kite" if holding.respond_to?(:cost_basis_source=) && !holding.cost_basis_locked?
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