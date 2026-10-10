require 'yaml'
# core only - the full gem patches Hash#deep_merge with semantics that differ from ActiveSupport's
require 'deep_merge/core'

module Lux
  module Boot
    module Config
      extend self

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

          base_key = if data.key?('default')
            'default'
          elsif data.key?('base')
            'base'
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

          DeepMerge.deep_merge!(env_data || {}, base, preserve_unmergeables: false)
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
