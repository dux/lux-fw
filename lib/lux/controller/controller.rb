# filters stack for call - before, before_action, :action, after
# if action is missing capture it via def action_missing name

require 'erb'
require_relative '../lifecycle'

module Lux
  class Controller
    include ClassCallbacks
    include Lifecycle

    DEFAULT_ERROR_TEMPLATE ||= ERB.new(File.read(File.expand_path('error_page.html.erb', __dir__)))

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

      # Sugar for defining the :error action via a block.
      # The block receives the exception as an argument; @error and @status
      # are already set as ivars by Application#render_error before it runs.
      #   rescue_from do |err|
      #     render :error_500
      #   end
      def rescue_from &block
        define_method(:error) { instance_exec(@error, &block) }
      end

      # Groups action definitions that handle ID-bearing URLs. Every `def NAME`
      # inside the block is renamed to `NAME_ref` after the block runs, matching
      # the routing rule that paths containing `:ref` resolve to `<action>_ref`.
      #
      #   class UsersController < Lux::Controller
      #     def edit       # /users/edit   -> :edit
      #     end
      #
      #     ref do
      #       def edit     # /users/123/edit -> :edit_ref
      #         @user = User.find(nav.id)
      #       end
      #
      #       def show     # /users/123 -> :show_ref
      #       end
      #     end
      #   end
      #
      # Snapshot-diff approach: capture instance_methods before/after `class_eval`
      # and rename whatever the block introduced. Public + private both captured.
      # If the block REDEFINES an existing method (e.g. `def foo` exists outside
      # and `def foo` also inside `ref do`), the inner impl becomes `foo_ref`
      # and the outer impl is restored as `foo`.
      def ref &block
        before = {}
        (instance_methods(false) + private_instance_methods(false)).each do |n|
          before[n] = instance_method(n)
        end

        class_eval(&block)

        (instance_methods(false) + private_instance_methods(false)).each do |n|
          next if n.to_s.end_with?('_ref')
          after_impl  = instance_method(n)
          before_impl = before[n]

          if before_impl.nil?
            # newly defined inside the block - rename to _ref
            remove_method(n)
            define_method(:"#{n}_ref", after_impl)
          elsif before_impl != after_impl
            # redefined - inner impl is the _ref version, restore outer
            remove_method(n)
            define_method(n, before_impl)
            define_method(:"#{n}_ref", after_impl)
          end
        end
      end

      # Self-contained HTML error page (no template lookup). Used by the default
      # Lux::Controller#error action; can be called directly from a custom :error
      # to wrap the framework chrome around your own content.
      def default_error_page status, error
        name      = ::Rack::Utils::HTTP_STATUS_CODES[status] || 'Error'
        message   = error.message.to_s.gsub('<', '&lt;').gsub('>', '&gt;')
        show_dev  = Lux.env.dev? || Lux.env.log?
        backtrace = (show_dev && error.respond_to?(:backtrace) && error.backtrace) ?
                    error.backtrace.first(40).join("\n").gsub('<', '&lt;').gsub('>', '&gt;') : nil
        color     = status >= 500 ? '#dc2626' : status >= 400 ? '#d97706' : '#374151'

        DEFAULT_ERROR_TEMPLATE.result(binding)
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

      if method_name == :action
        raise Lux.error.internal_server_error('Forbiden action name :%s' % method_name)
      end

      method_name = method_name.to_s.gsub('-', '_').gsub(/[^\w]/, '')

      # dev console log
      Lux.log { ' %s#%s (action)'.colorize(:light_blue) % [self.class, method_name] }
      # Lux.log { ' %s' % self.class.source_location }

      @lux.action = method_name.to_sym

      run_callback :before, @lux.action

      catch :done do
        unless lux.response.body?
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
      lux.response.flash
    end

    # Default :error action — renders a self-contained HTML page (no template lookup).
    # Override on any controller (def error) or via the rescue_from class macro.
    # Reads @error and @status set by Application#render_error before dispatch.
    def error
      @status ||= (lux.response.status.to_i >= 400 ? lux.response.status : 500)
      lux.response.status @status

      if lux.nav.format.to_s == 'json' || request.content_type.to_s.include?('json')
        render json: { status: @status, error: @error.message }
      else
        render html: self.class.default_error_page(@status, @error)
      end
    end

    private

    def redirect_to where, flash = {}
      lux.response.redirect_to where, flash
    end

    # delegated to current — use lux.request.get?, lux.request.post?, etc. for HTTP method checks
    define_method(:etag)          { |*args| lux.response.etag *args }
    define_method(:layout)        { |arg = :_nil| arg == :_nil ? @lux.layout : (@lux.layout = arg) }
    define_method(:cache_control) { |arg| lux.response.headers['cache-control'] = arg }

    # send file to browser
    def send_file file, opts = {}
      lux.response.send_file(file, opts)
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
      return if lux.response.body?

      opt = normalize_render_opts(name, opts)

      lux.response.status opt.status if opt.status
      lux.response.content_type = opt.content_type if opt.content_type

      return if render_static(opt)

      data = opt.cache ? render_cached(opt) : render_template(opt)
      lux.response.body data
    end

    # normalize render arguments into a RENDER_OPTS struct
    def normalize_render_opts name, opts
      if name.is_a?(Hash)
        opts.merge! name
      else
        opts[:template] = name
      end

      opt = RENDER_OPTS.new **opts
      opt.text = opt.plain if opt.plain
      opt.cache = @lux.render_cache if @lux.render_cache
      opt.cache = nil if lux.response.flash.present?
      opt.layout ||= @lux.layout.nil? ? self.class.cattr.layout : @lux.layout
      opt
    end

    # render static content types directly to response body
    # returns truthy if a static type was rendered
    def render_static opt
      for el in [:text, :html, :json, :javascript, :xml]
        if value = opt[el]
          lux.response.body value, content_type: el
          return true
        end
      end

      nil
    end

    # render template with page-level caching and etag support
    def render_cached opt
      return if etag(opt.cache)

      add_info = true
      from_cache = Lux.cache.fetch opt.cache, ttl: 1_000_000 do
        add_info = false
        render_template(opt)
      end

      if add_info && from_cache
        lux.response.header['x-lux-cache'] = 'render-cache'
        from_cache += '<!-- from page cache -->' if from_cache =~ %r{</html>\s*$}
      end

      from_cache
    end

    # compile and render a template with layout
    def render_template opt
      run_callback :before_render, @lux.action

      helper_name = opt.layout || @lux.layout || cattr.layout
      local_helper = self.helper helper_name

      # Default template name derives from the action. Strip the `_ref` suffix
      # that ref-bearing resourceful actions carry (`def show` inside `ref do`
      # is registered as `:show_ref`), so `show.haml` is shared between `:show`
      # and `:show_ref`. Explicit `render template: 'show_ref'` overrides.
      template = (opt.template || @lux.action.to_s.sub(/_ref$/, '')).to_s.sub(/^\//, '')
      page_template = if template.include?('/')
        [cattr.template_root, template].join('/')
      else
        [cattr.template_root, helper_name, template].compact.join('/')
      end
      Lux.current.var['views_root'] ||= cattr.template_root
      Lux.current.var.root_template_path = page_template.sub(%r{/[\w]+$}, '')
      data = opt.inline || Lux::Template.render(local_helper, {template: page_template, dev_info: "Helper: #{helper_name.to_s.classify}Helper, Template: #{page_template}" })

      if opt.layout
        path = Lux::Template.find_layout cattr.template_root, opt.layout
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
        if ext == lux.nav.format
          yield if block_given?
          true
        elsif lux.nav.format
          Lux.error.not_found '%s document Not Found' % lux.nav.format.to_s.upcase
        end
      else
        yield lux.nav.format
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

      message = 'Method "%s" not found found in "%s" (nav: %s).' % [name, self.class, lux.nav]

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

      Lux.error 404, [message, defined].join(' ')
    end
  end
end
