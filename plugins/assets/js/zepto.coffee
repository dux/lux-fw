# $.createFunction
  # const str = "(arg1, arg2) => alert(arg1 + arg2)";
  # const argsStart = str.indexOf("(");
  # const argsEnd = str.indexOf(")");
  # const args = str.substring(argsStart + 1, argsEnd).split(",").map(arg => arg.trim());
  # const bodyStart = str.indexOf("=>") + 2;
  # const body = str.substring(bodyStart).trim();
  # const func = new Function(...args, body);
  # func(10, 20);

# if location.port
#   window.alert = function(e){ console.warn( "Alerted: " + e ); }

Array.range = (min, max) ->
  @apply(null, @(max - min + 1)).map((i,j) => j + min)

Array.prototype.xpush = (el) ->
    @push el
    @

window.Z = $
window.ZZ = (nodeId) =>
  if typeof nodeId == 'string'
    nodeId = '#' + nodeId unless nodeId.includes('#')
    Z(nodeId)
  else
    nodeId

window.LOG = (what...) =>
  if location.port
    # console.warn what
    what = what[0] if what.length < 2
    # console.log what.constructor.name
    json = JSON.stringify(what, null, 2)
    if window.NO_CACHE
      console.log('Called from: ' + (new Error()).stack.split("\n")[2].trim().split(" ")[1])
    if ['Array', 'Object'].includes(what?.constructor.name)
      console.log(json)
    else
      console.log(what)

    """<xmp style="font-size: 14px;">#{json}</xmp>"""

window.XMP = (what) =>
  data = JSON.stringify(what, null, 2)
  "<xmp style='font-size: 0.9rem; line-height: 1.1rem; padding: 5px; border: 1px solid #ccc; background: #fff;'>#{data}</xmp>"

window.xalert = (message) ->
  try
    throw new Error(message)
  catch e
    stackLines = e.stack.split('\n')
    callerLine = stackLines[2] # Adjust the index as needed based on your project's call stack structure
    alert "#{callerLine.trim()}\n\n#{message}"

# loadResource 'https://cdnjs.cloudflare.com/some/min.css'
# loadResource css: 'https://cdnjs.cloudflare.com/some/min.css'
loadResource = (src, type) ->
  if typeof src == 'string'
    type ||= if src.includes('.css') then 'css' else 'js'
  else
    if src.css
      src = src.css
      type = 'css'
    else if src.js
      src = src.js
      type = 'js'
    else if src.img
      src = src.img
      type = 'img'
    else if src.module
      src = src.module
      type = 'module'

  id = 'res-' + src.replace(/^https?/, '').replace(/[^\w]+/g, '')

  unless document.getElementById(id)
    if type == 'css'
        node = document.createElement('link')
        node.id = id
        node.setAttribute 'rel', 'stylesheet'
        node.setAttribute 'type', 'text/css'
        node.setAttribute 'href', src
        document.getElementsByTagName('head')[0].appendChild node
    else if ['js', 'module'].includes(type)
        node = document.createElement('script')
        node.id    = id
        node.async = 'async'
        node.crossOrigin = 'anonymous'
        node.src   = src
        node.type = 'module' if type == 'module'
        document.getElementsByTagName('head')[0].appendChild node
    else if type == 'img'
        node.id = id
        node = document.createElement('img')
        node.src = src
    else
      alert "Unsupported type (#{type})"

#

Z.isTrue = (v) -> v && String(v) != 'false'

# Z.slice({foo: 123, style: 'nice'}, 'width', 'style', 'class')
Z.slice = (data, ...args) ->
  out = {}
  for key in args
    val = data[key]
    out[key] = val if val != undefined
  out

$.delete = (data, key) =>
  v = data[key]
  delete data[key]
  v

$.compact = (data, opts = {}) =>
  if Array.isArray(data)
    data.filter (el) ->
      ![undefined, null, 'undefined', ''].includes(el)
  else
    out = {}
    Object.entries(data).forEach ([k, v]) ->
      if !k.includes('$') && ![undefined, null, 'undefined', ''].includes(v)
        k = k.toLowerCase() if opts.toLowerCase
        out[k] = v
    out

