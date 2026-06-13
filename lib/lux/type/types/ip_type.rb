require 'resolv'

class Lux::Type::IpType < Lux::Type
  error :en, :invalid_ip, 'is not a valid IPv4 or IPv6 address'

  def coerce
    value { |data| data.to_s.strip }

    error_for(:invalid_ip) unless value =~ Resolv::AddressRegex
  end

  def db_schema
    [:string, { limit: 45 }]
  end
end
