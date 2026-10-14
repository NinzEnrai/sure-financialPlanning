# Groups a period's spending into Needs / Wants / Savings for the 50/30/20
# analyzer, and scores each bucket against its target share of net income.
#
# Needs and wants are ceilings and savings is a floor, so `on_track?` compares
# each bucket in the direction that actually matters to the household rather
# than treating "under 50% of needs" and "under 20% of savings" as equivalent
# successes.
#
# Category assignment comes from PlanningSetting#bucket_for, which prefers a
# family's explicit override and otherwise falls back to the built-in mapping.
class FinancialPlanning::BudgetAnalyzer
  Bucket = Data.define(:key, :amount, :income, :currency, :target_share_pct) do
    # Share of net income this bucket consumed. Nil without income -- a rate
    # against nothing is not 0%, it's unanswerable.
    def share_pct
      return nil unless income.positive?

      ((amount / income) * 100).round(1)
    end

    # Share of income the guideline allows this bucket.
    def target_amount
      ((income * target_share_pct) / 100).round(2)
    end

    # Savings has to be *at least* its share; the other two have to stay
    # *under* theirs. `on_track?` is what the view renders its tone from.
    def on_track?
      return false if share_pct.nil?

      key == "savings" ? share_pct >= target_share_pct : share_pct <= target_share_pct
    end

    # Money to bring this bucket back inside its target, signed by how far off
    # it is. Nil when the bucket is already on the right side.
    def gap_money
      return nil if share_pct.nil?

      gap = (share_pct - target_share_pct) / 100 * income
      return nil if gap.zero?

      key == "savings" ? -gap : gap
    end

    def amount_money
      Money.new(amount, currency)
    end

    def target_amount_money
      Money.new(target_amount, currency)
    end
  end

  attr_reader :family, :period

  def initialize(family, period:, user: nil)
    @family = family
    @period = period
    @user = user || Current.user
  end

  def buckets
    @buckets ||= PlanningSetting::BUCKETS.map do |key|
      Bucket.new(
        key: key,
        amount: bucket_amounts.fetch(key, 0),
        income: income,
        currency: currency,
        target_share_pct: PlanningSetting::TARGET_SHARE_PCT.fetch(key)
      )
    end
  end

  def income
    @income ||= income_statement.totals_for(period).income_money.amount
  end

  def income_money
    Money.new(income, currency)
  end

  # Spending categories with no bucket assigned -- they are excluded from all
  # three totals rather than silently folded into one, and the view says so.
  def unassigned_categories
    @unassigned_categories ||= spend_by_category.reject { |entry| entry[:bucket] }
  end

  def categories_for(bucket_key)
    spend_by_category.select { |entry| entry[:bucket] == bucket_key }
  end

  def assigned_categories
    spend_by_category.reject { |entry| entry[:bucket].nil? }
  end

  # Every category the family owns, for the bucket picker -- not just the ones
  # that spent this period. Assigning a bucket before the first purchase is the
  # point of the picker; waiting for a transaction to categorise would mean the
  # default silently decided the first one.
  #
  # Spending categories lead, largest first, because they are the ones currently
  # moving the split. The rest follow alphabetically so they stay findable
  # without being buried under whatever happened to spend this month.
  #
  # Subcategories are excluded because their parent row already carries their
  # spend, so the parent and the child would otherwise appear as two rows
  # competing to be assigned.
  def bucketed_categories
    @bucketed_categories ||= begin
      spent = spend_by_category.to_h { |entry| [ entry[:category].id, entry[:total].to_f ] }

      family.categories
        .reject(&:subcategory?)
        .sort_by { |category| [ spent.key?(category.id) ? 0 : 1, -(spent[category.id] || 0), category.name.to_s.downcase ] }
        .map do |category|
          {
            category: category,
            bucket: planning_setting.bucket_for(category, key: category.default_i18n_key),
            default_bucket: PlanningSetting::DEFAULT_BUCKETS[category.default_i18n_key],
            overridden: planning_setting.bucket_override?(category),
            total: spent[category.id] || 0
          }
        end
    end
  end

  # Every category that spent in the period, bucketed, largest first.
  def spend_by_category
    @spend_by_category ||= expense_category_totals.map do |ct|
      {
        category: ct.category,
        bucket: planning_setting.bucket_for(ct.category, key: ct.category.default_i18n_key),
        total: ct.total
      }
    end.sort_by { |entry| - entry[:total].to_f }
  end

  private
    attr_reader :user

    def currency
      family.currency
    end

    def income_statement
      @income_statement ||= family.income_statement(user: user)
    end

    def planning_setting
      @planning_setting ||= family.planning_setting || family.build_planning_setting
    end

    # Parent totals already include their subcategories, so subcategories are
    # dropped rather than summed -- otherwise every split category would be
    # counted twice and the buckets would overstate spending.
    #
    # The synthetic Uncategorized and Other Investments pseudo-categories are
    # kept: they are real money, and excluding them would let spending vanish
    # from the split without appearing anywhere else either.
    def expense_category_totals
      income_statement
        .expense_totals(period: period)
        .category_totals
        .reject { |ct| ct.category.subcategory? }
        .select { |ct| ct.total.positive? }
    end

    def bucket_amounts
      @bucket_amounts ||= spend_by_category.each_with_object(Hash.new(0)) do |entry, acc|
        # Stays in BigDecimal -- the category totals are money, and summing them
        # as floats would drift on a large ledger.
        acc[entry[:bucket]] += entry[:total]
      end
    end
end
