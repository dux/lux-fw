# Svelte('dialog', function(){
#   this.close()
#   window.$.delay(()=>{ window.scrollTo(0, 0) })
# })
window.Svelte = (name, func) ->
  if name.includes('*')
    console.error("""Svelte component glob "#{name}*", func not defined""") unless func

    # if giver * glob all execute function
    # Svelte 'filter*', (el) -> el.close()
    name = name.replace '*', ''
    Array.prototype.slice
      .call document.getElementsByTagName("s-#{name}")
      .forEach (el) ->
        func.bind(el.svelte)()

  if el = document.getElementsByTagName("s-#{name}")[0]
    if func
      func.bind(el.svelte)()
    else
      el.svelte
  else
    unless func
      console.error("""Svelte component "#{name}" not found""")

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
        if node.innerHTML.indexOf('</slot>') > -1
          opts.slots = Svelte.nodesAsList node
        else
          opts.innerHTML = node.innerHTML
          node.innerHTML = ''

      global = null
      if opts.global
        global  = opts.global
        delete opts.global

      element = new klass({ target: node, props: opts })
      window[global] = element if global
      node.svelte = element


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
    if window.customElements
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
