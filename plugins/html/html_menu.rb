# menu = HtmlMenu.new request.path
# menu.add 'Home', '/', default: false
# menu.add 'People', '/people', lambda { |path| path.index('peor') }
# menu.add 'Jobs', '/jobs', { icon: true }
#
# match exact path, defaults to path.start_with?
#  menu.add 'Jobs', '/jobs', :path
#  menu.add 'Jobs', '/jobs', { icon: true, active: :path }
# same as
#  menu.add 'Jobs', '/jobs', lambda { request.path == '/jobs '}
#
# menu.to_a
# ---
# [["Home", "/", {}, true], ["People", "/people", {}, false], ["Jobs", "/jobs", { icon: true }, false]]

class HtmlMenu
  attr_accessor :path
  attr_accessor :data

  def initialize path
    @path = path.to_s
    @data = []
  end

  # item 'Links', '/link'
  # item('Links', '/link', { default: true }) { ... }
  def add name, path, opts={}, &block
    opts = { active: opts } unless opts.is_a?(Hash)

    # set first element to default: false (no default activate first)
    # if there is defined rule for activation
    opts[:default] = false if !@data.first && opts[:active]

    test   = opts.delete(:active)
    test   = block if block
    test ||= @path == path

    # ap [@path, path, @path == path] if name == 'Info'

    active = @is_activated ? false : item_active(test, path)

    @is_activated ||= active

    @data.push [name, path, opts, active]
  end

  # is menu item active?
  def item_active test, path
    case test
      when Symbol
        @path.end_with?(test.to_s)
      when String
        @path.end_with?(test)
      when Regexp
        !!(@path =~ test)
      when Proc
        !! test.call(@path)
      when Integer
        true
      when TrueClass
        true
      when FalseClass
        false
      else
        raise ArgumentError.new("Unhandled class #{data.class} for #{data}")
    end
  end

  # return result as a list
  def to_a
    #@data[0][3] = true if !@is_activated && data[0][2][:default].class != FalseClass
    @data
  end

  # return result as list of hashes
  def to_h
    to_a.map do |it|
      {
        name:   it[0],
        path:   it[1],
        opts:   it[2],
        active: it[3],
      }
    end
  end

end
