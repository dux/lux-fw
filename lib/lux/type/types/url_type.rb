require 'uri'

class Lux::Type::UrlType < Lux::Type
  error :en, :url_not_starting_error, 'URL is not starting with http or https'
  error :en, :url_invalid_error, 'URL is not valid'

  def coerce
    error_for(:url_not_starting_error) unless value =~ /^https?:\/\//

    # protocol-only strings like "https://" should not pass
    begin
      uri = URI.parse(value)
      error_for(:url_invalid_error) if uri.host.to_s.empty?
    rescue URI::InvalidURIError
      error_for(:url_invalid_error)
    end
  end

  def db_schema
    [:string, {}]
  end
end
