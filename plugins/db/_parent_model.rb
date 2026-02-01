# You put in model
# * parent_key
# * or parent_type + parent_id/parent_ref
# @object.parent -> get parent
# @object.parent= model -> set parent
# Object.parent(@model) -> search Object

module Sequel::Plugins::ParentModel
  module DatasetMethods
    def where_parent object
      if model.db_schema[:parent_key]
        where(parent_key: object.key)
      else
        where(parent_type: object.class.to_s, parent_ref: object.ref)
      end
    end
  end

  module InstanceMethods
    # apply parent attributes
    def parent= model
      if db_schema[:parent_key]
        self[:parent_key] =
        if model.is_a?(String) && model.include?('/')
          key
        else
          '%s/%s' % [model.class, model.id]
        end
      else
        self[:parent_type] = model.class.to_s
        self[respond_to?(:parent_ref) ? :parent_ref : :parent_id] = model.id
      end

      @parent = model
    end

    # @board.parent -> @list
    def parent obj = nil
      if obj
        # OrgUser.new.parent(@org)
        self.parent = obj
        self
      else
        @parent ||=
        if key = self[:parent_key]
          key = key.split('/')
          key[0].constantize.find(key[1])
        elsif key = self[:parent_type]
          key.constantize.find(self[respond_to?(:parent_ref) ? :parent_ref : :parent_id])
        else
          raise ArgumentError, '%s parent key not found.' % self.class
        end
      end
    end

    # check if parent is present
    def parent?
      db_schema[:parent_key] || db_schema[:parent_type]
    end
  end

  # Favorite.for_parent(@cards) -> cards in favorites
  module ClassMethods
    def for_parent object
      if key = db_schema[:parent_key]
        where(parent_key: object.key)
      elsif db_schema[:parent_type]
        if db_schema[:parent_ref]
          where(parent_ref: object.ref, parent_type: object.class.to_s)
        else
          where(parent_id: object.id, parent_type: object.class.to_s)
        end
      else
        raise ArgumentError, 'parent key not found'
      end
    end
  end
end

# Sequel::Model.plugin :parent_model
