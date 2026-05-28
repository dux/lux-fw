# Sequel::Plugins::RefLinker
#
# Single source of truth for the `*_ref` column conventions used across
# models. Replaces the old, scattered `:lux_links` + `:parent_model`
# plugins (those names remain as aliases for compatibility).
#
# Recognised field shapes
# -----------------------
#   :scalar      <name>_ref                       -> belongs_to a single record
#   :array       <name>_refs   (text[])           -> has_many via array of refs
#   :poly_key    parent_key    (text)             -> polymorphic belongs_to ("Class/ref")
#   :poly_pair   (parent_model | parent_type)     -> polymorphic belongs_to (two cols);
#                + parent_ref                        type column is parent_model if present,
#                                                    else parent_type.
#
# All public operations (detect / resolve / assign / scope) work on the
# shapes above. The tree-array shape (`parent_refs text[]`) is handled by
# `model_tree.rb`, which delegates here for its `parent` / `children` /
# `children_refs` accessors.
#
# Usage
# -----
#   class Task < ApplicationModel
#     plugin :ref_linker
#     link :user            # belongs_to via user_ref
#     link :comments        # has_many via Comment.task_ref or parent_key
#   end
#
#   Task.where_ref(@user)         # class-level scope
#   Task.dataset.for(@user)       # dataset-level scope (alias: where_ref)
#   note.parent = @user           # writes parent_key OR parent_type+parent_ref
#   note.parent                   # reads back the parent
#
# Module-level helpers (Sequel::Plugins::RefLinker.<name>) are available
# for callers (e.g. dataset_methods#for) that need shape detection
# without going through the plugin's ClassMethods.

