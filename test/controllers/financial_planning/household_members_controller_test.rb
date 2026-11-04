require "test_helper"

class FinancialPlanning::HouseholdMembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => true))
    sign_in @user
  end

  test "adds a person to the current family" do
    assert_difference -> { @family.household_members.count }, 1 do
      post financial_planning_household_members_path, params: {
        household_member: {
          name: "Priya",
          relationship: "spouse",
          date_of_birth: Date.new(1992, 5, 1),
          dependent: "0"
        }
      }
    end

    assert_redirected_to financial_planning_path
    assert_equal "Priya", @family.household_members.order(:created_at).last.name
  end

  test "an invalid person is not created and the reason is shown" do
    assert_no_difference -> { HouseholdMember.count } do
      post financial_planning_household_members_path, params: {
        household_member: { name: "", relationship: "spouse" }
      }
    end

    assert_redirected_to financial_planning_path
    assert_predicate flash[:alert], :present?
  end

  test "removes a person from the family" do
    member = household_members(:child_member)

    assert_difference -> { HouseholdMember.count }, -1 do
      delete financial_planning_household_member_path(member)
    end

    assert_redirected_to financial_planning_path
  end

  test "cannot remove somebody from another family" do
    other = families(:empty).household_members.create!(name: "Someone else", relationship: "other")

    assert_no_difference -> { HouseholdMember.count } do
      delete financial_planning_household_member_path(other)
    end

    assert_redirected_to financial_planning_path
    assert_predicate flash[:alert], :present?
  end

  test "preview users without the flag cannot add a person" do
    @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => false))

    assert_no_difference -> { HouseholdMember.count } do
      post financial_planning_household_members_path, params: {
        household_member: { name: "Priya", relationship: "spouse" }
      }
    end

    assert_redirected_to root_path
  end
end
