# frozen_string_literal: true

module Provider
  module Kite
    class MutualFundSync
      def initialize(kite_item)
        @kite_item = kite_item
        @client = Client.new(kite_item)
      end

      def call
        return unless kite_item.token_valid?

        kite_account = kite_item.mutual_fund_account
        account = kite_account.current_account
        
        return unless account && !account.pending_deletion? && !account.disabled?

        as_of = Date.current

        mf_holdings.each do |row|
          security = find_or_create_fund(row)
          units = row["quantity"].to_d
          nav = row["last_price"].to_d

          holding = account.holdings.find_or_initialize_by(security: security, date: as_of, currency: "INR")
          next if holding.persisted? && holding.security_locked?

          holding.external_id = "kite_mf:#{row['folio']}:#{security.amfi_scheme_code}"
          holding.qty = units
          holding.price = nav
          holding.amount = (units * nav).round(2)
          holding.cost_basis = row["average_price"].to_d * units if row["average_price"] && !holding.cost_basis_locked?
          holding.save!
        end

        kite_item.record_sync!(kind: :mf)
        kite_item.mark_active!
      rescue Client::AuthenticationExpired
        # Handled in Client
      end

      private

      attr_reader :kite_item, :client

      def mf_holdings
        client.get("/mf/holdings")["data"] || []
      end

      def find_or_create_fund(row)
        scheme_code = row["tradingsymbol"] || row["fund"]
        Security.find_or_create_by!(amfi_scheme_code: scheme_code) do |sec|
          sec.ticker = scheme_code
          sec.name = row["fund"]
          sec.isin = row["isin"]
          sec.is_mutual_fund = true
          sec.country_code = "IN"
        end
      end
    end
  end
end