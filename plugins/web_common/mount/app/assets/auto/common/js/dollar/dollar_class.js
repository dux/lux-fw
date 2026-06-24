// $ static helpers ported from the apps' Zepto helpers, kept out of the
// _dollar core so the base stays a thin Zepto-shaped shim.
//   $.untilTrue(fn)        poll until truthy
//   $.getStyle(url)        inject a remote stylesheet
//   $.eval(fnOrStr, ...a)  run a function-or-fn-string handler
//   $.parseScripts(html)   execute inline <script>s in an html string

const $ = window.$

// poll until fn returns true, then stop. string form waits for a named global,
// then runs the callback once it appears.
//   $.untilTrue(() => { if (window.md5) { md5(key); return true } })
//   $.untilTrue('EventCalendar', () => init())
$.untilTrue = (...args) => {
  let func, timeout
  if (typeof args[0] == 'string') {
    func = () => { if (window[args[0]]) { args[1](); return true } }
    timeout = args[2]
  } else {
    func = args[0]
    timeout = args[1]
  }
  timeout ||= 200
  if (func() !== true) setTimeout(() => $.untilTrue(func, timeout), timeout)
}

// load a remote stylesheet via <link>; getScript's css counterpart, no-op if already present
$.getStyle = (url) => {
  if (document.querySelector(`link[href="${url}"]`)) return
  const l = document.createElement('link')
  l.rel = 'stylesheet'
  l.href = url
  document.head.appendChild(l)
}

// run a handler that may be a function or a fn-string ("(v)=>save(v)" or "doThing()"),
// forwarding any extra args. used by fez components for ping/onchange/onsubmit props.
$.eval = (fn, ...args) => {
  if (!fn) return
  if (typeof fn == 'string') fn = eval(`(${fn})`)
  if (typeof fn == 'function') return fn(...args)
}

// run inline <script>s in an html string (innerHTML won't execute them) and return
// the html with those scripts neutralized; external (src) scripts are left untouched
$.parseScripts = html => {
  const tmp = document.createElement('div')
  tmp.innerHTML = html
  for (const script of tmp.getElementsByTagName('script')) {
    if (script.getAttribute('src') || !script.textContent) continue
    const type = script.getAttribute('type') || 'javascript'
    if (type.indexOf('javascript') > -1) {
      try {
        new Function(script.textContent)()
        script.textContent = '1;'
      } catch (e) {
        console.error(e)
        alert(`JS error: ${e.message}`)
      }
    }
  }
  return tmp.innerHTML
}
