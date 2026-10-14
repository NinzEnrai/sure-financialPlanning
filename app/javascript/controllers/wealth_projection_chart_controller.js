import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";
import {
  createChartTooltip,
  CHART_TOOLTIP_CONTEXT_CLASSES,
  CHART_TOOLTIP_VALUE_CLASSES,
} from "utils/chart_tooltip";

// 10-year net worth projection. The whole series is projected (there is no
// realized history to draw alongside it), so this is a single dashed line with
// a marker on the first projected year rather than the saved/projected split
// the goal chart needs.
//
// Data shape: { currency, currency_symbol, points: [{ date, year, balance, balance_formatted }] }
//
// Every label ships pre-formatted from the server, so the chart never does
// currency formatting itself and stays consistent with the rest of the page.

const parseLocalDate = (s) => {
  if (!s) return null;
  const [ y, m, d ] = s.split("-").map(Number);
  return new Date(y, m - 1, d);
};

export default class extends Controller {
  static values = {
    data: Object,
    ariaLabel: { type: String, default: "Net worth projection" },
    yearPrefixValue: { type: String, default: "" },
  };

  connect() {
    this._resize = this._draw.bind(this);
    window.addEventListener("resize", this._resize);
    if (typeof ResizeObserver !== "undefined") {
      this._observer = new ResizeObserver(() => this._draw());
      this._observer.observe(this.element);
    } else {
      this._draw();
    }
    if (typeof MutationObserver !== "undefined") {
      this._themeObserver = new MutationObserver((mutations) => {
        if (mutations.some((m) => m.attributeName === "data-theme")) this._draw();
      });
      this._themeObserver.observe(document.documentElement, {
        attributes: true,
        attributeFilter: ["data-theme"],
      });
    }
    this._onTurboRender = () => {
      if (!this.element.querySelector("svg")) this._draw();
    };
    document.addEventListener("turbo:render", this._onTurboRender);
  }

  disconnect() {
    window.removeEventListener("resize", this._resize);
    this._observer?.disconnect();
    this._themeObserver?.disconnect();
    if (this._onTurboRender) {
      document.removeEventListener("turbo:render", this._onTurboRender);
    }
  }

  // Public: lets the compound calculator re-project without a page reload.
  // Merges the new series into the existing value so the pre-rendered
  // currency/aria strings the server shipped are preserved.
  render(data) {
    this.dataValue = { ...(this.dataValue || {}), ...data };
    this._draw();
  }

