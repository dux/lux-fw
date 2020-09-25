# call after_change to execute every time object changes
# (ideal for clearing caches)

module Sequel::Plugins::LuxAfterChange
  module InstanceMethods
    def after_change
    end

    def after_save
      after_change
      super
    end

    def after_destroy
      after_change
      super
    end
  end
end

Sequel::Model.plugin :lux_after_change