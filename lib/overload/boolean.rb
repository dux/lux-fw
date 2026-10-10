require_relative '../lux/utils/boolean'

class TrueClass
  include Lux::Utils::Boolean
end

class FalseClass
  include Lux::Utils::Boolean
end

# Top-level alias so apps can write `value.is_a?(Boolean)` instead of the
# longer `Lux::Utils::Boolean`. Works because both TrueClass and FalseClass
# `include Lux::Utils::Boolean` above. A different Boolean already loaded
# would silently change every `is_a?(Boolean)` check, so refuse to boot.
if defined?(::Boolean) && ::Boolean != Lux::Utils::Boolean
  raise NameError, "Boolean is already defined (#{::Boolean}); lux aliases it to Lux::Utils::Boolean"
end
Boolean ||= Lux::Utils::Boolean
