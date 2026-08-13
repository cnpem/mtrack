// Client-side "export dashboard images" for the Results screen.
//
// The heatmap / speed-profile PNGs already exist as static files served from
// /uploads/results/<id>/; the full dashboard is captured in the browser with
// html-to-image (WYSIWYG, high-res). The selected images are bundled into a
// single .zip assembled here — no server endpoint, no upload round-trip.
//
// The ZIP is written by hand (STORED / no compression) instead of pulling in a
// zip library: the payloads are already-compressed PNGs, so deflating them
// buys nothing, and this keeps the vendored-JS footprint to just html-to-image.
import * as htmlToImageNs from "../../vendor/html-to-image.js"

// html-to-image ships as UMD; depending on esbuild's CJS interop the API may
// live on the namespace or under `.default`. Resolve `toBlob` from either.
const htmlToImage = htmlToImageNs.toBlob ? htmlToImageNs : htmlToImageNs.default || htmlToImageNs

// --- minimal STORED (uncompressed) ZIP writer -------------------------------

const CRC_TABLE = (() => {
  const t = new Uint32Array(256)
  for (let n = 0; n < 256; n++) {
    let c = n
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
    t[n] = c >>> 0
  }
  return t
})()

function crc32(bytes) {
  let c = 0xffffffff
  for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8)
  return (c ^ 0xffffffff) >>> 0
}

const u16 = n => new Uint8Array([n & 0xff, (n >>> 8) & 0xff])
const u32 = n =>
  new Uint8Array([n & 0xff, (n >>> 8) & 0xff, (n >>> 16) & 0xff, (n >>> 24) & 0xff])

function concat(parts) {
  let len = 0
  for (const p of parts) len += p.length
  const out = new Uint8Array(len)
  let o = 0
  for (const p of parts) {
    out.set(p, o)
    o += p.length
  }
  return out
}

function makeZip(files) {
  const enc = new TextEncoder()
  const chunks = []
  const central = []
  let offset = 0

  for (const f of files) {
    const name = enc.encode(f.name)
    const crc = crc32(f.data)
    const size = f.data.length

    const local = concat([
      u32(0x04034b50), u16(20), u16(0), u16(0), u16(0), u16(0),
      u32(crc), u32(size), u32(size), u16(name.length), u16(0),
      name, f.data,
    ])
    chunks.push(local)

    central.push(concat([
      u32(0x02014b50), u16(20), u16(20), u16(0), u16(0), u16(0), u16(0),
      u32(crc), u32(size), u32(size), u16(name.length),
      u16(0), u16(0), u16(0), u16(0), u32(0), u32(offset), name,
    ]))
    offset += local.length
  }

  const centralStart = offset
  let centralSize = 0
  for (const c of central) {
    chunks.push(c)
    centralSize += c.length
  }

  chunks.push(concat([
    u32(0x06054b50), u16(0), u16(0),
    u16(files.length), u16(files.length),
    u32(centralSize), u32(centralStart), u16(0),
  ]))

  return new Blob(chunks, {type: "application/zip"})
}

// --- helpers ----------------------------------------------------------------

async function fetchBytes(url) {
  const res = await fetch(url)
  if (!res.ok) throw new Error(`fetch ${url} → ${res.status}`)
  return new Uint8Array(await res.arrayBuffer())
}

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

// --- hook -------------------------------------------------------------------

export const DashboardExport = {
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

    const {capture, heatmap, speed} = btn.dataset
    const base = btn.dataset.name || "dashboard"
    const isChecked = name =>
      !!document.querySelector(`input[data-export="${name}"]:checked`)

    const label = btn.querySelector("[data-label]") || btn
    const original = label.textContent
    btn.dataset.busy = "1"
    btn.disabled = true
    label.textContent = "Preparing…"

    try {
      const files = []

      if (isChecked("dashboard") && capture) {
        const el = document.getElementById(capture)
        if (el) {
          const blob = await htmlToImage.toBlob(el, {
            pixelRatio: 2,
            backgroundColor: "#f3f4f6",
          })
          if (blob) {
            files.push({
              name: `${base}-dashboard.png`,
              data: new Uint8Array(await blob.arrayBuffer()),
            })
          }
        }
      }

      if (isChecked("heatmap") && heatmap) {
        files.push({name: `${base}-heatmap.png`, data: await fetchBytes(heatmap)})
      }

      if (isChecked("speed") && speed) {
        files.push({name: `${base}-speed-profile.png`, data: await fetchBytes(speed)})
      }

      if (files.length > 0) downloadBlob(makeZip(files), `${base}.zip`)
    } catch (e) {
      console.error("dashboard export failed", e)
      window.alert("Não foi possível gerar o arquivo de imagens.")
    } finally {
      label.textContent = original
      btn.disabled = false
      delete btn.dataset.busy
    }
  },
}
