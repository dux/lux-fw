class Lux::Type::LabelType < Lux::Type
  def coerce
    value do |data|
      data
        .to_s
        .gsub(/\s+/, '-')
        .gsub(/[^\w\-]/, '')
        .gsub(/\-+/, '-')[0, 30]
        .downcase
    end

    error_for(:unallowed_characters_error) unless value =~ /^[\w\-]+$/
  end

  def db_schema
    [:string, {
      limit: 30
    }]
  end
end
