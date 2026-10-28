require 'test_helper'

describe Lux::Ref::Base do
  describe 'the format contract' do
    it 'leaves generate to the subclass' do
      _(-> { Lux::Ref::Base.new('x').generate }).must_raise NotImplementedError
    end

    it 'leaves valid? to the subclass' do
      _(-> { Lux::Ref::Base.new('x').valid? }).must_raise NotImplementedError
    end
  end

  describe '#value' do
    it 'is stored raw, uncoerced' do
      _(Lux::Ref::Base.new(42).value).must_equal 42
    end

    it 'is nil by default' do
      _(Lux::Ref::Base.new.value).must_be_nil
    end
  end

  describe 'as a path element' do
    it 'reads as ref and carries the id as value' do
      ref = Lux::Ref::Base.new('abc123')
      _(ref).must_equal 'ref'
      _(ref.value).must_equal 'abc123'
    end

    it 'joins into a path as ref' do
      _(['boards', Lux::Ref::Base.new('abc123')].join('/')).must_equal 'boards/ref'
    end

    it 'is frozen' do
      _(Lux::Ref::Base.new('abc123')).must_be :frozen?
    end
  end

  describe '#inspect' do
    it 'names the format and the value' do
      _(Lux::Ref::Short.new('abc').inspect).must_equal '#<Short "abc">'
    end
  end
end

describe Lux::Ref::Short do
  describe '#generate' do
    it 'returns a new instance of the same format' do
      _(Lux::Ref::Short.new.generate).must_be_kind_of Lux::Ref::Short
    end

    it 'mints a value that validates' do
      _(Lux::Ref::Short.new.generate.valid?).must_equal true
    end

    it 'honours a length, which then fails the canonical check' do
      generated = Lux::Ref::Short.new.generate(8)
      _(generated.value.length).must_equal 8
      _(generated.valid?).must_equal false
    end

    it 'does not repeat itself' do
      _(Lux::Ref::Short.new.generate.value).wont_equal Lux::Ref::Short.new.generate.value
    end
  end

  describe '#valid?' do
    it 'accepts the canonical 16-char lowercase form' do
      _(Lux::Ref::Short.new('k3p9x2mq7wd1nb84').valid?).must_equal true
    end

    it 'rejects a short value' do
      _(Lux::Ref::Short.new('abc').valid?).must_equal false
    end

    it 'rejects uppercase' do
      _(Lux::Ref::Short.new('K3P9X2MQ7WD1NB84').valid?).must_equal false
    end

    it 'rejects punctuation' do
      _(Lux::Ref::Short.new('k3p9x2mq7wd1nb8-').valid?).must_equal false
    end

    it 'returns false rather than raising on nil' do
      _(Lux::Ref::Short.new.valid?).must_equal false
    end

    it 'returns false rather than raising on a non-String' do
      _(Lux::Ref::Short.new(1234).valid?).must_equal false
    end
  end
end

describe Lux::Ref do
  it 'generates a value the format accepts' do
    _(Lux::Ref.is?(Lux::Ref.generate)).must_equal true
  end

  it 'generates a String, not an instance' do
    _(Lux::Ref.generate).must_be_kind_of ::String
  end

  it 'takes a length' do
    _(Lux::Ref.generate(8).length).must_equal 8
  end

  it 'is? returns a boolean, and does not raise on nil' do
    _(Lux::Ref.is?(nil)).must_equal false
  end
end

###

