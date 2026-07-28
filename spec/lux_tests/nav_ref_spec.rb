require 'test_helper'

NavBase      ||= Lux::Application::Nav::Base
NavRefString ||= Lux::Application::Nav::RefString

describe Lux::Application::Nav::Base do
  describe 'the format contract' do
    it 'leaves generate to the subclass' do
      _(-> { NavBase.new('x').generate }).must_raise NotImplementedError
    end

    it 'leaves valid? to the subclass' do
      _(-> { NavBase.new('x').valid? }).must_raise NotImplementedError
    end
  end

  describe '#value' do
    it 'is stored raw, uncoerced' do
      _(NavBase.new(42).value).must_equal 42
    end

    it 'is nil by default' do
      _(NavBase.new.value).must_be_nil
    end
  end

  describe '#path_before' do
    it 'is nil unless given' do
      _(NavBase.new('x').path_before).must_be_nil
    end

    it 'holds the segment it was built with' do
      _(NavBase.new('x', path_before: 'boards').path_before).must_equal 'boards'
    end
  end

  describe '#to_s' do
    it 'renders the value, not a placeholder' do
      _(NavBase.new('abc123').to_s).must_equal 'abc123'
    end

    it 'joins into a path as the value' do
      _(['boards', NavBase.new('abc123')].join('/')).must_equal 'boards/abc123'
    end
  end

  describe '#inspect' do
    it 'names the format and the value' do
      _(NavRefString.new('abc').inspect).must_equal '#<RefString "abc">'
    end
  end

  describe '#==' do
    it 'compares values against another instance' do
      _(NavBase.new('a')).must_equal NavBase.new('a')
      _(NavBase.new('a')).wont_equal NavBase.new('b')
    end

    it 'compares as text against anything else' do
      _(NavBase.new('abc123') == 'abc123').must_equal true
      _(NavBase.new('abc123') == 'other').must_equal false
    end

    # String#== rejects a non-String outright, and NavBase deliberately does not
    # define to_str to force it otherwise. Keep the segment on the left.
    it 'is one-way against a String - the segment must be the receiver' do
      _('abc123' == NavBase.new('abc123')).must_equal false
    end
  end
end

describe Lux::Application::Nav::RefString do
  describe '#generate' do
    it 'returns a new instance of the same format' do
      _(NavRefString.new.generate).must_be_kind_of NavRefString
    end

    it 'mints a value that validates' do
      _(NavRefString.new.generate.valid?).must_equal true
    end

    it 'honours a length, which then fails the canonical check' do
      generated = NavRefString.new.generate(8)
      _(generated.value.length).must_equal 8
      _(generated.valid?).must_equal false
    end

    it 'does not repeat itself' do
      _(NavRefString.new.generate.value).wont_equal NavRefString.new.generate.value
    end
  end

  describe '#valid?' do
    it 'accepts the canonical 16-char lowercase form' do
      _(NavRefString.new('k3p9x2mq7wd1nb84').valid?).must_equal true
    end

    it 'rejects a short value' do
      _(NavRefString.new('abc').valid?).must_equal false
    end

    it 'rejects uppercase' do
      _(NavRefString.new('K3P9X2MQ7WD1NB84').valid?).must_equal false
    end

    it 'rejects punctuation' do
      _(NavRefString.new('k3p9x2mq7wd1nb8-').valid?).must_equal false
    end

    it 'returns false rather than raising on nil' do
      _(NavRefString.new.valid?).must_equal false
    end

    it 'returns false rather than raising on a non-String' do
      _(NavRefString.new(1234).valid?).must_equal false
    end
  end
end

describe Lux::Utils::Ref do
  it 'generates a value the format accepts' do
    _(Lux::Utils::Ref.is?(Lux::Utils::Ref.generate)).must_equal true
  end

  it 'generates a String, not an instance' do
    _(Lux::Utils::Ref.generate).must_be_kind_of ::String
  end

  it 'takes a length' do
    _(Lux::Utils::Ref.generate(8).length).must_equal 8
  end

  it 'is? returns a boolean, and does not raise on nil' do
    _(Lux::Utils::Ref.is?(nil)).must_equal false
  end
end

###

NavBaseClass ||= Lux::Application::Nav::Base
NavUuid7     ||= Lux::Application::Nav::RefUuid7

