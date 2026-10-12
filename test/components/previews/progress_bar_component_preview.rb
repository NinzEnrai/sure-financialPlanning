class ProgressBarComponentPreview < ViewComponent::Preview
  # @param percent number
  # @param tone select ["success", "warning", "destructive", "info", "neutral"]
  # @param height select ["xs", "sm", "md"]
  # @param track select ["inset", "container"]
  # @param label text
  def default(percent: 65, tone: "success", height: "sm", track: "inset", label: nil)
    render DS::ProgressBar.new(
      percent: percent,
      tone: tone.to_sym,
      height: height.to_sym,
      track: track.to_sym,
      label: label.presence
    )
  end

  # @!group Tones (50%)
  def success
    render DS::ProgressBar.new(percent: 50, tone: :success)
  end

  def warning
    render DS::ProgressBar.new(percent: 50, tone: :warning)
  end

  def destructive
    render DS::ProgressBar.new(percent: 50, tone: :destructive)
  end

  def info
    render DS::ProgressBar.new(percent: 50, tone: :info)
  end

  def neutral
    render DS::ProgressBar.new(percent: 50, tone: :neutral)
  end
  # @!endgroup

  # @!group Sizes
  def xs
    render DS::ProgressBar.new(percent: 72, height: :xs, tone: :success)
  end

  def sm
    render DS::ProgressBar.new(percent: 72, height: :sm, tone: :success)
  end

  def md
    render DS::ProgressBar.new(percent: 72, height: :md, tone: :success)
  end
  # @!endgroup

  # @!group Tracks
  def track_inset
    render DS::ProgressBar.new(percent: 72, track: :inset)
  end

  def track_container
    render DS::ProgressBar.new(percent: 72, track: :container)
  end
  # @!endgroup

  # @!group Edges
  def empty_0
    render DS::ProgressBar.new(percent: 0, tone: :neutral)
  end

  def full_100
    render DS::ProgressBar.new(percent: 100, tone: :success)
  end

  def clamps_over_100
    render DS::ProgressBar.new(percent: 140, tone: :success)
  end

  def no_data_nil
    render DS::ProgressBar.new(percent: nil, tone: :neutral)
  end

  def labelled
    render DS::ProgressBar.new(percent: 40, tone: :warning, label: "Savings rate")
  end
  # @!endgroup
end