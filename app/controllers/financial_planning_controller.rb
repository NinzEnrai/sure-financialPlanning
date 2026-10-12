# Read-only planning view: savings rate, 50/30/20 split, FIRE progress and a
# 10-year wealth projection. Every figure is derived from the family's existing
# ledger, so this controller only assembles POROs and hands them to the view.
class FinancialPlanningController < ApplicationController
  # Declared before `include Periodable` so the preview gate runs ahead of
  # `set_period`, which may persist a `?period=` onto the user.
  before_action :require_preview_features!
  include Periodable

  def show
    @savings_rate = FinancialPlanning::SavingsRate.new(Current.family, period: current_month_period, user: Current.user)
    @year_to_date_savings_rate = FinancialPlanning::SavingsRate.new(Current.family, period: year_to_date_period, user: Current.user)

    @budget_analyzer = FinancialPlanning::BudgetAnalyzer.new(Current.family, period: @period, user: Current.user)

    @fire_progress = FinancialPlanning::FireProgress.new(Current.family, user: Current.user)
    @projector = FinancialPlanning::WealthProjector.new(Current.family, user: Current.user)
  end

  # Drives the projection chart. Kept as a separate action so the series can be
  # re-fetched when the horizon or assumptions change without re-rendering the
  # page. `private` amounts are already scoped to the signed-in family.
  def projection
    points = FinancialPlanning::WealthProjector.new(Current.family, user: Current.user).points

    render json: {
      years: points.map { |point| point.year },
      balances: points.map { |point| point.balance.to_s("F") },
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
    buckets = setting.category_buckets.merge(category.id.to_s => bucket_params[:bucket].to_s)

    if setting.update(category_buckets: buckets)
      redirect_to financial_planning_path, notice: t(".bucket_updated")
    else
      redirect_to financial_planning_path, alert: setting.errors.full_messages.to_sentence
    end
  end

  def update_setting
    setting = Current.family.planning_setting || Current.family.build_planning_setting

    if setting.update(setting_params)
      redirect_to financial_planning_path, notice: t(".setting_updated")
    else
      redirect_to financial_planning_path, alert: setting.errors.full_messages.to_sentence
    end
  end

  private
    def bucket_params
      params.permit(:category_id, :bucket)
    end

    def current_month_period
      Period.current_month_for(Current.family)
    end

    def year_to_date_period
      Period.from_key("current_year")
    end

    def setting_params
      params.require(:planning_setting).permit(:fire_withdrawal_rate_pct, :annual_growth_rate_pct)
    end
end
