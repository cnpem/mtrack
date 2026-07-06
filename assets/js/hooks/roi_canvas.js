// RoiCanvas — draws the first video frame and lets the user sketch geometry on
// top of it: the valid region (box), a scale reference (2-point segment), and
// ROIs (4-point polygon or circle). The LiveView is the source of truth: this
// hook only captures input and pushes finished shapes via `shape_drawn`, then
// re-draws whatever the server sends back in `data-shapes`.
//
// Element contract:
//   data-frame  — PNG url of the frame
//   data-mode   — "valid_region" | "scale" | "roi_polygon" | "roi_circle"
//   data-shapes — JSON of committed shapes (native px) to overlay
// Children: <img data-role="frame">, <canvas data-role="overlay">
//
// All coordinates pushed to the server are in the video's NATIVE pixel space
// (the PNG is saved at native resolution), converted from on-screen pixels via
// the image's naturalWidth/clientWidth ratio.

const ACCENT = "#CC5500"

export const RoiCanvas = {
  mounted() {
    this.img = this.el.querySelector('[data-role="frame"]')
    this.canvas = this.el.querySelector('[data-role="overlay"]')
    this.ctx = this.canvas.getContext("2d")
    this.pending = []      // in-progress points, in display px
    this.dragging = null   // {start} for box/circle drag, in display px

    this.onDown = (e) => this.handleDown(e)
    this.onMove = (e) => this.handleMove(e)
    this.onUp = (e) => this.handleUp(e)
    this.canvas.addEventListener("pointerdown", this.onDown)
    this.canvas.addEventListener("pointermove", this.onMove)
    window.addEventListener("pointerup", this.onUp)

    this.onResize = () => this.resize()
    window.addEventListener("resize", this.onResize)

    if (this.img.complete && this.img.naturalWidth > 0) {
      this.resize()
    } else {
      this.img.addEventListener("load", () => this.resize(), { once: true })
    }
  },

  updated() {
    // data-frame / data-mode / data-shapes may have changed on the server
    // (e.g. the active video switched, so the <img> src changed too).
    this.pending = []
    this.dragging = null
    if (this.img.complete && this.img.naturalWidth > 0) {
      this.resize()
    } else {
      this.img.addEventListener("load", () => this.resize(), { once: true })
    }
  },

  destroyed() {
    window.removeEventListener("pointerup", this.onUp)
    window.removeEventListener("resize", this.onResize)
  },

  mode() {
    return this.el.dataset.mode
  },

  shapes() {
    try {
      return JSON.parse(this.el.dataset.shapes || "{}")
    } catch (_e) {
      return {}
    }
  },

  // Ratio of native px per one on-screen px (uniform for width/height).
  nativeScale() {
    const rect = this.img.getBoundingClientRect()
    return this.img.naturalWidth / rect.width
  },

  dispPoint(e) {
    const rect = this.canvas.getBoundingClientRect()
    return { x: e.clientX - rect.left, y: e.clientY - rect.top }
  },

  toNative(p) {
    const s = this.nativeScale()
    return { x: Math.round(p.x * s), y: Math.round(p.y * s) }
  },

  resize() {
    const rect = this.img.getBoundingClientRect()
    this.canvas.width = rect.width
    this.canvas.height = rect.height
    this.redraw()
  },

  // --- input handling ---

  handleDown(e) {
    const mode = this.mode()
    const p = this.dispPoint(e)

    if (mode === "valid_region" || mode === "roi_circle") {
      this.dragging = { start: p, current: p }
    } else if (mode === "scale" || mode === "roi_polygon") {
      this.pending.push(p)
      const target = mode === "scale" ? 2 : 4
      if (this.pending.length >= target) {
        this.commitPending(mode)
      }
    }
    this.redraw()
  },

  handleMove(e) {
    if (!this.dragging) return
    this.dragging.current = this.dispPoint(e)
    this.redraw()
  },

  handleUp(e) {
    if (!this.dragging) return
    const mode = this.mode()
    const a = this.dragging.start
    const b = this.dispPoint(e)
    this.dragging = null

    if (mode === "valid_region") {
      const x = Math.min(a.x, b.x)
      const y = Math.min(a.y, b.y)
      const w = Math.abs(b.x - a.x)
      const h = Math.abs(b.y - a.y)
      if (w > 3 && h > 3) {
        const o = this.toNative({ x, y })
        const s = this.nativeScale()
        this.pushEvent("shape_drawn", {
          kind: "valid_region",
          x: o.x,
          y: o.y,
          w: Math.round(w * s),
          h: Math.round(h * s),
        })
      }
    } else if (mode === "roi_circle") {
      const c = this.toNative(a)
      const r = Math.round(Math.hypot(b.x - a.x, b.y - a.y) * this.nativeScale())
      if (r > 2) {
        this.pushEvent("shape_drawn", { kind: "roi_circle", cx: c.x, cy: c.y, r })
      }
    }
    this.redraw()
  },

  commitPending(mode) {
    const pts = this.pending.map((p) => this.toNative(p))
    this.pending = []

    if (mode === "scale") {
      this.pushEvent("shape_drawn", {
        kind: "scale",
        x1: pts[0].x,
        y1: pts[0].y,
        x2: pts[1].x,
        y2: pts[1].y,
      })
    } else if (mode === "roi_polygon") {
      this.pushEvent("shape_drawn", {
        kind: "roi_polygon",
        points: pts.flatMap((p) => [p.x, p.y]),
      })
    }
  },

  // --- drawing ---

  redraw() {
    const ctx = this.ctx
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height)
    this.drawCommitted()
    this.drawPending()
  },

  // native px -> display px
  fromNative(x, y) {
    const s = this.nativeScale() || 1
    return { x: x / s, y: y / s }
  },

  drawCommitted() {
    const ctx = this.ctx
    const shapes = this.shapes()

    if (shapes.valid_region) {
      const { x, y, w, h } = shapes.valid_region
      const o = this.fromNative(x, y)
      const s = this.nativeScale() || 1
      ctx.strokeStyle = "#2563eb"
      ctx.lineWidth = 1.5
      ctx.setLineDash([6, 4])
      ctx.strokeRect(o.x, o.y, w / s, h / s)
      ctx.setLineDash([])
    }

    if (shapes.scale) {
      const a = this.fromNative(shapes.scale.x1, shapes.scale.y1)
      const b = this.fromNative(shapes.scale.x2, shapes.scale.y2)
      ctx.strokeStyle = "#059669"
      ctx.lineWidth = 2
      ctx.beginPath()
      ctx.moveTo(a.x, a.y)
      ctx.lineTo(b.x, b.y)
      ctx.stroke()
      this.dot(a, "#059669")
      this.dot(b, "#059669")
    }

    for (const roi of shapes.rois || []) {
      if (roi.shape === "circle") {
        const c = this.fromNative(roi.cx, roi.cy)
        const r = roi.r / (this.nativeScale() || 1)
        ctx.strokeStyle = ACCENT
        ctx.lineWidth = 2
        ctx.beginPath()
        ctx.arc(c.x, c.y, r, 0, Math.PI * 2)
        ctx.stroke()
      } else if (roi.shape === "polygon") {
        const pts = []
        for (let i = 0; i < roi.points.length; i += 2) {
          pts.push(this.fromNative(roi.points[i], roi.points[i + 1]))
        }
        this.strokePolygon(pts, ACCENT, true)
      }
    }
  },

  drawPending() {
    const ctx = this.ctx
    const mode = this.mode()

    for (const p of this.pending) this.dot(p, ACCENT)
    if (this.pending.length > 1) {
      this.strokePolygon(this.pending, ACCENT, false)
    }

    if (this.dragging) {
      const a = this.dragging.start
      const b = this.dragging.current
      ctx.strokeStyle = mode === "valid_region" ? "#2563eb" : ACCENT
      ctx.lineWidth = 1.5
      if (mode === "valid_region") {
        ctx.setLineDash([6, 4])
        ctx.strokeRect(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(b.x - a.x), Math.abs(b.y - a.y))
        ctx.setLineDash([])
      } else {
        ctx.beginPath()
        ctx.arc(a.x, a.y, Math.hypot(b.x - a.x, b.y - a.y), 0, Math.PI * 2)
        ctx.stroke()
      }
    }
  },

  strokePolygon(pts, color, close) {
    if (pts.length < 2) return
    const ctx = this.ctx
    ctx.strokeStyle = color
    ctx.lineWidth = 2
    ctx.beginPath()
    ctx.moveTo(pts[0].x, pts[0].y)
    for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i].x, pts[i].y)
    if (close) ctx.closePath()
    ctx.stroke()
  },

  dot(p, color) {
    const ctx = this.ctx
    ctx.fillStyle = color
    ctx.beginPath()
    ctx.arc(p.x, p.y, 3.5, 0, Math.PI * 2)
    ctx.fill()
  },
}
