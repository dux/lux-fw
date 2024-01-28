module Lux
  class Template
    @@template_cache = {}

    class << self
      # scope is self or any other object
      # * methods called in templates will be called from scope
      # * scope = Lux::Template::Helper.new self, :main (prepare Rails style helper)
      # Lux::Template.render(scope, template)
      # Lux::Template.render(scope, template: template, layout: layout_file)
      # Lux::Template.render(scope, layout_template) { layout_data }
      def render scope, opts, &block
        opts = { template: opts } if opts.is_a?(String)
        opts = opts.to_hwia :layout, :template

        if opts.layout
          part_data = render(scope, opts.template)
          new(template: opts.layout, scope: scope).render { part_data }
        else
          new(template: opts.template, scope: scope).render &block
        end
      end

      def helper scope, name
        Lux::Template::Helper.new scope, name
      end

      def find_layout root, layout_template
        path = Lux.cache.fetch "layout-path-#{root}-#{layout_template}" do
          base1 = '%s/layouts/%s.*' % [root, layout_template]
          base2 = '%s/%s/layout.*' % [root, layout_template]
          path = Dir[base1][0] || Dir[base2][0]

          if path
            path.sub /\.[\w]+$/, ''
          else
            raise Lux::Error.not_found(%[Layout path for #{layout_template} not found. Looked in #{base1} & #{base2}])
          end
        end
      end
    end

    ###

    def initialize template:, scope:
      template = './app/views/' + template if template =~ /^\w/

      @helper = if scope.class == Hash
        # create helper class if only hash given
        Lux::Template::Helper.new(scope)
      else
        scope
      end

      compile_template template
    end

    def render
      # global thread safe reference pointer to last temaplte rendered
      # we nned this for inline template render
      Lux.current.files_in_use(@template) do |tpl|
        Lux.log ' ' + tpl.sub('//', '/').magenta
      end

      begin
        data = @tilt.render(@helper) do
          yield if block_given?
        end
      rescue => e
        report_error(e)
      end

      data
    end

    private

    def compile_template template
      pointer =
      if Lux.env.reload_code?
        Lux.current.var
      else
        Lux.var
      end

      pointer = (pointer[:_cached_templates] ||= {})

      if ref = pointer[template]
        @tilt, @template = *ref
        return
      end

      Tilt.default_mapping.template_map.keys.each do |ext|
        test = [template, ext].join('.')

        if File.exist?(test)
          @template = test
          break
        end
      end

      unless @template
        msg = %[Lux::Template "#{template}.{erb,haml}" not found]
        raise Lux::Error.not_found(msg)
      end

      begin
        @tilt = Tilt.new(@template, escape_html: false)
        pointer[template] = [@tilt, @template]
      rescue => e
        report_error(e)
      end
    end

    def report_error e
      if Lux.current.error
        raise Lux.current.error
      else
        Lux.current.error = e
        Lux.log ' %s (HAS ERROR)' % @template.red
        raise e
      end
    end
  end
end


