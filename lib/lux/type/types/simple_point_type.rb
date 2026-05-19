# Same as point, but we keep data as a float array [lat, lon]

class Lux::Type::SimplePointType < Lux::Type
  include Lux::Type::GeoExtract

  def coerce
    # already coerced (e.g. Sequel re-validates on save)
    if value.respond_to?(:to_a) && !value.is_a?(String)
      value { value.to_a.map(&:to_f) }
      return
    end

    coords = extract_coords(value)

    if coords
      value { coords.map(&:to_f) }
    else
      error_for(:unallowed_characters_error)
    end
  end

  # get returns the plain float array
  def get
    return super if value.nil?
    coerce
    value
  end

  # db_value wraps with Sequel.pg_array for proper DB storage
  def db_value
    result = get
    return result unless result.is_a?(Array)
    defined?(Sequel) && Sequel.respond_to?(:pg_array) ? Sequel.pg_array(result, :float) : result
  end

  def input_value
    value.to_a.map { |c| c.to_f.to_s }.join(', ')
  end
  alias :to_s :input_value

  def db_schema
    [:float, { array: true }]
  end
end
