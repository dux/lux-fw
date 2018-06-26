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

  def shift
    if block_given?
      result = yield(@path[0]) || return
      @path.shift
      result
    else
      @path.shift
      @path.first
    end
  end

  # used to make admin.lvm.me/users to lvh.me/admin/users
  def unshift name
    @path.unshift name
  end

  def root sub_nav=nil
    if block_given?
      # replace root in place if yields not nil
      result = yield(@path[0]) || return
      @path.slice!(0,1)
      @path[0] = result
    else
      sub_nav ? ('%s/%s' % [@path.first, sub_nav]) : @path.first
    end
  end

  def root= value
    @path[0] = value
  end

  def first
    if block_given?
      # replace root in place if yields not nil
      return unless @path[1].present?
      result = yield(@path[1]) || return
      @path.slice!(1,1)
      result
    else
      @path[1]
    end
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
end
