require "test_helper"

class TaxProfileTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @profile = @family.tax_profiles.build(user: @user)
  end

  test "accepts the two regimes or nothing" do
    @profile.regime = "flat"
    assert_not @profile.valid?
    assert_includes @profile.errors[:regime], "is not included in the list"

    TaxProfile::REGIMES.each do |regime|
      @profile.regime = regime
      assert @profile.valid?, "#{regime} should be accepted"
    end

    @profile.regime = nil
    assert @profile.valid?
  end

  test "rejects negative deductions" do
    @profile.deductions_80c = -1

    assert_not @profile.valid?
    assert_not_empty @profile.errors[:deductions_80c]
  end

  test "sums the declared deductions" do
    @profile.update!(
      deductions_80c: 150_000,
      deductions_80d: 25_000,
      deductions_nps: 50_000,
      hra_exemption: 0,
      home_loan_interest: 200_000
    )

    assert_in_delta 425_000, @profile.total_declared_deductions, 0.01
  end

  test "cannot belong to a user from another family" do
    other = families(:empty).users.create!(
      email: "other-#{SecureRandom.hex(3)}@example.com",
      password: "password123",
      first_name: "Other",
      family: families(:empty)
    )

    profile = @family.tax_profiles.build(user: other)

    assert_not profile.valid?
    assert_includes profile.errors[:user], "must belong to this family"
  end
end
