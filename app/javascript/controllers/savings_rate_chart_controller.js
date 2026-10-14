import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";
import {
  createChartTooltip,
  CHART_TOOLTIP_CONTEXT_CLASSES,
  CHART_TOOLTIP_VALUE_CLASSES,
} from "utils/chart_tooltip";

// Monthly savings rate over a trailing window, drawn as two series:
//
//   solid   -- cash savings only (income less everything that left the accounts)
//   dashed  -- the same month counting invested money as kept
//
// The dashed line is never below the solid one: investing is a way of saving, so
// the gap between them is exactly the month's investing. Both share one y-axis
// in percent, because the whole question the chart answers is "how far apart are
// these two" -- separate axes would make any gap meaningless.
//
// Data shape:
//   { currency, description, series: [{ date, percent, total_percent,
//                                        cash_label, total_label }] }
//
// Every label is pre-formatted server-side so the chart never formats currency
// or percentages itself and stays consistent with the tiles above it.
//
// A month with no income has no rate at all. `percent` and `total_percent` are
// nil rather than 0 there, and the gap in the line is deliberate: plotting a
// zero would read as "saved nothing this month" when the truth is "cannot
// compute", which is the one thing a savings chart must not imply.

const parseLocalDate = (s) => {
  if (!s) return null;
  const [y, m, d] = s.split("-").map(Number);
  return new Date(y, m - 1, d);
};

// Coerces a rate to a finite number, or null when there is nothing to plot.
//
// Number() rather than trusting the payload: a decimal arrives from the server as
// a JSON *string*, and d3.max over strings compares lexicographically, so
// "9" beats "38" and the scale maths goes NaN -- which blanks the entire plot
// while the legend still draws. Normalising here means a stray string can cost
// one point, never the chart.
const toRate = (value) => {
  if (value == null || value === "") return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
};

const fmtPct = (v) => (v == null ? "—" : `${v.toFixed(1)}%`);

export default class extends Controller {
  static values = {
    data: Object,
    ariaLabel: { type: String, default: "Savings rate over time" },
    monthFormat: { type: String, default: "%b" },
    solidLabel: { type: String, default: "Saved" },
    dashedLabel: { type: String, default: "Saved incl. investments" },
  };

  _id() {
    if (!this.__chartId) this.__chartId = Math.random().toString(36).slice(2, 9);
    return this.__chartId;
  }

