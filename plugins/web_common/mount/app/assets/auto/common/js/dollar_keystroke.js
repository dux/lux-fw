// keyboard shortcuts driven by data-key attributes, plus a Ctrl/Cmd overlay
// that reveals which keys are available on the current page.
//   <button data-key="Escape" onclick="...">   click when Escape is pressed
//   <input type="submit" data-key="ctrl+s">     triggered on Cmd/Ctrl+S
//   $.onKeyDown('ctrl+k', e => ...)             register a single combo
// holding Ctrl/Cmd dims every [data-key] element and labels it with its key.

const $ = window.$

// key event -> normalized code, e.g. 'ctrl+s', 'Escape', '`'
const keyCode = e => ((e.metaKey || e.ctrlKey) && `ctrl+${e.key}`) || e.key

// register a handler for one specific combo
$.onKeyDown = (key, func) => {
  $(document).on('keydown', e => { if (keyCode(e) == key) func(e) })
}

// last match wins so a dialog form appended to <body> takes priority over a
// form higher up the page
const keyTarget = code => {
  const all = document.querySelectorAll(`*[data-key='${code}']`)
  return all[all.length - 1]
}

// global dispatch: form save, escape-to-blur, and data-key targets
$(document).on('keydown', e => {
  const code = keyCode(e)

  // Cmd/Ctrl+S fires even while typing; submit button opts in with data-key="ctrl+s"
  if (code == 'ctrl+s') {
    const target = keyTarget(code)
    if (target) { e.preventDefault(); target.click() }
    return
  }

  if (code == 'Escape' && e.target.nodeName == 'INPUT') $(e.target).blur()

  // plain-key shortcuts must not hijack typing, so only fire outside a form/input
  if (!e.target.closest('form') && e.target.nodeName != 'INPUT') {
    if (code == '`' && window.Dialog && window.Dialog.isOpen()) {
      e.preventDefault()
      Dialog.refresh()
    }

    // <button data-key="Escape">, <input type="submit" data-key="ctrl+s">
    const target = keyTarget(code)
    if (target) {
      e.preventDefault()
      if (target.nodeName == 'INPUT') $(target).focus()
      else target.click()
    }
  }
})

// --- Ctrl/Cmd overlay: reveal available data-key targets --------------------

let overlayShown = false
let metaPressed = false

const showOverlay = () => {
  if (overlayShown) return
  overlayShown = true

  const overlay = $('<div id="keystroke-overlay"></div>').css({
    position: 'fixed',
    top: '0px',
    left: '0px',
    width: '100%',
    height: '100%',
    pointerEvents: 'none',
    zIndex: 99999
  })

  $('[data-key]').each(function () {
    const element = $(this)
    const rect = this.getBoundingClientRect()
    if (!(rect.width > 0 && rect.height > 0)) return

    element.css('opacity', '0.5')

    const label = $('<div></div>').css({
      position: 'fixed',
      top: `${rect.top + rect.height / 2}px`,
      left: `${rect.left + rect.width / 2}px`,
      background: 'white',
      padding: '1px 9px',
      border: '1px solid #333',
      borderRadius: '3px',
      fontSize: '16px',
      fontWeight: 'bold',
      color: '#333',
      transform: 'translate(-50%, -50%)',
      boxShadow: '0 2px 4px rgba(0,0,0,0.2)'
    })

    label.text(element.attr('data-key'))
    overlay.append(label)
  })

  $('body').append(overlay)
}

const hideOverlay = () => {
  if (!overlayShown) return
  overlayShown = false
  $('#keystroke-overlay').remove()
  $('[data-key]').css('opacity', '')
}

$(document).ready(() => {
  $(document).on('keydown', e => {
    if (e.ctrlKey || e.metaKey) { metaPressed = true; showOverlay() }
  })

  $(document).on('keyup', e => {
    if (!e.ctrlKey && !e.metaKey) { metaPressed = false; hideOverlay() }
  })

  // focus loss drops the overlay
  $(window).on('blur', () => { metaPressed = false; hideOverlay() })
})

// safety net for a missed keyup (e.g. tab switch while holding the key)
setInterval(() => { if (!metaPressed) hideOverlay() }, 500)
