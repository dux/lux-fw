# tag.ul do |n|
#   1.upto(3) do |num|
#     n.li do |n|
#       n.i '.arrow'
#       n.span num
#       n.id
#     end
#   end
# end

class HtmlTagBuilder
  class << self
    # tag.div -> tag.tag :div
    def method_missing tag_name, *args, &block
      tag tag_name, args[0], args[1], &block
    end

    # tag :div, { 'class'=>'iform' } do
    def tag name=nil, opts={}, data=nil
      # covert tag.a '.foo.bar' to class names
      # covert tag.a '#id' to id names
      if opts.class == String
        case opts[0,1]
          when '.'
            opts = { class: opts.sub('.', '').gsub('.', ' ') }
          when '#'
            opts = { id: opts.sub('#', '') }
          end
        else
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

  # forward to class
  def method_missing tag_name, *args, &block
    @data.push self.class.tag(tag_name, args[0], args[1], &block)
  end
end