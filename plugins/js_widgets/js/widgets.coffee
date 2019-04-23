'use strict'

# Micro Widget/Component lib by @dux
# Super simple component lib for server side rendered templates
# if you need someting similar but more widely adopted, use https://stimulusjs.org/

# instance public interface
# init()   - called on every wiget $init
# once()   - called once on every page
# css()    - will add css to document head if present
# set(k,v) - set state k to v and call render() if render defined
# id       - instance_id
# node     - dom_node
# ref      - "Widget.ref[this.id]", dom instance reference as string
# state    - data-json="{...}" -> @state all data-attributes are translated to state

# Widget public interface
# registere(name, object) - register widget
# bind(node)              - init widget by id or dom node
# get(node)               - get closest widget instance
# refresh()               - call render() on all widgets instances

# Example code
# <div class="w yes_no" data-filed="yes"></div>
# w.register 'yes_no',
#   init:
#     @root = $ @node
#     @state =
#       field:  @root.data('field')

#   render_button: (name, state) ->
#     $tag 'button.btn.btn-sm', name,
#       class:   "btn-#{klass}"
#       onclick: @ref+".update_state('"+state+"')"

#   render: ->
#     data = @render_button(@state.no, 0)
#     @root.html $tag('div.btn-group', data)

#   update_state: (state) ->
#     @state.state = state
#     @render()

# $ -> w.bind()

@Widget =
  css_klass: 'w'
  inst_id_name: 'data-widget_id'
  registered: {},
  count: 0,
  ref: {},

  # #consent.w.toggle ...
  # w.get('#consent').activate()
  # w.get('#consent').set('foo','bar') -> set state and call @render() if defined
  get: (node) ->
    parts = node.split('#', 2)
    node = document.getElementById(parts[1]) if parts[1]
    # node = node.closest(".#{@css_klass}") || alert('Cant find closest widgets')
    return unless node
    @bind node

  clear: ->
    for i, w of @ref
      delete @ref[i] unless document.body.contains(w.node)

  init: (data) ->
    @clear()

    while node = @get_next_widget_node(data)
      @bind(node)

  get_next_widget_node: (root) ->
    root ||= window.document

    for node in root.getElementsByClassName(@css_klass)
      return node if node && !node.getAttribute('data-widget_id')

    null

  # refresh all widgets
  refresh: ->
    @clear()

    for node in @registered.values()
      node.render() if node.render

  # register widget, trigger once method, insert css if present
  register:  (name, widget) ->
    return if @registered[name]

    @registered[name] = widget

    if widget.once
      widget.once()
      delete widget.once

    if widget.css
      data = if typeof(widget.css) == 'function' then widget.css() else widget.css
      document.head.innerHTML += """<style id="widget_#{name}_css">#{data}</style>"""
      delete widget.css

    # create set method unless defined
    widget.set ||= (name, value) ->
      @state[name] = value
      @render() if @render

    # for k, v of widget
    #   if typeof(v) == 'function'
    #     v = String(v)
    #     v = v.replace('{', "{\nvar w=$tag;\n")
    #     eval "widget.#{k} = #{v}"

  # runtime apply registered widget to dom node
  bind: (dom_node) ->
    dom_node = document.getElementById(dom_node) if typeof(dom_node) == 'string'

    instance_id  = dom_node.getAttribute(@inst_id_name)

    if instance_id
      instance_id = parseInt instance_id
    else
      instance_id = ++@count
      dom_node.setAttribute(@inst_id_name, instance_id)

    return @ref[instance_id] if @ref[instance_id]

    dom_node.setAttribute('id', "widget-#{instance_id}") unless dom_node.getAttribute('id')
    dom_node.setAttribute(@inst_id_name, instance_id)

    widget_name = dom_node.getAttribute('class').split(' ')[1]
    widget_opts = @registered[widget_name]

    # return if widget is not defined
    return alert "Widget #{widget_name} is not registred" unless widget_opts

    # define widget instance
    widget = {}

    # apply basic methods
    widget[key] = widget_opts[key] for key in Object.keys(widget_opts)

    # bind root to root
    widget.id    = instance_id
    widget.ref   = "Widget.ref[#{instance_id}]"
    widget.node  = dom_node
    widget.parse = (data) -> data.replace(/\$\$\./g, @ref+'.')

    # set widget state, copy all date-attributes to state
    json = dom_node.getAttribute('data-json') || '{}'
    json = JSON.parse json
    widget.state = Object.assign(json, dom_node.dataset)

    # store in global object
    @ref[instance_id] = widget

    # init and render
    widget.init() if widget.init
    widget.render() if widget.render

    # return widget instance
    widget

  is_widget: (node) ->
    klass = node.getAttribute('class')

    if klass?.split(' ')[0] == 'w'
      node
    else
      undefined

@w = Widget