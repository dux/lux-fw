# OpenAPI 3.0 generator. Consumes Lux::Api::Introspect.schema and emits a
# spec good enough for swagger-ui / redoc to render. Reached via
# Lux::Api::SysApi#openapi -> /<mount_on>/sys/openapi.

module Lux
  class Api
    class OpenapiSchema
      TYPE_MAP ||= {
        'integer' => { 'type' => 'integer' },
        'string'  => { 'type' => 'string' },
        'boolean' => { 'type' => 'boolean' },
        'float'   => { 'type' => 'number', 'format' => 'float' },
        'array'   => { 'type' => 'array', 'items' => { 'type' => 'string' } },
        'hash'    => { 'type' => 'object' }
      }

      def initialize api, mount_on: nil
        @api      = api
        @mount_on = mount_on
      end

      def openapi
        doc = Lux::Api::Introspect.schema(mount_on: @mount_on)

        {
          'openapi' => '3.0.3',
          'info'    => {
            'title'   => "#{request.host} API",
            'version' => doc[:version].to_s
          },
          'servers' => [{ 'url' => "#{request.scheme}://#{request.host_with_port}" }],
          'paths'   => paths(doc)
        }
      end

      private

      def paths doc
        out = {}

        doc[:apis].each do |api_name, api_doc|
          [:collection, :member].each do |type|
            methods = api_doc[type] or next

            methods.each do |action, mdata|
              # OpenAPI uses {ref} not :ref
              openapi_path = mdata[:path].gsub(/\/:([a-z_]+)/i, '/{\1}')

              ops = {}
              Array(mdata[:http]).each do |verb|
                ops[verb.to_s.downcase] = operation(api_name, action, type, mdata)
              end

              out[openapi_path] = ops
            end
          end
        end

        out
      end

      def operation api_name, action, type, mdata
        op = {
          'tags'        => [api_name],
          'operationId' => "#{api_name}.#{type}.#{action}",
          'summary'     => mdata[:desc] || action.to_s,
          'responses'   => {
            '200' => { 'description' => 'OK' }
          }
        }
        op['description'] = mdata[:detail] if mdata[:detail]

        params = mdata[:params] || {}
        required = params.select { |_, v| v[:required] }.keys.map(&:to_s)

        if params.any?
          props = {}
          params.each do |name, spec|
            field = TYPE_MAP[spec[:type].to_s] || { 'type' => 'string' }
            field = field.dup
            field['default']     = spec[:default] unless spec[:default].nil?
            field['description'] = spec[:desc]    if spec[:desc]
            field['enum']        = spec[:values]  if spec[:values]
            props[name.to_s] = field
          end

          op['requestBody'] = {
            'content' => {
              'application/json' => {
                'schema' => {
                  'type'       => 'object',
                  'properties' => props,
                  'required'   => required
                }.compact
              }
            }
          }
        end

        op
      end

      def request
        @api[:api_host].request
      end
    end
  end
end
