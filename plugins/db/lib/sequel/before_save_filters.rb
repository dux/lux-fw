module Sequel::Plugins::LuxBeforeSave
  module InstanceMethods
    def validate
      lux_stamp_audit
      super
    end

    # save! (validate: false) skips validate, so stamp here as well; idempotent
    def before_save
      lux_stamp_audit
      super
    end

    def lux_stamp_audit
      # timestamps
      self[:created_at] = Time.now.utc if new? && respond_to?(:created_at)
      self[:updated_at] = Time.now.utc if respond_to?(:updated_at)

      # audit fields are written once, at create; a later write cannot rewrite
      # them, however the update was constructed. A nil initial value is not a
      # written audit value: a save nested in an after_create hook runs before
      # dirty resets initial values, so they still hold the pre-insert nils.
      if !new?
        %i(created_at creator_ref).each do |col|
          next unless respond_to?(col) && column_changed?(col)
          old = initial_value(col)
          self[col] = old unless old.nil?
        end
      end

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
    end

    # clear before the after(:c/:u) hooks run (lux_hooks is plugged in first,
    # so this super chain reaches it later): a hook that re-reads the record
    # through find/take must see the saved row, not the pre-save cache entry
    def after_create
      lux_clear_find_cache
      super
    end

    def after_update
      lux_clear_find_cache
      super
    end

    def before_destroy
      lux_clear_find_cache
      super
    end

    # drop the find/take cache entry, global and request-local (the request
    # cache also keeps nil misses)
    def lux_clear_find_cache
      return unless self[:ref]
      key = "#{self.class}/#{self[:ref]}"
      Lux.cache.delete key
      Lux.ctx.var[:cache]&.delete key
    end

    def destroy
      if respond_to?(:is_deleted)
        opts = { is_deleted: true }
        opts[:deleted_at] = Time.now if respond_to?(:deleted_at)

        if defined?(User) && (cur = User.current)
          opts[:deleted_by_ref] = cur.ref if respond_to?(:deleted_by_ref)
          opts[:deleted_by]     = cur.ref if respond_to?(:deleted_by)
        end

        # soft delete is still a logical delete: run the destroy callbacks
        # (cache clear + before/after :d hooks) around the flag update.
        before_destroy
        self.this.update opts
        after_destroy
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