  _draw() {
    const root = this.element;
    root.innerHTML = "";

    const data = this.dataValue || {};
    const rawPoints = data.points || [];
    const width = root.clientWidth || 720;
    const height = root.clientHeight || 260;
    if (width <= 0 || height <= 0 || rawPoints.length < 2) return;

    const points = rawPoints
      .map((p) => ({ ...p, parsedDate: parseLocalDate(p.date) }))
      .filter((p) => p.parsedDate);
    if (points.length < 2) return;

    const isDark = document.documentElement.getAttribute("data-theme") === "dark";
    const textPrimary = isDark ? "#ffffff" : "#171717";
    const textSecondary = isDark ? "#cfcfcf" : "#737373";
    const borderSubdued = isDark ? "rgba(255,255,255,0.15)" : "rgba(0,0,0,0.10)";
    const containerBg = isDark ? "#0a0a0a" : "#ffffff";

    const yAxisVisible = width - 16 - 24 >= 320;
    const margin = { top: 24, right: 24, bottom: 28, left: yAxisVisible ? 52 : 16 };
    const innerWidth = width - margin.left - margin.right;
    const innerHeight = height - margin.top - margin.bottom;

    const first = points[0];
    const last = points[points.length - 1];

    const x = d3.scaleTime()
      .domain([first.parsedDate, last.parsedDate])
      .range([margin.left, margin.left + innerWidth]);

    // Pad the domain above the top point so the line's stroke isn't shaved
    // against the plot edge, and below zero is never shown — a projected
    // balance below zero would be a negative net worth, not a negative axis.
    const balances = points.map((p) => p.balance);
    const rawMax = d3.max(balances);
    const rawMin = d3.min(balances);
    const span = Math.max(rawMax - rawMin, Math.abs(rawMax) * 0.1, 1);
    const yMax = rawMax + span * 0.12;
    const yMin = Math.max(0, rawMin - span * 0.12);

    const y = d3.scaleLinear()
      .domain([yMin, yMax])
      .range([margin.top + innerHeight, margin.top]);

    const svg = d3
      .select(root)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .attr("viewBox", `0 0 ${width} ${height}`)
      .attr("role", "img")
      .attr("aria-label", this.ariaLabelValue);

    const descId = `projection-desc-${this._id()}`;
    svg.append("desc").attr("id", descId).text(data.description || "");
    svg.attr("aria-describedby", descId);

    const defs = svg.append("defs");
    const gradient = defs
      .append("linearGradient")
      .attr("id", `projection-fill-${this._id()}`)
      .attr("x1", 0).attr("y1", 0).attr("x2", 0).attr("y2", 1);
    gradient.append("stop").attr("offset", "0%").attr("stop-color", "var(--color-success)").attr("stop-opacity", 0.18);
    gradient.append("stop").attr("offset", "100%").attr("stop-color", "var(--color-success)").attr("stop-opacity", 0);

    // Structural guarantee that a value outside the domain stops at the plot
    // edge rather than painting over the axis labels.
    const clipId = `projection-clip-${this._id()}`;
    defs
      .append("clipPath")
      .attr("id", clipId)
      .append("rect")
      .attr("x", margin.left - 2)
      .attr("y", margin.top)
      .attr("width", innerWidth + 4)
      .attr("height", innerHeight);
    const plotClip = `url(#${clipId})`;

    if (yAxisVisible) {
      y.ticks(3).forEach((tickValue) => {
        svg
          .append("line")
          .attr("x1", margin.left)
          .attr("x2", margin.left + innerWidth)
          .attr("y1", y(tickValue))
          .attr("y2", y(tickValue))
          .attr("stroke", borderSubdued)
          .attr("stroke-width", 1);
        svg
          .append("text")
          .attr("x", margin.left - 6)
          .attr("y", y(tickValue) + 3)
          .attr("text-anchor", "end")
          .attr("font-size", 12)
          .attr("fill", textSecondary)
          .text(this._fmtMoneyShort(tickValue, data));
      });
    }

    const area = d3
      .area()
      .x((d) => x(d.parsedDate))
      .y0(margin.top + innerHeight)
      .y1((d) => y(d.balance))
      .curve(d3.curveMonotoneX);

    const line = d3
      .line()
      .x((d) => x(d.parsedDate))
      .y((d) => y(d.balance))
      .curve(d3.curveMonotoneX);

    svg
      .append("path")
      .datum(points)
      .attr("fill", `url(#projection-fill-${this._id()})`)
      .attr("clip-path", plotClip)
      .attr("d", area);

    // Dashed because every point is projected — there is no realized history on
    // this chart to distinguish it from.
    svg
      .append("path")
      .datum(points)
      .attr("fill", "none")
      .attr("stroke", "var(--color-success)")
      .attr("stroke-width", 2)
      .attr("stroke-linejoin", "round")
      .attr("stroke-linecap", "round")
      .attr("stroke-dasharray", "5 4")
      .attr("clip-path", plotClip)
      .attr("d", line);

    // Mark where the projection starts: today is a fact, not a projection.
    svg
      .append("circle")
      .attr("cx", x(first.parsedDate))
      .attr("cy", y(first.balance))
      .attr("r", 4)
      .attr("fill", textPrimary)
      .attr("stroke", containerBg)
      .attr("stroke-width", 2);

    svg
      .append("circle")
      .attr("cx", x(last.parsedDate))
      .attr("cy", y(last.balance))
      .attr("r", 4)
      .attr("fill", "var(--color-success)")
      .attr("stroke", containerBg)
      .attr("stroke-width", 2);

    // End-of-horizon label, suppressed on narrow widths where it would collide
    // with the y-axis column.
    if (innerWidth >= 320 && last.balance_label) {
      svg
        .append("text")
        .attr("x", x(last.parsedDate) - 8)
        .attr("y", y(last.balance) - 10)
        .attr("text-anchor", "end")
        .attr("font-size", 12)
        .attr("fill", textPrimary)
        .attr("paint-order", "stroke")
        .attr("stroke", containerBg)
        .attr("stroke-width", 4)
        .attr("stroke-linejoin", "round")
        .text(last.balance_label);
    }

    // Year ticks, at most five, de-duplicated so a short axis doesn't repeat.
    const tickCount = Math.min(5, Math.max(2, Math.round(innerWidth / 80)));
    const tickFmt = d3.timeFormat("%Y");
    const tickGroup = svg.append("g");
    tickGroup
      .selectAll("text")
      .data(x.ticks(tickCount))
      .enter()
      .append("text")
      .attr("x", (d) => x(d))
      .attr("y", height - 8)
      .attr("text-anchor", "middle")
      .attr("font-size", 12)
      .attr("fill", textSecondary)
      .text((d) => tickFmt(d));
    const tickNodes = tickGroup.selectAll("text").nodes();
    for (let i = tickNodes.length - 1; i > 0; i--) {
      if (tickNodes[i].textContent === tickNodes[i - 1].textContent) tickNodes[i].remove();
    }

    const crosshair = svg
      .append("line")
      .attr("y1", margin.top)
      .attr("y2", margin.top + innerHeight)
      .attr("stroke", textSecondary)
      .attr("stroke-width", 1)
      .attr("stroke-dasharray", "2 2")
      .attr("pointer-events", "none")
      .style("display", "none");

    const hoverDot = svg
      .append("circle")
      .attr("r", 4)
      .attr("fill", "var(--color-success)")
      .attr("stroke", containerBg)
      .attr("stroke-width", 2)
      .attr("pointer-events", "none")
      .attr("clip-path", plotClip)
      .style("display", "none");

    if (getComputedStyle(root).position === "static") root.style.position = "relative";
    const tooltip = createChartTooltip(root);
    tooltip.style.transition = "left 80ms ease-out, top 80ms ease-out";
    const tooltipDate = document.createElement("div");
    tooltipDate.className = CHART_TOOLTIP_CONTEXT_CLASSES;
    const tooltipValue = document.createElement("div");
    tooltipValue.className = CHART_TOOLTIP_VALUE_CLASSES;
    tooltip.replaceChildren(tooltipDate, tooltipValue);

    const overlay = svg
      .append("rect")
      .attr("x", margin.left)
      .attr("y", margin.top)
      .attr("width", innerWidth)
      .attr("height", innerHeight)
      .attr("fill", "transparent")
      .style("cursor", "crosshair");

    // Snap to the nearest projected year rather than the raw cursor position:
    // this series is one point per year, so anything finer would jitter.
    const bisect = d3.bisector((d) => d.parsedDate).center;

    const showAt = (xPos, yPos) => {
      const xVal = x.invert(xPos);
      const point = points[bisect(points, xVal)];

      const hoverX = x(point.parsedDate);
      crosshair.attr("x1", hoverX).attr("x2", hoverX).style("display", null);
      hoverDot.attr("cx", hoverX).attr("cy", y(point.balance)).style("display", null);

      tooltipDate.textContent = `${this.yearPrefixValue}${point.year}`;
      tooltipValue.textContent = point.balance_formatted || this._fmtMoney(point.balance, data);

      tooltip.style.display = "block";
      const tipRect = tooltip.getBoundingClientRect();
      const left = Math.min(width - tipRect.width - 4, Math.max(4, xPos + 12));
      const top = Math.max(4, yPos - tipRect.height - 8);
      tooltip.style.left = `${left}px`;
      tooltip.style.top = `${top}px`;
    };

    const hide = () => {
      crosshair.style("display", "none");
      hoverDot.style("display", "none");
      tooltip.style.display = "none";
    };

    overlay.on("pointermove", (event) => {
      const [mx, my] = d3.pointer(event);
      showAt(mx, my);
    });
    overlay.on("pointerleave", hide);
  }

  _fmtMoney(amount, data) {
    try {
      return new Intl.NumberFormat(undefined, {
        style: "currency",
        currency: data.currency || "USD",
        maximumFractionDigits: 0,
      }).format(amount);
    } catch {
      const symbol = data.currency_symbol || "$";
      return `${symbol}${Math.round(amount).toLocaleString()}`;
    }
  }

  _fmtMoneyShort(amount, data) {
    const symbol = data.currency_symbol || "$";
    const abs = Math.abs(amount);
    if (abs >= 1_000_000) return `${symbol}${(amount / 1_000_000).toFixed(1).replace(/\.0$/, "")}M`;
    if (abs >= 1_000) return `${symbol}${(amount / 1_000).toFixed(1).replace(/\.0$/, "")}K`;
    return `${symbol}${Math.round(amount).toLocaleString()}`;
  }

  _id() {
    if (!this._cachedId) {
      this._cachedId = Math.random().toString(36).slice(2, 8);
    }
    return this._cachedId;
  }
}