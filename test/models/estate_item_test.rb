require "test_helper"

class EstateItemTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "validates kind, status and title" do
    item = @family.estate_items.build(kind: "trust", status: "maybe", title: "")

    assert_not item.valid?
    assert_includes item.errors[:kind], "is not included in the list"
    assert_includes item.errors[:status], "is not included in the list"
    assert_includes item.errors[:title], "can't be blank"
  end

  test "cannot name a household member from another family" do
    other = families(:empty).household_members.create!(name: "Someone else", relationship: "other")
    item = @family.estate_items.build(kind: "will", title: "Will", household_member: other)

    assert_not item.valid?
    assert_includes item.errors[:household_member], "must belong to this family"
  end

  test "accepts every documented kind and status" do
    EstateItem::KINDS.each do |kind|
      assert @family.estate_items.build(kind: kind, title: "Item").valid?
    end

    EstateItem::STATUSES.each do |status|
      item = @family.estate_items.build(kind: "will", title: "Item", status: status)
      assert item.valid?
    end
  end

  test "flags an overdue review but not a future one" do
    assert @family.estate_items.build(kind: "will", title: "Will", review_on: 1.day.ago.to_date).review_overdue?
    assert_not @family.estate_items.build(kind: "will", title: "Will", review_on: 1.day.from_now.to_date).review_overdue?
    assert_not @family.estate_items.build(kind: "will", title: "Will").review_overdue?
  end
end
