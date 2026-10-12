require "test_helper"

class FinancialPlanning::BudgetAnalyzerTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @period = Period.current_month_for(@family)
    @setting = planning_settings(:active_family)

    Entry.where(account: @family.accounts).destroy_all

    # Built with the default translated names so Category#default_i18n_key
    # resolves and the default bucket mapping is actually exercised.
    @groceries = default_category("groceries")
    @entertainment = default_category("entertainment")
    @savings = default_category("savings_and_investments")
  end

  test "groups spending into needs, wants and savings" do
    spend 1000, on: @groceries
    spend 400, on: @entertainment
    spend 300, on: @savings

    buckets = analyzer.buckets.index_by(&:key)

    assert_equal 1000, buckets["needs"].amount
    assert_equal 400, buckets["wants"].amount
    assert_equal 300, buckets["savings"].amount
  end

  test "bucket share is measured against net income" do
    create_transaction(amount: -2000, date: Date.current)
    spend 1000, on: @groceries

    assert_equal 50.0, analyzer.buckets.find { |b| b.key == "needs" }.share_pct
  end

  test "needs and wants are judged as ceilings, savings as a floor" do
    create_transaction(amount: -1000, date: Date.current)
    spend 600, on: @groceries # 60% of income, target 50%
    spend 300, on: @savings  # 30% of income, target 20%

    buckets = analyzer.buckets.index_by(&:key)

    assert_not buckets["needs"].on_track?, "60% of income exceeds the 50% needs ceiling"
    assert buckets["savings"].on_track?, "30% of income clears the 20% savings floor"
  end

  test "built-in categories pick up their default bucket" do
    spend 1000, on: @groceries  # needs
    spend 400, on: @entertainment # wants
    spend 300, on: @savings # savings

    buckets = analyzer.buckets.index_by(&:key)

    assert_equal 1000, buckets["needs"].amount
    assert_equal 400, buckets["wants"].amount
    assert_equal 300, buckets["savings"].amount
    assert_empty analyzer.unassigned_categories
  end

  test "a family override reassigns a built-in category" do
    spend 1000, on: @groceries
    create_transaction(amount: -2000, date: Date.current)

    @setting.update!(category_buckets: { @groceries.id.to_s => "wants" })

    buckets = analyzer.buckets.index_by(&:key)

    assert_equal 0, buckets["needs"].amount
    assert_equal 1000, buckets["wants"].amount
  end

  test "a custom category with no override is unassigned, not silently bucketed" do
    category = @family.categories.create!(name: "Hobby", color: "#4da568", lucide_icon: "drama")
    spend 500, on: category

    assert_equal [ category ], analyzer.unassigned_categories.map { |e| e[:category] }
    assert_equal 500, analyzer.unassigned_categories.sum { |e| e[:total].to_f }
    assert_equal 0, analyzer.buckets.sum(&:amount)
  end

  test "uncategorized spending lands in needs rather than vanishing" do
    create_transaction(amount: 2000, date: Date.current) # no category

    buckets = analyzer.buckets.index_by(&:key)

    assert_equal 2000, buckets["needs"].amount,
                 "uncategorized money must appear somewhere, not disappear from the split"
    assert_empty analyzer.unassigned_categories
  end

  test "subcategories roll into the parent without double counting" do
    child = @family.categories.create!(
      name: "Bulk store", color: "#4da568", lucide_icon: "shopping-bag", parent: @groceries
    )

    spend 700, on: child
    create_transaction(amount: -2000, date: Date.current)

    # Only the child transacted, but its parent's total must carry it.
    assert_equal 700, analyzer.buckets.find { |b| b.key == "needs" }.amount
  end

  test "categories_for returns only that bucket's categories" do
    spend 1000, on: @groceries
    spend 400, on: @entertainment

    assert_equal [ @groceries ], analyzer.categories_for("needs").map { |e| e[:category] }
  end

  test "income is reported separately from the buckets" do
    create_transaction(amount: -5000, date: Date.current)

    assert_equal 5000, analyzer.income
    assert_equal 5000, analyzer.income_money.amount.to_f
  end

  test "every bucket reports a share even when nothing was spent" do
    create_transaction(amount: -2000, date: Date.current)

    buckets = analyzer.buckets.index_by(&:key)

    assert_equal 0.0, buckets["needs"].share_pct
    assert buckets["needs"].on_track?
    assert_not buckets["savings"].on_track?, "no savings recorded is not on track for the 20% floor"
  end

  private
    def analyzer
      FinancialPlanning::BudgetAnalyzer.new(@family, period: @period, user: @user)
    end

    def default_category(key)
      @family.categories.create!(
        name: I18n.t("models.category.defaults.#{key}"),
        color: "#4da568",
        lucide_icon: "shapes"
      )
    end

    def spend(amount, on:)
      create_transaction(amount: amount, date: Date.current, category: on)
    end
end