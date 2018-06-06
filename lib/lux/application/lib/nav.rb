# experiment for different nav in rooter

class Lux::Application::Nav
  attr_reader :path, :original, :subdomain, :domain, :id

  # acepts path as a string
  def initialize request
    @path = request.path.split('/').slice(1, 100) || []
    @original = @path.dup

    @subdomain = request.host.split('.')
    @domain    = @subdomain.pop(2).join('.')
    @domain    += ".#{@subdomain.pop}" if @domain.length < 6
  end

  def full
    @path.join('/').sub(/\/$/, '')
  end

  def shift skip_root=false
    @path.shift
    @path.first
  end

  def root sub_nav=nil
    sub_nav ? ('%s/%s' % [@path.first, sub_nav]) : @path.first
  end

  def root= value
    @path[0] = value
  end

  # used to make admin.lvm.me/users to lvh.me/admin/users
  def unshift name
    @path.unshift name
  end

  def first
    @path[1]
  end

  def first= data
    @path[1] = data
  end

  def second
    @path[2]
  end

  def last
    @path.last
  end

  def path
    @path.slice(1, @path.length-1) || []
  end

  def rest
    @path.slice(2, @path.length-1) || []
  end

  def to_s
    full
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
