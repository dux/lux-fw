# ref-based model associations
#
# ref :user         -> belongs_to via user_ref column
# ref :users        -> has_many via user_refs array or reverse lookup
# Task.where_ref(@board) -> dataset scoped to parent

module Sequel::Plugins::LuxLinks
  module DatasetMethods
    # Task.where_ref(@board)
    def where_ref object
      if object
        f = "#{object.class.to_s.underscore}_ref".to_sym
        if model.db_schema[f]
          where(f => object.ref)
        elsif model.db_schema[:parent_key]
          key = '%s/%s' % [object.class, object.ref]
          where(parent_key: key)
        elsif model.db_schema[:parent_ref]
          where(
            parent_type: object.class.to_s,
            parent_ref: object.ref
          )
        else
          raise "Link field not found for #{model} -> #{object.class}"
        end
      else
        self
      end
    end
  end

  module ClassMethods
    def where_ref(model)
      dataset.where_ref(model)
    end

    # ref :user         -> singular, belongs_to via user_ref
    # ref :users        -> plural, has_many via user_refs[] or reverse lookup
    # ref :user, class: 'OrgUser' -> custom class
    # ref :user, field: 'owner_ref' -> custom field
    def ref name = :_nil, opts = {}
      opts = opts.to_hwia :class, :field, :cache

      if name == :_nil
        return ('%s_ref' % self.to_s.underscore).to_sym
      end

      name = name.to_s
      klass = opts[:class] ? opts[:class].to_s : name.to_s.singularize.classify
      field = (opts[:field] || "#{name}_ref").to_s

      if name == name.singularize
        # ref :user (user_ref)
        field = db_schema[field.to_sym] ? field : :parent_ref
        class_eval <<-STR, __FILE__, __LINE__ + 1
          def #{name}
            #{field}.present? ? #{klass}.find(#{field}) : nil
          end

          def #{name}= object
            self[:#{name}_ref] = object.ref
          end
        STR
      else
        field = "#{name.to_s.singularize}_refs".to_sym

        if db_schema[field.to_sym]
          # ref :users (user_refs [])
          class_eval <<-STR, __FILE__, __LINE__ + 1
            def #{name}
              #{field}.or([]).map { #{klass}.find(_1) }
            end
          STR
        else
          host = klass.constantize
          action_field = opts[:field] || "#{self.to_s.underscore}_ref".to_sym
          action =
          if host.db_schema[action_field]
            "#{klass}.default.where(#{action_field}: ref)"
          else
            key = host.db_schema[:parent_key] ? :parent_key : :parent_ref
            "#{klass}.default.where(#{key}: key)"
          end
          class_eval <<-STR, __FILE__, __LINE__ + 1
            def #{name}
              #{action}
            end
          STR
        end
      end
    end
  end
end

# Sequel::Model.plugin :lux_links
