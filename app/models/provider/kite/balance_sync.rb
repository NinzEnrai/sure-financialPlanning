# frozen_string_literal: true

class Provider
  module Kite
    # Gives a linked Zerodha account a balance anchor.
    #
    # Zerodha reports what you hold, not what you deposited. Without an anchor,
    # Balance::ReverseCalculator has no total to work back from and derives cash
    # as the negative of the holdings, so the two cancel and the account reads
    # 0.00 -- invisible on the accounts page, absent from net worth, FIRE and the
    # wealth projection, even though the holdings themselves imported fine.
    #
    # The anchor is holdings market value plus whatever cash Kite reports. A
    # delivery portfolio usually leaves /user/margins flat at zero, so the anchor
    # is just the holdings.
    class BalanceSync
      def initialize(kite_item, kite_account)
        @kite_item = kite_item
        @kite_account = kite_account
      end

      def call
        account = kite_account.current_account
        return if account.nil?

        value = holdings_value
        return if value.zero?

        # schedule_sync: false -- KiteItem::Importer schedules the account sync
        # itself straight afterwards, and this call must not enqueue a second one.
        account.set_current_balance(value + cash, date: Date.current, schedule_sync: false)
      end

      private

        attr_reader :kite_item, :kite_account

        def account
          @account ||= kite_account.current_account
        end

        # Only the latest snapshot counts: holdings carry one row per date, so
        # summing across dates would double-count every previous day's position.
        def holdings_value
          latest_date = account.holdings.maximum(:date)
          return BigDecimal("0") if latest_date.nil?

          account.holdings.where(date: latest_date).sum(:amount)
        end

        # Kite's margin "net" is the cash side of the account. Mutual fund
        # holdings (Coin) have no margin segment at all, so their cash is nil.
        def cash
          return BigDecimal("0") unless kite_account.segment == "equity"

          BigDecimal(margins.fetch("equity", {}).fetch("net", 0).to_s)
        rescue StandardError => e
          # A missing margin figure must not cost us the holdings anchor: without
          # the cash component the portfolio value is still far closer than zero.
          Rails.logger.warn(
            "Kite::BalanceSync##{kite_account.id} could not read margins: #{e.class} - #{e.message}"
          )
          BigDecimal("0")
        end

        def margins
          @margins ||= kite_item.kite_client.get("/user/margins")["data"] || {}
        end
    end
  end
end