module Sequel::Plugins::RefLinker
  # ------------------------------------------------------------------
  # Module-level API
  # ------------------------------------------------------------------

  class << self
    # Polymorphic type-column lookup. Returns [type_col, :parent_ref] when
    # the host class has either `parent_model` (preferred) or `parent_type`
    # alongside `parent_ref`; nil otherwise. Single source of truth for the
    # poly_pair column resolution used by detect / parent= / parent.
    def poly_pair_columns host_class
      schema = host_class.db_schema
      type_col =
        if schema[:parent_model]
          :parent_model
        elsif schema[:parent_type]
          :parent_type
        end
      type_col ? [type_col, :parent_ref] : nil
    end

    # Inspect host_class and decide which shape it uses to point at target_class.
    # Returns a Hash { kind:, columns: [...] } or nil if no shape matches.
    #   detect(Task, User)    -> { kind: :scalar,    columns: [:user_ref] }
    #   detect(Project, User) -> { kind: :array,     columns: [:user_refs] }
    #   detect(Note, User)    -> { kind: :poly_pair, columns: [:parent_model | :parent_type, :parent_ref] }
    def detect host_class, target_class
      schema = host_class.db_schema
      name   = target_class.to_s.underscore

      scalar = "#{name}_ref".to_sym
      return { kind: :scalar, columns: [scalar] } if schema[scalar]

      array = "#{name}_refs".to_sym
      return { kind: :array, columns: [array] } if schema[array]

      return { kind: :poly_key, columns: [:parent_key] } if schema[:parent_key]
      if cols = poly_pair_columns(host_class)
        return { kind: :poly_pair, columns: cols }
      end

      nil
    end

    # Load the related object(s) from a host instance, given the target class.
    # Returns a single record for :scalar / :poly_key / :poly_pair,
    # an Array of records for :array, or nil if the column is blank.
    #   RefLinker.resolve(@task, User)    -> User instance or nil
    #   RefLinker.resolve(@project, User) -> [User, User, ...]
    def resolve instance, target_class
      shape = detect(instance.class, target_class) or
        raise "No ref link from #{instance.class} to #{target_class}"

      case shape[:kind]
      when :scalar
        v = instance[shape[:columns][0]]
        v.present? ? target_class.find(v) : nil
      when :array
        (instance[shape[:columns][0]] || []).map { target_class.find(_1) }
      when :poly_key
        v = instance[:parent_key] or return nil
        klass, ref = v.split('/', 2)
        klass.constantize.find(ref)
      when :poly_pair
        type = instance[shape[:columns][0]] or return nil
        ref  = instance[shape[:columns][1]]
        type.constantize.find(ref)
      end
    end

    # Write the columns on a host instance so it points at object.
    # Accepts a model instance OR a pre-formatted "Class/ref" string
    # (only meaningful for :poly_key and :poly_pair shapes).
    #   RefLinker.assign(@task, @user)            -> sets task[:user_ref]
    #   RefLinker.assign(@note, @user)            -> sets parent_key OR parent_type+parent_ref
    #   RefLinker.assign(@note, "User/abc123...") -> same, no DB lookup
    def assign instance, object
      if object.is_a?(String)
        if instance.db_schema[:parent_key]
          instance[:parent_key] = object
        elsif cols = poly_pair_columns(instance.class)
          klass, ref = object.split('/', 2)
          instance[cols[0]] = klass
          instance[cols[1]] = ref
        else
          die_missing_poly_columns instance.class
        end
        return object
      end

      shape = detect(instance.class, object.class) or
        raise "No ref link from #{instance.class} to #{object.class}"

      case shape[:kind]
      when :scalar
        instance[shape[:columns][0]] = object.ref
      when :poly_key
        instance[:parent_key] = '%s/%s' % [object.class, object.ref]
      when :poly_pair
        instance[shape[:columns][0]] = object.class.to_s
        instance[shape[:columns][1]] = object.ref
      when :array
        # appending semantics live in the caller; assigning replaces.
        instance[shape[:columns][0]] = [object.ref]
      end
      object
    end

    # Filter a dataset to rows linking to object.
    # Returns the dataset unchanged if object is nil (mirrors old `for` behaviour).
    #   RefLinker.scope(Task.dataset, @user)   -> Task.where(user_ref: @user.ref)
    #   RefLinker.scope(Note.dataset, @user)   -> Note.where(parent_type:..., parent_ref:...)
    def scope dataset, object
      return dataset unless object

      shape = detect(dataset.model, object.class) or
        raise "Unknown link for #{object.class} (probably missing db field on #{dataset.model})"

      col = shape[:columns][0]
      case shape[:kind]
      when :scalar
        dataset.where(col => object.ref)
      when :array
        dataset.where(Sequel.lit("?=any(#{col})", object.ref.to_s))
      when :poly_key
        dataset.where(parent_key: object.key)
      when :poly_pair
        dataset.where(shape[:columns][0] => object.class.to_s, shape[:columns][1] => object.ref)
      end
    end

    # Lux.shell.die helper for the "no polymorphic columns" case. Names
    # the columns the plugin looked for and the host class so the schema
    # gap is obvious from the fatal message.
    def die_missing_poly_columns host_class
      Lux.shell.die [
        'Polymorphic parent columns missing on %s' % host_class,
        'searched for: parent_key, parent_model (+parent_ref), parent_type (+parent_ref)',
        'add one of those columns to the table schema to enable a polymorphic parent'
      ]
    end
  end

  # ------------------------------------------------------------------
  # ClassMethods
  # ------------------------------------------------------------------

  module ClassMethods
    # Class-level scope. Same shape as DatasetMethods#for, kept for the
    # ergonomic `Task.where_ref(@user)` call style.
    def where_ref object
      dataset.for(object)
    end

    # Declare an association via a *_ref / *_refs column.
    #
    #   link :user                    -> belongs_to via user_ref
    #   link :users                   -> has_many via user_refs[] OR reverse lookup
    #   link :user, class: 'OrgUser'  -> override class name
    #   link :user, field: 'owner_ref'-> override column name
    #   link                          -> returns "<self>_ref" symbol (used by other plugins)
    def link name = :_nil, opts = {}
      opts = opts.to_lux_hash :class, :field, :cache

      if name == :_nil
        return ('%s_ref' % self.to_s.underscore).to_sym
      end

      name  = name.to_s
      klass = opts[:class] ? opts[:class].to_s : name.singularize.classify
      field = (opts[:field] || "#{name}_ref").to_s

      if name == name.singularize
        # singular: belongs_to a single record via <name>_ref (falls back to
        # parent_ref so models that store the parent there can still say `link :user`).
        field = db_schema[field.to_sym] ? field : :parent_ref
        class_eval <<-STR, __FILE__, __LINE__ + 1
          def #{name}
            #{field}.present? ? #{klass}.find(#{field}) : nil
          end

          def #{name}= object
            self[:#{field}] = object.ref
          end
        STR
      else
        field = "#{name.singularize}_refs".to_sym

        if db_schema[field.to_sym]
          # plural with <name>_refs[] column: load each ref through find().
          class_eval <<-STR, __FILE__, __LINE__ + 1
            def #{name}
              #{field}.or([]).map { #{klass}.find(_1) }
            end
          STR
        else
          # plural reverse lookup: ask the other side for rows pointing back at us.
          # Resolved at call time via RefLinker.scope so the shape stays accurate
          # even if a column is added to the other model later.
          class_eval <<-STR, __FILE__, __LINE__ + 1
            def #{name}
              Sequel::Plugins::RefLinker.scope(#{klass}.default, self)
            end
          STR
        end
      end
    end
    alias :ref :link
  end

  # ------------------------------------------------------------------
  # InstanceMethods (polymorphic parent)
  # ------------------------------------------------------------------

  module InstanceMethods
    # Set parent. Accepts a model instance OR a pre-formatted "Class/ref"
    # string. Always writes the polymorphic columns (parent_key OR
    # parent_model+parent_ref OR parent_type+parent_ref) - never a typed
    # *_ref column, even if one exists on the host. Use a direct
    # assignment (e.g. task.user = u) or `link :user` if you want to
    # write a scalar column instead.
    def parent= model
      if model.is_a?(String)
        if db_schema[:parent_key]
          self[:parent_key] = model
        elsif cols = Sequel::Plugins::RefLinker.poly_pair_columns(self.class)
          klass, ref = model.split('/', 2)
          self[cols[0]] = klass
          self[cols[1]] = ref
        else
          Sequel::Plugins::RefLinker.die_missing_poly_columns self.class
        end
        @parent = nil
        return model
      end

      if db_schema[:parent_key]
        self[:parent_key] = '%s/%s' % [model.class, model.ref]
      elsif cols = Sequel::Plugins::RefLinker.poly_pair_columns(self.class)
        self[cols[0]] = model.class.to_s
        self[cols[1]] = model.ref
      else
        Sequel::Plugins::RefLinker.die_missing_poly_columns self.class
      end
      @parent = model
    end

    # parent          -> read the parent (cached after first access)
    # parent(@model)  -> set the parent and return self (chainable)
    def parent obj = nil
      if obj
        self.parent = obj
        return self
      end

      @parent ||=
      if key = self[:parent_key]
        klass, ref = key.split('/', 2)
        klass.constantize.find(ref)
      elsif cols = Sequel::Plugins::RefLinker.poly_pair_columns(self.class)
        if type = self[cols[0]]
          type.constantize.find(self[cols[1]])
        else
          raise ArgumentError, '%s parent not set.' % self.class
        end
      else
        Sequel::Plugins::RefLinker.die_missing_poly_columns self.class
      end
    end

    # True if the host model declares any polymorphic-parent columns.
    def parent?
      !!(db_schema[:parent_key] || db_schema[:parent_model] || db_schema[:parent_type])
    end
  end

  # ------------------------------------------------------------------
  # DatasetMethods (kept minimal; `for` lives in dataset_methods.rb
  # and routes here so it works on every Sequel model, plugged or not)
  # ------------------------------------------------------------------

  module DatasetMethods
  end
end

# Compatibility aliases so existing `plugin :lux_links` and
# `plugin :parent_model` calls in consumer apps keep working.
Sequel::Plugins.const_set(:LuxLinks,   Sequel::Plugins::RefLinker) unless defined?(Sequel::Plugins::LuxLinks)
Sequel::Plugins.const_set(:ParentModel, Sequel::Plugins::RefLinker) unless defined?(Sequel::Plugins::ParentModel)
