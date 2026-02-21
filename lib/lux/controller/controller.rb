# filters stack for call - before, before_action, :action, after
# if action is missing capture it via def action_missing name

module Lux
  class Controller
    include ClassCallbacks
    include ::Lux::Application::Shared

    # define master layout
    # string is template, symbol is method pointer and lambda is lambda
    cattr :layout, class: true

    # define helper contest, by defult derived from class name
    # cattr :helper, class: true

    # custom template root instead calcualted one
    cattr :template_root, default: './app/views', class: true

    # before and after any action filter, ignored in controllers, after is called just before render
    define_callback :before
    define_callback :before_action
    define_callback :before_render
    define_callback :after

    class << self
      # simple shortcut allows direct call to action, bypasing call
      def action *args, **kwargs
        new.action(*args, **kwargs)
      end

      # render a template in this controller's scope without action dispatch
      # skips before/after callbacks — just renders template with layout and helpers
      # MainController.render_template(:error_404)
      # MainController.render_template(:error_404, self)
      def render_template template, scope = nil
        ctrl = new
        if scope
          scope.instance_variables_hash.each { |k, v| ctrl.instance_variable_set(k, v) }
        end
        ctrl.send(:render, template.to_sym)
      end

      # create mock function, to enable template rendering
      # mock :index, :login
      def mock *args
        args.each do |el|
          define_method(el) { true }
        end
      end

    end

    ### INSTANCE METHODS

    IVARS ||= Struct.new 'LuxControllerIvars', :template_suffix, :action, :layout, :render_cache
    RENDER_OPTS ||= Struct.new 'LuxControllerRenderOpts', :inline, :text, :plain, :html, :json, :javascript, :xml, :cache, :template, :layout, :render_to_string, :status, :ttl, :content_type

    attr_reader :controller_action

    def initialize
      # before and after should be exected only once
      @lux = IVARS.new
      @lux.template_suffix = self.class.to_s.sub(/Controller$/,'').underscore.downcase.split('/').first
    end

    # action(:show)
    # action(:select', ['users'])
    def action method_name, args: [], ivars: {}
      if method_name.blank?
        raise ArgumentError.new('Controller action called with blank action name argument')
      end

      ivars.each { |k, v| instance_variable_set(k, v) }

      method_name = method_name.to_sym unless method_name.is_a?(Symbol)

      if [:action, :error].include?(method_name)
        raise Lux.error.internal_server_error('Forbiden action name :%s' % method_name)
      end

      method_name = method_name.to_s.gsub('-', '_').gsub(/[^\w]/, '')

      # dev console log
      Lux.log { ' %s#%s (action)'.colorize(:light_blue) % [self.class, method_name] }
      # Lux.log { ' %s' % self.class.source_location }

      @lux.action = method_name.to_sym

      run_callback :before, @lux.action

      catch :done do
        unless response.body?
          run_callback :before_action, @lux.action

          # if action not found
          if respond_to?(method_name)
            send method_name, *args
          else
            action_missing method_name
          end

          render
        end
      end

      run_callback :after, @lux.action
    end

    def timeout seconds
      Lux.current.var[:app_timeout] = seconds
    end

    def flash
      response.flash
    end

    private

    # delegated to current — use request.get?, request.post?, etc. for HTTP method checks
    define_method(:etag)          { |*args| current.response.etag *args }
    define_method(:layout)        { |arg = :_nil| arg == :_nil ? @lux.layout : (@lux.layout = arg) }
    define_method(:cache_control) { |arg| response.headers['cache-control'] = arg }

    # send file to browser
    def send_file file, opts = {}
      response.send_file(file, opts)
    end

    # does not set the body, returns body string
    def render_to_string name=nil, opts={}
      opts[:render_to_string] = true
      render name, opts
    end

    # shortcut to render javascript
    def render_javascript name=nil, opts={}
      opts[:content_type] = :javascript
      opts[:layout]       = false
      render name, opts
    end

    # render :index
    # render 'main/root/index'
    # render text: 'ok'
    # render json: { a: 1 }
    # render html: '<h1>hi</h1>', status: 200
    def render name = nil, opts = {}
      return if response.body?

      opts = normalize_render_opts(name, opts)

      response.status opts.status if opts.status
      response.content_type = opts.content_type if opts.content_type

      return if render_static(opts)

      data = opts.cache ? render_cached(opts) : render_template(opts)
      response.body data
    end

    # normalize render arguments into a RENDER_OPTS struct
    def normalize_render_opts name, opts
      if name.is_a?(Hash)
        opts.merge! name
      else
        opts[:template] = name
      end

      opts = RENDER_OPTS.new **opts

      # match rails naming
      opts.text = opts.plain if opts.plain

      # copy value from render_cache
      opts.cache = @lux.render_cache if @lux.render_cache

      # we do not want to cache pages that have flashes in response
      opts.cache = nil if response.flash.present?

      # define which layout we use
      opts.layout ||= @lux.layout.nil? ? self.class.cattr.layout : @lux.layout

      opts
    end

    # render static content types directly to response body
    # returns truthy if a static type was rendered
    def render_static opts
      for el in [:text, :html, :json, :javascript, :xml]
        if value = opts[el]
          response.body value, content_type: el
          return true
        end
      end

      nil
    end

    # render template with page-level caching and etag support
    def render_cached opts
      return if etag(opts.cache)

      add_info = true
      from_cache = Lux.cache.fetch opts.cache, ttl: 1_000_000 do
        add_info = false
        render_template(opts)
      end

      if add_info && from_cache
        response.header['x-lux-cache'] = 'render-cache'
        from_cache += '<!-- from page cache -->' if from_cache =~ %r{</html>\s*$}
      end

      from_cache
    end

    # compile and render a template with layout
    def render_template opts
      run_callback :before_render, @lux.action

      helper_name = opts.layout || @lux.layout || cattr.layout
      local_helper = self.helper helper_name

      template = (opts.template || @lux.action).to_s.sub(/^\//, '')
      page_template = if template.include?('/')
        [cattr.template_root, template].join('/')
      else
        [cattr.template_root, helper_name, template].compact.join('/')
      end
      Lux.current.var['views_root'] ||= cattr.template_root
      Lux.current.var.root_template_path = page_template.sub(%r{/[\w]+$}, '')
      data = opts.inline || Lux::Template.render(local_helper, {template: page_template, dev_info: "Helper: #{helper_name.to_s.classify}Helper, Template: #{page_template}" })

      if opts.layout
        path = Lux::Template.find_layout cattr.template_root, opts.layout
        data = Lux::Template.render(local_helper, path) { data }
      end

      data
    end

    def namespace
      self.class.to_s.split('::').first.underscore.to_sym
    end

    HELPERS ||= {}
    def helper helper
      HELPERS[helper] ||= Class.new Object do
        include Lux::Template::Helper
        include HtmlHelper
        include ApplicationHelper
        include "#{helper.to_s.classify}Helper".constantize if helper.present?
      end

      ctx = HELPERS[helper].new

      for k, v in instance_variables_hash
        ctx.instance_variable_set("@#{k.to_s.sub('@','')}", v)
      end

      ctx
    end

    # respond_to :js do ...
    # respond_to do |format| ...
    def respond_to ext=nil
      if ext
        if ext == nav.format
          yield if block_given?
          true
        elsif nav.format
          Lux.error.not_found '%s document Not Found' % nav.format.to_s.upcase
        end
      else
        yield nav.format
      end
    end

    def cache *args, &block
      Lux.cache.fetch *args, &block
    end

    def render_cache key = :_nil
      if key == :_nil
        @lux.render_cache
      else
        unless @lux.render_cache == false
          @lux.render_cache = key
        end
      end
    end

    def controller_action_call controller_action, *args
      object, action = nil

      if controller_action.is_a?(String)
        object, action = controller_action.split('#') if controller_action.include?('#')
        object = ('%s_controller' % object).classify.constantize
      elsif controller_action.is_a?(Array)
        object, action = controller_action
      else
        raise ArgumentError.new('Not supported')
      end

      object.action action.to_sym, *args
    end

    def action_missing name
      path = [cattr.template_root, @lux.template_suffix, name].join('/')

      if template = Dir['%s.*' % path].first
        unless Lux.config.use_autoroutes
          raise 'Autoroute for "%s" is found but it is disabled in Lux.config.use_autoroutes' % name
        end

        self.class.define_method(name) {}
        Lux.log ' created method %s#%s | found template %s'.colorize(:yellow) % [self.class, name, template]
        return true
      else
        # if called via super from `action_missing', return false,
        # so once can easily fallback to custom template search pattern
        return false if caller[0].include?("`action_missing'")
      end

      message = 'Method "%s" not found found in "%s" (nav: %s).' % [name, self.class, nav]

      if Lux.env.log?
        defined_methods = (methods - Lux::Controller.instance_methods).map(&:to_s)
        defined = '<br /><br />Defined methods %s' % defined_methods.sort.to_ul

        if Lux.config.use_autoroutes
          root  = [cattr.template_root, @lux.template_suffix].join('/')
          files = Dir.files(root).sort.filter {|f| f =~ /^[a-z]/ }.map {|f| f.sub(/\.\w+$/, '') }
          files = files - defined_methods
          defined += '<br />Defined via templates in %s%s' % [root, files.to_ul]
        else
          defined += 'Defined templates - disabled'
        end
      end

      raise Lux::Error.not_found [message, defined].join(' ')
    end
  end
end
