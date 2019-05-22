# call just after body tag or $ -> window.MediaBodyClass.init()
# sets body class for
# mobile to  "mobile not-tablet not-desktop"
# tablet to  "not-mobile tablet not-desktop"
# desktop to "not-mobile not-tablet desktop"

window.MediaBodyClass =
  sizes: [['mobile'], ['tablet', 767], ['desktop', 1023]]

  init: ->
    for [name, size] in @sizes.reverse()
      if !size || (size && window.innerWidth > size)
        @set name
        return

  set: (name) ->
    body = $(document.body)

    for it in @sizes
      body.removeClass it[0]
      body.removeClass "not-#{it[0]}"

    for it in @sizes
      klass = if it[0] == name then name else "not-#{it[0]}"
      body.addClass klass

#

for i in [0..(MediaBodyClass.sizes.length - 2)]
  name = MediaBodyClass.sizes[i][0]
  [next_name, next_size] = MediaBodyClass.sizes[i+1]

  window.matchMedia("(max-width: #{next_size}px)").addListener new Function 'e',
    "window.MediaBodyClass.set(e.matches ? '#{name}' : '#{next_name}');"


$ -> window.MediaBodyClass.init()
