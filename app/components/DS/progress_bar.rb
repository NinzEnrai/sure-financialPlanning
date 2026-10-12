# A linear progress bar, decoupled from any domain model.
#
# The bar shape was already hand-rolled in four places -- bills' month pulse,
# budget categories, goal funding breakdowns and the balance sheet -- each with
# its own height, rounding and track color. This owns the geometry so a fifth
# surface doesn't add a fifth copy, and so the accessible progressbar role is
# emitted consistently.
#
# Not a segmented/stacked bar (several proportional segments, e.g. the 50/30/20
# split or a goal's funding mix) and not DS::ProgressRing. This is one value
# against one track.
class DS::ProgressBar < DesignSystemComponent
  TONES = {
    success: "bg-success",
    warning: "bg-warning",
    destructive: "bg-destructive",
    info: "bg-info",
    neutral: "bg-gray-400"
  }.freeze

  # 6px is the height every existing hand-rolled bar settled on.
  HEIGHTS = { xs: "h-1", sm: "h-1.5", md: "h-2" }.freeze

  TRACKS = {
    inset: "bg-surface-inset",
    container: "bg-container-inset"
  }.freeze

  attr_reader :percent, :label, :tone, :height, :track

  def initialize(percent:, label: nil, tone: :success, height: :sm, track: :inset, **opts)
    @percent = percent
    @label = label
    @tone = tone.to_sym
    @height = height.to_sym
    @track = track.to_sym
    @opts = opts
  end

  # A nil percent (a metric that can't be computed) renders an empty track
  # rather than 0%, so "no data" is never read as "none of the way there".
  def clamped_percent
    return 0 if percent.nil?

    [ [ percent.to_f, 0 ].max, 100 ].min
  end

  def computed?
    percent.present?
  end

  def tone_class
    TONES.fetch(tone, TONES[:neutral])
  end

  def height_class
    HEIGHTS.fetch(height, HEIGHTS[:sm])
  end

  def track_class
    TRACKS.fetch(track, TRACKS[:inset])
  end

  def container_classes
    class_names("w-full rounded-full overflow-hidden", height_class, track_class, opts[:class])
  end

  # role=progressbar + values only when a label is supplied; otherwise the bar is
  # decorative and the surrounding copy carries the meaning.
  def wrapper_aria
    return {} if label.blank?

    { role: "progressbar", aria: { valuenow: clamped_percent.round, valuemin: 0, valuemax: 100, label: label } }
  end

  private
    attr_reader :opts
end
