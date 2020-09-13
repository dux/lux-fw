$.delay = (time, func) ->
  if !func
    func = time
    time = 10
  setTimeout func, time

# run until function returns true
$.untilTrue = (func) ->
  unless func()
    $.delay 100, func

# capture key press unless in forms
$.keyPress = (key, func) ->
  $(document).keydown (e) ->
    return if e.code != key
    return if e.target.nodeName == 'INPUT'
    return if $(e.target).parents('form')[0]
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

# insert script in the head
$.getScript = (src, func) ->
  # if $("script[src='#{src}']").length > 0
  #   func()
  # else
  script = document.createElement('script')
  script.async  = 'async'
  script.src    = src
  script.onload = func if func
  document.getElementsByTagName('head')[0].appendChild script

# parse and execute nested <script> tags
$.parseScripts = (html) ->
  tmp = document.createElement 'DIV'
  tmp.innerHTML = html

  for script_tag in tmp.getElementsByTagName('script')
    next if script_tag.getAttribute('src') || !script_tag.innerText
    type = script_tag.getAttribute('type') || 'javascript'
    if type.indexOf('javascript') > -1
      f = new Function script_tag.innerText
      f()

# return child nodes as list of hashes
$.nodesAsList = (root) ->
  list = []

  if typeof root == 'string'
    node = document.createElement("div")
    node.innerHTML = root
    root = node

  root.childNodes.forEach (node, i) ->
    if node.attributes
      o = {}
      o.HTML = node.innerHTML
      o.OUTER = node.outerHTML
      o.ID = i + 1

      for a in node.attributes
        o[a.name] = a.value

      list.push o

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

#

$.fn.node_id = ->
  unless window._node_id_cnt
    window._node_id_cnt = 0
  unless @attr('id')
    @attr 'id', 'jsapp_uid_' + ++window._node_id_cnt
  @attr 'id'

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

$.fn.serializeHash = ->
  hash = {}

  $(this).find('input, textarea, select').each ->
    if @name and !@disabled
      val = $(@).val()
      val = 0 if @type == 'checkbox' and !@checked
      hash[@name] = val

  hash

# execute func if first element found
$.fn.xfirst = (func) ->
  el = undefined
  el = $(this).first()
  if el
    func(el)

# better focus, cursor at the end of the input
# $('input[name=q]').xfocus()
$.fn.xfocus = ->
  $.delay =>
    $(this).xfirst (el) ->
      value = undefined
      value = el.val()
      el.focus()
      el.val value + ' '
      el.val value

# load URL and replace content under specific ID
# executes scripts found in a page
# $('#card-dialog-main').reload('/c/cts/show_dialog')
$.fn.reload = (path) ->
  node_id = this.attr('id') || alert('Error: ID not defined');

  $.get path, (data) =>
    $.parseScripts data
    data = $("""<div>#{data}</div>""").find("##{node_id}").html()
    this.html(data)

  "Node ##{node_id} reloaded from '#{path}'"
