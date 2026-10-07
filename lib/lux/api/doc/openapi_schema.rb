# OpenAPI 3.0 generator. Consumes Lux::Api::Introspect.schema and emits a
# spec good enough for swagger-ui / redoc and client generators. Reached via
# Lux::Api::SysApi#openapi -> /<mount_on>/sys/openapi.
#
# Field shapes come from Lux::Type#json_schema, so a param declared `:email`
# documents as `format: email` and `max: 30` as `maxLength: 30`.

module Lux
  class Api
    class OpenapiSchema
      # Built from class-level declarations only, so it is cached unless code
      # can reload; info/servers are added per request.
      CACHE ||= {}

      ENVELOPE ||= {
        'type'       => 'object',
        'properties' => {
          'success' => { 'type' => 'boolean' },
          'status'  => { 'type' => 'integer' },
          'message' => { 'type' => 'string' },
          'meta'    => { 'type' => 'object' },
          'data'    => {},
          'error'   => {
            'type'       => 'object',
            'properties' => {
              'code'     => { 'type' => 'string' },
              'messages' => { 'type' => 'array', 'items' => { 'type' => 'string' } },
              'details'  => { 'type' => 'object' }
            }
          }
        }
      }

      def initialize api, mount_on: nil
        @api      = api
        @mount_on = mount_on
      end

      def openapi
        body = Lux.reload? ? build : (CACHE[@mount_on] ||= build)

        {
          'openapi' => '3.0.3',
          'info'    => {
            'title'   => "#{request.host} API",
            'version' => body[:version]
          },
          'servers'    => [{ 'url' => "#{request.scheme}://#{request.host_with_port}" }],
          'paths'      => body[:paths],
          'components' => body[:components]
        }
      end

      private

      def build
        doc = Lux::Api::Introspect.schema(mount_on: @mount_on)

        schemas = { 'Response' => ENVELOPE }
        (doc[:schemas] || {}).each { |name, rules| schemas[name.to_s] = object_schema(rules) }

        {
          version:    doc[:version].to_s,
          paths:      paths(doc),
          components: {
            'schemas'         => schemas,
            'securitySchemes' => { 'bearer' => { 'type' => 'http', 'scheme' => 'bearer' } }
          }
        }
      end

      def paths doc
        out = {}

        doc[:apis].each do |api_name, api_doc|
          [:collection, :member].each do |type|
            methods = api_doc[type] or next

            methods.each do |action, mdata|
              # OpenAPI uses {ref} not :ref
              openapi_path = mdata[:path].gsub(/\/:([a-z_]+)/i, '/{\1}')
              verbs        = Array(mdata[:http])

              out[openapi_path] = verbs.to_h do |verb|
                id = [api_name, type, action]
                id << verb.to_s.downcase if verbs.length > 1
                [verb.to_s.downcase, operation(id.join('.'), api_name, api_doc, mdata, verb, doc[:errors])]
              end
            end
          end
        end

        out
      end

      def operation id, api_name, api_doc, mdata, verb, errors
        op = {
          'tags'        => [api_name.to_s],
          'operationId' => id,
          'summary'     => mdata[:desc] || id.split('.')[2],
          'responses'   => responses(api_doc, mdata, errors)
        }
        op['description'] = mdata[:detail] if mdata[:detail]
        op['security']    = [{ 'bearer' => [] }] if api_doc[:auth] && !mdata[:unsafe]

        parameters = mdata[:path].scan(/:([a-z_]+)/i).flatten.map do |name|
          { 'name' => name, 'in' => 'path', 'required' => true, 'schema' => { 'type' => 'string' } }
        end

        params = mdata[:params] || {}

        if verb.to_s.upcase == 'GET'
          params.each do |name, rule|
            parameters << {
              'name'     => name.to_s,
              'in'       => 'query',
              'required' => !!rule[:required],
              'schema'   => field_schema(rule)
            }
          end
        elsif params.any? || mdata[:schema_ref]
          schema = params.any? ? object_schema(params) : schema_ref(mdata[:schema_ref])
          op['requestBody'] = { 'content' => { 'application/json' => { 'schema' => schema } } }
        end

        op['parameters'] = parameters if parameters.any?
        op
      end

      # Lux APIs answer 200 or 400 with the same envelope; error.code tells
      # failures apart, so the 400 lists the codes the app declared.
      def responses api_doc, mdata, errors
        json  = { 'application/json' => { 'schema' => schema_ref('Response') } }
        codes = (errors || {}).map { |code, desc| "* `#{code}` - #{desc}" }

        out = {
          '200' => { 'description' => 'OK', 'content' => json },
          '400' => { 'description' => ['Error, see `error.code`', *codes].join("\n"), 'content' => json }
        }
        out['401'] = { 'description' => 'Bearer token missing or rejected', 'content' => json } if api_doc[:auth] && !mdata[:unsafe]
        out
      end

      def object_schema rules
        required = rules.select { |_, rule| rule[:required] }.keys.map(&:to_s)

        {
          'type'       => 'object',
          'properties' => rules.to_h { |name, rule| [name.to_s, field_schema(rule)] },
          'required'   => (required if required.any?)
        }.compact
      end

      # One field. Model params arrive from Introspect either as a named
      # schema (schema:) or inline (fields:); stored schemas still carry the
      # Lux::Schema under :model.
      def field_schema rule
        out =
          if rule[:schema]
            schema_ref(rule[:schema])
          elsif rule[:fields]
            object_schema(rule[:fields])
          elsif rule[:model].is_a?(Lux::Schema)
            rule[:model].klass ? schema_ref(rule[:model].klass.to_s.underscore) : object_schema(rule[:model].rules)
          else
            Lux::Type.load(rule[:type]).new(nil, rule.slice(:min, :max)).json_schema
          end

        # min/max check each element; the count has its own limits (Lux::Schema)
        if rule[:array]
          out = { 'type' => 'array', 'items' => out, 'minItems' => rule[:min_count], 'maxItems' => rule[:max_count] || 100 }
        end

        extra = {
          'enum'        => rule[:values],
          'default'     => rule[:default],
          'description' => rule[:description]
        }.compact
        return out.compact if extra.empty?

        # OpenAPI 3.0 ignores keywords beside a $ref
        out.key?('$ref') ? { 'allOf' => [out] }.merge(extra) : out.merge(extra).compact
      end

      def schema_ref name
        { '$ref' => "#/components/schemas/#{name}" }
      end

      def request
        @api[:api_host].request
      end
    end
  end
end
