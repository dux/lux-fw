require 'spec_helper'

describe 'GeoExtract' do
  context 'point type' do
    it 'converts plain lat,lon' do
      expect(Lux.type(:point, '45.815,15.982')).to eq('SRID=4326;POINT(15.982 45.815)')
    end

    it 'converts Google Maps link' do
      url = 'https://www.google.com/maps/place/Zagreb/@45.815,15.982,12z'
      expect(Lux.type(:point, url)).to eq('SRID=4326;POINT(15.982 45.815)')
    end

    it 'converts OpenStreetMap link' do
      url = 'https://www.openstreetmap.org/#map=15/45.815/15.982'
      expect(Lux.type(:point, url)).to eq('SRID=4326;POINT(15.982 45.815)')
    end

    it 'converts Apple Maps link' do
      url = 'https://maps.apple.com/?ll=45.815,15.982'
      expect(Lux.type(:point, url)).to eq('SRID=4326;POINT(15.982 45.815)')
    end

    it 'converts Waze link' do
      url = 'https://www.waze.com/ul?ll=45.815,15.982'
      expect(Lux.type(:point, url)).to eq('SRID=4326;POINT(15.982 45.815)')
    end

    it 'converts Bing Maps cp link' do
      url = 'https://www.bing.com/maps?cp=45.815~15.982&lvl=12'
      expect(Lux.type(:point, url)).to eq('SRID=4326;POINT(15.982 45.815)')
    end

    it 'preserves existing SRID format' do
      srid = 'SRID=4326;POINT(15.982 45.815)'
      expect(Lux.type(:point, srid)).to eq(srid)
    end
  end

  context 'simple_point type' do
    it 'converts plain lat,lon to float array' do
      expect(Lux.type(:simple_point, '45.815,15.982')).to eq([45.815, 15.982])
    end

    it 'converts Google Maps link' do
      url = 'https://www.google.com/maps/place/Zagreb/@45.815,15.982,12z'
      expect(Lux.type(:simple_point, url)).to eq([45.815, 15.982])
    end

    it 'converts OpenStreetMap link' do
      url = 'https://www.openstreetmap.org/#map=15/45.815/15.982'
      expect(Lux.type(:simple_point, url)).to eq([45.815, 15.982])
    end

    it 'converts Apple Maps link' do
      url = 'https://maps.apple.com/?ll=45.815,15.982'
      expect(Lux.type(:simple_point, url)).to eq([45.815, 15.982])
    end

    it 'converts Waze link' do
      url = 'https://www.waze.com/ul?ll=45.815,15.982'
      expect(Lux.type(:simple_point, url)).to eq([45.815, 15.982])
    end

    it 'converts Bing Maps link' do
      url = 'https://www.bing.com/maps?cp=45.815~15.982&lvl=12'
      expect(Lux.type(:simple_point, url)).to eq([45.815, 15.982])
    end
  end

  context 'negative coordinates' do
    it 'handles negative lat/lon' do
      expect(Lux.type(:simple_point, '-33.868,-151.209')).to eq([-33.868, -151.209])
    end

    it 'handles negative in Google Maps' do
      url = 'https://www.google.com/maps/@-33.868,151.209,12z'
      expect(Lux.type(:simple_point, url)).to eq([-33.868, 151.209])
    end
  end
end
