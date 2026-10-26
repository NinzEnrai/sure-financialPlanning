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
          # cost_basis is a PER-SHARE figure: Holding#avg_cost reads it straight
          # back as "average cost per share". Kite's average_price is already per
          # unit, so multiplying by units made the reported cost 500-2000x too
          # large and turned a small gain into a multi-crore loss.
          if row["average_price"].to_d.positive? && !holding.cost_basis_locked?
            holding.cost_basis = row["average_price"].to_d
            holding.cost_basis_source = "provider"
          end
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

        # Zerodha names a fund by ISIN ("INF959L01FX6"); the AMFI NAV feed is
        # keyed by scheme code ("149892"), and mfapi answers 400 to an ISIN. So
        # resolve the real scheme code and use it as the ticker -- the ticker is
        # what Security::Provided passes to the provider as the symbol. An
        # unresolvable ISIN falls back to itself so the holding still imports;
        # it simply stays unpriced until AMFI publishes that fund.
        def find_or_create_fund(row)
          raw = (row["tradingsymbol"].presence || row["fund"]).to_s
          isin = row["isin"].presence
          isin = raw if isin.blank? && AmfiSchemeIndex.isin?(raw)
          scheme_code = AmfiSchemeIndex.scheme_code_for(isin)

          security = find_existing_fund(isin: isin, scheme_code: scheme_code, raw: raw)
          security.ticker = scheme_code.presence || raw
          security.name = row["fund"] if row["fund"].present?
          security.isin = isin if isin.present?
          security.amfi_scheme_code = scheme_code.presence || raw
          security.is_mutual_fund = true
          security.country_code = "IN"
          # AMFI scheme codes are numeric MF identifiers, not exchange tickers:
          # sending one to a stock provider returns nothing. mfapi serves the
          # official AMFI daily NAV for exactly this code.
          security.price_provider ||= "mfapi"
          security.save!
          security
        end

        # Matched by ISIN first so funds imported before the ISIN lookup existed
        # are corrected in place rather than duplicated alongside their own
        # holdings.
        def find_existing_fund(isin:, scheme_code:, raw:)
          (Security.find_by(isin: isin) if isin.present?) ||
            (Security.find_by(amfi_scheme_code: scheme_code) if scheme_code.present?) ||
            Security.find_by(ticker: raw) ||
            Security.new
        end
    end
  end
end
