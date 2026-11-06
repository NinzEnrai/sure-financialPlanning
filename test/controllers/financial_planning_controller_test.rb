require "test_helper"
require "tempfile"

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

  test "renders the planning page header without missing translations" do
    get financial_planning_url

    assert_response :success
    assert_select "h1", text: I18n.t("financial_planning.show.title")
    assert_no_match(/translation missing/, response.body)
  end

  test "updates the retirement age" do
    patch setting_financial_planning_path, params: {
      planning_setting: { retirement_age: 65 }
    }

    assert_redirected_to financial_planning_path
    assert_equal 65, @family.reload.planning_setting.retirement_age
  end

  test "saves a person's declared tax inputs" do
    patch tax_profile_financial_planning_path(user_id: users(:family_admin).id), params: {
      tax_profile: { regime: "new", deductions_80c: 150_000, deductions_80d: 25_000 }
    }

    assert_redirected_to financial_planning_path
    profile = @family.reload.tax_profiles.find_by(user: users(:family_admin))
    assert_equal "new", profile.regime
    assert_in_delta 175_000, profile.total_declared_deductions, 0.01
  end

  test "clears a person's tax regime when the blank option is submitted" do
    @family.tax_profiles.create!(user: users(:family_admin), regime: "new")

    patch tax_profile_financial_planning_path(user_id: users(:family_admin).id), params: {
      tax_profile: { regime: "" }
    }

    assert_redirected_to financial_planning_path
    assert_nil @family.reload.tax_profiles.find_by(user: users(:family_admin)).regime
  end

  test "rejects tax inputs for somebody outside the family" do
    outsider = families(:empty).users.create!(
      email: "outsider-#{SecureRandom.hex(3)}@example.com",
      password: "password123",
      first_name: "Outsider",
      family: families(:empty)
    )

    patch tax_profile_financial_planning_path(user_id: outsider.id), params: {
      tax_profile: { regime: "new" }
    }

    assert_redirected_to financial_planning_path
    assert_nil @family.reload.tax_profiles.find_by(user: outsider)
    assert_predicate flash[:alert], :present?
  end

  test "renders the estate and nominations card" do
    get financial_planning_url

    assert_response :success
    assert_select "[data-testid='estate']"
    assert_select "select[name='estate_item[kind]']"
    assert_no_match(/translation missing/, response.body)
  end

  test "renders the planning pages for a household with no data" do
    family = families(:empty)
    user = family.users.create!(
      email: "empty-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      first_name: "Empty"
    )
    user.update!(preferences: (user.preferences || {}).merge("preview_features_enabled" => true))
    sign_in user

    get financial_planning_url
    assert_response :success

    get review_financial_planning_url
    assert_response :success
  end

  test "renders the fee audit card" do
    get financial_planning_url

    assert_response :success
    assert_select "[data-testid='fee-audit']"
  end

  test "renders the tax profile card for an admin" do
    get financial_planning_url

    assert_response :success
    assert_select "[data-testid='tax-profile']"
    assert_select "select[name='tax_profile[regime]']"
  end

  test "the page has no nested forms" do
    # A button_to inside a form_with nests a <form> in a <form>; browsers ignore
    # the inner tag, so the button submits the outer form. Render a household
    # member so every edit form is on the page, then prove the markup is valid.
    @family.household_members.create!(name: "Nested form guard", relationship: "self")

    get financial_planning_url

    assert_response :success
    assert_equal 0, nested_form_count(response.body)
  end

  test "renders the retirement stress test card" do
    get financial_planning_url

    assert_response :success
    assert_select "[data-testid='retirement-stress']"
    assert_select "[data-testid='retirement-stress'] h2", text: I18n.t("financial_planning.retirement_stress.title")
    assert_select "input[name='planning_setting[retirement_age]']"
  end

  test "updates the risk profile" do
    patch setting_financial_planning_path, params: {
      planning_setting: { risk_profile: "aggressive" }
    }

    assert_redirected_to financial_planning_path
    assert_equal "aggressive", @family.reload.planning_setting.risk_profile
  end

  test "renders the risk profile control" do
    get financial_planning_url

    assert_response :success
    assert_select "select[name='planning_setting[risk_profile]']"
  end

  test "renders the year in review" do
    get review_financial_planning_url

    assert_response :success
    assert_select "h1", text: I18n.t("financial_planning.review.title")
    assert_match I18n.t("financial_planning.review.numbers_title"), response.body
    assert_no_match(/translation missing/, response.body)
  end

  test "marks the annual review as done today" do
    patch mark_reviewed_financial_planning_path

    assert_redirected_to review_financial_planning_path
    assert_equal Date.current, @family.reload.planning_setting.last_reviewed_on
  end

  test "renders the household card and the add form" do
    get financial_planning_url

    assert_response :success
    assert_select "[data-testid='household']"
    assert_match I18n.t("financial_planning.household.title"), response.body
    assert_select "input[name='household_member[name]']"
    assert_match household_members(:self_member).name, response.body
  end

  test "renders the budget split form with the family's targets" do
    get financial_planning_url

    assert_response :success
    assert_select "input[name='planning_setting[needs_target_pct]']"
    assert_select "input[name='planning_setting[savings_target_pct]']"
  end

  test "imports an uploaded Console tradebook" do
    csv = "symbol,isin,trade_date,trade_type,quantity,price,trade_id\nAAPL,,#{(Date.current - 5.days).iso8601},buy,2,215,TR-1\n"
    file = upload(csv)

    assert_difference -> { accounts(:investment).entries.count }, 1 do
      post import_tradebook_financial_planning_path, params: { account_id: accounts(:investment).id, tradebook: file }
    end

    assert_redirected_to financial_planning_path
    assert_match(/Imported 1/, flash[:notice])
  end

  test "treats a non-file tradebook param as a missing upload" do
    assert_no_difference -> { Entry.count } do
      post import_tradebook_financial_planning_path, params: {
        account_id: accounts(:investment).id, tradebook: "not a file"
      }
    end

    assert_redirected_to financial_planning_path
    assert_predicate flash[:alert], :present?
  end

  test "cannot import into another member's unshared account" do
    unshared = @family.accounts.create!(
      name: "Jakob's brokerage", balance: 0, currency: "USD",
      accountable: Investment.new, owner: users(:family_member)
    )
    csv = "symbol,isin,trade_date,trade_type,quantity,price,trade_id\nAAPL,,#{(Date.current - 5.days).iso8601},buy,2,215,TR-PRIV\n"
    file = upload(csv)

    assert_no_difference -> { unshared.entries.count } do
      post import_tradebook_financial_planning_path, params: { account_id: unshared.id, tradebook: file }
    end

    assert_redirected_to financial_planning_path
    assert_predicate flash[:alert], :present?
  end

  test "refuses a tradebook import without a file" do
    assert_no_difference -> { Entry.count } do
      post import_tradebook_financial_planning_path, params: { account_id: accounts(:investment).id }
    end

    assert_redirected_to financial_planning_path
    assert_predicate flash[:alert], :present?
  end

  test "renders the tradebook import form" do
    get financial_planning_url

    assert_response :success
    assert_select "input[name='tradebook']"
    assert_select "select[name='account_id']"
  end

  test "renders the tax harvesting card" do
    get financial_planning_url

    assert_response :success
    assert_select "[data-testid='tax-harvesting']"
    assert_select "[data-testid='tax-harvesting'] h2", text: I18n.t("financial_planning.tax_harvesting.title")
  end

  test "renders the capital gains estimate card" do
    get financial_planning_url

    assert_response :success
    assert_select "[data-testid='capital-gains-estimate']"
    assert_select "[data-testid='capital-gains-estimate'] h2", text: I18n.t("financial_planning.capital_gains_estimate.title")
  end

  test "renders the realised gains card" do
    get financial_planning_url

    assert_response :success
    assert_select "[data-testid='realised-gains']"
    assert_select "[data-testid='realised-gains'] h2", text: I18n.t("financial_planning.realised_gains.title")
  end

  test "renders the coaching card" do
    get financial_planning_url

    assert_response :success
    assert_select "[data-testid='coaching']"
    assert_select "[data-testid='coaching'] h2", text: I18n.t("financial_planning.coaching.title")
  end

  test "renders the cash-flow forecast card" do
    get financial_planning_url

    assert_response :success
    assert_select "[data-testid='cash-flow-forecast']"
    assert_select "[data-testid='cash-flow-forecast'] h2", text: I18n.t("financial_planning.cash_flow_forecast.title")
  end

  test "renders the allocation and concentration card" do
    get financial_planning_url

    assert_response :success
    assert_select "[data-testid='allocation']"
    assert_select "[data-testid='allocation'] h2", text: I18n.t("financial_planning.allocation.title")
  end

  test "renders the protection card and the add form" do
    get financial_planning_url

    assert_response :success
    assert_select "[data-testid='protection']"
    assert_match I18n.t("financial_planning.protection.title"), response.body
    assert_select "input[name='insurance_policy[provider]']"
  end

  test "renders the emergency fund card" do
    get financial_planning_url

    assert_response :success
    assert_select "[data-testid='emergency-fund']"
    assert_match I18n.t("financial_planning.emergency_fund.title"), response.body
  end

  test "renders the emergency fund placeholder without spending history" do
    Entry.where(account: @family.accounts).destroy_all

    get financial_planning_url

    assert_response :success
    assert_match I18n.t("financial_planning.emergency_fund.unavailable"), response.body
  end

  test "renders the debt summary card" do
    get financial_planning_url

    assert_response :success
    assert_select "[data-testid='debt-summary']"
    assert_match I18n.t("financial_planning.debt_summary.title"), response.body
  end

  test "renders the debt placeholder when no liabilities are visible" do
    @family.accounts.liabilities.update_all(status: "disabled")

    get financial_planning_url

    assert_response :success
    assert_match I18n.t("financial_planning.debt_summary.none"), response.body
  end

  test "updates the budget split" do
    patch setting_financial_planning_path, params: {
      planning_setting: { needs_target_pct: 60, wants_target_pct: 20, savings_target_pct: 20 }
    }

    assert_redirected_to financial_planning_path
    setting = @family.reload.planning_setting
    assert_equal 60, setting.needs_target_pct
    assert_equal 20, setting.savings_target_pct
  end

  test "rejects a split that does not add up to one hundred" do
    patch setting_financial_planning_path, params: {
      planning_setting: { needs_target_pct: 60, wants_target_pct: 20, savings_target_pct: 10 }
    }

    assert_redirected_to financial_planning_path
    assert_predicate flash[:alert], :present?
  end

  test "updates the emergency target months" do
    patch setting_financial_planning_path, params: {
      planning_setting: { emergency_target_months: 9 }
    }

    assert_redirected_to financial_planning_path
    assert_equal 9, @family.reload.planning_setting.emergency_target_months
  end

  test "renders the emergency target control" do
    get financial_planning_url

    assert_response :success
    assert_select "select[name='planning_setting[emergency_target_months]']"
  end

  test "renders the portfolio return card" do
    get financial_planning_url

    assert_response :success
    assert_select "[data-testid='portfolio-return']"
    assert_match I18n.t("financial_planning.portfolio_return.title"), response.body
  end

  test "renders the goal funding card" do
    get financial_planning_url

    assert_response :success
    assert_select "[data-testid='goal-funding']"
    assert_match I18n.t("financial_planning.goal_funding.title"), response.body
  end

  test "renders the data confidence card" do
    get financial_planning_url

    assert_response :success
    assert_select "[data-testid='data-confidence']"
    assert_match I18n.t("financial_planning.data_confidence.title"), response.body
  end

  test "renders the tax readiness card" do
    get financial_planning_url

    assert_response :success
    assert_select "[data-testid='tax-readiness']"
    assert_match I18n.t("financial_planning.tax_readiness.title"), response.body
  end

  test "renders the financial health scorecard" do
    get financial_planning_url

    assert_response :success
    assert_select "[data-testid='health-scorecard']"
    assert_match I18n.t("financial_planning.health_scorecard.title"), response.body
    assert_select "[data-testid='health-scorecard'] [data-check='protection']"
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

  test "switching FIRE variant carries that variant's withdrawal rate" do
    setting = planning_settings(:active_family)

    patch setting_financial_planning_path, params: {
      planning_setting: { fire_variant: "fat" }
    }

    assert_redirected_to financial_planning_path
    setting.reload
    assert_equal "fat", setting.fire_variant
    # A lower rate is the whole point of Fat FIRE; leaving the number at the 4%
    # rule would move the label and nothing else.
    assert_equal PlanningSetting::FIRE_VARIANTS.fetch("fat")[:withdrawal_rate_pct],
      setting.fire_withdrawal_rate_pct.to_f
  end

  test "re-saving the same variant keeps a hand-tuned rate" do
      setting = planning_settings(:active_family)
      setting.update!(fire_variant: "standard", fire_withdrawal_rate_pct: 3.7)

      patch setting_financial_planning_path, params: {
        planning_setting: { fire_variant: "standard", fire_withdrawal_rate_pct: 3.7 }
      }

      assert_equal 3.7, setting.reload.fire_withdrawal_rate_pct.to_f
    end

  test "coast fire requires a target age" do
      setting = planning_settings(:active_family)
      setting.update!(fire_variant: "standard", fire_target_year: nil)

      patch setting_financial_planning_path, params: { planning_setting: { fire_variant: "coast" } }

      assert_redirected_to financial_planning_path
      assert_equal "standard", setting.reload.fire_variant, "an invalid variant must not be persisted"
    end

  test "coast fire saves with a target age" do
      setting = planning_settings(:active_family)

      patch setting_financial_planning_path, params: {
        planning_setting: { fire_variant: "coast", fire_target_year: Date.current.year + 5 }
      }

      assert_redirected_to financial_planning_path
      setting.reload
      assert_equal "coast", setting.fire_variant
      assert_equal Date.current.year + 5, setting.fire_target_year
    end

  test "switching away from coast keeps the target age" do
      setting = planning_settings(:active_family)
      setting.update!(fire_variant: "coast", fire_target_year: Date.current.year + 5)

      patch setting_financial_planning_path, params: { planning_setting: { fire_variant: "standard" } }

      setting.reload
      assert_equal "standard", setting.fire_variant
      # Kept rather than wiped: switching back to Coast is normal, and the age is
      # valid for the other variants, so there is nothing to gain by destroying it.
      assert_equal Date.current.year + 5, setting.fire_target_year
    end

  test "reports validation errors instead of persisting bad rates" do
      setting = planning_settings(:active_family)

      patch setting_financial_planning_path, params: {
        planning_setting: { fire_withdrawal_rate_pct: 0 }
      }

      assert_redirected_to financial_planning_path
      assert_equal 4.0, setting.reload.fire_withdrawal_rate_pct.to_f
    end

  private
    def nested_form_count(html)
      depth = 0
      nested = 0

      html.scan(/<\/?form\b[^>]*>/) do |tag|
        if tag.start_with?("</")
          depth -= 1 if depth.positive?
        else
          nested += 1 if depth.positive?
          depth += 1
        end
      end

      nested
    end

    def upload(csv)
      file = Tempfile.new([ "tradebook", ".csv" ])
      file.write(csv)
      file.rewind
      Rack::Test::UploadedFile.new(file.path, "text/csv")
    end
end
