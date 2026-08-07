// Client-side "export chart as PNG" for the Analyses screen.
//
// The Analyses charts are hand-rolled inline SVG (no server-side image), so we
// capture the chart card in the browser with html-to-image (WYSIWYG, high-res)
// and trigger a direct PNG download — no server endpoint, no upload round-trip.
// A single chart is one PNG, so (unlike the Results dashboard export) there's no
// .zip to assemble here.
import * as htmlToImageNs from "../../vendor/html-to-image.js"

// html-to-image ships as UMD; depending on esbuild's CJS interop the API may
// live on the namespace or under `.default`. Resolve `toBlob` from either.
const htmlToImage = htmlToImageNs.toBlob ? htmlToImageNs : htmlToImageNs.default || htmlToImageNs

function downloadBlob(blob, filename) {
  const url = URL.createObjectURL(blob)
  const a = document.createElement("a")
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

export const ChartExport = {
  mounted() {
    this.handler = () => this.run()
    this.el.addEventListener("click", this.handler)
  },

  destroyed() {
    this.el.removeEventListener("click", this.handler)
  },

  async run() {
    const btn = this.el
    if (btn.dataset.busy === "1") return

    const capture = btn.dataset.capture
    const base = btn.dataset.name || "chart"
    const el = capture && document.getElementById(capture)
    if (!el) return

    const label = btn.querySelector("[data-label]") || btn
    const original = label.textContent
    btn.dataset.busy = "1"
    btn.disabled = true
    label.textContent = "Preparing…"

    try {
      const blob = await htmlToImage.toBlob(el, {
        pixelRatio: 2,
        backgroundColor: "#ffffff",
      })
      if (blob) downloadBlob(blob, `${base}.png`)
    } catch (e) {
      console.error("chart export failed", e)
      window.alert("Não foi possível exportar o gráfico.")
    } finally {
      label.textContent = original
      btn.disabled = false
      delete btn.dataset.busy
    }
  },
}
