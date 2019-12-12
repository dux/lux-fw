# frozen_string_literal: true

require_relative 'view'

class Lux::View::Helper

  attr_reader :_source_object

  # create helper object that cah be used in template render
  def initialize instance, *list
    extend ApplicationHelper

    @_source_object = instance

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
  define_method(:params)  { Lux.current.request.params }
  define_method(:nav)     { Lux.current.nav }
  define_method(:get)     { |name| instance_variable_get('@%s' % name) }

  def no_white_space
    yield.gsub(/>\s+</,'><')
  end

  # - @foo = content do ...
  # = @foo
  # - content :foo do ...
  # = content :foo
  def content name=nil
    if name.is_a?(Array)
      data = yield
      name.push data if data.present?
    else
      block = 'haml_content_%s' % name
      Lux.current.var[block] = yield if block_given?
      Lux.current.var[block]
    end
  end

  # foo = function do |list| ...
  # foo.call @list
  def function &block
    block
  end

  # renders just template but it is called
  # = render :_link, link:link
  # = render 'main/links/_link', link:link
  def render name, locals={}
    if name.is_array?
      return name.map { |b| render(b) }.join("\n")
    elsif name.respond_to?(:db_schema)
      raise 'not supported'
      path = Lux.current.var.root_template_path.split('/')[1]
      table_name = name.class.name.tableize
      locals[table_name.singularize.to_sym] = name
      eval "@_#{table_name.singularize} = name"
      name = "#{path}/#{table_name}/_#{table_name.singularize}"
    elsif !name.to_s.start_with?('./')
      name = name.to_s
      name = Pathname.new(Lux.current.var.root_template_path).join(name).to_s
      # name = [Lux.current.var.root_template_path, name].join('/') if name =~ /^\w/
      name = './app/views' + name if name.starts_with?('/')
    end

    for k, v in locals
      instance_variable_set("@_#{k}", v)
    end

    if block_given?
      name = "#{name}/layout" unless name.index('/')

      Lux::View.render(self, name) { yield }
    else
      Lux::View.render(self, name)
    end
  end

  def cache *args, &block
    ttl = args.last.class == Hash ? args.pop[:ttl] : nil
    key  = 'view:'+Lux.cache.generate_key(args)+block.source_location.join(':')
    Lux.cache.fetch(key, ttl) { yield }
  end

  def error msg=nil
    return Lux::Error unless msg
    %[<pre style="color:red; background:#eee; padding:10px; font-family:'Lucida Console'; line-height:14pt; font-size:10pt;">#{msg}</pre>]
  end

  # helper(:main).method
  def helper *names
    Lux::View::Helper.new(self, *names)
  end

  def once id=nil
    Lux.current.once("template-#{id || caller[0]}") do
      block_given? ? yield : true
    end
  end

end

