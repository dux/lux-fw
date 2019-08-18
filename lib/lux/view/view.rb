class Lux::View
  @@template_cache = {}

  class << self
    def render_with_layout layout, template, helper={}
      part_data = new(template, helper).render_part
      new(layout, helper).render_part { part_data }
    end

    def render_part template, helper={}
      new(template, helper).render_part
    end
  end

  def initialize template, context={}, caller_object=nil
    # we need this to extract caller_object.source_location for DebugPlugin
    @caller_object = caller_object if caller_object

    # template = template.sub(/^\//, '')
    template = './app/views/' + template if template =~ /^\w/

    @helper = if context.class == Hash
      # create helper class if only hash given
      Lux::View::Helper.new(context)
    else
      context
    end

    mutex = Mutex.new

    # if auto_code_reload is on then clear only once per request
    if Lux.config(:auto_code_reload) && !Thread.current[:lux][:template_cache]
      Thread.current[:lux][:template_cache] = true
      mutex.synchronize { @@template_cache = {} }
    end

    if ref = @@template_cache[template]
      @tilt, @template = *ref
      return
    end

    for ext in Tilt.default_mapping.template_map.keys
      next if @template
      test = [template, ext].join('.')
      @template = test if File.exists?(test)
    end

    unless @template
      err  = caller.reject{ |l| l =~ %r{(/lux/|/gems/)} }.map{ |l| el=l.to_s.split(Lux.root.to_s); el[1] || l }.join("\n")
      msg  = %[Lux::View "#{template}.{erb,haml}" not found]
      msg += %[\n\n#{err}] if Lux.config(:dump_errors)

      Lux.error msg
    end

    begin
      mutex.synchronize do
        # @tilt = Tilt.new(@template, ugly:true, escape_html: false)
        @tilt = Tilt.new(@template, escape_html: false)
        @@template_cache[template] = [@tilt, @template]
      end
    rescue
      Lux.error("#{$!.message}\n\nTemplate: #{@template}")
    end
  end

  def render_part
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

end


