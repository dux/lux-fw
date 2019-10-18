class PageMeta

  def initialize
    @meta   = {}
    @head   = []
    @links  = []
    @robots = []
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
    Lux.dev? ? %[<script src="/autoreload-check"></script>] : nil
  end

  def description data
    meta(:description, data)
  end
  alias_method :description=, :description

  def link rel, href
    @links.push '<link rel="%s" href="%s" />' % [rel, href]
  end

  def title data=nil
    return @title unless data
    @title = data.trim(100)
  end
  alias_method :title=, :title

  def robots *args
    raise ArgumentError.new('Unsupported robots decalaration %s' % args.first) unless args - [:noindex, :nofollow] == []
    @robots += args
  end

  def image url
    @meta['og:image'] = url
  end
  alias_method :image=, :image

  def render header_id
    ret   = []

    meta 'pjax_template_id', header_id

    ret.push %[<meta name="viewport" content="width=device-width" initial-scale="1.0" maximum-scale="1.0" minimum-scale="1.0" user-scalable="no" />]

    # do not render other data if request is xhr/ajax
    # robots
    @robots.push :index unless @robots.include?(:noindex)
    @robots.push :follow unless @robots.include?(:nofollow)
    meta :robots, @robots.join(', ')
    Lux.current.response.header 'x-robots-tag', @robots.join(', ')

    # favicon
    link 'apple-touch-icon', '/favicon.png'

    for k,v in @meta
      v.gsub!('"', '&quot;')
      name = k.starts_with?('og:') ? :property : :name
      ret.push %[<meta #{name}="#{k}" content="#{v}" />]
    end

    ret += @links

    ret.push Lux.ram_cache(Crypt.sha1(caller.first)) { yield(self) } if block_given?

    # title
    title = @title ? "#{@title} | #{Lux.config.app.name}" : Lux.config.app.name
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
