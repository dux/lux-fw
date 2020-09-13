$(document).on 'click', (event) ->
  # if ctrl or cmd button is pressed
  return if event.which == 2

  event.stopPropagation()
  # event.preventDefault()

  node = $(event.target).closest('*[href], *[click], *[onclick]')
  return unless node[0]

  return if node[0].nodeName == 'INPUT'

  # scoped confirmatoon box
  conf = node.closest('*[confirm]')
  if conf[0]
    return false unless confirm(conf.attr('confirm'))

  # nested click or oncllick events
  if node.attr('onclick') || node.attr('click')
    if data = node.attr('click')
      func = new Function(data)
      func.bind(node[0])()

    return false

  # self or scoped href, as on %tr row element.
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


