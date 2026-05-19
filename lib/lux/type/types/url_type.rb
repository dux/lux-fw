class Lux::Type::UrlType < Lux::Type
  error :en, :url_not_starting_error, 'URL is not starting with http or https'

  def coerce
    error_for(:url_not_starting_error) unless value =~ /^https?:\/\//
  end

  def db_schema
    [:string, {}]
  end
end
