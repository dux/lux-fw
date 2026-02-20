module Lux
  class Template
    module Helper
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

      # renders just template but it is called
      # = render :_link, link:link
      # = render 'main/links/_link', link:link
      def render name = nil, locals = {}
        if !name
          return InlineRenderProxy.new(self)
        elsif name.is_array?
          return name.map { |b| render(b) }.join("\n")
        elsif name.respond_to?(:db_schema)
          raise 'not supported'
          path = Lux.current.var.root_template_path.split('/')[1]
          table_name = name.class.name.tableize
          locals[table_name.singularize.to_sym] = name
          instance_variable_set("@_#{table_name.singularize}", name)
          name = "#{path}/#{table_name}/_#{table_name.singularize}"
        elsif !name.to_s.start_with?('./')
          template_path = Lux.current.var.root_template_path || './app/views'
          name = Pathname.new(template_path).join(name.to_s).to_s
          name = './app/views' + name if name.starts_with?('/')
        end

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
