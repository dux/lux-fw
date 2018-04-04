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

    def qs name, value=nil
      current.qs(name, value).relative
    end

    # for search
    # Url.prepare_qs(:q) -> /foo?bar=1&q=
    def prepare_qs name
      url = current.qs(name).relative
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
    if url =~ /:/
      @elms = url.split '/', 4
    else
      @elms = [url]
      @elms.unshift '',''
    end

    domain_and_port = @elms[2].split(':')
    @domain_parts = domain_and_port[0].to_s.split('.').reverse.map(&:downcase)

    @qs = {}
    path_with_qs = @elms[3].to_s.split(/\?|#/)
    path_with_qs[1].split('&').map do |el|
      parts = el.split('=')
      @qs[parts[0]] = Url.unescape parts[1]
    end if path_with_qs[1]

    @path = path_with_qs[0] || '/'
    @proto = @elms[0].split(':').first.downcase
    @port = domain_and_port[1] ? domain_and_port[1].to_i : 80
  end

  def domain what=nil
    if what
      @host = what
      return self
    end

    @domain_parts.slice(0,2).reverse.join '.'
  end

  def subdomain name
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

  def host_with_port
    %[#{proto}://#{host}#{port == 80 ? '' : ":#{port}"}]
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

  def qs name, value=nil
    if value
      @qs[name.to_s] = value
    elsif name
      @qs.delete(name.to_s)
    end
    self
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

  def qs_val
    ret = []
    if @qs.keys.length > 0
      ret.push '?' + @qs.keys.sort.map{ |key| "#{key}=#{Url.escape(@qs[key].to_s)}" }.join('&')
    end
    ret.join('')
  end

  def url
    [host_with_port, path, qs_val, @hash].join('')
  end

  def relative
    [path, qs_val, @hash].join('').sub('//','/')
  end

  def to_s
    domain.length > 0 ? url : local_url
  end

end