describe 'Lux::Ref registry' do
  def with_format value
    was = Lux.config[:ref_format]
    Lux.config[:ref_format] = value
    yield
  ensure
    Lux.config[:ref_format] = was
  end

  describe '.resolve' do
    it 'resolves a registered symbol' do
      klass, attrs = Lux::Ref.resolve(:string)
      _(klass).must_equal Lux::Ref::Short
      _(attrs).must_equal({})
    end

    it 'resolves a string name too' do
      _(Lux::Ref.resolve('uuid7').first).must_equal Lux::Ref::Uuid7
    end

    it 'resolves a { name => attrs } hash, merging over registered defaults' do
      klass, attrs = Lux::Ref.resolve(string: { upcase: true, length: 26 })
      _(klass).must_equal Lux::Ref::Short
      _(attrs).must_equal({ upcase: true, length: 26 })
    end

    it 'symbolizes attr keys, so a config.yaml hash works' do
      _(Lux::Ref.resolve('string' => { 'length' => 8 }).last).must_equal({ length: 8 })
    end

    it 'accepts a Base subclass directly' do
      _(Lux::Ref.resolve(Lux::Ref::Uuid7)).must_equal [Lux::Ref::Uuid7, {}]
    end

    it 'raises on an unknown name, naming what is registered' do
      err = _{ Lux::Ref.resolve(:nope) }.must_raise ArgumentError
      _(err.message).must_include 'string'
    end

    it 'raises on a class that is not a Base' do
      _{ Lux::Ref.resolve(::String) }.must_raise ArgumentError
    end
  end

  describe '.default' do
    it 'follows Lux.config.ref_format' do
      with_format(:uuid7) { _(Lux::Ref.default.first).must_equal Lux::Ref::Uuid7 }
    end

    it 'falls back to :string when unset' do
      with_format(nil) { _(Lux::Ref.default.first).must_equal Lux::Ref::Short }
    end

    it 'is read per call, not memoized' do
      with_format(:uuid7) { _(Lux::Ref.build).must_be_kind_of Lux::Ref::Uuid7 }
      with_format(:string) { _(Lux::Ref.build).must_be_kind_of Lux::Ref::Short }
    end
  end

  describe 'attributes reach the instance' do
    it 'parameterises Short rather than needing a subclass' do
      upper = Lux::Ref::Short.new(nil, upcase: true, length: 26).generate
      _(upper.value.length).must_equal 26
      _(upper.value).must_match(/\A[A-Z0-9]{26}\z/)
      _(upper.valid?).must_equal true
    end

    it 'carries attrs through #generate, so the new value validates' do
      _(Lux::Ref::Short.new(nil, upcase: true).generate.valid?).must_equal true
    end

    it 'a plain Short rejects what an upcase one accepts' do
      value = Lux::Ref::Short.new(nil, upcase: true).generate.value
      _(Lux::Ref::Short.new(value).valid?).must_equal false
    end

    it 'the :ref type stores an upcase family ref upcased' do
      with_format(string: { upcase: true }) do
        upper = Lux::Ref::Short.new(nil, upcase: true).generate.value
        _(Lux::Type::RefType.new(upper.downcase).get).must_equal upper
      end
    end

    it 'the :ref type still rejects uppercase for the plain family' do
      with_format(:string) do
        _{ Lux::Type::RefType.new('K3P9X2MQ7WD1NB84').get }.must_raise TypeError
      end
    end
  end

  # the whole point: one declaration, every consumer follows
  describe 'Lux.config.ref_format drives every consumer' do
    it 'moves Lux::Ref, the :ref column type and nav.map_path together' do
      with_format :uuid7 do
        generated = Lux::Ref.generate
        _(Lux::Ref::Uuid7.new(generated).valid?).must_equal true
        _(Lux::Ref.is?(generated)).must_equal true

        _(Lux::Type::RefType.new(generated).value).must_equal generated
        _(Lux::Type::RefType.new(nil).db_schema).must_equal [:string, { limit: 36 }]

        Lux::Context.new "http://example.com/boards/#{generated}"
        Lux.ctx.nav.map_path
        _(Lux.ctx.nav.ref).must_equal generated
        _(Lux.ctx.nav.path).must_equal %w[boards ref]
      end
    end

    it 'a 16-char ref is not an id when the app is on uuid7' do
      with_format :uuid7 do
        Lux::Context.new 'http://example.com/boards/k3p9x2mq7wd1nb84'
        Lux.ctx.nav.map_path
        _(Lux.ctx.nav.ref).must_be_nil
      end
    end

    it 'the string default still emits the varchar the ref column always had' do
      with_format(:string) { _(Lux::Type::RefType.new(nil).db_schema).must_equal [:string, { limit: 20 }] }
    end
  end
end

describe Lux::Ref::Uuid7 do
  it 'generates a valid uuid7' do
    _(Lux::Ref::Uuid7.new.generate.valid?).must_equal true
  end

  it 'stamps version 7 and the RFC variant' do
    _(Lux::Ref::Uuid7.new.generate.value).must_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
  end

  it 'sorts by creation time - the reason to pick it' do
    early = Lux::Ref::Uuid7.new.generate(1_700_000_000_000).value
    late  = Lux::Ref::Uuid7.new.generate(1_800_000_000_000).value
    _(early < late).must_equal true
  end

  it 'does not repeat itself within the same millisecond' do
    at = 1_700_000_000_000
    _(Lux::Ref::Uuid7.new.generate(at).value).wont_equal Lux::Ref::Uuid7.new.generate(at).value
  end

  it 'rejects a v4 uuid' do
    _(Lux::Ref::Uuid7.new('f47ac10b-58cc-4372-a567-0e02b2c3d479').valid?).must_equal false
  end

  it 'rejects a 16-char ref' do
    _(Lux::Ref::Uuid7.new('k3p9x2mq7wd1nb84').valid?).must_equal false
  end

  it 'returns false rather than raising on nil' do
    _(Lux::Ref::Uuid7.new.valid?).must_equal false
  end

  it 'is 36 wide in the db' do
    _(Lux::Ref::Uuid7.new.db_limit).must_equal 36
  end
end

describe 'Lux::Ref::Base#extract' do
  it 'returns a valid segment as the id' do
    _(Lux::Ref::Short.new.extract('k3p9x2mq7wd1nb84')).must_equal 'k3p9x2mq7wd1nb84'
  end

  it 'is nil for a segment the format rejects' do
    _(Lux::Ref::Short.new.extract('short')).must_be_nil
  end

  it 'normalises through the format' do
    _(Lux::Ref::Short.new(nil, upcase: true).extract('k' * 16)).must_equal 'K' * 16
  end
end

describe Lux::Ref::Slug do
  it 'takes the id off the end of a slug' do
    ref = Lux::Ref.generate
    _(Lux::Ref::Slug.new.extract("dino-reic-#{ref}")).must_equal ref
  end

  it 'still takes a bare id' do
    ref = Lux::Ref.generate
    _(Lux::Ref::Slug.new.extract(ref)).must_equal ref
  end

  it 'is nil for a slug without an id' do
    _(Lux::Ref::Slug.new.extract('dino-reic')).must_be_nil
  end

  it 'drives nav.map_path when it is the app format' do
    was = Lux.config[:ref_format]
    Lux.config[:ref_format] = :slug
    ref = Lux::Ref.generate

    Lux::Context.new "http://example.com/terapeut/dino-reic-#{ref}"
    Lux.ctx.nav.map_path
    _(Lux.ctx.nav.ref).must_equal ref
    _(Lux.ctx.nav.path).must_equal %w[terapeut ref]
  ensure
    Lux.config[:ref_format] = was
  end
end
