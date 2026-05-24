module Lux
  module Test
    # Factory builds real model instances from named blueprints. Vendored
    # from clean-mock 0.2.3 (github.com/dux/clean-mock); renamed and
    # namespaced under Lux::Test so the lux test suite has no external
    # test dep. The `factory` helper is exposed inside Minitest::Spec
    # (see Lux::Test::Case); it is NOT injected onto Object.
    class Factory
      VERSION ||= '0.2.3-lux'

      attr_reader :model

      @@fetched     ||= {}
      @@blueprints  ||= {}
      @@sequence    ||= {}

      class << self
        # register a blueprint
        def define name, opts = {}, &block
          @@blueprints[name] = [block, opts]
        end

        def attributes_for *args
          build(*args).attributes.select { |_k, v| !v.nil? && v != '' }
        end

        # instantiate without save
        def build *args
          new(*args).model
        end

        # instantiate and save if model responds to :save
        def create *args
          new(*args).create_model
        end

        # memoized create, keyed on args identity
        def fetch *args, &block
          @@fetched[args] ||= create(*args, &block)
        end

        # clear sequence counters + fetch cache; called between tests
        def reset
          @@fetched.clear
          @@sequence.clear
        end

        # for diagnostics
        def known
          @@blueprints.keys
        end
      end

      def initialize *args
        opts    = args.last.is_a?(::Hash) ? args.pop : {}
        @kind   = args.shift
        @traits = args

        block, blueprint_opts = @@blueprints[@kind] || raise(
          ArgumentError,
          'Factory blueprint "%s" not defined. Known: %s' % [@kind, @@blueprints.keys.join(', ')]
        )

        @model =
        case blueprint_opts[:class]
        when false
          nil
        when nil
          @kind.to_s.classify.constantize.new
        when Symbol
          name = blueprint_opts[:class].to_s.classify
          if Object.const_defined?(name)
            name.constantize.new
          else
            Object.const_set(name, Class.new).new
          end
        else
          blueprint_opts[:class].new
        end

        if @model
          instance_exec @model, opts, &block
        else
          @model = instance_exec opts, &block
        end

        raise 'Trait [%s] not found' % @traits.join(', ') if @traits.first
      end

      # invoked inside a define block to apply a named variant
      def trait name, &block
        if @traits.delete(name)
          instance_exec(@model, &block)
        end
      end

      # define or overload a singleton method on the current model
      def func name, &block
        @model.define_singleton_method(name, &block)
      end

      # auto-incrementing counter, one per name
      def sequence name = nil, start = nil
        name ||= :seq
        @@sequence[name] ||= start || 0
        @@sequence[name] += 1
      end

      # link a created sibling model: `create :org` -> @model.org_id = factory.create(:org).id
      def create name, field = nil
        field ||= name.to_s.singularize + '_id'
        new_model = Factory.create(name)
        @model.send('%s=' % field, new_model.id)
        new_model
      end

      def create_model
        @model.save if @model.respond_to?(:save)
        @after_create.call if @after_create
        @model
      end

      # callback fires after create/fetch save, not after build
      def after_create &block
        @after_create = block
      end
      alias_method :after_save, :after_create
    end
  end
end
