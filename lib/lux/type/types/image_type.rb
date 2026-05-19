class Lux::Type::ImageType < Lux::Type
  FORMATS ||= %w[jpg jpeg gif png svg webp]

  error :en, :image_not_starting_error, 'URL is not starting with http'
  error :en, :image_not_image_format, 'URL is not ending with %s' % FORMATS.join(', ')

  opts :strict, 'Force image to have known extension (%s)' % FORMATS.join(', ')

  def coerce
    error_for(:image_not_starting_error) unless value =~ /^https?:\/\/./

    if opts[:strict]
      # strip query string and fragment before checking extension
      path = value.split('?').first.split('#').first
      ext = path.split('.').last.downcase
      error_for(:image_not_image_format) unless FORMATS.include?(ext)
    end
  end

  def db_schema
    [:string]
  end
end
