module Lux
  class Template
    class << self
      def wrap_with_debug_info files, data, opts = {}
        return data unless Lux.env.dev? && Lux.current.request.env['QUERY_STRING'].include?('debug=render')

        files = [files] unless files.is_a?(Array)
        files = files.compact.map do |file|
          file, prefix = file.sub(/'$/, '').sub(Lux.root.to_s, '.').split(':in `')
          prefix = ' # %s' % prefix if prefix

          %[<a href="vscode://file/%s" style="color: #fff;">%s%s</a>] % [Lux.root.join(file).to_s, file.split(':').first, prefix]
        end.join(' &bull; ')

        opts[:color] ||= '#fff'
        opts[:bgcolor] ||= '#800'

        %[<div style="border: 1px solid #{opts[:bgcolor]}; margin: 3px; padding: 35px 5px 5px 5px;">
            <span style="position: absolute; background: #{opts[:bgcolor]}; color: #{opts[:color]}; font-weight: 400; font-size: 15px; margin: -36px 0 0 -5px; padding: 2px 5px;">#{files}</span>
            #{data}
        </div>]
      end

      # scope is self or any other object
      # * methods called in templates will be called from scope
      # * scope = Lux::Template::Helper.new self, :main (prepare Rails style helper)
      # Lux::Template.render(scope, template)
      # Lux::Template.render(scope, template: template, layout: layout_file)
      # Lux::Template.render(scope, layout_template) { layout_data }
      def render scope, opts, &block
        opts = { template: opts } if opts.is_a?(String)
        opts = opts.to_hwia :layout, :template, :dev_info

        if opts.layout
          part_data = render(scope, opts.template)
          new(template: opts.layout, scope: scope, info: opts.dev_info).render { part_data }
        else
          new(template: opts.template, scope: scope, info: opts.dev_info).render &block
        end
      end

      def helper scope, name
        Lux::Template::Helper.new scope, name
      end

      def find_layout root, layout_template
        pointer = Lux.env.reload_code? ? Lux.current.var : Lux.var
        cache = (pointer[:_cached_layouts] ||= {})
        cache_key = "#{root}/#{layout_template}"

        return cache[cache_key] if cache[cache_key]

        base1 = '%s/layouts/%s.*' % [root, layout_template]
        base2 = '%s/%s/layout.*' % [root, layout_template]
        path = Dir[base1][0] || Dir[base2][0]

        if path
          cache[cache_key] = path.sub(/\.[\w]+$/, '')
        else
          raise Lux::Error.not_found(%[Layout path for #{layout_template} not found. Looked in #{base1} & #{base2}])
        end
      end
    end

    ###

    def initialize template:, scope:, info:
      template = './app/views/' + template if template =~ /^\w/

      @dev_info = info
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
      Lux.current.files_in_use(@template)

      data = @tilt.render(@helper) do
        yield if block_given?
      end

      Lux::Template.wrap_with_debug_info @template, data

    rescue => error
      if Lux.env.dev? && @dev_info
        msg = error.message
        dev_info = @dev_info
        error.define_singleton_method :message do
          "#{msg}\n - #{dev_info}"
        end
      end

      raise error
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

      @tilt = Tilt.new(@template, escape_html: false)
      pointer[template] = [@tilt, @template]
    end
  end
end


