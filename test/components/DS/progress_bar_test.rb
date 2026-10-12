require "test_helper"

class DS::ProgressBarTest < ViewComponent::TestCase
  test "renders a track and a fill sized to the percent" do
    render_inline(DS::ProgressBar.new(percent: 40))

    assert_selector "[style='width: 40.0%']"
  end

  test "clamps out-of-range percents" do
    assert_equal 100, DS::ProgressBar.new(percent: 140).clamped_percent
    assert_equal 0, DS::ProgressBar.new(percent: -10).clamped_percent
  end

  test "a nil percent renders an empty bar rather than reading as zero" do
    render_inline(DS::ProgressBar.new(percent: nil))

    assert_selector "[style='width: 0%']"
    assert_not DS::ProgressBar.new(percent: nil).computed?
  end

  test "exposes a progressbar role and value only when labelled" do
    render_inline(DS::ProgressBar.new(percent: 30, label: "Savings rate"))

    assert_selector "[role='progressbar'][aria-valuenow='30'][aria-label='Savings rate']"

    render_inline(DS::ProgressBar.new(percent: 30))

    assert_no_selector "[role='progressbar']"
  end

  test "tone selects the fill color class" do
    assert_equal "bg-success", DS::ProgressBar.new(percent: 1, tone: :success).tone_class
    assert_equal "bg-warning", DS::ProgressBar.new(percent: 1, tone: :warning).tone_class
    assert_equal "bg-destructive", DS::ProgressBar.new(percent: 1, tone: :destructive).tone_class
    # Unknown tone falls back to neutral.
    assert_equal "bg-gray-400", DS::ProgressBar.new(percent: 1, tone: :bogus).tone_class
  end

  test "height and track map to the shared scale tokens" do
    assert_equal "h-1.5", DS::ProgressBar.new(percent: 1).height_class
    assert_equal "h-2", DS::ProgressBar.new(percent: 1, height: :md).height_class
    assert_equal "bg-surface-inset", DS::ProgressBar.new(percent: 1).track_class
    assert_equal "bg-container-inset", DS::ProgressBar.new(percent: 1, track: :container).track_class
  end
end