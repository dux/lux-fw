#$tag 'button.btn.btn-xs', button_name, class: 'btn-primary'
@$tag = (name, args...) ->
  # evaluate function if data is function
  args = args.map (el) -> if typeof el == 'function' then el() else el

  # fill second value
  args[1] ||= if typeof args[0] == 'object' then '' else {}

  # swap args if first option is object
  [opts, data] = if typeof args[0] == 'object' then args else args.reverse()
  opts ||= {}

  # haml style id define
  name = name.replace /#([\w\-]+)/, (_, id) ->
    opts['id'] = id
    ''

  # haml style class add with a dot
  name_parts = name.split('.')
  name       = name_parts.shift() || 'div'

  if name_parts[0]
    old_class = if opts['class'] then ' '+opts['class'] else ''
    opts['class'] = name_parts.join(' ') + old_class

  node = ['<'+name]

  for key in Object.keys(opts)
    val = opts[key]

    if typeof val == 'function'
      val = String(val).replace(/\s+/g,' ')
      val = """(#{val})();"""

    node.push ' '+key+'="'+val+'"'

  if ['input', 'img'].indexOf(name) > -1
    node.push ' />'
  else
    node.push '>'+data+'</'+name+'>'

  node.join('')
