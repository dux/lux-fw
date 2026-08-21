// Shared browser helpers for the vibe harness components (loaded before the
// .fez files, plain script - no build step).
//
//   Vibe.api(path, body)   json call to the harness api, throws Error(server message)
//   Vibe.oc(path, opts)    call to opencode through the /oc proxy (directory pin is server side)
//   Vibe.md(text)          markdown -> html (marked), <script> stripped
//   Vibe.esc(text)         html escape
//   Vibe.toast(msg, kind)  broadcast a toast (vibe-app renders them)
//   Fez.publish / this.subscribe are the cross-component bus (global channels):
//     'health' {..}, 'files:refresh', 'git:changed', 'turn:done', 'app:restarted', 'toast' {text, kind}

window.Vibe = (() => {
  async function parse(res) {
    const ct = res.headers.get('content-type') || ''
    if (ct.includes('json')) return res.json()
    return res.text()
  }

  async function api(path, body, opts = {}) {
    const init = { method: body === undefined ? 'GET' : 'POST', headers: {}, ...opts }
    if (body !== undefined) {
      init.headers['content-type'] = 'application/json'
      init.body = JSON.stringify(body)
    }
    const res  = await fetch(path, init)
    const data = await parse(res)
    if (!res.ok) {
      const msg = (data && data.error) || (typeof data === 'string' && data.slice(0, 200)) || `${init.method} ${path} -> ${res.status}`
      throw new Error(msg)
    }
    return data
  }

  // opencode api through the proxy; returns json (arrays come back bare)
  async function oc(path, opts = {}) {
    const init = { ...opts }
    if (init.json !== undefined) {
      init.method = init.method || 'POST'
      init.headers = { 'content-type': 'application/json', ...(init.headers || {}) }
      init.body = JSON.stringify(init.json)
      delete init.json
    }
    const res  = await fetch(`/oc${path}`, init)
    const data = await parse(res)
    if (!res.ok) {
      const msg = (data && (data.error || (data.data && data.data.message))) || `${init.method || 'GET'} ${path} -> ${res.status}`
      throw new Error(typeof msg === 'string' ? msg : JSON.stringify(msg))
    }
    return data
  }

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
  }

  function md(text) {
    if (!text) return ''
    let html
    try {
      html = window.marked ? marked.parse(text, { gfm: true, breaks: true }) : `<p>${esc(text)}</p>`
    } catch (e) {
      html = `<p>${esc(text)}</p>`
    }
    // the agent's own output, but a stray <script> must not run in the harness page
    return html.replace(/<script[\s\S]*?<\/script>/gi, '').replace(/ on\w+="[^"]*"/gi, '')
  }

  function toast(text, kind = 'info') {
    Fez.publish('toast', { text: String(text), kind })
  }

  function trunc(s, n) {
    s = String(s == null ? '' : s)
    return s.length > n ? s.slice(0, n) + '...' : s
  }

  // "3m ago" style for unix ms timestamps
  function ago(ms) {
    if (!ms) return ''
    const d = Math.max(0, Date.now() - ms) / 1000
    if (d < 60)    return 'just now'
    if (d < 3600)  return `${Math.floor(d / 60)}m ago`
    if (d < 86400) return `${Math.floor(d / 3600)}h ago`
    return `${Math.floor(d / 86400)}d ago`
  }

  return { api, oc, esc, md, toast, trunc, ago }
})()
