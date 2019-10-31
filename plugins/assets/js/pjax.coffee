# How to use?

# Pjax will replace only contents of MAIN HTML tag
# HTML <main> Tag
# https://www.w3schools.com/tags/tag_main.asp

# skip pjax on followin links and do location.href = target
# Pjax.skip('/admin', '/login')
# if you want to automaticly reload headers, put unique id tags to the HEAD
# <head id="head-app">, # <head id="head-admin"> -> auto relaod all

# do not scroll to to
# Pjax.keep_scrool('.no-scroll', '.menu-heading', '.skill')

# execute action before pjax load and do not proceed if return is false
# Pjax.before (href, opts) ->
#   if opts.node
#     if opts.node.closest('.in-popup')
#       Dialog.load href
#       return false
#   true

# init pjax and optionaly send function to execute on every page request
# Pjax.init ->
#  Widget.bind()
#  Dialog.close()
#  ga('send', 'pageview') if window.ga;

# set meta[name=pjax_template_id] in header, and full reaload page on missmatch

# Pjax.fresh == true if page has not been refreshed

window.Pjax =
  abort_message:  'Pjax request aborted'
  silent:          false
  fresh:           true

  no_scroll_list: []
  before_test:    []
  paths_to_skip:  []

  # overload to display custom message
  error: (message) ->
    alert message
  # helpers

  path: ->
    location.pathname+location.search
  redirect: (href) ->
    location.href = href
    false
  info: (data) ->
    return if @silent
    msg = "Pjax info: #{data}"
    console.log msg
    alert msg
  console: (msg) ->
     console.log msg unless @silent

  # what to do on request error
  on_error: (ret) ->
    @console("Pjax request error: #{ret.statusText} (#{ret.status})")

  # if you want to react before pjax load , for example pagination in a popup to load in a popup
  before: (func) -> @before_test.push func

  # if you do not want to scroll to the top of the document after page load
  keep_scrool: -> @no_scroll_list = arguments

  # refresh page, keep scrool
  refresh: (func)   -> Pjax.load(Pjax.path(), { no_scroll: true, done: func })

  # reload, jump to top, no_cache http request forced
  reload: (func)    -> Pjax.load(Pjax.path(), { no_cache: true, done: func })

  last_path: (path) ->
    if path
      @_last_path = path
      return

    return @_last_path if @_last_path

    if location.search
      location.pathname + location.search
    else
      location.pathname

  # set the no scroll list
  no_scroll: ->
    @no_scroll_list = arguments

  # paths to skips
  skip: ->
    for el in arguments
      @paths_to_skip.push el

  # init Pjax with function that will run after every pjax request
  init: (func) ->
    @init_ok   = true


    # if page change fuction provided, store it and run it
    if func
      @init_func = func if func
      document.addEventListener "DOMContentLoaded", -> func()

  # get pjax template id
  template_id: (data) ->
    node = document.head

    if data
      node = document.createElement('div')
      node.innerHTML = data

    if meta = node.querySelector('meta[name=pjax_template_id]')
      meta.content
    else
      null

  filter: (query_string, query_value) ->
    qs = []
    location.search.replace('?', '').split('&').forEach (el) ->
      [name, value] = el.split '=', 2
      qs.push name + '=' + (if name == query_string then query_value else value)

    qs = '?' + qs.join('&')

    unless RegExp("[^\\w]#{query_string}=").test(qs)
      qs += "&#{query_string}=#{query_value}"

    path = location.pathname + qs.replace('?&', '?')

    @load path

  # load a new page
  load: (href, opts={}) ->
    @info 'You did not use Pjax.init()' unless @init_ok

    return false unless href

    href = location.pathname + href if href[0] == '?'

    if opts.qs
      href += '?'

      for k, v of opts.qs
        href += "#{k}=#{v}&"

      href = href.replace(/&$/, '')

    for func in @before_test
      return false unless func(href, opts)

    return if href == '#'
    return @redirect(href)  if /^http/.test(href)
    return @redirect(href)  if /#/.test(href)
    return @redirect(href)  if @is_disabled
    return if location.hash && location.pathname == href

    for el in @paths_to_skip
      switch typeof el
        when 'object' then return @redirect(href) if el.test(href)
        when 'function' then return @redirect(href) if el(href)
        else return @redirect(href) if href.startsWith(el)

    req_start_time = (new Date()).getTime()

    @request.abort() if @request

    headers = {}
    headers['cache-control'] = 'no-cache' if opts.no_cache

    pjax_template_id = @template_id()

    @request = req = new XMLHttpRequest()
    req.onerror = (e) ->
      Pjax.error 'Net error: Server response not received (Pjax)'
    req.open('GET', href)
    req.setRequestHeader k, v for k,v of headers
    req.send()
    req.onload = (e) =>
      @fresh = false

      # if not 200, redirect to page to show the error
      if req.status != 200
        @console("Pjax status: #{@request.status}")
        location.href = href
        return false

      @_last_path = href

      # this has to happen before body change
      unless opts.no_history
        # push new empty data state, just ot change url
        window.history.pushState({ title: title, data: main}, title, href)

      # fix href because of redirects
      if rul = req.responseURL
        href = rul.split('/')
        href.splice(0,3)
        href = '/' + href.join('/')

      # console log
      log_data  = "Pjax.load #{href}"
      log_data += if opts.no_history then ' (back trigger)' else ''
      @console "#{log_data} (app #{req.getResponseHeader('x-lux-speed')}, real #{((new Date()).getTime() - req_start_time)}ms)"

      # extract data
      title  = @extract(req.responseText, 'title').HTML
      header = @extract(req.responseText, 'head').HTML
      main   = @extract(req.responseText, 'main').HTML || @info("<main> tag not defined in recieved page")

      if pjax_template_id != @template_id(header)
        console.log(pjax_template_id)
        console.log(@template_id(header))

        @console 'Pjax: Template ID missmatch, full load'
        document.head.innerHTML = header
        document.body.innerHTML = @extract(req.responseText, 'body').HTML
      else
        # replace title and body
        @replace title, main

      Pjax.parse_scripts(main)

      # trigger init func if one provided on init
      @init_func() if @init_func

      opts.done() if typeof(opts.done) == 'function'

      # scroll to top of the page unless defined otherwise
      unless opts.no_scroll || @no_scroll_check(opts.node)
        window.scrollTo(0, 0)

    false

  # private methods

  # manualy proces script data, to not do it with $ helper
  parse_scripts: (html) ->
    for data, i in html.split(/<\/?script>/)
      if i%2
        f = new Function(data)
        f()

  # extract node as object from html data
  extract: (data, node_name) ->
    out = {}

    match = new RegExp("<#{node_name}([^>]*)>([^§]+)</#{node_name}>")
    if match.test(data)
      attrs    = RegExp.$1
      out.HTML = RegExp.$2
      attrs.replace /([\-\w]+)=['"]([^'"]+)/, ->
        out[RegExp.$1] = RegExp.$2

    out

  no_scroll_check: (node) ->
    return unless node && node.closest

    for el in @no_scroll_list
      return true if node.closest(el)

    false

  # replace title and body on page refresh
  replace: (title, body) ->
    # replace document title
    document.title = title

    # replace document body
    main = $('main')
    @info "%main tag not defined in document" unless main[0]
    main.html body

# handle back button gracefully
window.onpopstate = (event) ->
  if event.state && event.state.data
    Pjax.console "Pjax.load #{Pjax.path()} (popstate trigger, cache hit)"
    Pjax.replace event.state.title, event.state.data
  else
    Pjax.load Pjax.path(), no_history: true

