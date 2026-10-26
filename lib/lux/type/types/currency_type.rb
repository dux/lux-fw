# you should not use this filed for currency calculations
# use integer and covert in code
# Example: use cents and divide by 100 for $

require_relative './float_type'

class Lux::Type::CurrencyType < Lux::Type::FloatType

  # column is decimal(8,2): anything above MAX_VALUE would overflow on save (PG 500)
  MAX_VALUE ||= 999_999.99

  def coerce
    super
    @value = @value.round(2)
    error_for(:max_value_error, MAX_VALUE, @value) if !opts[:max] && @value > MAX_VALUE
  end

  def db_schema
    [:decimal, {
      precision: 8,
      scale:     2
    }]
  end

end
