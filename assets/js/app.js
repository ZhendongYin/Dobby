// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/dobby"
import topbar from "../vendor/topbar"
import {ScratchCard} from "./scratch_card"
import {CampaignChart} from "./campaign_chart"
import {EmailEditor} from "./email_editor"

// Import jQuery if needed for other components
import jQuery from "jquery"
window.$ = window.jQuery = jQuery

const DownloadCSV = {
  mounted() {
    this.handleEvent("download_csv", ({content, filename, content_type}) => {
      // Add UTF-8 BOM (Byte Order Mark) for proper Chinese character display in Excel
      // UTF-8 BOM is \uFEFF (U+FEFF)
      // Check if BOM already exists to avoid duplication
      const bom = "\uFEFF"
      const contentWithBom = content.startsWith(bom) ? content : bom + content
      
      // Create blob with UTF-8 encoding
      const blob = new Blob([contentWithBom], {type: content_type || "text/csv;charset=utf-8;"})
      const url = URL.createObjectURL(blob)
      const link = document.createElement("a")
      link.href = url
      link.download = filename || "export.csv"
      document.body.appendChild(link)
      link.click()
      document.body.removeChild(link)
      URL.revokeObjectURL(url)
    })
  }
}

const CopyToClipboard = {
  mounted() {
    this.originalLabel = this.el.getAttribute("aria-label") || ""
    this.handleClick = event => {
      event.preventDefault()
      event.stopPropagation()
      const text = this.el.dataset.copyText

      if (!text) return

      const write = navigator.clipboard
        ? navigator.clipboard.writeText(text)
        : this.fallbackCopy(text)

      Promise.resolve(write)
        .then(() => this.showCopiedState())
        .catch(() => this.showCopiedState())
    }

    this.el.addEventListener("click", this.handleClick)
  },

  destroyed() {
    this.el.removeEventListener("click", this.handleClick)
    if (this.resetTimer) {
      clearTimeout(this.resetTimer)
    }
    this.hideTooltip()
  },

  fallbackCopy(text) {
    const textarea = document.createElement("textarea")
    textarea.value = text
    textarea.setAttribute("readonly", "")
    textarea.style.position = "absolute"
    textarea.style.left = "-9999px"
    document.body.appendChild(textarea)
    textarea.select()
    document.execCommand("copy")
    document.body.removeChild(textarea)
  },

  showCopiedState() {
    const successLabel = this.el.dataset.copySuccessLabel || "已复制"

    if (successLabel) {
      this.el.setAttribute("aria-label", successLabel)
    }

    this.el.classList.add("copied")

    // Show visual tooltip
    this.showTooltip(successLabel)

    if (this.resetTimer) {
      clearTimeout(this.resetTimer)
    }

    this.resetTimer = setTimeout(() => {
      if (this.originalLabel) {
        this.el.setAttribute("aria-label", this.originalLabel)
      }
      this.el.classList.remove("copied")
      this.hideTooltip()
    }, 1500)
  },

  showTooltip(text) {
    // Remove existing tooltip if any
    this.hideTooltip()

    // Create tooltip element
    const tooltip = document.createElement("div")
    tooltip.textContent = text
    tooltip.className = "fixed z-50 px-2 py-1 text-xs font-medium text-white bg-slate-900 rounded shadow-lg pointer-events-none transition-opacity opacity-0"
    tooltip.id = `copy-tooltip-${Date.now()}`
    document.body.appendChild(tooltip)

    // Position tooltip above the button (calculate after adding to DOM)
    const rect = this.el.getBoundingClientRect()
    const tooltipWidth = tooltip.offsetWidth
    const tooltipHeight = tooltip.offsetHeight
    tooltip.style.left = `${rect.left + rect.width / 2 - tooltipWidth / 2}px`
    tooltip.style.top = `${rect.top - tooltipHeight - 8}px`

    // Trigger animation
    requestAnimationFrame(() => {
      tooltip.style.opacity = "1"
    })

    this.tooltipElement = tooltip
  },

  hideTooltip() {
    if (this.tooltipElement) {
      this.tooltipElement.style.opacity = "0"
      setTimeout(() => {
        if (this.tooltipElement && this.tooltipElement.parentNode) {
          this.tooltipElement.parentNode.removeChild(this.tooltipElement)
        }
        this.tooltipElement = null
      }, 200)
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ScratchCard, CampaignChart, DownloadCSV, EmailEditor, CopyToClipboard},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

