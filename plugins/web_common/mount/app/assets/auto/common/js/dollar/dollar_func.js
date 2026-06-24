// $.fn extensions ported from the apps' Zepto helpers, kept out of the
// _dollar core so the base stays a thin Zepto-shaped shim.
//   $('.btn').shake()        rotate wobble (error feedback)
//   $('input').focus()       native focus on each
//   $('input').blur()        native blur on each
//   $('form').submit()       cancelable submit event, then native submit
//   $('#list').reload()      re-fetch an .ajax container
//   $(btn).activate()        mark active among siblings

const $ = window.$

// rotate wobble, ported from the apps' Zepto $.fn.shake
$.fn.shake = function (interval = 150) {
  this.css('transition', `all 0.${interval}s`)
  ;['-10deg', '10deg', '-5deg', '5deg', '-2deg', '0deg'].forEach((deg, i) =>
    setTimeout(() => this.css('transform', `rotate(${deg})`), interval * i))
  return this
}

$.fn.focus = function () { return this.each(function () { this.focus?.() }) }
$.fn.blur = function () { return this.each(function () { this.blur?.() }) }

// fire a cancelable submit event, then native-submit if not prevented (Zepto-style)
$.fn.submit = function () {
  const f = this[0]
  if (f) f.requestSubmit ? f.requestSubmit() : f.submit()
  return this
}

// disable a button: gray it out, swallow clicks, append a spinner (undo with .enable())
$.fn.disable = function () {
  return this.each(function () {
    $(this).addClass('btn-disabled')
    this.oldclick = this.onclick
    this.onclick = e => { e.stopPropagation(); e.preventDefault() }
    this.innerHTML += ' <ui-icon name="spinner"></ui-icon>'
  })
}

// undo .disable(): restore the click handler and remove the spinner icon
$.fn.enable = function () {
  return this.each(function () {
    const el = $(this)
    el.removeClass('btn-disabled')
    el.find('svg.icon').remove()
    if (this.oldclick) this.onclick = this.oldclick
  })
}

// focus the first element and move the caret to the end (re-set value trick)
$.fn.xfocus = function () {
  const el = this.first()
  if (!el[0]) return this
  setTimeout(() => {
    const v = el.val()
    el.focus()
    el.val(v + ' ')
    el.val(v)
  }, 10)
  return this
}

// reload an .ajax container's content from its path (running any inline scripts).
//   $('#tasks-list').reload()           // path from the node's data-path/path attr
//   $('#dialog').reload('/c/cts/show')  // explicit path
$.fn.reload = function (path, func) {
  if (typeof path == 'function') { func = path; path = null }

  let ajaxNode = this.parents('.ajax').first()
  if (!ajaxNode[0]) ajaxNode = this

  path ||= ajaxNode.attr('data-path') || ajaxNode.attr('path') || location.pathname + location.hash
  const nodeId = ajaxNode.attr('id')
  ajaxNode.attr('path', path)

  $.get(path, data => {
    const fresh = $(`<div>${data}</div>`)
    const html = nodeId ? fresh.find('#' + nodeId).html() : fresh.find('.ajax').html()
    if (html) data = html
    ajaxNode.html($.parseScripts(data))
    if (func) func(data)
  })
  return this
}

// activate one element among its siblings: drop klass from siblings, add to this
//   $('.tab-title-2').activate()          // default 'active'
//   $(btn).activate('btn-primary')
$.fn.activate = function (klass = 'active') {
  const target = this[0]
  if (target) {
    $(target.parentNode).children().removeClass(klass)
    $(target).addClass(klass)
  }
  return this
}

// run func(selection) every `every` ms; auto-stops once the node leaves the DOM,
// so pjax navigations don't leak intervals. Clears a prior interval on re-init.
//   $('#top-bg').setInterval((n) => n.css('height', h), 200)
$.fn.setInterval = function (func, every) {
  return this.each(function () {
    const node = this, el = $(this)
    clearInterval(node.__fnInterval)
    node.__fnInterval = setInterval(() => {
      if (!document.body.contains(node)) return clearInterval(node.__fnInterval)
      func(el)
    }, every)
  })
}

// drag-to-pan horizontal scroll on an overflow block (e.g. a wide <pre>)
$.fn.pannableBlock = function () {
  return this.each(function () {
    const el = $(this)
    let isDown = false, startX = null, scrollLeft = null
    el.on('mousedown', (e) => {
      isDown = true
      startX = e.pageX - el.offset().left
      scrollLeft = el.scrollLeft()
      el.css('cursor', 'move')
    })
    el.on('mousemove', (e) => {
      if (!isDown) return
      e.preventDefault()
      const x = e.pageX - el.offset().left
      el.scrollLeft(scrollLeft - (x - startX))
      document.body.classList.add('no-select')
    })
    $(document).on('mouseup', () => {
      isDown = false
      el.css('cursor', 'default')
      document.body.classList.remove('no-select')
    })
  })
}