$.css = (data) ->
  if typeof data == 'object'
    out = Object.entries(data).map ([k,v]) =>
      v = if typeof v == 'string' then v else "#{Math.round(v)}px"
      "#{k}: #{v};"
    out.join(' ')
  else
    data.split(';').reduce((objeect, line) ->
      [key, value] = line.trim().split(':')
      objeect[key.trim()] = value.trim() if value
      objeect
    , {})

$.qs = (data) ->
  if typeof data == 'object'
    Object.entries(data).map(([k,v]) => "#{k}=#{encodeURIComponent(v)}").join('&')
  else
    data.split('&').reduce((objeect, line) ->
      [key, value] = line.trim().split('=')
      objeect[key.trim()] = decodeURIComponent value.trim() if value
      objeect
    , {})


$.JSON = (data) ->
  if data
    if typeof data == 'string'
      JSON.parse(data)
    else
      data

$.prompt = (q, v, func) ->
  r = prompt q, v || ''
  func(r) if typeof r == 'string'

$.capitalize = (str) ->
  str.charAt(0).toUpperCase() + str.slice(1)

$.tag = (nodeName, attrs) ->
  attrStr = Object.keys(attrs)
    .filter (key) -> attrs[key] != undefined
    .map (key) -> "#{key}='#{attrs[key]}'"
    .join(' ')

  if ['img', 'input', 'link', 'meta'].includes(nodeName)
    "<#{nodeName} #{attrStr} />"
  else
    "<#{nodeName} #{attrStr}></#{nodeName}>"

$.eval = (...args) ->
  if str = args.shift()
    # str = "()=>{render(#{str})}" unless str[0] == '('
    # params = str.match(/\((.*?)\)/)[1]
    # alert params
    func = if typeof str == 'string' then eval "(#{str})" else str
    func(args...) if typeof func == 'function'

$.fnv1 = (str) ->
  FNV_OFFSET_BASIS = 2166136261
  FNV_PRIME = 16777619

  hash = FNV_OFFSET_BASIS

  for i in [0..str.length - 1]
    hash ^= str.charCodeAt(i)
    hash *= FNV_PRIME

  # Convert the hash to base 36
  hash.toString(36).replaceAll('-', '')

$.htmlSafe = (text) =>
  String(text).replaceAll('#LT;', '<').replaceAll('<script', '&lt;script')

$.imageSize = (url, callback) ->
  img = new Image()
  img.onload = () =>
    callback({w: img.naturalWidth, h: img.naturalHeight})
  img.src = url

ulidCounter = 0
$.ulid = (prefix) ->
  parts = [
    (new Date()).getTime(),
    String(Math.random()).replace('0.', ''),
    ++ulidCounter
  ]
  out = BigInt(parts.join('')).toString(36).slice(0, 20)
  if prefix then "#{prefix}-#{out}" else out

$.delay = (time, func) ->
  if !func
    func = time
    time = 10
  setTimeout func, time

# run until function returns true
# $.untilTrue('md5', () => { md5(key) })
# $.untilTrue(() => { if (window.md5) { md5(key); return true}})
$.untilTrue = (args...) ->
  if typeof args[0] == 'string'
    func = () ->
      if window[args[0]]
        args[1]()
        return true
    timeout = args[2]
  else
    func = args[0]
    timeout = args[1]

  timeout ||= 200
  unless func() == true
      setTimeout ->
        $.untilTrue func, timeout
      , timeout

# run until function returns true and node exists
$.untilTrueWhileExists = (node, func, timeout) ->
  $.untilTrue =>
    if node
      # console.log(node.checkVisibility(), document.body.contains(node))
      return true unless document.body.contains(node)
      if node.checkVisibility()
        return true if func()
  , timeout

# capture key press unless in forms
$.keyPress = (key, func) ->
  $(document).keydown (e) ->
    # console.log([e.keyCode, e.key])

    return if e.target.nodeName == 'INPUT'
    return if $(e.target).parents('form')[0]

    if key.includes('+')
      [base, part] = key.split('+', 2)
      return unless e.ctrlKey || e.metaKey
    else
      part = key

    if e.key == part
      $(e).cancel()
      func e

