require_relative '../lux/utils/json'

class Hash
  include Lux::Utils::Json
end

class Array
  include Lux::Utils::Json
end
