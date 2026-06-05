// memory + localStorage TTL cache, reachable as $.cache
//   $.cache.set('k', v, { ttl: 60, perma: true })   ttl in seconds, perma also persists to localStorage
//   $.cache.fetch('k', () => api(...), { ttl: 60 })  memoize an async producer

const $ = window.$
const mem = {}
const key = k => `cache-${k}`

$.cache = {
  data: mem,

  set(k, value, opts = {}) {
    const blob = JSON.stringify([value, Date.now() + (opts.ttl || 86400) * 1000])
    mem[key(k)] = blob
    if (opts.perma) localStorage.setItem(key(k), blob)
    return value
  },

  get(k) {
    if (window.noCache) return null
    const blob = mem[key(k)] ?? localStorage.getItem(key(k))
    if (!blob) return null
    const [value, expires] = JSON.parse(blob)
    if (expires > Date.now()) return value
    $.cache.delete(k)
    return null
  },

  delete(k) {
    delete mem[key(k)]
    localStorage.removeItem(key(k))
  },

  async fetch(k, fn, opts = {}) {
    const hit = $.cache.get(k)
    return hit === null ? $.cache.set(k, await fn(), opts) : hit
  }
}
