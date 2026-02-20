module Sequel::Plugins::LuxBeforeSave
  module InstanceMethods
    def validate
      return unless defined?(User)

      # timestamps
      self[:created_at] = Time.now.utc if new? && respond_to?(:created_at)
      self[:updated_at] = Time.now.utc if respond_to?(:updated_at)

      # updater audit (prefer new naming, fall back to old)
      ref = default_current_user_ref
      if ref
        self[:updater_ref]    = ref if respond_to?(:updater_ref)
        self[:updated_by_ref] = ref if respond_to?(:updated_by_ref)
        self[:updated_by]     = ref if respond_to?(:updated_by)
      end

      if new?
        Lux.cache.delete "#{self.class}/#{self[:ref]}" if self[:ref]

        if ref
          self[:creator_ref]     ||= ref if respond_to?(:creator_ref)
          self[:created_by_ref]  ||= ref if respond_to?(:created_by_ref)
          self[:created_by]      ||= ref if respond_to?(:created_by)
        end
      end

      super
    end

    def before_destroy
      Lux.cache.delete cache_key
      super
    end

    def destroy
      if respond_to?(:is_deleted)
        opts = { is_deleted: true }
        opts[:deleted_at]     = Time.now         if respond_to?(:deleted_at)
        opts[:deleted_by_ref] = User.current.ref if respond_to?(:deleted_by_ref) && User.current
        opts[:deleted_by]     = User.current.ref if respond_to?(:deleted_by) && User.current
        self.this.update opts
        true
      else
        super
      end
    end

    # returns current user ref for audit columns
    def default_current_user_ref
      if User.current
        User.current.ref
      else
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
