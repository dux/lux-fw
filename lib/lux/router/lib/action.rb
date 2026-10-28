# Actions and rendering for Lux::Router.
#
#   action             # resourceful, name read off the route cursor
#   action :show       # explicit; inside an action it transfers without rerunning before
#
# An action runs: only/except gates, verb check, params validation, the method,
# then the implicit render of <views dir>/<action>. `render` and `redirect_to`
# write the body and throw :done, so nothing after them runs.
module Lux
  class Router
    module Action
      def action name = nil
        resourceful = name.nil?
        name ||= resourceful_action(Lux.ctx.route.path)
        name = action_key(name)

        if name == :action
          raise Lux.error.internal_server_error('Forbiden action name :%s' % name)
        end

        if @_lux.only && !@_lux.only.include?(name)
          raise Lux.error.not_found Lux.debug?('404 Not Found') { "Action :#{name} not allowed on #{self.class}, allowed are: #{@_lux.only}" }
        end

        if @_lux.except&.include?(name)
          raise Lux.error.not_found Lux.debug?('404 Not Found') { "Action :#{name} not allowed on #{self.class}, forbidden are: #{@_lux.except}" }
        end

        Lux.log { ' %s#%s (action)'.colorize(:light_blue) % [self.class, name] }

        @_lux.action = name
        # what actually served the request; `lux render -i` prints it
        Lux.ctx.var[:dispatch] = { router: self.class.name, action: name }

        # An error page (dispatched by Router#render_error) renders without the
        # verb check and param validation - they already ran, or are what failed.
        unless Lux.ctx.var[:error_page]
          enforce_allowed_verbs!
          validate_action_params!
        end

        unless Lux.ctx.response.body?
          if respond_to?(name) && (!resourceful || app_defined_action?(name))
            send name
          else
            action_missing name
          end
        end

        render
      end

      def flash
        Lux.ctx.response.flash
      end

      private

      define_method(:etag)          { |*args, **kw| Lux.ctx.response.etag(*args, **kw) }
      define_method(:cache_control) { |arg| Lux.ctx.response.headers['cache-control'] = arg }

      # layout          -> current runtime layout
      # layout :dialog  -> layout, views dir and helper for the rest of this router
      # layout false    -> no layout
      def layout name = :_nil
        name == :_nil ? @_lux.layout : (@_lux.layout = name)
      end

      def send_file file, opts = {}
        Lux.ctx.response.send_file(file, opts)
      end

      # Renders and returns the markup without touching the response body.
      def render_to_string name = nil, opts = {}
        opts[:render_to_string] = true
        render name, opts
      end

      def render_javascript name = nil, opts = {}
        opts[:content_type] = :javascript
        opts[:layout]       = false
        render name, opts
      end

      # render                       # template named after the action
      # render :index
      # render 'main/root/index'
      # render text: 'ok'
      # render json: { a: 1 }
      # render html: '<h1>hi</h1>', status: 200
      def render name = nil, opts = {}
        opt = normalize_render_opts(name, opts)

        # render_to_string is a pure "give me the markup" call - it must not read
        # or write the response, so it bypasses the body? guard below.
        return render_template(opt) if opt.render_to_string

        throw :done if Lux.ctx.response.body?

        Lux.ctx.response.status opt.status if opt.status
        Lux.ctx.response.content_type = opt.content_type if opt.content_type

        unless render_static(opt)
          # page cache keeps full documents only; body-only pjax responses render fresh
          cached = opt.cache && !request.env['HTTP_X_PJAX_LAYOUT']
          Lux.ctx.response.body(cached ? render_cached(opt) : render_template(opt))
        end

        throw :done
      end

      def normalize_render_opts name, opts
        if name.is_hash?
          opts.merge! name
        else
          opts[:template] = name
        end

        opt = RENDER_OPTS.new **opts
        opt.text = opt.plain if opt.plain
        opt.cache = @_lux.render_cache if @_lux.render_cache
        opt.cache = nil if Lux.ctx.var[:error_page] || Lux.ctx.response.flash.present?
        opt.layout = (@_lux.layout.nil? ? self.class.cattr.layout : @_lux.layout) if opt.layout.nil?
        opt
      end

      # render static content types directly to response body
      # returns truthy if a static type was rendered
      def render_static opt
        for el in [:text, :html, :json, :javascript, :xml]
          if value = opt[el]
            Lux.ctx.response.body value, content_type: opt.content_type || el
            return true
          end
        end

        nil
      end

      # render template with page-level caching and etag support
      def render_cached opt
        return if etag(opt.cache)

        add_info = true
        from_cache = Lux.cache.fetch opt.cache, ttl: opt.ttl || 1_000_000 do
          add_info = false
          render_template(opt)
        end

        if add_info && from_cache
          Lux.ctx.response.header['x-lux-cache'] = 'render-cache'
          from_cache += '<!-- from page cache -->' if from_cache =~ %r{</html>\s*$}
        end

        from_cache
      end

      # compile and render a template with layout
      def render_template opt
        run_callback :before_render, @_lux.action

        view_dir     = template_dir
        helper_name  = cattr.helper || @_lux.layout || cattr.layout
        local_helper = self.helper helper_name

        # Template path comes from the action name verbatim.
        template = (opt.template || @_lux.action).to_s.sub(/^\//, '')
        page_template = build_template_path(template, view_dir)

        Lux.ctx.var['views_root'] ||= cattr.template_root
        Lux.ctx.var.root_template_path = page_template.sub(%r{/[^/]+$}, '')
        data = opt.inline || Lux::Template.render(local_helper, {template: page_template, dev_info: "Helper: #{helper_name.to_s.classify}Helper, Template: #{page_template}" })

        if opt.layout
          path = Lux::Template.find_layout cattr.template_root, opt.layout
          Lux.ctx.browser.layout = path
          data = Lux::Template.render(local_helper, path) { data }
        end

        Lux.ctx.var[:dispatch]&.merge!(template: page_template, layout: path)

        data
      end

      def helper name = cattr.helper || @_lux.layout || cattr.layout
        Lux::Template::Helper.new self, name
      end

      # respond_to :js do ...      runs the block when the request format is :js, else false;
      #                            chain several calls, one per format
      # respond_to do |format| ... yields the request format (nil when none)
      def respond_to ext = nil
        return yield(Lux.ctx.nav.format) unless ext
        return false unless ext == Lux.ctx.nav.format

        yield if block_given?
        true
      end

      # Like respond_to, but a request for any other explicit format is a 404.
      # A request without a format (plain html) falls through with false.
      def respond_to! ext, &block
        return true if respond_to(ext, &block)
        return false unless Lux.ctx.nav.format

        raise Lux.error.not_found Lux.debug?('404 Not Found') { '%s document Not Found' % Lux.ctx.nav.format.to_s.upcase }
      end

      def cache *args, &block
        Lux.cache.fetch *args, &block
      end

      # View subfolder under template_root. `views :foo` overrides it; otherwise it
      # follows the runtime layout, then the class layout. Used by auto_render,
      # which has no per-render layout option.
      def template_dir
        cattr.views || @_lux.layout || cattr.layout
      end

      # Build a "<template_root>/<dir>/<name>" path (or "<template_root>/<name>"
      # when the name already contains a slash). No extension - extension probing
      # lives in Lux::Template.compile_template.
      def build_template_path template, dir
        if template.include?('/')
          [cattr.template_root, template].join('/')
        else
          [cattr.template_root, dir, template].compact.join('/')
        end
      end

      def render_cache key = :_nil
        if key == :_nil
          @_lux.render_cache
        else
          unless @_lux.render_cache == false
            @_lux.render_cache = key
          end
        end
      end

      # Runs this router's `route do` block, or a resourceful action when it
      # has none.
      def run_route
        blk = self.class.route_block
        blk ? instance_exec(&blk) : action
      end

      # Entry point of a mounted router: its own `before` hooks (minus those the
      # mounting router already ran), then the action or the route.
      def run_mounted action_name, parent_class
        catch :done do
          run_callback :before, skip: parent_class unless Lux.ctx.var[:error_page]

          unless Lux.ctx.response.body?
            action_name ? action(action_name) : run_route
          end
        end
      end

      # Resourceful dispatch takes the action name straight from the URL, so only
      # methods the app defined on a router subclass are reachable - never
      # framework instance methods (auto, flash, error, respond_to, ...), methods
      # defined on the root (`Lux.router do def x`) or inherited Object/Kernel
      # methods. Explicit `map 'x', :name` / 'router#name' bypasses this.
      def app_defined_action? name
        owner = method(name).owner
        owner.is_a?(Class) && owner < Lux::Router
      end

      # The single action-name sanitiser - dashes to underscores, non-word
      # characters dropped. Every dispatch and resourceful lookup goes through it.
      def action_key name
        name.to_s.tr('-', '_').gsub(/[^\w]/, '').to_sym
      end

      # No action by that name. Override on a router to add a custom lookup;
      # call `super` when your lookup also misses, to raise the 404.
      def action_missing name
        message = Lux.debug? '404 Method Not Found' do
          base = 'Method "%s" not found found in "%s" (nav: %s).' % [name, self.class, Lux.ctx.nav]
          defined_methods = (methods - Lux::Router.instance_methods).map(&:to_s)
          defined = '<br /><br />Defined methods %s' % defined_methods.sort.to_ul

          [base, defined].join(' ')
        end

        raise Lux.error 404, message
      end
    end
  end
end
