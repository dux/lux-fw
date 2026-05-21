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
          schemas:  schemas,
          errors:   errors
        }
      end

      private

      # collect model schemas for documented APIs that opt in by defining
      # self.api_schema (returning a Lux::Schema). Keyed by api_schema_ref so
      # per-method entries can $ref into here without duplicating field lists.
      def schemas
        out = {}

        Lux::Api.documented.each do |klass|
          next if klass.to_s == 'Lux::Api::SysApi'
          next unless klass.respond_to?(:api_schema) && klass.respond_to?(:api_schema_ref)

          name = klass.api_schema_ref.to_s
          next if name.empty? || out.key?(name)

          rules = klass.api_schema.rules rescue nil
          out[name] = rules if rules
        end

        out.empty? ? nil : out
      end

      def apis mount_on
        out         = {}
        schemas_map = schemas || {}

        Lux::Api.documented.each do |klass|
          next if klass.to_s == 'Lux::Api::SysApi'

          api_name   = klass.api_path
          class_opts = klass.opts.dig(:opts) || {}

          out[api_name] = {
            path:       api_name,
            desc:       class_opts[:desc],
            detail:     class_opts[:detail],
            icon:       class_opts[:icon],
            schema_ref: class_schema_ref(klass, schemas_map),
            collection: methods_for(klass, :collection, mount_on, api_name),
            member:     methods_for(klass, :member,     mount_on, api_name)
          }.compact
        end

        out
      end

      # class-level schema link: the model name the class declares via
      # api_schema_ref. Returned only when api_schema actually yields a
      # truthy Lux::Schema and that name is present in the assembled
      # schemas map (avoids dangling refs on the consumer side).
      def class_schema_ref klass, schemas_map
        return nil unless klass.respond_to?(:api_schema) && klass.respond_to?(:api_schema_ref)
        return nil unless (klass.api_schema rescue nil)

        name = klass.api_schema_ref.to_s
        name.empty? || !schemas_map.key?(name) ? nil : name
      end

      # build the per-method entry; strips private (_*) keys like :_schema
      # methods marked with the built-in `undocumented` annotation are skipped
      # entirely - they remain callable, just hidden from generated schemas.
      def methods_for klass, type, mount_on, api_name
        raw = klass.opts[type] || {}
        return nil if raw.empty?

        base = mount_on.to_s.sub(/\/$/, '')
        out  = {}

        # implicit schema_ref for classes that expose a top-level model schema
        # (any class with api_schema_ref). Falls through to explicit per-action
        # schema_ref set via the DSL.
        implicit_ref = klass.respond_to?(:api_schema_ref) ? klass.api_schema_ref.to_s : nil

        raw.each do |action, mopts|
          next if (mopts || {})[:annotations]&.key?(:undocumented)

          cleaned = (mopts || {}).reject { |k, _| k.to_s.start_with?('_') }

          path_parts = [base, api_name]
          path_parts << ':ref' if type == :member
          path_parts << action.to_s

          schema_ref = cleaned[:schema_ref]
          if !schema_ref && implicit_ref && %i(create update).include?(action.to_sym)
            schema_ref = implicit_ref
          end

          out[action] = {
            path:       path_parts.join('/'),
            http:       (['POST'] | Array(cleaned[:allow])),
            desc:       cleaned[:desc],
            detail:     cleaned[:detail],
            params:     cleaned[:params],
            schema_ref: schema_ref
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
