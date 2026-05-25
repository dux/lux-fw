require 'yaml'
require 'deep_merge'

module Lux
  module Boot
    module Config
      extend self

      def app_timeout
        # Peek at the existing thread-local Current instead of triggering lazy
        # creation - app_timeout runs before Application#initialize installs the
        # real Current, so calling Lux.current here would build a throwaway /mock
        # Current and autoload Rack::MockRequest (and on Ruby 4 + rack 3.1, drag
        # in cgi/cookie which is no longer a default gem).
        cur = Thread.current[:lux]
        per_request = cur && cur[:app_timeout]
        per_request || Lux.config[:app_timeout] || (Lux.env.dev? ? 3600 : 30)
      rescue
        30
      end

      # './config/secrets.yaml'
      # default is shared + specific envs
      # default:
      #   foo:
      # development:
      #   foo:
      # production:
      #   foo:
      def load
        Lux.init_env if Lux.respond_to?(:init_env)

        source = Pathname.new './config/config.yaml'

        if source.exist?
          data = YAML.safe_load source.read, aliases: true
          bad  = ->(reason) { Lux.shell.die ["Bad config.yaml: #{source}", "reason: #{reason}"] }

          bad.('root must be a Hash') unless data.is_a?(::Hash)

          base_key = if data['default']
            'default'
          elsif data.key?('base')
            'base'
          elsif data.key?('default')
            'default'
          end
          base = data[base_key]
          bad.(':default / :base root not defined') unless base_key
          bad.(":#{base_key} root must be a Hash") unless base.is_a?(::Hash)

          env_name = Lux.env.to_s
          env_data = data[env_name]
          if data.key?(env_name) && !env_data.is_a?(::Hash)
            bad.(":#{env_name} section must be a Hash")
          end

          production_data = data['production']
          if data.key?('production') && !production_data.is_a?(::Hash)
            bad.(':production section must be a Hash')
          end

          base.deep_merge!(env_data || {})
          base['production'] = production_data
          base
        else
          Lux.shell.info '%s not found' % source
          {}
        end
      end

      private

      def env_value_of key, default = :_undef
        value = ENV["LUX_#{key.to_s.upcase}"].to_s
        value = true if ['true', 't', 'yes'].include?(value)
        value = false if ['false', 'f', 'no'].include?(value)

        if default == :_undef
          value
        else
          value.nil? ? default : value
        end
      end
    end
  end
end
