# Add and remove protection policies. Like household members, this is scoped to
# the current family and preview-gated with the rest of the planning page.
class FinancialPlanning::InsurancePoliciesController < ApplicationController
  before_action :require_preview_features!

  def create
    policy = Current.family.insurance_policies.build(policy_params)

    if policy.save
      redirect_to financial_planning_path, notice: t(".created")
    else
      redirect_to financial_planning_path, alert: policy.errors.full_messages.to_sentence
    end
  end

  def destroy
    policy = Current.family.insurance_policies.find_by(id: params[:id])
    return redirect_to(financial_planning_path, alert: t(".not_found")) if policy.nil?

    policy.destroy
    redirect_to financial_planning_path, notice: t(".removed")
  end

  private
    def policy_params
      params.require(:insurance_policy).permit(
        :policy_type, :household_member_id, :provider, :policy_number,
        :cover_amount, :premium_amount, :premium_frequency,
        :renewal_date, :nominee, :notes
      )
    end
end
