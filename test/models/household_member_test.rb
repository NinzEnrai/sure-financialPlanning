require "test_helper"

class HouseholdMemberTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @family = families(:dylan_family)
  end

  test "requires a name and a known relationship" do
    member = @family.household_members.build(relationship: "spouse")
    assert_not member.valid?
    assert_includes member.errors[:name], "can't be blank"

    member.name = "Priya"
    member.relationship = "cousin"
    assert_not member.valid?
    assert_includes member.errors[:relationship], "is not included in the list"

    member.relationship = "spouse"
    assert member.valid?
  end

  test "computes age from the date of birth" do
    travel_to Date.new(2026, 11, 5) do
      member = @family.household_members.build(name: "A", relationship: "self", date_of_birth: Date.new(1990, 6, 15))
      assert_equal 36, member.age

      member.date_of_birth = Date.new(1990, 12, 31)
      assert_equal 35, member.age
    end
  end

  test "age is unknown without a date of birth" do
    member = @family.household_members.build(name: "A", relationship: "child")

    assert_nil member.age
    assert_not member.adult?
  end

  test "rejects a future date of birth" do
    member = @family.household_members.build(name: "A", relationship: "child", date_of_birth: Date.current + 1.day)

    assert_not member.valid?
    assert_includes member.errors[:date_of_birth], "cannot be in the future"
  end

  test "rejects an implausible date of birth" do
    member = @family.household_members.build(name: "A", relationship: "parent", date_of_birth: 122.years.ago.to_date)

    assert_not member.valid?
    assert_includes member.errors[:date_of_birth], "is not a plausible date of birth"
  end
end
