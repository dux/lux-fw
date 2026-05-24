require 'test_helper'

describe Lux::Type::IbanType do
  def validate(input)
    schema = Lux.schema do
      iban :iban
    end
    data = { iban: input }
    errors = schema.validate(data)
    [data[:iban], errors[:iban]]
  end

  it 'should accept valid IBAN' do
    value, error = validate('GB29 NWBK 6016 1331 9268 19')
    _(error).must_be_nil
    _(value).must_equal 'GB29NWBK60161331926819'
  end

  it 'should accept valid Croatian IBAN' do
    value, error = validate('HR1210010051863000160')
    _(error).must_be_nil
    _(value).must_equal 'HR1210010051863000160'
  end

  it 'should accept valid German IBAN' do
    _value, error = validate('DE89370400440532013000')
    _(error).must_be_nil
  end

  it 'should strip spaces and upcase' do
    value, error = validate('  gb29 nwbk 6016 1331 9268 19  ')
    _(error).must_be_nil
    _(value).must_equal 'GB29NWBK60161331926819'
  end

  it 'should reject invalid checksum' do
    _value, error = validate('GB00NWBK60161331926819')
    _(error).must_include 'IBAN'
  end

  it 'should reject too short input' do
    _value, error = validate('GB29')
    _(error).must_include 'IBAN'
  end

  it 'should reject special characters' do
    _value, error = validate('GB29-NWBK-6016-1331')
    _(error).must_include 'IBAN'
  end

  it 'should have correct db_schema' do
    _(Lux::Type::IbanType.db_schema).must_equal [:string, { limit: 34 }]
  end
end
