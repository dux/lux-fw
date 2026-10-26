// pub/sub on the Fez bus (Fez.publish / Fez.subscribe), so $.pub reaches Fez
// component subscribers and Fez.publish reaches $.sub. A subscription bound to a
// DOM node is dropped once that node leaves the document.
//   $.sub('user:changed', fn, 'mykey')  subscribe; key dedupes (default = handler source)
//   $.pub('user:changed', data)         publish
//   $('#panel').sub('tick', fn)         node-bound subscribe, auto-cleaned on removal
//   $.clearSubs('user:changed')         drop every $.sub / $.fn.sub made for the name

const $ = window.$
const SUBS = {}   // name -> { key: unsubscribe }, so a key re-registration replaces
let nodeSeq = 0
const SUB_ID = Symbol('sub')

const add = (name, key, unsub) => {
  const subs = SUBS[name] ||= {}
  subs[key]?.()
  subs[key] = unsub
}

$.pub = (name, ...args) => Fez.publish(name, ...args)

$.sub = (name, func, key) => {
  add(name, key || $.fnv1(String(func)), Fez.subscribe(name, func))
  return null
}

$.clearSubs = name => {
  for (const unsub of Object.values(SUBS[name] || {})) unsub()
  delete SUBS[name]
}

$.fn.sub = function (name, func) {
  const node = this[0]
  if (node) add(name, `n${node[SUB_ID] ||= ++nodeSeq}:${$.fnv1(String(func))}`, Fez.subscribe(node, name, func))
  return this
}
