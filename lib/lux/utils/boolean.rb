# inspired by
# https://github.com/typesigs/safebool/blob/master/lib/safebool.rb

module Lux
module Utils
  module Boolean
    TRUE_VALUES  = %w[true yes on t y 1]
    FALSE_VALUES = %w[false no off f n 0]

    def self.parse data
      case data.to_s.downcase.strip
      when *TRUE_VALUES
        true
      when *FALSE_VALUES
        false
      else
        nil
      end
    end
  end
end
end
