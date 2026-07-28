# Convention-based routing mixin for controllers.
#
# Mixed into every controller by default (see controller.rb). Path filters run
# automatically each action (Controller#action); `auto` renders the template
# matching cattr.layout + nav.path. Including it explicitly is harmless:
#
#   class MainController < FrontendController
#     layout :main
#
#     filter do                  # optional - runs before auto_render
#       filter :spaces do ... end
#     end
#   end
#
# Override `auto` for full control. `auto_render` renders cattr.layout + nav.path;
# `filter` runs automatically per action as the nav.path matcher. Model loading
# by ref now lives on `nav.load_models` (db plugin).
module Lux
  class Controller
    module Auto
      AUTO_EXTS       ||= %w[haml md erb].freeze
      AUTO_PATH_CACHE ||= {}

      def self.included base
        base.extend ClassMethods
      end

      module ClassMethods
        # Class-level `filter do |mount_on| ... end` - the static counterpart to
        # the runtime `filter :seg do ... end` matcher, in the spirit of `before do`.
        # Stores the block; the instance-level #filter (invoked automatically
        # each action by Controller#action) runs it.
        def filter &block
          @auto_filter = block if block
          @auto_filter
        end
      end

      # Default entry point for convention-routed controllers (mounted via
      # `call 'main#auto'`). Filters already ran automatically (Controller#action),
      # so this just renders the cattr.layout + nav.path template unless a filter
      # already rendered or redirected.
      def auto
        auto_render
      end

      # Two call shapes share this name:
      #
      #   filter                       Invoked automatically each action by
      #                                Controller#action. Runs the class-level
      #                                `filter do |mount_on| ... end` block
      #                                (mount_on = cattr.layout) when one is
      #                                defined; a no-op otherwise. Override with
      #                                `def filter` on the controller and call
      #                                `super` to keep the class-level block.
      #
      #   filter :seg [, :seg] do end  Runtime route matcher. Runs the block only
      #                                when the segments at the cursor match;
      #                                nesting descends one segment per level so
      #                                filters read like the URL. `:ref` matches
      #                                any segment `nav.ref` classified as an id,
      #                                by type - so the classifier has to have run,
      #                                and a segment literally spelled "ref" is not
      #                                one. Pass several
      #                                segments to match in one step
      #                                (`filter :admin, :users`). A filter that
      #                                renders or redirects sets the response
      #                                body, so the action is then skipped.
      #     filter :spaces do        # /spaces/*
      #       filter :ref do         # /spaces/:ref/*
      #         filter :admin do ... end   # /spaces/:ref/admin
      #       end
      #     end
      #
      # Matching runs against `lux.route`, the same cursor `map` advances, so a
      # controller mounted under a prefix (`map 'dev', 'dev#auto'`) does not
      # repeat that prefix in its filters.
      def filter *segments, &block
        if segments.empty? && block.nil?
          if blk = self.class.filter
            instance_exec cattr.layout, &blk
          end
          return
        end

        return unless block
        return unless lux.route.start_with?(*segments)

        lux.route.with_scope(segments.length) { instance_eval(&block) }
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

        AUTO_PATH_CACHE[key] = [tpl_root, "#{tpl_root}/root"].find do |check|
          AUTO_EXTS.any? { |ext| File.exist?("#{root}#{check}.#{ext}") }
        end
      end

      # Render the template matching cattr.layout + the remaining route path, or
      # raise a 404. The 404 flows through the app error sink, which renders the
      # error template at the layout root (e.g. app/views/main/error.haml).
      def auto_render
        return if lux.response.body?

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
