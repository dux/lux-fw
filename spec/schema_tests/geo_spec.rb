require 'test_helper'

describe 'GeoExtract' do
  describe 'point type' do
    it 'converts plain lat,lon' do
      _(Lux.type(:point, '45.815,15.982')).must_equal 'SRID=4326;POINT(15.982 45.815)'
    end

    it 'converts Google Maps link' do
      url = 'https://www.google.com/maps/place/Zagreb/@45.815,15.982,12z'
      _(Lux.type(:point, url)).must_equal 'SRID=4326;POINT(15.982 45.815)'
    end

    it 'converts OpenStreetMap link' do
      url = 'https://www.openstreetmap.org/#map=15/45.815/15.982'
      _(Lux.type(:point, url)).must_equal 'SRID=4326;POINT(15.982 45.815)'
    end

    it 'converts Apple Maps link' do
      url = 'https://maps.apple.com/?ll=45.815,15.982'
      _(Lux.type(:point, url)).must_equal 'SRID=4326;POINT(15.982 45.815)'
    end

    it 'converts Waze link' do
      url = 'https://www.waze.com/ul?ll=45.815,15.982'
      _(Lux.type(:point, url)).must_equal 'SRID=4326;POINT(15.982 45.815)'
    end

    it 'converts Bing Maps cp link' do
      url = 'https://www.bing.com/maps?cp=45.815~15.982&lvl=12'
      _(Lux.type(:point, url)).must_equal 'SRID=4326;POINT(15.982 45.815)'
    end

    it 'preserves existing SRID format' do
      srid = 'SRID=4326;POINT(15.982 45.815)'
      _(Lux.type(:point, srid)).must_equal srid
    end
  end

  describe 'simple_point type' do
    it 'converts plain lat,lon to float array' do
      _(Lux.type(:simple_point, '45.815,15.982')).must_equal [45.815, 15.982]
    end

    it 'converts Google Maps link' do
      url = 'https://www.google.com/maps/place/Zagreb/@45.815,15.982,12z'
      _(Lux.type(:simple_point, url)).must_equal [45.815, 15.982]
    end

    it 'converts OpenStreetMap link' do
      url = 'https://www.openstreetmap.org/#map=15/45.815/15.982'
      _(Lux.type(:simple_point, url)).must_equal [45.815, 15.982]
    end

    it 'converts Apple Maps link' do
      url = 'https://maps.apple.com/?ll=45.815,15.982'
      _(Lux.type(:simple_point, url)).must_equal [45.815, 15.982]
    end

    it 'converts Waze link' do
      url = 'https://www.waze.com/ul?ll=45.815,15.982'
      _(Lux.type(:simple_point, url)).must_equal [45.815, 15.982]
    end

    it 'converts Bing Maps link' do
      url = 'https://www.bing.com/maps?cp=45.815~15.982&lvl=12'
      _(Lux.type(:simple_point, url)).must_equal [45.815, 15.982]
    end
  end

  describe 'negative coordinates' do
    it 'handles negative lat/lon' do
      _(Lux.type(:simple_point, '-33.868,-151.209')).must_equal [-33.868, -151.209]
    end

    it 'handles negative in Google Maps' do
      url = 'https://www.google.com/maps/@-33.868,151.209,12z'
      _(Lux.type(:simple_point, url)).must_equal [-33.868, 151.209]
    end
  end
end
