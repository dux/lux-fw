# frozen_string_literal: true
require 'thread'

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

  def initialize template, context={}
    template           = template.sub(/^[^\w]+/, '')
    @original_template = template

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

    for dir in ['./app/views']
      for ext in Tilt.default_mapping.template_map.keys
        next if @template
        test = "#{dir}/#{template}.#{ext}"
        @template = test if File.exists?(test)
      end
    end

    unless @template
      err  = caller.reject{ |l| l =~ %r{(/lux/|/gems/)} }.map{ |l| el=l.to_s.split(Lux.root.to_s); el[1] || l }.join("\n")
      msg  = %[Lux::View "#{template}.{erb,haml}" not found]
      msg += %[\n\n#{err}] if Lux.config(:dump_errors)

      raise Lux.error msg
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

    Thread.current[:lux][:last_template_path] = @template.sub('/app/views','').sub(/\/[^\/]+$/,'').sub(/^\./,'')
    Lux.current.files_in_use @template

    data = nil

    speed = Lux.speed do
      begin
        data = @tilt.render(@helper) do
          yield if block_given?
        end
      rescue => e
        data = Lux::Error.inline %[Lux::View #{@template} render error], e
      end
    end

    Lux.log " app/views/#{@template.split('app/views/').last}, #{speed}"

    data
  end

end


