# frozen_string_literal: true

module FinancialPlanning
  # Computes monthly savings rate = (income - expenses) / income * 100, and rolling averages
  # over 3/6/12-month windows, from the family's existing transaction ledger.
  #
  # ASSUMPTION TO VERIFY: assumes transactions/entries are categorized such that you can
  # distinguish income vs expense (likely a `classification` enum on Category, or a sign
  # convention on amount, per Sure's budgeting feature which already must do this same
  # income-vs-expense split -- reuse that exact query/scope if one already exists rather
  # than duplicating it here).
  class SavingsRateCalculator
    def initialize(family)
      @family = family
    end

    # Returns [{ month: Date (1st of month), income:, expenses:, savings:, savings_rate_pct: }, ...]
    # oldest -> newest, for the given number of trailing months.
    def monthly_series(months: 12)
      range_start = months.months.ago.beginning_of_month.to_date

      income_by_month = monthly_totals(classification: "income", since: range_start)
      expense_by_month = monthly_totals(classification: "expense", since: range_start)

      (0...months).map do |i|
        month = (months - 1 - i).months.ago.beginning_of_month.to_date
        income = income_by_month[month] || 0
        expenses = expense_by_month[month] || 0
        savings = income - expenses

        {
          month: month,
          income: income,
          expenses: expenses,
          savings: savings,
          savings_rate_pct: income.positive? ? (savings / income * 100).round(1) : nil
        }
      end
    end

    # Rolling average savings rate over the trailing N months (weighted by total income,
    # not a simple average of monthly percentages -- avoids distortion from low-income months).
    def rolling_rate(months:)
      series = monthly_series(months: months)
      total_income = series.sum { |m| m[:income] }
      total_savings = series.sum { |m| m[:savings] }
      return nil if total_income.zero?

      (total_savings / total_income * 100).round(1)
    end

    def summary
      { three_month: rolling_rate(months: 3), six_month: rolling_rate(months: 6), twelve_month: rolling_rate(months: 12) }
    end

    private

    attr_reader :family

    def monthly_totals(classification:, since:)
      # CONFIRMED against your schema: `transactions.category_id` + a `category_classification`
      # concept exists (seen on `import_rows.category_classification` during CSV mapping), and
      # a separate `transfers` table links pairs of transactions for internal movements between
      # accounts -- those must be excluded here or a transfer would be double-counted as both an
      # "expense" leaving one account and "income" landing in another, inflating the savings rate.
      transferred_transaction_ids = Transfer.pluck(:inflow_transaction_id, :outflow_transaction_id).flatten

      family.entries
            .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id AND entries.entryable_type = 'Transaction'")
            .joins("INNER JOIN categories ON categories.id = transactions.category_id")
            .where(categories: { classification: classification })
            .where.not(entries: { entryable_id: transferred_transaction_ids })
            .where("entries.date >= ?", since)
            .group("date_trunc('month', entries.date)")
            .sum(:amount)
            .transform_keys { |k| k.to_date.beginning_of_month }
    end
  end
end
