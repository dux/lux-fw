# Pjax will replace only contents of MAIN HTML tag
# HTML <main> Tag
# https://www.w3schools.com/tags/tag_main.asp

# How to use?

# Pjax.load('/some/page', opts)
# Pjax.refresh()
# Pjax.refresh('#some-node')
# Pjax.useViewTransition = true -> use viewTransition if supported

# Pjax.error = (msg) -> Info.error msg
# Pjax.before ->
#   Dialog.close()
#   InlineDialog.close()
# Pjax.after ->
#   Dialog.close() if window.Dialog
# Pjax.load('/users/new', no_history: bool, no_scroll: bool, done: ()=>{...})

# to refresh link in container, pass current node and have ajax node ready, with id and path
# .ajax{ id: :foo, path: '/some_dialog_path' }
#   ...
#   .div{ onclick: Pjax.load('?q=search_term', node: this) }

# opts: {
#   path: what path to load
#   replacePath: path to replace path with (on ajax state change, to have back button on different path)
#   done: function to execute on done
#   target: dom node to refresh
#   form: pass form attriutes
#   ajax: ajax dom node to refresh, finds closest
#   scroll: set to false if you want to have no scroll (default for Pjax.refresh)
#   history: set to false if you dont want to add state change to history
#   cache: set to false if you want to force no-cache header
# }

