// App-level $/Z helpers ported from the apps' Zepto `_zepto_app.coffee` so the
// dollar shim is the single source and old Zepto can be dropped. Only helpers the
// dollar core (`dollar/_dollar.js`), `dollar/dollar_func.js` and
// `dollar/dollar_class.js` don't already
// provide live here. Bundled after `dollar/*`, so the core $ already exists.

const $ = window.$
const Z = window.Z

// --- debounce: superset of the core (fn, wait) form plus the
//     (uid, delay?, cb) keyed trailing form for legacy app callers ---
const _coreDebounce = $.debounce
const _keyedTimers = {}
$.debounce = (a, b, c) => {
  if (typeof a === 'function') return _coreDebounce(a, b)
  let delay = b, cb = c
  if (typeof delay === 'function') { cb = delay; delay = 10 }
  clearTimeout(_keyedTimers[a])
  _keyedTimers[a] = setTimeout(cb, delay)
}

// --- getScript: superset of the core (url, success) form. Restores the legacy
//     resource loader - object descriptors ({module|js|css|img: url}), arrays of
//     them, and a (src, check, func) form where `check` is a global name polled
//     until defined. Dedups by a src-derived id; a callback fires on the frame
//     after the resource(s) load (after the `check` global appears, if given). ---
const _coreGetScript = $.getScript
// resolves on the node's load event - or immediately when already present or
// when the descriptor names nothing loadable. One promise per id, so a second
// request while the first is still loading waits for the same load.
const _resources = {}
const _loadResource = src => {
  let type
  if (typeof src === 'string') type = src.includes('.css') ? 'css' : 'js'
  else if (src.css) { src = src.css; type = 'css' }
  else if (src.js) { src = src.js; type = 'js' }
  else if (src.img) { src = src.img; type = 'img' }
  else if (src.module) { src = src.module; type = 'module' }
  else return Promise.resolve()

  const id = 'res-' + src.replace(/^https?/, '').replace(/[^\w]+/g, '')
  if (!_resources[id] && document.getElementById(id)) return Promise.resolve()

  return _resources[id] ||= new Promise(resolve => {
    let node
    if (type === 'css') {
      node = Object.assign(document.createElement('link'), { id, rel: 'stylesheet', type: 'text/css', href: src })
      document.head.appendChild(node)
    } else if (type === 'js' || type === 'module') {
      node = Object.assign(document.createElement('script'), { id, async: true, crossOrigin: 'anonymous', src })
      if (type === 'module') node.type = 'module'
      document.head.appendChild(node)
    } else {
      node = Object.assign(document.createElement('img'), { id, src })
    }
    node.onload = node.onerror = resolve
  })
}
$.getScript = (src, check, func) => {
  // plain url, no legacy args -> keep the core promise-returning behavior
  if (typeof src === 'string' && check === undefined && func === undefined) return _coreGetScript(src)

  if (func && typeof check === 'string') { const g = check; check = () => !!window[g] }
  if (!func) { func = check; check = null }

  const loaded = Promise.all((Array.isArray(src) ? src : [src]).map(_loadResource))

  // fire on the frame after load; gate on the `check` global first when present
  if (func) loaded.then(() => check
    ? $.untilTrue(() => check() && (requestAnimationFrame(func), true))
    : requestAnimationFrame(func))

  return loaded
}

// pull a key off an object, returning its value
$.delete = (data, key) => { const v = data[key]; delete data[key]; return v }

// drop blank entries from an array, or from an object (keys lowercased with opts.toLowerCase)
$.compact = (data, opts = {}) => {
  const blank = v => [undefined, null, 'undefined', ''].includes(v)
  if (Array.isArray(data)) return data.filter(el => !blank(el))
  const out = {}
  Object.entries(data).forEach(([k, v]) => {
    if (!k.includes('$') && !blank(v)) out[opts.toLowerCase ? k.toLowerCase() : k] = v
  })
  return out
}

