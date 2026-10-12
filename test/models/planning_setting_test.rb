require "test_helper"

class PlanningSettingTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @setting = planning_settings(:active_family)
  end

  test "fire target is annual expenses divided by the withdrawal rate" do
    assert_equal 2500000, @setting.fire_target_money(100000).amount.to_f
  end

  test "fire target does not accumulate float error" do
    @setting.update!(fire_withdrawal_rate_pct: 3.0)

    # Float arithmetic gives 399999.99999999994 here; the stored figure must be
    # exact to the cent.
    assert_equal 400000, @setting.fire_target_money(12000).amount.to_f
  end

  test "fire target respects a custom withdrawal rate" do
    target = planning_settings(:custom_rates).fire_target_money(100000)

    assert_in_delta 2857142.86, target.amount.to_f, 0.01
  end

  test "fire target is zero when there are no expenses" do
    assert_equal 0, @setting.fire_target_money(0).amount.to_f
  end

  test "fire multiple is the reciprocal of the withdrawal rate" do
    assert_equal 25, @setting.fire_multiple
    assert_equal 29, planning_settings(:custom_rates).fire_multiple
  end

  test "growth rate is a fraction" do
    assert_in_delta 0.07, @setting.growth_rate, 0.0001
    assert_in_delta 0.09, planning_settings(:custom_rates).growth_rate, 0.0001
  end

  test "every default bucket is a known bucket" do
    assert_empty PlanningSetting::DEFAULT_BUCKETS.values - PlanningSetting::BUCKETS
  end

  test "falls back to the default bucket for a built-in category" do
    category = default_category("groceries")

    assert_equal "needs", @setting.bucket_for(category, key: category.default_i18n_key)
    assert_equal "wants", @setting.bucket_for(category, key: "models.category.defaults.entertainment")
    assert_not @setting.bucket_override?(category)
  end

  test "every default bucket key is a key Category actually resolves" do
    # Guards the trap where DEFAULT_BUCKETS is written with short suffixes but
    # Category#default_i18n_key hands back full keys -- the mapping then silently
    # never matches and every category reads as unassigned.
    resolvable = Category::DEFAULT_CATEGORY_TRANSLATION_KEYS.map { |key| "models.category.defaults.#{key}" } +
                 [ Category::UNCATEGORIZED_NAME_KEY, Category::OTHER_INVESTMENTS_NAME_KEY ]

    assert_empty PlanningSetting::DEFAULT_BUCKETS.keys - resolvable
  end

  test "built-in categories resolve their full i18n key" do
    assert_equal "models.category.defaults.groceries", default_category("groceries").default_i18n_key
    assert_equal "models.category.defaults.savings_and_investments",
                 default_category("savings_and_investments").default_i18n_key
  end

  test "a family override beats the default mapping" do
    category = default_category("groceries")
    @setting.update!(category_buckets: { category.id.to_s => "wants" })

    assert_equal "wants", @setting.bucket_for(category, key: category.default_i18n_key)
    assert @setting.bucket_override?(category)
  end

  test "a custom category with no override has no bucket" do
    category = @family.categories.create!(name: "Hobby", color: "#4da568", lucide_icon: "drama")

    assert_nil @setting.bucket_for(category, key: category.default_i18n_key)
    assert_not @setting.bucket_override?(category)
  end

  test "rejects an unknown bucket value" do
    @setting.category_buckets = { categories(:one).id => "nonsense" }

    assert_not @setting.valid?
    assert_includes @setting.errors[:category_buckets].first, "needs"
  end

  test "rejects a bucket pointing at another family's category" do
    foreign = families(:empty).categories.create!(name: "Elsewhere", color: "#4da568", lucide_icon: "drama")
    @setting.category_buckets = { foreign.id.to_s => "needs" }

    assert_not @setting.valid?
    assert @setting.errors[:category_buckets].any?
  end

  test "rejects a malformed bucket key without hitting the database" do
    @setting.category_buckets = { "not-a-uuid" => "needs" }

    assert_not @setting.valid?
    assert_match(/category id/, @setting.errors[:category_buckets].first)
  end

  test "requires positive rates" do
    @setting.fire_withdrawal_rate_pct = 0
    @setting.annual_growth_rate_pct = -1

    assert_not @setting.valid?
  end

  test "family has at most one setting" do
    assert_raises ActiveRecord::RecordNotUnique do
      @family.create_planning_setting!
    end
  end

  private
    def default_category(key)
      @family.categories.create!(
        name: I18n.t("models.category.defaults.#{key}"),
        color: "#4da568",
        lucide_icon: "shapes"
      )
    end
end