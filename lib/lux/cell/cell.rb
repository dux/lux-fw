# frozen_string_literal: true

# Cells can be called in few ways
# Cell.call path
# Cell.action action_name, path
# Cell.new.action_name *args

class Lux::Cell
  # define maser layout
  # string is template, symbol is metod pointer and lambda is lambda
  ClassAttributes.define self, :layout

  # define helper contest, by defult derived from class name
  ClassAttributes.define self, :helper

  # before and after any action filter, ignored in cells, after is called just before render
  ClassCallbacks.define self, :before, :before_action, :before_render, :after

  class << self
    # class call method, should not be overridden
    def call
      Lux.current.files_in_use.push "app/cells/#{self.to_s.underscore}.rb"

      cell = new
      cell.filter :before
      cell.call

      return if Lux.current.response.body

      # we want to exec filter after the call
      cell.filter :before_action
    end

    # create mock function, to enable template rendering
    # mock :index, :login
    def mock *args
      args.each do |el|
        define_method el do
          true
        end
      end
    end

    # simple shortcut allows direct call to action, bypasing call
    def action *args
      new.action(*args)
    end
  end

  ### INSTANCE METHODS

  attr_reader :cell_action

  def initialize
    # before and after should be exected only once
    @executed_filters = {}
    @base_template = self.class.to_s.include?('::') ? self.class.to_s.sub(/Cell$/,'').underscore : self.class.to_s.sub(/Cell$/,'').downcase
  end

  # default call method, should be overitten
  # expects arguments as flat array
  # usually called by router
  def call
    action(:index)
  end

  # execute before and after filters, only once
  def filter fiter_name
    # move this to ClassCallbacks class?
    return if @executed_filters[fiter_name]
    @executed_filters[fiter_name] = true

    ClassCallbacks.execute(self, fiter_name)
  end

  def cache *args, &block
    Lux.cache.fetch *args, &block
  end

  # action(:show, 2)
  # action(:select', ['users'])
  def action method_name, *args
    raise ArgumentError.new('Cell action called with blank action name argument') if method_name.blank?

    # maybe before filter rendered page
    return if response.body

    method_name = method_name.to_s.gsub('-', '_').gsub(/[^\w]/, '')

    Lux.log " #{self.class.to_s}(:#{method_name})".light_blue
    Lux.current.files_in_use.push "app/cells/#{self.class.to_s.underscore}.rb"

    @cell_action = method_name

    unless respond_to? method_name
      raise NotFoundError.new('Method %s not found' % method_name) unless Lux.config(:show_server_errors)

      list = methods - Lux::Cell.instance_methods
      err = [%[No instance method "#{method_name}" found in class "#{self.class.to_s}"]]
      err.push ["Expected so see def show(id) ..."] if method_name == 'show!'
      err.push %[You have defined \n- #{(list).join("\n- ")}]
      return Lux.error(err.join("\n\n"))
    end

    filter :before
    return if response.body

    filter :before_action
    return if response.body

    send method_name, *args
    filter :after

    return if response.body
    render
  end

  # render :show, id
  # render :index
  # render 'main/root/index'
  # render :profile,  name:'Dux'
  # render text: 'ok'
  def render name=nil, opts={}
    return if response.body
    return if @no_render

    filter :before_render

    if name.is_hash?
      opts = name
      name = nil
    end

    opts[:template] = name if name

    render_resolve_body opts

    Lux.cache.set(opts[:cache], response.body) if opts[:cache]
  end

  # renders template to string
  def render_part
    Lux::Template.render_part("#{@base_template}/#{@cell_action}", instance_variables_hash, namespace)
  end

  def render_to_string name=nil, opts={}
    opts[:set_page_body] = false
    render name, opts
  end

  def send_file

  end

  private
    # called be render
    def render_resolve_body opts
      # resolve basic types
      if opts[:text]
        response.content_type = 'text/plain'
        return response.body(opts[:text])
      elsif opts[:html]
        response.content_type = 'text/html'
        return response.body(opts[:html])
      elsif opts[:json]
        response.content_type = 'application/json'
        return response.body(opts[:json])
      end

      # resolve page data, without template
      page_data = opts[:data] || Proc.new do
        if template = opts.delete(:template)
          template = template.to_s
          template = "#{@base_template}/#{template}" unless template.starts_with?('/')
        else
          template = "#{@base_template}/#{@cell_action}"
        end

        Lux::Template.render_part(template, helper)
      end.call

      # resolve data with layout
      layout = opts.delete(:layout)
      layout = nil if layout.class == TrueClass
      layout = false if @layout.class == FalseClass

      if layout.class != FalseClass
        layout_define = layout || self.class.layout

        layout = case layout_define
          when String
            layout = layout_define
          when Symbol
            send(layout_define)
          when Proc
            layout_define.call
          else
            "#{@base_template.split('/')[0]}/layout"
        end

        page_data = Lux::Template.new(layout, helper).render_part do
          page_data
        end
      end

      response.body(page_data) unless opts[:set_page_body].is_false?

      page_data
    end

    def etag *args
      response.etag *args
    end

    def halt status, desc=nil
      response.status = status
      response.body   = desc || "Hatlt code #{status}"

      throw :done
    end

    # helper functions
    def current
      Lux.current
    end

    def request
      Lux.current.request
    end

    def response
      Lux.current.response
    end

    def params
      Lux.current.params
    end

    def nav
      Lux.current.nav
    end

    def redirect where, flash={}
      Lux.current.redirect where, flash
    end

    def session
      Lux.current.session
    end

    def namespace
      @base_template.split('/')[0].to_sym
    end

    def helper ns=nil
      Lux::Helper.new self, :html, self.class.helper, ns
    end
end

ApplicationCell = Class.new Lux::Cell

