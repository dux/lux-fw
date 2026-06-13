class Lux::Type::DomainType < Lux::Type
  opts :max, 'Maximum domain length'

  error :en, :domain_invalid_error, 'is not a valid domain name'

  # RFC-1123 host: dot-separated labels, each 1-63 chars, alnum with internal
  # dashes. Allows single-label hosts (localhost) and any TLD length.
  LABEL ||= /[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?/
  RE    ||= /\A#{LABEL}(?:\.#{LABEL})*\z/

  def coerce
    value { |v| normalize(v) }
    check_min_max_length(opts[:max] || 253)
    error_for(:domain_invalid_error) unless value =~ RE
  end

  def db_schema
    [:string, { limit: opts[:max] || 253 }]
  end

  private

  # accept a bare host, or peel the host out of a pasted URL / host:port
  def normalize v
    v = v.to_s.strip.downcase
    v = v.split('://', 2).last   # drop scheme
    v = v.split('/', 2).first    # drop path
    v = v.split(':', 2).first    # drop port
    v.to_s
  end
end
