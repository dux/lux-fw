# filters stack for call - before, before_action, :action, after
# define path_id {} to capture path ids
# if action is missing capture it via def action_missing name

module Lux
  class Controller
    include ClassCallbacks
    include ::Lux::Application::Shared

    TEMPLATE_ROOT ||= './app/views'

    # define master layout
    # string is template, symbol is method pointer and lambda is lambda
    cattr :layout, nil

    # define helper contest, by defult derived from class name
    cattr :helper, nil

    # custom template root instead calcualted one
    cattr :template_root, nil

    cattr :path_id_store
    cattr.path_id_store = [proc { raise 'path_id {} is not defined on controller' }]

    # before and after any action filter, ignored in controllers, after is called just before render
    define_callback :before
    define_callback :before_action
    define_callback :after_action
    define_callback :before_render
    define_callback :after

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

      def path_id *args, &block
        if block
          cattr.path_id_store = [block]
        else
          cattr.path_id_store[0].call(*args)
        end
      end
    end

    ### INSTANCE METHODS

    attr_reader :controller_action

    def initialize
      # before and after should be exected only once
      @lux = {}.to_hwia :executed_filters, :template_sufix, :action, :layout, :helper
      @lux.executed_filters = {}
      @lux.template_sufix = self.class.to_s.include?('::') ? self.class.to_s.sub(/Controller$/,'').underscore : self.class.to_s.sub(/Controller$/,'').downcase
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
      Lux.log { ' %s' % self.class.source_location }

      @lux.action = method_name.to_sym

      # we need to process before
      catch :done do
        filter :before, @lux.action
      end

      # if action not found
      unless respond_to?(method_name)
        action_missing method_name
      end

      catch :done do
        filter :before_action, @lux.action
        send method_name, *args
        render
      end

      filter :after, @lux.action

      throw :done
    end

    private

    # send file to browser
    def send_file file, opts={}
      response.send_file(file, opts)
    end

    # render :index
    # render 'main/root/index'
    # render text: 'ok'
    def render name=nil, opts={}
      filter :after_action, @lux.action
      filter :before_render, @lux.action

      # respond with not found
      # * if format provided /foo.png
      # * and error not triggered
      # error.not_found('%s document Not Found' % nav.format.to_s.upcase) if nav.format && !$!

      if name.class == Hash
        opts.merge! name
      else
        opts[:template] = name
      end

      opts = opts.to_hwia :text, :plain, :html, :json, :javascript, :cache, :template, :layout, :render_to_string, :data, :status, :ttl, :content_type

      response.status opts.status               if opts.status
      response.content_type = opts.content_type if opts.content_type
      opts.text             = opts.plain        if opts.plain         # match rails nameing

      page =
      if opts.cache
        Lux.cache.fetch(opts.cache, opts.ttl || 3600) { render_resolve(opts) }
      else
        render_resolve(opts)
      end

      if opts.render_to_string
        page
      else
        response.body page
      end
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

    # delegated to current
    define_method(:get?)          { request.request_method == 'GET' }
    define_method(:post?)         { request.request_method == 'POST' }
    define_method(:etag)          { |*args| current.response.etag *args }
    define_method(:layout)        { |arg = :_nil| arg == :_nil ? @lux.layout : (@lux.layout = arg) }
    define_method(:cache_control) { |arg| response.headers['cache-control'] = arg }

    # called be render
    def render_resolve opts
      # render static types
      for el in [:text, :html, :json, :javascript]
        if value = opts[el]
          response.content_type ||= el
          return value
        end
      end

      # resolve page data, without template
      page_part =
        if opts.data
          Lux.current.var.root_template_path = './views'
          opts.data
        else
          render_body(opts)
        end

      # resolve data with layout
      layout = opts.layout
      layout = nil   if layout.class == TrueClass
      layout = false if @lux.layout.class == FalseClass

      if layout.class == FalseClass
        page_part
      else
        layout_define = @lux.layout || layout || self.class.layout

        layout = case layout_define
          when String
            if layout_define.start_with?('./')
              layout_define
            else
              'layouts/%s' % layout_define
            end
          when Symbol
            'layouts/%s' % layout_define
          when Proc
            instance_execute &layout_define
          else
            'layouts/%s' % namespace
        end

        Lux::Template.render(helper, layout) { page_part }
      end
    end

    def render_body opts
      template      = (opts.template      || @lux.action).to_s
      template_root = cattr.template_root || TEMPLATE_ROOT

      template =
      if template.start_with?('./')
        # full path
        # render './apps/main/root/index'
        template
      elsif template.start_with?('/')
        # relative template root
        [template_root, template].join('')
      else
        # join with sufix but use Pathname to enable ../ joins
        Pathname
          .new(template_root)
          .join(@lux.template_sufix)
          .join(template)
          .to_s
      end

      Lux.current.var.root_template_path = template.sub(%r{/[\w]+$}, '')

      Lux::Template.render(helper, template)
    end

    def halt status, desc=nil
      response.status = status
      response.body   = desc || "Hatlt code #{status}"
    end

    def namespace
      self.class.to_s.split('::').first.underscore.to_sym
    end

    def helper ns=nil
      @lux.helper ||= Lux::Template::Helper.new self, :html, self.class.helper, ns
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
      return if @lux.executed_filters[fiter_name]
      @lux.executed_filters[fiter_name] = true

      run_callback fiter_name, arg
    end

    def cache *args, &block
      Lux.cache.fetch *args, &block
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
      path = [cattr.template_root || TEMPLATE_ROOT, @lux.template_sufix, name].join('/')

      if template = Dir['%s.*' % path].first
        unless Lux.config.use_autoroutes
          raise 'Autoroute for "%s" is found but it is disabled in Lux.config.use_autoroutes' % name
        end

        self.class.define_method(name) {}
        Lux.log ' created method %s#%s | found template %s'.yellow % [self.class, name, template]
        return
      end

      message = 'Method "%s" not found found in "%s" (nav: %s).' % [name, self.class, nav]

      if Lux.env.dev?
        defined_methods = (methods - Lux::Controller.instance_methods).map(&:to_s)
        defined = '<br /><br />Defined methods %s' % defined_methods.sort.to_ul

        if Lux.config.use_autoroutes
          root  = [cattr.template_root || TEMPLATE_ROOT, @lux.template_sufix].join('/')
          files = Dir.files(root).sort.filter {|f| f =~ /^[a-z]/ }.map {|f| f.sub(/\.\w+$/, '') }
          files = files - defined_methods
          defined += '<br />Defined via templates %s' % files.to_ul
        else
          defined += 'Defined templates - disabled'
        end
      end

      raise Lux::Error.new 500, [message, defined].join(' ')
    end
  end
end
