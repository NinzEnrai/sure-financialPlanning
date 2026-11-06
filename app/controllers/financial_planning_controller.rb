# Read-only planning view: savings rate, 50/30/20 split, FIRE progress and a
# 10-year wealth projection. Every figure is derived from the family's existing
# ledger, so this controller only assembles POROs and hands them to the view.
class FinancialPlanningController < ApplicationController
  # Declared before `include Periodable` so the preview gate runs ahead of
  # `set_period`, which may persist a `?period=` onto the user.
  before_action :require_preview_features!
  include Periodable

  # Cards on the planning page, in the order they are laid out. Each key also
  # names the section in user preferences, so the dashboard-style "edit widgets"
  # mode can hide and restore them without touching the card partials.
  PLANNING_SECTIONS = {
    "health_scorecard" => { title: "financial_planning.sections.health_scorecard", partial: "financial_planning/health_scorecard" },
    "household" => { title: "financial_planning.sections.household", partial: "financial_planning/household" },
    "protection" => { title: "financial_planning.sections.protection", partial: "financial_planning/protection" },
    "estate" => { title: "financial_planning.sections.estate", partial: "financial_planning/estate" },
    "savings_rate" => { title: "financial_planning.sections.savings_rate", partial: "financial_planning/savings_rate" },
    "fire_progress" => { title: "financial_planning.sections.fire_progress", partial: "financial_planning/fire_progress" },
    "emergency_fund" => { title: "financial_planning.sections.emergency_fund", partial: "financial_planning/emergency_fund" },
    "debt_summary" => { title: "financial_planning.sections.debt_summary", partial: "financial_planning/debt_summary" },
    "portfolio_return" => { title: "financial_planning.sections.portfolio_return", partial: "financial_planning/portfolio_return" },
    "goal_funding" => { title: "financial_planning.sections.goal_funding", partial: "financial_planning/goal_funding" },
    "allocation" => { title: "financial_planning.sections.allocation", partial: "financial_planning/allocation" },
    "fee_audit" => { title: "financial_planning.sections.fee_audit", partial: "financial_planning/fee_audit" },
    "cash_flow_forecast" => { title: "financial_planning.sections.cash_flow_forecast", partial: "financial_planning/cash_flow_forecast" },
    "coaching" => { title: "financial_planning.sections.coaching", partial: "financial_planning/coaching" },
    "data_confidence" => { title: "financial_planning.sections.data_confidence", partial: "financial_planning/data_confidence" },
    "tax_readiness" => { title: "financial_planning.sections.tax_readiness", partial: "financial_planning/tax_readiness" },
    "realised_gains" => { title: "financial_planning.sections.realised_gains", partial: "financial_planning/realised_gains" },
    "capital_gains_estimate" => { title: "financial_planning.sections.capital_gains_estimate", partial: "financial_planning/capital_gains_estimate" },
    "tax_harvesting" => { title: "financial_planning.sections.tax_harvesting", partial: "financial_planning/tax_harvesting" },
    "tax_profile" => { title: "financial_planning.sections.tax_profile", partial: "financial_planning/tax_profile" },
    "budget_analyzer" => { title: "financial_planning.sections.budget_analyzer", partial: "financial_planning/budget_analyzer" },
    "wealth_projector" => { title: "financial_planning.sections.wealth_projector", partial: "financial_planning/wealth_projector" },
    "retirement_stress" => { title: "financial_planning.sections.retirement_stress", partial: "financial_planning/retirement_stress" }
  }.freeze

  PLANNING_ROWS = [
    [ "health_scorecard" ],
    [ "household" ],
    [ "protection" ],
    [ "estate" ],
    [ "savings_rate", "fire_progress" ],
    [ "emergency_fund", "debt_summary" ],
    [ "portfolio_return", "goal_funding" ],
    [ "allocation" ],
    [ "fee_audit" ],
    [ "cash_flow_forecast", "coaching" ],
    [ "data_confidence", "tax_readiness" ],
    [ "realised_gains" ],
    [ "capital_gains_estimate" ],
    [ "tax_harvesting" ],
    [ "tax_profile" ],
    :period_picker,
    [ "budget_analyzer" ],
    [ "wealth_projector" ],
    [ "retirement_stress" ]
  ].freeze

  def show
    # Reverse proxies in front of self-hosted instances (nginx, Caddy, Tailscale
    # Serve) cache aggressively, and a stale HTML page is worse than a slow one:
    # it references asset fingerprints that no longer exist and renders as an
    # unstyled, half-functional page. no-store keeps the document fresh without
    # disabling caching of the fingerprinted assets underneath.
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"

    # One income statement, balance sheet and investment statement per request:
    # every card reads through these, and each memoises its aggregates per
    # period. Sharing them removes the duplicated aggregate queries that made
    # this page the slowest in the app.
    family = Current.family
    user = Current.user
    income_statement = family.income_statement(user: user)
    balance_sheet = family.balance_sheet(user: user)
    investment_statement = family.investment_statement(user: user)
    active_goals = Goal.prepared_for(family, scope: family.goals.where(state: "active"))
    funding_goals = Goal.active_prepared_for(family)
    tax_lots = Portfolio::TaxLots.new(
      account_ids: family.accounts.visible.accessible_by(user).pluck(:id),
      as_of: Date.current
    )

    @savings_rate = FinancialPlanning::SavingsRate.new(family, period: current_month_period, user: user, income_statement: income_statement)
    @year_to_date_savings_rate = FinancialPlanning::SavingsRate.new(family, period: year_to_date_period, user: user, income_statement: income_statement)

    @budget_analyzer = FinancialPlanning::BudgetAnalyzer.new(family, period: @period, user: user, income_statement: income_statement)

    @fire_progress = FinancialPlanning::FireProgress.new(family, user: user, income_statement: income_statement, balance_sheet: balance_sheet)
    # Built here rather than inside the card so the FIRE form edits the persisted
    # record instead of writing to an unsaved copy that would silently vanish.
    @planning_setting = family.planning_setting || family.build_planning_setting
    @projector = FinancialPlanning::WealthProjector.new(family, user: user, savings_rate: @savings_rate, balance_sheet: balance_sheet)

    # Cash-only buffer: deliberately separate from FIRE, which is the whole net
    # worth against the same spending figure.
    @emergency_fund = FinancialPlanning::EmergencyFund.new(family, user: user, income_statement: income_statement)
    @debt_summary = FinancialPlanning::DebtSummary.new(family, user: user, income_statement: income_statement, balance_sheet: balance_sheet)

    # Protection is cheap but read by four cards; build it once.
    @insurance_policies = family.insurance_policies.order(:created_at)
    @insurance_policy = InsurancePolicy.new
    @protection_gap = FinancialPlanning::ProtectionGap.new(family, user: user)

    @health_scorecard = FinancialPlanning::HealthScorecard.new(
      family, user: user, savings_rate: @savings_rate, emergency_fund: @emergency_fund,
      debt_summary: @debt_summary, protection_gap: @protection_gap, goals: active_goals
    )
    @portfolio_return = FinancialPlanning::PortfolioReturn.new(family, user: user, investment_statement: investment_statement)
    @goal_funding = FinancialPlanning::GoalFunding.new(family, user: user, goals: funding_goals)
    @portfolio_allocation = FinancialPlanning::PortfolioAllocation.new(family, user: user, investment_statement: investment_statement)
    @fee_audit = FinancialPlanning::FeeAudit.new(family, user: user, investment_statement: investment_statement)
    @cash_flow_forecast = FinancialPlanning::CashFlowForecast.new(
      family, user: user, emergency_fund: @emergency_fund, debt_summary: @debt_summary, protection_gap: @protection_gap
    )
    @coaching = FinancialPlanning::BehaviouralNudges.new(
      family, user: user, emergency_fund: @emergency_fund, debt_summary: @debt_summary,
      allocation: @portfolio_allocation, income_statement: income_statement
    )
    @realised_gains = FinancialPlanning::RealisedGains.new(family, user: user, tax_lots: tax_lots)
    @capital_gains = FinancialPlanning::CapitalGainsEstimate.new(family, user: user)
    @tax_harvesting = FinancialPlanning::TaxHarvesting.new(family, user: user, tax_lots: tax_lots)
    @retirement_stress = FinancialPlanning::RetirementStressTest.new(
      family, user: user, fire_progress: @fire_progress, savings_rate: @savings_rate, balance_sheet: balance_sheet
    )
    @tax_users = family.users.order(:created_at)
    @tax_profiles = @tax_users.index_with { |tax_user| family.tax_profiles.find_or_initialize_by(user: tax_user) }
    @data_confidence = FinancialPlanning::DataConfidence.new(family, user: user)
    @tax_readiness = FinancialPlanning::TaxReadiness.new(family, user: user, data_confidence: @data_confidence)
    @tradebook_accounts = family.accounts.visible
      .accessible_by(user)
      .where(accountable_type: %w[Investment Crypto])
      .order(:name)

    # People the plan is for, plus a blank record for the add form.
    @household_members = family.household_members.order(:created_at)
    @household_member = HouseholdMember.new

    # Succession checklist, plus a blank record for the add form.
    @estate_items = family.estate_items.order(:created_at)
    @estate_item = EstateItem.new

    # Dashboard-style widget preferences for this page: hide/show only. The
    # cards are rendered through a small wrapper so no card partial needs to
    # know about the edit mode.
    @customizing_planning = params[:customize].present?
    @planning_hidden_sections = Current.user.financial_planning_hidden_sections
    @planning_sections = PLANNING_SECTIONS
    @planning_rows = PLANNING_ROWS
    @planning_locals = {
      "health_scorecard" => { scorecard: @health_scorecard },
      "household" => { members: @household_members, member: @household_member },
      "protection" => { policies: @insurance_policies, policy: @insurance_policy, gap: @protection_gap, members: @household_members },
      "estate" => { items: @estate_items, item: @estate_item },
      "savings_rate" => { rate: @savings_rate, year_to_date: @year_to_date_savings_rate },
      "fire_progress" => { fire: @fire_progress, setting: @planning_setting },
      "emergency_fund" => { emergency_fund: @emergency_fund, setting: @planning_setting },
      "debt_summary" => { debt: @debt_summary },
      "portfolio_return" => { portfolio: @portfolio_return },
      "goal_funding" => { funding: @goal_funding },
      "allocation" => { allocation: @portfolio_allocation, setting: @planning_setting },
      "fee_audit" => { audit: @fee_audit },
      "cash_flow_forecast" => { forecast: @cash_flow_forecast },
      "coaching" => { coaching: @coaching },
      "data_confidence" => { confidence: @data_confidence },
      "tax_readiness" => { readiness: @tax_readiness, accounts: @tradebook_accounts },
      "realised_gains" => { gains: @realised_gains },
      "capital_gains_estimate" => { estimate: @capital_gains },
      "tax_harvesting" => { harvesting: @tax_harvesting },
      "tax_profile" => { users: @tax_users, profiles: @tax_profiles },
      "budget_analyzer" => { analyzer: @budget_analyzer, period: @period },
      "wealth_projector" => { projector: @projector },
      "retirement_stress" => { stress: @retirement_stress, setting: @planning_setting }
    }
  end

  # Hide or restore one planning card. The card list and titles are fixed
  # server-side, so an unknown key is a 404 rather than an arbitrary preference.
  def update_section_hidden
    section_key = params[:section_key]
    return head :not_found unless PLANNING_SECTIONS.key?(section_key)

    hidden = ActiveModel::Type::Boolean.new.cast(params[:hidden])
    Current.user.update_financial_planning_section_hidden(section_key, hidden)

    changed = hidden ? { hidden_section: section_key } : { shown_section: section_key }
    redirect_to financial_planning_path(customize: true, **changed), status: :see_other
  end

  # The yearly artefact a planner hands over: what changed, what is protected,
  # whether the goals are moving, and what to carry into next year.
  def review
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    @review = FinancialPlanning::AnnualReview.new(Current.family, user: Current.user)
  end

  def mark_reviewed
    setting = Current.family.planning_setting || Current.family.build_planning_setting

    if setting.update(last_reviewed_on: Date.current)
      redirect_to review_financial_planning_path, notice: t(".review_marked")
    else
      redirect_to review_financial_planning_path, alert: setting.errors.full_messages.to_sentence
    end
  end

  # Import a Zerodha Console tradebook CSV so purchases made before the app saw
  # the trades have real dates. Idempotent: re-uploading the same file skips
  # rows that already exist.
  def import_tradebook
    account = Current.family.accounts.visible
      .accessible_by(Current.user)
      .where(accountable_type: %w[Investment Crypto])
      .find_by(id: params[:account_id])
    file = params[:tradebook]

    # A crafted POST can send a string where the form sends a file; treat that as
    # a missing upload rather than raising on .read.
    if account.nil? || !file.respond_to?(:read)
      redirect_to financial_planning_path, alert: t(".missing")
      return
    end

    result = Portfolio::ConsoleTradebook.new(
      family: Current.family,
      account: account,
      csv: file.read
    ).call

    if result.errors.any?
      redirect_to financial_planning_path, alert: t(".failed", count: result.errors.size)
    else
      flash[:notice] = t(".imported", imported: result.imported_count, skipped: result.skipped)
      flash[:alert] = t(".unresolved", symbols: result.unresolved.join(", ")) if result.unresolved.any?
      redirect_to financial_planning_path
    end
  end

  # Save one person's declared tax inputs. Scoped to the current family's users,
  # so a submitted id cannot write another household's profile.
  def update_tax_profile
    user = Current.family.users.find_by(id: params[:user_id])
    return redirect_to(financial_planning_path, alert: t("financial_planning.tax_profile.user_not_found")) if user.nil?

    profile = Current.family.tax_profiles.find_or_initialize_by(user: user)

    if profile.update(tax_profile_params)
      redirect_to financial_planning_path, notice: t("financial_planning.tax_profile.saved")
    else
      redirect_to financial_planning_path, alert: profile.errors.full_messages.to_sentence
    end
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

    def tax_profile_params
      params.require(:tax_profile).permit(
        :regime, *TaxProfile::DEDUCTION_ATTRIBUTES
      )
    end

    def setting_params
      params.require(:planning_setting).permit(
        :fire_variant, :fire_target_year, :fire_withdrawal_rate_pct, :annual_growth_rate_pct,
        :emergency_target_months, :needs_target_pct, :wants_target_pct, :savings_target_pct,
        :risk_profile, :retirement_age
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

      pct / 100
    end
end
