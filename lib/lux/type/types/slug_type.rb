class Lux::Type::SlugType < Lux::Type
  opts :max, 'Maximum slug length'

  error :en, :invalid_slug, 'contains invalid characters'

  def coerce
    max = opts[:max] || 255

    value do |data|
      data
        .to_s
        .downcase
        .gsub(/[^\w\-]/, '-')
        .gsub(/\-+/, '-')
        .sub(/^\-/, '')
        .sub(/\-$/, '')[0, max]
    end

    error_for(:invalid_slug) unless value =~ /^[\w][\w\-]*[\w]$|^[\w]$/
  end

  def db_schema
    [:string, { limit: opts[:max] || 255 }]
  end
end
