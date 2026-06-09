// node-aware pub/sub. a subscription bound to a DOM node is dropped automatically
// once that node leaves the document, so detached views stop receiving events.
//   $.sub('user:changed', fn)        global subscribe (keyed by handler source)
//   $.pub('user:changed', data)      publish
//   $('#panel').sub('tick', fn)      node-bound subscribe, auto-cleaned on removal

const $ = window.$
const SUBS = {}
let nodeSeq = 0

$.pub = (name, ...args) => {
  const subs = SUBS[name] || {}
  for (const key in subs) {
    const item = subs[key]
    if (!item.node) { item.func(...args); continue }
    if (item.node.isConnected && item.node.parentNode) item.func(...args)
    else delete subs[key]
  }
}

$.sub = (name, func) => {
  const [base, hash] = name.split(':', 2)
  ;(SUBS[base] ||= {})[hash || $.fnv1(String(func))] = { func }
  return null
}

$.clearSubs = name => { delete SUBS[name] }

$.fn.sub = function (name, func) {
  const node = this[0]
  if (node) (SUBS[name] ||= {})[node.id ||= `psgen_id_${++nodeSeq}`] = { func, node }
  return this
}