window.Pjax = class Pjax
  @config = {
    # shoud Pjax log info to console
    is_silent : parseInt(location.port) < 1000,

    # do not scroll to top, use refresh() and not reload() on node with selectors
    no_scroll_selector : ['.no-scroll'],

    # skip pjax on followin links and do location.href = target
    # you can add function, regexp of string (checks for starts with)
    paths_to_skip : [],

    # if link has any of this classes, Pjax will be skipped and link will be followed
    # Example: %a.direct{ href '/somewhere' } somewhere
    no_pjax_class : ['no-pjax', 'direct'],
    no_ajax_class : ['ajax-skip', 'skip-ajax', 'no-ajax', 'top']

    # if parent id found with ths class, ajax response data will be loaded in this class
    # you can add ID for better targeting. If no ID given to .ajax class
    #  * if response contains .ajax, first node found will be selected and it innerHTML will be used for replacement
    #  * if there is no .ajax in response, full page response will be used
    # Example: all links in "some_template" will refresh ".ajax" block only
    # .ajax
    #   = render 'some_template'
    ajax_selector  : '.ajax',
  }

  @historyData = {}

  # you have to call this if you want to capture clicks on document level
  # Example: Pjax.onDocumentClick()
  @onDocumentClick: ->
    document.addEventListener 'click', PjaxOnClick.main

  # base class method to load page
  # istory: bool
  # scroll: bool
  # cache: bool
  # done: ()=>{...}
  @load: (href, opts) ->
    opts = @getOpts href, opts
    @fetch(opts)

  # refresh page, keep scroll
  @refresh: (func, opts) ->
    if typeof func == 'string' && func[0] == '#'
      opts ||= {}
      opts.target = func
      func = Pjax.path()
      # opts.href = Pjax.lastHref # if we want to refresh inline dialogs, s-ajax will set Pjax.lastHref and this will work
      opts.history = false

    opts = @getOpts func, opts
    opts.scroll ||= false
    # opts.cache ||= false

    @fetch(opts)

  # reload, jump to top, no_cache http request forced
  @reload: (opts) ->
    opts = @getOpts opts
    opts.cache ||= false
    @fetch(opts)

  @refreshed: ->
    return false unless @pastHref
    @pastHref == @lastHref

  # normalize options
  @getOpts = (path, opts) ->
    opts ||= {}

    if typeof(path) == 'object'
      if path.nodeName
        opts.ajax = path
      else
        opts = path
    else if typeof(path) == 'function'
      opts.done = path
    else
      opts.path = path

    if opts.href
      opts.path = opts.href
      delete opts.href

    opts.path ||= @path()

    if opts.form
      for key, value of Z(opts.form).serializeHash()
        opts.path += if opts.path.includes('?') then '&' else '?'
        opts.path += "#{key}=#{encodeURIComponent(value)}"

    if opts.ajax
      opts.node = opts.ajax
      opts.node = document.querySelector(opts.node) if typeof opts.node == 'string'

      skip_ajax = false
      for el in @config.no_ajax_class
        skip_ajax = true if opts.ajax.closest(".#{el}")

      unless skip_ajax
        if ajax_node = opts.node.closest(Pjax.config.ajax_selector)
          opts.ajax_node = ajax_node
          opts.scroll ||= false

      delete opts.ajax

    if opts.target
      if typeof opts.target == 'string'
        opts.target = document.querySelectorAll(opts.target)[0]
      opts.node = opts.target
      opts.scroll ||= false

    if opts.path[0] == '?'
      # if href starts with ?
      if opts.ajax_node
        # and we are in ajax node
        ajax_path = opts.ajax_node.getAttribute('data-path') || opts.ajax_node.getAttribute('path')

        if ajax_path
          # and ajax path is defined, use it to create full url
          opts.path = ajax_path.split('?')[0] + opts.path

      if opts.path[0] == '?'
        # if not modified, use base url
        opts.path = location.pathname + opts.path

    if opts.replacePath
      if opts.replacePath[0] == '?'
        opts.replacePath = location.pathname + path

    opts

  @fetch: (opts) ->
    pjax = new Pjax(opts)
    pjax.load()

  # used to get full page path
  @path: ->
    location.pathname+location.search

  @node: ->
    document.getElementsByTagName('pjax')[0] || document.getElementsByClassName('pjax')[0] || alert('.pjax or #pjax not found')

  @console: (msg) ->
    unless @config.is_silent
      console.log msg

  # execute action before pjax load and do not proceed if return is false
  # example, load dialog links inside the dialog
  # Pjax.before (href, opts) ->
  #   if opts.node
  #     if opts.node.closest('.in-popup')
  #       Dialog.load href
  #       return false
  #   true
  @before: () ->
    true

  # execute action after pjax load
  @after: () ->
    true

  # error logger, replace as fitting
  @error: (msg) ->
    console.error "Pjax error: #{msg}"

  @parseSingleScript: (id, img) ->
    img.remove()
    if node = document.getElementById(id)
      func = new Function node.innerText
      func()
      node.text = 1

  @parseScripts: (node) ->
    if typeof node == 'string'
      duplicate = node
      node = document.createElement "span"
      node.innerHTML = duplicate

    for script_tag in node.getElementsByTagName('script')
      if script_tag
        unless script_tag.getAttribute('src')
          type = script_tag.getAttribute('type') || 'javascript'

          if type.indexOf('javascript') > -1
            unless script_tag.id
              @script_cnt ||= 0
              script_tag.id = "app-sc-#{++@script_cnt}"

            script_data = script_tag.textContent
            if script_tag.getAttribute('delay') || script_data.includes('// DELAY')
              # if delay, script will be executed once the dom is mounted
              # this hack is make inline execution work, like it works in browsers on initial load, seqential
              # after every script tag, add emppty png img that onload points to script, parse script
              span = document.createElement "span"
              span.innerHTML = """<img style="display: none;" src="data:image/gif;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==" onload="Pjax.parseSingleScript('#{script_tag.id}', this)" />"""
              script_tag.after span
            else
              func = new Function(script_data)
              func()
              script_tag.text = 1

    node.innerHTML

  # internal
  @noScrollCheck: (node) ->
    return unless node && node.closest

    for el in @config.no_scroll_selector
      return true if node.closest(el)

    false

  @last: ->
    @lastHref || @path()

  @sendGlobalEvent: ->
    document.dispatchEvent new CustomEvent('pjax:render')

  @pushState: (href) ->
    window.history.pushState({}, document.title, href);

  @push: (href) -> @pushState(href)

  # locks page scrolling to prevent jump to top of the page on refresh
  @scrollLock: (opts = {}) ->
    now = Date.now()
    return if @_scrollLockTime && now - @_scrollLockTime < 1000
    @_scrollLockTime = now

    scrollPosition = window.pageYOffset
    body = document.body
    body.style.height = window.getComputedStyle(body).height
    window.scrollTo(0, scrollPosition) # Forces exact position

    window.requestAnimationFrame =>
      body.style.height = ''
      window.scrollTo(0, scrollPosition) # Forces exact position again

  # prevert page flicker on refresh by fixing main node height
  @setPageBody: (node, href) ->
    title = node.querySelector('title')?.innerHTML
    document.title = title || 'no page title (pjax)'
    Pjax.scrollLock()
    pjaxNode = Pjax.node()
    if new_body = node.querySelector('#' + pjaxNode.id)
      # this has to be before data insert, because maybe we want to insert some JS that inserted nodes expect to be present
      # if you need to delay execution of some code untill html is inserted, use this
      #   window.requestAnimationFrame( ()=>...) ) or add comment // DELAY in inline js

      if Pjax.useViewTransition && document.startViewTransition
        document.startViewTransition () =>
          pjaxNode.innerHTML = Pjax.parseScripts(new_body)
      else
        pjaxNode.innerHTML = Pjax.parseScripts(new_body)

      # pjaxNode.innerHTML = Pjax.parseScripts(new_body)
      Pjax.after(href, @opts)
      Pjax.sendGlobalEvent()

  # sets or adds value to querystring
  # Pjax.qs('place', el.name, { push: true })
  @qs: (key, value, opts = {}) ->
    parts = location.search.replace(/^\?/, '').split('&').map (el) -> el.split('=', 2)

    if typeof value == 'undefined'
      parts.forEach (el) ->
        value = decodeURIComponent(el[1]) if el[0] == key
      value
    else
      qs = {}
      parts.forEach (el) ->
        qs[el[0]] = el[1] if el[0]

      qs[key] = encodeURIComponent value
      data = Object.keys(qs).map((key)=> "#{key}=#{qs[key]}").join('&')
      href = location.pathname + '?' + data

      if opts.push
        window.history.pushState({}, document.title, href) if opts.push
        Pjax.push href unless opts.mock
      else if opts.href
        href
      else
        Pjax.load href

  #

  constructor: (@opts) ->
    @href = @opts.href || @opts.path

  redirect: ->
    @href ||= location.href

    if @href[0] == 'h' && !@href.includes(location.host)
      # if page is on a foreign server, open it in new window
      window.open @href
    else
      location.href = @href

    false

  # load a new page
  load: ->
    return false unless @href

    # if Pjax.lastHref == @href && Pjax.lastTime && (new Date() - 1000) > Pjax.lastTime
    #   LOG 'skipped'
    #   return
    # else if Pjax.lastTime
    #   console.log Pjax.lastHref == @href, (new Date() - 1000) > Pjax.lastTime
    # else
    #   console.log 'lt', Pjax.lastTime

    # Pjax.lastTime = new Date()
    Pjax.pastHref = Pjax.lastHref
    Pjax.lastHref = @href

    # if ctrl or cmd button is pressed, open in new window
    if event && !event.key && (event.which == 2 || event.metaKey)
      return window.open @href

    if Pjax.before(@href, @opts) == false
      return

    if (location.hash && location.pathname == @href)
      return

    # handle %a{ href: '#top' } go to top
    if @href.startsWith('#')
      return if @href == '#'
      if node = document.querySelector("a[name=#{@href.replace('#', '')}]")
        node.scrollIntoView({behavior: 'smooth', block: 'start'});
        return false

    if /^http/.test(@href) || /#/.test(@href) || @is_disabled
      return @redirect()

    for el in Pjax.config.paths_to_skip
      switch typeof el
        when 'object' then return @redirect() if el.test(@href)
        when 'function' then return @redirect() if el(@href)
        else return @redirect() if @href.startsWith(el)

    @opts.req_start_time = (new Date()).getTime()
    @opts.path = @href

    headers = {}
    headers['cache-control'] = 'no-cache' if @opts.cache == false
    headers['x-requested-with'] = 'XMLHttpRequest'

    if Pjax.request
      Pjax.request.abort()

    Pjax.request = @req = new XMLHttpRequest()

    @req.onerror = (e) ->
      Pjax.error 'Net error: Server response not received (Pjax)'
      console.error(e)

    @req.open('GET', @href)
    @req.setRequestHeader k, v for k,v of headers

    @req.onload = (e) =>
      @response  = @req.responseText

      # console log
      time_diff = (new Date()).getTime() - @opts.req_start_time
      log_data  = "Pjax.load #{@href}"
      log_data += if @opts.history == false then ' (back trigger)' else ''
      Pjax.console "#{log_data} (app #{@req.getResponseHeader('x-lux-speed') || 'n/a'}, real #{time_diff}ms, status #{@req.status})"

      # if not 200, redirect to page to show the error
      if @req.status != 200
        @redirect()
      else
        # fix href because of redirects
        if rul = @req.responseURL
          @href = rul.split('/')
          @href.splice(0, 3)
          @href = '/' + @href.join('/')

        # inject response in current page and process if ok
        if @applyLoadedData()
          # trigger opts['done'] function
          @opts.done() if typeof(@opts.done) == 'function'

          # scroll to top of the page unless defined otherwise
          unless @opts.scroll == false || Pjax.noScrollCheck(@opts.node)
            window.requestAnimationFrame ->
              window.scrollTo({ top: 0, left: 0, behavior: 'smooth' })
          else
            Pjax.scrollLock()
        else
          # document.write @response is buggy and unsafe
          # do full reload
          @redirect()

    @req.send()

    false

  applyLoadedData: ->
    @pjaxNode = Pjax.node()

    unless @pjaxNode
      Pjax.error 'template_id mismatch, full page load (use no-pjax as a class name)'
      return

    unless @pjaxNode.id
      alert 'No ID attribute on pjax node'
      return

    @historyAddCurrent(@opts.replacePath || @href)

    @rroot = document.createElement('div')
    @rroot.innerHTML = @response

    if @opts.target
      if id = @opts.target.getAttribute('id')
        rtarget = @rroot.querySelector('#'+id)
        if rtarget
          Pjax.scrollLock()
          @opts.target.innerHTML = rtarget.innerHTML
          return true
      else
        alert('ID attribute not found on Pjax target')

    if ajax_node = @opts.ajax_node
      ajax_node.setAttribute('data-path', @href)
      ajax_node.removeAttribute('path')
      ajax_id = ajax_node.getAttribute('id') || alert('Pjax .ajax node has no ID')
      ajax_data = @rroot.querySelector('#'+ajax_id)?.innerHTML || @response
      ajax_node.innerHTML = Pjax.parseScripts(ajax_data)
      return true

    Pjax.historyData[Pjax.path()] = @response

    Pjax.setPageBody(@rroot, @href)

  # private

  # add current page to history
  historyAddCurrent: (href) ->
    return if @opts.history == false || (@opts.ajax_node && ! @opts.target)
    return if @history_added; @history_added = true

    if Pjax._lastHrefCheck == href
      window.history.replaceState({}, document.title, href);
    else
      window.history.pushState({}, document.title, href)
      Pjax._lastHrefCheck = href

