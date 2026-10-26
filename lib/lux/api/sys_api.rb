# Reserved /sys namespace: serves introspection JSON, generator outputs
# (postman, openapi) and a health probe. Inherits straight from Lux::Api to
# stay outside any user-defined ApplicationApi callback stack.

module Lux
  class Api
    class SysApi < Lux::Api
      class_desc 'Lux::Api system endpoints: introspection, schema export, health.'

      # action -> one-line description, also the source for the /sys/ index.
      ENDPOINTS ||= {
        guide:   'Human guide (markdown; HTML for browsers)',
        md:      'Raw markdown of the guide (always text/markdown)',
        schema:  'Canonical introspection JSON',
        openapi: 'OpenAPI 3 spec',
        postman: 'Postman 2.1 collection',
        hammer:  'lux-hammer CLI client (Ruby source)',
        web:     'Interactive browser explorer',
        agents:  'AGENTS.md for LLMs',
        health:  'Liveness probe'
      }.freeze

      allow :get, :post
      desc 'Plain-text index of the system endpoints (served at /<mount>/sys/).'
      define :index do
        proc do
          response('text/plain; charset=utf-8') { sys_index }
        end
      end

      allow :get, :post
      desc 'Raw markdown of the human API guide (always text/markdown).'
      define :md do
        proc do
          response('text/markdown; charset=utf-8') do
            Lux::Api::Guide.markdown(@api, mount_on: mount_path)
          end
        end
      end

      allow :get, :post
      desc 'Human-readable API guide generated from introspection. Rendered to HTML for browsers, raw markdown otherwise (or with ?format=md).'
      define :guide do
        proc do
          mount = mount_path
          if @api.params[:format].to_s == 'md' || !browser?
            response('text/markdown; charset=utf-8') do
              Lux::Api::Guide.markdown(@api, mount_on: mount)
            end
          else
            response('text/html; charset=utf-8') do
              Lux::Api::Guide.html(@api, mount_on: mount)
            end
          end
        end
      end

      allow :get, :post
      desc 'Raw introspection schema (single source of truth for all generators).'
      define :schema do
        proc do
          response('application/json') do
            JSON.pretty_generate(Lux::Api::Introspect.schema(mount_on: mount_path))
          end
        end
      end

      allow :get, :post
      desc 'Postman collection v2.1, built from the introspection schema.'
      define :postman do
        proc do
          response('application/json') do
            Lux::Api::PostmanSchema.new(@api, mount_on: mount_path).postman
          end
        end
      end

      allow :get, :post
      desc 'OpenAPI 3 specification, built from the introspection schema.'
      define :openapi do
        proc do
          response('application/json') do
            JSON.pretty_generate(Lux::Api::OpenapiSchema.new(@api, mount_on: mount_path).openapi)
          end
        end
      end

      allow :get, :post
      desc 'lux-hammer CLI client (Ruby), generated from the introspection schema. Pipe to a Hammerfile: curl .../sys/hammer > Hammerfile.'
      define :hammer do
        proc do
          response('text/plain; charset=utf-8') do
            Lux::Api::HammerSchema.new(@api, mount_on: mount_path).hammer
          end
        end
      end

      allow :get, :post
      desc 'Interactive API explorer. Default response is index.html; pass ?file=fez/nav-block.fez (any whitelisted file under assets/api/web/) to fetch a specific asset. Content-Type is inferred from the extension.'
      define :web do
        proc do
          begin
            result = Lux::Api::Web.render(file: @api.params[:file], api: @api, mount_on: mount_path)
            response(result[:content_type]) { result[:body] }
          rescue ArgumentError => e
            response.error e.message, status: 400
          end
        end
      end

      allow :get, :post
      desc 'AGENTS.md for LLMs/AIs - how to call this API and build tools against it. Generated from introspection.'
      define :agents do
        proc do
          response('text/markdown; charset=utf-8') do
            Lux::Api::ErbView.new(@api, mount_on: mount_path).render(Lux.fw_root.join('assets/api/agents.md.erb').to_s)
          end
        end
      end

      allow :get, :post
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
        mount = mount_path
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

      # A page load from a real browser accepts HTML; curl/scripts default to
      # */* and get the raw markdown.
      def browser?
        @api.request && @api.request.env['HTTP_ACCEPT'].to_s.include?('text/html')
      end

      # The mount prefix auto_mount resolved for this request ('' at /); an
      # in-process render has none, so fall back to the declared mount_on.
      def mount_path
        @api.mount_path || self.class.mount_on
      end
    end
  end
end
