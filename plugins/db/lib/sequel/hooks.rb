# https://sequel.jeremyevans.net/rdoc/files/doc/model_hooks_rdoc.html

module Sequel::Plugins::LuxHooks
  HOOK_METHODS ||= {}

  module InstanceMethods
    def save(opts = Sequel::OPTS)
      @_lux_skip_filters = opts[:validate] == false
      super
    ensure
      @_lux_skip_filters = false
    end

    # hooks declared on any ancestor (ApplicationModel.before ...) fire too,
    # parents first. A :v error is left to Sequel so valid? returns false.
    def before_update_exec k, m
      return if @_lux_skip_filters
      self.class.ancestors.reverse_each do |klass|
        HOOK_METHODS.dig(klass, k, m)&.each_value { |pr| instance_exec m, k, &pr }
      end
      raise Sequel::ValidationFailed.new(errors) if k == :b && m != :v && errors.any?
    end

    def validate
      before_update_exec :b, :v
      super
    end

    def before_create
      before_update_exec :b, :c
      super
    end

    def after_create
      before_update_exec :a, :c
      super
    end

    def before_update
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
    # Sequel's own hook macros would silently be replaced; fail at declaration
    [:before_create, :after_create, :before_update, :after_update, :before_destroy, :after_destroy].each do |hook_name|
      define_method(hook_name) { |&| raise ArgumentError, "#{hook_name} { } is not supported, use before/after(:cud) { ... }" }
    end

    def validate(&block) = before(:v, &block)

    # key: identifies the hook (re-declaring a key replaces it); defaults to
    # the block's source location
    def before_and_after_define kind, what, key: nil, &block
      key ||= block.source_location&.join(':') || 'unknown'
      HOOK_METHODS[self] ||= {}
      HOOK_METHODS[self][kind] ||= {}
      what.to_s.each_char { |m| (HOOK_METHODS[self][kind][m.to_sym] ||= {})[key] = block }
    end

    # before create, update and destroy
    # before :cud do
    #   ...
    # end
    def before(what, key: nil, &block) = before_and_after_define(:b, what, key: key, &block)
    def after(what, key: nil, &block)  = before_and_after_define(:a, what, key: key, &block)
  end
end

# Sequel::Model.plugin :lux_hooks
