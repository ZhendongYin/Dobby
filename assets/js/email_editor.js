// Email Studio - Rich Text Editor using Quill.js
import Quill from "quill"
import "quill/dist/quill.snow.css"

export const EmailEditor = {
  mounted() {
    console.log("EmailEditor: mounted", this.el)
    // Delay initialization to ensure DOM is fully ready
    setTimeout(() => {
      this.initEditor()
    }, 200)
  },

  initEditor() {
    // Get elements
    const container = this.el
    const editorEl = container.querySelector("#email-editor")
    const htmlInput = container.querySelector("#html-content-input")
    const textInput = container.querySelector("#text-content-input")

    console.log("EmailEditor: initEditor", {
      container: !!container,
      editorEl: !!editorEl,
      htmlInput: !!htmlInput,
      textInput: !!textInput
    })

    if (!editorEl) {
      console.error("EmailEditor: #email-editor not found")
      return
    }

    if (!htmlInput) {
      console.error("EmailEditor: #html-content-input not found")
      return
    }

    // Check Quill availability
    if (typeof Quill === "undefined") {
      console.error("EmailEditor: Quill is not loaded")
      return
    }

    // Ensure editor element is visible and has proper dimensions
    editorEl.style.display = "block"
    editorEl.style.minHeight = "300px"
    editorEl.style.width = "100%"
    editorEl.style.visibility = "visible"
    editorEl.style.opacity = "1"

    // Clear any existing content
    editorEl.innerHTML = ""

    // Initialize Quill
    try {
      this.quill = new Quill(editorEl, {
        theme: "snow",
        modules: {
          toolbar: [
            [{ header: [1, 2, 3, false] }],
            ["bold", "italic", "underline", "strike"],
            [{ color: [] }, { background: [] }],
            [{ list: "ordered" }, { list: "bullet" }],
            [{ align: [] }],
            ["link", "image"],
            ["clean"]
          ]
        },
        placeholder: "開始撰寫郵件內容..."
      })

      console.log("EmailEditor: Quill initialized", this.quill)

      // Quill is ready, keep textarea as graceful fallback only.
      htmlInput.style.display = "none"

      // Wait a bit for Quill to create DOM elements
      setTimeout(() => {
        // Ensure Quill elements are visible
        const qlContainer = editorEl.querySelector(".ql-container")
        const qlEditor = editorEl.querySelector(".ql-editor")
        const qlToolbar = editorEl.querySelector(".ql-toolbar")

        console.log("EmailEditor: Quill elements", {
          container: !!qlContainer,
          editor: !!qlEditor,
          toolbar: !!qlToolbar
        })

        if (qlContainer) {
          qlContainer.style.display = "block"
          qlContainer.style.visibility = "visible"
          qlContainer.style.opacity = "1"
          qlContainer.style.height = "auto"
          qlContainer.style.minHeight = "300px"
        }

        if (qlEditor) {
          qlEditor.style.display = "block"
          qlEditor.style.visibility = "visible"
          qlEditor.style.opacity = "1"
          qlEditor.style.minHeight = "300px"
          qlEditor.style.height = "auto"
          qlEditor.style.padding = "15px"
          qlEditor.style.background = "white"
          // Ensure it's editable
          qlEditor.setAttribute("contenteditable", "true")
          qlEditor.removeAttribute("disabled")
          qlEditor.removeAttribute("readonly")
        }

        if (qlToolbar) {
          qlToolbar.style.display = "block"
          qlToolbar.style.visibility = "visible"
          qlToolbar.style.opacity = "1"
          qlToolbar.style.background = "white"
        }

        // Force a reflow to ensure styles are applied
        if (qlEditor) {
          qlEditor.offsetHeight
        }
      }, 100)

      // Load initial content after ensuring editor is visible
      setTimeout(() => {
        const initialContent = htmlInput.value || container.dataset.initialContent || ""
        if (initialContent && initialContent.trim() !== "") {
          this.quill.root.innerHTML = initialContent
        }
        
        // Double-check editor is visible and has content
        const qlEditor = editorEl.querySelector(".ql-editor")
        if (qlEditor) {
          // Force visibility one more time
          qlEditor.style.display = "block"
          qlEditor.style.visibility = "visible"
          qlEditor.style.opacity = "1"
          qlEditor.style.minHeight = "300px"
          qlEditor.style.height = "auto"
          
          // If editor is empty, add a paragraph to ensure it's visible
          if (qlEditor.innerHTML.trim() === "" || qlEditor.innerHTML === "<p><br></p>") {
            qlEditor.innerHTML = "<p><br></p>"
          }
          
          console.log("EmailEditor: Editor content", {
            innerHTML: qlEditor.innerHTML.substring(0, 100),
            height: qlEditor.offsetHeight,
            computedHeight: window.getComputedStyle(qlEditor).height
          })
        }
      }, 200)

      // Sync to hidden inputs on content change
      this.quill.on("text-change", () => {
        const html = this.quill.root.innerHTML
        const text = this.quill.getText()

        // Update hidden inputs
        htmlInput.value = html
        if (textInput) {
          textInput.value = text
        }

        // Do not dispatch input on the form: phx-change would re-render the LiveView
        // on every keystroke, run hook updated(), and break Quill if HTML strings differ
        // after Quill normalizes content. Hidden fields still hold the latest value for submit.

        // Push to LiveView (debounced)
        if (this.updateTimeout) {
          clearTimeout(this.updateTimeout)
        }
        this.updateTimeout = setTimeout(() => {
          this.pushEvent("editor-update", { html_content: html })
        }, 500)
      })

      // Handle variable insertion
      this.handleEvent("insert-variable", ({ variable }) => {
        if (!this.quill) return

        const range = this.quill.getSelection(true) || { index: this.quill.getLength() - 1 }
        const variableText = `{{${variable}}}`
        
        this.quill.insertText(range.index, variableText, "user")
        this.quill.setSelection(range.index + variableText.length, "user")
        this.quill.focus()

        const html = this.quill.root.innerHTML
        htmlInput.value = html
        if (textInput) {
          textInput.value = this.quill.getText()
        }
        this.pushEvent("editor-update", { html_content: html })
      })

      // Store references
      this.htmlInput = htmlInput
      this.textInput = textInput

      // Focus editor after a short delay
      setTimeout(() => {
        if (this.quill) {
          this.quill.focus()
          console.log("EmailEditor: Focused editor")
        }
      }, 300)

    } catch (error) {
      console.error("EmailEditor: Failed to initialize", error)
      console.error(error.stack)
      // Keep textarea visible when Quill fails so HTML remains editable.
      if (htmlInput) {
        htmlInput.style.display = "block"
      }
    }
  },

  updated() {
    // Container uses phx-update="ignore"; content is owned by Quill.
    // Never assign quill.root.innerHTML here: Quill normalizes HTML, so it would almost
    // always differ from the hidden input's string and corrupt the editor model.
  },

  destroyed() {
    if (this.updateTimeout) {
      clearTimeout(this.updateTimeout)
    }
  }
}
