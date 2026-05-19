# you should not use this filed for currency calculations
# use integer and covert in code
# Example: use cents and divide by 100 for $

require_relative './float_type'

class Lux::Type::CurrencyType < Lux::Type::FloatType

  def coerce
    value { |data| data.to_f.round(2) }

    error_for(:min_value_error, opts[:min], value) if opts[:min] && value < opts[:min]
    error_for(:max_value_error, opts[:max], value) if opts[:max] && value > opts[:max]
  end

  def db_schema
    [:decimal, {
      precision: 8,
      scale:     2
    }]
  end

end
