# Same as point, but we keep data as a float array [lat, lon]

class Lux::Type::SimplePointType < Lux::Type
  include Lux::Type::GeoExtract

  def coerce
    return if value.nil?

    coords = normalize_pair(value)

    if coords
      value { coords.map { |c| c.to_f } }
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
    Array(value).map { |c| c.to_f.to_s }.join(', ')
  end
  alias :to_s :input_value

  def db_schema
    [:float, { array: true }]
  end

  private

  # Accepts:
  #   [lat, lon] / ["lat","lon"]
  #   { "0" => lat, "1" => lon }  (form/JSON object indices — common from JS)
  #   { lat:, lon: } / { latitude:, longitude: }
  #   "lat,lon" / map URLs via GeoExtract
  #   Sequel pg_array (to_a → floats)
  def normalize_pair(v)
    case v
    when String
      extract_coords(v)
    when Hash
      normalize_hash(v)
    when Array
      normalize_array(v)
    else
      if v.respond_to?(:to_a) && !v.is_a?(String)
        arr = v.to_a
        return normalize_pair(arr) unless arr.equal?(v)
      end
      nil
    end
  end

  def normalize_hash(h)
    # indexed object from JSON/form: { "0" => "37.8", "1" => "-119.5" }
    if h.key?('0') || h.key?(0) || h.key?(:'0')
      [h['0'] || h[0] || h[:'0'], h['1'] || h[1] || h[:'1']]
    elsif (lat = h['lat'] || h[:lat] || h['latitude'] || h[:latitude])
      lon = h['lon'] || h[:lon] || h['lng'] || h[:lng] || h['longitude'] || h[:longitude]
      [lat, lon]
    elsif h.values.length >= 2
      h.values.first(2)
    end
  end

  def normalize_array(a)
    return nil if a.empty?

    # flat [lat, lon]
    if a.length >= 2 && !a[0].is_a?(Array) && !a[0].is_a?(Hash)
      return a.first(2)
    end

    # Hash#to_a shape: [["0", lat], ["1", lon]]
    if a[0].is_a?(Array) && a[0].length == 2 && a.length >= 2
      return [a[0][1], a[1][1]]
    end

    nil
  end
end
