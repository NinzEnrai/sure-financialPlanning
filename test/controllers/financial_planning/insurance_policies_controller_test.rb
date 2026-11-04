require "test_helper"

class FinancialPlanning::InsurancePoliciesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => true))
    sign_in @user
  end

  test "adds a policy to the current family" do
    assert_difference -> { @family.insurance_policies.count }, 1 do
      post financial_planning_insurance_policies_path, params: {
        insurance_policy: {
          policy_type: "term_life",
          household_member_id: household_members(:self_member).id,
          provider: "HDFC Life",
          cover_amount: 2_000_000,
          premium_amount: 18_000,
          premium_frequency: "yearly",
          renewal_date: Date.current + 20.days,
          nominee: "Priya"
        }
      }
    end

    assert_redirected_to financial_planning_path
    assert_equal "HDFC Life", @family.insurance_policies.order(:created_at).last.provider
  end

  test "an invalid policy is not created and the reason is shown" do
    assert_no_difference -> { InsurancePolicy.count } do
      post financial_planning_insurance_policies_path, params: {
        insurance_policy: { policy_type: "bogus", provider: "" }
      }
    end

    assert_redirected_to financial_planning_path
    assert_predicate flash[:alert], :present?
  end

  test "removes a policy from the family" do
    policy = @family.insurance_policies.create!(
      policy_type: "health", provider: "Star", cover_amount: 300_000, premium_amount: 12_000, premium_frequency: "yearly"
    )

    assert_difference -> { InsurancePolicy.count }, -1 do
      delete financial_planning_insurance_policy_path(policy)
    end

    assert_redirected_to financial_planning_path
  end

  test "cannot remove another family's policy" do
    other = families(:empty).insurance_policies.create!(
      policy_type: "health", provider: "Other", cover_amount: 100_000, premium_amount: 1000, premium_frequency: "yearly"
    )

    assert_no_difference -> { InsurancePolicy.count } do
      delete financial_planning_insurance_policy_path(other)
    end

    assert_redirected_to financial_planning_path
    assert_predicate flash[:alert], :present?
  end

  test "preview users without the flag cannot add a policy" do
    @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => false))

    assert_no_difference -> { InsurancePolicy.count } do
      post financial_planning_insurance_policies_path, params: {
        insurance_policy: { policy_type: "health", provider: "Star", cover_amount: 100_000, premium_amount: 1000, premium_frequency: "yearly" }
      }
    end

    assert_redirected_to root_path
  end
end
