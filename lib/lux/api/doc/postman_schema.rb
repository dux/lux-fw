# Postman collection v2.1 generator. Consumes Lux::Api::Introspect.schema
# rather than poking OPTS directly. Extension hooks (formdata_<type>, e.g.
# formdata_model) are still resolved via respond_to?/send, so user reopens
# of this class to add per-type formdata builders keep working.
#
# Reached via Lux::Api::SysApi#postman -> /<mount_on>/sys/postman.

module Lux
  class Api
    class PostmanSchema
      def initialize api, mount_on: nil
        @api      = api
        @mount_on = mount_on
      end

      def postman
        doc = Lux::Api::Introspect.schema(mount_on: @mount_on)

        out = {
          info: {
            _postman_id:   request.url,
            _bearer_token: @api[:bearer],
            name:          request.host,
            schema:        'https://schema.getpostman.com/json/collection/v2.1.0/collection.json'
          },
          item: []
        }

        doc[:apis].each do |api_name, api_doc|
          group = { name: api_name, item: [] }

          [:collection, :member].each do |type|
            methods = api_doc[type] or next

            methods.each do |action, mdata|
              group[:item].push postman_add_method(
                type:        type,
                object_name: api_name,
                name:        action.to_s,
                item:        mdata
              )
            end
          end

          out[:item].push group
        end

        @api[:development] ? JSON.pretty_generate(out) : out.to_json
      end

      private

      # Build a single postman item from an introspection method entry.
      # `item` is the per-method hash from Introspect (path, http, params, desc).
      def postman_add_method type:, object_name:, name:, item:
        raw_url     = absolute_url(item[:path])
        path_parts  = item[:path].sub(/^\//, '').split('/')
        display     = type == :collection ? "#{name}*" : name

        out = {
          name:    display,
          request: {
            method: Array(item[:http]).reject { |m| m == 'POST' }.first || 'POST',
            header: [],
            url: {
              raw:      raw_url,
              protocol: request.scheme,
              host:     request.host.split('.'),
              port:     request.port,
              path:     path_parts
            }
          }
        }
        out[:description] = item[:desc] if item[:desc]

        (item[:params] || {}).each do |key, value|
          out[:request][:body] ||= { mode: 'formdata', formdata: [] }

          formdata_custom = 'formdata_%s' % value[:type]

          # if value[:type] == 'model' and key == 'user' you can define
          # `formdata_model` that returns list of fields for that model
          formdata_value = if respond_to?(formdata_custom)
            opts = { key: key, value: value, name: name, type: type, group: object_name }
            [send(formdata_custom, opts.to_hwia)].flatten
          else
            { key: key, description: value[:type] }
          end

          formdata_value = [formdata_value] unless formdata_value.is_a?(Array)
          out[:request][:body][:formdata].push *formdata_value
        end

        out
      end

      # Combine request host with the introspection path (which already
      # includes mount_on, e.g. "/api/company/:ref/show").
      def absolute_url path
        "#{request.scheme}://#{request.host_with_port}#{path}"
      end

      def request
        @api[:api_host].request
      end
    end
  end
end
