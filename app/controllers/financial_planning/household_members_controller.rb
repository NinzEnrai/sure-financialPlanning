# Create and remove the people the advisory plan is for. Deliberately narrow:
# this is a list of names, relationships and dates of birth, not a user account
# management screen.
class FinancialPlanning::HouseholdMembersController < ApplicationController
  before_action :require_preview_features!

  def create
    member = Current.family.household_members.build(member_params)

    if member.save
      redirect_to financial_planning_path, notice: t(".created")
    else
      redirect_to financial_planning_path, alert: member.errors.full_messages.to_sentence
    end
  end

  def update
    member = Current.family.household_members.find_by(id: params[:id])
    return redirect_to(financial_planning_path, alert: t(".not_found")) if member.nil?

    if member.update(member_params)
      redirect_to financial_planning_path, notice: t(".updated")
    else
      redirect_to financial_planning_path, alert: member.errors.full_messages.to_sentence
    end
  end

  def destroy
    member = Current.family.household_members.find_by(id: params[:id])
    return redirect_to(financial_planning_path, alert: t(".not_found")) if member.nil?

    member.destroy
    redirect_to financial_planning_path, notice: t(".removed")
  end

  private
    def member_params
      params.require(:household_member).permit(:name, :relationship, :date_of_birth, :dependent)
    end
end
