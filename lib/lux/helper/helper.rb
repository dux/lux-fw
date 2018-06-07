# frozen_string_literal: true

class Lux::Helper

  # create helper object that cah be used in template render
  def initialize instance, *list
    extend ApplicationHelper

    list.flatten.compact.each do |el|
      el = el.to_s.classify+'Helper'
      extend el.constantize
    end

    local_vars = instance.class == Hash ? instance : instance.instance_variables_hash

    # locals overide globals
    for k, v in local_vars
      instance_variable_set("@#{k.to_s.sub('@','')}", v)
    end

    # helper.instance_exec &block if block
  end

  define_method(:current) { Lux.current }
  define_method(:request) { Lux.current.request }
  define_method(:params)  { Lux.current.params }
  define_method(:nav)     { Lux.current.nav }
  define_method(:get)     { |name| instance_variable_get('@%s' % name) }

  def no_white_space
    yield.gsub(/>\s+</,'><')
  end

  # renders just template but it is called
  # = render :_link, link:link
  # = render 'main/links/_link', link:link
  def render name, locals={}
    if name.is_array?
      return name.map { |b| render(b) }.join("\n")
    elsif name.respond_to?(:db_schema)
      path = Lux.thread[:last_template_path].split('/')[1]
      table_name = name.class.name.tableize
      locals[table_name.singularize.to_sym] = name
      eval "@_#{table_name.singularize} = name"
      name = "#{path}/#{table_name}/_#{table_name.singularize}"
    else
      name = name.to_s
      name = "#{Thread.current[:lux][:last_template_path]}/#{name}" unless name.index('/')
    end

    for k, v in locals
      instance_variable_set("@_#{k}", v)
    end

    if block_given?
      name = "#{name}/layout" unless name.index('/')

      Lux::Template.new(name, self).render_part { yield }
    else
      Lux::Template.new(name, self).render_part
    end
  end

  def cache *args, &block
    ttl = args.last.class == Hash ? args.pop[:ttl] : nil
    key  = 'view:'+Lux.cache.generate_key(args)+block.source_location.join(':')
    Lux.cache.fetch(key, ttl) { yield }
  end

  def error msg
    %[<pre style="color:red; background:#eee; padding:10px; font-family:'Lucida Console'; line-height:14pt; font-size:10pt;">#{msg}</pre>]
  end

  # = render 'main/tag_list', klass:Link
  # = cell Main::PartsController, :tag_filter, klass
  def cell name, action, *args
    klass = name.is_string? ? "#{name}_controller".classify.constantize : name
    klass.cell(action, *args) rescue error("#{klass}.#{action}()\n\n#{$!.message}")
  end

  # tag :div, { 'class'=>'iform' } do
  def tag name=nil, opts={}, data=nil
    return HtmlTagBuilder unless name

    data = yield(opts) if block_given?
    HtmlTagBuilder.tag name, opts, data
  end

  # helper(:main).method
  def helper *names
    Lux::Helper.new(self, *names)
  end

  def once id=nil
    Lux.current.once("template-#{id || caller[0]}") do
      block_given? ? yield : true
    end
  end

end
