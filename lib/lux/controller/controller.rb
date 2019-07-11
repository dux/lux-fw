# frozen_string_literal: true

# filters stack for call
# before, before_action, :action, after

class Lux::Controller
  # define maser layout
  # string is template, symbol is metod pointer and lambda is lambda
  class_attribute :layout

  # define helper contest, by defult derived from class name
  class_attribute :helper

  # custom template root instead calcualted one
  class_attribute :template_root

  # before and after any action filter, ignored in controllers, after is called just before render
  [:before, :before_action, :after_action, :before_render, :after].each { |filter| class_callback filter }

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
  end

  ### INSTANCE METHODS

  attr_reader :controller_action

  def initialize
    # before and after should be exected only once
    @lux = FreeStruct.new :executed_filters, :template, :action, :layout
    @lux.executed_filters = {}
    @lux.template = self.class.to_s.include?('::') ? self.class.to_s.sub(/Controller$/,'').underscore : self.class.to_s.sub(/Controller$/,'').downcase
  end

  # action(:show)
  # action(:select', ['users'])
  def action method_name, *args
    raise ArgumentError.new('Controller action called with blank action name argument') if method_name.blank?

    method_name = method_name.to_s.gsub('-', '_').gsub(/[^\w]/, '')

    # dev console log
    Lux.log " #{self.class.to_s}##{method_name}".light_blue

    @lux.action = method_name.to_sym

    catch :done do
      begin
        filter :before
        filter :before_action
        send method_name, *args
        render
      rescue StandardError => error
        @had_errros = true
        Lux.current.response.status error.code if error.respond_to?(:code)
        Lux::Error.log error
        on_error error
      end
    end

    filter :after unless @had_errros

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
    return if response.body?

    filter :after_action
    filter :before_render

    if nav.format
      current.once(:format_handled) do
        current.var.format_handled = true
        error.not_found('%s document Not Found' % nav.format.to_s.upcase)
      end
    end

    if name.class == Hash
      opts.merge! name
    else
      opts[:template] = name
    end

    opts = opts.to_opts :text, :html, :json, :javascript, :cache, :template, :layout, :render_to_string, :data, :status, :ttl, :content_type

    response.status opts.status               if opts.status
    response.content_type = opts.content_type if opts.content_type

    page =
    if opts.cache
      Lux.cache.fetch(opts.cache, opts.ttl || 3600) { render_resolve(opts) }
    else
      render_resolve(opts)
    end

    if opts.render_to_string
      page
    else
      response.body { page }
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

  def call
    nav.root ||= @id ? :show : :index
    action nav.root
  end

  # delegated to current
  define_method(:current)     { Lux.current }
  define_method(:request)     { current.request }
  define_method(:response)    { current.response }
  define_method(:params)      { current.request.params }
  define_method(:nav)         { current.nav }
  define_method(:session)     { current.session }
  define_method(:get?)        { request.request_method == 'GET' }
  define_method(:post?)       { request.request_method == 'POST' }
  define_method(:redirect_to) { |where, flash={}| current.response.redirect_to where, flash }
  define_method(:etag)        { |*args| current.response.etag *args }
  define_method(:layout)      { |arg| @lux.layout = arg }

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
    page_part = opts.data || render_body(opts)

    # resolve data with layout
    layout = opts.layout
    layout = nil   if layout.class == TrueClass
    layout = false if @lux.layout.class == FalseClass

    if layout.class == FalseClass
      page_part
    else
      layout_define = layout || self.class.layout

      layout = case layout_define
        when String
          'layouts/%s' % layout_define
        when Symbol
          'layouts/%s' % layout_define
        when Proc
          layout_define.call
        else
          'layouts/%s' % @lux.template.split('/')[0]
      end

      Lux::View.new(layout, helper).render_part { page_part }
    end
  end

  def render_body opts
    if opts.template
      template = opts.template.to_s
      template = "/#{@lux.template}/#{template}" if template =~ /^\w/
    else
      template = "/#{@lux.template}/#{@lux.action}"
    end

    if self.class.template_root && !template.starts_with?('./')
      template = self.class.template_root + template
    end

    Lux.current.var.root_template_path = template.sub(%r{/[\w]+$}, '')

    Lux::View.render_part(template, helper)
  end

  def halt status, desc=nil
    response.status = status
    response.body   = desc || "Hatlt code #{status}"
  end

  def namespace
    @lux.template.split('/')[0].to_sym
  end

  def helper ns=nil
    Lux::View::Helper.new self, :html, self.class.helper, ns
  end

  def report_not_found_error error
    raise Lux::Error.not_found unless Lux.config(:dump_errors)

    ap Lux::Error.split_backtrace error

    err =   [%[Method "#{@lux.action}" not found found in #{self.class.to_s}]]
    err.push %[You have defined \n- %s] % (methods - Lux::Controller.instance_methods).join("\n- ")

    return Lux.error err.join("\n\n")
  end

  def error *args
    args.first.nil? ? Lux::Error::AutoRaise : Lux::Error.report(*args)
  end

  def respond_to ext=nil
    current.once(:format_handled) do
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
  end

  # because we can call action multiple times
  # ensure we execute filters only once
  def filter fiter_name, arg=nil
    return if @lux.executed_filters[fiter_name]
    @lux.executed_filters[fiter_name] = true

    Object.class_callback fiter_name, self, @lux.action
  end

  def on_error error
    render html: Lux::Error.render(error)
  end

  def cache *args, &block
    Lux.cache.fetch *args, &block
  end

end
