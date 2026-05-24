require 'test_helper'

describe 'new types' do
  describe 'phone' do
    it 'converts parens and dashes to spaces' do
      _(Lux.type(:phone, '+385 (91) 123-4567')).must_equal '+385 91 123 4567'
    end

    it 'accepts clean numbers' do
      _(Lux.type(:phone, '0911234567')).must_equal '0911234567'
    end

    it 'normalizes formatting' do
      _(Lux.type(:phone, '(01) 4567-890')).must_equal '01 4567 890'
    end

    it 'rejects too few digits' do
      _{ Lux.type(:phone, '123') }.must_raise TypeError
    end

    it 'rejects letters' do
      _{ Lux.type(:phone, 'call me') }.must_raise TypeError
    end
  end

  describe 'uuid' do
    it 'downcases and validates' do
      uuid = 'A1B2C3D4-E5F6-7890-ABCD-EF1234567890'
      _(Lux.type(:uuid, uuid)).must_equal uuid.downcase
    end

    it 'rejects bad format' do
      _{ Lux.type(:uuid, 'not-a-uuid') }.must_raise TypeError
    end

    it 'rejects too short' do
      _{ Lux.type(:uuid, '12345678-1234-1234-1234') }.must_raise TypeError
    end
  end

  describe 'slug' do
    it 'converts spaces and special chars' do
      _(Lux.type(:slug, 'Hello World!')).must_equal 'hello-world'
    end

    it 'collapses multiple dashes' do
      _(Lux.type(:slug, 'foo---bar')).must_equal 'foo-bar'
    end

    it 'strips leading and trailing dashes' do
      _(Lux.type(:slug, '-foo-bar-')).must_equal 'foo-bar'
    end

    it 'accepts clean slugs' do
      _(Lux.type(:slug, 'my-post')).must_equal 'my-post'
    end

    it 'respects max length' do
      assert Lux.type(:slug, 'a' * 300, max: 10).length <= 10
    end
  end
end
