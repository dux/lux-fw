require_relative './view_cell'

module Lux
  class ViewCell
    RENDER_CACHE ||= {}

    def initialize parent = nil, vars = {}
      @_parent = parent
      vars.each { |k, v| instance_variable_set "@#{k}", v }
      before
    end

    # runs once from initialize; override or use the class-level before { }
    def before
    end

    # access parent scope
    def parent &block
      if block
        @_parent.instance_exec self, &block
      else
        @_parent
      end
    end

    def cell *args
      Lux::ViewCell.cell @_parent, *args
    end

    # render template by name
    def template name
      path = if template_root = self.class.template_root
        [template_root, name].join '/'
      else
        [File.dirname(caller[0]), name].join '/'
      end

      class_part = self.class.to_s.underscore.sub(/_cell$/, '')
      path = path % class_part if path.include?('%s')

      RENDER_CACHE.delete(path) if Lux.env.dev?
      tilt = RENDER_CACHE[path] ||= begin
        file_name = if path =~ /\.\w{2,4}$/
          path
        else
          ext = Lux::Template.tilt_extensions.find { |e| (f = Lux.root.resolve("#{path}.#{e}")) && f.exist? }
          ext && Lux.root.resolve("#{path}.#{ext}").to_s
        end
        raise ArgumentError, 'Template "%s.*" not found' % [path.sub(Dir.pwd, '.')] unless file_name && File.exist?(file_name)
        Lux.ctx.files_in_use file_name
        Tilt.new(file_name)
      end

      data = Lux::Template.wrap_with_debug_info(tilt.file, tilt.render(self))
      Lux::SafeString.new data
    end
  end
end
