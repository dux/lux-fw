# Micro Widget/Component lib by @dux
# Super simple component lib for server side rendered templates
# if you need someting similar but more widely adopted, use https://stimulusjs.org/

# instance public interface
# once()           - called only once on widget register
# init()           - called on wiget init
# css()            - will add css to document head if present
# set(k,v)         - set @state[k]=v to v and call render() if render defined
# html(data, node) - set innerHTML to current node, auto call helpers
# id               - instance_id
# node             - dom_node
# ref              - "Widget.ref[this.id]", dom instance reference as string
# state            - data-json="{...}" -> @state all data-attributes are translated to state

# Widget public interface
# registere(name, object) - register widget
# bind(node)              - init widget by id or dom node
# get(node)               - get closest widget instance
# refresh()               - call render() on all widgets instances

# Example code
# <w-yes_no data-filed="yes"></w-yes_no>
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

window.Widget =
  css_klass: 'w'
  inst_id_name: 'widget_id'
  registered: {},
  count: 0,
  ref: {},

  # #consent.w.toggle ...
  # w.get('#consent').activate()
  # w.get('#consent').set('foo','bar') -> set state and call @render() if defined
  get: (node) ->
    parts = node.split('#', 2)
    node = document.getElementById(parts[1]) if parts[1]
    return unless node
    @bind node

  clear: ->
    for i, w of @ref
      delete @ref[i] unless document.body.contains(w.node)

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
      if typeof name == 'string'
        @state[name] = value
      else
        Object.assign @state, name

      @render() if @render

    # set html to current node
    widget.html ||= (data, root) ->
      data = data.join('') if typeof data != 'string'
      data = data.replace(/\$\$\./g, "#{@ref}.")
      (root || @node).innerHTML = data

    # create custom HTML element
    DOMCustomElement.define "w-#{name}", (node) -> Widget.bind(node, name)

  # runtime apply registered widget to dom node
  bind: (dom_node, widget_name) ->
    dom_node = document.getElementById(dom_node) if typeof(dom_node) == 'string'

    return if dom_node.classList.contains('mounted')
    dom_node.classList.add('mounted')

    instance_id  = dom_node.getAttribute(@inst_id_name)

    if instance_id
      instance_id = parseInt instance_id
    else
      instance_id = ++@count
      dom_node.setAttribute(@inst_id_name, instance_id)

    return @ref[instance_id] if @ref[instance_id]

    dom_node.setAttribute('id', "widget-#{instance_id}") unless dom_node.getAttribute('id')
    dom_node.setAttribute(@inst_id_name, instance_id)

    widget_name ||= dom_node.classList.item(1) if dom_node.classList.item(0) == @css_klass
    widget_opts = @registered[widget_name]

    # return if widget is not defined
    return alert "Widget #{widget_name} is not registred" unless widget_opts

    # define widget instance
    widget = {...widget_opts}

    # bind root to root
    widget.id    = instance_id
    widget.ref   = "Widget.ref[#{instance_id}]"
    widget.node  = dom_node

    # set widget state, copy all date-attributes to state
    json         = dom_node.getAttribute('data-json') || '{}'
    json         = JSON.parse(json)
    widget.state = {...json, ...dom_node.dataset}
    delete widget.state.json

    # store in global object
    @ref[instance_id] = widget

    # init and render
    widget.init() if widget.init
    widget.render() if widget.render

    # return widget instance
    widget

  isWidget: (node) ->
    node.classList.item(0) == @css_klass

  # get dom node child nodes as a list of objects
  childNodes: (root, node_name) ->
    list = []
    i    = 0

    root.childNodes.forEach (node) ->
      return unless node.attributes
      return if node_name && node_name.toUpperCase() != node.nodeName
      o = {}
      o.HTML = node.innerHTML
      o.NODE = node
      o.ID   = i++

      for a in node.attributes
        o[a.name] = a.value

      list.push o

    list

window.w = Widget

