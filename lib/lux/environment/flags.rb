# Boot-time behavior toggles, independent of env identity.
#
#   Lux.debug?    # verbose responses + pretty JSON + :info logging
#   Lux.reload?   # per-request code reload
#   Lux.silent    # mute framework chatter
#
# Precedence (lowest -> highest):
#   env default -> ENV var (LUX_DEBUG / LUX_RELOAD) -> runtime setter
#
# ENV values are case-insensitive 'true' / 'false'. Empty/unset = default.
# Any other value raises ArgumentError eagerly in Lux::Environment::Flags.new.
#
# debug? supports a ternary block form for verbose 404/error messages:
#   Lux.debug?                       # => bool
#   Lux.debug?('short') { 'long' }   # => 'short' or 'long'
#
# Call sites use the flat Lux.* delegators in environment/lux_adapter.rb;
# Lux.flags is the object itself, for the boot banner and specs.

module Lux
  class Environment::Flags
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
    # still surface. Deliberately not a FLAGS entry - block-scoped, no env
    # default, no ENV var. Forms:
    #   Lux.silent              # => current state (bool)
    #   Lux.silent true         # set persistently (false restores)
    #   Lux.silent { ... }      # mute for the block, then restore previous
    #   Lux.silent(false) { }   # un-mute for the block, then restore
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
      @silent    = false
      @from_env  = parse_env
    end

    # ENV can change after construction: Lux.dotenv loads .env files at boot,
    # by which point the logger may already have touched the flags. Runtime
    # overrides and silent are left alone, so precedence still holds.
    def reload_env!
      @from_env = parse_env
    end

    private

    def parse_env
      FLAGS.each_with_object({}) do |(name, spec), out|
        raw = ENV[spec[:env]]
        next if raw.nil? || raw.empty?

        case raw.downcase
          when 'true'  then out[name] = true
          when 'false' then out[name] = false
          else raise ArgumentError, "#{spec[:env]}=#{raw.inspect} is invalid, expected 'true' or 'false'"
        end
      end
    end

    def resolve name
      return @overrides[name] if @overrides.key?(name)
      return @from_env[name]  if @from_env.key?(name)
      FLAGS[name][@env_key]
    end
  end
end
