(win => {
  const doc = win.document
  const HTML = /^\s*</
  const isStr = v => typeof v == 'string'
  const isFn = v => typeof v == 'function'
  const arr = v => Array.prototype.slice.call(v)
  const uniq = a => [...new Set(a)]

  // natural display per tag (span->inline, div->block, ...), probed once and cached
  const DISPLAY_CACHE = {}
  const defaultDisplay = tag => {
    tag = tag.toLowerCase()
    if (!DISPLAY_CACHE[tag]) {
      const el = doc.createElement(tag)
      doc.body.appendChild(el)
      const d = getComputedStyle(el).display
      el.remove()
      DISPLAY_CACHE[tag] = d == 'none' ? 'block' : d
    }
    return DISPLAY_CACHE[tag]
  }
  // reveal: drop the inline display first; if a class still hides it (display:none),
  // set the tag's natural default inline so it overrides the class.
  const reveal = el => {
    el.style.display = ''
    if (getComputedStyle(el).display == 'none') el.style.display = defaultDisplay(el.tagName)
  }

  const onReady = fn => doc.readyState != 'loading' ? fn() : doc.addEventListener('DOMContentLoaded', fn)

  const sib = (e, prop, until) => { const o = []; let n = e[prop]; while (n) { if (until && n.matches(until)) break; o.push(n); n = n[prop] } return o }
  const ups = (e, until) => { const o = []; let p = e.parentElement; while (p) { if (until && p.matches(until)) break; o.push(p); p = p.parentElement } return o }

  const frag = a => {
    if (a instanceof D) return [...a]
    if (a.nodeType) return [a]
    if (isStr(a)) { if (!HTML.test(a)) return [doc.createTextNode(a)]; const t = doc.createElement('template'); t.innerHTML = a.trim(); return arr(t.content.childNodes) }
    return arr(a)
  }

  const nodes = (sel, ctx) => {
    if (!sel) return []
    if (sel instanceof D) return [...sel]
    if (isFn(sel)) return (onReady(sel), [])
    if (sel.nodeType || sel === win) return [sel]
    if (isStr(sel)) return HTML.test(sel) ? frag(sel) : arr((ctx ? $(ctx)[0] : doc).querySelectorAll(sel))
    return arr(sel)
  }

  class D extends Array {}
  const $ = (sel, ctx) => D.from(nodes(sel, ctx))
  const map$ = (set, fn) => $(uniq([].concat(...[...set].map(fn)).filter(Boolean)))

  Object.assign(D.prototype, {
    each(fn) { [...this].forEach((e, i) => fn.call(e, i, e)); return this },
    map(fn) { return $([...this].map((e, i) => fn.call(e, i, e))) },
    filter(f) { return $([...this].filter((e, i) => isStr(f) ? e.matches(f) : f.call(e, i, e))) },
    slice(...a) { return $([...this].slice(...a)) },
    get(i) { return i === undefined ? [...this] : this[i < 0 ? this.length + i : i] },
    eq(i) { return $(this.get(i)) },
    first() { return this.eq(0) },
    last() { return this.eq(-1) },
    index(el) { return el === undefined ? (this[0] ? [...this[0].parentNode.children].indexOf(this[0]) : -1) : [...this].indexOf($(el)[0]) },
    add(sel) { return $(uniq([...this, ...nodes(sel)])) },
    not(sel) { return $([...this].filter(e => isFn(sel) ? !sel(e) : !e.matches(sel))) },
    is(sel) { return [...this].some(e => isFn(sel) ? sel(e) : e.matches(sel)) },
    has(sel) { return $([...this].filter(e => isStr(sel) ? !!e.querySelector(sel) : e.contains(sel))) },

    addClass(c) { return this.each(function () { this.classList.add(...c.split(/\s+/)) }) },
    removeClass(c) { return this.each(function () { this.classList.remove(...c.split(/\s+/)) }) },
    toggleClass(c, f) { return this.each(function () { c.split(/\s+/).forEach(n => this.classList.toggle(n, f)) }) },
    hasClass(c) { return [...this].some(e => e.classList.contains(c)) },
    attr(n, v) { return v === undefined && isStr(n) ? this[0]?.getAttribute(n) : this.each(function () { typeof n == 'object' ? Object.entries(n).forEach(([k, x]) => this.setAttribute(k, x)) : this.setAttribute(n, v) }) },
    removeAttr(n) { return this.each(function () { this.removeAttribute(n) }) },
    prop(n, v) { return v === undefined ? this[0]?.[n] : this.each(function () { this[n] = v }) },
    removeProp(n) { return this.each(function () { delete this[n] }) },

    css(n, v) { if (typeof n == 'object') return this.each(function () { Object.assign(this.style, n) }); if (v === undefined) return this[0] && getComputedStyle(this[0])[n]; return this.each(function () { this.style[n] = v }) },
    data(n, v) { return v === undefined ? this[0]?.dataset[n] : this.each(function () { this.dataset[n] = v }) },

    width() { return parseFloat(getComputedStyle(this[0]).width) },
    height() { return parseFloat(getComputedStyle(this[0]).height) },
    innerWidth() { return this[0].clientWidth },
    innerHeight() { return this[0].clientHeight },
    outerWidth(m) { const e = this[0], s = getComputedStyle(e); return e.offsetWidth + (m ? parseFloat(s.marginLeft) + parseFloat(s.marginRight) : 0) },
    outerHeight(m) { const e = this[0], s = getComputedStyle(e); return e.offsetHeight + (m ? parseFloat(s.marginTop) + parseFloat(s.marginBottom) : 0) },

    show() { return this.each(function () { reveal(this) }) },
    hide() { return this.each(function () { this.style.display = 'none' }) },
    toggle(f) { return this.each(function () { (f === undefined ? getComputedStyle(this).display == 'none' : f) ? reveal(this) : this.style.display = 'none' }) },

    on(type, sel, fn) {
      const dele = isStr(sel), cb = dele ? fn : sel
      const h = dele ? function (ev) { const t = ev.target.closest(sel); if (t && this.contains(t)) cb.call(t, ev) } : cb
      if (dele) cb.__d = h
      return this.each(function () { type.split(/\s+/).forEach(t => this.addEventListener(t, h)) })
    },
    off(type, fn) { return this.each(function () { type.split(/\s+/).forEach(t => this.removeEventListener(t, fn.__d || fn)) }) },
    one(type, sel, fn) {
      const dele = isStr(sel), cb = dele ? fn : sel, self = this
      const h = function (ev) { const t = dele ? ev.target.closest(sel) : this; if (dele && !(t && this.contains(t))) return; self.off(type, h); cb.call(t, ev) }
      return this.each(function () { type.split(/\s+/).forEach(t => this.addEventListener(t, h)) })
    },
    ready(fn) { onReady(fn); return this },
    trigger(type, detail) { return this.each(function () { this.dispatchEvent(new CustomEvent(type, { bubbles: true, cancelable: true, detail })) }) },

    serialize() { return new URLSearchParams(new FormData(this[0])).toString() },
    val(v) { return v === undefined ? this[0]?.value : this.each(function () { this.value = v }) },

    html(v) { return v === undefined ? this[0]?.innerHTML : this.each(function () { this.innerHTML = v }) },
    text(v) { return v === undefined ? this[0]?.textContent : this.each(function () { this.textContent = v }) },
    append(c) { return this.each(function (i) { frag(c).forEach(n => this.appendChild(i ? n.cloneNode(true) : n)) }) },
    prepend(c) { return this.each(function (i) { frag(c).reverse().forEach(n => this.insertBefore(i ? n.cloneNode(true) : n, this.firstChild)) }) },
    before(c) { return this.each(function (i) { frag(c).forEach(n => this.parentNode.insertBefore(i ? n.cloneNode(true) : n, this)) }) },
    after(c) { return this.each(function (i) { frag(c).reverse().forEach(n => this.parentNode.insertBefore(i ? n.cloneNode(true) : n, this.nextSibling)) }) },
    appendTo(t) { $(t).append(this); return this },
    prependTo(t) { $(t).prepend(this); return this },
    insertBefore(t) { $(t).before(this); return this },
    insertAfter(t) { $(t).after(this); return this },
    replaceWith(c) { return this.each(function (i) { const f = frag(c); this.replaceWith(...(i ? f.map(n => n.cloneNode(true)) : f)) }) },
    replaceAll(t) { $(t).replaceWith(this); return this },
    clone() { return $([...this].map(e => e.cloneNode(true))) },
    empty() { return this.each(function () { this.replaceChildren() }) },
    remove() { return this.each(function () { this.remove() }) },
    detach() { return this.remove() },
    wrap(w) { return this.each(function () { const x = frag(w)[0].cloneNode(true); this.parentNode.insertBefore(x, this); x.appendChild(this) }) },
    wrapInner(w) { return this.each(function () { const x = frag(w)[0].cloneNode(true); while (this.firstChild) x.appendChild(this.firstChild); this.appendChild(x) }) },
    wrapAll(w) { const x = frag(w)[0]; if (this[0]) { this[0].parentNode.insertBefore(x, this[0]); this.each(function () { x.appendChild(this) }) } return this },
    unwrap() { return this.each(function () { const p = this.parentNode; if (p && p.parentNode) p.replaceWith(...p.childNodes) }) },

    offset() { const r = this[0].getBoundingClientRect(); return { top: r.top + scrollY, left: r.left + scrollX } },
    position() { return { top: this[0].offsetTop, left: this[0].offsetLeft } },
    offsetParent() { return $(this[0].offsetParent) },

    find(sel) { return map$(this, e => arr(e.querySelectorAll(sel))) },
    children(sel) { const r = map$(this, e => arr(e.children)); return sel ? r.filter(sel) : r },
    contents() { return map$(this, e => arr(e.childNodes)) },
    closest(sel) { return map$(this, e => e.closest(sel)) },
    parent(sel) { const r = map$(this, e => e.parentElement); return sel ? r.filter(sel) : r },
    parents(sel) { const r = map$(this, e => ups(e)); return sel ? r.filter(sel) : r },
    parentsUntil(sel) { return map$(this, e => ups(e, sel)) },
    next(sel) { const r = map$(this, e => e.nextElementSibling); return sel ? r.filter(sel) : r },
    prev(sel) { const r = map$(this, e => e.previousElementSibling); return sel ? r.filter(sel) : r },
    nextAll(sel) { const r = map$(this, e => sib(e, 'nextElementSibling')); return sel ? r.filter(sel) : r },
    prevAll(sel) { const r = map$(this, e => sib(e, 'previousElementSibling')); return sel ? r.filter(sel) : r },
    nextUntil(sel) { return map$(this, e => sib(e, 'nextElementSibling', sel)) },
    prevUntil(sel) { return map$(this, e => sib(e, 'previousElementSibling', sel)) },
    siblings(sel) { const r = map$(this, e => arr(e.parentNode.children).filter(c => c !== e)); return sel ? r.filter(sel) : r },

    scrollLeft(v) { return v === undefined ? this[0]?.scrollLeft : this.each(function () { this.scrollLeft = v }) },
    scrollTop(v) { return v === undefined ? this[0]?.scrollTop : this.each(function () { this.scrollTop = v }) }
  })

  // event shorthands: x(fn) binds the handler, x() fires the native action (or dispatches the event)
  'click dblclick focus blur submit change input select keydown keyup keypress scroll mousedown mousemove mouseup mouseenter mouseleave load'.split(' ').forEach(ev => {
    D.prototype[ev] = function (fn) { return fn === undefined ? this.each(function () { isFn(this[ev]) ? this[ev]() : $(this).trigger(ev) }) : this.on(ev, fn) }
  })

  // jQuery/Zepto-style statics kept so app code ported off Zepto keeps working
  $.isArray = Array.isArray
  $.isFunction = isFn
  $.isPlainObject = v => v != null && typeof v == 'object' && [Object.prototype, null].includes(Object.getPrototypeOf(v))
  $.each = (o, fn) => { Array.isArray(o) ? o.forEach((v, i) => fn(i, v)) : Object.keys(o).forEach(k => fn(k, o[k])); return o }
  $.map = (o, fn) => (Array.isArray(o) ? o.map((v, i) => fn(v, i)) : Object.keys(o).map(k => fn(o[k], k))).filter(v => v != null)
  $.extend = Object.assign

  // trailing-edge debounce: fires fn once after `wait` ms of silence
  $.debounce = (fn, wait) => {
    let t
    return function (...a) { clearTimeout(t); t = setTimeout(() => fn.apply(this, a), wait) }
  }

  // throttle: fires fn at most once per `wait` ms (leading edge)
  $.throttle = (fn, wait) => {
    let last = 0, t
    return function (...a) {
      const now = Date.now(), gap = wait - (now - last)
      if (gap <= 0) { clearTimeout(t); t = null; last = now; fn.apply(this, a) }
      else if (!t) t = setTimeout(() => { last = Date.now(); t = null; fn.apply(this, a) }, gap)
    }
  }

  // promise that resolves after `ms`, optionally with a value
  $.delay = (ms, v) => new Promise(res => setTimeout(() => res(v), ms))

  // wrap fn so it runs at most once; later calls return the first result
  $.once = fn => {
    let done, val
    return function (...a) { if (!done) { done = true; val = fn.apply(this, a) } return val }
  }

  // form-urlencoded with Rails/Zepto nested-bracket serialization
  $.param = (obj, scope) => {
    const out = []
    for (const k in obj) {
      const key = scope ? `${scope}[${k}]` : k, v = obj[k]
      out.push(v != null && typeof v == 'object' ? $.param(v, key) : `${encodeURIComponent(key)}=${encodeURIComponent(v == null ? '' : v)}`)
    }
    return out.join('&')
  }

  // XMLHttpRequest-based $.ajax with a Zepto-shaped callback contract:
  // success(data, xhr) / complete(xhr) / error(xhr). Returns the xhr synchronously
  // (old Zepto behaviour) so `const xhr = $.get(...)` works; for a promise, use fetch().
  $.ajax = o => {
    const type = (o.type || o.method || 'GET').toUpperCase()
    let url = o.url, body
    const headers = { 'x-requested-with': 'XMLHttpRequest', ...(o.headers || {}) }
    if (o.data != null) {
      const enc = isStr(o.data) ? o.data : $.param(o.data)
      if (type == 'GET') url += (url.includes('?') ? '&' : '?') + enc
      else if (o.contentType == 'json' || o.dataType == 'json') { body = JSON.stringify(o.data); headers['content-type'] = 'application/json' }
      else { body = enc; headers['content-type'] = 'application/x-www-form-urlencoded' }
    }
    const xhr = new XMLHttpRequest()
    xhr.open(type, url, true)
    for (const k in headers) xhr.setRequestHeader(k, headers[k])
    xhr.onload = () => {
      const txt = xhr.responseText
      if (o.success) o.success((xhr.getResponseHeader('content-type') || '').includes('json') ? JSON.parse(txt || 'null') : txt, xhr)
      o.complete?.(xhr)
    }
    xhr.onerror = () => { o.error?.(xhr); o.complete?.(xhr) }
    xhr.send(body)
    return xhr
  }

  // $.get / $.post return a small chainable result: .done/.error/.always plus
  // .json/.text response coercion. An inline success callback still works, and
  // .xhr / .abort() keep the old "returns the XHR" callers working. $.ajax
  // itself is unchanged (still returns the XHR) for option-style callers.
  const ajaxProxy = (opts, success) => {
    const cbs = { done: [], error: [], always: [] }
    if (success) cbs.done.push(success)
    const xhr = $.ajax({
      ...opts,
      success: (data, x) => cbs.done.forEach(f => f(data, x)),
      error: x => cbs.error.forEach(f => f(x)),
      complete: x => cbs.always.forEach(f => f(x)),
    })
    const p = {
      done: f => (cbs.done.push(f), p),
      error: f => (cbs.error.push(f), p),
      always: f => (cbs.always.push(f), p),
      json: f => (cbs.done.push((d, x) => f(typeof d == 'string' ? JSON.parse(d) : d, x)), p),
      text: f => (cbs.done.push((d, x) => f(x.responseText, x)), p),
      abort: () => (xhr.abort(), p),
      xhr,
    }
    return p
  }

  $.get = (url, success) => ajaxProxy({ type: 'GET', url }, success)
  $.post = (url, data, success) => ajaxProxy({ type: 'POST', url, data }, success)

  // load and execute a remote script, jQuery.getScript compatible
  $.getScript = (url, success) => new Promise((resolve, reject) => {
    const s = doc.createElement('script')
    s.src = url
    s.onload = () => { success?.(); resolve() }
    s.onerror = reject
    doc.head.appendChild(s)
  })

  // FNV-1a string hash, returned base36
  $.fnv1 = str => {
    let h = 0x811c9dc5
    for (let i = 0; i < str.length; i++) {
      h ^= str.charCodeAt(i)
      h = (h + ((h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24))) >>> 0
    }
    return h.toString(36)
  }

  $.fn = D.prototype
  $.ready = onReady
  win.$ = $
  win.Z = $

  // single app namespace: data lands in app.cfg/current/page (server-injected).
  // framework utilities stay on $ (above); app.fn is the empty namespace that
  // individual apps register their own app-specific functions into.
  ;(win.app ||= {}).fn ||= {}
})(window)
