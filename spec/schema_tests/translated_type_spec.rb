require 'test_helper'

# Unit coverage for Lux::Type::TranslatedType. The stored-value prune path
# (a single changed locale drops its siblings) is driven by passing `stored:`
# straight to the type - the same value Schema#coerce_value feeds from a
# persisted record's initial_value. Full save-path integration lives with the
# db plugin specs.

describe Lux::Type::TranslatedType do
  def coerce(value, stored: nil, **opts)
    Lux::Type::TranslatedType.new(value, opts, stored: stored).db_value
  end

  describe 'input shapes' do
    it 'keeps a bare string under the given default locale' do
      _(coerce('Hello', default_locale: 'en')).must_equal({ 'en' => 'Hello' })
    end

    it 'passes a hash through, stringifying locale keys' do
      _(coerce({ en: 'A', hr: 'B' })).must_equal({ 'en' => 'A', 'hr' => 'B' })
    end

    it 'parses a JSON string' do
      _(coerce('{"en":"A","hr":"B"}')).must_equal({ 'en' => 'A', 'hr' => 'B' })
    end

    it 'treats an empty string as no translations' do
      _(coerce('   ')).must_equal({})
    end

    it 'drops blank translations' do
      _(coerce({ 'en' => 'A', 'hr' => '  ' })).must_equal({ 'en' => 'A' })
    end
  end

  describe 'prune against stored value' do
    it 'stores multiple locales as given, ignoring stored' do
      got = coerce({ 'en' => 'A', 'hr' => 'B' }, stored: { 'en' => 'OLD', 'de' => 'X' })
      _(got).must_equal({ 'en' => 'A', 'hr' => 'B' })
    end

    it 'keeps stored siblings when the single locale is unchanged' do
      got = coerce({ 'en' => 'A' }, stored: { 'en' => 'A', 'hr' => 'B' })
      _(got).must_equal({ 'en' => 'A', 'hr' => 'B' })
    end

    it 'drops stored siblings when the single locale changed' do
      got = coerce({ 'en' => 'A2' }, stored: { 'en' => 'A', 'hr' => 'B' })
      _(got).must_equal({ 'en' => 'A2' })
    end

    it 'drops siblings for a changed bare string too' do
      got = coerce('A2', stored: { 'en' => 'A', 'hr' => 'B' }, default_locale: 'en')
      _(got).must_equal({ 'en' => 'A2' })
    end

    it 'treats a new record (no stored value) as a fresh single locale' do
      _(coerce('Hi', stored: nil, default_locale: 'hr')).must_equal({ 'hr' => 'Hi' })
    end
  end

  describe 'current locale' do
    before { Lux::Current.new('http://test') }

    it 'keys a bare string under Lux.current.locale when set' do
      Lux.current.locale = 'de'
      _(coerce('Hallo')).must_equal({ 'de' => 'Hallo' })
    end
  end

  describe 'db_schema' do
    it 'is a non-null jsonb column defaulting to {}' do
      _(Lux::Type::TranslatedType.new(nil).db_schema).must_equal([:jsonb, { null: false, default: '{}' }])
    end
  end
end
