# FIFO tax lots over the trades in a set of accounts.
#
# Average cost answers "what is this position worth"; tax asks "which shares
# were sold, and when were they bought", and only lots can answer that. This is
# a pure function over stored trades: no schema, no writes, no tax rates.
#
# Scope is an account list, not a family. Tax is assessed per person, so the
# caller passes the accounts owned by one person (or the whole family when the
# owner is not being split); the engine deliberately does not re-filter.
#
# Rules, stated because each one can change a tax figure:
#
#   * FIFO. The oldest lot is consumed first, always.
#   * Fees are capitalised: a buy's fee joins its cost basis, and a sell's fee
#     is allocated across the chunks it consumes, reducing proceeds.
#   * Splits are applied at the open of their ex-date, before that day's trades
#     (Security::Split's own rule), scaling open lots and cost per share.
#   * Internal movements (transfer, sweep) are ignored: they move ownership
#     between the caller's own accounts, so within one scope they are not a
#     disposal. A position that arrived only by transfer has no purchase date
#     here — that is a data gap the caller must surface, not paper over.
#   * A sell with no matching buy is reported as unknown-origin rather than
#     given a fabricated cost basis.
#
# Foreign currency is left on each lot: converting to the basis currency needs
# the rate on the lot's own acquisition date, which is a later caller's job.
# Security-for-security exchanges are also out of scope here; they dispose of
# one asset to acquire another and need a valuation rule this engine does not
# own.
class Portfolio::TaxLots
  Lot = Data.define(:security, :acquired_on, :qty, :cost_per_unit, :currency) do
    def total_cost
      (qty * cost_per_unit).round(2)
    end
  end

  Realisation = Data.define(
    :security, :acquired_on, :sold_on, :qty, :cost_per_unit, :proceeds_per_unit, :fee_allocated, :currency, :unknown_origin
  ) do
    def cost_basis
      return nil if unknown_origin

      (qty * cost_per_unit).round(2)
    end

    def proceeds
      (qty * proceeds_per_unit - fee_allocated).round(2)
    end

    def gain
      return nil if cost_basis.nil?

      (proceeds - cost_basis).round(2)
    end

    def holding_days
      return nil if acquired_on.nil?

      (sold_on - acquired_on).to_i
    end
  end

  attr_reader :account_ids, :as_of

  def initialize(account_ids:, as_of: Date.current)
    @account_ids = Array(account_ids).map(&:to_s).uniq.freeze
    @as_of = as_of.to_date
  end

  def lots
    process
    @lots
  end

  def realisations
    process
    @realisations
  end

  # Total shares sold that had no matching purchase lot in this scope.
  def unmatched_sales_qty
    process
    @unmatched_sales_qty
  end

  def lots_for(security)
    lots.select { |lot| lot.security == security }
  end

  private
    def process
      return if defined?(@processed)

      @processed = true
      @lots = []
      @realisations = []
      @unmatched_sales_qty = BigDecimal("0")

      trades_by_security.each do |security, trades|
        process_security(security, trades)
      end
    end

    def process_security(security, trades)
      splits = Security::Split.where(security_id: security.id, ex_date: ..as_of).order(:ex_date).to_a
      split_index = 0
      open_lots = []

      trades.each do |trade|
        while split_index < splits.size && splits[split_index].ex_date <= trade.entry.date
          apply_split!(open_lots, splits[split_index])
          split_index += 1
        end

        # A movement between the caller's own accounts is not a purchase or a
        # sale. There is no net position change in a single scope.
        next if trade.internal_movement?

        if trade.buy?
          open_lots << build_lot(trade)
        elsif trade.sell?
          sell!(open_lots, trade)
        end
      end

      @lots.concat(open_lots)
    end

    def apply_split!(open_lots, split)
      open_lots.map! do |lot|
        scaled_qty = Security::Split.scale(lot.qty, split.ratio)
        scaled_cost = (lot.cost_per_unit.to_d * split.ratio.denominator / split.ratio.numerator).round(10)
        Lot.new(
          security: lot.security,
          acquired_on: lot.acquired_on,
          qty: scaled_qty,
          cost_per_unit: scaled_cost,
          currency: lot.currency
        )
      end
    end

    def build_lot(trade)
      qty = trade.qty.to_d
      total_cost = qty * trade.price.to_d + trade.fee.to_d
      Lot.new(
        security: trade.security,
        acquired_on: trade.entry.date,
        qty: qty,
        cost_per_unit: (total_cost / qty).round(10),
        currency: trade.currency
      )
    end

    def sell!(open_lots, trade)
      remaining = trade.qty.to_d.abs
      sold_on = trade.entry.date
      price = trade.price.to_d
      fee = trade.fee.to_d
      sold_qty = remaining
      fee_per_share = sold_qty.positive? ? fee / sold_qty : BigDecimal("0")

      while remaining.positive? && open_lots.any?
        lot = open_lots.first
        consumed = [ lot.qty, remaining ].min
        fee_allocated = (fee_per_share * consumed).round(10)

        @realisations << Realisation.new(
          security: trade.security,
          acquired_on: lot.acquired_on,
          sold_on: sold_on,
          qty: consumed,
          cost_per_unit: lot.cost_per_unit,
          proceeds_per_unit: price,
          fee_allocated: fee_allocated,
          currency: lot.currency,
          unknown_origin: false
        )

        remaining -= consumed
        if consumed == lot.qty
          open_lots.shift
        else
          open_lots[0] = Lot.new(
            security: lot.security,
            acquired_on: lot.acquired_on,
            qty: lot.qty - consumed,
            cost_per_unit: lot.cost_per_unit,
            currency: lot.currency
          )
        end
      end

      return unless remaining.positive?

      # Sold more than this scope can show a purchase for. The tax position is
      # unknown for that slice, and inventing a cost basis would hide it.
      @unmatched_sales_qty += remaining
      @realisations << Realisation.new(
        security: trade.security,
        acquired_on: nil,
        sold_on: sold_on,
        qty: remaining,
        cost_per_unit: nil,
        proceeds_per_unit: price,
        fee_allocated: (fee_per_share * remaining).round(10),
        currency: trade.currency,
        unknown_origin: true
      )
    end

    def trades_by_security
      scoped = Trade
        .joins(:entry)
        .where(entries: { account_id: account_ids, excluded: false })
        .where(entries: { date: ..as_of })
        .order("entries.date ASC, entries.created_at ASC, trades.id ASC")
        .includes(:security, :entry)

      scoped.group_by(&:security)
    end
end
