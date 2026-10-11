# frozen_string_literal: true

# Backs the new "Financial Planning & Projections" tab. Kept as a single controller with
# a few member-ish actions since each sub-feature (savings rate / goals / FIRE / allocation)
# is read-mostly and cheap to compute on each request -- split into separate controllers
# later if any of these views grow complex enough to warrant it (goals CRUD especially,
# once you add edit/delete UI, should probably move to its own GoalsController).
class FinancialPlanningController < ApplicationController
  before_action :set_family

  def index
    @savings = FinancialPlanning::SavingsRateCalculator.new(@family).summary
    @savings_series = FinancialPlanning::SavingsRateCalculator.new(@family).monthly_series(months: 12)
    @goals = @family.financial_goals.order(:target_date)
    @allocation = @family.planning_setting ? FinancialPlanning::AssetAllocationComparator.new(@family).compare : []
  end

  def savings_rate
    months = params[:months].to_i.clamp(1, 36).nonzero? || 12
    render json: FinancialPlanning::SavingsRateCalculator.new(@family).monthly_series(months: months)
  end

  def fire_simulator
    settings = @family.planning_setting || @family.build_planning_setting
    simulator = FinancialPlanning::FireSimulator.new(@family, settings: settings)

    result = simulator.simulate(
      current_net_worth: params[:net_worth]&.to_d,
      monthly_savings: params[:monthly_savings]&.to_d
    )

    render json: {
      years_to_fire: result.years_to_fire,
      fire_number: result.fire_number,
      projection: result.projection.map(&:to_h)
    }
  end

  def create_goal
    goal = @family.financial_goals.new(goal_params)
    if goal.save
      redirect_to financial_planning_path, notice: "Goal created."
    else
      redirect_to financial_planning_path, alert: goal.errors.full_messages.to_sentence
    end
  end

  def goal_projection
    goal = @family.financial_goals.find(params[:id])
    projector = FinancialPlanning::GoalProjector.new(goal)
    render json: {
      required_monthly_contribution: projector.required_monthly_contribution,
      projected_balance: projector.projected_balance
    }
  end

  private

  def set_family
    @family = current_family # ASSUMPTION: matches existing controllers' auth helper
  end

  def goal_params
    params.require(:financial_goal).permit(:name, :goal_type, :target_amount, :target_date,
                                            :linked_account_id, :priority)
  end
end
