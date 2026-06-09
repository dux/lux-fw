# Hammerfile generator. Consumes Lux::Api::Introspect.schema and emits a
# ready-to-run lux-hammer CLI client as plain Ruby source: one namespace per
# API class, one task per action, a shared POST helper, and (when the API
# exposes one) a `login` task. Meant to be piped straight onto a client:
#   curl -s <base>/<mount_on>/sys/hammer > Hammerfile
# Reached via Lux::Api::SysApi#hammer -> /<mount_on>/sys/hammer.

module Lux
  class Api
    class HammerSchema
      # action names that look like a credentials->token exchange; the match
      # is wired as a no-auth `login` task that caches the returned token.
      LOGIN_RE ||= /\A(login|sign_?in|authenticate|token)\z/i

      # param types we can mirror 1:1 onto a hammer opt; the rest -> :string.
      OPT_TYPES ||= %w[integer float boolean array].freeze

      def initialize api, mount_on: nil
        @api      = api
        @mount_on = mount_on
      end

      def hammer
        doc   = Lux::Api::Introspect.schema(mount_on: @mount_on)
        parts = [preamble(doc)]
        if entry = login_action(doc)         # optional login task, only if found
          parts << login_task(entry)
        end
        doc[:apis].each { |name, api_doc| parts << api_block(name, api_doc) }
        parts.join("\n")
      end

      private

      # per-host token file so several generated clients can coexist
      def token_path
        '~/.%s_token' % request.host.gsub(/[^a-z0-9]+/i, '_')
      end

      def base_url
        "#{request.scheme}://#{request.host_with_port}"
      end

      # header: requires, BASE/STATE consts, top-level desc, shared api_post.
      # api_post lives in a `helpers do` block (per lux-hammer AGENTS.md) so
      # task procs can call it as a bare name and reach Shell#error.
      def preamble doc
        <<~RUBY
          # lux-hammer client generated from #{request.host} (#{doc[:mount_on]}).
          # Regenerate: curl -s #{base_url}#{doc[:mount_on]}/sys/hammer > Hammerfile
          require 'net/http'
          require 'json'
          require 'uri'

          BASE  ||= '#{base_url}'
          STATE ||= File.expand_path('#{token_path}')

          desc 'CLI client for the #{request.host} API'

          helpers do
            # POST a JSON body to <path>, unwrap the { data: } envelope, raise
            # on an { error: } body. Bearer token attached unless no_auth.
            def api_post(path, params = {}, no_auth: false)
              uri = URI("\#{BASE}\#{path}")
              req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
              req['Authorization'] = "Bearer \#{File.read(STATE).strip}" if !no_auth && File.exist?(STATE)
              req.body = params.to_json
              res  = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') { |h| h.request(req) }
              body = JSON.parse(res.body) rescue res.body
              error "API error: \#{body['error']}" if body.is_a?(Hash) && body['error']
              body.is_a?(Hash) ? (body['data'] || body) : body
            end
          end
        RUBY
      end

      # first collection action whose name reads like a login (see LOGIN_RE)
      def login_action doc
        doc[:apis].each_value do |api_doc|
          (api_doc[:collection] || {}).each do |action, entry|
            return entry if action.to_s =~ LOGIN_RE
          end
        end
        nil
      end

      def login_task entry
        params = entry[:params] || {}
        lines  = ['task :login do', "  desc 'log in and cache the bearer token'"]
        params.each { |n, spec| lines << "  #{opt_line(n, spec)}" }
        lines << '  proc do |o|'
        lines << "    File.write(STATE, api_post('#{entry[:path]}', #{params_hash(params)}, no_auth: true).to_s)"
        lines << "    say.green 'token cached to ' + STATE"
        lines << '  end'
        lines << "end\n"
        lines.join("\n")
      end

      # one `namespace :<api>` with a task per collection/member action
      def api_block name, api_doc
        ns    = name.to_s.gsub(/[^a-z0-9]+/i, '_')   # admin/users -> admin_users
        lines = ["namespace :#{ns} do"]
        { collection: false, member: true }.each do |type, member|
          (api_doc[type] || {}).each do |action, entry|
            lines << indent(task_block(action, entry, member), 2)
          end
        end
        lines << "end\n"
        lines.join("\n")
      end

      # member tasks take the record ref as the first positional arg (o[:args]);
      # `ref` is the API's canonical member identifier (the :ref path segment).
      def task_block action, entry, member
        params = entry[:params] || {}
        lines  = ["task :#{action} do", "  desc #{(entry[:desc] || action.to_s).inspect}"]
        params.each { |n, spec| lines << "  #{opt_line(n, spec)}" }
        lines << '  proc do |o|'
        if member
          path = entry[:path].sub('/:ref', '/#{ref}')   # interpolated in generated source
          lines << "    ref = o[:args].first or error 'ref required'"
          lines << "    say api_post(\"#{path}\", #{params_hash(params)}).inspect"
        else
          lines << "    say api_post('#{entry[:path]}', #{params_hash(params)}).inspect"
        end
        lines << '  end'
        lines << 'end'
        lines.join("\n")
      end

      def opt_line name, spec
        out  = "opt :#{name}"
        type = spec[:type].to_s
        out += ", type: :#{type}"                     if OPT_TYPES.include?(type)
        out += ', req: true'                          if spec[:required]
        out += ", default: #{spec[:default].inspect}" unless spec[:default].nil?
        if d = (spec[:description] || spec[:desc])
          out += ", desc: #{d.inspect}"
        end
        out
      end

      def params_hash params
        return '{}' if params.empty?
        '{ %s }' % params.keys.map { |k| "#{k}: o[:#{k}]" }.join(', ')
      end

      def indent text, n
        pad = ' ' * n
        text.split("\n").map { |l| l.empty? ? l : pad + l }.join("\n")
      end

      def request
        @api[:api_host].request
      end
    end
  end
end
