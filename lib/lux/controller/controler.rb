# frozen_string_literal: true

# Controllers can be called in few ways
# Controller.call path
# Controller.action action_name, path
# Controller.new.action_name *args

# filters stack for call
# before, call, before_action, action, after

class Lux::Controller
  # define maser layout
  # string is template, symbol is metod pointer and lambda is lambda
  class_attribute :layout

  # define helper contest, by defult derived from class name
  class_attribute :helper

  # before and after any action filter, ignored in controllers, after is called just before render
  [:before, :before_action, :before_render, :after].each { |filter| class_callback filter }

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
    @executed_filters = {}
    @base_template = self.class.to_s.include?('::') ? self.class.to_s.sub(/Controller$/,'').underscore : self.class.to_s.sub(/Controller$/,'').downcase
  end

  # because we can call action multiple times
  # ensure we execute filters only once
  def filter fiter_name, arg=nil
    return if @executed_filters[fiter_name]
    @executed_filters[fiter_name] = true

    Object.class_callback fiter_name, self, @controller_action
  end

  def cache *args, &block
    Lux.cache.fetch *args, &block
  end

  # action(:show)
  # action(:select', ['users'])
  def action method_name, *args
    raise ArgumentError.new('Controller action called with blank action name argument') if method_name.blank?

    method_name = method_name.to_s.gsub('-', '_').gsub(/[^\w]/, '')

    # dev console log
    Lux.log " #{self.class.to_s}##{method_name}".light_blue

    @controller_action = method_name.to_sym

    # format error unless method found
    report_not_found_error unless respond_to? method_name

    # catch throw gymnastics to allow after filter in controllers, after the body is set
    catch(:done) do
      # catch error but forward unless handled
      begin
        filter :before
        filter :before_action

        send method_name, *args
      rescue => e
        on_error(e)
      end

      render
    end

    filter :after
    throw :done
  end

  def error *args
    args.first.nil? ? Lux::AutoRaiseError : Lux::Error.report(*args)
  end

  def on_error error
    raise error
  end

  def send_file file, opts={}
    Lux::Response::File.send(file, opts)
  end

  # render :index
  # render 'main/root/index'
  # render text: 'ok'
  def render name=nil, opts={}
    if name.class == Hash
      opts.merge! name
    else
      opts[:template] = name
    end

    filter :before_render

    opts = opts.to_opts! :text, :html, :cache, :template, :json, :layout, :render_to_string, :data, :status, :ttl

    response.status opts.status if opts.status

    page =
    if opts.cache
      Lux.cache.fetch(opts.cache, opts.ttl || 3600) { render_resolve(opts) }
    else
      render_resolve(opts)
    end

    if opts.render_to_string
      page
    else
      response.body page
    end
  end

  def render_to_string name=nil, opts={}
    opts[:render_to_string] = true
    render name, opts
  end

  private
    # delegated to current
    define_method(:current)  { Lux.current }
    define_method(:request)  { current.request }
    define_method(:response) { current.response }
    define_method(:params)   { current.request.params }
    define_method(:nav)      { current.nav }
    define_method(:session)  { current.session }
    define_method(:get?)     { request.request_method == 'GET' }
    define_method(:post?)    { request.request_method == 'POST' }
    define_method(:redirect) { |where, flash={}| current.redirect where, flash }
    define_method(:etag)     { |*args| current.response.etag *args }
    define_method(:layout)   { |arg| current.var[:controller_layout] = arg }

    # called be render
    def render_resolve opts
      # resolve basic types
      types = [ [:text, 'text/plain'], [:html, 'text/html'], [:json, 'application/json'] ]
      types.select{ |it| opts[it.first] }.each do |name, content_type|
        response.content_type = content_type
        return opts[name]
      end

      # resolve page data, without template
      page_part = opts.data || render_body(opts)

      # resolve data with layout
      full_page = render_layout opts, page_part

      full_page
    end

    def render_body opts
      if template = opts.template
        template = template.to_s
        template = "#{@base_template}/#{template}" unless template.starts_with?('/')
      else
        template = "#{@base_template}/#{@controller_action}"
      end

      Lux::Template.render_part(template, helper)
    end

    def render_layout opts, page_data
      layout = opts.layout
      layout = nil   if layout.class == TrueClass
      layout = false if current.var[:controller_layout].class == FalseClass

      if layout.class == FalseClass
        page_data
      else
        layout_define = layout || self.class.layout

        layout = case layout_define
          when String
            'layouts/%s' % layout_define
          when Symbol
            send(layout_define)
          when Proc
            layout_define.call
          else
            'layouts/%s' % @base_template.split('/')[0]
        end

        Lux::Template.new(layout, helper).render_part { page_data }
      end
    end

    def halt status, desc=nil
      response.status = status
      response.body   = desc || "Hatlt code #{status}"

      throw :done
    end

    def namespace
      @base_template.split('/')[0].to_sym
    end

    def helper ns=nil
      Lux::Helper.new self, :html, self.class.helper, ns
    end

    def report_not_found_error
      raise Lux::Error.not_found unless Lux.config(:dump_errors)

      err = [%[Method "#{@controller_action}" not found found in #{self.class.to_s}]]
      err.push "You have defined \n- %s" % (methods - Lux::Controller.instance_methods).join("\n- ")

      return Lux.error err.join("\n\n")
    end
end
