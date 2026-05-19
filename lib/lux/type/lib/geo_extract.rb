# Shared coordinate extraction from map URLs and plain lat,lon strings.
# Returns [lat, lon] as strings, or nil if no match.

module Lux
  class Type
    module GeoExtract
      def extract_coords data
        data = data.to_s.strip

        coords = extract_from_url(data) || extract_from_string(data)
        return nil unless coords

        coords.map { |c| c.to_s.strip }
      end

      private

      def extract_from_url data
        return nil unless data.include?('://')

        # Google Maps: /@45.815,15.982,... or ?q=45.815,15.982
        if data.include?('/@')
          parts = data.split('/@', 2).last.split(',')
          return [parts[0], parts[1]] if parts.length >= 2
        end

        if data =~ /google.*[?&]q=([-\d.]+),([-\d.]+)/
          return [$1, $2]
        end

        # OpenStreetMap: /#map=15/45.815/15.982
        if data =~ /openstreetmap.*#map=\d+\/([-\d.]+)\/([-\d.]+)/
          return [$1, $2]
        end

        # OpenStreetMap: ?mlat=45.815&mlon=15.982
        if data =~ /openstreetmap.*[?&]mlat=([-\d.]+).*[?&]mlon=([-\d.]+)/
          return [$1, $2]
        end

        # Apple Maps: ?ll=45.815,15.982
        if data =~ /maps\.apple\.com.*[?&]ll=([-\d.]+),([-\d.]+)/
          return [$1, $2]
        end

        # Waze: ?ll=45.815,15.982
        if data =~ /waze\.com.*[?&]ll=([-\d.]+),([-\d.]+)/
          return [$1, $2]
        end

        # Bing Maps: ?cp=45.815~15.982
        if data =~ /bing\.com.*[?&]cp=([-\d.]+)~([-\d.]+)/
          return [$1, $2]
        end

        # Bing Maps: /point.45.815_15.982
        if data =~ /bing\.com.*point\.([-\d.]+)_([-\d.]+)/
          return [$1, $2]
        end

        nil
      end

      def extract_from_string data
        return nil if data.include?('://') || data.include?('POINT')

        if data.include?(',')
          parts = data.split(/\s*,\s*/)
          return [parts[0], parts[1]] if parts.length >= 2
        end

        nil
      end
    end
  end
end
