require "test_helper"

class InsurancePolicyTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @family = families(:dylan_family)
  end

  test "validates type, frequency, insurer and amounts" do
    policy = @family.insurance_policies.build(
      policy_type: "bogus",
      premium_frequency: "weekly",
      provider: "",
      cover_amount: -1,
      premium_amount: -1
    )

    assert_not policy.valid?
    assert_includes policy.errors[:policy_type], "is not included in the list"
    assert_includes policy.errors[:premium_frequency], "is not included in the list"
    assert_includes policy.errors[:provider], "can't be blank"
    assert_not_empty policy.errors[:cover_amount]
    assert_not_empty policy.errors[:premium_amount]
  end

  test "annualises the premium by payment frequency" do
    policy = build_policy(policy_type: "health", premium_amount: 1000, premium_frequency: "monthly")

    assert_equal 12_000, policy.annual_premium
    assert_equal 4000, build_policy(policy_type: "health", premium_amount: 1000, premium_frequency: "quarterly").annual_premium
    assert_equal 1000, build_policy(policy_type: "health", premium_amount: 1000, premium_frequency: "yearly").annual_premium
  end

  test "classifies life and health cover" do
    assert build_policy(policy_type: "term_life").life?
    assert build_policy(policy_type: "ulip").life?
    assert_not build_policy(policy_type: "health").life?
    assert build_policy(policy_type: "health").health?
  end

  test "flags renewals inside the warning window and overdue ones" do
    travel_to Date.new(2026, 11, 5) do
      assert build_policy(renewal_date: Date.new(2026, 11, 20)).renewing_soon?
      assert build_policy(renewal_date: Date.new(2026, 11, 1)).renewal_overdue?
      assert_not build_policy(renewal_date: Date.new(2027, 6, 1)).renewing_soon?
      assert_not build_policy(renewal_date: nil).renewing_soon?
    end
  end

  private
    def build_policy(**attrs)
      @family.insurance_policies.build(
        {
          policy_type: "term_life",
          provider: "Insurer",
          cover_amount: 1_000_000,
          premium_amount: 20_000,
          premium_frequency: "yearly"
        }.merge(attrs)
      )
    end
end
