require 'timeout'

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

  # Shell/process execution + status output. See lib/lux/shell/.
  def shell
    Lux::Shell
  end

  # Namespaced translation lookup. See lib/lux/locale/.
  def locale
    Lux::Locale
  end

  def app_caller
    app_line   = caller.find { |line| !line.include?('/lux-') && !line.include?('/.') && !line.include?('(eval)') }
    app_line ? app_line.split(':in ').first.sub(Lux.root.to_s, '.') : nil
  end

  # Spawn a background thread with a clean Lux.current.
  #
  # The parent request context is NOT silently installed inside the thread.
  # Instead it is passed to the block as an explicit argument (a shallow dup
  # of Lux.current), so the caller decides what to read from it.
  #
  #   Lux.defer do |ctx|
  #     # ctx is Lux.current.dup from the parent thread
  #     # Lux.current inside this thread is a fresh instance
  #   end
  #
  #   Lux.defer(context: user) { |u| Mailer.welcome(u).deliver }
  #
  # Zero-arity blocks stay compatible: Lux.defer { ... }.
  def defer context: nil, timeout: nil, &block
    raise ArgumentError, 'Block not given' unless block

    context = Lux.current.dup if context.nil?
    timeout ||= Lux.config.delay_timeout
    raise 'Timeout is not numeric (seconds)' unless timeout.is_a?(Numeric)

    Thread.new do
      # new thread starts with Thread.current[:lux] == nil; do not install
      # parent context. Any Lux.current access here lazily builds a clean one.
      begin
        ::Timeout::timeout(timeout) do
          block.arity == 0 ? block.call : block.call(context)
        end
      rescue => e
        Lux.logger.error ['Lux.defer error: %s' % e.message, e.backtrace].join($/)
      ensure
        Thread.current[:lux] = nil
      end
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
    klass = name.to_s.classify if name && !name.is_hash?

    if block_given?
      Lux::Schema.new(klass, opts, &block)
    else
      if name.is_hash?
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

# Shell + status output. Loaded early so Lux.shell.info works during boot.
require_relative 'shell/error'
require_relative 'shell/result'
require_relative 'shell/shell'

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
