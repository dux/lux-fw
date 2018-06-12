# menu = HtmlMenu.new request.path
# menu.add 'Home', '/'
# menu.add 'People', '/people', lambda { |path| path.index('peor') }
# menu.add 'Jobs', '/jbos'
# menu.to_a
# ---
# [["Home", "/", true], ["People", "/people", false], ["Jobs", "/jbos", false]]

class HtmlMenu
  attr_accessor :path
  attr_accessor :data

  def initialize path
    @path = path.to_s
    @data = []
  end

  # item 'Links', '/link'
  # item('Links', '/link') { ... }
  def add name, path, test=nil, &block
    if @data.first
      active = nil
      active = false if test.class == FalseClass && !@data.first

      if !@is_activated && @data.first && path != @data.first[1]
        test          ||= block || path
        active          = item_active(test)
        @is_activated ||= active
      end

      @data.push [name, path, active]
    else
      @data.push [name, path, test.class == FalseClass ? false : nil]
    end
  end

  # is menu item active?
  def item_active data
    case data
      when Symbol
        @path.include?(data.to_s)
      when String
        @path.starts_with? data
      when Regexp
        @path =~ data
      when Proc
        !! data.call(@path)
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
    @data[0][2] = true if ! @is_activated && @data[0][2].class != FalseClass
    @data
  end

  # return result as list of hashes
  def to_h
    to_a.map do |it|
      {
        name:   it[0],
        path:   it[1],
        active: it[2],
      }
    end
  end

end