# handle back button gracefully
window.onpopstate = (event) ->
  window.requestAnimationFrame ->
    path = Pjax.path()
    if hdata = Pjax.historyData[path]
      console.log "from history: #{path}"
      rroot = document.createElement('div')
      rroot.innerHTML = hdata
      Pjax.setPageBody(rroot, path)
    else
      Pjax.load path, history: false

PjaxOnClick =
  main: (event) ->
    # self or scoped href, as on %tr row element.
    # if you do not want parent onclick to trigger when using href, use "click" attribute on parent
    # %tr{ click: ""... }
    #   %td{ href: "/..." }
    if node = event.target.closest('*[click], *[href]')
      event.stopPropagation()
      event.preventDefault()

      if click = node.getAttribute('click')
        (new Function(click)).bind(node)()
      else
        href = node.getAttribute 'href'

        # to make it work onmouse dowm
        # node.onclick = () => false

        # %a{ href: '...' hx-target: "#some-id" } -> will refresh target element, if one found
        if hxTarget = node.getAttribute('hx-target')
          if hxNode = document.querySelectorAll(hxTarget)[0]
            Pjax.load href, target: hxNode
            return

        if href.slice(0, 2) == '//'
          href = href.replace '/', ''
          return window.open href

        # if ctrl or cmd button is pressed, open in new window
        if event.which == 2 || event.metaKey
          return window.open href

        # if direct link, do not use Pjax
        klass = ' ' + node.className + ' '
        for el in Pjax.config.no_pjax_class
          if klass.includes(" #{el} ")
            if /^http/.test(href)
              window.open(href)
            else
              return window.location.href = href

        # execute inline JS
        if /^javascript:/.test(href)
          func = new Function href.replace(/^javascript:/, '')
          return func()

        # disable bots
        # return if /bot|googlebot|crawler|spider|robot|crawling/i.test(navigator.userAgent)

        # if target attribute provided, open in new window
        if /^\w/.test(href) || node.getAttribute('target')
          return window.open(href, node.getAttribute('target') || href.replace(/[^\w]/g, ''))

        # if double slash start
        if /^\/\//.test(href)
          return window.open(window.location.origin + href.replace('/', ''), node.getAttribute('target') || href.replace(/[^\w]/g, ''))

        # if everything else fails, call Pjax
        Pjax.load href, ajax: node

        false

window.addEventListener 'DOMContentLoaded', () ->
  setTimeout(Pjax.sendGlobalEvent, 0)

  # <form action="/search" data-pjax="true"> -> refresh full page
  # <form action="/search" data-pjax="#search"> -> refresh search block only
  document.body.addEventListener 'submit', (e) ->
    form = e.target
    if is_pjax = form.getAttribute('data-pjax')
      e.preventDefault()
      target = if is_pjax == 'true' then null else target
      Pjax.load form.getAttribute('action'), form: form, target: target
  , once: true
