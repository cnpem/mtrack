// Dual-handle analysis-window slider for step 2 of the experiment wizard.
//
// The server is the single source of truth: it renders the container with
// data-duration / data-start / data-end (seconds) and the handles start with
// no position. `mounted()` and `updated()` position the handles from those
// data attributes, so the slider stays in sync with the numeric inputs (which
// go through the server). During a drag the movement is handled entirely
// client-side (no round-trip); only on release does it pushEvent("set_trim"),
// which reloads the start/end preview frame — mirroring the cost profile of
// the reference-frame picker.
//
// Values snap to whole seconds, matching the Python side's 1s granularity.
export const VideoTrimmer = {
  mounted() {
    this.track = this.el.querySelector('[data-role="track"]')
    this.range = this.el.querySelector('[data-role="range"]')
    this.hStart = this.el.querySelector('[data-role="handle-start"]')
    this.hEnd = this.el.querySelector('[data-role="handle-end"]')
    this.labStart = this.el.querySelector('[data-role="label-start"]')
    this.labEnd = this.el.querySelector('[data-role="label-end"]')

    this.readData()
    this.render()
    this.bind(this.hStart, "start")
    this.bind(this.hEnd, "end")
  },

  updated() {
    // Re-sync from the server (numeric input change / clamp) unless a drag is
    // in progress — never fight the pointer.
    if (this.dragging) return
    this.readData()
    this.render()
  },

  readData() {
    this.duration = parseFloat(this.el.dataset.duration) || 0
    this.start = parseFloat(this.el.dataset.start) || 0
    const e = this.el.dataset.end
    this.end = e === "" || e == null ? this.duration : parseFloat(e)
    this.ref = this.el.dataset.ref
  },

  fmt(s) {
    s = Math.max(0, Math.round(s))
    const m = Math.floor(s / 60)
    const sec = s % 60
    return m + ":" + String(sec).padStart(2, "0")
  },

  pct(s) {
    return this.duration > 0 ? (s / this.duration) * 100 : 0
  },

  render() {
    const a = this.pct(this.start)
    const b = this.pct(this.end)
    this.hStart.style.left = a + "%"
    this.hEnd.style.left = b + "%"
    this.range.style.left = a + "%"
    this.range.style.width = Math.max(0, b - a) + "%"
    this.labStart.textContent = this.fmt(this.start)
    this.labEnd.textContent = this.fmt(this.end)
  },

  bind(handle, which) {
    handle.addEventListener("pointerdown", e => {
      e.preventDefault()
      this.dragging = which
      handle.setPointerCapture(e.pointerId)

      const move = ev => this.onMove(ev, which)
      const up = () => {
        handle.removeEventListener("pointermove", move)
        handle.removeEventListener("pointerup", up)
        this.dragging = null
        this.commit()
      }

      handle.addEventListener("pointermove", move)
      handle.addEventListener("pointerup", up)
    })
  },

  onMove(ev, which) {
    const rect = this.track.getBoundingClientRect()
    let ratio = (ev.clientX - rect.left) / rect.width
    ratio = Math.min(1, Math.max(0, ratio))
    const s = Math.round(ratio * this.duration)

    if (which === "start") {
      this.start = Math.max(0, Math.min(s, this.end - 1))
    } else {
      this.end = Math.min(this.duration, Math.max(s, this.start + 1))
    }

    this.render()
  },

  commit() {
    // end == duration means "to the end" — send blank so the server stores nil.
    const endVal = this.end >= this.duration ? "" : String(Math.round(this.end))
    this.pushEvent("set_trim", {
      ref: this.ref,
      start: String(Math.round(this.start)),
      end: endVal
    })
  }
}
