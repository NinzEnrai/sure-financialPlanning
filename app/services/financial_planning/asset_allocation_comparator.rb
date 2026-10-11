# frozen_string_literal: true

module FinancialPlanning
  # Compares the family's PlanningSetting#target_allocation (e.g. {equity: 60, debt: 25,
  # gold: 10, cash: 5}) against actual current holdings across ALL accounts -- manual
  # accounts and Kite-synced ones alike, since both ultimately land in the same
  # Account/Holding tables by Phase 2.
  #
  # ASSUMPTION TO VERIFY: assumes each `Security` (and non-investment account, e.g. a savings
  # account standing in for "cash") can be mapped to one of the target_allocation buckets.
  # The simplest robust approach is an explicit `asset_class` enum column on Security
  # (equity/debt/gold/cash/other) rather than inferring it from exchange/ticker -- add that
  # alongside the Phase 1 migration if it doesn't already exist, and backfill it (gold ETFs,
  # debt mutual funds, and equity mutual funds all trade through the same "MF" exchange_segment
  # so exchange_segment alone can't disambiguate them).
  class AssetAllocationComparator
    Row = Struct.new(:asset_class, :target_pct, :actual_pct, :actual_amount, :delta_pct, keyword_init: true)

    def initialize(family)
      @family = family
      @settings = family.planning_setting
    end

    def compare
      target = settings&.target_allocation || {}
      actual_amounts = actual_amounts_by_class
      total = actual_amounts.values.sum

      classes = (target.keys.map(&:to_s) + actual_amounts.keys.map(&:to_s)).uniq

      classes.map do |asset_class|
        target_pct = target[asset_class].to_f
        amount = actual_amounts[asset_class] || 0
        actual_pct = total.positive? ? (amount / total * 100).round(1) : 0.0

        Row.new(
          asset_class: asset_class,
          target_pct: target_pct,
          actual_pct: actual_pct,
          actual_amount: amount.round(2),
          delta_pct: (actual_pct - target_pct).round(1)
        )
      end
    end

    private

    attr_reader :family, :settings

    def actual_amounts_by_class
      investment_amounts = family.accounts.where(accountable_type: "Investment")
                                  .joins(holdings: :security)
                                  .where(holdings: { date: Holding.maximum(:date) }) # latest snapshot per holding; adjust if your Holding model already exposes a `current` scope
                                  .group("securities.asset_class")
                                  .sum("holdings.amount")
                                  .transform_keys { |k| k || "other" }

      cash_amount = family.accounts.where(accountable_type: "Depository").sum(:balance)
      investment_amounts.merge("cash" => investment_amounts["cash"].to_f + cash_amount.to_f)
    end
  end
end