# clear timeout and postopne execution of a function
# like for autocomplete
# $.debounce 'foo-1', -> ...
# $.debounce 'foo-1', 500, -> ...
$._debounce_hash = {}
$.debounce = (uid, delay, callback) ->
  if typeof delay == 'function'
    callback = delay
    delay = 10

  if $._debounce_hash[uid]
    clearTimeout $._debounce_hash[uid]

  $._debounce_hash[uid] = setTimeout(callback, delay)

# throttle but runes one last tick at the end (window, resize)
# can be used instead of debounce to get some emidiate response
$.throttle = (func, delay) ->
  prev = 0
  delayed = null
  (...args) ->
    now = new Date().getTime()
    diff = now - prev
    if diff > delay
      prev = now
    else
      clearTimeout delayed
      delayed = setTimeout(
        ()=>func(...args)
      , delay - diff)

$.memoize = (fn) ->
  cache = {}
  (...args) ->
    cache_id = $.fnv1 String(args)
    cache[cache_id] ||= fn(...args)

# for ajax search, will cache results
$._cached_get = {}
$.cachedGet = (url, func) ->
  if data = $._cached_get[url]
    func data
  else
    $.debounce 'cached-get', 200, ->
      $.get url, (data) ->
        func(data)
        $._cached_get[url] = data

# insert script in the head
$.getScript = (src, check, func) ->
  if func && typeof check == 'string'
    check = new Function "return !!window['#{check}']"

  unless func
    func = check
    check = null

  if src.forEach
    for el in src
      loadResource el
  else
    loadResource src

   if check
    $.untilTrue =>
      if check()
        func()
        true
   else if func
    func()

# insert script module in the head
# $.loadModule('https://cdn.skypack.dev/easymde', 'EasyMDE', ()=>{
#   let editor = new EasyMDE({
$.loadModule = (src, import_gobal, on_load) ->
  module_id = "header_module_#{$.fnv1(src)}"

  unless document.getElementById(module_id)
    script = document.createElement('script')
    script.id   = module_id
    script.type = 'module'
    script.innerHTML = """
      import mod from '#{src}';
      window.#{import_gobal} = mod;
    """
    document.getElementsByTagName('head')[0].appendChild script

  if on_load
    $.untilTrue import_gobal, () =>
      on_load()

  src

# parse and execute nested <script> tags
# we need this for example in svelte, where template {@html data} does nor parse scripts
$.parseScripts = (html) ->
  tmp = document.createElement 'DIV'
  tmp.innerHTML = html

  for script_tag in tmp.getElementsByTagName('script')
    continue if script_tag.getAttribute('src') || !script_tag.innerText
    type = script_tag.getAttribute('type') || 'javascript'

    if type.indexOf('javascript') > -1
      try
        f = new Function script_tag.innerText
        f()
        script_tag.innerText = '1;'
      catch e
        console.error(e)
        alert "JS error: #{e.message}"


  tmp.innerHTML

# return child nodes as list of hashes
$.nodesAsList = (root, as_hash) ->
  list = []

  return list unless root

  if typeof root == 'string'
    node = document.createElement("div")
    node.innerHTML = root
    root = node

  root.childNodes.forEach (node, i) ->
    if node.attributes
      o = {}
      o.NODENAME = node.nodeName
      o.HTML = node.innerHTML
      o.OUTER = node.outerHTML
      o.ID = i + 1

      for a in node.attributes
        o[a.name] = a.value

      list.push o

  if as_hash
    out = {}
    for el in list
      out[el.NODENAME] ||= []
      out[el.NODENAME].push el
    out
  else
    list

$.cookies =
  get: (name) ->
    list = {}

    for line in document.cookie.split("; ")
      [key, value] = line.split('=', 2)

      if key == name
        return value
      else
        list[key] = value

    list

  set: (name, value, days) ->
    date = new Date()
    date.setTime date.getTime() + ((days || 7) * 24 * 60 * 60 * 1000)
    expires = "; expires=" + date.toGMTString()
    document.cookie = name + "=" + value + expires + "; path=/"

  delete: (name) ->
    setCookie name, "", -1

