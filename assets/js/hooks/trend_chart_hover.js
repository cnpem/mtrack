// TrendChartHover — on hover, snaps to the nearest session and shows a
// tooltip listing every series' value at that session (LocomoComponents
// .trend_chart/1). The chart itself is static server-rendered SVG (no
// charting library); this hook only draws a vertical guide line inside the
// SVG and positions an HTML tooltip over it, built from `data-sessions` (a
// JSON blob of `%{x:, entries: [%{label:, color:, point_label:, value:}]}`
// per session index) — the same x positions the server used to place the
// plotted points.
//
// Element contract (the wrapping <div id=... phx-hook="TrendChartHover">):
//   data-width, data-height                — viewBox size
//   data-pad-left/right/top/bottom          — plot-area padding
//   data-unit                               — optional unit suffix
//   data-sessions                           — JSON: [{x, entries: [{label, color, point_label, value}]}]
// Children: <svg> (the chart itself)

export const TrendChartHover = {
  mounted() {
    this.onMove = e => this.handleMove(e)
    this.onLeave = () => this.hide()
    this.el.addEventListener("pointermove", this.onMove)
    this.el.addEventListener("pointerleave", this.onLeave)
    this.build()
  },

  updated() {
    // A data update (metric/subject/experiment changed) re-renders the
    // server-side SVG children; morphdom drops elements it didn't put there,
    // so the guide line we appended into the SVG needs to be rebuilt.
    this.build()
  },

  destroyed() {
    this.el.removeEventListener("pointermove", this.onMove)
    this.el.removeEventListener("pointerleave", this.onLeave)
    if (this.tooltip) this.tooltip.remove()
  },

  build() {
    this.svg = this.el.querySelector("svg")
    this.sessions = JSON.parse(this.el.dataset.sessions || "[]")

    // The guide line and tooltip aren't part of the server-rendered markup
    // (they're appended by this hook), so a LiveView patch (metric/subject
    // change) has morphdom drop them from the DOM — but `this.line`/
    // `this.tooltip` still hold references to those now-detached nodes.
    // Discard and rebuild both from scratch on every mount/update instead of
    // reusing (and silently updating) stale, invisible elements.
    if (this.line) this.line.remove()
    if (this.tooltip) this.tooltip.remove()

    const ns = "http://www.w3.org/2000/svg"
    this.line = document.createElementNS(ns, "line")
    this.line.setAttribute("stroke", "#CC5500")
    this.line.setAttribute("stroke-width", "1")
    this.line.setAttribute("stroke-dasharray", "3,3")
    this.line.style.display = "none"
    this.svg.append(this.line)

    this.tooltip = document.createElement("div")
    this.tooltip.className =
      "pointer-events-none absolute z-10 hidden min-w-[120px] rounded-[8px] border border-[#e7e9ee] bg-white px-2.5 py-2 text-[11px] shadow-[0_2px_8px_rgba(16,24,40,.12)]"
    this.el.append(this.tooltip)
  },

  nearestSession(svgX) {
    if (this.sessions.length === 0) return null

    return this.sessions.reduce((closest, session) =>
      Math.abs(session.x - svgX) < Math.abs(closest.x - svgX) ? session : closest
    )
  },

  handleMove(e) {
    const d = this.el.dataset
    const width = parseFloat(d.width)
    const height = parseFloat(d.height)
    const padLeft = parseFloat(d.padLeft)
    const padRight = parseFloat(d.padRight)
    const padTop = parseFloat(d.padTop)
    const padBottom = parseFloat(d.padBottom)
    const unit = d.unit || ""

    const rect = this.svg.getBoundingClientRect()
    const scale = rect.width / width
    if (!scale) return
    const svgX = (e.clientX - rect.left) / scale
    const svgY = (e.clientY - rect.top) / scale

    if (svgX < padLeft || svgX > width - padRight || svgY < padTop || svgY > height - padBottom) {
      this.hide()
      return
    }

    const session = this.nearestSession(svgX)
    if (!session || session.entries.length === 0) {
      this.hide()
      return
    }

    this.line.setAttribute("x1", session.x)
    this.line.setAttribute("x2", session.x)
    this.line.setAttribute("y1", padTop)
    this.line.setAttribute("y2", height - padBottom)
    this.line.style.display = ""

    this.renderTooltip(session, unit)

    const leftPct = (session.x / width) * 100
    const anchorRight = leftPct > 60
    this.tooltip.style.top = "6px"
    this.tooltip.style.left = `${leftPct}%`
    this.tooltip.style.transform = anchorRight ? "translateX(calc(-100% - 10px))" : "translateX(10px)"
    this.tooltip.classList.remove("hidden")
  },

  renderTooltip(session, unit) {
    this.tooltip.replaceChildren()

    const heading = document.createElement("div")
    heading.className = "font-medium text-[#0f1729]"
    heading.textContent = session.entries[0].point_label
    this.tooltip.append(heading)

    for (const entry of session.entries) {
      const row = document.createElement("div")
      row.className = "mt-1 flex items-center gap-1.5 font-data text-[#344054]"

      const dot = document.createElement("span")
      dot.className = "size-1.5 shrink-0 rounded-full"
      dot.style.background = entry.color

      const text = document.createElement("span")
      text.className = "truncate"
      text.textContent = `${entry.label}: ${entry.value}${unit ? " " + unit : ""}`

      row.append(dot, text)
      this.tooltip.append(row)
    }
  },

  hide() {
    if (this.line) this.line.style.display = "none"
    if (this.tooltip) this.tooltip.classList.add("hidden")
  },
}