// object <-> inline css string; numbers get px unless the property is unitless
const _unitless = ['opacity', 'zIndex', 'z-index', 'fontWeight', 'font-weight', 'lineHeight', 'line-height', 'flex', 'flexGrow', 'flex-grow', 'flexShrink', 'flex-shrink', 'order', 'zoom']
$.css = data => {
  if (typeof data === 'object') {
    return Object.entries(data)
      .map(([k, v]) => `${k}: ${typeof v === 'number' && !_unitless.includes(k) ? v + 'px' : v};`)
      .join(' ')
  }
  return data.split(';').reduce((o, line) => {
    const [k, v] = line.trim().split(':')
    if (v) o[k.trim()] = v.trim()
    return o
  }, {})
}

// object <-> query string
$.qs = data => typeof data === 'object' ? $.param(data) : Object.fromEntries(new URLSearchParams(data))

$.JSON = data => data ? (typeof data === 'string' ? JSON.parse(data) : data) : data

$.prompt = (q, v, func) => { const r = prompt(q, v || ''); if (typeof r === 'string') func(r) }

$.capitalize = str => str.charAt(0).toUpperCase() + str.slice(1)

// build an html tag string from a name + attrs hash
$.tag = (nodeName, attrs) => {
  const attrStr = Object.keys(attrs).filter(k => attrs[k] !== undefined)
    .map(k => `${k}='${attrs[k]}'`).join(' ')
  return ['img', 'input', 'link', 'meta'].includes(nodeName)
    ? `<${nodeName} ${attrStr} />`
    : `<${nodeName} ${attrStr}></${nodeName}>`
}

// custom-element tag string: underscores in the name become dashes
$.rawTag = (name, opts) => {
  const upName = name.replaceAll('_', '-')
  const attrs = Object.keys(opts).map(k => `${k}="${opts[k]}"`).join(' ')
  return `<${upName} ${attrs}></${upName}>`
}

$.htmlSafe = text => String(text).replaceAll('&LT;', '<').replaceAll('#LT;', '<').replaceAll('<script', '&lt;script')

$.imageSize = (url, callback) => {
  const img = new Image()
  img.onload = () => callback({ w: img.naturalWidth, h: img.naturalHeight })
  img.src = url
}

let _ulidCounter = 0
$.ulid = prefix => {
  const parts = [(new Date()).getTime(), String(Math.random()).replace('0.', ''), ++_ulidCounter]
  const out = BigInt(parts.join('')).toString(36).slice(0, 20)
  return prefix ? `${prefix}-${out}` : out
}

// untilTrue, but also stops once the node leaves the DOM
$.untilTrueWhileExists = (node, func, timeout) => {
  $.untilTrue(() => {
    if (node) {
      if (!document.body.contains(node)) return true
      if (node.checkVisibility() && func()) return true
    }
  }, timeout)
}

// memoize on the JSON-serialized args
$.memoize = fn => {
  const cache = {}
  return (...args) => {
    const id = JSON.stringify(args)
    return id in cache ? cache[id] : (cache[id] = fn(...args))
  }
}

$.d = obj => JSON.stringify(obj, null, 2)

$.random = list => list[Math.floor(Math.random() * list.length)]

$.shuffle = list => {
  const out = list.slice()
  for (let i = out.length - 1; i >= 1; i--) {
    const j = Math.floor(Math.random() * (i + 1))
    ;[out[i], out[j]] = [out[j], out[i]]
  }
  return out
}

$.times = (num, func) => {
  const out = []
  for (let i = 0; i < num; i++) out.push(func(i))
  return out
}

$.scrollToBottom = goNow => {
  const go = () => window.scrollTo({ top: document.body.scrollHeight, left: 0, behavior: 'smooth' })
  goNow === true ? go() : setTimeout(go, goNow || 300)
}

$.resizeIframe = obj => {
  obj.style.height = obj.contentWindow.document.documentElement.scrollHeight + 'px'
}

$.cookies = {
  get(name) {
    const list = {}
    for (const line of document.cookie ? document.cookie.split('; ') : []) {
      const i = line.indexOf('='), key = line.slice(0, i), value = decodeURIComponent(line.slice(i + 1))
      if (key === name) return value
      list[key] = value
    }
    return name ? undefined : list
  },
  set(name, value, days) {
    const date = new Date()
    date.setTime(date.getTime() + ((days || 7) * 864e5))
    document.cookie = `${name}=${encodeURIComponent(value)}; expires=${date.toUTCString()}; path=/`
  },
  delete(name) { $.cookies.set(name, '', -1) },
}