describe 'Lux::Application::Nav::Base registry' do
  def with_format value
    was = Lux.config[:ref_format]
    Lux.config[:ref_format] = value
    yield
  ensure
    Lux.config[:ref_format] = was
  end

  describe '.resolve' do
    it 'resolves a registered symbol' do
      klass, attrs = NavBaseClass.resolve(:string)
      _(klass).must_equal NavRefString
      _(attrs).must_equal({})
    end

    it 'resolves a string name too' do
      _(NavBaseClass.resolve('uuid7').first).must_equal NavUuid7
    end

    it 'resolves a { name => attrs } hash, merging over registered defaults' do
      klass, attrs = NavBaseClass.resolve(string: { upcase: true, length: 26 })
      _(klass).must_equal NavRefString
      _(attrs).must_equal({ upcase: true, length: 26 })
    end

    it 'symbolizes attr keys, so a config.yaml hash works' do
      _(NavBaseClass.resolve('string' => { 'length' => 8 }).last).must_equal({ length: 8 })
    end

    it 'accepts a Base subclass directly' do
      _(NavBaseClass.resolve(NavUuid7)).must_equal [NavUuid7, {}]
    end

    it 'raises on an unknown name, naming what is registered' do
      err = _{ NavBaseClass.resolve(:nope) }.must_raise ArgumentError
      _(err.message).must_include 'string'
    end

    it 'raises on a class that is not a Base' do
      _{ NavBaseClass.resolve(::String) }.must_raise ArgumentError
    end
  end

  describe '.default' do
    it 'follows Lux.config.ref_format' do
      with_format(:uuid7) { _(NavBaseClass.default.first).must_equal NavUuid7 }
    end

    it 'falls back to :string when unset' do
      with_format(nil) { _(NavBaseClass.default.first).must_equal NavRefString }
    end

    it 'is read per call, not memoized' do
      with_format(:uuid7) { _(NavBaseClass.build).must_be_kind_of NavUuid7 }
      with_format(:string) { _(NavBaseClass.build).must_be_kind_of NavRefString }
    end
  end

  describe 'attributes reach the instance' do
    it 'parameterises RefString rather than needing a subclass' do
      upper = NavRefString.new(nil, upcase: true, length: 26).generate
      _(upper.value.length).must_equal 26
      _(upper.value).must_match(/\A[A-Z0-9]{26}\z/)
      _(upper.valid?).must_equal true
    end

    it 'carries attrs through #generate, so the new value validates' do
      _(NavRefString.new(nil, upcase: true).generate.valid?).must_equal true
    end

    it 'a plain RefString rejects what an upcase one accepts' do
      value = NavRefString.new(nil, upcase: true).generate.value
      _(NavRefString.new(value).valid?).must_equal false
    end
  end

  # the whole point: one declaration, every consumer follows
  describe 'Lux.config.ref_format drives every consumer' do
    it 'moves Utils::Ref, the :ref column type and nav.map_path together' do
      with_format :uuid7 do
        generated = Lux::Utils::Ref.generate
        _(NavUuid7.new(generated).valid?).must_equal true
        _(Lux::Utils::Ref.is?(generated)).must_equal true

        _(Lux::Type::RefType.new(generated).value).must_equal generated
        _(Lux::Type::RefType.new(nil).db_schema).must_equal [:string, { limit: 36 }]

        Lux::Current.new "http://example.com/boards/#{generated}"
        Lux.current.nav.map_path
        _(Lux.current.nav.ref).must_equal generated
        _(Lux.current.nav.normalized_path).must_equal %w[boards ref]
      end
    end

    it 'a 16-char ref is not an id when the app is on uuid7' do
      with_format :uuid7 do
        Lux::Current.new 'http://example.com/boards/k3p9x2mq7wd1nb84'
        Lux.current.nav.map_path
        _(Lux.current.nav.ref).must_be_nil
      end
    end

    it 'the string default still emits the varchar the ref column always had' do
      with_format(:string) { _(Lux::Type::RefType.new(nil).db_schema).must_equal [:string, { limit: 20 }] }
    end
  end
end

describe Lux::Application::Nav::RefUuid7 do
  it 'generates a valid uuid7' do
    _(NavUuid7.new.generate.valid?).must_equal true
  end

  it 'stamps version 7 and the RFC variant' do
    _(NavUuid7.new.generate.value).must_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
  end

  it 'sorts by creation time - the reason to pick it' do
    early = NavUuid7.new.generate(1_700_000_000_000).value
    late  = NavUuid7.new.generate(1_800_000_000_000).value
    _(early < late).must_equal true
  end

  it 'does not repeat itself within the same millisecond' do
    at = 1_700_000_000_000
    _(NavUuid7.new.generate(at).value).wont_equal NavUuid7.new.generate(at).value
  end

  it 'rejects a v4 uuid' do
    _(NavUuid7.new('f47ac10b-58cc-4372-a567-0e02b2c3d479').valid?).must_equal false
  end

  it 'rejects a 16-char ref' do
    _(NavUuid7.new('k3p9x2mq7wd1nb84').valid?).must_equal false
  end

  it 'returns false rather than raising on nil' do
    _(NavUuid7.new.valid?).must_equal false
  end

  it 'is 36 wide in the db' do
    _(NavUuid7.new.db_limit).must_equal 36
  end
end