# copies text to clipboard
$.copyText = (str) ->
  # node? pass refrence to table, to copy table
  if typeof str == 'function'
    if window.navigator
      navigator.clipboard.readText().then(str)
    else
      console.error 'You are not on localhost of HTTPS'
    return

  if typeof str != 'string'
    str = $(str)[0].innerText.trim()

  el = document.createElement('textarea')
  el.value = str
  document.body.appendChild(el)
  el.select()
  document.execCommand('copy')
  document.body.removeChild(el)

$.noCacheGet = (path, func) ->
  $.ajax
    type: 'get'
    url: path
    headers: { 'cache-control': 'no-cache' }
    success: func

# run fuction only once
$.once_hash = {}
$.once = (name, func) ->
  if $.once_hash[name]
    false
  else
    $.once_hash[name] = true
    func()
    true

$.resizeIframe = (obj) ->
  obj.style.height = obj.contentWindow.document.documentElement.scrollHeight + 'px';

$.d = (obj) ->
  JSON.stringify obj, null, 2

$.simpleEncodeBase = (str) -> # base64 then rot13
  str.replace /[a-zA-Z]/g, (c) ->
    charCode = c.charCodeAt(0)
    baseCharCode = if c >= 'a' then 'a'.charCodeAt(0) else 'A'.charCodeAt(0)
    String.fromCharCode(baseCharCode + ((charCode - baseCharCode + 13) % 26))

$.simpleEncode = (str) -> # base64 then rot13
  $.simpleEncodeBase btoa(str).replaceAll('/', '_').replace(/=+$/, '')

$.simpleDecode = (encodedStr) ->
  atob $.simpleEncodeBase encodedStr.replace(/_/g, '/')

$._setInterval = {}
$.setInterval = (name, func, every) ->
  clearInterval $._setInterval[name]
  $._setInterval[name] = setInterval func, every

$.scrollToBottom = (goNow) ->
  if goNow == true
    window.scrollTo({ top: document.body.scrollHeight, left: 0, behavior: 'smooth' })
  else
    setTimeout () =>
      window.scrollTo({ top: document.body.scrollHeight, left: 0, behavior: 'smooth' })
    , goNow || 300

$.random = (list) ->
  list[Math.floor(Math.random() * list.length)]

# top bar save info
$.saveInfo = () ->
  data = """<div id="loader-bar">
    <style>
      .loader-bar {
        position: fixed;
        top: 0px;
        left: 0px;
        width: 0px;
        height: 3px;
        background-color: #8198cd;
        animation: loader-bar-fill 0.5s cubic-bezier(0.23, 1, 0.32, 1) forwards;
      }

      @keyframes loader-bar-fill {
        0% {
          width: 0;
        }
        60% {
          width: 50%;
        }
        100% {
          width: 100%;
        }
      }
    </style>
    <div class="loader-bar"></div>
  </div>"""

  $(document.body).append(data)
  $.delay(500, () => $('#loader-bar').remove() )

$.svelteNode = (name, opts) ->
  un_name = name.replaceAll '-', '_'
  up_name = name.replaceAll '_', '-'
  if S[un_name]
    """<script type="template">#{JSON.stringify(opts)}</script><s-#{up_name} data-json-template="true"></s-#{up_name}>"""
  else
    alert("Svelte component [#{up_name}] not defined")

$.times = (num, func) ->
  out = []
  for i in [0...num]
    out.push func(i)
  out

# node functions

# https://svelte.dev/repl/225254b125754b7782534670815cde27
$.fn.animateInsert = (html) ->
  if node = @[0]
    html = node.innerHTML if html == undefined

    node.style.transition ||= 'all .3s ease-out';
    node.style.overflow = 'hidden'
    node.style.height ||= 'auto'

    if node.oldHtmlCache != html
      node.oldHtmlCache = html

      # if we want to animate reduction of html, we need tmp node
      test = document.createElement('div')
      test.style.height = '0px'
      test.innerHTML = html
      node.insertAdjacentElement('afterend', test)
      node.innerHTML = html

      window.requestAnimationFrame ->
        node.style.height = test.scrollHeight + 'px'
        test.parentNode.removeChild(test)

