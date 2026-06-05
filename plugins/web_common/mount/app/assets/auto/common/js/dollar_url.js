// Browser port of Lux::Utils::Url (lib/lux/utils/url.rb). Same internal model
// (proto/port/subdomain/domain/locale/path/qs/qsPath/qsHash) and method
// vocabulary; statics that read the server request in Ruby read location.href here.
//
//   u = $.url('https://www.youtube.com/watch?t=1260&v=cOFSX6nezEY')
//   u.delete('t').hash('160s').toString()
//   $.url().qs('page', 2).relative()        build a link off the current page
//
// $.url is dual-purpose (mirrors Ruby's Url('href') instance vs Url.qs(...) class call):
//   $.url(href) / $.url()                    -> a Url instance; no arg reads the current
//                                               page. Instance methods chain (return self):
//                                               $.url().qs('page', 2).relative()
//   $.url.qs('page', 2)                      -> static shortcut bound to the class; reads
//                                               the current page and returns a finished
//                                               string (.relative() baked in), so it equals
//                                               $.url().qs('page', 2).relative(). Same name
//                                               as the instance method, different return
//                                               type - the trailing () picks which you get.
//
// One intentional divergence: the '#fragment' is always parsed, even on a url
// without a '?' (Ruby only parses it when a querystring is present).

const $ = window.$

const NIL = Symbol('nil')                                   // "argument not passed" sentinel (Ruby :_nil)
const DEFAULT_PORTS = { http: '80', https: '443', ws: '80', wss: '443' }
const LOCALE_RE = /^[a-z]{2}(-[A-Z]{2})?$/

