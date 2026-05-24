# Lux::Test - test scaffolding for the lux suite (and lux apps).
#
# Loaded only from spec/spec_helper.rb, never from lux boot. Pulls in
# Minitest::Spec, the vendored Factory (was clean-mock), and the helper modules
# (Request, Capture, DB, TimeHelpers, Assertions). The single base class
# Lux::Test::Case wires them all together; specs inherit from it.
#
# See lib/lux/test/AGENTS.md for the rules AI must follow when writing
# specs against this layer.

require 'minitest'
require 'minitest/spec'

module Lux
  module Test
  end
end

require_relative './factory/factory'
require_relative './lib/assertions'
require_relative './lib/capture'
require_relative './lib/db'
require_relative './case'
