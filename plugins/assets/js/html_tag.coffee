# tag 'a', { href: '#'}, 'link name' -> <a href="#">link name</a>
# tag 'a', 'link name'               -> <a>link name</a>
# tag '.a', 'b'                      -> <div class="a">b</div>
# tag '#a.b', ['c','d']              -> <div class="b" id="a">cd</div>
# tag '#a.b', {c:'d'}                -> <div c="d" class="b" id="a"></div>

tag_events = {}
tag_uid    = 0

window.tag = (name, args...) ->
  return tag_events unless name

  # evaluate function if data is function
  args = args.map (el) -> if typeof el == 'function' then el() else el

  # swap args if first option is object
  args[1] ||= undefined # fill second value
  [opts, data] = if typeof args[0] == 'object' && !Array.isArray(args[0]) then args else args.reverse()

  # set default values
  opts ||= {}
  data = '' if typeof(data) == 'undefined'
  data = data.join('') if Array.isArray(data)

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

  for key in Object.keys(opts).sort()
    val = opts[key]

    # hide function calls
    if typeof val == 'function'
      uid = ++tag_uid
      tag_events[uid] = val
      val = "tag()[#{uid}](this)"

    node.push ' '+key+'="'+val+'"'

  if ['input', 'img'].indexOf(name) > -1
    node.push ' />'
  else
    node.push '>'+data+'</'+name+'>'

  node.join('')
