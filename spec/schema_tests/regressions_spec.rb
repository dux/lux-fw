require 'test_helper'

describe 'Lux::Schema / Lux::Type regressions' do
  it 'keys schemas without singularizing (Address)' do
    schema = Lux.schema(:address) { street String }
    assert_equal 'Address', Lux::Schema.key('Address')
    assert_equal 'User', Lux::Schema.key(:user)
    assert_equal schema, Lux.schema?('Address')
  end

  it 'accepts Boolean as a type constant' do
    schema = Lux.schema { active Boolean }
    assert_equal :boolean, schema.rules[:active][:type]
    data = { active: 'true' }
    schema.validate data
    assert_equal true, data[:active]
  end

  it 'reads an indexed hash as array values' do
    schema = Lux.schema { tags [String] }
    data = { tags: { '0' => 'a', '1' => 'b' } }
    schema.validate data
    assert_equal %w[a b], data[:tags]
  end

  it 'checks allow: on array elements' do
    schema = Lux.schema { tags [String], allow: %w[a b] }
    assert_match(/not allowed/, schema.validate({ tags: ['x'] })[:tags])
  end

  it 'rejects a bare scheme as domain with a TypeError' do
    assert_raises(TypeError) { Lux.type(:domain, 'http://') }
  end

  it 'rejects non-numeric integers' do
    assert_raises(TypeError) { Lux.type(:integer, 'abc') }
    assert_raises(TypeError) { Lux.type(:integer, [1]) }
    assert_raises(TypeError) { Lux.type(:integer, true) }
  end

  it 'compares date min: given as a Date' do
    assert_equal Date.new(2020, 1, 2), Lux.type(:date, '2020-01-02', min: Date.new(1900, 1, 1))
    assert_raises(TypeError) { Lux.type(:date, '1800-01-02', min: Date.new(1900, 1, 1)) }
  end

  it 'falls back to :en for keys missing in a partial locale table' do
    Lux::Type.error :xx, :min_length_error, 'prekratko'
    Lux.ctx.locale = 'xx'
    err = assert_raises(TypeError) { Lux.type(:email, 'nomonkey') }
    assert_equal 'is missing @', err.message
    err = assert_raises(TypeError) { Lux.type(:email, 'a') }
    assert_equal 'prekratko', err.message
  ensure
    Lux.ctx.locale = nil
  end
end

class AccessorProbe
  def initialize(h) = @h = h
  def [](k) = @h[k]
end

describe 'Lux::Schema::Accessor#validate(field)' do
  before do
    Lux.schema(:accessor_probe) do
      email :email, req: true
      color String, allow: %w[red blue]
    end
  end

  it 'applies required and allowed like Schema#validate' do
    acc = Lux::Schema::Accessor.new(AccessorProbe.new({ color: 'green' }))
    assert_raises(TypeError) { acc.validate(:email) }
    msg = nil
    acc.validate(:color) { |e| msg = e }
    assert_match(/not allowed/, msg)
    assert_nil Lux::Schema::Accessor.new(AccessorProbe.new({ color: 'red' })).validate(:color)
  end
end

describe 'Lux::Type opts check and currency overflow' do
  it 'checks opts in Lux.type, not on every Type.new' do
    assert_raises(ArgumentError) { Lux.type(:integer, 1, bogus: 1) }
    assert_equal 1, Lux::Type::IntegerType.new(1, { bogus: 1 }).get
  end

  it 'rejects currency above the decimal(8,2) column range' do
    assert_equal 999_999.99, Lux.type(:currency, '999999.99')
    assert_raises(TypeError) { Lux.type(:currency, 1_000_000) }
    assert_equal 2_000_000.0, Lux.type(:currency, 2_000_000, max: 5_000_000)
  end
end
