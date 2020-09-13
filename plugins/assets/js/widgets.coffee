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
# <w-yes_no data-field="yes"></w-yes_no>
# Widget 'yes_no',
#   init:
#     @root = $ @node
#     @state =
#       field:  @root.data('field')

#   render_button: (name, state) ->
#     $tag 'button.btn.btn-sm', name,
#       class:   "btn-#{klass}"
#       onclick: => { @update_state(state) }

#   render: ->
#     data = @render_button(@state.no, 0)
#     @root.html tag('div.btn-group', data)

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

  # register widget, trigger once method, insert css if present
  register: (name, widget) ->
    return if Widget.registered[name]

    @registered[name] = widget

    if widget.once
      widget.once()
      delete widget.once

    # create custom HTML element
    # %widget-yes_no{ id: @product.id, object: :products, field: :use_suggestions, state: @product.use_suggestions ? 1 : 0 }
    CustomElement.define "#{@namespace}-#{name}", (node, opts) ->
      Widget.bind(name, node, opts)

  # runtime apply registered widget to dom node
  bind: (widget_name, dom_node, state) ->
    dom_node = document.getElementById(dom_node) if typeof(dom_node) == 'string'

    return if dom_node.classList.contains('mounted')
    dom_node.classList.add('mounted')

    unless dom_node.getAttribute('id')
      dom_node.setAttribute('id', "widget_#{++@count}")

    # return if widget is not defined
    widget_opts = @registered[widget_name]
    return console.error("Widget #{widget_name} is not registred") unless widget_opts

    # define widget instance
    widget = {...widget_opts}

    if widget.css
      id = "widget_#{widget_name}_css"
      unless document.getElementById id
        style = document.createElement 'style'
        style.setAttribute 'id', id
        style.innerHTML = widget.css
        document.head.append style


    # @h('b', { color: 'red' }, 'red') => <b color="red">red</b>
    widget.h ||= tag if window.tag

    # bind widget to node
    dom_node.widget = widget

    # bind root to root
    widget.node  = dom_node
    widget.id    = dom_node.id
    widget.ref   = "document.getElementById('#{widget.node.id}').widget"

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

    # shortcut
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
      data = data.replace(/\$\$\./g, widget.ref+'.')
      (root || @node).innerHTML = data

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
    !!node.widget

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