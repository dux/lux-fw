# frozen_string_literal: true

# u = Url.new('https://www.YouTube.com/watch?t=1260&v=cOFSX6nezEY')
# u.delete :t
# u.hash '160s'
# u.to_s -> 'https://com.youtube.www/watch?v=cOFSX6nezEY#160s'

require 'cgi'

class Url
  class << self
    # get current Url
    def current
      new '/' + Lux.current.request.url.split('/').drop(3).join('/')
    end

    def host
      ::Url.new(Lux.config.host)
    end

    def force_locale loc
      u = current
      u.locale loc
      u.relative
    end

    # change current subdomain
    def subdomain name, in_path=nil
      b = current.subdomain(name)
      b.path in_path if in_path
      b.url
    end

    def qs name, value
      current.qs(name, value).relative
    end

    # same as force qs but remove value if selected
    def toggle name, value
      value = nil if Lux.current.params[name].to_s == value.to_s
      qs name, value
    end

    # for search
    # Url.prepare_qs(:q) -> /foo?bar=1&q=
    def prepare_qs name
      url = current.delete(name).relative
      url += url.index('?') ? '&' : '?'
      "#{url}#{name}="
    end

    def escape str=nil
      CGI::escape(str.to_s)
    end

    def unescape str=nil
      CGI::unescape(str.to_s)
    end
  end

  ###

  def initialize url
    @opt = {}.to_hwia %i(proto port subdomain domain locale path qs qs_hash)

    url, qs_part = url.split('?', 2)

    # querysting hash
    qs_part, @opt.qs_hash = qs_part.to_s.split('#')
    @opt.qs_hash = '#%s' % @opt.qs_hash if @opt.qs_hash

    # querystring
    @opt.qs = qs_part.to_s.split('&').inject({}) do |qs, el|
      parts = el.split('=', 2)
      qs[parts[0]] = Url.unescape parts[1]
      qs
    end

    # domain and subdomain
    if url =~ %r{://}
      @opt.proto, _, host, @opt.path = url.split '/', 4

      @opt.proto = @opt.proto.sub(':', '')

      host, @opt.port = host.split(':', 2)
      @opt.port = nil if @opt.port == '80' || @opt.port == '443' || @opt.port.blank?

      # domain and subdomain
      parts = host.split('.').map(&:downcase)
      @opt.domain = parts.pop(2)
      @opt.domain.unshift parts.pop if @opt.domain.join('').length == 4 # co.uk
      @opt.domain = @opt.domain.join('.')
      @opt.subdomain = parts.first ? parts.join('.') : nil
    else
      @opt.path = url.to_s.sub(%r{^/}, '')
    end

    # check for locale
    parts = @opt.path.to_s.split('/')
    if parts[0] =~ /^\w{2}$/ || parts[0] =~ /^\w{2}\-\w{2}$/
      @opt.locale = parts.shift
      @opt.path   = parts.join('/')
    end

    @opt.path = '' if @opt.path.blank?
  end

  def prepare_qs name
    url = delete(name).relative
    url += url.index('?') ? '&' : '?'
    "#{url}#{name}="
  end

  def domain what=nil
    if what
      @opt.domain = what
      self
    else
      @opt.domain
    end
  end
  alias :domain= :domain

  def subdomain name=nil
    if name
      @opt.subdomain = name
      self
    else
      @opt.subdomain
    end
  end
  alias :subdomain= :subdomain

  def host
    @opt.subdomain ? [@opt.subdomain, @opt.domain].join('.') : @opt.domain
  end

  def host_with_port
    %[#{@opt.proto}://#{host}#{@opt.port.present? ? ":#{@opt.port}" : ''}]
  end

  def path val=nil
    if val
      @opt.path = val.sub /^\//, ''
      return self
    else
      @opt.locale ? "/#{@opt.locale}/#{@opt.path}" : "/#{@opt.path}"
    end
  end
  alias :path= :path

  def delete *keys
    keys.map{ |key| @opt.qs.delete(key.to_s) }
    self
  end

  def hash val
    @opt.qs_hash = "##{val}"
  end

  def qs name=nil, value=:_nil
    return @opt.qs unless name

    if value != :_nil
      if value.nil?
        @opt.qs.delete(name.to_s)
      else
        @opt.qs[name.to_s] = value
      end

      self
    elsif name.is_a?(Hash)
      @opt.qs = name.inject(@opt.qs) do |t, el|
        if el[1]
          t[el[0].to_s] = el[1]
        else
          t.delete el[0].to_s
        end

        t
      end

      self
    elsif name
      @opt.qs[name.to_s]
    end
  end

  def locale name=nil
    if name
      @opt.locale = name
      self
    else
      @opt.locale
    end
  end

  def url
    [host_with_port, path, qs_val, @opt.qs_hash].join('')
  end

  def relative
    [path, qs_val, @opt.qs_hash].join('').sub('//','/')
  end

  def to_s
    @opt.domain ? url : relative
  end

  def [] key
    @opt.qs[key.to_s]
  end

  def []= key, value
    @opt.qs[key.to_s] = value
  end

  def to_h
    {
      proto:  @opt.proto,
      port:   @opt.port,
      domain: {
        full:      host,
        domain:    @opt.domain,
        subdomain: subdomain
      },
      locale: @opt.locale,
      path:   @opt.path,
      qs:     @opt.qs,
      hash:   @opt.qs_hash
    }
  end

  def to_json
    JSON.pretty_generate(to_h)
  end

  private

  def qs_val
    ret = []
    if @opt.qs.keys.length > 0
      ret.push '?' + @opt.qs.keys.sort.map{ |key| "#{key}=#{Url.escape(@opt.qs[key].to_s)}" }.join('&')
    end
    ret.join('')
  end
end
