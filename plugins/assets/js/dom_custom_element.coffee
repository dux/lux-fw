# create DOM custom element or polyfil for older browsers
window.DOMCustomElement =
  ping_interval: 100
  data: {}

  attributes: (node) ->
    o = {}
    i = 0

    while el = node.attributes[i]
      o[el.name] = el.value;
      i++

    o

  define: (name, func) ->
    if window.customElements
      customElements.define name, class extends HTMLElement
        constructor: ->
          super()
          window.requestAnimationFrame =>
            func @, DOMCustomElement.attributes(@)
    else
      @data[name] = func

  bind: ->
    for name, func of @data
      for node in Array.from(document.querySelectorAll("#{name}:not(.mounted)"))
        node.classList.add('mounted')
        func node, @attributes(node)

  init: ->
    unless window.customElements
      setInterval =>
        @bind()
      , @ping_interval

DOMCustomElement.init()
