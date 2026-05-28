# Convention-based routing mixin for controllers.
#
# Include it; Auto supplies a `call` that runs `filter` then renders the template
# matching cattr.layout + nav.path:
#
#   class MainController < FrontendController
#     include Lux::Controller::Auto    # usually via ControllerAutoLoader
#     layout :main
#
#     filter do                  # optional - runs before auto_render
#       filter :spaces do ... end
#     end
#   end
#
# Override `call` for full control. `auto_render` renders cattr.layout + nav.path;
# `filter` is the entry hook and the nav.path matcher; `auto_export_var` loads a
# model by ref.
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
        # Stores the block; the instance-level #filter (invoked by #call) runs it.
        def filter &block
          @auto_filter = block if block
          @auto_filter
        end
      end

      # Default entry point for convention-routed controllers (mounted via
      # `call 'main#call'`). Runs #filter, then renders the cattr.layout + nav.path
      # template unless a filter already rendered or redirected.
      def call
        filter
        auto_render unless lux.response.body?
      end

      # Find a template by path under cattr.template_root (default ./app/views).
      # Tries /path.{haml,md,erb} then /path/root.{...}; returns the path or nil.
      #   auto_find_template(['main', 'notes'])  ->  '/main/notes' or nil
      def auto_find_template path
        root     = cattr.template_root
        path     = path.flatten.map { _1.to_s.gsub('-', '_') }
        tpl_root = '/' + path.join('/')

        AUTO_PATH_CACHE[tpl_root] = nil if Lux.env.dev?
        AUTO_PATH_CACHE[tpl_root] ||= begin
          for check in [tpl_root, "#{tpl_root}/root"]
            for ext in AUTO_EXTS
              return check if File.exist?("#{root}#{check}.#{ext}")
            end
          end
          nil
        end
      end

      # Render the template matching cattr.layout + nav.path, or the 404 page.
      def auto_render
        path = [cattr.layout] + nav.path
        if tpl = auto_find_template(path)
          render tpl
        else
          base = '/' + path.join('/')
          exts = AUTO_EXTS.map { |e| ".#{e}" }.join(', ')
          @paths = ["#{base}{#{exts}}", "#{base}/root{#{exts}}"]
          render '/error_404', status: 404
        end
      end

      # Find a model by ref, optionally policy-check, set @object and @<name>.
      #   auto_export_var :task, params[:t], :read
      def auto_export_var name, ref, can = nil
        name = name.to_s.singularize

        if @object = name.classify.constantize.find(ref)
          @object = @object.can.send("#{can}!") if can
          instance_variable_set "@#{name}".to_sym, @object
        else
          raise Lux.error.not_found "Object not found"
        end
      end

      # Two call shapes share this name:
      #
      #   filter                       Entry hook invoked by #call. Runs the
      #                                class-level `filter do |mount_on| ... end`
      #                                block (mount_on = cattr.layout) when one is
      #                                defined; a no-op otherwise. Override with
      #                                `def filter` on the controller and call
      #                                `super` to keep the class-level block.
      #
      #   filter :seg [, :seg] do end  Runtime nav.path matcher. Runs the block
      #                                only when the segments at the current depth
      #                                match; nesting descends one segment per
      #                                level so filters read like the URL. `:ref`
      #                                matches the extracted ref placeholder. Pass
      #                                several segments to match in one step
      #                                (`filter :admin, :users`). A filter that
      #                                renders or redirects sets the response
      #                                body, so #call then skips auto_render.
      #     filter :spaces do        # /spaces/*
      #       filter :ref do         # /spaces/:ref/*
      #         filter :admin do ... end   # /spaces/:ref/admin
      #       end
      #     end
      def filter *segments, &block
        if segments.empty? && block.nil?
          if blk = self.class.filter
            instance_exec cattr.layout, &blk
          end
          return
        end

        return unless block

        @filter_depth ||= 0
        path     = nav.path.drop(@filter_depth).map { _1.to_s.gsub('-', '_') }
        segments = segments.map { _1.to_s.gsub('-', '_') }

        return unless path[0, segments.length] == segments

        @filter_depth += segments.length
        instance_eval(&block)
        @filter_depth -= segments.length
      end
    end
  end
end
