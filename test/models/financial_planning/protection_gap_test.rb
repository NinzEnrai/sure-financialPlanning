require "test_helper"

class FinancialPlanning::ProtectionGapTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    clear_entries
  end

  test "is unknown with no policies rather than reassuringly zero" do
    gap = build_gap

    assert gap.empty?
    assert_equal :unknown, gap.status
    assert_equal 0, gap.life_cover_total
  end

  test "compares life cover with ten times recorded annual income" do
    create_transaction(amount: -120_000, date: Date.current)
    add_policy(policy_type: "term_life", cover_amount: 500_000)

    gap = build_gap

    assert_equal 500_000, gap.life_cover_total
    assert_equal 1_200_000, gap.recommended_life_cover
    assert_equal 700_000, gap.life_cover_gap
    assert_equal :attention, gap.status
  end

  test "is good when cover meets the guide" do
    create_transaction(amount: -120_000, date: Date.current)
    add_policy(policy_type: "term_life", cover_amount: 1_500_000)

    gap = build_gap

    assert_equal 0, gap.life_cover_gap
    assert_equal :good, gap.status
  end

  test "stays unknown when income has not been recorded" do
    add_policy(policy_type: "term_life", cover_amount: 1_500_000)

    gap = build_gap

    assert_nil gap.annual_income
    assert_equal :unknown, gap.status
  end

  test "sums annual premiums and health cover" do
    add_policy(policy_type: "health", cover_amount: 300_000, premium_amount: 1000, premium_frequency: "monthly")
    add_policy(policy_type: "term_life", cover_amount: 500_000, premium_amount: 20_000, premium_frequency: "yearly")

    gap = build_gap

    assert_equal 300_000, gap.health_cover_total
    assert_equal 32_000, gap.annual_premium_total
  end

  test "compares premiums with recorded income" do
    create_transaction(amount: -120_000, date: Date.current)
    add_policy(policy_type: "term_life", premium_amount: 12_000, premium_frequency: "yearly")

    gap = build_gap

    assert_in_delta 10.0, gap.premium_affordability_percent.to_f, 0.05
    assert_equal :watch, gap.premium_affordability_status
  end

  test "flags premiums above a tenth of income" do
    create_transaction(amount: -120_000, date: Date.current)
    add_policy(policy_type: "term_life", premium_amount: 24_000, premium_frequency: "yearly")

    gap = build_gap

    assert_in_delta 20.0, gap.premium_affordability_percent.to_f, 0.05
    assert_equal :attention, gap.premium_affordability_status
  end

  test "affordability is unknown without recorded income" do
    add_policy(policy_type: "term_life", premium_amount: 12_000, premium_frequency: "yearly")

    assert_nil build_gap.premium_affordability_percent
    assert_equal :unknown, build_gap.premium_affordability_status
  end

  test "benchmarks Indian health cover per adult" do
    @family.update!(country: "IN", currency: "INR")
    add_policy(policy_type: "health", cover_amount: 300_000)

    gap = build_gap

    assert_in_delta 500_000, gap.health_cover_benchmark, 0.01
    assert_in_delta 200_000, gap.health_cover_gap, 0.01
    assert_equal :watch, gap.health_cover_status
  end

  test "no health cover needs attention whatever the benchmark" do
    @family.update!(country: "IN", currency: "INR")

    assert_equal :attention, build_gap.health_cover_status
  end

  test "no rupee benchmark outside an Indian rupee household" do
    @family.update!(country: "US", currency: "USD")
    add_policy(policy_type: "health", cover_amount: 300_000)

    gap = build_gap

    assert_nil gap.health_cover_benchmark
    assert_nil gap.health_cover_gap
    assert_equal :good, gap.health_cover_status
  end

  test "reports whether health cover exists" do
    assert_not build_gap.health_recorded?

    add_policy(policy_type: "health", cover_amount: 300_000)

    assert build_gap.health_recorded?
  end

  test "counts adults with life cover attached" do
    add_policy(policy_type: "term_life", household_member_id: household_members(:self_member).id)

    gap = build_gap

    assert_equal 1, gap.adults_count
    assert_equal 1, gap.covered_adults_count
    assert_empty gap.uncovered_adults
  end

  test "flags adults without life cover" do
    add_policy(policy_type: "term_life", household_member_id: household_members(:self_member).id)
    @family.household_members.create!(name: "Sam", relationship: "spouse")

    gap = build_gap

    assert_equal 2, gap.adults_count
    assert_equal 1, gap.covered_adults_count
    assert_equal [ "Sam" ], gap.uncovered_adults.map(&:name)
  end

  test "a household-wide policy covers every adult" do
    add_policy(policy_type: "term_life")
    @family.household_members.create!(name: "Sam", relationship: "spouse")

    gap = build_gap

    assert_equal 2, gap.covered_adults_count
    assert_empty gap.uncovered_adults
  end

  test "counts dependants from the household profile" do
    assert_equal 1, build_gap.dependants_count
  end

  private
    def build_gap
      FinancialPlanning::ProtectionGap.new(@family, user: @user)
    end

    def add_policy(**attrs)
      @family.insurance_policies.create!(
        {
          policy_type: "term_life",
          provider: "Insurer",
          cover_amount: 1_000_000,
          premium_amount: 10_000,
          premium_frequency: "yearly"
        }.merge(attrs)
      )
    end

    def clear_entries
      Entry.where(account: @family.accounts).destroy_all
    end
end
