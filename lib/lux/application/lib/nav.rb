# experiment for different nav in rooter

class Lux::Application::Nav
  attr_accessor :path, :id
  attr_reader :original, :subdomain, :domain, :format

  # acepts path as a string
  def initialize request
    @path = request.path.split('/').slice(1, 100) || []
    @original = @path.dup

    @subdomain = request.host.split('.')
    @domain    = @subdomain.pop(2).join('.')
    @subdomain = @subdomain.join('.')
    @domain    += ".#{@subdomain.pop}" if @domain.length < 6
  end

  def active_shift
    @active = @path.shift
  end

  def shift
    return unless @path[0].present?

    if block_given?
      result = yield(@path[0]) || return

      result
    else
      active_shift
    end
  end

  # used to make admin.lvm.me/users to lvh.me/admin/users
  def unshift name
    @path.unshift name
  end

  def root sub_nav=nil
    if block_given?
      return unless @path[0]

      # shift root in place if yields not nil
      result = yield(@path[0]) || return
      active_shift
      result
    else
      sub_nav ? ('%s/%s' % [@path.first, sub_nav]) : @path.first
    end
  end

  def root= value
    @path[0] = value
  end

  def first
    if block_given?
      # shift first in place if yields not nil
      return unless @path[1].present?
      result = yield(@path[1]) || return
      @path.slice!(1,1)
      result
    else
      @path[1]
    end
  end

  def last
    if block_given?
      # replace root in place if yields not nil
      return unless @path.last.present?
      result = yield(@path.last) || return
      @path.pop
      result
    else
      @path.last
    end
  end

  def second
    @path[2]
  end

  def reset
    out = @path.dup
    @path = []
    out
  end

  def active
    @active
  end

  def to_s
    @path.join('/').sub(/\/$/, '')
  end

end