$.fn.slideDown = (duration) ->
  @show()
  height = @height()
  @css height: 0
  @animate { height: height }, duration

$.fn.slideUp = (duration) ->
  target = this
  height = @height()
  @css height: height
  @animate { height: 0 }, duration, '', ->
    target.css
      display: 'none'
      height: ''

$.fn.slideToggle = (duration) ->
  if @css('display') == 'none'
    $(@).slideDown()
  else
    $(@).slideUp()

# https://svelte.dev/repl/4edf94c1d3f24fb0a7d86670f194cefb
$.fn.toggleMaxHeight = ->
  if node = @[0]
    node.style.transition ||= "max-height 0.2s ease-out"
    node.style.overflow = 'hidden'

    window.requestAnimationFrame =>
      if @css('max-height') == '0px'
        @addClass 'is-open'
        node.style.maxHeight = "#{node.scrollHeight}px"
      else
        @removeClass 'is-open'
        node.style.maxHeight = '0px'

# $('form#foo').serializeHash()
$.fn.serializeHash = ->
  hash = {}

  $(this).find('input, textarea, select').each ->
    if @name and !@disabled
      val = $(@).val()
      val = 0 if @type == 'checkbox' and !@checked
      hash[@name] = val

  hash

# $('form#foo').ajaxSubmit((response) { ... })
$.fn.ajaxSubmit = (callback)->
  form = $(this)
  $.ajax
    type: (form.attr('method') || 'get').toUpperCase()
    url: form.attr 'action'
    data: form.serializeHash()
    headers:
      'x-tz-name': Intl.DateTimeFormat().resolvedOptions().timeZone if window.Intl
    complete: (r) =>
      data = r.responseText
      data = JSON.parse(data) if r.getResponseHeader('content-type').toLowerCase().includes('json')
      callback(data, r) if callback

# execute func if first element found
$.fn.xfirst = (func) ->
  el = undefined
  el = $(this).first()
  if el
    func(el)

# better focus, cursor at the end of the input
# $('input[name=q]').xfocus()
$.fn.xfocus = ->
  setTimeout =>
    $(this).xfirst (el) ->
      value = undefined
      value = el.val()
      el.focus()
      el.val value + ' '
      el.val value
    , 10

# load URL and replace content under specific ID
# executes scripts found in a page
# load path into node
#   $('#dialog').reload('/c/cts/show_dialog')
# load path from attribute
#   #dialog{ path: '...' }
#   $('#dialog').reload() -> path in attribute
# refresh full page and replace only target element
#   $('#dialog').reload() -> path in attribute
$.fn.reload = (path, func) ->
  if typeof path == 'function'
    func = path
    path = null

  ajax_node = @parents('.ajax').first()
  ajax_node = @ unless ajax_node[0]

  path  ||= ajax_node.attr('data-path') || ajax_node.attr('path') || location.pathname + location.hash

  node_id = ajax_node.attr('id')
  ajax_node.attr('path', path)

  $.get path, (data) =>
    new_node = $("""<div>#{data}</div>""")
    if node_id
      if html = new_node.find('#'+node_id).html()
        data = html
    else
      if html = new_node.find('.ajax').html()
        data = html

    data = $.parseScripts data
    ajax_node.html(data)
    func(data) if func

# stop event propaation from a node
$.fn.cancel = ->
  e = @[0]
  if e.preventDefault
    e.preventDefault()
    e.stopPropagation()
  else if window.event
    window.event.cancelBubble = true

