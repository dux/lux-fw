require 'test_helper'

# --- DB bootstrap ---------------------------------------------------------
Object.send(:remove_const, :DB) if defined?(DB)
DB ||= Sequel.connect('postgres:///lux_fw_test')
DB.extension :pg_json
DB.loggers.clear

Lux::Plugin.load File.expand_path('..', __dir__)

# Fresh table; it must exist before Sequel::Model() resolves the schema.
DB.drop_table?(:_translation_tests)
DB.create_table(:_translation_tests) do
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
      _(TranslationTestModel.t_columns).must_include :name_t
      _(TranslationTestModel.t_columns).must_include :desc_t
    end

    it 'excludes non _t columns' do
      refute_includes TranslationTestModel.t_columns, :code
      refute_includes TranslationTestModel.t_columns, :id
    end
  end

  describe 'localized getter' do
    def record
      @record ||= TranslationTestModel.create(
        name_t: Sequel.pg_jsonb('en' => 'Hello', 'hr' => 'Bok'),
        desc_t: Sequel.pg_jsonb('en' => 'A description', 'hr' => 'Opis'),
        code: 'test'
      )
    end

    it 'returns value for current locale' do
      Lux.current.locale = 'en'
      _(record.name).must_equal 'Hello'
    end

    it 'returns value for switched locale' do
      Lux.current.locale = 'hr'
      _(record.name).must_equal 'Bok'
    end

    it 'falls back to default locale when current locale is missing' do
      Lux.current.locale = 'de'
      Lux.locale.default = :en
      _(record.name).must_equal 'Hello'
    end

    it 'returns nil when translation data is nil' do
      obj = TranslationTestModel.create(name_t: nil)
      _(obj.name).must_be_nil
    end

    it 'returns nil when both locale and default are missing' do
      Lux.current.locale = 'de'
      Lux.locale.default = :fr
      _(record.name).must_be_nil
    end

    it 'falls back when current locale value is empty string' do
      obj = TranslationTestModel.create(
        name_t: Sequel.pg_jsonb('en' => '', 'hr' => 'Bok')
      )
      Lux.current.locale = 'en'
      Lux.locale.default = :hr
      _(obj.name).must_equal 'Bok'
    end

    it 'works for multiple _t columns independently' do
      Lux.current.locale = 'hr'
      _(record.name).must_equal 'Bok'
      _(record.desc).must_equal 'Opis'
    end
  end

  describe 'raw _t accessor' do
    it 'returns the full jsonb hash' do
      record = TranslationTestModel.create(
        name_t: Sequel.pg_jsonb('en' => 'Hello', 'hr' => 'Bok')
      )
      _(record.name_t['en']).must_equal 'Hello'
      _(record.name_t['hr']).must_equal 'Bok'
    end
  end

  describe '#respond_to?' do
    def record
      @record ||= TranslationTestModel.create(name_t: Sequel.pg_jsonb('en' => 'Hi'))
    end

    it 'returns true for translated accessors' do
      _(record.respond_to?(:name)).must_equal true
      _(record.respond_to?(:desc)).must_equal true
    end

    it 'returns false for non-existent translated accessors' do
      _(record.respond_to?(:unknown)).must_equal false
    end
  end

  describe 'method_missing passthrough' do
    def record
      @record ||= TranslationTestModel.create(name_t: Sequel.pg_jsonb('en' => 'Hi'), code: 'abc')
    end

    it 'raises NoMethodError for undefined methods' do
      assert_raises(NoMethodError) { record.nonexistent_method }
    end

    it 'does not interfere with regular column access' do
      _(record.code).must_equal 'abc'
    end
  end

  describe 'method caching' do
    def record
      @record ||= TranslationTestModel.create(name_t: Sequel.pg_jsonb('en' => 'Hello', 'hr' => 'Bok'))
    end

    it 'defines a real method after first call' do
      record.name
      _(TranslationTestModel.method_defined?(:name)).must_equal true
    end

    it 'still returns correct locale after method is cached' do
      Lux.current.locale = 'en'
      _(record.name).must_equal 'Hello'

      Lux.current.locale = 'hr'
      _(record.name).must_equal 'Bok'
    end
  end
end
