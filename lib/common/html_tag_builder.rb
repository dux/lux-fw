# tag.ul do |n|
#   1.upto(3) do |num|
#     n.li do |n|
#       n.i 'arrow'              # <i class="arrow"></i>
#       n._arrow                 # <div class="arrow"></div>
#       n.span 123               # <span>123</span>
#       n.span { 123 }           # <span>123</span>
#       n.('foo')                # <div class="foo"></div>
#       n._foo(bar: baz) { 123 } # <div class="foo" bar="baz">123</div>
#     end
#   end
# end
#
# tag._row [                      # <div class="row">
#   tag.('#menu.col') { @menu },  #   <div id="menu" class="col">@menu</div>
#   tag._col { @data }            #   <div class="col">@data</div>
# ]                               # </div>

class HtmlTagBuilder
  class << self
    # tag.div -> tag.tag :div
    def method_missing tag_name, *args, &block
      tag tag_name, args[0], args[1], &block
    end

    # tag :div, { 'class'=>'iform' } do
    def tag name=nil, opts={}, data=nil
      if Array === opts
        # join data given as an array
        data = opts
        opts = {}
      elsif Hash === data
        # tag.button('btn', href: '/') { 'Foo' }
        opts = data.merge class: opts
        data = nil
      end

      # covert n._row to n(class: 'row')
      name = name.to_s
      if name.to_s[0, 1] == '_'
        opts ||= {}
        opts[:class] = name.to_s.sub('_', '')
        name = :div
      end

      # covert tag.a '.foo.bar' to class names
      # covert tag.a '#id' to id names
      if (data || block_given?) && opts.is_a?(String)
        given = opts.dup
        opts  = {}

        given.sub(/#([\w\-]+)/) { opts[:id] = $1 }
        klass = given.sub(/^\./, '').gsub('.', ' ')
        opts[:class] = klass if klass.present?
      end

      # fix data and opts unless opts is Hash
      data, opts = opts, {} unless opts.class == Hash

      if block_given?
        inline = new
        data = yield(inline, opts)

        # if data is pushed to passed node, use that data
        data = inline.data if inline.data.first
      end

      data = data.join('') if data.is_a?(Array)

      build opts, name, data
    end

    # build html node
    def build attrs, node=nil, text=nil
      opts = ''
      attrs.each do |k,v|
        opts += ' '+k.to_s.gsub(/_/,'-')+'="'+v.to_s.gsub(/"/,'&quot;')+'"' if v.present?
      end

      return opts unless node

      text = yield opts if block_given?
      text ||= '' unless ['input', 'img', 'meta', 'link', 'hr', 'br'].include?(node.to_s)
      text ? %{<#{node}#{opts}>#{text}</#{node}>} : %{<#{node}#{opts} />}
    end

    # tag.div(class: 'klasa') do -> tag.('klasa') do
    def call class_name, &block
      tag(:div, class_name, &block)
    end

  end

  ###

  attr_reader :data

  def initialize
    @data = []
  end

  # push data to stack
  def push data
    @data.push data
  end

  # n.div(class: 'klasa') do -> n.('klasa') do
  def call class_name, &block
    @data.push self.class.tag(:div, { class: class_name }, &block)
  end

  # forward to class
  def method_missing tag_name, *args, &block
    @data.push self.class.tag(tag_name, args[0], args[1], &block)
  end
end