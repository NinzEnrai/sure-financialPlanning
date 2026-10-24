import { Controller } from "@hotwired/stimulus";

// Compound calculator for the wealth projection.
//
// Two range inputs (monthly contribution, annual growth) re-project through
// GET /financial_planning/projection and push the result into the chart's
// `render()`. The compounding maths stays in WealthProjector -- doing it twice
// in JS would let the slider and the saved projection drift apart.
//
// Requests are debounced and stale responses are discarded by tracking a
// monotonically increasing token, so dragging quickly never lets an older
// response land after a newer one.

export default class extends Controller {
  static targets = [ "contribution", "growth", "contributionValue", "growthValue", "outcome", "chart" ];
  static values = {
    url: String,
    currency: { type: String, default: "" },
    contributionStep: { type: Number, default: 500 },
    contributionMax: { type: Number, default: 500000 },
    growthMax: { type: Number, default: 25 },
  };

  connect() {
    this._token = 0;
    this._timer = null;
    this._onInput = () => this._scheduleRefresh();
    this._onCommit = () => this._refresh();

    if (this.hasContributionTarget) {
      this.contributionTarget.addEventListener("input", this._onInput);
      this.contributionTarget.addEventListener("change", this._onCommit);
    }
    if (this.hasGrowthTarget) {
      this.growthTarget.addEventListener("input", this._onInput);
      this.growthTarget.addEventListener("change", this._onCommit);
    }

    this._syncLabels();
  }

  disconnect() {
    if (this._timer) clearTimeout(this._timer);
    if (this.hasContributionTarget) {
      this.contributionTarget.removeEventListener("input", this._onInput);
      this.contributionTarget.removeEventListener("change", this._onCommit);
    }
    if (this.hasGrowthTarget) {
      this.growthTarget.removeEventListener("input", this._onInput);
      this.growthTarget.removeEventListener("change", this._onCommit);
    }
  }

  // Keep the printed value under each slider live even while dragging, so the
  // control never feels inert between the (debounced) server round trips.
  _syncLabels() {
    if (this.hasContributionValueTarget && this.hasContributionTarget) {
      this.contributionValueTarget.textContent = this._formatMoney(this.contributionTarget.value);
    }
    if (this.hasGrowthValueTarget && this.hasGrowthTarget) {
      this.growthValueTarget.textContent = `${Number(this.growthTarget.value).toFixed(1)}%`;
    }
  }

  _scheduleRefresh() {
    this._syncLabels();
    if (this._timer) clearTimeout(this._timer);
    this._timer = setTimeout(() => this._refresh(), 180);
  }

  async _refresh() {
    const url = this.urlValue;
    if (!url) return;

    const token = ++this._token;
    const params = new URLSearchParams();
    if (this.hasContributionTarget) params.set("monthly_contribution", this.contributionTarget.value);
    if (this.hasGrowthTarget) params.set("growth_rate_pct", this.growthTarget.value);

    // Visual feedback: the chart is about to change, so the reader knows the
    // drag is doing something rather than wondering whether it registered.
    this._setUpdating(true);

    try {
      const response = await fetch(`${url}?${params.toString()}`, {
        headers: { Accept: "application/json" },
      });
      if (!response.ok) return;

      const data = await response.json();
      // A newer request has already gone out; this answer is stale.
      if (token !== this._token) return;

      const points = (data.years || []).map((year, i) => ({
        date: `${year}-01-01`,
        year,
        balance: Number(data.balances[i]),
        balance_formatted: data.balance_labels?.[i] ?? "",
        balance_label: data.balance_labels?.[i] ?? "",
      }));

      const chart = this._chartController();
      if (chart) {
        chart.render({ points });
      } else {
        // The chart controller isn't connected yet (or the slider moved before
        // Stimulus wired everything up). Log it so a silent failure doesn't read
        // as "the slider does nothing".
        console.warn("[compound-calculator] wealth-projection-chart controller not found on the chart target");
      }

      if (this.hasOutcomeTarget) {
        this.outcomeTarget.textContent = data.final_balance_label ?? "";
      }
    } catch (error) {
      // A failed re-projection leaves the previous series on screen rather than
      // blanking the chart, which would read as "your net worth is zero".
      console.error("[compound-calculator] projection refresh failed", error);
    } finally {
      this._setUpdating(false);
    }
  }

  _setUpdating(updating) {
    if (this.hasOutcomeTarget) {
      this.outcomeTarget.classList.toggle("opacity-50", updating);
    }
    if (this.hasChartTarget) {
      this.chartTarget.classList.toggle("opacity-60", updating);
    }
  }

  _chartController() {
    const target = this.hasChartTarget ? this.chartTarget : null;
    if (!target) return null;
    return this.application.getControllerForElementAndIdentifier(target, "wealth-projection-chart");
  }

  _formatMoney(value) {
    const amount = Number(value);
    if (!Number.isFinite(amount)) return "";

    try {
      return new Intl.NumberFormat(undefined, {
        style: "currency",
        currency: this.currencyValue || undefined,
        maximumFractionDigits: 0,
      }).format(amount);
    } catch {
      return String(Math.round(amount));
    }
  }
}