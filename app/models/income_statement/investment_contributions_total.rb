# Cash moved out of the family's accounts into investments (SIPs, transfers into
# brokerage/crypto accounts, round-ups) for a period.
#
# Sure records these as `investment_contribution` transfers, and
# IncomeStatement::Totals classifies them as expenses, so the amounts are
# already inside `expense_money`. This query pulls that same money back out as
# its own bucket: contributions buy an asset rather than being consumed, and net
# worth already holds that asset, so counting them purely as spending
# understates what was actually kept.
#
# Scoping fragments are shared with the other IncomeStatement queries, so a
# contribution can only be counted here if it also counted in the expense total
# it is subtracted from. Nothing here changes how the statement classifies
# anything -- budgeting, reports and net worth still see contributions as
# expenses, which is deliberate and not a bug.
class IncomeStatement::InvestmentContributionsTotal
  include IncomeStatement::ScopedTransactionsQuery

  def initialize(family, transactions_scope:, date_range:, included_account_ids: nil)
    @family = family
    @transactions_scope = transactions_scope
    @date_range = date_range
    @included_account_ids = included_account_ids

    validate_date_range!
  end

  def call
    # No finance accounts means no transactions to report
    return 0.to_d if @included_account_ids&.empty?

    ActiveRecord::Base.connection.select_value(query_sql).to_d
  end

  private
    def query_sql
      ActiveRecord::Base.sanitize_sql_array([ query_sql_body, sql_params ])
    end

    # Mirrors IncomeStatement::Totals' transactions subquery, but keeps only the
    # contribution rows and sums them straight across categories instead of
    # grouping by one. The kind is matched literally, so the BUDGET_EXCLUDED_KINDS
    # filter the other queries carry is redundant here -- `investment_contribution`
    # is not one of those kinds. `converted_amount_sql` already flips outflows
    # positive, so contributions add up rather than cancelling out.
    def query_sql_body
      <<~SQL
        SELECT COALESCE(SUM(#{converted_amount_sql("at")}), 0) as total
        FROM (#{@transactions_scope.to_sql}) at
        #{entries_join_sql("at")}
        #{accounts_join_sql}
        #{exchange_rates_join_sql}
        WHERE at.kind = 'investment_contribution'
          #{investment_activity_label_sql("at")}
          AND ae.excluded = false
          AND a.family_id = :family_id
          AND a.status IN ('draft', 'active')
          AND a.exclude_from_reports = false
          #{exclude_tax_advantaged_sql}
          #{include_finance_accounts_sql}
      SQL
    end

    def sql_params
      params = base_sql_params(start_date: @date_range.begin, end_date: @date_range.end)
      params[:included_account_ids] = @included_account_ids if @included_account_ids
      params
    end
end
