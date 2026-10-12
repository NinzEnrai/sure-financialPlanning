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