class Url {
  // parse an absolute or relative URL into @opt. Order:
  //   1. split off #fragment and ?qs
  //   2. if absolute, extract proto, host, port, domain, subdomain (co.uk length heuristic)
  //   3. peel locale prefix (xx or xx-YY) and trailing /key:value segments off the path
  constructor(url) {
    url ||= location.href

    const opt = this.opt = {
      proto: null, port: null, subdomain: null, domain: null,
      locale: null, path: '', qs: {}, qsHash: null, qsPath: {}
    }

    const fi = url.indexOf('#')
    if (fi >= 0) { opt.qsHash = '#' + url.slice(fi + 1); url = url.slice(0, fi) }

    const qi = url.indexOf('?')
    let qsPart = ''
    if (qi >= 0) { qsPart = url.slice(qi + 1); url = url.slice(0, qi) }

    if (qsPart) {
      for (const el of qsPart.split('&')) {
        const i = el.indexOf('=')
        const key = i < 0 ? el : el.slice(0, i)
        opt.qs[key] = Url.unescape(i < 0 ? '' : el.slice(i + 1))
      }
    }

    if (/^\w+:\/\//.test(url)) {
      const seg = url.split('/')
      opt.proto = seg[0].replace(':', '')

      let [host, port] = seg[2].split(':', 2)
      opt.port = (!port || port === DEFAULT_PORTS[opt.proto]) ? null : port

      const parts = host.split('.').map(s => s.toLowerCase())
      const domain = parts.splice(-2)
      if (domain.join('').length === 4 && parts.length) domain.unshift(parts.pop()) // co.uk
      opt.domain = domain.join('.')
      opt.subdomain = parts.length ? parts.join('.') : null

      url = seg.slice(3).join('/')
    }
    opt.path = url.replace(/^\//, '')

    let parts = opt.path.split('/')
    if (LOCALE_RE.test(parts[0])) opt.locale = parts.shift()

    while (parts.length && parts[parts.length - 1].includes(':')) {
      const [k, v] = parts.pop().split(':')
      opt.qsPath[k] = v
    }

    opt.path = parts.join('/')
  }

  // returns a relative url primed for appending a value to `name`, e.g. "/foo?bar=1&q="
  prepareQs(name) {
    let url = this.delete(name).relative()
    url += url.includes('?') ? '&' : '?'
    return `${url}${name}=`
  }

  // reader when called bare; writer (chainable) when given a value
  domain(what) {
    if (what) { this.opt.domain = what; return this }
    return this.opt.domain
  }

  // reader/writer; pass null/'' to clear -> apex/root
  subdomain(name = NIL) {
    if (name === NIL) return this.opt.subdomain
    this.opt.subdomain = (name == null || name === '') ? null : name
    return this
  }

  // full host: subdomain.domain (or just domain)
  host() {
    return this.opt.subdomain ? `${this.opt.subdomain}.${this.opt.domain}` : this.opt.domain
  }

  // origin string: proto://host[:port]; empty when no proto/host (relative urls)
  hostWithPort() {
    if (!(this.opt.proto && this.host())) return ''
    const port = this.opt.port ? `:${this.opt.port}` : ''
    return `${this.opt.proto}://${this.host()}${port}`
  }

  // getter renders /locale/path/key:val; setter strips leading slash and is chainable
  path(val) {
    if (val) { this.opt.path = String(val).replace(/^\//, ''); return this }
    const parts = []
    if (this.opt.locale) parts.push(this.opt.locale)
    if (this.opt.path) parts.push(...this.opt.path.split('/'))
    for (const [k, v] of Object.entries(this.opt.qsPath)) if (v != null && v !== '') parts.push(`${k}:${v}`)
    return '/' + parts.join('/')
  }

  // remove one or more keys from the query string; chainable
  delete(...keys) {
    keys.forEach(key => delete this.opt.qs[String(key)])
    return this
  }

  // set the #fragment; chainable
  hash(val) {
    this.opt.qsHash = `#${val}`
    return this
  }

  port() { return this.opt.port }
  proto() { return this.opt.proto }

  // four modes: bare -> full qs object; (object) -> bulk merge (null values delete);
  // (name) -> read value (falls back to qsPath); (name, value) -> write (null deletes)
  qs(name, value = NIL) {
    if (name == null) return this.opt.qs

    if (typeof name === 'object') {
      for (const [k, v] of Object.entries(name)) v == null ? delete this.opt.qs[k] : this.opt.qs[k] = v
      return this
    }

    name = String(name)

    if (value !== NIL) {
      value == null ? delete this.opt.qs[name] : this.opt.qs[name] = value
      return this
    }
    return this.opt.qs[name] ?? this.opt.qsPath[name]
  }

  // path query string -> /foo/bar:baz
  pqs(name = null, value = NIL) {
    if (value !== NIL) { this.opt.qsPath[String(name)] = Url.escape(String(value)); return this }
    if (name != null) return this.opt.qsPath[name]
    return this.opt.qsPath
  }

  pathQs(...args) { return this.pqs(...args) }

  // tokens after a leading ':' in the path, e.g. /:a:b/x -> ['a', 'b']
  pathPrefix() {
    if (this.opt.path[0] === ':') return this.opt.path.slice(1).split('/')[0].split(':')
    return []
  }

  // reader/writer; pass null to clear
  locale(name) {
    if (name) { this.opt.locale = name; return this }
    return this.opt.locale
  }

  // absolute form: origin + path + ?qs + #fragment
  url() {
    return [this.hostWithPort(), this.path(), this._qsVal(), this.opt.qsHash || ''].join('')
  }

  // relative form: path + ?qs + #fragment (no origin); collapses a leading run of slashes
  relative() {
    return [this.path(), this._qsVal(), this.opt.qsHash || ''].join('').replace(/^\/+/, '/')
  }

  // absolute if a domain is known, else relative
  toString() {
    return this.opt.domain ? this.url() : this.relative()
  }

  // qs shortcut: url.get('foo') === url.qs('foo')
  get(key) { return this.qs(key) }

  // Zepto-url compat: relative by default, absolute origin with { url: true }
  render(opts = {}) { return opts.url ? this.url() : this.relative() }

  // structured snapshot of all parsed fields
  toH() {
    return {
      proto: this.opt.proto,
      port: this.opt.port,
      domain: { full: this.host(), domain: this.opt.domain, subdomain: this.opt.subdomain },
      locale: this.opt.locale,
      path: this.opt.path,
      qs: this.opt.qs,
      hash: this.opt.qsHash
    }
  }

  toJSON() { return this.toH() }

  // renders ?a=1&b=2 with keys sorted alphabetically (stable across calls)
  _qsVal() {
    const keys = Object.keys(this.opt.qs)
    if (!keys.length) return ''
    return '?' + keys.sort().map(k => `${k}=${Url.escape(String(this.opt.qs[k]))}`).join('&')
  }

  // -- statics; the Ruby class reads Lux.current.request, here we read location.href --

  static current() { return new Url(location.href) }

  static host() { return Url.current().host() }

  static root() { return Url.current().hostWithPort() }

  static locale(loc) { const u = Url.current(); u.locale(loc); return u.relative() }

  static subdomain(name, inPath) {
    const b = Url.current().subdomain(name)
    if (inPath) b.path(inPath)
    return b.url()
  }

  static qs(name, value) { return Url.current().qs(name, value).relative() }

  static pqs(name, value) {
    const u = Url.current().pqs(name, value)
    u.qs(name, null)
    return u.relative()
  }

  static toggle(name, value) {
    if (String(Url.current().qs(name)) === String(value)) value = null
    return Url.qs(name, value)
  }

  static prepareQs(name) { return Url.current().prepareQs(name) }

  // CGI.escape compatible (space -> '+'); null-safe
  static escape(str) {
    if (str == null) return ''
    return encodeURIComponent(String(str))
      .replace(/%20/g, '+')
      .replace(/[!'()*~]/g, c => '%' + c.charCodeAt(0).toString(16).toUpperCase())
  }

  // CGI.unescape compatible ('+' -> space); null-safe
  static unescape(str) {
    if (str == null) return ''
    return decodeURIComponent(String(str).replace(/\+/g, '%20'))
  }
}

// $.url(href) builds an instance; the statics ride on the same function object so
// $.url.qs(...) etc. resolve to the class methods (see header for the dual call shape).
$.url = url => new Url(url)
'current host root locale subdomain qs pqs toggle prepareQs escape unescape'.split(' ').forEach(m => $.url[m] = Url[m].bind(Url))
