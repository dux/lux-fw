# How to use?

# Pjax will replace only contents of MAIN HTML tag
# HTML <main> Tag
# https://www.w3schools.com/tags/tag_main.asp

# Pjax.keep_scrool('.no-scroll', '.menu-heading', '.skill', ()=>{ ... })
# set meta[name=pjax_template_id] in header, and full reaload page on missmatch
# Pjax.init -> ... -> function to execute after every page load

# handle back button gracefully
window.onpopstate = (event) ->
  if event.state && event.state.data
    Pjax.console "Pjax.load #{Pjax.path()} (popstate trigger, cache hit)"
    Pjax.replace event.state.title, event.state.data
  else
    Pjax.load Pjax.path(), no_history: true

window.Pjax =
class Pjax
  @abort_message  = 'Pjax request aborted'
  @silent         = false
  @fresh          = true                    # if page has not been refreshed
  @no_scroll_list = []
  @before_test    = []
  @paths_to_skip  = []
  @preloaded      = {}

  @load: (href, opts) ->
    pjax = new Pjax(href, opts || {})
    pjax.load()

  @path: ->
    location.pathname+location.search

  @info: (data) ->
    return if @silent
    msg = "Pjax info: #{data}"
    @console.log msg
    alert msg

  @console: (msg) ->
    console.log msg unless @silent

  # what to do on request error
  @on_error: (ret) ->
    @console("Pjax request error: #{ret.statusText} (#{ret.status})")

  # execute action before pjax load and do not proceed if return is false
  # example, load dialog links inside the dialog
  # Pjax.before (href, opts) ->
  #   if opts.node
  #     if opts.node.closest('.in-popup')
  #       Dialog.load href
  #       return false
  #   true
  @before: (func) -> @before_test.push func

  # do not scroll to top, use refresh() and not reload()
  # Pjax.keep_scrool('.no-scroll', '.menu-heading', '.skill')
  @keep_scrool: -> @no_scroll_list = arguments

  # set the no scroll list
  @no_scroll: ->
    @no_scroll_list = arguments

  # refresh page, keep scrool
  @refresh: (func)   -> Pjax.load(Pjax.path(), { no_scroll: true, done: func })

  # reload, jump to top, no_cache http request forced
  @reload: (func)    -> Pjax.load(Pjax.path(), { no_cache: true, done: func })

  @no_scroll_check: (node) ->
    return unless node && node.closest

    for el in @no_scroll_list
      return true if node.closest(el)

    false

  # skip pjax on followin links and do location.href = target
  # Pjax.skip('/admin', '/login')
  @skip: ->
    for el in arguments
      @paths_to_skip.push el

  # Pjax.init ->
  #  Widget.bind()
  #  Dialog.close()
  #  ga('send', 'pageview') if window.ga;
  # init Pjax with function that will run after every pjax request
  @init: (func) ->
    @init_ok = true

    # if page change fuction provided, store it and run it
    if func
      @init_func = func
      document.addEventListener "DOMContentLoaded", -> func()

  # replace with real page reload init func
  @init_func: -> true

  ###########

  constructor: (@href, @opts) ->
    true

  # load a new page
  load: ->
    @info 'You did not use Pjax.init()' unless Pjax.init_ok

    return false unless @href

    if Pjax.preloaded[@href] && !@opts.preload
      Pjax.preloaded[@href]()
      delete Pjax.preloaded[@href]
      return

    @href = location.pathname + @href if @href[0] == '?'

    for func in Pjax.before_test
      return false unless func(@href, @opts)

    if @href == '#' || (location.hash && location.pathname == @href)
      return

    if /^http/.test(@href) || /#/.test(@href) || @is_disabled
      return @redirect()

    for el in Pjax.paths_to_skip
      switch typeof el
        when 'object' then return @redirect() if el.test(@href)
        when 'function' then return @redirect() if el(@href)
        else return @redirect() if @href.startsWith(el)

    @opts.req_start_time = (new Date()).getTime()

    headers = {}
    headers['cache-control'] = 'no-cache' if @opts.no_cache
    headers['x-requested-with'] = 'XMLHttpRequest'

    @opts.pjax_template_id = @template_id()

    if Pjax.request
      Pjax.request.abort()

    Pjax.request = @req = new XMLHttpRequest()

    @req.onerror = (e) ->
      Pjax.error 'Net error: Server response not received (Pjax)'
      Pjax.console.error(e)

    @req.open('GET', @href)
    @req.setRequestHeader k, v for k,v of headers
    @req.send()
    @req.onload = (e) =>
      Pjax.fresh = false
      @response  = @req.responseText

      # if not 200, redirect to page to show the error
      if @req.status != 200
        Pjax.console("Pjax status: #{@request.status}")
        location.href = @href
        return false

      Pjax.last_path = @href

      # fix href because of redirects
      if rul = @req.responseURL
        @href = rul.split('/')
        @href.splice(0,3)
        @href = '/' + @href.join('/')

      if Pjax.preload
        Pjax.preloaded[@href] = =>
          @replace_page()
      else
        @replace_page()

    false

  # # # private methods # # #

  replace_page: ->
    # extract data
    main   = @extract('main').HTML || @info("<main> tag not defined in recieved page")
    title  = @extract('title').HTML
    header = @extract('head').HTML

    # this has to happen before body change
    unless @opts.no_history
      # push new empty data state, just ot change url
      window.history.pushState({ title: title, data: main}, title, @href)

    # console log
    time_diff = (new Date()).getTime() - @opts.req_start_time
    log_data  = "Pjax.load #{@href}"
    log_data += if @opts.no_history then ' (back trigger)' else ''
    Pjax.console "#{log_data} (app #{@req.getResponseHeader('x-lux-speed')}, real #{time_diff}ms)"

    if @opts.pjax_template_id != @template_id(header)
      Pjax.console 'Pjax: Template ID missmatch, full load'
      document.head.innerHTML = header
      document.body.innerHTML = @extract('body').HTML
    else
      # replace title and body
      @replace title, main

    # trigger init func if one provided on init
    Pjax.init_func()

    @opts.done() if typeof(@opts.done) == 'function'

    # scroll to top of the page unless defined otherwise
    unless @opts.no_scroll || Pjax.no_scroll_check(@opts.node)
      window.scrollTo(0, 0)

  # replace title and body on page refresh
  replace: (title, body) ->
    # replace document title
    document.title = title

    # replace document body
    main = $('main')
    @info "%main tag not defined in document" unless main[0]
    main.html body

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

  redirect: ->
    location.href = @href
    false

  # extract node as object from html data
  extract: (node_name) ->
    out = {}

    match = new RegExp("<#{node_name}([^>]*)>([^§]+)</#{node_name}>")
    if match.test(@response)
      attrs    = RegExp.$1
      out.HTML = RegExp.$2
      attrs.replace /([\-\w]+)=['"]([^'"]+)/, ->
        out[RegExp.$1] = RegExp.$2

    out
