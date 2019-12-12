class Lux::View
  @@template_cache = {}

  class << self
    # context is self or any other object
    # * methods called in templates will be called from context
    # * context = Lux::View::Helper.new self, :main (prepare Rails style helper)
    # Lux::View.render(context, template)
    # Lux::View.render(context, template, layout_file)
    # Lux::View.render(context, layout) { layout_data }
    def render context, template, layout=nil, &block
      if layout
        part_data = render(context, template)
        new(layout, context).render { part_data }
      else
        new(template, context).render &block
      end
    end
  end

  def initialize template, context={}
    # template = template.sub(/^\//, '')
    template = './app/views/' + template if template =~ /^\w/

    @helper = if context.class == Hash
      # create helper class if only hash given
      Lux::View::Helper.new(context)
    else
      context
    end

    compile_template template
  end

  def render
    # global thread safe reference pointer to last temaplte rendered
    # we nned this for inline template render

    Lux.current.files_in_use @template

    data = nil

    speed = Lux.speed do
      begin
        data = @tilt.render(@helper) do
          yield if block_given?
        end
      rescue => e
        if Lux.config(:dump_errors)
          data = Lux::Error.inline %[Lux::View #{@template} render error], e
        else
          raise e
        end
      end
    end

    Lux.log do
      log = @template.split('app/views/').last

      if log.start_with?('./')
        log = log.sub('./', '')
      else
        log = 'app/views/%s' % log
      end

      ' %s, %s' % [log, speed]
    end

    data
  end

  private

  def compile_template template
    pointer =
    if Lux.config(:auto_code_reload)
      Lux.current.var[:cached_templates] ||= {}
    else
      Lux.var.cached_templates
    end

    if ref = pointer[template]
      @tilt, @template = *ref
      return
    end

    Tilt.default_mapping.template_map.keys.each do |ext|
      test = [template, ext].join('.')

      if File.exists?(test)
        @template = test
        break
      end
    end

    unless @template
      err  = caller.reject{ |l| l =~ %r{(/lux/|/gems/)} }.map{ |l| el=l.to_s.split(Lux.root.to_s); el[1] || l }.join("\n")
      msg  = %[Lux::View "#{template}.{erb,haml}" not found]
      msg += %[\n\n#{err}] if Lux.config(:dump_errors)

      raise msg
    end

    begin
      @tilt = Tilt.new(@template, escape_html: false)
      pointer[template] = [@tilt, @template]
    rescue
      Lux.error "#{$!.message}\n\nTemplate: #{@template}"
    end
  end

end


