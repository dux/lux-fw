module Sequel::Plugins::LuxBeforeSave
  module InstanceMethods
    def validate
      return unless defined?(User)

      # timestamps
      self[:created_at] = Time.now.utc if !self.id && respond_to?(:created_at)
      self[:updated_at] = Time.now.utc if respond_to?(:updated_at)
      self[:updated_by] = default_current_user if respond_to?(:updated_by)
      self[:updated_by_ref] = default_current_user if respond_to?(:updated_by_ref)

      if self.id
        Lux.cache.delete "#{self.class}/#{id}"
      else
        self[:created_by] ||= default_current_user if respond_to?(:created_by)
        self[:created_by_ref] ||= default_current_user if respond_to?(:created_by_ref)
      end

      super
    end

    def before_destroy
      Lux.cache.delete cache_key
      super
    end

    def destroy
      if respond_to?(:is_deleted)
        opts = {is_deleted: true}
        opts[:deleted_at] = Time.now if respond_to?(:deleted_at)
        opts[:deleted_by] = User.current.id if respond_to?(:deleted_by)
        opts[:deleted_by_ref] = User.current.ref if respond_to?(:deleted_by_ref)
        self.this.update opts
        true
      else
        super
      end
    end

    # overload to return guest user, when needed
    def default_current_user
      if User.current
        User.current.id
      else
        error 'You have to be registered to save data'
        nil
      end
    end
  end

  module DatasetMethods
    def not_deleted
      model.db_schema[:is_deleted] ? xwhere("#{model.to_s.tableize}.is_deleted = false") : self
    end

    def deleted
      model.db_schema[:is_deleted] ? xwhere("#{model.to_s.tableize}.is_deleted = true") : self
    end

    def activated
      model.db_schema[:is_active] ? xwhere("#{model.to_s.tableize}.is_active = true") : self
    end

    def deactivated
      model.db_schema[:is_active] ? xwhere("#{model.to_s.tableize}.is_active = false") : self
    end
  end
end

# Sequel::Model.plugin :lux_before_save
