require 'spec_helper'

describe 'new types' do
  context 'phone' do
    it 'converts parens and dashes to spaces' do
      expect(Lux.type(:phone, '+385 (91) 123-4567')).to eq('+385 91 123 4567')
    end

    it 'accepts clean numbers' do
      expect(Lux.type(:phone, '0911234567')).to eq('0911234567')
    end

    it 'normalizes formatting' do
      expect(Lux.type(:phone, '(01) 4567-890')).to eq('01 4567 890')
    end

    it 'rejects too few digits' do
      expect { Lux.type(:phone, '123') }.to raise_error TypeError
    end

    it 'rejects letters' do
      expect { Lux.type(:phone, 'call me') }.to raise_error TypeError
    end
  end

  context 'uuid' do
    it 'downcases and validates' do
      uuid = 'A1B2C3D4-E5F6-7890-ABCD-EF1234567890'
      expect(Lux.type(:uuid, uuid)).to eq(uuid.downcase)
    end

    it 'rejects bad format' do
      expect { Lux.type(:uuid, 'not-a-uuid') }.to raise_error TypeError
    end

    it 'rejects too short' do
      expect { Lux.type(:uuid, '12345678-1234-1234-1234') }.to raise_error TypeError
    end
  end

  context 'slug' do
    it 'converts spaces and special chars' do
      expect(Lux.type(:slug, 'Hello World!')).to eq('hello-world')
    end

    it 'collapses multiple dashes' do
      expect(Lux.type(:slug, 'foo---bar')).to eq('foo-bar')
    end

    it 'strips leading and trailing dashes' do
      expect(Lux.type(:slug, '-foo-bar-')).to eq('foo-bar')
    end

    it 'accepts clean slugs' do
      expect(Lux.type(:slug, 'my-post')).to eq('my-post')
    end

    it 'respects max length' do
      expect(Lux.type(:slug, 'a' * 300, max: 10).length).to be <= 10
    end
  end
end
