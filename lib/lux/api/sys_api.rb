# Reserved /sys namespace: serves introspection JSON, generator outputs
# (postman, openapi) and a health probe. Inherits straight from Lux::Api to
# stay outside any user-defined ApplicationApi callback stack.

module Lux
  class Api
    class SysApi < Lux::Api
      class_desc 'Lux::Api system endpoints: introspection, schema export, health.'

      allow :get
      desc 'Raw introspection schema (single source of truth for all generators).'
      def schema
        response('application/json') do
          JSON.pretty_generate(Lux::Api::Introspect.schema(mount_on: derive_mount_on))
        end
      end

      allow :get
      desc 'Postman collection v2.1, built from the introspection schema.'
      def postman
        response('application/json') do
          Lux::Api::PostmanSchema.new(@api, mount_on: derive_mount_on).postman
        end
      end

      allow :get
      desc 'OpenAPI 3 specification, built from the introspection schema.'
      def openapi
        response('application/json') do
          JSON.pretty_generate(Lux::Api::OpenapiSchema.new(@api, mount_on: derive_mount_on).openapi)
        end
      end

      allow :get
      desc 'Interactive API explorer. Default response is index.html; pass ?file=lux-api-nav.fez (or any whitelisted file under lib/lux/api/web/) to fetch a specific asset. Content-Type is inferred from the extension.'
      def web
        result = Lux::Api::Web.render(file: @api.params[:file])
        response(result[:content_type]) { result[:body] }
      rescue ArgumentError => e
        response.error e.message, status: 400
      end

      allow :get
      desc 'AGENTS.md for LLMs/AIs - how to call this API and build tools against it. Generated from introspection.'
      def agents
        response('text/markdown; charset=utf-8') do
          Lux::Api::AgentsMd.new(@api, mount_on: derive_mount_on).render
        end
      end

      allow :get
      desc 'Health probe.'
      def health
        response('application/json') do
          { ok: true, schema_version: Lux::Api::Introspect::SCHEMA_VERSION }.to_json
        end
      end

      private

      # Recover the actual mount prefix from the live request path; this is
      # more reliable than OPTS[:api][:mount_on], which is global state that
      # the last-loaded class wins.
      def derive_mount_on
        path = @api.request&.path
        return OPTS.dig(:api, :mount_on) || '/' unless path

        # "/api/sys/schema" -> "/api"
        prefix = path.split('/sys/').first.to_s
        prefix.empty? ? '/' : prefix
      end
    end
  end
end