// copy a string (or a node's innerText, or read the clipboard via callback)
$.copyText = str => {
  if (typeof str === 'function') {
    if (navigator.clipboard) navigator.clipboard.readText().then(str)
    else console.error('You are not on localhost or HTTPS')
    return
  }
  if (typeof str !== 'string') str = $(str)[0].innerText.trim()
  const el = document.createElement('textarea')
  el.value = str
  document.body.appendChild(el)
  el.select()
  document.execCommand('copy')
  document.body.removeChild(el)
}

// base64 + rot13 obfuscation (NOT security)
$.simpleEncodeBase = str => str.replace(/[a-zA-Z]/g, c => {
  const code = c.charCodeAt(0)
  const base = c >= 'a' ? 97 : 65
  return String.fromCharCode(base + ((code - base + 13) % 26))
})
$.simpleEncode = str => $.simpleEncodeBase(btoa(str).replaceAll('/', '_').replace(/=+$/, ''))
$.simpleDecode = s => atob($.simpleEncodeBase(s.replace(/_/g, '/')))

// named setInterval that clears any prior timer registered under the same name
const _namedIntervals = {}
$.setInterval = (name, func, every) => {
  clearInterval(_namedIntervals[name])
  _namedIntervals[name] = setInterval(func, every)
}

// child nodes of a root (html string or node) as a list (or grouped hash) of attr maps
$.nodesAsList = (root, asHash) => {
  const list = []
  if (!root) return list
  if (typeof root === 'string') { const n = document.createElement('div'); n.innerHTML = root; root = n }
  root.childNodes.forEach((node, i) => {
    if (!node.attributes) return
    const o = { NODENAME: node.nodeName, HTML: node.innerHTML, OUTER: node.outerHTML, ID: i + 1 }
    for (const a of node.attributes) o[a.name] = a.value
    list.push(o)
  })
  if (!asHash) return list
  const out = {}
  for (const el of list) (out[el.NODENAME] ||= []).push(el)
  return out
}

// --- $.fn node helpers ---

// css-transition animate (Zepto fx replacement). animate(props, duration, easing?, complete?)
$.fn.animate = function (props, duration = 400, easing, complete) {
  if (typeof duration === 'function') { complete = duration; duration = 400 }
  if (typeof easing === 'function') { complete = easing; easing = 'ease' }
  easing ||= 'ease'
  return this.each(function () {
    const el = this
    el.style.transition = Object.keys(props)
      .map(k => `${k.replace(/[A-Z]/g, m => '-' + m.toLowerCase())} ${duration}ms ${easing}`)
      .join(', ')
    requestAnimationFrame(() => {
      for (const [k, v] of Object.entries(props)) el.style[k] = typeof v === 'number' ? `${v}px` : v
    })
    if (complete) setTimeout(() => complete.call(el), duration)
  })
}

// serialize a form into a plain hash (unchecked checkboxes -> 0)
$.fn.serializeHash = function () {
  const hash = {}
  $(this).find('input, textarea, select').each(function () {
    if (this.name && !this.disabled) {
      if (this.type === 'radio' && !this.checked) return
      let val = $(this).val()
      if (this.type === 'checkbox' && !this.checked) val = 0
      hash[this.name] = val
    }
  })
  return hash
}

// submit a form via ajax, decoding json responses; callback(data, xhr)
$.fn.ajaxSubmit = function (callback) {
  const form = $(this)
  $.ajax({
    type: (form.attr('method') || 'get').toUpperCase(),
    url: form.attr('action'),
    data: form.serializeHash(),
    headers: window.Intl ? { 'x-tz-name': Intl.DateTimeFormat().resolvedOptions().timeZone } : {},
    complete: r => {
      let data = r.responseText
      if ((r.getResponseHeader('content-type') || '').toLowerCase().includes('json')) data = JSON.parse(data)
      if (callback) callback(data, r)
    },
  })
  return this
}

// animate an <img> to its natural aspect height (needs a starting height + css transition)
$.fn.animateHeight = function (height) {
  const img = this[0]
  if (height) {
    img.style.height = `${height}px`
    this.on('load', () => $(img).animateHeight())
  } else {
    const aspect = img.naturalWidth / img.naturalHeight
    img.style.height = (img.width / aspect) + 'px'
    setTimeout(() => { img.style.height = 'auto' }, 1500)
  }
  return this
}

