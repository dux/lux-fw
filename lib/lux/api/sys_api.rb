# Reserved /sys namespace: serves introspection JSON, generator outputs
# (postman, openapi) and a health probe. Inherits straight from Lux::Api to
# stay outside any user-defined ApplicationApi callback stack.

module Lux
  class Api
    class SysApi < Lux::Api
      class_desc 'Lux::Api system endpoints: introspection, schema export, health.'

      # action -> one-line description, also the source for the /sys/ index.
      ENDPOINTS ||= {
        schema:  'Canonical introspection JSON',
        openapi: 'OpenAPI 3 spec',
        postman: 'Postman 2.1 collection',
        hammer:  'lux-hammer CLI client (Ruby source)',
        web:     'Interactive browser explorer',
        agents:  'AGENTS.md for LLMs',
        health:  'Liveness probe'
      }.freeze

      allow :get
      desc 'Plain-text index of the system endpoints (served at /<mount>/sys/).'
      define :index do
        proc do
          response('text/plain; charset=utf-8') { sys_index }
        end
      end

      allow :get
      desc 'Raw introspection schema (single source of truth for all generators).'
      define :schema do
        proc do
          response('application/json') do
            JSON.pretty_generate(Lux::Api::Introspect.schema(mount_on: derive_mount_on))
          end
        end
      end

      allow :get
      desc 'Postman collection v2.1, built from the introspection schema.'
      define :postman do
        proc do
          response('application/json') do
            Lux::Api::PostmanSchema.new(@api, mount_on: derive_mount_on).postman
          end
        end
      end

      allow :get
      desc 'OpenAPI 3 specification, built from the introspection schema.'
      define :openapi do
        proc do
          response('application/json') do
            JSON.pretty_generate(Lux::Api::OpenapiSchema.new(@api, mount_on: derive_mount_on).openapi)
          end
        end
      end

      allow :get
      desc 'lux-hammer CLI client (Ruby), generated from the introspection schema. Pipe to a Hammerfile: curl .../sys/hammer > Hammerfile.'
      define :hammer do
        proc do
          response('text/plain; charset=utf-8') do
            Lux::Api::HammerSchema.new(@api, mount_on: derive_mount_on).hammer
          end
        end
      end

      allow :get
      desc 'Interactive API explorer. Default response is index.html; pass ?file=lux-api-nav.fez (or any whitelisted file under lib/lux/api/web/) to fetch a specific asset. Content-Type is inferred from the extension.'
      define :web do
        proc do
          begin
            result = Lux::Api::Web.render(file: @api.params[:file], api: @api, mount_on: derive_mount_on)
            response(result[:content_type]) { result[:body] }
          rescue ArgumentError => e
            response.error e.message, status: 400
          end
        end
      end

      allow :get
      desc 'AGENTS.md for LLMs/AIs - how to call this API and build tools against it. Generated from introspection.'
      define :agents do
        proc do
          response('text/markdown; charset=utf-8') do
            Lux::Api::ErbView.new(@api, mount_on: derive_mount_on).render(Lux.fw_root.join('assets/api/agents.md.erb').to_s)
          end
        end
      end

      allow :get
      desc 'Health probe.'
      define :health do
        proc do
          response('application/json') do
            { ok: true, schema_version: Lux::Api::Introspect::SCHEMA_VERSION }.to_json
          end
        end
      end

      private

      # Right-justified nav of every system endpoint, with absolute URLs built
      # from the current request (scheme/host/mount) so the links work as-is
      # regardless of where the API is mounted or behind which host.
      def sys_index
        req   = @api.request
        base  = req ? "#{req.scheme}://#{req.host_with_port}" : ''
        mount = derive_mount_on
        name_w = ENDPOINTS.keys.map { |k| k.length }.max

        rows = ENDPOINTS.map do |action, desc|
          ["#{base}#{mount}/sys/#{action}", action.to_s, desc]
        end
        url_w = rows.map { |url, _, _| url.length }.max

        lines = ["#{req && req.host} API - system endpoints", '']
        rows.each do |url, action, desc|
          lines << '  %s   %s   %s' % [action.rjust(name_w), url.ljust(url_w), desc]
        end
        lines.join("\n") + "\n"
      end

      # Recover the actual mount prefix from the live request path. With
      # per-class mount_on this matches the dispatching class, even when
      # multiple APIs are mounted at different roots.
      def derive_mount_on
        path = @api.request&.path
        return '/api' unless path

        # "/api/sys/schema" -> "/api"; also the bare index "/api/sys" -> "/api"
        prefix = path.split(%r{/sys(?:/|\z)}).first.to_s
        prefix.empty? ? '/api' : prefix
      end
    end
  end
end