  connect() {
    this._observer = new ResizeObserver(() => this._draw());
    this._observer.observe(this.element);

    this._themeObserver = new MutationObserver((mutations) => {
      if (mutations.some((m) => m.attributeName === "data-theme")) this._draw();
    });
    this._themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });

    this._draw();
  }

  disconnect() {
    this._observer?.disconnect();
    this._themeObserver?.disconnect();
  }

  _draw() {
    const root = this.element;
    root.innerHTML = "";

    const data = this.dataValue || {};
    const series = (data.series || [])
      .map((row) => ({ ...row, percent: toRate(row.percent), total_percent: toRate(row.total_percent) }))
      .map((row) => ({ ...row, parsedDate: parseLocalDate(row.date) }))
      .filter((row) => row.parsedDate);
    // Two months minimum: a single point cannot describe a rate over time, and
    // d3's line generator silently drops a single-point path.
    if (series.length < 2) return;

    const width = root.clientWidth || 640;
    const height = root.clientHeight || 220;
    if (width <= 0 || height <= 0) return;

    const isDark = document.documentElement.getAttribute("data-theme") === "dark";
    const textPrimary = isDark ? "#ffffff" : "#171717";
    const textSecondary = isDark ? "#cfcfcf" : "#737373";
    const borderSubdued = isDark ? "rgba(255,255,255,0.15)" : "rgba(0,0,0,0.10)";
    const containerBg = isDark ? "#0a0a0a" : "#ffffff";

    const yAxisVisible = width - 16 - 24 >= 300;
    const margin = { top: 20, right: 20, bottom: 28, left: yAxisVisible ? 44 : 12 };
    const innerWidth = width - margin.left - margin.right;
    const innerHeight = height - margin.top - margin.bottom;

    const x = d3
      .scalePoint()
      .domain(series.map((row) => row.date))
      .range([margin.left, margin.left + innerWidth])
      .padding(0.5);

    // Domain spans both series together. Zero is always inside it: a savings
    // rate chart with no zero line can't tell saving from overspending, and
    // every month's sign is the first thing a reader looks for.
    const values = series.flatMap((row) => [row.percent, row.total_percent]).filter((v) => v != null);
    if (!values.length) return;

    const rawMax = d3.max(values);
    const rawMin = d3.min(values);
    const span = Math.max(rawMax - rawMin, Math.abs(rawMax) * 0.15, 5);
    const yMax = rawMax + span * 0.1;
    const yMin = Math.min(0, rawMin - span * 0.1);

    const y = d3.scaleLinear().domain([yMin, yMax]).range([margin.top + innerHeight, margin.top]);

    const svg = d3
      .select(root)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .attr("viewBox", `0 0 ${width} ${height}`)
      .attr("role", "img")
      .attr("aria-label", this.ariaLabelValue);

    const descId = `savings-desc-${this._id()}`;
    svg.append("desc").attr("id", descId).text(data.description || "");
    svg.attr("aria-describedby", descId);

    // Structural guarantee that a value outside the domain stops at the plot
    // edge rather than painting over the axis labels.
    const clipId = `savings-clip-${this._id()}`;
    svg
      .append("defs")
      .append("clipPath")
      .attr("id", clipId)
      .append("rect")
      .attr("x", margin.left - 2)
      .attr("y", margin.top)
      .attr("width", innerWidth + 4)
      .attr("height", innerHeight);
    const plotClip = `url(#${clipId})`;

    if (yAxisVisible) {
      y.ticks(4).forEach((tickValue) => {
        svg
          .append("line")
          .attr("x1", margin.left)
          .attr("x2", margin.left + innerWidth)
          .attr("y1", y(tickValue))
          .attr("y2", y(tickValue))
          .attr("stroke", tickValue === 0 ? textSecondary : borderSubdued)
          .attr("stroke-width", 1)
          .attr("stroke-dasharray", tickValue === 0 ? "3 3" : null);
        svg
          .append("text")
          .attr("x", margin.left - 6)
          .attr("y", y(tickValue) + 3)
          .attr("text-anchor", "end")
          .attr("font-size", 11)
          .attr("fill", textSecondary)
          .text(`${tickValue}%`);
      });
    }

    const build = d3
      .line()
      .x((d) => x(d.date))
      .y((d) => y(d.value))
      .defined((d) => d.value != null)
      .curve(d3.curveMonotoneX);

    // Dashed series first so the solid one sits on top when they coincide --
    // which they do for every month with no investing, and a solid line drawn
    // under a dashed one would read as a single moving series.
    svg
      .append("path")
      .datum(series.map((row) => ({ date: row.date, value: row.total_percent })))
      .attr("fill", "none")
      .attr("stroke", "var(--color-info)")
      .attr("stroke-width", 2)
      .attr("stroke-dasharray", "5 4")
      .attr("stroke-linecap", "round")
      .attr("clip-path", plotClip)
      .attr("d", build);

    svg
      .append("path")
      .datum(series.map((row) => ({ date: row.date, value: row.percent })))
      .attr("fill", "none")
      .attr("stroke", "var(--color-success)")
      .attr("stroke-width", 2)
      .attr("stroke-linejoin", "round")
      .attr("stroke-linecap", "round")
      .attr("clip-path", plotClip)
      .attr("d", build);

    const tickStep = Math.ceil(series.length / (innerWidth >= 420 ? 6 : 3));
    const tickFmt = d3.timeParse(this.monthFormatValue);
    const tickGroup = svg.append("g");
    tickGroup
      .selectAll("text")
      .data(series.filter((row, i) => i % tickStep === 0))
      .enter()
      .append("text")
      .attr("x", (d) => x(d.date))
      .attr("y", height - 8)
      .attr("text-anchor", "middle")
      .attr("font-size", 11)
      .attr("fill", textSecondary)
      .text((d) => (tickFmt ? tickFmt(d.parsedDate) : d.date));

    if (getComputedStyle(root).position === "static") root.style.position = "relative";
    const tooltip = createChartTooltip(root);
    tooltip.style.transition = "left 80ms ease-out, top 80ms ease-out";

    const tipContext = document.createElement("div");
    tipContext.className = CHART_TOOLTIP_CONTEXT_CLASSES;
    const tipSolid = document.createElement("div");
    tipSolid.className = CHART_TOOLTIP_VALUE_CLASSES;
    const tipDashed = document.createElement("div");
    tipDashed.className = CHART_TOOLTIP_VALUE_CLASSES;
    tooltip.append(tipContext, tipSolid, tipDashed);

    const crosshair = svg
      .append("line")
      .attr("y1", margin.top)
      .attr("y2", margin.top + innerHeight)
      .attr("stroke", textSecondary)
      .attr("stroke-width", 1)
      .attr("stroke-dasharray", "2 2")
      .attr("pointer-events", "none")
      .style("display", "none");

    const hoverDots = [
      svg
        .append("circle")
        .attr("r", 3.5)
        .attr("fill", "var(--color-success)")
        .attr("stroke", containerBg)
        .attr("stroke-width", 2)
        .attr("pointer-events", "none")
        .attr("clip-path", plotClip)
        .style("display", "none"),
      svg
        .append("circle")
        .attr("r", 3.5)
        .attr("fill", "var(--color-info)")
        .attr("stroke", containerBg)
        .attr("stroke-width", 2)
        .attr("pointer-events", "none")
        .attr("clip-path", plotClip)
        .style("display", "none"),
    ];

    const onMove = (event) => {
      const [px] = d3.pointer(event);
      const nearest = series.reduce((best, row) => {
        const distance = Math.abs(x(row.date) - px);
        return !best || distance < best.distance ? { row, distance } : best;
      }, null);
      if (!nearest) return;

      const row = nearest.row;
      const cx = x(row.date);
      crosshair.attr("x1", cx).attr("x2", cx).style("display", null);

      [row.percent, row.total_percent].forEach((value, i) => {
        if (value == null) return hoverDots[i].style("display", "none");
        hoverDots[i].attr("cx", cx).attr("cy", y(value)).style("display", null);
      });

      tipContext.textContent = row.tooltip_date || row.date;
      tipSolid.textContent = `${this.solidLabelValue}: ${fmtPct(row.percent)}${
        row.cash_label ? ` (${row.cash_label})` : ""
      }`;
      tipDashed.textContent = `${this.dashedLabelValue}: ${fmtPct(row.total_percent)}${
        row.total_label ? ` (${row.total_label})` : ""
      }`;

      tooltip.style.display = "block";
      const half = tooltip.offsetWidth / 2;
      tooltip.style.left = `${Math.max(half, Math.min(cx, root.clientWidth - half))}px`;
      tooltip.style.top = `${margin.top}px`;
    };

    const onLeave = () => {
      crosshair.style("display", "none");
      hoverDots.forEach((dot) => dot.style("display", "none"));
      tooltip.style.display = "none";
    };

    svg
      .append("rect")
      .attr("x", margin.left)
      .attr("y", margin.top)
      .attr("width", innerWidth)
      .attr("height", innerHeight)
      .attr("fill", "transparent")
      .attr("pointer-events", "all")
      .on("pointermove", onMove)
      .on("pointerleave", onLeave);

    // Legend, drawn in the SVG so it scales with the chart instead of drifting
    // when the container resizes.
    if (innerWidth >= 260) {
      const legend = [
        { label: this.solidLabelValue, color: "var(--color-success)", dashed: false },
        { label: this.dashedLabelValue, color: "var(--color-info)", dashed: true },
      ];
      let cursor = margin.left;
      legend.forEach((item) => {
        svg
          .append("line")
          .attr("x1", cursor)
          .attr("x2", cursor + 16)
          .attr("y1", 10)
          .attr("y2", 10)
          .attr("stroke", item.color)
          .attr("stroke-width", 2)
          .attr("stroke-dasharray", item.dashed ? "5 4" : null);
        const text = svg
          .append("text")
          .attr("x", cursor + 21)
          .attr("y", 14)
          .attr("font-size", 11)
          .attr("fill", textSecondary)
          .text(item.label);
        cursor += 21 + item.label.length * 5.8 + 18;
        return text;
      });
    }
  }
}