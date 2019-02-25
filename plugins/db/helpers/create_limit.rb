# define create limit for objects in a database
# registred user can create max or x items in y time
ApplicationModel.class_eval do

  class_attribute :create_limit_data

  def self.create_limit number, in_time
    create_limit_data [number, in_time.to_i]
  end

end

module Sequel::Plugins::LuxCreateLimit
  module ClassMethods
  end

  module DatasetMethods
  end

  module InstanceMethods
    def validate
      return unless ::User.current

      name = self.class.to_s.tableize.humanize.downcase

      if data = self.class.create_limit_data
        count, seconds = *data

        cnt = self.class.my.xwhere("created_at > (now() - interval '#{seconds} seconds')").count

        errors.add(:base, "You are allowed to create max of #{count} #{name} in #{(seconds/60).to_i} minutes (Spam protection).") if cnt >= count
      end

      super
    end
  end
end

Sequel::Model.plugin :lux_create_limit