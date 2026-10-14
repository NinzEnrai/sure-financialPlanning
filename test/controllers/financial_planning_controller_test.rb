require "test_helper"

class FinancialPlanningControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => true))
    sign_in @user
    @family = families(:dylan_family)
    ensure_tailwind_build
  end

  test "redirects users without preview access" do
    @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => false))

    get financial_planning_url

    assert_redirected_to root_path
    assert_match(/preview/i, flash[:alert])
  end

  test "shows the planning page for a signed-in user" do
    planning_settings(:active_family)

    get financial_planning_url

    assert_response :success
  end

  test "does not require a persisted planning setting to render" do
    @family.planning_setting.destroy!

    get financial_planning_url

    assert_response :success
  end

  test "projection returns one balance per year in the family currency" do
    get projection_financial_planning_url

    assert_response :success

    payload = response.parsed_body
    assert_equal 11, payload["balances"].size
    assert_equal @family.currency, payload["currency"]
    assert_equal Date.current.year, payload["years"].first
  end

  test "projection accepts a monthly contribution override" do
    # The compound calculator's whole reason to exist. Without an override the
    # contribution arrives as a decimal column and the response formats it as
    # "F"; an override that parses to a Float instead raises mid-render, which
    # broke the slider while the page itself still loaded clean.
    get projection_financial_planning_url, params: { monthly_contribution: 50000 }

    assert_response :success

    payload = response.parsed_body
    assert_equal 50000, payload["monthly_contribution"].to_d
    assert_equal 11, payload["balance_labels"].size
    assert payload["final_balance_label"].present?
  end

test "projection applies a growth rate override as a percentage" do
    get projection_financial_planning_url, params: { growth_rate_pct: 12 }

    assert_response :success
    # Serialized as a string: BigDecimal rides through #render json as one.
    assert_equal 12.0, response.parsed_body["growth_rate_pct"].to_f
  end

test "projection ignores an unparseable or negative override" do
    saved = @family.planning_setting
    # The project's own default, which is the saved assumption. Not necessarily
    # positive -- a family running a deficit legitimately has a negative pace --
    # so the assertion is equality with the saved value, not a positive bound.
    saved_contribution = FinancialPlanning::WealthProjector.new(@family, user: @user).monthly_contribution

    get projection_financial_planning_url, params: { monthly_contribution: "not-a-number", growth_rate_pct: -5 }

    assert_response :success

    payload = response.parsed_body
    assert_equal saved.annual_growth_rate_pct.to_f.round(2), payload["growth_rate_pct"].to_f
    assert_equal saved_contribution.to_d, payload["monthly_contribution"].to_d
  end

test "a larger contribution projects a larger balance" do
    get projection_financial_planning_url, params: { monthly_contribution: 10_000 }
    low = response.parsed_body["final_balance"].to_d

    get projection_financial_planning_url, params: { monthly_contribution: 100_000 }
    high = response.parsed_body["final_balance"].to_d

    assert_operator high, :>, low
  end

test "renders both savings rate series for the chart" do
    get financial_planning_url

    assert_response :success
    assert_match "savings-rate-chart", response.body

    # Both series ship as pre-formatted server-side values, and a month with no
    # income must reach the chart as null rather than 0 so the line breaks
    # instead of drawing a false "saved nothing".
    payload = response.body[/data-savings-rate-chart-data-value="([^"]*)"/, 1]
    assert payload.present?, "expected the chart data attribute to be rendered"

    series = CGI.unescapeHTML(payload).then { |json| JSON.parse(json).fetch("series") }
    assert_equal 12, series.size
    assert_equal %w[date tooltip_date percent total_percent cash_label total_label].sort, series.first.keys.sort
    series.each do |row|
      assert_equal row["total_percent"].nil?, row["percent"].nil?,
        "a month with no income must be nil in both series, not one"

      # Numbers, not strings. A decimal column rides through #to_json as a
      # string, and d3.max over strings compares lexicographically -- "9" beats
      # "38" -- so the scale maths goes NaN and the whole plot silently vanishes
      # while the legend still draws. Nothing else fails, so this is the only
      # place the bug can be caught.
      [ "percent", "total_percent" ].each do |key|
        next if row[key].nil?

        assert_kind_of Numeric, row[key], "#{key} must serialize as a number"
      end
    end
  end

