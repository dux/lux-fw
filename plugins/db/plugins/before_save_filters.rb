module Sequel::Plugins::LuxBeforeSave
  module InstanceMethods
    def validate
      # timestamps
      self[:created_at] = Time.now.utc if new? && respond_to?(:created_at)
      self[:updated_at] = Time.now.utc if respond_to?(:updated_at)

      if defined?(User)
        # updater audit
        ref = default_current_user_ref
        if ref
          self[:updater_ref] = ref if respond_to?(:updater_ref)
        end

        if new?
          if ref
            self[:creator_ref] ||= ref if respond_to?(:creator_ref)
          end
        end
      end

      super
    end

    def after_save
      Lux.cache.delete("#{self.class}/#{self[:ref]}") if self[:ref]
      super
    end

    def before_destroy
      Lux.cache.delete("#{self.class}/#{self[:ref]}") if self[:ref]
      super
    end

    def destroy
      if respond_to?(:is_deleted)
        opts = { is_deleted: true }
        opts[:deleted_at] = Time.now if respond_to?(:deleted_at)

        if (cur = User.current)
          opts[:deleted_by_ref] = cur.ref if respond_to?(:deleted_by_ref)
          opts[:deleted_by]     = cur.ref if respond_to?(:deleted_by)
        end

        self.this.update opts
        true
      else
        super
      end
    end

    # returns current user ref for audit columns
    def default_current_user_ref
      User.current&.ref
    end
  end
end

# Sequel::Model.plugin :lux_before_save

