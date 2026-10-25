class PlanningSetting < ApplicationRecord
  belongs_to :family

  # 50/30/20 targets, expressed as a share of net income. Needs and wants are
  # ceilings, savings is a floor -- the analyzer scores each bucket against the
  # matching direction rather than treating all three as "spend less".
  BUCKETS = %w[needs wants savings].freeze
  TARGET_SHARE_PCT = { "needs" => 50, "wants" => 30, "savings" => 20 }.freeze

  # Submitted by the bucket picker to mean "drop my override and go back to the
  # built-in mapping". Deliberately not a member of BUCKETS: the model validates
  # that every stored value is a real bucket, so a reset has to be expressed as
  # an absent key rather than as a value to store.
  RESET_BUCKET = "__default__".freeze

  # The flavours of financial independence, and what each one assumes.
  #
  # `withdrawal_rate_pct` is the default a family gets when they pick the
  # variant. It is a starting point, not a lock -- a family who tunes the rate by
  # hand keeps their value, because the form only overwrites it on the transition
  # into a new variant.
  #
  # The rates are the commonly-cited numbers for each style rather than a claim
  # about anyone's circumstances:
  #
  #   lean      ~30x -- deliberately austere, so a lower rate still covers it
  #   coast     25x, but the goal is reaching it *by an age* rather than at any
  #             age, then coasting to retirement on growth alone
  #   barista   ~15x -- the portfolio only has to stretch part-time work over the
  #             gap, so the target is deliberately lower
  #   standard  25x -- the classic 4% rule
  #   fat       ~33x -- a richer lifestyle funded by a lower rate
  #
  # `needs_target_age` marks Coast FIRE as the one variant measured against a
  # date rather than a multiple.
  FIRE_VARIANTS = {
    "lean" => { withdrawal_rate_pct: 3.3, needs_target_age: false },
    "coast" => { withdrawal_rate_pct: 4.0, needs_target_age: true },
    "barista" => { withdrawal_rate_pct: 6.5, needs_target_age: false },
    "standard" => { withdrawal_rate_pct: 4.0, needs_target_age: false },
    "fat" => { withdrawal_rate_pct: 3.0, needs_target_age: false }
  }.freeze

  DEFAULT_FIRE_VARIANT = "standard".freeze

  # Default bucket for each of Sure's built-in categories. Keyed by the exact
  # value Category#default_i18n_key returns -- the full I18n key, not the short
  # suffix -- because a default category persists a translated name and a family
  # may have been bootstrapped in any locale, so the key is the only stable
  # handle. A category the family created itself has no key and stays unassigned
  # until it is overridden in category_buckets.
  #
  # The built-in `income` category is deliberately absent: it holds inflows, so
  # it never reaches the analyzer's expense side.
  DEFAULT_BUCKETS = {
    "models.category.defaults.food_and_drink" => "wants",
    "models.category.defaults.groceries" => "needs",
    "models.category.defaults.shopping" => "wants",
    "models.category.defaults.transportation" => "needs",
    "models.category.defaults.travel" => "wants",
    "models.category.defaults.entertainment" => "wants",
    "models.category.defaults.healthcare" => "needs",
    "models.category.defaults.personal_care" => "wants",
    "models.category.defaults.home_improvement" => "needs",
    "models.category.defaults.mortgage_rent" => "needs",
    "models.category.defaults.utilities" => "needs",
    "models.category.defaults.subscriptions" => "wants",
    "models.category.defaults.insurance" => "needs",
    "models.category.defaults.sports_and_fitness" => "wants",
    "models.category.defaults.gifts_and_donations" => "wants",
    "models.category.defaults.taxes" => "needs",
    "models.category.defaults.loan_payments" => "needs",
    "models.category.defaults.services" => "needs",
    "models.category.defaults.fees" => "needs",
    "models.category.defaults.savings_and_investments" => "savings",
    Category::UNCATEGORIZED_NAME_KEY => "needs",
    Category::OTHER_INVESTMENTS_NAME_KEY => "savings"
  }.freeze

  validates :fire_withdrawal_rate_pct, :annual_growth_rate_pct,
            numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validates :fire_variant, inclusion: { in: FIRE_VARIANTS.keys }
  validates :fire_target_year,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: Date.current.year,
              less_than_or_equal_to: Date.current.year + 60
            },
            allow_nil: true
  validate :category_buckets_are_known_buckets
  validate :category_buckets_belong_to_family

  # Coast FIRE is the one variant measured against a date, so a target year is
  # meaningless for the rest -- and required for it, because without one there is
  # nothing to measure progress toward.
  validate :coast_fire_requires_a_target_year

  def fire_variant_config
    FIRE_VARIANTS.fetch(fire_variant.presence || DEFAULT_FIRE_VARIANT)
  end

  def coast_fire?
    fire_variant == "coast"
  end

  def needs_target_age?
    fire_variant_config[:needs_target_age]
  end

  # Cash needed to sustain the family's current lifestyle indefinitely at the
  # configured withdrawal rate. 25x at 4% -- the number the FIRE progress bar
  # measures net worth against.
  #
  # BigDecimal throughout, and divided rather than multiplied by the reciprocal:
  # in Float, `12000 * (1 / 0.03)` lands on 399999.99999999994, so a figure
  # displayed as a target would be a fraction of a currency unit short.
  def fire_target_money(annual_expenses)
    rate = withdrawal_rate
    return Money.new(0, family.currency) unless rate.positive?

    Money.new(annual_expenses / rate, family.currency)
  end

  # The reciprocal of the withdrawal rate: how many years of expenses one
  # saved dollar buys. Exposed so the widget can show "25x" next to a 4% rate
  # instead of making the reader do the division.
  def fire_multiple
    rate = withdrawal_rate
    return 0 unless rate.positive?

    (1 / rate).round
  end

  def growth_rate
    BigDecimal(annual_growth_rate_pct.to_s.presence || "0") / 100
  end

  # The bucket a category belongs to, preferring the family's own override.
  # `key` is the category's i18n key for built-ins and nil for custom ones.
  #
  # The synthetic Uncategorized / Other Investments pseudo-categories are never
  # persisted, so they have no id and cannot carry an override -- they resolve
  # through DEFAULT_BUCKETS alone.
  def bucket_for(category, key: nil)
    override = category.id && category_buckets[category.id.to_s]

    override || DEFAULT_BUCKETS[key]
  end

  def bucket_override?(category)
    category.id.present? && category_buckets.key?(category.id.to_s)
  end

  private
    def coast_fire_requires_a_target_year
      return unless coast_fire?
      return if fire_target_year.present?

      errors.add(:fire_target_year, "is required for Coast FIRE, which targets a number by a date")
    end

    def withdrawal_rate
      BigDecimal(fire_withdrawal_rate_pct.to_s) / 100
    end

    def category_buckets_are_known_buckets
      unknown = category_buckets.values - BUCKETS
      return if unknown.empty?

      errors.add(:category_buckets, "must each be one of #{BUCKETS.join(', ')}")
    end

    # A bucket row pointing at another family's category would silently never
    # match, so the override would look ignored. Keys are checked for UUID shape
    # before the lookup -- handing Postgres a non-uuid string raises instead of
    # failing validation, turning a bad request into a 500.
    def category_buckets_belong_to_family
      ids = category_buckets.keys
      return if ids.empty?

      if ids.any? { |id| !id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/) }
        errors.add(:category_buckets, "must be keyed by category id")
        return
      end

      return if family.categories.where(id: ids).count == ids.uniq.size

      errors.add(:category_buckets, "must only reference this family's categories")
    end
end
