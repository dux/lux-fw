# frozen_string_literal: true

# u = Url.new('https://www.YouTube.com/watch?t=1260&v=cOFSX6nezEY')
# u.delete :t
# u.hash '160s'
# u.to_s -> 'https://com.youtube.www/watch?v=cOFSX6nezEY#160s'

require 'cgi'

class Url

  attr_accessor :proto, :host, :port

  class << self
    def current
      new Lux.current.request.url
    end

    def force_locale loc
      # u = current
      # u.locale loc
      # u.relative

      '/' + loc.to_s + Lux.current.nav.full
    end

    def subdomain name,  in_path=nil
      b = current.subdomain(name)
      b.path in_path if in_path
      b.url
    end

    def qs name, value
      current.qs(name, value).relative
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
    url, qs_part = url.split('?', 2)

    @qs = qs_part.to_s.split('&').inject({}) do |qs, el|
      parts = el.split('=', 2)
      qs[parts[0]] = Url.unescape parts[1]
      qs
    end

    if url =~ /:/
      @proto, _, @domain, @path = url.split '/', 4
      @proto, @port = @proto.split(':', 2)
      @port = nil if @port == '80'
      @domain_parts = @domain.split('.').reverse.map(&:downcase)
    else
      @path = url.to_s
      @path = @path.sub('/', '') if @path[0,1] == '/'
    end

    @path = '/' if @path.blank?
  end

  def domain what=nil
    if what
      @host = what
      return self
    end

    @domain_parts.slice(0,2).reverse.join '.'
  end

  def subdomain name=nil
    if name
      @domain_parts[2] = name
      return self
    end

    @domain_parts.drop(2).reverse.join('.').or nil
  end

  def subdomain= name
    @domain_parts[2] = name
  end

  def host
    @domain_parts.reverse.join '.'
  end

  def query
    @query
  end

  def path val=nil
    return '/'+@path+(@namespace ? ":#{@namespace}" : '') unless val

    @path = val.sub(/^\//,'')
    self
  end

  def delete *keys
    keys.map{ |key| @qs.delete(key.to_s) }
    self
  end

  def hash val
    @hash = "##{val}"
  end

  def qs name, value=:_nil
    if value != :_nil
      @qs[name.to_s] = value
      self
    elsif name
      @qs[name.to_s]
    end
  end

  def namespace data
    @namespace = data.to_s
    self
  end

  def locale what
    elms = @path.split('/')

    if elms[0] && Locale.all.index(elms[0].to_s)
      elms[0] = what
    else
      elms.unshift what
    end

    @path = elms.join('/')

    self
  end

  def url
    [host_with_port, path, qs_val, @hash].join('')
  end

  def relative
    [path, qs_val, @hash].join('').sub('//','/')
  end

  def to_s
    @domain ? url : relative
  end

  def [] key
    @qs[key.to_s]
  end

  def []= key, value
    @qs[key.to_s] = value
  end

  private

  def qs_val
    ret = []
    if @qs.keys.length > 0
      ret.push '?' + @qs.keys.sort.map{ |key| "#{key}=#{Url.escape(@qs[key].to_s)}" }.join('&')
    end
    ret.join('')
  end

  def host_with_port
    %[#{proto}://#{host}#{@port.present? ? '' : ":#{@port}"}]
  end

end