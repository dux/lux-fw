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
    cattr :helper, class: true

    # custom template root instead calcualted one
    cattr :template_root, default: './app/views', class: true

    # before and after any action filter, ignored in controllers, after is called just before render
    define_callback :before
    define_callback :before_action
    define_callback :after_action
    define_callback :before_render

    class << self
      # simple shortcut allows direct call to action, bypasing call
      def action *args
        new.action(*args)
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

    IVARS ||= Struct.new 'LuxControllerIvars', :template_sufix, :action, :layout, :helper, :render_cache

    attr_reader :controller_action

    def initialize
      # before and after should be exected only once
      @lux = IVARS.new
      @lux.template_sufix = self.class.to_s.sub(/Controller$/,'').underscore.downcase.split('/').first
    end

    # action(:show)
    # action(:select', ['users'])
    def action method_name, *args
      if method_name.blank?
        raise ArgumentError.new('Controller action called with blank action name argument')
      end

      if method_name.is_a?(Symbol)
        raise ArgumentError.new('Forbiden action name :%s' % method_name) if [:action, :error].include?(method_name)
      else
        return controller_action_call(method_name, *args)
      end

      method_name = method_name.to_s.gsub('-', '_').gsub(/[^\w]/, '')

      # dev console log
      Lux.log { ' %s#%s (action)'.light_blue % [self.class, method_name] }
      # Lux.log { ' %s' % self.class.source_location }

      @lux.action = method_name.to_sym

      filter :before, @lux.action

      catch :done do
        unless response.body?
          filter :before_action, @lux.action

          # if action not found
          if respond_to?(method_name)
            send method_name, *args
          else
            action_missing method_name
          end

          render
        end
      end
    # rescue => err
    #   Lux::Error.log err
    #   Lux::Error.screen err unless err.class == Lux::Error
    #   render_error err
    end

    def timeout seconds
      Lux.current.var[:app_timeout] = seconds
    end

    def flash
      response.flash
    end

    private

    # delegated to current
    define_method(:get?)          { request.request_method == 'GET' }
    define_method(:post?)         { request.request_method == 'POST' }
    define_method(:etag)          { |*args| current.response.etag *args }
    define_method(:layout)        { |arg = :_nil| arg == :_nil ? @lux.layout : (@lux.layout = arg) }
    define_method(:cache_control) { |arg| response.headers['cache-control'] = arg }

    # send file to browser
    def send_file file, opts={}
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
    def render name = nil, opts = {}
      return if response.body?

      if name.class == Hash
        opts.merge! name
      else
        opts[:template] = name
      end

      opts = opts.to_hwia :text, :plain, :html, :json, :javascript, :cache, :template, :layout, :render_to_string, :data, :status, :ttl, :content_type

      # set response status and content_type
      response.status opts.status if opts.status
      response.content_type = opts.content_type if opts.content_type

      # match rails nameing
      opts.text = opts.plain if opts.plain

      # copy value from render_cache
      opts.cache = @lux.render_cache if @lux.render_cache

      # we do not want to cache pages that have flashes in response
      opts.cache = nil if response.flash.present?

      # render static types
      for el in [:text, :html, :json, :javascript]
        if value = opts[el]
          response.body value, content_type: el
        end
      end

      data = if cache = opts.cache
        return if etag(cache)

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
      else
        render_template(opts)
      end

      response.body data
    end

    def render_template opts
      filter :after_action, @lux.action
      filter :before_render, @lux.action

      # prepare helper from layout, if possible
      inline_helpers = self.helper(opts.layout)
      
      page_template = cattr.template_root + opts.template.to_s
      Lux.current.var.root_template_path = page_template.sub(%r{/[\w]+$}, '')
      data = Lux::Template.render(inline_helpers, page_template)

      layout_template = [opts.layout, @lux.layout, self.class.cattr.layout].select { ! _1.nil? }.first
      if layout_template
        layout_template = cattr.template_root  + '/layouts/' + layout_template.to_s
        data = Lux::Template.render(inline_helpers, layout_template) { data }
      end

      data
    end

    def namespace
      self.class.to_s.split('::').first.underscore.to_sym
    end

    def helper ns = nil
      inline_helpers = [@lux.layout, ns].compact.map do |l|
        Object.const_defined?("#{l}_helper".classify) ? l : nil
      end
      Lux::Template::Helper.new self, :html, self.class.helper, inline_helpers
    end

    # respond_to :js do ...
    # respond_to do |format| ...
    def respond_to ext=nil
      if ext
        if ext == nav.format
          yield if block_given?
          true
        elsif nav.format
          error.not_found '%s document Not Found' % nav.format.to_s.upcase
        end
      else
        yield nav.format
      end
    end

    # because we can call action multiple times
    # ensure we execute filters only once
    def filter fiter_name, arg=nil
      Lux.current.once 'lux-controller-filter-%s-%s' % [self.class, fiter_name] do
        run_callback fiter_name, arg
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
      elsif object.is_a?(Array)
        object, action = controller_action
      else
        raise ArgumentError.new('Not supported')
      end

      object.action action.to_sym, *args
    end

    def action_missing name
      path = [cattr.template_root, @lux.template_sufix, name].join('/')

      if template = Dir['%s.*' % path].first
        unless Lux.config.use_autoroutes
          raise 'Autoroute for "%s" is found but it is disabled in Lux.config.use_autoroutes' % name
        end

        self.class.define_method(name) {}
        Lux.log ' created method %s#%s | found template %s'.yellow % [self.class, name, template]
        return true
      else
        # if called via super from `action_missing', return false,
        # so once can easily fallback to custom template search pattern
        return false if caller[0].include?("`action_missing'")
      end

      message = 'Method "%s" not found found in "%s" (nav: %s).' % [name, self.class, nav]

      if Lux.env.dev?
        defined_methods = (methods - Lux::Controller.instance_methods).map(&:to_s)
        defined = '<br /><br />Defined methods %s' % defined_methods.sort.to_ul

        if Lux.config.use_autoroutes
          root  = [cattr.template_root, @lux.template_sufix].join('/')
          files = Dir.files(root).sort.filter {|f| f =~ /^[a-z]/ }.map {|f| f.sub(/\.\w+$/, '') }
          files = files - defined_methods
          defined += '<br />Defined via templates in %s%s' % [root, files.to_ul]
        else
          defined += 'Defined templates - disabled'
        end
      end

      raise Lux::Error.new 404, [message, defined].join(' ')
    end
  end
end
