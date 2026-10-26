# Composite natural key, enforced by a unique index (race-free, no SELECT per save).
# class OrgUser < ApplicationModel
#   primary_keys :org_ref, :user_ref
# end
#
# `lux db:am` adds the unique index on the keys (AutoMigrate#table). A save
# that hits it raises Sequel::Plugins::PrimaryKeys::DuplicateRecord.

module Sequel::Plugins::PrimaryKeys
  # subclass, so existing `rescue Sequel::UniqueConstraintViolation` still catches it
  class DuplicateRecord < Sequel::UniqueConstraintViolation; end

  module ClassMethods
    def primary_keys(*args)
      unless args[0]
        return respond_to?(:_primary_keys) ? _primary_keys : [:ref]
      end

      define_singleton_method(:_primary_keys) { args }
    end

    # the name Sequel's add_index / create_table `index` gives the key index
    def primary_keys_index_name
      "#{table_name}_#{_primary_keys.join('_')}_index"
    end
  end

  module InstanceMethods
    def save(*)
      super
    rescue Sequel::UniqueConstraintViolation => e
      klass = self.class
      raise unless klass.respond_to?(:_primary_keys) && e.message.include?(klass.primary_keys_index_name)

      raise DuplicateRecord, "#{klass} #{klass._primary_keys.join(' + ')} already exists"
    end
  end
end

# Sequel::Model.plugin :primary_keys
