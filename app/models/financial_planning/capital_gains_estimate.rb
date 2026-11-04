# A per-person capital-gains estimate for the current financial year, built on
# the FIFO lot engine and the realised-gains conversion.
#
# It estimates the TAXABLE gain, not the tax. Rates are deliberately not
# applied: the app's own notes say current-year Indian rates must be re-checked
# against the Finance Act before any figure ships, and a stale rate quoted as
# fact is worse than no rate. What this does apply are the mechanics that decide
# the taxable amount:
#
#   * the tax unit is a person (account owner), because tax is assessed per PAN;
#     accounts with no owner are grouped as unassigned rather than folded into
#     someone else's return;
#   * short-term losses offset short-term gains first, then long-term gains;
#   * long-term losses offset only long-term gains;
#   * the listed-equity long-term exemption, only for an Indian household, is
#     applied after set-off and only to what remains;
#   * unusable losses are reported as carried forward, never netted away.
#
# The listed-equity 365-day threshold comes from RealisedGains. Debt funds,
# unlisted shares and foreign shares have different rules; that limitation is
# stated on the card and belongs to the eventual tax estimate, not here.
class FinancialPlanning::CapitalGainsEstimate
  LTCG_EXEMPTION = BigDecimal("125000")

  OwnerEstimate = Data.define(
    :owner, :realised_gains, :short_term, :long_term, :exemption_used,
    :short_term_taxable, :long_term_taxable, :carried_forward_loss, :unknown_count
  ) do
    def sales_count
      realised_gains.rows.size
    end
  end

  attr_reader :family, :user, :as_of

  def initialize(family, user: nil, as_of: Date.current)
    @family = family
    @user = user || Current.user
    @as_of = as_of.to_date
  end

  def estimates
    @estimates ||= accounts_by_owner.map do |owner_id, account_ids|
      build_estimate(owner_id, account_ids)
    end
  end

  def any?
    estimates.any? { |estimate| !estimate.realised_gains.empty? }
  end

  def apply_exemption?
    family.country.to_s.upcase == "IN"
  end

  def exemption_limit
    apply_exemption? ? LTCG_EXEMPTION : BigDecimal("0")
  end

  def financial_year_label
    readiness.financial_year_label
  end

  def total_taxable
    estimates.sum { |estimate| estimate.short_term_taxable + estimate.long_term_taxable }.round(2)
  end

  def total_taxable_money
    Money.new(total_taxable, family.currency)
  end

  private
    def build_estimate(owner_id, account_ids)
      gains = FinancialPlanning::RealisedGains.new(
        family, user: user, as_of: as_of, account_ids: account_ids
      )
      short = gains.short_term_gain.to_d
      long = gains.long_term_gain.to_d

      short_gain = [ short, 0 ].max
      long_gain = [ long, 0 ].max
      short_loss = [ -short, 0 ].max
      long_loss = [ -long, 0 ].max

      short_loss_used = [ short_loss, long_gain ].min
      long_gain_after_setoff = long_gain - short_loss_used
      short_loss_left = short_loss - short_loss_used

      exemption_used = [ long_gain_after_setoff, exemption_limit ].min
      long_term_taxable = long_gain_after_setoff - exemption_used

      OwnerEstimate.new(
        owner: owners[owner_id],
        realised_gains: gains,
        short_term: short,
        long_term: long,
        exemption_used: exemption_used,
        short_term_taxable: short_gain,
        long_term_taxable: long_term_taxable,
        carried_forward_loss: short_loss_left + long_loss,
        unknown_count: gains.unknown_count
      )
    end

    def accounts_by_owner
      family.accounts.visible.group_by(&:owner_id).transform_values { |accounts| accounts.map(&:id) }
    end

    def owners
      @owners ||= User.where(id: family.accounts.visible.distinct.pluck(:owner_id).compact).index_by(&:id)
    end

    def readiness
      @readiness ||= FinancialPlanning::TaxReadiness.new(family, user: user)
    end
end