# searches for parent %ajax node and refreshes with given url
# node has to have path or ID
# $(this).ajax('/cell/post/preview/post_id:8/site_id:4/edit:true', '/dashboard/posts/czr/edit:true')
$.fn.ajax = (path, path_state) ->
  node = if @hasClass('ajax') then @ else @parents('.ajax')
  id = @attr('id')

  if id && node[0]
    path ||= @attr('path') || @attr('data-path')
    path ||= location.pathname + String(location.search)
    node.attr('data-path', path) if path

    $.get path, (data) =>
      html = $("<div>#{data}</div>").find("##{id}").html() if id
      html ||= data
      node.html html

  else
    $.get path, (data) => @.html(data)

  # set new path state, so back can work in browsers
  if path_state
    if path_state[0] == '?'
      path_state = location.pathname + path_state

    window.history.pushState({ title: document.title }, document.title, path_state)

$.fn.shake = (interval = 150) ->
  @addClass 'shaking'
  @css 'transition', "all 0.#{interval}s"
  setTimeout (=>@css('transform', 'rotate(-10deg)')), interval * 0
  setTimeout (=>@css('transform', 'rotate(10deg)')), interval * 1
  setTimeout (=>@css('transform', 'rotate(-5deg)')), interval * 2
  setTimeout (=>@css('transform', 'rotate(5deg)')), interval * 3
  setTimeout (=>@css('transform', 'rotate(-2deg)')), interval * 4
  setTimeout (=>@css('transform', 'rotate(0deg)')), interval * 5
  @removeClass 'shaking'

$.fn.isVisible = () -> @[0] && @[0].checkVisibility()

# to animate image height, css transition has to be set, and you have to have starting height
$.fn.animateHeight = (height) ->
  img = @[0]

  if height
    img.style.height = "#{height}px"
    @.on 'load', -> $(img).animateHeight()
  else
    width = img.width
    aspect = img.naturalWidth / img.naturalHeight
    img.style.height = (width / aspect) + 'px'

    # reset height at end because we want natural resizeing to work
    setTimeout ->
      img.style.height = 'auto'
    , 1500

# node kind aware show
$.fn.show = ->
  for n in @
    kind =
      SPAN: 'inline-block'
      TABLE: 'table'
      TR: 'table-row'
      TD: 'table-cell'
    n.style.display = kind[n.nodeName] || 'block'

# activate target node in list, remove active from other nodes
# $('ul li-2').activate('active')
# <ul>
#   <li class="li-1 active">
#   <li class="li-2">
$.fn.activate = (klass = 'active') ->
  if target = @[0]
    $(target.parentNode).find('& > *').removeClass klass
    $(target).addClass klass

# $.fn.onDestroy = ->
#   for n in @


# simple pub sub, node aware. when node is removed, no sub trigger
# global publish, and global + node subscribe
PUB_SUB = {}
$.pub = (name, ...args) ->
  if list = PUB_SUB[name]
    PUB_SUB[name] = list.filter (el) =>
      if typeof el == 'object'
        if el.n.parentNode
          el.f(...args)
          true
      else
        el(...args)
        true
  null

$.sub = (name, func) ->
  PUB_SUB[name] ||= []
  PUB_SUB[name].push(func)
  null

$.fn.sub = (name, func) ->
  if this[0]
    unless this[0].nodeName
      console.error 'Not a DOM node given for sub', this[0]

    PUB_SUB[name] ||= []
    PUB_SUB[name].push({n: this[0], f: func})
    @

window.escapeHTML = (text) ->
  text
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');

# drag and pan horizontally scrollable block
$.fn.pannableBlock = ->
  @each ->
    el = $(@)
    isDown = false
    startX = null
    scrollLeft = null

    el.on 'mousedown', (e) ->
      isDown = true
      startX = e.pageX - el.offset().left
      scrollLeft = el.scrollLeft()
      el.css 'cursor', 'move'

    el.on 'mousemove', (e) ->
      return unless isDown
      e.preventDefault()
      x = e.pageX - el.offset().left
      walk = (x - startX) * 1
      el.scrollLeft(scrollLeft - walk)
      document.body.classList.add 'no-select'

    $(document).on 'mouseup', ->
      isDown = false
      el.css 'cursor', 'default'
      document.body.classList.remove 'no-select'
