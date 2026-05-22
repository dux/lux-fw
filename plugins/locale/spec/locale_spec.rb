require 'spec_helper'
require 'fileutils'
require 'tmpdir'

Lux.plugin Lux.fw_root.join('plugins/locale')

describe Lux::Locale do
  let(:tmp) { Pathname.new(Dir.mktmpdir('lux-locale-')) }

  before do
    Lux::Current.new('http://test-locale')
    Lux.locale.instance_variable_set(:@default, nil)
    Lux.locale.instance_variable_set(:@available, nil)
    Lux.locale.instance_variable_set(:@dir, nil)
    Lux.locale.instance_variable_set(:@before_get, nil)
    Lux.locale.instance_variable_set(:@before_set, nil)
    Lux.locale.instance_variable_set(:@namespaces, nil)
    Lux.locale.instance_variable_set(:@store, nil)
    Lux.locale.reload!

    Lux.locale.dir       = tmp
    Lux.locale.default   = :en
    Lux.locale.available = %i[en de]

    File.write tmp.join('users.en.txt'), <<~TXT
      welcome: Hi %{name}
      profile.title: Profile
    TXT

    File.write tmp.join('users.de.txt'), <<~TXT
      welcome: Hallo %{name}
    TXT
  end

  after do
    FileUtils.remove_entry tmp if tmp.exist?
  end

  describe '#current' do
    it 'falls back to default when Lux.current.locale is unset' do
      expect(Lux.locale.current).to eq(:en)
    end

    it 'reads from Lux.current.locale' do
      Lux.current.locale = 'de'
      expect(Lux.locale.current).to eq(:de)
    end

    it 'raises Unknown for a locale not in available' do
      Lux.current.locale = 'fr'
      expect { Lux.locale.current }.to raise_error(Lux::Locale::Unknown)
    end
  end

  describe '#t' do
    it 'looks up dotted keys in the YAML file' do
      expect(Lux.locale.t('users.profile.title')).to eq('Profile')
    end

    it 'interpolates %{vars}' do
      expect(Lux.locale.t('users.welcome', name: 'Joe')).to eq('Hi Joe')
    end

    it 'honors an explicit locale: override' do
      expect(Lux.locale.t('users.welcome', name: 'Joe', locale: :de)).to eq('Hallo Joe')
    end

    it 'falls back to the default locale when key missing in requested' do
      Lux.current.locale = 'de'
      expect(Lux.locale.t('users.profile.title')).to eq('Profile')
    end

    it 'uses the fallback: arg when nothing matches' do
      expect(Lux.locale.t('users.missing', fallback: 'X')).to eq('X')
    end

    it 'returns [key] when fully missing' do
      expect(Lux.locale.t('users.unknown')).to eq('[users.unknown]')
    end

    it 'requires a namespace' do
      expect { Lux.locale.t('hi') }.to raise_error(ArgumentError, /namespaced/)
    end
  end

  describe '#namespace' do
    it 'wins over the YAML file when handler returns non-nil' do
      Lux.locale.namespace(:users) { |sub, _lc| sub == 'profile.title' ? 'Dynamic' : nil }
      expect(Lux.locale.t('users.profile.title')).to eq('Dynamic')
    end

    it 'falls through to YAML when handler returns nil' do
      Lux.locale.namespace(:users) { |_sub, _lc| nil }
      expect(Lux.locale.t('users.welcome', name: 'Joe')).to eq('Hi Joe')
    end

    it 'receives subkey and locale' do
      seen = []
      Lux.locale.namespace(:users) { |sub, lc| seen << [sub, lc]; nil }
      Lux.locale.t('users.welcome', name: 'Joe')
      expect(seen).to eq([['welcome', :en]])
    end
  end

  describe '#before_get' do
    it 'short-circuits the lookup when it returns non-nil' do
      Lux.locale.before_get { |_lc, _key| 'Hijacked' }
      expect(Lux.locale.t('users.welcome', name: 'Joe')).to eq('Hijacked')
    end

    it 'falls through when nil' do
      Lux.locale.before_get { |_lc, _key| nil }
      expect(Lux.locale.t('users.welcome', name: 'Joe')).to eq('Hi Joe')
    end
  end

  describe '#set' do
    it 'writes a new key to the text file' do
      Lux.locale.set('users.farewell', 'Bye', locale: :en)
      expect(Lux.locale.t('users.farewell')).to eq('Bye')

      raw = tmp.join('users.en.txt').read
      expect(raw).to include('farewell: Bye')
    end

    it 'creates the file when missing' do
      Lux.locale.set('cart.empty', 'Empty', locale: :en)
      expect(tmp.join('cart.en.txt')).to exist
      expect(Lux.locale.t('cart.empty')).to eq('Empty')
    end

    it 'sorts keys alphabetically on save' do
      Lux.locale.set('users.zeta',  'Z', locale: :en)
      Lux.locale.set('users.alpha', 'A', locale: :en)
      lines = tmp.join('users.en.txt').read.lines.map(&:chomp).reject(&:empty?)
      expect(lines).to eq(lines.sort)
    end

    it 'invalidates the in-process cache' do
      Lux.locale.t('users.welcome', name: 'Joe')  # warm cache
      Lux.locale.set('users.welcome', 'Hey %{name}', locale: :en)
      expect(Lux.locale.t('users.welcome', name: 'Joe')).to eq('Hey Joe')
    end

    it 'runs before_set and stores its return value when non-nil' do
      Lux.locale.before_set { |_lc, _key, v| v.to_s.strip }
      Lux.locale.set('users.foo', "  trimmed  ", locale: :en)
      expect(Lux.locale.t('users.foo')).to eq('trimmed')
    end

    it 'leaves value untouched when before_set returns nil' do
      Lux.locale.before_set { |_lc, _key, _v| nil }
      Lux.locale.set('users.foo', 'raw', locale: :en)
      expect(Lux.locale.t('users.foo')).to eq('raw')
    end
  end

  describe '#reload!' do
    it 'forces a re-read of files' do
      Lux.locale.t('users.welcome', name: 'Joe')          # warm
      File.write tmp.join('users.en.txt'), "welcome: Yo %{name}\n"
      Lux.locale.reload!
      expect(Lux.locale.t('users.welcome', name: 'Joe')).to eq('Yo Joe')
    end
  end

  describe '#store' do
    # Minimal duck for Lux::Locale.store: responds to .get and .set
    let(:store) do
      Class.new do
        def initialize; @rows = {}; end
        def get(lc, ns, sub);        @rows[[lc, ns, sub]]; end
        def set(lc, ns, sub, value); @rows[[lc, ns, sub]] = value.to_s; end
      end.new
    end

    before { Lux.locale.store = store }

    it 'reads from store before falling back to file' do
      store.set(:en, :users, 'welcome', 'From DB %{name}')
      expect(Lux.locale.t('users.welcome', name: 'Joe')).to eq('From DB Joe')
    end

    it 'falls through to file when store returns nil' do
      expect(Lux.locale.t('users.welcome', name: 'Joe')).to eq('Hi Joe')
    end

    it 'writes through store instead of file' do
      Lux.locale.set('users.farewell', 'Bye', locale: :en)
      expect(store.get(:en, :users, 'farewell')).to eq('Bye')
      expect(tmp.join('users.en.txt').read).not_to include('farewell:')
    end
  end
end
