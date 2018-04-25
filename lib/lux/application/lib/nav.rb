# experiment for different nav in rooter

class Lux::Application::Nav
  attr_reader :path, :original, :subdomain, :domain, :id

  # acepts path as a string
  def initialize request
    @path = request.path.split('/').slice(1, 100) || []
    @original = @path.dup

    shift_to_root if @path.first

    @subdomain = request.host.split('.')
    @domain    = @subdomain.pop(2).join('.')
    @domain    += ".#{@subdomain.pop}" if @domain.length < 6
  end

  def full
    @full = '/%s/%s' % [@root, @path.join('/')]
    @full = @full.sub(/\/$/, '')
  end

  def shift_to_root
    @root.tap do
      @root = @path.shift.to_s.gsub('-', '_')
    end

    @root = nil if @root.blank?

    @root
  end

  def root sub_nav=nil
    sub_nav ? ('%s/%s' % [@root, sub_nav]) : @root
  end

  # used to make admin.lvm.me/users to lvh.me/admin/users
  def unshift name
    @path.unshift @root
    @root = name
  end

  def shift
    @path.shift
  end

  def first
    @path.first
  end

  def first= data
    @path[0] = data
  end

  def second
    @path[1]
  end

  def last
    @path.last
  end

  def rest
    @path.slice(1, @path.length-1)
  end

  def to_s
    @full
  end

  def id
    if first && block_given?
      if @id = yield(first)
        shift
      end
    end

    @id
  end
end
