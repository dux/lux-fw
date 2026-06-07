# Boot-time behavior toggles, independent of env identity.
#
#   Lux.mode.debug?    # verbose responses + pretty JSON + :info logging
#   Lux.mode.reload?   # per-request code reload
#
# Precedence (lowest -> highest):
#   env default -> ENV var (LUX_DEBUG / LUX_RELOAD) -> runtime setter
#
# ENV values are case-insensitive 'true' / 'false'. Empty/unset = default.
# Any other value raises ArgumentError eagerly in Lux::Environment::Mode.new.
#
# debug? supports a ternary block form for verbose 404/error messages:
#   Lux.mode.debug?                       # => bool
#   Lux.mode.debug?('short') { 'long' }   # => 'short' or 'long'

module Lux
  class Environment::Mode
    FLAGS ||= {
      debug:  { dev: true, prod: false, test: false, env: 'LUX_DEBUG' },
      reload: { dev: true, prod: false, test: false, env: 'LUX_RELOAD' },
    }.freeze

    FLAGS.each_key do |name|
      define_method("#{name}?") do |short = nil, &block|
        val = resolve(name)
        block ? (val ? block.call : short) : val
      end

      define_method("#{name}=") do |v|
        @overrides[name] = !!v
      end
    end

    # Mute framework chatter (per-statement DB log, Lux.shell.info); errors
    # still surface. Forms:
    #   Lux.mode.silent              # => current state (bool)
    #   Lux.mode.silent true         # set persistently (false restores)
    #   Lux.mode.silent { ... }      # mute for the block, then restore previous
    #   Lux.mode.silent(false) { }   # un-mute for the block, then restore
    def silent value = nil
      if block_given?
        prev    = @silent
        @silent = value.nil? ? true : !!value
        begin
          yield
        ensure
          @silent = prev
        end
      elsif value.nil?
        @silent == true
      else
        @silent = !!value
      end
    end

    def initialize env_name
      @env_key   = case env_name.to_s
                   when 'production' then :prod
                   when 'test'       then :test
                   else                   :dev
                   end
      @overrides = {}
      @from_env  = {}
      @silent    = false

      FLAGS.each do |name, spec|
        raw = ENV[spec[:env]]
        next if raw.nil? || raw.empty?

        case raw.downcase
          when 'true'  then @from_env[name] = true
          when 'false' then @from_env[name] = false
          else raise ArgumentError, "#{spec[:env]}=#{raw.inspect} is invalid, expected 'true' or 'false'"
        end
      end
    end

    private

    def resolve name
      return @overrides[name] if @overrides.key?(name)
      return @from_env[name]  if @from_env.key?(name)
      FLAGS[name][@env_key]
    end
  end
end
