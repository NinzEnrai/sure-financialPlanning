# Manage the succession checklist. Family-scoped and preview-gated like the rest
# of the planning page; this records status only, never legal advice.
class FinancialPlanning::EstateItemsController < ApplicationController
  before_action :require_preview_features!

  def create
    item = Current.family.estate_items.build(item_params)

    if item.save
      redirect_to financial_planning_path, notice: t(".created")
    else
      redirect_to financial_planning_path, alert: item.errors.full_messages.to_sentence
    end
  end

  def update
    item = Current.family.estate_items.find_by(id: params[:id])
    return redirect_to(financial_planning_path, alert: t(".not_found")) if item.nil?

    if item.update(item_params)
      redirect_to financial_planning_path, notice: t(".updated")
    else
      redirect_to financial_planning_path, alert: item.errors.full_messages.to_sentence
    end
  end

  def destroy
    item = Current.family.estate_items.find_by(id: params[:id])
    return redirect_to(financial_planning_path, alert: t(".not_found")) if item.nil?

    item.destroy
    redirect_to financial_planning_path, notice: t(".removed")
  end

  private
    def item_params
      params.require(:estate_item).permit(
        :kind, :title, :nominee, :status, :review_on, :notes, :household_member_id
      )
    end
end
