# Read-only planning view: savings rate, 50/30/20 split, FIRE progress and a
# 10-year wealth projection. Every figure is derived from the family's existing
# ledger, so this controller only assembles POROs and hands them to the view.
class FinancialPlanningController < ApplicationController
  # Declared before `include Periodable` so the preview gate runs ahead of
  # `set_period`, which may persist a `?period=` onto the user.
  before_action :require_preview_features!
  include Periodable

  def show
    # Reverse proxies in front of self-hosted instances (nginx, Caddy, Tailscale
    # Serve) cache aggressively, and a stale HTML page is worse than a slow one:
    # it references asset fingerprints that no longer exist and renders as an
    # unstyled, half-functional page. no-store keeps the document fresh without
    # disabling caching of the fingerprinted assets underneath.
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"

    @savings_rate = FinancialPlanning::SavingsRate.new(Current.family, period: current_month_period, user: Current.user)
    @year_to_date_savings_rate = FinancialPlanning::SavingsRate.new(Current.family, period: year_to_date_period, user: Current.user)

    @budget_analyzer = FinancialPlanning::BudgetAnalyzer.new(Current.family, period: @period, user: Current.user)

    @fire_progress = FinancialPlanning::FireProgress.new(Current.family, user: Current.user)
    # Built here rather than inside the card so the FIRE form edits the persisted
    # record instead of writing to an unsaved copy that would silently vanish.
    @planning_setting = Current.family.planning_setting || Current.family.build_planning_setting
    @projector = FinancialPlanning::WealthProjector.new(Current.family, user: Current.user)
  end

  # Drives the projection chart. Kept as a separate action so the series can be
  # re-fetched when the horizon or assumptions change without re-rendering the
  # page. `private` amounts are already scoped to the signed-in family.
  # Drives the projection chart, and the compound calculator above it. Both
  # `monthly_contribution` and `growth_rate_pct` may be supplied per request so
  # dragging a slider re-projects without persisting anything -- the saved
  # PlanningSetting is only consulted when a param is absent or unparseable.
  def projection
    # The calculator re-projects on every slider drag; a cached answer would
    # make the slider feel broken even though the server computed a new one.
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"

    projector = FinancialPlanning::WealthProjector.new(
      Current.family,
      user: Current.user,
      monthly_contribution: positive_param(:monthly_contribution),
      growth_rate: ratio_param(:growth_rate_pct)
    )
    points = projector.points

    render json: {
      years: points.map { |point| point.year },
      balances: points.map { |point| point.balance.to_s("F") },
      balance_labels: points.map { |point| helpers.format_money(point.balance_money(Current.family.currency)) },
      final_balance: points.last.balance.to_s("F"),
      final_balance_label: helpers.format_money(points.last.balance_money(Current.family.currency)),
      monthly_contribution: projector.monthly_contribution.to_s("F"),
      growth_rate_pct: projector.growth_rate_pct,
      currency: Current.family.currency
    }
  end

  # Category -> bucket assignment, made inline from the analyzer. Scoped to the
  # signed-in family's categories so a submitted id from another family can't
  # be used to write into this family's settings.
  def update_bucket
    category = Current.family.categories.find_by(id: bucket_params[:category_id])
    return redirect_to(financial_planning_path, alert: t(".category_not_found")) if category.nil?

    setting = Current.family.planning_setting || Current.family.build_planning_setting
    # Keyed by category id, valued by bucket -- the inverse silently fails the
    # model's validation, so the override looks ignored instead of rejected.
    buckets = setting.category_buckets.dup

    if reset_bucket?
      # Dropping the key is what "back to the default" means. Writing a sentinel
      # instead would leave a permanent override that shadows the built-in
      # mapping forever, and `category_buckets` validates values against BUCKETS
      # so there is no legal way to spell "no override" as a value.
      buckets.delete(category.id.to_s)
    else
      buckets[category.id.to_s] = bucket_params[:bucket].to_s
    end

    if setting.update(category_buckets: buckets)
      redirect_to financial_planning_path, notice: t(".bucket_updated")
    else
      redirect_to financial_planning_path, alert: setting.errors.full_messages.to_sentence
    end
  end

  def update_setting
    setting = Current.family.planning_setting || Current.family.build_planning_setting
    attrs = setting_params

    variant = attrs[:fire_variant].presence
    if variant.present? && variant != setting.fire_variant
      # Switching variant carries that variant's rate with it, otherwise picking
      # "Fat FIRE" would silently leave the number at the 4% rule and the target
      # unchanged -- the family would see the label change and nothing else. A
      # hand-tuned rate survives because the form only overwrites on a *change*
      # of variant.
      attrs = attrs.merge(
        fire_withdrawal_rate_pct: PlanningSetting::FIRE_VARIANTS.fetch(variant)[:withdrawal_rate_pct]
      )
    end

    # The target year only means anything for Coast FIRE, but it is deliberately
    # left in place for the other variants rather than cleared: switching away
    # and back is a normal thing to do, and wiping it would make the family
    # retype it. It stays valid there, and PlanningSetting only *requires* it
    # when the variant is coast.
    if setting.update(attrs)
      redirect_to financial_planning_path, notice: t(".setting_updated")
    else
      redirect_to financial_planning_path, alert: setting.errors.full_messages.to_sentence
    end
  end

  private
    def bucket_params
      params.permit(:category_id, :bucket)
    end

    # The bucket select offers "back to default" alongside the three buckets, so
    # "unassigned" has to be distinguishable from a real bucket without being
    # submitted as a value the model would accept.
    def reset_bucket?
      bucket_params[:bucket].to_s == PlanningSetting::RESET_BUCKET
    end

    def current_month_period
      Period.current_month_for(Current.family)
    end

    def year_to_date_period
      Period.from_key("current_year")
    end

    def setting_params
      params.require(:planning_setting).permit(
        :fire_variant, :fire_target_year, :fire_withdrawal_rate_pct, :annual_growth_rate_pct
      )
    end

    # BigDecimal, not Float: the projector reads its saved assumptions from a
    # decimal column, so an override has to be the same type or the response
    # formats as "F" against a Float and raises mid-render. Money arithmetic
    # downstream also wants the decimal.
    def positive_param(key)
      value = params[key].presence
      return nil if value.nil?

      parsed = BigDecimal(value, exception: false)
      return nil if parsed.nil? || !parsed.finite? || parsed.negative?

      parsed
    end

    def ratio_param(key)
      pct = positive_param(key)
      return nil if pct.nil?

      pct / 100.0
    end
end
