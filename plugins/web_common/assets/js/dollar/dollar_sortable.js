// drag-to-reorder backed by SortableJS (lib/sortable.js), auto-persisted via Api.
// the container needs data-api-path; each draggable child needs data-ref (or pass { target }).
//   $.sortable('#board')
//   $.sortable('.cards', { group: 'cards', handle: '.drag-handler', done: fn })
//
// SaveSortable.connect(...) is kept as a back-compat alias for the old CoffeeScript API.

const $ = window.$

// element children only (text nodes have no dataset), read in DOM order
const refs = node => [...node.children].map(n => n.dataset.ref)

const persist = node => {
  const path = node.sortableTarget
  if (!path) return
  const list = refs(node)
  if (!list.length) return
  // every sortable child must carry a data-ref; a missing one would silently
  // drop the item from the persisted order, so surface the markup bug instead
  if (list.some(ref => !ref)) return console.warn('ui-sortable: every child needs a data-ref', node)
  if (typeof path == 'function') return path(list)
  if (path[0] == '(') return eval(`(${path})`)(list)
  $.api(path, { refs: list }).topInfo().done((r, n) => {
    $.pub('drag-end', r, n)
    node.sortableDone?.(r, n)
  })
}

// one debounced saver per node, so rapid drops collapse into a single write
const save = o => {
  const node = o[0]
  if (!node?.sortableTarget) return
  ;(node.sortableSave ||= $.debounce(() => persist(node), 250))()
}

$.sortable = (selection, opts = {}) => {
  opts.animation ||= 100
  opts.onStart   ||= e => $.pub('drag-start', e)
  opts.onSort    ||= e => { save($(e.from)); if (e.from != e.to) save($(e.to)) }

  let done = opts.done || (() => true)
  if (typeof done == 'string') done = new Function(done)

  const nodes = $(selection)
  nodes.each((_, el) => {
    el.sortableTarget = opts.target || nodes.attr('data-api-path')
    el.sortableDone = done
    new Sortable(el, opts)
  })
  return nodes
}

// back-compat: old CoffeeScript SaveSortable.connect(selection, opts)
window.SaveSortable = { connect: (selection, opts) => $.sortable(selection, opts) }
