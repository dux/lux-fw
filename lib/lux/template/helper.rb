module Lux
  class Template
    module Helper
      def self.new scope, *names
        obj = Object.new
        obj.extend self
        obj.extend ApplicationHelper if defined?(ApplicationHelper)

        names.flatten.compact.each do |name|
          mod = "#{name.to_s.classify}Helper"
          obj.extend mod.constantize if mod.constantize?
        end

        local_vars = scope.class == Hash ? scope : scope.instance_variables_hash
        local_vars.each do |k, v|
          obj.instance_variable_set("@#{k.to_s.sub('@', '')}", v)
        end

        obj
      end

      define_method(:current) { Lux.current }
      define_method(:request) { Lux.current.request }
      define_method(:params)  { Lux.current.params }
      define_method(:nav)     { Lux.current.nav }
      define_method(:get)     { |name| instance_variable_get('@%s' % name) }

      def no_white_space
        yield.gsub(/>\s+</,'><')
      end

      # = content :foo do ...            # define
      # = content :foo? ? true : false   # ceheck existance
      # = content :foo                   # get content
      def content key
        name = 'haml_content_%s' % key

        if name.end_with?('?')
          haz = !!Lux.current.var[name.sub(/\?$/, '')]
          if block_given?
            haz ? "#{yield}" : ''
          else
            haz
          end
        elsif block_given?
          Lux.current.var[name] = "#{yield}"
          nil
        else
          Lux.current.var[name]
        end
      end

      def capture_proc
        proc { |*args| "#{yield(*args)}" }
      end

      # renders template by name, resolves relative to current template's directory
      # = render :_link, link:link
      # = render 'main/links/_link', link:link
      def render name = nil, locals = {}
        if !name
          return InlineRenderProxy.new(self)
        end

        name = name.to_s

        unless name.start_with?('./')
          if name.include?('/')
            # path with directory (e.g., 'shared/_widget') → resolve from views root
            views_root = Lux.current.var.views_root || './app/views'
            name = Pathname.new(views_root).join(name.delete_prefix('/')).to_s
          else
            # simple name (e.g., :_partial) → resolve relative to current template
            template_path = Lux.current.var.root_template_path || './app/views'
            name = Pathname.new(template_path).join(name).to_s
          end
        end

        # update root_template_path to this template's directory so nested
        # render calls resolve relative to the template that calls them
        previous_root = Lux.current.var.root_template_path
        Lux.current.var.root_template_path = name.sub(%r{/[^/]+$}, '')

        # scope locals per render call - save previous values, restore after render
        saved = {}
        for k, v in locals
          ivar = "@_#{k}"
          saved[ivar] = instance_variable_defined?(ivar) ? [true, instance_variable_get(ivar)] : [false]
          instance_variable_set(ivar, v)
        end

        result = if block_given?
          name = "#{name}/layout" unless name.index('/')

          Lux::Template.render(self, name) { yield() }
        else
          Lux::Template.render(self, name)
        end

        # restore previous locals so nested/sibling renders don't leak
        saved.each do |ivar, (existed, old_val)|
          if existed
            instance_variable_set(ivar, old_val)
          else
            remove_instance_variable(ivar)
          end
        end

        # restore previous root so sibling renders still resolve correctly
        Lux.current.var.root_template_path = previous_root

        result
      end

      def cache name = nil, opts = {}, &block
        if opts.class == Integer
          opts = { ttl: opts }
        elsif name.is_a?(Hash)
          opts = name
          name = ''
        else
          name = Lux.cache.generate_key(name)
        end

        opts[:ttl] ||= 1.hour
        key = 'view:' + name + block.source_location.join(':') + Lux.config.deploy_timestamp.to_s

        if etag = opts.delete(:etag)
          etag = key if etag.class != String
          Lux.current.response.etag etag
        end

        Lux.cache.fetch(key, opts) { yield }
      end

      # helper(:main).method
      def helper *names
        Lux::Template::Helper.new(self, *names)
      end

      def once id = nil
        Lux.current.once("template-#{id || caller[0]}") do
          block_given? ? yield : true
        end
      end

      def flash
        Lux.current.response.flash
      end
    end
  end
end
