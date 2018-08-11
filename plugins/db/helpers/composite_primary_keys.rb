# define composite key and check before save
# class OrgUser < ApplicationModel
#   primary_keys :org_id, :user_id
# end

module Sequel::Plugins::PrimaryKeys
  module ClassMethods
    def primary_keys(*args)
      unless args[0]
        return respond_to?(:_primary_keys) ? _primary_keys : [:id]
      end

      define_singleton_method(:_primary_keys) { args }
    end
  end

  module InstanceMethods
    def before_save
      klass = self.class

      if klass.respond_to?(:_primary_keys)
        check = klass._primary_keys.inject(klass.dataset) do |record, field|
          record = record.where(field =>send(field))
        end

        check = check.xwhere('id<>?', id) if self[:id]

        raise StandardError, 'Record allredy exists (primary_keys check)' if check.first
      end

      super
    end
  end
end

Sequel::Model.plugin :primary_keys