test "renders the bucket picker for every family category" do
    get financial_planning_url

    assert_response :success
    # The resolved URL, not the path helper -- the form action in the markup is
    # what a regression would actually break.
    assert_match bucket_financial_planning_path, response.body
    # The reset option is what removes an override; it has to be offered or a
    # customised category can never go back to Sure's built-in mapping.
    assert_match PlanningSetting::RESET_BUCKET, response.body

    @family.categories.reject(&:subcategory?).each do |category|
      # Escaped: a category named "Food & Drink" is markup-encoded in the page,
      # so the raw body never contains the literal ampersand.
      assert_includes response.body, ERB::Util.html_escape(category.name)
    end
  end

test "assigning a bucket overrides the built-in mapping" do
    category = categories(:one)
    setting = @family.planning_setting
    default_bucket = PlanningSetting::DEFAULT_BUCKETS[category.default_i18n_key]
    other_bucket = PlanningSetting::BUCKETS.find { |b| b != default_bucket }

    patch bucket_financial_planning_path, params: { category_id: category.id, bucket: other_bucket }

    assert_redirected_to financial_planning_path
    assert_equal other_bucket, setting.reload.bucket_for(category, key: category.default_i18n_key)
    assert setting.bucket_override?(category)
  end

test "resetting a bucket drops the override and restores the default" do
    category = categories(:one)
    setting = @family.planning_setting
    default_bucket = PlanningSetting::DEFAULT_BUCKETS[category.default_i18n_key]

    patch bucket_financial_planning_path, params: { category_id: category.id, bucket: "needs" }
    assert setting.reload.bucket_override?(category)

    patch bucket_financial_planning_path,
          params: { category_id: category.id, bucket: PlanningSetting::RESET_BUCKET }

    assert_redirected_to financial_planning_path
    setting.reload
    # The key is removed rather than stored as a sentinel, so the built-in
    # mapping applies again and stops being shadowed by a permanent override.
    refute setting.bucket_override?(category)
    refute setting.category_buckets.key?(category.id.to_s)
    assert_equal default_bucket, setting.bucket_for(category, key: category.default_i18n_key)
  end

test "resetting a category with no override is harmless" do
    category = categories(:one)
    setting = @family.planning_setting

    patch bucket_financial_planning_path,
          params: { category_id: category.id, bucket: PlanningSetting::RESET_BUCKET }

    assert_redirected_to financial_planning_path
    assert_empty setting.reload.category_buckets
  end

test "assigns a category bucket override to the family" do
    category = categories(:one)

    patch bucket_financial_planning_path, params: { category_id: category.id, bucket: "wants" }

    assert_redirected_to financial_planning_path
    assert_equal "wants", @family.reload.planning_setting.bucket_for(category)
  end

  test "refuses to bucket another family's category" do
    foreign = families(:empty).categories.create!(name: "Elsewhere", color: "#4da568", lucide_icon: "drama")

    patch bucket_financial_planning_path, params: { category_id: foreign.id, bucket: "wants" }

    assert_redirected_to financial_planning_path
    assert_nil @family.reload.planning_setting&.category_buckets&.key(foreign.id.to_s)
  end

  test "rejects an unknown bucket value" do
    category = categories(:one)

    patch bucket_financial_planning_path, params: { category_id: category.id, bucket: "nonsense" }

    assert_redirected_to financial_planning_path
    assert_nil @family.reload.planning_setting&.category_buckets&.key(category.id.to_s)
  end

  test "updates the fire and growth rates" do
    setting = planning_settings(:active_family)

    patch setting_financial_planning_path, params: {
      planning_setting: { fire_withdrawal_rate_pct: 3.5, annual_growth_rate_pct: 8.0 }
    }

    assert_redirected_to financial_planning_path
    assert_equal 3.5, setting.reload.fire_withdrawal_rate_pct.to_f
    assert_equal 8.0, setting.annual_growth_rate_pct.to_f
  end

  test "reports validation errors instead of persisting bad rates" do
    setting = planning_settings(:active_family)

    patch setting_financial_planning_path, params: {
      planning_setting: { fire_withdrawal_rate_pct: 0 }
    }

    assert_redirected_to financial_planning_path
    assert_equal 4.0, setting.reload.fire_withdrawal_rate_pct.to_f
  end
end