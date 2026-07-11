# DB-related extensions to the Lux::Schema::Define DSL.
#
# Only loaded with `Lux.plugin :db`, since the helpers below describe
# database columns / migrations.

module Lux
  class Schema
    class Define
      # `timestamps` inside `schema do ... end` adds the canonical audit
      # quartet: created_at, updated_at, creator_ref, updater_ref.
      # Lux::Type::RefType is provided by plugins/db/lib/ref_type.rb.
      def timestamps
        created_at Time
        updated_at Time
        creator_ref :ref
        updater_ref :ref
      end

      # Declare an enum field inside `schema do ... end`. Synthesizes the
      # backing column rule AND registers the enum on the Sequel model
      # (class accessor + instance label method + save-time validation).
      #
      # Column suffix is derived from the first key's type:
      #   Integer => "<name>_id"  :integer column
      #   else    => "<name>_sid" :string column (max = longest key length)
      #
      # The class accessor name is pluralized: enum :status -> Klass.statuses
      #
      #   enum :status, default: 'a', meta: { as: :buttons } do |f|
      #     f[:a] = 'Active'
      #     f[:i] = 'Inactive'
      #   end
      #
      #   enum :priority do |f|
      #     f[1] = 'Low'
      #     f[2] = { name: 'Normal', icon: :dot }
      #     f[3] = 'High'
      #   end
      #
      #   enum :kind, values: ['ta', 'is']  # array shorthand
      #
      # opts:
      #   default:  default key (must be in the value set)
      #   field:    column override (defaults to "<name>_sid" or "<name>_id")
      #   method:   instance label method (defaults to <name>)
      #   values:   array or hash shorthand (block takes precedence)
      #   helpers:  :both | :class | :instance | false
      #   validate: false to skip enums_plugin save-time validation
      #   meta:     merged into the field's meta (label/as/hint/etc.)
      def enum field, opts = {}, &block
        # plain Hash here (not to_lux_hash) so Integer keys survive for type
        # detection; enums_plugin re-wraps as lux_hash with its own caster.
        raw =
          if block
            {}.tap { |h| block.call(h) }
          elsif opts[:values].is_a?(Array)
            opts[:values].inject({}) { |h, k| h[k] = nil; h }
          elsif opts[:values].is_a?(Hash)
            opts[:values]
          end

        Lux.shell.die 'enum :%s: no values given (block or values:)' % field if raw.nil? || raw.empty?

        keys     = raw.keys
        classes  = keys.map { |k| k.is_a?(Integer) ? :int : :other }.uniq
        Lux.shell.die 'enum :%s: mixed key types %s' % [field, keys.map(&:class).uniq.inspect] if classes.length > 1

        is_int   = classes.first == :int
        suffix   = is_int ? '_id' : '_sid'
        col_type = is_int ? :integer : :string

        field_str = field.to_s
        required  = !field_str.end_with?('?')
        base      = field_str.sub('?', '')

        col       = (opts[:field]  || "#{base}#{suffix}").to_sym
        meth      = (opts[:method] || base).to_sym
        enum_name = base.to_sym
        plural    = base.pluralize.to_sym

        if opts.key?(:default) && !opts[:default].nil?
          # normalize both sides so :a and 'a' compare equal for string-keyed
          # enums; integer-keyed enums compare by stringified form too
          unless keys.map(&:to_s).include?(opts[:default].to_s)
            Lux.shell.die 'enum :%s: default %p not in keys %p' % [base, opts[:default], keys]
          end
        end

        if @rules.key?(col)
          Lux.shell.die 'enum :%s: column :%s already declared' % [base, col]
        end

        # The Sequel adapter populates collection_ref[:klass] after the
        # model class binds, so the lambda can resolve Klass.<plural> at
        # form-render time without us knowing the class at schema-define time.
        collection_ref = {}
        meta_opts = (opts[:meta] || {}).dup
        meta_opts[:collection] ||= proc { collection_ref[:klass].send(plural) }

        field_opts = {
          type:     col_type,
          required: required,
          allowed:  keys,
          meta:     meta_opts
        }
        field_opts[:default] = opts[:default] if opts.key?(:default)
        field_opts[:max]     = keys.map { |k| k.to_s.length }.max unless is_int

        @rules[col] = field_opts

        (@enums ||= []) << {
          name:           enum_name,
          field:          col,
          method:         meth,
          default:        opts[:default],
          required:       required,
          values:         raw,
          helpers:        opts.fetch(:helpers, :both),
          validate:       opts.fetch(:validate, true),
          collection_ref: collection_ref
        }
      end

      def enums_list
        @enums || []
      end
    end
  end
end
