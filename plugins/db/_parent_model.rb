# Polymorphic parent support:
# * parent_key (single string "Class/ref" format)
# * parent_model + parent_ref (two columns)
#
# @object.parent -> get parent
# @object.parent= model -> set parent
# Object.for_parent(@model) -> search Object

module Sequel::Plugins::ParentModel
  module DatasetMethods
    def where_parent object
      if model.db_schema[:parent_key]
        where(parent_key: object.key)
      else
        where(parent_model: object.class.to_s, parent_ref: object.ref)
      end
    end
  end

  module InstanceMethods
    def parent= model
      if db_schema[:parent_key]
        self[:parent_key] = '%s/%s' % [model.class, model.ref]
      else
        self[:parent_model] = model.class.to_s
        self[:parent_ref] = model.ref
      end
      @parent = model
    end

    def parent obj = nil
      if obj
        self.parent = obj
        self
      else
        @parent ||=
        if key = self[:parent_key]
          key = key.split('/')
          key[0].constantize.find(key[1])
        elsif type = self[:parent_model]
          type.constantize.find(self[:parent_ref])
        else
          raise ArgumentError, '%s parent not set.' % self.class
        end
      end
    end

    def parent?
      !!(db_schema[:parent_key] || db_schema[:parent_model])
    end
  end

  module ClassMethods
    def for_parent object
      if db_schema[:parent_key]
        where(parent_key: object.key)
      else
        where(parent_model: object.class.to_s, parent_ref: object.ref)
      end
    end
  end
end

# Sequel::Model.plugin :parent_model
