# Single source of truth for everything Lux::Api knows about its API surface.
# Generators (postman, openapi, future clients) consume this; they don't
# poke OPTS directly.

module Lux
  class Api
    module Introspect
      extend self

      SCHEMA_VERSION ||= '1'

      # full schema document
      def schema mount_on: nil
        mount_on ||= OPTS.dig(:api, :mount_on) || '/'

        {
          version:  SCHEMA_VERSION,
          mount_on: mount_on,
          apis:     apis(mount_on),
          errors:   errors
        }
      end

      private

      def apis mount_on
        out = {}

        Lux::Api.documented.each do |klass|
          next if klass.to_s == 'Lux::Api::SysApi'

          api_name   = klass.api_path
          class_opts = klass.opts.dig(:opts) || {}

          out[api_name] = {
            path:       api_name,
            desc:       class_opts[:desc],
            detail:     class_opts[:detail],
            icon:       class_opts[:icon],
            collection: methods_for(klass, :collection, mount_on, api_name),
            member:     methods_for(klass, :member,     mount_on, api_name)
          }.compact
        end

        out
      end

      # build the per-method entry; strips private (_*) keys like :_schema
      # methods marked with the built-in `undocumented` annotation are skipped
      # entirely - they remain callable, just hidden from generated schemas.
      def methods_for klass, type, mount_on, api_name
        raw = klass.opts[type] || {}
        return nil if raw.empty?

        base = mount_on.to_s.sub(/\/$/, '')
        out  = {}

        raw.each do |action, mopts|
          next if (mopts || {})[:annotations]&.key?(:undocumented)

          cleaned = (mopts || {}).reject { |k, _| k.to_s.start_with?('_') }

          path_parts = [base, api_name]
          path_parts << ':ref' if type == :member
          path_parts << action.to_s

          out[action] = {
            path:   path_parts.join('/'),
            http:   (['POST'] | Array(cleaned[:allow])),
            desc:   cleaned[:desc],
            detail: cleaned[:detail],
            params: cleaned[:params]
          }.compact
        end

        out.empty? ? nil : out
      end

      def errors
        out = {}

        RESCUE_FROM.each do |key, desc|
          next if key == :all
          next unless key.is_a?(Symbol) && desc.is_a?(String)
          out[key] = desc
        end

        out
      end
    end
  end
end
