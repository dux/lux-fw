class PageMeta
  attr_accessor :app

  def initialize app = nil
    @meta      = {}
    @links     = []
    @scripts   = []
    @site_name = app
  end

  def meta name, desc
    @meta[name.to_s] = desc.to_s
  end

  # preload fonts
  def preload resource
    type = 'font/%s' % resource.split('.').last
    @links.push %[<link rel="preload" href="#{resource}" as="font" type="#{type}" crossorigin="anonymous" />]
  end

  def description data
    return @description unless data.present?
    data = data.trim(140)
    @meta['description'] = data
    @meta['og:description'] = data
    @meta['twitter:description'] = data
  end
  alias_method :description=, :description

  def link rel, href
    @links.push '<link rel="%s" href="%s" />' % [rel, href]
  end

  def type kind
    @og_type = kind
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

  def site_name name
    @site_name = name if name
  end

  def noindex
    @noindex = true
  end

  def nofollow
    @nofollow = true
  end

  def rss url, title = nil
    @links.push %[<link rel="alternate" type="application/rss+xml" title="#{title || 'RSS feed'}" href="#{url}" />]
  end

  def sitemap link
    @links.push %[<link rel="sitemap" type="application/xml" title="Sitemap" href="#{link}" />]
  end

  # last modified date
  def revised date_time
    meta :revised, date_time.iso8601
  end

  def image url
    return unless url.present?

    url = "#{Lux.current.nav.base}#{url}" if url.start_with?('/')

    @meta['og:image'] = url
    @meta['twitter:image'] = url
    @meta['twitter:card'] = 'summary_large_image'

    # size = url.split('.').last(2).first.to_s.split('-').last.to_s.split('x')
    # if size[1].is_numeric?
    #   @meta['og:image:width']  = size[0]
    #   @meta['og:image:height'] = size[1]
    # end
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
    robots.push @noindex ? 'noindex, noarchive' : :index
    robots.push @nofollow ? :nofollow : :follow
    meta :robots, robots.join(', ')
    Lux.current.response.header 'x-robots-tag', robots.join(', ')

    # favicon
    @icon_path ||= '/favicon.svg'
    ext = File.ext(@icon_path) || '*'
    @links.push %[<link rel="icon" href="#{@icon_path}" type="image/#{ext}" />]
    @links.push %[<link rel="apple-touch-icon" href="#{@icon_path}" type="image/#{ext}" />]

    meta = []
    meta.push '<meta charset="UTF-8" />'
    @meta['og:type'] = @og_type || 'website'
    @meta['viewport'] ||= 'width=device-width, initial-scale=1'

    # title
    @site_name ||= Lux.config.app.name
    @meta['og:site_name'] = @site_name
    title = @title ? "#{@title} | #{@site_name}" : @site_name
    title = title.remove_tags

    for k,v in @meta
      if v
        v = v.gsub('"', '&quot;')
        name = k.start_with?('og:') ? :property : :name
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

    ret.push %[<title>#{title}</title>]

    data = ret.join("\n")
    data = data.gsub("\n<","\n  <").gsub(/\n\s*\n/,"\n")

    '  ' + data
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
