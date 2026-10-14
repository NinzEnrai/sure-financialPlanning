import { Controller } from "@hotwired/stimulus";

// Shows the target-age field only when Coast FIRE is selected, since every other
// variant is measured against a spending multiple and has no date to hit.
//
// The field is rendered for all variants and hidden here rather than added and
// removed, so switching variants does not need a server round trip just to
// reveal an input. It is still submitted; FinancialPlanningController drops
// `fire_target_age` for non-Coast variants so a stale age can't fail validation.

export default class extends Controller {
  static targets = ["select", "ageField"];
  static values = {
    coast: { type: String, default: "coast" },
  };

  connect() {
    if (!this.hasSelectTarget) return;
    this._onChange = () => this._sync();
    this.selectTarget.addEventListener("change", this._onChange);
    this._sync();
  }

  disconnect() {
    if (this._onChange && this.hasSelectTarget) {
      this.selectTarget.removeEventListener("change", this._onChange);
    }
  }

  _sync() {
    if (!this.hasAgeFieldTarget) return;
    this.ageFieldTarget.hidden = this.selectTarget.value !== this.coastValue;
  }
}