require 'spec_helper'

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
    expect(error).to be_nil
    expect(value).to eq('GB29NWBK60161331926819')
  end

  it 'should accept valid Croatian IBAN' do
    value, error = validate('HR1210010051863000160')
    expect(error).to be_nil
    expect(value).to eq('HR1210010051863000160')
  end

  it 'should accept valid German IBAN' do
    value, error = validate('DE89370400440532013000')
    expect(error).to be_nil
  end

  it 'should strip spaces and upcase' do
    value, error = validate('  gb29 nwbk 6016 1331 9268 19  ')
    expect(error).to be_nil
    expect(value).to eq('GB29NWBK60161331926819')
  end

  it 'should reject invalid checksum' do
    _value, error = validate('GB00NWBK60161331926819')
    expect(error).to include('IBAN')
  end

  it 'should reject too short input' do
    _value, error = validate('GB29')
    expect(error).to include('IBAN')
  end

  it 'should reject special characters' do
    _value, error = validate('GB29-NWBK-6016-1331')
    expect(error).to include('IBAN')
  end

  it 'should have correct db_schema' do
    expect(Lux::Type::IbanType.db_schema).to eq([:string, { limit: 34 }])
  end
end
