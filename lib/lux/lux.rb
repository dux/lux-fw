module ::Lux
  extend self

  # Sentinel for "no argument given". Use when nil/false are valid explicit values.
  # Compare with .equal?(Lux::UNSET), never ==.
  UNSET ||= Object.new.tap do |obj|
    def obj.inspect = 'Lux::UNSET'
    def obj.to_s    = inspect
  end.freeze

  def root
    @lux_app_root ||= Pathname.new(ENV.fetch('APP_ROOT') { Dir.pwd }).freeze
  end

  def fw_root
    @lux_fw_root ||= Pathname.new(__dir__).join('../..').expand_path.freeze
  end

  VERSION ||= fw_root.join('.version').read.chomp

  # main rack response
  def call env = nil
    Timeout::timeout Lux::Config.app_timeout do
      app  = Lux::Application.new env
      app.render_base || raise('No RACK response given')
    end
  rescue => err
    Lux.logger.error Lux::Error.format(err, message: true)

    if Lux.mode.log?
      raise
    else
      [500, {}, ['Server error: %s' % err.message]]
    end
  end

  # simple block to calc block execution speed
  def speed
    render_start = Time.monotonic
    yield
    num = (Time.monotonic - render_start) * 1000
    if num > 1000
      '%s sec' % (num/1000).round(2)
    else
      '%s ms' % num.round(1)
    end
  end

  # Status/notice output. Routed to STDERR so that CLI tasks (lux render, etc.)
  # can produce clean machine-parseable output on STDOUT.
  def info text
    if text.class == Array
      text.each {|line| self.info line }
    else
      STDERR.puts '* %s' % text.to_s.colorize(:magenta)
    end
  end

  def run command, get_result = false
    Lux.logger.info command
    get_result ? `#{command}` : system(command)
  end

  def die text
    Lux.logger.fatal "Lux FATAL: #{text}"
    exit
  end

  def app_caller
    app_line   = caller.find { |line| !line.include?('/lux-') && !line.include?('/.') && !line.include?('(eval)') }
    app_line ? app_line.split(':in ').first.sub(Lux.root.to_s, '.') : nil
  end

  def delay time_to_live = nil
    Thread.new do
      time_to_live ||= Lux.config.delay_timeout

      unless time_to_live.is_a?(Numeric)
        raise 'Time to live is not integer (seconds)'
      end

      Timeout::timeout time_to_live do
        yield
      end
    rescue => e
      Lux.logger.error e
    end
  end

  # check and coerce value
  # Lux.type(:label) -> Lux::Type::LabelType
  # Lux.type(:label, 'Foo bar') -> "foo-bar"
  def type klass_name, value = UNSET, opts = {}, &block
    klass = Lux::Type.load(klass_name)

    if value.equal?(UNSET)
      klass
    else
      begin
        check = klass.new value, opts
        check.get
      rescue TypeError => error
        if block
          block.call error
          false
        else
          raise error
        end
      end
    end
  end

  # define or look up a schema
  #   Lux.schema(:blog) { ... }            - define
  #   Lux.schema(:blog, type: :model) { }  - define with opts
  #   Lux.schema(:blog)                    - lookup, raises if missing
  #   Lux.schema(type: :model)             - find all schemas matching opt
  def schema name = nil, opts = nil, &block
    klass = name.to_s.classify if name && !name.is_a?(Hash)

    if block_given?
      Lux::Schema.new(klass, opts, &block)
    else
      if name.is_a?(Hash)
        out = []
        Lux::Schema::SCHEMA_STORE.values.each do |schema|
          if schema.opts[name.keys.first] == name.values.first
            out.push schema.klass
          end
        end
        out
      else
        Lux::Schema::SCHEMA_STORE[klass] || raise('Schema "%s" not found' % klass)
      end
    end
  end

  # same as schema but returns nil if not found
  def schema? name
    klass = name.to_s.classify if name
    Lux::Schema::SCHEMA_STORE[klass] if klass
  end

  # array of database fields, Sequel-compatible
  def db_schema name
    Lux.schema(name).db_schema
  end

  # shortcut for Lux::JsonExporter.define and .export
  #   Lux.json_exporter(Page) { prop :name }   - register exporter for Page
  #   Lux.json_exporter(Page.first)            - render Page.first
  def json_exporter name_or_object, opts = {}, &block
    if block
      Lux::JsonExporter.define name_or_object, &block
    else
      Lux::JsonExporter.new(name_or_object, opts).render
    end
  end
end

###

def Lux &block
  raise 'Lux error: Rack not found' unless self.class == Rack::Builder
  $rack_handler = self
  Lux::Application.class_eval(&block) if block
  run Lux
  puts Lux::Config.start_info
end

###

require_relative 'environment/environment'
require_relative 'environment/mode'
require_relative 'environment/runtime'
require_relative 'environment/lux_adapter'

require_relative 'logger/lux_adapter'

require_relative 'config/config'
require_relative 'config/lux_adapter'

if $lux_start_time
  # for better start stats add $lux_start_time ||= Time.now to begginging of Gemfile
  $lux_start_time = [$lux_start_time, Time.now]
else
  $lux_start_time = Time.now
end
