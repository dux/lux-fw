# get all <s-filter ...> components and run close() on them
# window.Svelte('filter', function(){ this.close() })
#
# get singleton dialog component
# el = Svelte('dialog')
# el.close()
#
# get closest ajax svelte node
# Svelte('ajax', this)
window.Svelte = (name, func) ->
  if func
    if typeof func == 'object'
      target = func.closest("s-#{name}")
      target = target[0] if target[0]
      target.svelte
    else
      Array.prototype.slice
        .call document.getElementsByTagName("s-#{name}")
        .forEach (el) ->
          func.bind(el.svelte)()
  else if typeof(name) == 'string'
    elements = document.getElementsByTagName("s-#{name}")
    alert("""Globed more then one svelte "#{name}" component""") if elements[1]

    if el = elements[0]
      el.svelte
    else
      null
  else
    alert('Svelte error: not supported')

# bind Svelte elements
Object.assign Svelte,
  cnt: 0

  nodesAsList: (root) ->
    list = []

    root.childNodes.forEach (node, i) ->
      if node.attributes
        o = {}
        o.HTML = node.innerHTML
        o.ID = i + 1

        for a in node.attributes
          o[a.name] = a.value

        list.push o

    list

  # bind custom node to class
  bind:(name, klass) ->
    CustomElement.define name, (node, opts) ->
      if node.innerHTML
        opts.svelte_node = node.cloneNode(true)
        node.innerHTML   = ''

      element = new klass({ target: node, props: opts })
      node.svelte = element

      # define singleton
      # export function singleton() { return 'Dialog' }
      if element.singleton
        window[element.singleton()] = element

# create DOM custom element or polyfil for older browsers
window.CustomElement =
  data: {}
  dom_loaded: false

  attributes: (node) ->
    Array.prototype.slice
      .call(node.attributes)
      .reduce (h, el) ->
        h[el.name] = el.value;
        h
      , {}

  # define custom element
  define: (name, func) ->
    if window.customElements && !window.customElements.get(name)
      customElements.define name, class extends HTMLElement
        connectedCallback: ->
          if CustomElement.dom_loaded
            func @, CustomElement.attributes(@)
          else
            # we need to delay bind if DOM is not loaded
            window.requestAnimationFrame =>
              func @, CustomElement.attributes(@)

    else
      @data[name] = func


# pollyfill for old browsers
unless window.customElements
  setInterval =>
    for name, func of CustomElement.data
      for node in Array.from(document.querySelectorAll("#{name}:not(.mounted)"))
        node.classList.add('mounted')
        func node, CustomElement.attributes(node)
  , 100

# when document is loaded we can render nodes without animation frame
document.addEventListener "DOMContentLoaded", ->
  CustomElement.dom_loaded = true

# # bind react elements
# bind_react: (name, klass) ->
#   @define name, (node, opts) ->
#     element = React.createElement klass, opts, node.innerHTML
#     ReactDOM.render element, node
