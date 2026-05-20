# Generic file renderer for Lux::Api.
#
#   Lux::Api::ErbView.new(api, mount_on: '/api').render(path)
#
# - If `path` ends in `.erb`, the file is read and evaluated as ERB in the
#   context of the view instance (helpers below are available as method
#   calls inside the template).
# - Otherwise the file is returned verbatim.
#
# The view returns a String. Callers (SysApi#agents, SysApi#web) decide
# the Content-Type from the inner extension.

require 'erb'

module Lux
  class Api
    class ErbView
      def initialize api, mount_on: nil
        @api      = api
        @mount_on = mount_on
      end

      def render path
        body = File.read(path)
        path.end_with?('.erb') ? ERB.new(body, trim_mode: '-').result(binding) : body
      end

      # ---- helpers exposed to ERB templates ----

      def doc
        @doc ||= Lux::Api::Introspect.schema(mount_on: @mount_on)
      end

      def mount_on
        @mount_on.to_s.sub(/\/$/, '').then { |s| s.empty? ? '' : s }
      end

      def base_url
        return '' unless request
        "#{request.scheme}://#{request.host_with_port}"
      end

      def absolute path
        "#{base_url}#{path}"
      end

      def request
        @api && @api[:api_host] && @api[:api_host].request
      end

      # ---- markdown helpers (used by AGENTS.md.erb) ----

      def http_verbs entry
        Array(entry[:http]).uniq
      end

      def primary_verb entry
        verbs = http_verbs(entry)
        verbs.find { |v| v != 'POST' } || 'POST'
      end

      def has_methods? api_doc
        (api_doc[:collection] && !api_doc[:collection].empty?) ||
        (api_doc[:member]     && !api_doc[:member].empty?)
      end

      def params_table params
        return '' if params.nil? || params.empty?

        rows = [
          '| Name | Type | Required | Default | Description |',
          '|---|---|---|---|---|'
        ]
        params.each do |name, spec|
          rows << '| %s | %s | %s | %s | %s |' % [
            name,
            spec[:type] || 'string',
            spec[:required] ? 'yes' : 'no',
            spec[:default].nil? ? '' : spec[:default].to_s,
            (spec[:desc] || '').to_s.gsub('|', '\\|')
          ]
        end
        rows.join("\n")
      end

      def curl_example entry, api_name, action_name, type
        verb = primary_verb(entry)
        path = entry[:path].dup
        path = path.gsub(':ref', '123') if type == :member

        auth = ' \\\n  -H "Authorization: Bearer $TOKEN"'
        url  = absolute(path)

        if verb == 'GET'
          "curl '#{url}'#{auth}"
        else
          body = sample_body(entry[:params])
          if body
            "curl -X #{verb} '#{url}'#{auth} \\\n  -H 'Content-Type: application/json' \\\n  -d '#{body}'"
          else
            "curl -X #{verb} '#{url}'#{auth}"
          end
        end
      end

      def sample_body params
        return nil if params.nil? || params.empty?
        sample = {}
        params.each { |name, spec| sample[name] = sample_value_for(spec) }
        JSON.generate(sample)
      end

      def sample_value_for spec
        return spec[:default] unless spec[:default].nil?
        return spec[:values].first if spec[:values].is_a?(Array) && spec[:values].any?

        case spec[:type].to_s
        when 'integer' then 0
        when 'float'   then 0.0
        when 'boolean' then false
        when 'array'   then []
        when 'hash'    then {}
        else                '...'
        end
      end
    end
  end
end
