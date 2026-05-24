module Lux
  module Test
    # Lux::Test::Case is just a reference to Minitest::Spec - the helpers
    # below are mixed straight into Minitest::Spec so every `describe ... do`
    # block (including ones that don't explicitly inherit) gets them.
    #
    # Provides:
    #   factory              - Lux::Test::Factory (model factory)
    #   capture_log { }      - Lux::Test::Capture
    #   with_transaction { } - Lux::Test::DB
    #   assert_status, assert_json_includes, assert_body_includes, assert_redirect
    #
    # HTTP responses come from Lux.render.<verb>; those return a Lux::Response
    # which has #status, #body, #json, #headers, #redirect_to, #ok?.
    #
    # Hooks: resets Factory fetch/sequence caches and Lux.current between
    # tests so order can't leak state.
    Case = ::Minitest::Spec
  end
end

class Minitest::Spec
  # Minitest::Spec 6.0 implements `before` as `define_method(:setup)`,
  # which OVERWRITES on each call instead of chaining. A second
  # `before { ... }` at the same describe level silently replaces the
  # first. Patch so all `before` blocks at the same level run in
  # registration order, and `super()` still chains to the parent
  # describe's setup (so outer describes still propagate).
  def self.before _type = nil, &block
    @lux_before_blocks ||= []
    @lux_before_blocks << block
    blocks = @lux_before_blocks
    define_method(:setup) do
      super()
      blocks.each { |b| instance_eval(&b) }
    end
  end

  # Same issue with `after`. Last-wins is even more dangerous for
  # teardown than for setup.
  def self.after _type = nil, &block
    @lux_after_blocks ||= []
    @lux_after_blocks << block
    blocks = @lux_after_blocks
    define_method(:teardown) do
      blocks.reverse_each { |b| instance_eval(&b) }
      super()
    end
  end
end

class Minitest::Spec
  include Lux::Test::Capture
  include Lux::Test::DB
  include Lux::Test::Assertions

  def factory
    Lux::Test::Factory
  end

  before do
    Lux::Test::Factory.reset
    Thread.current[:lux] = nil
  end

  after do
    Thread.current[:lux] = nil
  end
end
