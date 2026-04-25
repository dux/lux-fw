# Auto controller plugin for convention-based routing
# Provides filter matching and template auto-finding
#
# Usage:
#   class MainController < ApplicationController
#     include Lux::AutoController
#
#     def filters
#       filter :notes do
#         filter :ref do
#           # runs for /notes/:id
#         end
#       end
#     end
#
#     def call
#       auto_load_models
#       filters
#       render auto_find_template(['main'] + nav.path)
#     end
#   end

module Lux
  module AutoController
    AUTO_PATH_CACHE = {}

    # Runtime filter matching against nav.path
    # Executes block only if path matches segments at current depth
    # Supports nesting - each level increments depth
    #
    # Examples:
    #   # matches /notes, /notes/foo, /notes/123/bar
    #   filter :notes do
    #     @note_section = true
    #   end
    #
    #   # matches /notes/ref (where ref is ULID placeholder)
    #   filter :notes do
    #     filter :ref do
    #       @note.can.read!
    #     end
    #   end
    #
    #   # matches /admin/users
    #   filter :admin, :users do
    #     require_admin!
    #   end
    #
    #   # matches /api/v1/*
    #   filter :api do
    #     filter :v1 do
    #       @api_version = 1
    #     end
    #   end
    #
    #   # early return with render
    #   filter :invite_link do
    #     render text: 'TODO'
    #   end
    def filter *segments, &block
      return unless block_given?

      @filter_depth ||= 0
      return if @filter_matched_depth && @filter_depth <= @filter_matched_depth

      path = nav.path.drop(@filter_depth).map { _1.to_s.gsub('-', '_') }
      segments = segments.map { _1.to_s.gsub('-', '_') }

      # Check if remaining path starts with segments
      return unless path[0, segments.length] == segments

      @filter_matched_depth = @filter_depth
      @filter_depth += segments.length
      instance_eval(&block)
      @filter_depth -= segments.length
    end

    AUTO_TEMPLATE_EXTS = %w[haml md erb].freeze

    # Find template by path, returns nil if not found
    # Tries: /path.{haml,md,erb} then /path/root.{haml,md,erb}
    #
    # Examples:
    #   auto_find_template(['main', 'notes'])
    #   # tries ./app/views/main/notes.haml, .md, .erb
    #   # then  ./app/views/main/notes/root.haml, .md, .erb
    #
    #   auto_find_template(['main', 'boards', 'ref', 'kanban'])
    #   # tries ./app/views/main/boards/ref/kanban.haml, .md, .erb
    #   # then  ./app/views/main/boards/ref/kanban/root.haml, .md, .erb
    #
    #   # typical usage in controller
    #   tpl = auto_find_template([root] + nav.path)
    #   tpl ? render(tpl) : render('/errors/404', status: 404)
    def auto_find_template path
      path = path.flatten.map { _1.to_s.gsub('-', '_') }
      tpl_root = '/' + path.join('/')

      AUTO_PATH_CACHE[tpl_root] = nil if Lux.env.dev?
      AUTO_PATH_CACHE[tpl_root] ||= begin
        for check in [tpl_root, "#{tpl_root}/root"]
          for ext in AUTO_TEMPLATE_EXTS
            return check if File.exist?("./app/views#{check}.#{ext}")
          end
        end
        nil
      end
    end

    def auto_render
      path = [cattr.layout] + nav.path
      if tpl = auto_find_template(path)
        render tpl
      else
        base = '/' + path.join('/')
        exts = AUTO_TEMPLATE_EXTS.map { |e| ".#{e}" }.join(', ')
        @paths = ["#{base}{#{exts}}", "#{base}/root{#{exts}}"]
        render '/error_404', status: 404
      end
    end

    # Auto export model instance variable by name and ref
    # Finds model by ref, optionally checks permission, sets instance variable
    #
    # Examples:
    #   auto_export_var :board, 'abc123'
    #   # @object = Board.find('abc123')
    #   # @board = @object
    #
    #   auto_export_var :tasks, params[:t], :read
    #   # @object = Task.find(params[:t])
    #   # @object.can.read!
    #   # @task = @object
    #
    #   auto_export_var 'users', params[:u], :manage
    #   # @object = User.find(params[:u])
    #   # @object.can.manage!
    #   # @user = @object
    def auto_export_var name, ref, can = nil
      name = name.to_s.singularize

      if @object = name.classify.constantize.find(ref)
        @object = @object.can.send("#{can}!") if can
        instance_variable_set "@#{name}".to_sym, @object
      else
        raise Lux.error.not_found "Object not found"
      end
    end

    # /org/foobar123 -> @object = @org = Org.find('foobar123')
    def auto_load_object
      if nav.id
        model = nav.path[0].classify
        if Object.const_defined?(model)
          @object = model.constantize.find(nav.id)
          instance_variable_set "@#{@object.class.to_s.underscore}".to_sym, @object
        end
      end
    end
  end
end
