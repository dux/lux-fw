# define create limit for objects in a database
# registred user can create max or x items in y time

# triggers autoloader error unless present
# ApplicationModel

# create max 30 objects per day
# create_limit 30, 1.day

# create max 30 object that have the same :org_id
# create_limit 30, :org_id

module Sequel::Plugins::LuxCreateLimit
  module ClassMethods
    def include _
      self.cattr :create_limit_data
      super
    end

    def create_limit number, in_time, name=nil
      cattr.create_limit_data = [number, in_time, name]
    end
  end

  module DatasetMethods
  end

  module InstanceMethods
    def validate
      super

      # return if Lux.env.cli?
      return unless defined?(User)

      # return if object exists
      return if self[:id]

      return unless db_schema[:created_by] || db_schema[:created_by_ref]

      if data = cattr.create_limit_data
        unless ::User.try(:current)
          raise Lux::Error.unauthorized('You need to log in to save')
        end

        max_count, sec_or_field, name = *data

        if sec_or_field.is_a?(Symbol)
          current_count = self.class.my.xwhere(sec_or_field => self[sec_or_field]).count
        else
          sec_or_field = sec_or_field.to_i
          current_count = self.class.my.xwhere("created_at > (now() - interval '#{sec_or_field} seconds')").count
        end

        if !Lux.env.test? && current_count >= max_count
          time   = data[1].class == AS::Duration ? data[1].parts[0].to_a.reverse.join(' ') : "#{data[1].to_i/60} minutes"
          name ||= (self.class.display_name.pluralize rescue self.class.to_s.tableize.humanize).downcase
          errors.add(:base, "You are allowed to create max of #{max_count} #{name} in #{time} (Spam protection).")
        end
      end
    end
  end
end

# Sequel::Model.plugin :lux_create_limit
