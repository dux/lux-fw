# define create limit for objects in a database
# registred user can create max or x items in y time

# triggers autoloader error unless present
# ApplicationModel

# create max 30 objects per day
# create_limit 30, 1.day

# create max 30 object that have the same :org_ref
# create_limit 30, :org_ref

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

  module InstanceMethods
    def validate
      super

      # return if Lux.env.cli?
      return unless defined?(User)

      # return if object exists
      return unless new?

      return unless db_schema[:creator_ref]

      if data = cattr.create_limit_data
        unless ::User.try(:current)
          raise Lux.error.unauthorized('You need to log in to save')
        end

        # Dev only: seeding runs as a real user, so a reseed spends that user's
        # whole quota and locks them out of their own site for a day. Production
        # keeps the limit for everybody - raise it per model if it is too tight.
        return if Lux.env.dev? && ::User.current.respond_to?(:is_admin?) && ::User.current.is_admin?

        max_count, sec_or_field, name = *data

        mine = self.class.where(creator_ref: ::User.current.ref)

        if sec_or_field.is_a?(Symbol)
          current_count = mine.where(sec_or_field => self[sec_or_field]).count
        else
          current_count = mine.where(Sequel.lit("created_at > (now() - interval '#{sec_or_field.to_i} seconds')")).count
        end

        if !Lux.env.test? && current_count >= max_count
          errors.add(:base, create_limit_message(*data))
        end
      end
    end

    def create_limit_message max_count, sec_or_field, name = nil
      span =
        case sec_or_field
        when Symbol                  then "per #{sec_or_field.to_s.humanize.downcase}"
        when AS::Duration            then "in #{sec_or_field.parts[0].reverse.join(' ')}"
        else                              "in #{sec_or_field.to_i / 60} minutes"
        end

      name ||= (self.class.display_name.pluralize rescue self.class.to_s.tableize.humanize).downcase
      "You are allowed to create max of #{max_count} #{name} #{span} (Spam protection)."
    end
  end
end

# Sequel::Model.plugin :lux_create_limit
