class PageMeta
  attr_accessor :app

  def initialize
    @meta    = {}
    @links   = []
    @scripts = []
  end

  def meta name, desc
    @meta[name.to_s] = desc.to_s
  end

  # preload fonts
  def preload resource
    type = 'font/%s' % resource.split('.').last
    @links.push %[<link rel="preload" href="#{resource}" as="font" type="#{type}" crossorigin="anonymous" />]
  end

  def live_reload
    Lux.env.dev? ? %[<script src="/autoreload-check"></script>] : nil
  end

  def description data
    return @description unless data.present?
    data = data.trim(140)
    @meta['og:description'] = data
  end
  alias_method :description=, :description

  def link rel, href
    @links.push '<link rel="%s" href="%s" />' % [rel, href]
  end

  def title data = nil
    return @title unless data.present?
    @meta['og:title'] = @title = data.trim(100)
  end
  alias_method :title=, :title

  def url data = nil
    return @url unless data.present?
    @meta['og:url'] = @url = data
  end
  alias_method :url=, :url

  def noindex
    @noindex = true
  end

  def nofollow
    @nofollow = true
  end

  # last modified date
  def revised date_time
    meta :revised, date_time.iso8601
  end

  def image url
    return unless url.present?

    @meta['og:image'] = url
    @meta['twitter:image'] = url
    @meta['twitter:card'] = 'summary_large_image'

    size = url.split('.').last(2).first.to_s.split('-').last.to_s.split('x')

    if size[1].is_numeric?
      @meta['og:image:width']  = size[0]
      @meta['og:image:height'] = size[1]
    end
  end
  alias_method :image=, :image

  def icon path
    @icon_path = path
  end

  def canonical href
    @links << '<link rel="canonical" href="%s" />' % href
    meta 'og:url', href
  end

  def locale name
    meta 'og:locale', name
  end

  def render
    render_data = yield(self)

    ret = []

    ret.push %[<meta name="viewport" content="width=device-width" initial-scale="1.0" maximum-scale="1.0" minimum-scale="1.0" user-scalable="no" />]

    # do not render other data if request is xhr/ajax
    # robots
    robots = []
    robots.push @noindex ? :noindex : :index
    robots.push @nofollow ? :nofollow : :follow
    meta :robots, robots.join(', ')
    Lux.current.response.header 'x-robots-tag', robots.join(', ')

    # favicon
    @icon_path ||= '/favicon.png'
    ext = File.ext(@icon_path) || '*'
    @links.push %[<link rel="icon" href="#{@icon_path}" type="image/#{ext}" />]
    @links.push %[<link rel="apple-touch-icon" href="#{@icon_path}" type="image/#{ext}" />]

    meta = []
    meta.push '<meta charset="UTF-8">'
    
    for k,v in @meta
      if v
        v.gsub!('"', '&quot;')
        name = k.starts_with?('og:') ? :property : :name
        meta.push %[<meta #{name}="#{k}" content="#{v}" />]
      end
    end

    ret += meta.sort
    ret += @links

    if block_given?
      ret.push render_data
    end

    if Lux.current.no_cache?
      ret.push %[<script>window.noCache = true;</script>]
    end

    # title
    app_name = @app || Lux.config.app.name
    title    = @title ? "#{@title} | #{app_name}" : app_name
    ret.push %[<title>#{title}</title>]

    data = ret.join("\n")
    data = data.gsub("\n<","\n  <").gsub(/\n\s*\n/,"\n")

    '  '+data
  end
end

# X-Robots-Tag h

#   noindex
#  "nofollow" -> do not to follow (i.e., crawl) any outgoing links on the page.

# - "noarchive"

# <link rel="apple-touch-icon" href="/apple-touch-icon.png"/>
# <link rel="canonical" href="https://flowmapp.com/" />
# <meta name="description" content="FlowMapp is online planning tool for creating a visual sitemap that will help you effectively design and plan a better UX for your websites."/>

# <meta property="og:locale" content="en_US" />
# <meta property="og:type" content="article" />
# <meta property="og:title" content="FlowMapp - UX planning tool" />
# <meta property="og:description" content="FlowMapp is online planning tool for creating a visual sitemaps that will help you effectively design and plan a better UX for your websites." />
# <meta property="og:url" content="https://flowmapp.com/" />
# <meta property="og:site_name" content="FlowMapp" />
# <meta property="og:image" content="https://flowmapp.com/wp-content/uploads/2018/07/user_flow_snippet.png" />

# <meta name="twitter:image" content="https://flowmapp.com/wp-content/uploads/2018/07/user_flow_snippet.png"/>
# <meta name="twitter:card" content="summary_large_image" />
# <meta name="twitter:description" content="FlowMapp is next-generation online planning tool for creating a visual sitemap that will help you effectively design and plan a better UX for your websites." />
# <meta name="twitter:title" content="FlowMapp - UX planning tool" />
# <meta name="twitter:site" content="@flowmapp" />
# <meta name="twitter:image" content="https://flowmapp.com/wp-content/uploads/2018/07/User-flow-teaser-2.png" />
# <meta name="twitter:creator" content="@flowmapp" />
