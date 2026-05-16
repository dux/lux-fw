# define composite key and check before save
# class OrgUser < ApplicationModel
#   primary_keys :org_ref, :user_ref
# end

module Sequel::Plugins::PrimaryKeys
  module ClassMethods
    def primary_keys(*args)
      unless args[0]
        return respond_to?(:_primary_keys) ? _primary_keys : [:ref]
      end

      define_singleton_method(:_primary_keys) { args }
    end
  end

  module InstanceMethods
    def before_save
      klass = self.class

      if klass.respond_to?(:_primary_keys)
        check = klass._primary_keys.inject(klass.dataset) do |record, field|
          record = record.where(field => send(field))
        end

        check = check.xwhere('ref<>?', ref) if ref

        if check.first
          raise StandardError, "Record already exists"
        end
      end

      super
    end
  end
end

# Sequel::Model.plugin :primary_keys
