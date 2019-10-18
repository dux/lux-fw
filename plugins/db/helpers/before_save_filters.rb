module Sequel::Plugins::LuxBeforeSave
  module InstanceMethods
    def before_save
      return unless defined?(User)

      # timestamps
      self[:created_at] = Time.now.utc if !self[:id] && respond_to?(:created_at)
      self[:updated_at] = Time.now.utc if respond_to?(:updated_at)

      # return error if user needed and not defined
      if !User.current && (respond_to?(:created_by) || respond_to?(:updated_by))
        errors.add(:base, 'You have to be registered to save data')
        return
      end

      # add timestamps
      self[:created_by] = User.current.id if respond_to?(:created_by) && !id
      self[:updated_by] = User.current.id if respond_to?(:updated_by)

      # delete cache key if defined
      Lux.cache.delete(cache_key)

      super
    end

    def before_destroy
      Lux.cache.delete(cache_key)

      super
    end
  end
end

Sequel::Model.plugin :lux_before_save
