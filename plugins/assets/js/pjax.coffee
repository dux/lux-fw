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
#     n = $(opts.node)
#     if n.closest('.in-popup')[0]
#       Dialog.load href
#       return false
#   true

# init pjax and optionaly send function to execute on every page request
# Pjax.init ->
#  Widget.bind()
#  Dialog.close()
#  ga('send', 'pageview') if window.ga;

window.Pjax =
  abort_message:  'Pjax request aborted'
  silent:          false

  no_scroll_list: []
  before_test:    []
  paths_to_skip:  []

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
  refresh: (func)   -> Pjax.load(Pjax.path(), { keep_scrool: true })

  # reload, jump to top, no_cache http request forced
  reload: (func)    -> Pjax.refresh(func, { no_cache: true })

  # refresh blok of data
  refresh_block: (node_id, url) ->
    $.get url, (data) ->
      data = $("""<div>#{data}</div>""").find(node_id)
      $(node_id).html data.html()

  # paths to skips
  skip: ->
    for el in arguments
      @paths_to_skip.push el

  # init Pjax with function that will run after every pjax request
  init: (func) ->
    @init_ok = true

    # if page change fuction provided, store it and run it
    if func
      $(window).on 'page:change', func
      $ -> func()
    else
      $(window).trigger 'page:change'

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

    @request = $.ajax
      headers: headers,
      method: 'GET'
      url:  href,
      data: {},
      complete: (ret, message) =>
        if message == 'abort'
          @console(@abort_message) if @abort_message
          return

        # fix href because of redirects
        if ret.responseURL
          href = ret.responseURL.split('/')
          href.splice(0,3)
          href = '/' + href.join('/')

        # log error
        return @on_error(ret) if ret.status != 200 && ret.statusText != 'abort'

        # console log
        log_data  = "Pjax.load #{href}"
        log_data += if opts.no_history then ' (back trigger)' else ''
        @console "#{log_data} (app #{ret.getResponseHeader('x-lux-speed').replace(' ','')}, real #{((new Date()).getTime() - req_start_time)}ms)"

        # extract data
        title  = @extract(ret.responseText, 'title').HTML
        header = @extract(ret.responseText, 'head')
        main   = @extract(ret.responseText, 'main').HTML || @info("<main> tag not defined in recieved page")

        @replace title, main

        # check header change
        # ret.getResponseHeader('location')
        if String($('head').attr('id')) != String(header.id)
          @console 'Head change'
          location.href = href
          return

        opts.done() if typeof(opts.done) == 'function'

        # scroll to top of the page unless defined otherwise
        unless @no_scroll_check(opts.node) || opts.no_scroll
          window.scrollTo(0, 0)

        unless opts.no_history
          # push new empty data state, just ot change url
          window.history.pushState({ title: title, data: main}, title, href)

    false

  # private methods

  # extract node as object from html data
  extract: (data, node_name) ->
    out = {}
    match = new RegExp("<#{node_name}([^>]*)>([^§]+)</#{node_name}>")
    match.test(data)

    attrs    = RegExp.$1
    out.HTML = RegExp.$2
    attrs.replace /([\-\w]+)=['"]([^'"]+)/, ->
      out[RegExp.$1] = RegExp.$2

    out

  no_scroll_check: (node) ->
    return unless node
    node = $(node)

    @no_scroll_list ||= []

    for el in @no_scroll_list
      return true if node.closest(el)[0]

    false

  # replace title and body on page refresh
  replace: (title, body) ->
    # replace document title
    document.title = title

    # replace document body
    main = $('main')
    @info "%main tag not defined in document" unless main[0]
    main.html body

    $(window).trigger('page:change')

# handle back button gracefully
window.onpopstate = (event) ->
  if event.state && event.state.data
    Pjax.console "Pjax.load #{Pjax.path()} (popstate trigger, cache hit)"
    Pjax.replace event.state.title, event.state.data
  else
    Pjax.load Pjax.path(), no_history: true