// swap innerHTML with a height transition
$.fn.animateInsert = function (html) {
  const node = this[0]
  if (!node) return this
  if (html === undefined) html = node.innerHTML
  node.style.transition ||= 'all .3s ease-out'
  node.style.overflow = 'hidden'
  node.style.height ||= 'auto'
  if (node.oldHtmlCache !== html) {
    node.oldHtmlCache = html
    const test = document.createElement('div')
    test.style.height = '0px'
    test.innerHTML = html
    node.insertAdjacentElement('afterend', test)
    node.innerHTML = html
    requestAnimationFrame(() => {
      node.style.height = test.scrollHeight + 'px'
      test.parentNode.removeChild(test)
    })
  }
  return this
}

// stop propagation on the wrapped event: $(event).cancel()
$.fn.cancel = function () { const e = this[0]; e?.preventDefault?.(); e?.stopPropagation?.(); return this }

$.fn.isVisible = function () { return this[0] && this[0].checkVisibility() }

// height-transition slide helpers (replace the old Zepto fx .animate versions)
$.fn.slideDown = function (duration = 200) {
  return this.each(function () {
    const el = this
    el.style.overflow = 'hidden'
    el.style.transition = `height ${duration}ms ease-out`
    if (getComputedStyle(el).display === 'none') el.style.display = 'block'
    const h = el.scrollHeight
    el.style.height = '0px'
    requestAnimationFrame(() => { el.style.height = `${h}px` })
    setTimeout(() => { el.style.height = 'auto' }, duration)
  })
}
$.fn.slideUp = function (duration = 200) {
  return this.each(function () {
    const el = this
    el.style.overflow = 'hidden'
    el.style.height = `${el.scrollHeight}px`
    el.style.transition = `height ${duration}ms ease-out`
    requestAnimationFrame(() => { el.style.height = '0px' })
    setTimeout(() => { el.style.display = 'none' }, duration)
  })
}
$.fn.slideToggle = function (duration) {
  return this.each(function () {
    const el = $(this)
    getComputedStyle(this).display === 'none' ? el.slideDown(duration) : el.slideUp(duration)
  })
}

// toggle max-height between 0 and scrollHeight, marking the open state with .is-open
$.fn.toggleMaxHeight = function () {
  const node = this[0]
  if (!node) return this
  node.style.transition ||= 'max-height 0.2s ease-out'
  node.style.overflow = 'hidden'
  requestAnimationFrame(() => {
    if (this.css('max-height') === '0px') {
      this.addClass('is-open'); node.style.maxHeight = `${node.scrollHeight}px`
    } else {
      this.removeClass('is-open'); node.style.maxHeight = '0px'
    }
  })
  return this
}

// run func against the first matched element, if any
$.fn.xfirst = function (func) {
  const el = this.first()
  if (el[0]) func(el)
  return this
}

// --- window / Z / Array helpers ---

// ZZ('#id') sugar: string -> ensure a leading '#'; a node passes through
window.ZZ = nodeId => {
  if (typeof nodeId === 'string') return Z(nodeId.includes('#') ? nodeId : '#' + nodeId)
  return nodeId
}

window.XMP = what => {
  const data = JSON.stringify(what, null, 2)
  return `<xmp style='font-size: 0.9rem; line-height: 1.1rem; padding: 5px; border: 1px solid #ccc; background: #fff;'>${data}</xmp>`
}

window.xalert = message => {
  try { throw new Error(message) }
  catch (e) { alert(`${e.stack.split('\n')[2].trim()}\n\n${message}`) }
}

window.escapeHTML = text => String(text)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;').replace(/'/g, '&#39;')

Z.isTrue = v => v && String(v) !== 'false'

// Z.slice({foo: 1, style: 'x'}, 'style') -> { style: 'x' }; skips undefined keys
Z.slice = (data, ...args) => {
  const out = {}
  for (const key of args) if (data[key] !== undefined) out[key] = data[key]
  return out
}

Array.range = (min, max) => Array.from({ length: max - min + 1 }, (_, j) => j + min)

Object.defineProperty(Array.prototype, 'xpush', {
  value(el) { this.push(el); return this },
  enumerable: false,
})
