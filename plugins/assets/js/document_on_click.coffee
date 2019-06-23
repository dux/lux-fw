$(document).on 'click', (event) ->
  # if ctrl or cmd button is pressed
  return if event.which == 2

  event.stopPropagation()

  node = $(event.target)
  node_nested = node.closest('*[href]')

  # scoped confirmatoon box
  conf = node.closest('*[confirm]')
  if conf[0]
    return false unless confirm(conf.attr('confirm'))

  # nested click or oncllick events
  test_click = node.closest('*[onclick], *[click]')
  if test_click[0]
    if data = test_click.attr('click')
      func = new Function(data)
      func.bind(test_click[0])()
    return

  # self or scoped href, as on %tr row element.
  if node_nested[0]
    node = node_nested
    href = node.attr('href')

    if /^#/.test(href)
      location.hash = href
      return false

    return if /^(mailto|subl):/.test(href)
    return if node.prop('target')
    return if node.hasClass('no-pjax') || node.hasClass('direct')

    if js = href.split('javascript:')[1]
      func = new Function(js)
      func.bind(node[0])()
      return false

    if event.metaKey || /^\w+:/.test(href)
      window.open node.attr('href')
      return false

    Pjax.load href, node: node[0]

    false


