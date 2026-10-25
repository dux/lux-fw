# Convention rendering: `auto` renders the template matching the router's views
# dir + the rest of the route path, else 404s.
#
#   class MainRouter < FrontendRouter
#     layout :main
#
#     route do
#       map :spaces, :ref, :admin do
#         @space.can.update!
#       end
#       auto                     # /spaces/:ref/admin -> app/views/main/spaces/ref/admin/root.haml
#     end
#   end
#
# `auto_render` is the bare renderer, for actions that pick their own moment
# (`def call; nav.load_models; auto_render; end`).
module Lux
  class Router
    module Auto
      AUTO_EXTS       ||= %w[haml md erb].freeze
      AUTO_PATH_CACHE ||= {}

      # Inside an action renders straight away. Called from a route block it
      # dispatches as action :auto first, so the verb check, params validation
      # and before_render hooks see an action name.
      def auto
        @_lux.action ? auto_render : action(:auto)
      end

      private

      # Find a template by path under cattr.template_root (default ./app/views).
      # Tries /path.{haml,md,erb} then /path/root.{...}; returns the path or nil.
      # URL segments are underscored here because that is how template files are
      # named on disk.
      #   auto_find_template(['main', 'notes'])  ->  '/main/notes' or nil
      def auto_find_template path
        root     = cattr.template_root
        tpl_root = '/' + path.flatten.map { _1.to_s.tr('-', '_') }.join('/')
        key      = "#{root}#{tpl_root}"

        AUTO_PATH_CACHE.delete(key) if Lux.env.dev?
        return AUTO_PATH_CACHE[key] if AUTO_PATH_CACHE.key?(key)

        found = [tpl_root, "#{tpl_root}/root"].find do |check|
          AUTO_EXTS.any? { |ext| Lux.root.resolve("#{root}#{check}.#{ext}") }
        end

        # only hits are cached: misses are keyed by whatever path a client
        # sends, so caching them grows the hash without bound
        found ? AUTO_PATH_CACHE[key] = found : nil
      end

      # Render the template matching the views dir + the remaining route path,
      # or raise a 404. The 404 flows through the app error sink, which renders
      # the error template at the views root (e.g. app/views/main/error.haml).
      def auto_render
        throw :done if lux.response.body?

        # normalized_path, not path: a classified id renders as its value, but
        # on disk the convention is a literal `ref` segment (boards/ref/edit.haml)
        path = [template_dir] + lux.route.normalized_path
        if tpl = auto_find_template(path)
          render tpl
        else
          base = '/' + path.join('/')
          exts = AUTO_EXTS.map { |e| ".#{e}" }.join(', ')
          raise Lux.error.not_found Lux.debug?('Not Found') { "No template found, looked for #{base}{#{exts}} and #{base}/root{#{exts}}" }
        end
      end
    end
  end
end
