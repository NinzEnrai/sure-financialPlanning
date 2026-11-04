require "test_helper"

class FinancialPlanning::EstateItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => true))
    sign_in @user
  end

  test "adds a checklist item to the family" do
    assert_difference -> { @family.estate_items.count }, 1 do
      post financial_planning_estate_items_path, params: {
        estate_item: { kind: "will", title: "Will at the family lawyer", status: "in_place", review_on: Date.current + 1.year }
      }
    end

    assert_redirected_to financial_planning_path
    assert_equal "Will at the family lawyer", @family.estate_items.last.title
  end

  test "marks an item in place" do
    item = @family.estate_items.create!(kind: "nomination", title: "Bank nomination", status: "pending")

    patch financial_planning_estate_item_path(item), params: { estate_item: { status: "in_place" } }

    assert_redirected_to financial_planning_path
    assert_equal "in_place", item.reload.status
  end

  test "removes a checklist item" do
    item = @family.estate_items.create!(kind: "document", title: "Old will", status: "not_applicable")

    assert_difference -> { EstateItem.count }, -1 do
      delete financial_planning_estate_item_path(item)
    end

    assert_redirected_to financial_planning_path
  end

  test "cannot touch another family's item" do
    other = families(:empty).estate_items.create!(kind: "will", title: "Other will", status: "pending")

    patch financial_planning_estate_item_path(other), params: { estate_item: { status: "in_place" } }

    assert_redirected_to financial_planning_path
    assert_equal "pending", other.reload.status
    assert_predicate flash[:alert], :present?
  end

  test "rejects an invalid item" do
    assert_no_difference -> { EstateItem.count } do
      post financial_planning_estate_items_path, params: {
        estate_item: { kind: "will", title: "" }
      }
    end

    assert_redirected_to financial_planning_path
    assert_predicate flash[:alert], :present?
  end

  test "preview users without the flag cannot add an item" do
    @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => false))

    assert_no_difference -> { EstateItem.count } do
      post financial_planning_estate_items_path, params: {
        estate_item: { kind: "will", title: "Will" }
      }
    end

    assert_redirected_to root_path
  end
end
