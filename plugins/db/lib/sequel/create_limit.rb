# Spam protection: a user may create at most N records of a model in a time
# window, or N per value of a field.
#
#   create_limit 30, 1.day        # 30 per user per day
#   create_limit 30, :org_ref     # 30 per user with the same org_ref
#
# It guards client writes only, so it runs inside an HTTP API call
# (Lux::Api.current) and nowhere else - router pages, jobs, seeds and the
# console create freely. Admins (User#is_admin?) are never limited. Inside an
# API call the check can be switched off for a block, on every model:
#
#   Spot.without_create_limit { SpotImporter.new(data).import_all }

module Sequel::Plugins::LuxCreateLimit
  def self.apply(model)
    model.cattr :create_limit_data
  end

  def self.skipped?
    Thread.current[:lux_create_limit_skip] == true
  end

  module ClassMethods
    def create_limit number, in_time, name=nil
      cattr.create_limit_data = [number, in_time, name]
    end

    # Per thread and nestable, restored even when the block raises
    def without_create_limit
      prev = Thread.current[:lux_create_limit_skip]
      Thread.current[:lux_create_limit_skip] = true
      yield
    ensure
      Thread.current[:lux_create_limit_skip] = prev
    end
  end

  module InstanceMethods
    def validate
      super

      return unless new?
      return unless data = cattr.create_limit_data
      return unless db_schema[:creator_ref]
      return unless defined?(Lux::Api) && Lux::Api.current
      return if Sequel::Plugins::LuxCreateLimit.skipped?
      return unless defined?(User)

      user = ::User.try(:current)
      raise Lux.error.unauthorized('You need to log in to save') unless user
      return if user.respond_to?(:is_admin?) && user.is_admin?

      max_count, sec_or_field, _name = *data

      mine = self.class.where(creator_ref: user.ref)

      current_count =
        if sec_or_field.is_a?(Symbol)
          mine.where(sec_or_field => self[sec_or_field]).count
        else
          mine.where(Sequel.lit("created_at > (now() - interval '#{sec_or_field.to_i} seconds')")).count
        end

      if !Lux.env.test? && current_count >= max_count
        errors.add(:base, create_limit_message(*data))
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
