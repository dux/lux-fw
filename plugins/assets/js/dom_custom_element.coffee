# React to do
# ReactDOM.render(React.createElement(SomeReactComponent, { foo: 'bar' }), dom_node);

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

  # bind custom node to class
  bind:(name, svelte_klass) ->
    CustomElement.define name, (node, opts) ->
      in_opts = {
        props: {
          ...opts,
          node: node,
          html: node.innerHTML
        }
      }

      node.innerHTML = ''

      element = new svelte_klass({ target: node, props: in_opts })
      node.svelte = element

      if element.windowGlobal
        window[element.windowGlobal] = element

# create DOM custom element or polyfil for older browsers
window.CustomElement =
  registred: {}
  un_registred: {}

  attributes: (node) ->
    Array.prototype.slice
      .call(node.attributes)
      .reduce (h, el) ->
        h[el.name] = el.value;
        h
      , {}

  # define custom element
  define: (name, func) ->
    @registred[name] = func

    if window.customElements
      customElements.define name, class extends HTMLElement
        connectedCallback: ->
          window.requestAnimationFrame =>
            func @, CustomElement.attributes(@)
    else
      @un_registred[name] = func


# pollyfill for old browsers (this should never trigger)
unless window.customElements
  setInterval =>
    for name, func of CustomElement.un_registred
      for node in Array.from(document.querySelectorAll("#{name}:not(.mounted)"))
        node.classList.add('mounted')
        func node, CustomElement.attributes(node)
  , 300

# # bind react elements
# bind_react: (name, klass) ->
#   @define name, (node, opts) ->
#     element = React.createElement klass, opts, node.innerHTML
#     ReactDOM.render element, node
