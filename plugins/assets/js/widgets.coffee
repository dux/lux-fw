# Micro Widget/Component lib by @dux
# Super simple component lib for server side rendered templates
# if you need someting similar but more widely adopted, use https://stimulusjs.org/

# instance public interface
# once()            - called only once on widget register
# init()            - called on wiget init
# css()             - will add css to document head if present
# set(k,v)          - set @state[k]=v to v and call render() if render defined
# html(data, node?) - set innerHTML to current node, auto call helpers. replaces $$ with current node reference
# render()          - if it returns string, renders data to container
# id                - instance_id
# node              - dom_node
# ref               - "Widget.ref[this.id]", dom instance reference as string
# state             - data-json="{...}" -> @state all data-attributes are translated to state

# simplified access interface
# to register a widget
#   Widget name, { inti: ... }
# to bind to DOM node
#   Widget name, HTMLElement
# to get reference to binded node
#   Widget #name || HTMLElement

# Example code
# <w-yes_no data-filed="yes"></w-yes_no>
# <div class="w yes_no" data-filed="yes"></div>
# Widget 'yes_no',
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
#
# %w-yes_no{ ... }

window.Widget = (name, object) ->
  if object.constructor == Object
    Widget.register name, object
  else if !object
    Widget.get name
  else
    Widget.bind name, object

Object.assign Widget,
  inst_id_name: 'widget_id'
  namespace:    'w'
  registered:   {}
  ref:          {}
  count:        0

  # overload with custom on register fuction
  on_register: (name) -> console.log("Widget #{name} registered")

  # #consent.w.toggle ...
  # w.get('#consent').activate()
  # w.get('#consent').set('foo','bar') -> set state and call @render()
  get: (node) ->
    if typeof node == 'string'
      node.split('#', 2)[1] if node[0] == '#'
      node = document.getElementById(node)

    return unless node
    @bind node

  # clear all unbound nodes
  clear: ->
    for i, w of @ref
      delete @ref[i] unless document.body.contains(w.node)

  # register widget, trigger once method, insert css if present
  register: (name, widget) ->
    return if Widget.registered[name]

    @registered[name] = widget

    if widget.once
      widget.once()
      delete widget.once

    if widget.css
      data = if typeof(widget.css) == 'function' then widget.css() else widget.css
      document.head.innerHTML += """<style id="widget_#{name}_css">#{data}</style>"""
      delete widget.css

    widget.attr ||= (name) ->
      @node.getAttribute(name)

    # create set method unless defined
    widget.set ||= (name, value) ->
      if typeof name == 'string'
        @state[name] = value
      else
        Object.assign @state, name

    # set html to current node
    widget.html ||= (data, root) ->
      data = data.join('') if typeof data != 'string'
      data = data.replace(/\$\$\./g, "#{@ref}.")
      (root || @node).innerHTML = data

    # create custom HTML element
    CustomElement.define "#{@namespace}-#{name}", (node, opts) ->
      Widget.bind(name, node, opts)

  # runtime apply registered widget to dom node
  bind: (widget_name, dom_node, state) ->
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

    # return if widget is not defined
    widget_opts = @registered[widget_name]
    return alert("Widget #{widget_name} is not registred") unless widget_opts

    # define widget instance
    widget = {...widget_opts}

    # bind root to root
    widget.id    = instance_id
    widget.ref   = "Widget.ref[#{instance_id}]"
    widget.node  = dom_node

    # set widget state, copy all date-attributes to state
    if state
      if state['data-json']
        widget.state = JSON.parse state['data-json']
      else
        widget.state = state
    else
      json         = dom_node.getAttribute('data-json') || '{}'
      json         = JSON.parse(json)
      widget.state = {...json, ...dom_node.dataset}

    delete widget.state.json

    # store in global object
    @ref[instance_id] = widget

    # redefine render method to insert html to widget if return is a string
    widget.render ||= -> false
    widget.$$render = widget.render
    widget.render = ->
      data = widget.$$render()

      if typeof data == 'string'
        @html data
      else
        null

    # init and render
    widget.init() if widget.init
    widget.render()

    # return widget instance
    widget

  # is node a binded widget
  isWidget: (node) ->
    !!node.getAttribute(@inst_id_name)

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

# clear unused widgets every minute
setTimeout ->
  Widget.clear()
, 60 * 1000