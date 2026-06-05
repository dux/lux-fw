require 'spec_helper'

Lux.plugin Lux.fw_root.join('plugins/locale')

# table must exist before Sequel::Model() resolves the schema
DB.create_table?(:_translation_tests) do
  primary_key :id
  column :name_t, :jsonb
  column :desc_t, :jsonb
  String :code
end

class TranslationTestModel < Sequel::Model(DB[:_translation_tests])
  plugin :pg_translations
end

describe Sequel::Plugins::PgTranslations do
  before do
    Lux::Current.new('http://test-pg-translations')
    Lux.locale.instance_variable_set(:@default, nil)
    Lux.locale.instance_variable_set(:@available, nil)
    Lux.locale.default   = :en
    Lux.locale.available = %i[en hr de fr]
    Lux.current.locale   = 'en'
  end

  after do
    TranslationTestModel.dataset.delete
  end

  describe '.t_columns' do
    it 'detects columns ending with _t' do
      expect(TranslationTestModel.t_columns).to include(:name_t, :desc_t)
    end

    it 'excludes non _t columns' do
      expect(TranslationTestModel.t_columns).not_to include(:code)
      expect(TranslationTestModel.t_columns).not_to include(:id)
    end
  end

  describe 'localized getter' do
    let(:record) do
      TranslationTestModel.create(
        name_t: Sequel.pg_jsonb('en' => 'Hello', 'hr' => 'Bok'),
        desc_t: Sequel.pg_jsonb('en' => 'A description', 'hr' => 'Opis'),
        code: 'test'
      )
    end

    it 'returns value for current locale' do
      Lux.current.locale = 'en'
      expect(record.name).to eq('Hello')
    end

    it 'returns value for switched locale' do
      Lux.current.locale = 'hr'
      expect(record.name).to eq('Bok')
    end

    it 'falls back to default locale when current locale is missing' do
      Lux.current.locale = 'de'
      Lux.locale.default = :en
      expect(record.name).to eq('Hello')
    end

    it 'returns nil when translation data is nil' do
      obj = TranslationTestModel.create(name_t: nil)
      expect(obj.name).to be_nil
    end

    it 'returns nil when both locale and default are missing' do
      Lux.current.locale = 'de'
      Lux.locale.default = :fr
      expect(record.name).to be_nil
    end

    it 'falls back when current locale value is empty string' do
      obj = TranslationTestModel.create(
        name_t: Sequel.pg_jsonb('en' => '', 'hr' => 'Bok')
      )
      Lux.current.locale = 'en'
      Lux.locale.default = :hr
      expect(obj.name).to eq('Bok')
    end

    it 'works for multiple _t columns independently' do
      Lux.current.locale = 'hr'
      expect(record.name).to eq('Bok')
      expect(record.desc).to eq('Opis')
    end
  end

  describe 'raw _t accessor' do
    it 'returns the full jsonb hash' do
      record = TranslationTestModel.create(
        name_t: Sequel.pg_jsonb('en' => 'Hello', 'hr' => 'Bok')
      )
      expect(record.name_t['en']).to eq('Hello')
      expect(record.name_t['hr']).to eq('Bok')
    end
  end

  describe '#respond_to?' do
    let(:record) do
      TranslationTestModel.create(name_t: Sequel.pg_jsonb('en' => 'Hi'))
    end

    it 'returns true for translated accessors' do
      expect(record.respond_to?(:name)).to be(true)
      expect(record.respond_to?(:desc)).to be(true)
    end

    it 'returns false for non-existent translated accessors' do
      expect(record.respond_to?(:unknown)).to be(false)
    end
  end

  describe 'method_missing passthrough' do
    let(:record) do
      TranslationTestModel.create(name_t: Sequel.pg_jsonb('en' => 'Hi'), code: 'abc')
    end

    it 'raises NoMethodError for undefined methods' do
      expect { record.nonexistent_method }.to raise_error(NoMethodError)
    end

    it 'does not interfere with regular column access' do
      expect(record.code).to eq('abc')
    end
  end

  describe 'method caching' do
    let(:record) do
      TranslationTestModel.create(name_t: Sequel.pg_jsonb('en' => 'Hello', 'hr' => 'Bok'))
    end

    it 'defines a real method after first call' do
      record.name
      expect(TranslationTestModel.method_defined?(:name)).to be(true)
    end

    it 'still returns correct locale after method is cached' do
      Lux.current.locale = 'en'
      expect(record.name).to eq('Hello')

      Lux.current.locale = 'hr'
      expect(record.name).to eq('Bok')
    end
  end
end
