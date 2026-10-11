# frozen_string_literal: true

module Provider
  module Kite
    class TradeImporter
      def initialize(kite_item)
        @kite_item = kite_item
        @client = Client.new(kite_item)
      end

      def call
        return unless kite_item.token_valid?

        kite_account = kite_item.equity_account
        account = kite_account.current_account
        
        return unless account && !account.pending_deletion? && !account.disabled?

        trades_data.each do |row|
          mic = HoldingsSync::EXCHANGE_TO_MIC[row["exchange"]] || row["exchange"]
          security = Security.find_by(ticker: row["tradingsymbol"], exchange_operating_mic: mic)
          next unless security

          next if already_imported?(account, security, row)

          import_trade!(account, security, row)
        end

        kite_item.mark_active!
      rescue Client::AuthenticationExpired
        # Handled in Client
      end

      private

      attr_reader :kite_item, :client

      def trades_data
        client.get("/trades")["data"] || []
      end

      def already_imported?(account, security, row)
        trade_date = Date.parse(row["fill_timestamp"] || row["order_timestamp"])
        Entry.joins("INNER JOIN trades ON trades.id = entries.entryable_id AND entries.entryable_type = 'Trade'")
             .where(account: account, date: trade_date)
             .where(trades: { security_id: security.id, qty: signed_qty(row), price: row["average_price"].to_d })
             .exists?
      end

      def signed_qty(row)
        qty = row["quantity"].to_d
        row["transaction_type"] == "SELL" ? -qty : qty
      end

      def import_trade!(account, security, row)
        ActiveRecord::Base.transaction do
          trade = Trade.create!(
            security: security,
            qty: signed_qty(row),
            price: row["average_price"].to_d,
            currency: "INR",
            investment_activity_label: row["transaction_type"]&.downcase
          )

          Entry.create!(
            account: account,
            entryable: trade,
            amount: (row["average_price"].to_d * row["quantity"].to_d).round(2),
            currency: "INR",
            date: Date.parse(row["fill_timestamp"] || row["order_timestamp"]),
            name: "#{row['transaction_type']} #{row['tradingsymbol']}"
          )
        end
      rescue => e
        Rails.logger.error("[Kite::TradeImporter] failed to import trade #{row['trade_id']}: #{e.message}")
      end
    end
  end
end