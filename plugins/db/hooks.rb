# https://sequel.jeremyevans.net/rdoc/files/doc/model_hooks_rdoc.html

module Sequel::Plugins::LuxHooks
  HOOK_METHODS = {}

  module InstanceMethods
    def before_update_exec k, m
      hash = HOOK_METHODS.dig(self.class, k, m) || {}
      hash.values.each do |proc|
        instance_exec m, k, &proc
      end
    end

    def before_create
      @is_new = true
      before_update_exec :b, :c unless self.id
      super
    end

    def after_create
      before_update_exec :a, :c
      super
    end

    def before_update
      # rr HOOK_METHODS[self.class]
      before_update_exec :b, :u
      super
    end

    def after_update
      before_update_exec :a, :u
      super
    end

    def before_destroy
      before_update_exec :b, :d
      super
    end

    def after_destroy
      before_update_exec :a, :d
      super
    end
  end

  module ClassMethods
    [
      :validate,
      :before_create,
      :after_create,
      :before_update,
      :after_update,
      :before_destroy,
      :after_destroy
    ].each do |el|
      eval %[
        def #{el} &block
          define_method :#{el} do
            if :#{el} != :validate && caller[0].include?('gems/sequel')
              raise "#{el} called directly, you need to call via proxy. Example: before(:cu) { ... }"
            end

            instance_exec &block
            super()
          end
        end
      ]
    end

    def before_and_after_define kind, what, &block
      src = caller[1].split('/').last.split(':in').first
      HOOK_METHODS[self] ||= {}
      HOOK_METHODS[self][kind] ||= {}
      what.to_s.split('').each do |m|
        pointer = HOOK_METHODS[self][kind][m.to_sym] ||= {}
        pointer[src] = block
      end
    end

    # before create, update and destroy
    # before :cud do
    #   ...
    # end
    def before what, &block
      before_and_after_define :b, what, &block
    end

    def after what, &block
      before_and_after_define :a, what, &block
    end
  end
end

# Sequel::Model.plugin :lux_hooks
